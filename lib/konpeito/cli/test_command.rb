# frozen_string_literal: true

module Konpeito
  module Commands
    # Test command - run tests with Minitest
    class TestCommand < BaseCommand
      def self.command_name
        "test"
      end

      def self.description
        "Run tests (Minitest integration)"
      end

      def run
        parse_options!

        test_files = find_test_files

        if test_files.empty?
          puts "No test files found matching pattern: #{options[:pattern]}"
          return
        end

        target = options[:target] || config.target

        if target == :jvm
          run_jvm_tests(test_files)
        else
          if options[:compile_first]
            compile_source_files
          end
          run_tests(test_files)
        end
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          pattern: config.test_pattern,
          compile_first: false,
          name_pattern: nil,
          target: nil,
          classpath: nil
        }
      end

      def setup_option_parser(opts)
        opts.on("-p", "--pattern PATTERN", "Test file pattern (default: test/**/*_test.rb)") do |pattern|
          options[:pattern] = pattern
        end

        opts.on("-n", "--name PATTERN", "Run tests matching name pattern") do |pattern|
          options[:name_pattern] = pattern
        end

        opts.on("--compile", "Compile source files before running tests") do
          options[:compile_first] = true
        end

        opts.on("--target TARGET", %i[native jvm], "Target platform (native, jvm)") do |target|
          options[:target] = target
        end

        opts.on("--classpath PATH", "Add external JARs/directories to classpath (JVM only)") do |path|
          options[:classpath] = path
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito test [options] [test_files...]

          Examples:
            konpeito test                              Run all tests
            konpeito test test/main_test.rb            Run specific test file
            konpeito test -n test_hello                Run matching test name
            konpeito test --target jvm                 Run JVM tests
        BANNER
      end

      private

      def find_test_files
        if args.empty?
          Dir.glob(options[:pattern])
        else
          args.select { |f| File.exist?(f) }
        end
      end

      def compile_source_files
        puts_verbose "Compiling source files..."

        src_files = Dir.glob("src/**/*.rb")
        src_files.each do |source_file|
          puts_verbose "  Compiling #{source_file}..."
          begin
            output_file = default_output_name(source_file)
            compiler = Compiler.new(
              source_file: source_file,
              output_file: output_file,
              format: :cruby_ext,
              verbose: options[:verbose],
              rbs_paths: config.rbs_paths,
              require_paths: config.require_paths
            )
            compiler.compile
          rescue Konpeito::Error => e
            $stderr.puts "Warning: Failed to compile #{source_file}: #{e.message}"
          end
        end
      end

      def run_jvm_tests(test_files)
        require "tmpdir"
        require "fileutils"

        passed = 0
        failed = 0
        errors = 0

        # Build classpath
        classpath_parts = []
        cp = options[:classpath] || config.jvm_classpath
        classpath_parts << cp unless cp.empty?
        lib_jars = Dir.glob("lib/*.jar")
        classpath_parts << lib_jars.join(Platform.classpath_separator) unless lib_jars.empty?
        classpath = classpath_parts.reject(&:empty?).join(Platform.classpath_separator)

        puts "Running #{test_files.size} JVM test file(s)..."
        puts ""

        test_files.each do |test_file|
          puts_verbose "Compiling #{test_file}..."

          Dir.mktmpdir("konpeito-test") do |tmpdir|
            jar_path = File.join(tmpdir, "test.jar")

            begin
              # Compile to JAR
              build_args = ["--target", "jvm", "-o", jar_path]
              build_args += ["--classpath", classpath] unless classpath.empty?
              config.rbs_paths.each { |p| build_args << "--rbs" << p }
              build_args << test_file

              Commands::BuildCommand.new(build_args, config: config).run

              # Run the JAR
              java_cmd = find_java
              run_cmd = if classpath.empty?
                [java_cmd, "-jar", jar_path]
              else
                main_class = File.basename(test_file, ".rb").split("_").map(&:capitalize).join
                cp = "#{jar_path}#{Platform.classpath_separator}#{classpath}"
                [java_cmd, "-cp", cp, main_class]
              end

              output = `#{run_cmd.map { |s| s.include?(" ") ? "\"#{s}\"" : s }.join(" ")} 2>&1`

              # Parse PASS:/FAIL: from output
              output.each_line do |line|
                line = line.strip
                if line.start_with?("PASS:")
                  passed += 1
                  puts "  \e[32m#{line}\e[0m" if options[:color]
                  puts "  #{line}" unless options[:color]
                elsif line.start_with?("FAIL:")
                  failed += 1
                  puts "  \e[31m#{line}\e[0m" if options[:color]
                  puts "  #{line}" unless options[:color]
                end
              end
            rescue => e
              errors += 1
              $stderr.puts "  ERROR: #{test_file}: #{e.message}"
            end
          end
        end

        # Summary
        puts ""
        total = passed + failed
        summary = "#{total} assertions, #{passed} passed, #{failed} failed"
        summary += ", #{errors} errors" if errors > 0

        if failed > 0 || errors > 0
          puts options[:color] ? "\e[31m#{summary}\e[0m" : summary
          exit 1
        else
          puts options[:color] ? "\e[32m#{summary}\e[0m" : summary
        end
      end

      def find_java
        java_home = config.jvm_java_home
        java_home = ENV["JAVA_HOME"] || Platform.default_java_home if java_home.empty?
        java_path = File.join(java_home, "bin", "java")
        return java_path if File.exist?(java_path)

        java_in_path = Platform.find_executable("java")
        return java_in_path if java_in_path

        error("Java not found. Install Java 21+: #{Platform.java_install_hint}")
      end

      def run_tests(test_files)
        puts_verbose "Running #{test_files.size} test file(s)..."

        # Build minitest command
        cmd = ["ruby"]

        # Add load paths
        cmd << "-I" << "lib"
        cmd << "-I" << "test"
        cmd << "-I" << "src" if Dir.exist?("src")

        # Require minitest
        cmd << "-rminitest/autorun"

        # Add name filter if specified
        if options[:name_pattern]
          cmd << "-e" << "Minitest.run_with_autorun([])"
          cmd << "--" << "--name" << "/#{options[:name_pattern]}/"
        end

        # Add test files
        test_files.each { |f| cmd << "-r" << "./#{f}" }

        # Add final execution trigger if no name pattern
        unless options[:name_pattern]
          cmd << "-e" << ""
        end

        puts_verbose "Running: #{cmd.join(' ')}"

        # Execute tests
        success = system(*cmd)
        exit(success ? 0 : 1)
      end
    end
  end
end
