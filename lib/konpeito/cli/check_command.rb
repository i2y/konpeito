# frozen_string_literal: true

module Konpeito
  module Commands
    # Check command - type check only (no code generation)
    class CheckCommand < BaseCommand
      def self.command_name
        "check"
      end

      def self.description
        "Type check Ruby source (no code generation)"
      end

      def run
        parse_options!

        if args.empty?
          error("No source file specified. Usage: konpeito check <source.rb>")
        end

        source_file = args.first

        unless File.exist?(source_file)
          error("File not found: #{source_file}")
        end

        type_check(source_file)
      end

      protected

      def default_options
        {
          verbose: false,
          rbs_paths: config.rbs_paths.dup,
          require_paths: config.require_paths.dup,
          color: $stderr.tty?
        }
      end

      def setup_option_parser(opts)
        opts.on("-I", "--require-path PATH", "Add require search path (can be used multiple times)") do |path|
          options[:require_paths] << path
        end

        opts.on("--rbs FILE", "RBS type definition file (can be used multiple times)") do |file|
          options[:rbs_paths] << file
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito check [options] <source.rb>

          Examples:
            konpeito check src/main.rb                 Type check source file
            konpeito check --rbs sig/types.rbs src/main.rb  With explicit RBS
        BANNER
      end

      private

      def type_check(source_file)
        emit("Checking", source_file)

        compiler = Compiler.new(
          source_file: source_file,
          output_file: nil,
          format: :cruby_ext,
          verbose: options[:verbose],
          rbs_paths: options[:rbs_paths],
          require_paths: options[:require_paths]
        )

        compiler.type_check
        display_diagnostics(compiler.diagnostics)

        if compiler.diagnostics.any?(&:error?)
          error_count = compiler.diagnostics.count(&:error?)
          emit_error("Failed", "with #{error_count} error(s)")
          exit 1
        end

        stats = compiler.compile_stats
        if stats
          duration_str = "%.2fs" % stats.duration_s
          emit("Finished", "type check in #{duration_str} (no errors)")
        end
      rescue Konpeito::DependencyError => e
        display_dependency_error(e)
        exit 1
      rescue Konpeito::ParseError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      rescue Konpeito::Error => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end
  end
end
