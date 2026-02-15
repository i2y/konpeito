# frozen_string_literal: true

module Konpeito
  module Diagnostics
    # Renders diagnostics in Rust/Elm style with optional color support
    class DiagnosticRenderer
      COLORS = {
        error: "\e[1;31m",      # Bold red
        warning: "\e[1;33m",    # Bold yellow
        note: "\e[1;36m",       # Bold cyan
        help: "\e[1;32m",       # Bold green
        bold: "\e[1m",          # Bold
        blue: "\e[1;34m",       # Bold blue
        reset: "\e[0m"          # Reset
      }.freeze

      def initialize(color: true, io: $stderr)
        @color = color
        @io = io
      end

      def render(diagnostic)
        output = []
        output << render_header(diagnostic)
        output << render_location(diagnostic) if diagnostic.span
        output << render_source(diagnostic) if diagnostic.span
        output << render_labels(diagnostic) if diagnostic.labels.any?
        output << render_notes(diagnostic) if diagnostic.notes.any?
        output << render_suggestions(diagnostic) if diagnostic.suggestions.any?
        output << ""

        @io.puts output.join("\n")
      end

      def render_all(diagnostics)
        diagnostics.each { |d| render(d) }
        render_summary(diagnostics) if diagnostics.size > 1
      end

      private

      def render_header(diagnostic)
        severity_str = colorize(diagnostic.severity.to_s, diagnostic.severity)
        code_str = colorize("[#{diagnostic.code}]", diagnostic.severity)
        message_str = colorize(diagnostic.message, :bold)
        "#{severity_str}#{code_str}: #{message_str}"
      end

      def render_location(diagnostic)
        span = diagnostic.span
        arrow = colorize("-->", :blue)
        "   #{arrow} #{span}"
      end

      def render_source(diagnostic)
        snippet = diagnostic.span.snippet(context_lines: 1)
        return "" unless snippet

        lines = []
        gutter_width = snippet.map { |l| l[:line_num] }.max.to_s.length

        # Blank line before source
        lines << "#{' ' * gutter_width} #{colorize('|', :blue)}"

        snippet.each do |line_info|
          gutter = line_info[:line_num].to_s.rjust(gutter_width)
          pipe = colorize("|", :blue)

          if line_info[:highlight]
            lines << "#{colorize(gutter, :blue)} #{pipe} #{line_info[:content].chomp}"

            # Add underline for highlighted lines
            underline = render_underline(diagnostic, line_info)
            lines << "#{' ' * gutter_width} #{pipe} #{underline}" if underline
          else
            lines << "#{colorize(gutter, :blue)} #{pipe} #{line_info[:content].chomp}"
          end
        end

        lines.join("\n")
      end

      def render_underline(diagnostic, line_info)
        span = diagnostic.span
        return nil unless line_info[:line_num] >= span.start_line &&
                          line_info[:line_num] <= span.end_line

        line_content = line_info[:content]
        start_col = line_info[:line_num] == span.start_line ? span.start_column : 0
        end_col = line_info[:line_num] == span.end_line ? span.end_column : line_content.length

        # Ensure we have at least one caret
        end_col = [end_col, start_col + 1].max

        underline = " " * start_col + "^" * (end_col - start_col)

        # Add primary label message if any
        primary_label = diagnostic.labels.find { |l| l.style == :primary }
        if primary_label
          underline += " #{primary_label.message}"
        end

        colorize(underline, diagnostic.severity)
      end

      def render_labels(_diagnostic)
        # Additional labels are rendered in source context
        # For now, this is a placeholder for future multi-span support
        ""
      end

      def render_notes(diagnostic)
        diagnostic.notes.map do |note|
          "   #{colorize("=", :blue)} #{colorize("note:", :note)} #{note}"
        end.join("\n")
      end

      def render_suggestions(diagnostic)
        diagnostic.suggestions.map do |suggestion|
          "   #{colorize("=", :blue)} #{colorize("help:", :help)} #{suggestion}"
        end.join("\n")
      end

      def render_summary(diagnostics)
        error_count = diagnostics.count(&:error?)
        warning_count = diagnostics.count(&:warning?)

        parts = []
        parts << colorize("#{error_count} error(s)", :error) if error_count > 0
        parts << colorize("#{warning_count} warning(s)", :warning) if warning_count > 0

        @io.puts parts.join(", ") + " generated"
      end

      def colorize(text, color)
        return text unless @color

        color_code = COLORS[color] || ""
        reset_code = COLORS[:reset]
        "#{color_code}#{text}#{reset_code}"
      end
    end
  end
end
