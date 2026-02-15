# frozen_string_literal: true

require "optparse"
require_relative "cli/config"
require_relative "cli/base_command"
require_relative "cli/build_command"
require_relative "cli/check_command"
require_relative "cli/lsp_command"
require_relative "cli/init_command"
require_relative "cli/fmt_command"
require_relative "cli/test_command"
require_relative "cli/watch_command"
require_relative "cli/run_command"
require_relative "cli/deps_command"
require_relative "cli/doctor_command"

module Konpeito
  # Main CLI router - dispatches to subcommands
  class CLI
    COMMANDS = {
      "build" => Commands::BuildCommand,
      "run" => Commands::RunCommand,
      "check" => Commands::CheckCommand,
      "lsp" => Commands::LspCommand,
      "init" => Commands::InitCommand,
      "fmt" => Commands::FmtCommand,
      "test" => Commands::TestCommand,
      "watch" => Commands::WatchCommand,
      "deps" => Commands::DepsCommand,
      "doctor" => Commands::DoctorCommand
    }.freeze

    attr_reader :args

    def initialize(args)
      @args = args.dup
    end

    def run
      # Handle global options first
      if args.empty? || args.first == "-h" || args.first == "--help"
        show_help
        exit(args.empty? ? 1 : 0)
      end

      if args.first == "--version" || args.first == "-V"
        show_version
        exit 0
      end

      # Determine command
      command_name = args.first

      if COMMANDS.key?(command_name)
        # Explicit subcommand
        args.shift
        run_command(command_name, args)
      elsif command_name.start_with?("-") || File.exist?(command_name)
        # Legacy mode: implicit build command for backwards compatibility
        # Either starts with option flag or is an existing file
        run_legacy_mode
      else
        # Unknown command
        $stderr.puts "Unknown command: #{command_name}"
        $stderr.puts "Run 'konpeito --help' for usage information."
        exit 1
      end
    end

    private

    def run_command(command_name, command_args)
      command_class = COMMANDS[command_name]
      config = Commands::Config.new
      command = command_class.new(command_args, config: config)
      command.run
    end

    def run_legacy_mode
      # Parse legacy options and delegate to appropriate command
      legacy = LegacyCLI.new(args)
      legacy.run
    end

    def show_help
      puts "Konpeito - Ruby AOT Native Compiler"
      puts ""
      puts "Usage: konpeito <command> [options] [args]"
      puts "       konpeito [options] <source.rb>  (legacy build mode)"
      puts ""
      puts "Commands:"
      COMMANDS.each do |name, klass|
        puts "  %-10s %s" % [name, klass.description]
      end
      puts ""
      puts "Global Options:"
      puts "  -h, --help       Show this help"
      puts "  -V, --version    Show version and environment info"
      puts ""
      puts "Examples:"
      puts "  konpeito build src/main.rb            Compile to CRuby extension"
      puts "  konpeito build --target jvm src/app.rb Compile to JAR"
      puts "  konpeito run src/main.rb              Build and run"
      puts "  konpeito check src/main.rb            Type check only"
      puts "  konpeito test                         Run tests"
      puts "  konpeito fmt                          Format source files"
      puts "  konpeito doctor                       Check environment"
      puts ""
      puts "Legacy mode (backwards compatible):"
      puts "  konpeito source.rb                     Same as: konpeito build source.rb"
      puts "  konpeito -c source.rb                  Same as: konpeito check source.rb"
      puts ""
      puts "For help on a specific command, run: konpeito <command> --help"
    end

    def show_version
      puts "konpeito #{Konpeito::VERSION}"
      puts "ruby #{RUBY_VERSION} [#{RUBY_PLATFORM}]"

      # LLVM
      clang = Platform.find_llvm_tool("clang")
      if clang
        llvm_version = clang[/llvm[@-]?(\d+)/, 1]
        unless llvm_version
          # Try clang --version
          begin
            output = `"#{clang}" --version 2>&1`
            llvm_version = output[/(?:clang|LLVM)\s+version\s+(\d+)/, 1]
          rescue
          end
        end
        llvm_version ||= "?"
        llvm_dir = File.dirname(File.dirname(clang))
        puts "llvm #{llvm_version} (#{llvm_dir})"
      else
        puts "llvm not found"
      end

      # Java
      java_home = ENV["JAVA_HOME"] || Platform.default_java_home
      java_path = File.join(java_home, "bin", "java")
      java_path = Platform.find_executable("java") unless File.exist?(java_path)
      if java_path
        version = begin
          output = `"#{java_path}" -version 2>&1`
          output[/version "(\d+)/, 1] || "?"
        rescue
          "?"
        end
        java_dir = File.dirname(File.dirname(java_path))
        puts "java #{version} (#{java_dir})"
      else
        puts "java not found"
      end
    end
  end

  # Legacy CLI class for backwards compatibility
  # Supports old-style options like -c, -o, --lsp, etc.
  class LegacyCLI
    attr_reader :args, :options

    def initialize(args)
      @args = args.dup
      @options = {
        output: nil,
        format: :cruby_ext,
        verbose: false,
        type_check_only: false,
        rbs_paths: [],
        require_paths: [],
        color: $stderr.tty?,
        debug: false,
        lsp: false,
        profile: false,
        incremental: false,
        clean_cache: false
      }
    end

    def run
      parse_options!

      # Start LSP server if requested
      if options[:lsp]
        Commands::LspCommand.new([], config: Commands::Config.new).run
        return
      end

      if args.empty?
        puts "Usage: konpeito [options] <source.rb>"
        puts "Run 'konpeito --help' for more information."
        exit 1
      end

      source_file = args.first

      unless File.exist?(source_file)
        $stderr.puts "Error: File not found: #{source_file}"
        exit 1
      end

      if options[:type_check_only]
        # Delegate to check command
        check_args = []
        check_args << "-v" if options[:verbose]
        check_args << "--no-color" unless options[:color]
        options[:rbs_paths].each { |p| check_args << "--rbs" << p }
        options[:require_paths].each { |p| check_args << "-I" << p }
        check_args << source_file
        Commands::CheckCommand.new(check_args, config: Commands::Config.new).run
      else
        # Delegate to build command
        build_args = []
        build_args << "-o" << options[:output] if options[:output]
        build_args << "-f" << options[:format].to_s if options[:format] != :cruby_ext
        build_args << "-v" if options[:verbose]
        build_args << "-g" if options[:debug]
        build_args << "-p" if options[:profile]
        build_args << "--no-color" unless options[:color]
        build_args << "--incremental" if options[:incremental]
        build_args << "--clean-cache" if options[:clean_cache]
        options[:rbs_paths].each { |p| build_args << "--rbs" << p }
        options[:require_paths].each { |p| build_args << "-I" << p }
        build_args << source_file
        Commands::BuildCommand.new(build_args, config: Commands::Config.new).run
      end
    end

    private

    def parse_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: konpeito [options] <source.rb>"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-o", "--output FILE", "Output file name") do |file|
          options[:output] = file
        end

        opts.on("-f", "--format FORMAT", %i[cruby_ext standalone],
                "Output format (cruby_ext, standalone)") do |format|
          options[:format] = format
        end

        opts.on("-c", "--check", "Type check only (no code generation)") do
          options[:type_check_only] = true
        end

        opts.on("-g", "--debug", "Generate debug info (DWARF) for lldb/gdb") do
          options[:debug] = true
        end

        opts.on("-p", "--profile", "Enable profiling (function call counts and timing)") do
          options[:profile] = true
        end

        opts.on("-v", "--verbose", "Verbose output") do
          options[:verbose] = true
        end

        opts.on("-I", "--require-path PATH", "Add require search path (can be used multiple times)") do |path|
          options[:require_paths] << path
        end

        opts.on("--rbs FILE", "RBS type definition file (can be used multiple times)") do |file|
          options[:rbs_paths] << file
        end

        opts.on("--no-color", "Disable colored output") do
          options[:color] = false
        end

        opts.on("--lsp", "Start Language Server Protocol server") do
          options[:lsp] = true
        end

        opts.on("--incremental", "Enable incremental compilation (cache unchanged files)") do
          options[:incremental] = true
        end

        opts.on("--clean-cache", "Clear compilation cache before building") do
          options[:clean_cache] = true
        end

        opts.on("--version", "Show version") do
          puts "konpeito #{Konpeito::VERSION}"
          exit
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit
        end
      end

      parser.parse!(args)
    end
  end
end
