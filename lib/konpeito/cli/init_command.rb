# frozen_string_literal: true

require "fileutils"

module Konpeito
  module Commands
    # Init command - generates project structure
    class InitCommand < BaseCommand
      def self.command_name
        "init"
      end

      def self.description
        "Initialize a new Konpeito project"
      end

      def run
        parse_options!

        @project_name = args.first || File.basename(Dir.pwd)
        @project_dir = args.first ? File.expand_path(@project_name, Dir.pwd) : Dir.pwd

        if args.first && Dir.exist?(@project_dir)
          # Allow if directory is empty, otherwise error
          entries = Dir.entries(@project_dir) - %w[. ..]
          unless entries.empty?
            error("Directory '#{@project_name}' already exists and is not empty")
          end
        end

        create_project_structure
        puts "Project '#{@project_name}' initialized successfully!"
        puts ""
        puts "Next steps:"
        puts "  cd #{@project_name}" if args.first
        if options[:target] == :jvm
          puts "  konpeito run src/main.rb"
          puts "  konpeito test"
        else
          puts "  konpeito build src/main.rb"
          puts "  konpeito test"
        end
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          with_git: true,
          target: :native
        }
      end

      def setup_option_parser(opts)
        opts.on("--no-git", "Do not create .gitignore") do
          options[:with_git] = false
        end

        opts.on("--target TARGET", %i[native jvm], "Target platform (native, jvm)") do |target|
          options[:target] = target
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito init [options] [project_name]

          Examples:
            konpeito init my_project                   Create native project
            konpeito init --target jvm my_app          Create JVM project
            konpeito init                              Initialize current directory
        BANNER
      end

      private

      def create_project_structure
        # Create directories
        create_dir(@project_dir)
        create_dir(File.join(@project_dir, "src"))
        create_dir(File.join(@project_dir, "test"))

        if options[:target] == :jvm
          create_dir(File.join(@project_dir, "lib"))
          create_jvm_config_file
          create_jvm_main_rb
          create_jvm_main_test
        else
          create_dir(File.join(@project_dir, "sig"))
          create_config_file
          create_main_rb
          create_main_rbs
          create_main_test
        end

        create_gitignore if options[:with_git]
        puts_verbose "Created project structure in #{@project_dir}"
      end

      def create_dir(path)
        return if Dir.exist?(path)

        puts_verbose "Creating directory: #{path}"
        FileUtils.mkdir_p(path)
      end

      def create_config_file
        path = File.join(@project_dir, "konpeito.toml")
        content = <<~TOML
          # Konpeito project configuration
          name = "#{@project_name}"
          version = "0.1.0"

          [build]
          output = "#{@project_name}.bundle"
          format = "cruby_ext"
          rbs_paths = ["sig"]
          require_paths = ["src"]
          debug = false
          profile = false
          incremental = true

          [test]
          pattern = "test/**/*_test.rb"

          [fmt]
          indent = 2

          [watch]
          paths = ["src", "sig"]
          extensions = ["rb", "rbs"]
        TOML

        write_file(path, content)
      end

      def create_main_rb
        path = File.join(@project_dir, "src", "main.rb")
        content = <<~RUBY
          # frozen_string_literal: true

          # Main module for #{@project_name}
          module #{camelize(@project_name)}
            def self.hello(name)
              "Hello, " + name + "!"
            end
          end
        RUBY

        write_file(path, content)
      end

      def create_main_rbs
        path = File.join(@project_dir, "sig", "main.rbs")
        content = <<~RBS
          # Type definitions for #{@project_name}
          module #{camelize(@project_name)}
            def self.hello: (String name) -> String
          end
        RBS

        write_file(path, content)
      end

      def create_main_test
        path = File.join(@project_dir, "test", "main_test.rb")
        content = <<~RUBY
          # frozen_string_literal: true

          require "minitest/autorun"

          class #{camelize(@project_name)}Test < Minitest::Test
            def setup
              # Load the compiled extension
              # require_relative "../#{@project_name}"
            end

            def test_hello
              # result = #{camelize(@project_name)}.hello("World")
              # assert_equal "Hello, World!", result
              skip "Compile with 'konpeito build src/main.rb' first"
            end
          end
        RUBY

        write_file(path, content)
      end

      def create_gitignore
        path = File.join(@project_dir, ".gitignore")
        lines = []
        lines << "# Compiled extensions"
        lines << "*.bundle"
        lines << "*.so"
        lines << "*.dll"
        lines << "*.o"
        lines << "*.dSYM/"

        if options[:target] == :jvm
          lines << ""
          lines << "# JVM artifacts"
          lines << "*.jar"
          lines << "*.class"
          lines << "lib/"
        end

        lines << ""
        lines << "# Konpeito cache"
        lines << ".konpeito_cache/"
        lines << ""
        lines << "# Profile output"
        lines << "*_profile.json"
        lines << "*.folded"
        lines << ""
        lines << "# Ruby"
        lines << "*.gem"
        lines << ".bundle/"
        lines << "vendor/bundle/"
        lines << ""
        lines << "# IDE"
        lines << ".idea/"
        lines << ".vscode/"
        lines << "*.swp"
        lines << "*.swo"
        lines << "*~"
        lines << ""
        lines << "# macOS"
        lines << ".DS_Store"
        lines << ""

        write_file(path, lines.join("\n"))
      end

      def create_jvm_config_file
        path = File.join(@project_dir, "konpeito.toml")
        content = <<~TOML
          # Konpeito JVM project configuration
          name = "#{@project_name}"
          version = "0.1.0"

          [build]
          target = "jvm"
          output = "#{@project_name}.jar"
          rbs_paths = []
          require_paths = ["src"]

          [jvm]
          classpath = ""
          java_home = ""
          library = false

          [deps]
          jars = []

          [test]
          pattern = "test/**/*_test.rb"
        TOML

        write_file(path, content)
      end

      def create_jvm_main_rb
        path = File.join(@project_dir, "src", "main.rb")
        content = <<~RUBY
          # Main entry point for #{@project_name}
          def greet(name)
            "Hello, " + name + "!"
          end

          puts greet("World")
        RUBY

        write_file(path, content)
      end

      def create_jvm_main_test
        path = File.join(@project_dir, "test", "main_test.rb")
        content = <<~RUBY
          # Test for #{@project_name}
          # Konpeito JVM tests use PASS:/FAIL: convention

          def add(a, b)
            a + b
          end

          result = add(2, 3)
          if result == 5
            puts "PASS: add returns correct sum"
          else
            puts "FAIL: add expected 5"
          end
        RUBY

        write_file(path, content)
      end

      def write_file(path, content)
        puts_verbose "Creating file: #{path}"
        File.write(path, content)
      end

      def camelize(str)
        str.gsub(/[-_](\w)/) { ::Regexp.last_match(1).upcase }
           .sub(/^\w/) { ::Regexp.last_match(0).upcase }
      end
    end
  end
end
