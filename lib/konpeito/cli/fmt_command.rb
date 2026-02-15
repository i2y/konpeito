# frozen_string_literal: true

require_relative "../formatter/formatter"

module Konpeito
  module Commands
    # Fmt command - format Ruby source files with built-in Prism-based formatter
    class FmtCommand < BaseCommand
      def self.command_name
        "fmt"
      end

      def self.description
        "Format Ruby source files"
      end

      def run
        parse_options!

        @files = args.empty? ? find_ruby_files : args

        if @files.empty?
          $stderr.puts "No Ruby files found to format."
          return
        end

        emit("Formatting", "#{@files.size} file(s)...") unless options[:quiet]

        changed = 0
        unchanged = 0
        errored = 0

        @files.each do |file|
          result = format_file(file)
          case result
          when :changed
            changed += 1
          when :unchanged
            unchanged += 1
          when :error
            errored += 1
          end
        end

        unless options[:quiet]
          parts = []
          parts << "#{changed} changed" if changed > 0
          parts << "#{unchanged} unchanged" if unchanged > 0
          parts << "#{errored} error(s)" if errored > 0
          emit("Finished", parts.join(", "))
        end

        if options[:check] && changed > 0
          exit 1
        end

        exit 1 if errored > 0
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          check: false,
          diff: false,
          quiet: false,
          exclude: []
        }
      end

      def setup_option_parser(opts)
        opts.on("--check", "Check formatting without modifying files") do
          options[:check] = true
        end

        opts.on("--diff", "Show what would change (unified diff)") do
          options[:diff] = true
          options[:check] = true  # diff implies check
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
            konpeito fmt --diff                        Show what would change
        BANNER
      end

      private

      def find_ruby_files
        default_exclude = ["vendor/", ".bundle/", ".konpeito_cache/", "tools/"]
        all_exclude = default_exclude + options[:exclude]

        Dir.glob("**/*.rb").reject do |f|
          all_exclude.any? { |pat| f.start_with?(pat) || File.fnmatch?(pat, f) }
        end
      end

      def format_file(file)
        unless File.exist?(file)
          $stderr.puts "Warning: #{file} not found, skipping"
          return :error
        end

        source = File.read(file)
        formatter = Formatter::Formatter.new(source, filepath: file)
        formatted = formatter.format

        if source == formatted
          return :unchanged
        end

        if options[:diff]
          show_diff(file, source, formatted)
          emit("Formatted", file) unless options[:quiet]
          return :changed
        end

        if options[:check]
          emit_warn("Unformatted", file) unless options[:quiet]
          return :changed
        end

        # Write formatted content
        File.write(file, formatted)
        emit("Formatted", file) unless options[:quiet]
        :changed
      rescue => e
        $stderr.puts "Error formatting #{file}: #{e.message}"
        :error
      end

      def show_diff(file, original, formatted)
        orig_lines = original.lines
        fmt_lines = formatted.lines

        # Simple unified diff
        $stdout.puts "--- #{file}"
        $stdout.puts "+++ #{file} (formatted)"

        # Find differing regions
        max_len = [orig_lines.size, fmt_lines.size].max
        i = 0
        while i < max_len
          if orig_lines[i] != fmt_lines[i]
            # Find the end of this diff hunk
            hunk_start = i
            while i < max_len && orig_lines[i] != fmt_lines[i]
              i += 1
            end
            hunk_end = i

            # Context
            ctx_start = [hunk_start - 3, 0].max
            ctx_end = [hunk_end + 3, max_len].min

            $stdout.puts "@@ -#{ctx_start + 1},#{hunk_end - ctx_start} +#{ctx_start + 1},#{hunk_end - ctx_start} @@"

            (ctx_start...ctx_end).each do |j|
              if j >= hunk_start && j < hunk_end
                if j < orig_lines.size && orig_lines[j]
                  line = orig_lines[j].chomp
                  $stdout.puts options[:color] ? "\e[31m-#{line}\e[0m" : "-#{line}"
                end
                if j < fmt_lines.size && fmt_lines[j]
                  line = fmt_lines[j].chomp
                  $stdout.puts options[:color] ? "\e[32m+#{line}\e[0m" : "+#{line}"
                end
              else
                line = (orig_lines[j] || fmt_lines[j] || "").chomp
                $stdout.puts " #{line}"
              end
            end
          else
            i += 1
          end
        end
      end
    end
  end
end
