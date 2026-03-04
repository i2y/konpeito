# frozen_string_literal: true

module Konpeito
  module Commands
    # Run command - build and execute in one step
    class RunCommand < BaseCommand
      def self.command_name
        "run"
      end

      def self.description
        "Build and run a Konpeito program"
      end

      def run
        parse_options!

        source_file = args.first
        unless source_file
          # Try to find default source from config or convention
          source_file = find_default_source
          unless source_file
            error("No source file specified. Usage: konpeito run [options] <source.rb>")
          end
        end

        unless File.exist?(source_file)
          error("File not found: #{source_file}")
        end

        target = options[:target] || config.target

        case target
        when :jvm
          run_jvm(source_file)
        else
          run_native(source_file)
        end
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          target: nil,
          classpath: nil,
          rbs_paths: config.rbs_paths.dup,
          require_paths: config.require_paths.dup,
          inline_rbs: false,
          lib: false
        }
      end

      def setup_option_parser(opts)
        opts.on("--target TARGET", %i[native jvm], "Target platform (native, jvm)") do |target|
          options[:target] = target
        end

        opts.on("--classpath PATH", "Add external JARs/directories to classpath (colon-separated)") do |path|
          options[:classpath] = path
        end

        opts.on("--rbs FILE", "RBS type definition file (can be used multiple times)") do |file|
          options[:rbs_paths] << file
        end

        opts.on("-I", "--require-path PATH", "Add require search path") do |path|
          options[:require_paths] << path
        end

        opts.on("--inline", "Use inline RBS annotations (# @rbs, #:) from Ruby source") do
          options[:inline_rbs] = true
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito run [options] [source.rb]

          Examples:
            konpeito run src/main.rb                   Build and run (native)
            konpeito run --inline src/main.rb          Build and run with inline RBS
            konpeito run --target jvm src/main.rb      Build and run (JVM)
        BANNER
      end

      private

      def find_default_source
        # Check common source locations
        candidates = ["src/main.rb", "main.rb", "app.rb"]
        candidates.find { |f| File.exist?(f) }
      end

      def run_jvm(source_file)
        # Build classpath from config + options + lib/*.jar
        classpath = build_classpath

        # Build args for build command
        build_args = build_jvm_args(source_file, classpath)
        build_args << "--run"

        Commands::BuildCommand.new(build_args, config: config).run
      end

      def run_native(source_file)
        require "tmpdir"

        # Use a subdirectory to avoid conflicts, but keep the basename matching
        # the Init_ function name (Ruby requires Init_<basename> to match the filename)
        @run_tmpdir = File.join(Dir.tmpdir, "konpeito_run_#{Process.pid}")
        FileUtils.mkdir_p(@run_tmpdir)
        output_file = File.join(@run_tmpdir, "#{File.basename(source_file, '.rb')}#{Platform.shared_lib_extension}")

        build_args = ["-o", output_file]
        build_args << "-v" if options[:verbose]
        build_args << "--no-color" unless options[:color]
        build_args << "--inline" if options[:inline_rbs]
        options[:rbs_paths].each { |p| build_args << "--rbs" << p }
        options[:require_paths].each { |p| build_args << "-I" << p }
        build_args << source_file

        Commands::BuildCommand.new(build_args, config: config).run

        emit("Running", output_file)
        # Run without Bundler environment so the compiled extension can load
        # any installed gem (not just those in the current Gemfile)
        run_without_bundler("ruby", "-r", output_file, "-e", "")
      ensure
        FileUtils.rm_rf(@run_tmpdir) if @run_tmpdir && Dir.exist?(@run_tmpdir)
      end

      def build_classpath
        parts = []

        # From config
        cp = options[:classpath] || config.jvm_classpath
        parts << cp unless cp.empty?

        # From lib/*.jar (downloaded dependencies)
        lib_jars = Dir.glob("lib/*.jar")
        parts << lib_jars.join(Platform.classpath_separator) unless lib_jars.empty?

        parts.reject(&:empty?).join(Platform.classpath_separator)
      end

      # Run a command without Bundler's environment restrictions.
      # When konpeito is invoked via `bundle exec`, child processes inherit
      # BUNDLE_GEMFILE/RUBYOPT which restrict gem access. The compiled extension
      # may require gems not in the current Gemfile.
      def run_without_bundler(*cmd)
        if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
          Bundler.with_unbundled_env { system(*cmd) }
        else
          system(*cmd)
        end
      end

      def build_jvm_args(source_file, classpath)
        build_args = ["--target", "jvm"]
        build_args << "-v" if options[:verbose]
        build_args << "--no-color" unless options[:color]
        build_args << "--inline" if options[:inline_rbs]
        build_args += ["--classpath", classpath] unless classpath.empty?
        options[:rbs_paths].each { |p| build_args << "--rbs" << p }
        options[:require_paths].each { |p| build_args << "-I" << p }
        build_args << source_file
        build_args
      end
    end
  end
end
