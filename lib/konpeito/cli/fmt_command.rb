# frozen_string_literal: true

module Konpeito
  module Commands
    # Fmt command - format Ruby source files via RuboCop
    class FmtCommand < BaseCommand
      def self.command_name
        "fmt"
      end

      def self.description
        "Format Ruby source files (via RuboCop)"
      end

      def run
        parse_options!

        rubocop_args = build_rubocop_args
        success = system("bundle", "exec", "rubocop", *rubocop_args)
        exit 1 unless success
      end

      # Visible for testing
      def build_rubocop_args
        rubocop_args = []

        if options[:check]
          # Check mode: report violations without modifying files
        else
          # Default: auto-correct
          rubocop_args << "-A"
        end

        rubocop_args << "--format" << "quiet" if options[:quiet]
        rubocop_args << "--no-color" unless options[:color]

        options[:exclude].each do |pattern|
          rubocop_args << "--exclude" << pattern
        end

        rubocop_args.concat(args) unless args.empty?

        rubocop_args
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          check: false,
          quiet: false,
          exclude: []
        }
      end

      def setup_option_parser(opts)
        opts.on("--check", "Check formatting without modifying files") do
          options[:check] = true
        end

        opts.on("--diff", "Check formatting without modifying files (alias for --check)") do
          options[:check] = true
        end

        opts.on("-q", "--quiet", "Suppress non-error output") do
          options[:quiet] = true
        end

        opts.on("--exclude PATTERN", "Exclude files matching pattern") do |pattern|
          options[:exclude] << pattern
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito fmt [options] [files...]

          Examples:
            konpeito fmt                               Format all Ruby files
            konpeito fmt src/main.rb                   Format specific file
            konpeito fmt --check                       Check without modifying
            konpeito fmt --diff                        Check without modifying (alias)
        BANNER
      end
    end
  end
end
