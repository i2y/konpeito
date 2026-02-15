# frozen_string_literal: true

require "optparse"

module Konpeito
  module Commands
    # Base class for all CLI commands
    class BaseCommand
      attr_reader :args, :options, :config

      def initialize(args, config: nil)
        @args = args.dup
        @config = config || Config.new
        @options = default_options
      end

      # Override in subclasses
      def run
        raise NotImplementedError, "Subclasses must implement #run"
      end

      # Override in subclasses to provide command name
      def self.command_name
        raise NotImplementedError, "Subclasses must implement .command_name"
      end

      # Override in subclasses to provide command description
      def self.description
        raise NotImplementedError, "Subclasses must implement .description"
      end

      protected

      # Override in subclasses
      def default_options
        {
          verbose: false,
          color: $stderr.tty?
        }
      end

      # Override in subclasses
      def setup_option_parser(opts)
        opts.on("-v", "--verbose", "Verbose output") do
          options[:verbose] = true
        end

        opts.on("--no-color", "Disable colored output") do
          options[:color] = false
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit
        end
      end

      def parse_options!
        parser = OptionParser.new do |opts|
          opts.banner = banner
          opts.separator ""
          opts.separator "Options:"
          setup_option_parser(opts)
        end

        parser.parse!(args)
      end

      def banner
        "Usage: konpeito #{self.class.command_name} [options]"
      end

      def puts_verbose(message)
        puts message if options[:verbose]
      end

      # Cargo-style structured output: right-aligned tag + message
      # Output goes to $stderr so stdout remains clean for program output
      def emit(tag, message)
        if options[:color]
          $stderr.puts "  \e[1;32m%12s\e[0m %s" % [tag, message]
        else
          $stderr.puts "  %12s %s" % [tag, message]
        end
      end

      # Emit a warning line
      def emit_warn(tag, message)
        if options[:color]
          $stderr.puts "  \e[1;33m%12s\e[0m %s" % [tag, message]
        else
          $stderr.puts "  %12s %s" % [tag, message]
        end
      end

      # Emit an error line
      def emit_error(tag, message)
        if options[:color]
          $stderr.puts "  \e[1;31m%12s\e[0m %s" % [tag, message]
        else
          $stderr.puts "  %12s %s" % [tag, message]
        end
      end

      # Format a file size for display
      def format_size(bytes)
        if bytes >= 1024 * 1024
          "%.1f MB" % (bytes / (1024.0 * 1024))
        elsif bytes >= 1024
          "%d KB" % (bytes / 1024)
        else
          "%d B" % bytes
        end
      end

      def error(message)
        $stderr.puts "Error: #{message}"
        exit 1
      end

      def display_diagnostics(diagnostics)
        return if diagnostics.empty?

        renderer = Diagnostics::DiagnosticRenderer.new(
          color: options[:color],
          io: $stderr
        )
        renderer.render_all(diagnostics)
      end

      def display_dependency_error(error)
        renderer = Diagnostics::DiagnosticRenderer.new(
          color: options[:color],
          io: $stderr
        )

        if error.cycle
          span = if error.from_file
            Diagnostics::SourceSpan.new(
              file_path: error.from_file,
              start_line: 1,
              start_column: 0
            )
          end
          diagnostic = Diagnostics::Diagnostic.circular_dependency(
            cycle: error.cycle,
            span: span
          )
          renderer.render(diagnostic)
        elsif error.missing_file
          span = if error.from_file
            Diagnostics::SourceSpan.new(
              file_path: error.from_file,
              start_line: error.line || 1,
              start_column: 0,
              source: error.from_file && File.exist?(error.from_file) ? File.read(error.from_file) : nil
            )
          end
          diagnostic = Diagnostics::Diagnostic.file_not_found(
            path: error.missing_file,
            span: span
          )
          renderer.render(diagnostic)
        else
          $stderr.puts "Error: #{error.message}"
        end
      end

      def default_output_name(source_file, format: :cruby_ext, target: :native)
        base = File.basename(source_file, ".rb")

        if target == :jvm
          "#{base}.jar"
        else
          case format
          when :cruby_ext
            "#{base}#{Platform.shared_lib_extension}"
          when :standalone
            base
          else
            "#{base}#{Platform.shared_lib_extension}"
          end
        end
      end
    end
  end
end
