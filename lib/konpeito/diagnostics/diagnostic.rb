# frozen_string_literal: true

module Konpeito
  module Diagnostics
    # Represents a location in source code with ability to extract snippets
    class SourceSpan
      attr_reader :file_path, :start_line, :start_column, :end_line, :end_column

      def initialize(file_path:, start_line:, start_column:, end_line: nil, end_column: nil, source: nil)
        @file_path = file_path
        @start_line = start_line
        @start_column = start_column
        @end_line = end_line || start_line
        @end_column = end_column || start_column
        @source = source
      end

      # Create from a Prism node location
      def self.from_prism_location(location, file_path:, source: nil)
        new(
          file_path: file_path,
          start_line: location.start_line,
          start_column: location.start_column,
          end_line: location.end_line,
          end_column: location.end_column,
          source: source
        )
      end

      # Get source lines with optional context
      def snippet(context_lines: 2)
        return nil unless source_lines

        first_line = [@start_line - context_lines, 1].max
        last_line = [@end_line + context_lines, source_lines.size].min

        lines = []
        (first_line..last_line).each do |line_num|
          line_content = source_lines[line_num - 1] || ""
          lines << { line_num: line_num, content: line_content, highlight: line_in_span?(line_num) }
        end
        lines
      end

      # Get only the highlighted source text
      def highlighted_text
        return nil unless source_lines

        if @start_line == @end_line
          line = source_lines[@start_line - 1] || ""
          line[@start_column...@end_column] || line[@start_column..]
        else
          # Multi-line span
          lines = source_lines[(@start_line - 1)...@end_line]
          return nil unless lines

          result = []
          lines.each_with_index do |line, idx|
            if idx == 0
              result << line[@start_column..]
            elsif idx == lines.size - 1
              result << line[0...@end_column]
            else
              result << line
            end
          end
          result.join("\n")
        end
      end

      def to_s
        "#{@file_path}:#{@start_line}:#{@start_column}"
      end

      private

      def source_lines
        return @source_lines if defined?(@source_lines)

        @source_lines = if @source
          @source.lines
        elsif @file_path && File.exist?(@file_path)
          File.read(@file_path).lines
        end
      end

      def line_in_span?(line_num)
        line_num >= @start_line && line_num <= @end_line
      end
    end

    # Represents a diagnostic label (additional annotation on source)
    class Label
      attr_reader :span, :message, :style

      def initialize(span:, message:, style: :primary)
        @span = span
        @message = message
        @style = style  # :primary, :secondary
      end
    end

    # Represents a single diagnostic message (error, warning, or note)
    class Diagnostic
      SEVERITIES = { error: 0, warning: 1, note: 2, help: 3 }.freeze

      attr_reader :severity, :code, :message, :span, :labels, :notes, :suggestions

      def initialize(severity:, code:, message:, span: nil, labels: [], notes: [], suggestions: [])
        raise ArgumentError, "Invalid severity: #{severity}" unless SEVERITIES.key?(severity)

        @severity = severity
        @code = code
        @message = message
        @span = span
        @labels = labels
        @notes = notes
        @suggestions = suggestions
      end

      def error?
        @severity == :error
      end

      def warning?
        @severity == :warning
      end

      # Create a type mismatch error
      def self.type_mismatch(expected:, found:, span:, note_span: nil)
        labels = [Label.new(span: span, message: "expected #{expected}, found #{found}")]

        notes = []
        if note_span
          notes << "type was inferred here: #{note_span}"
        end

        new(
          severity: :error,
          code: "E001",
          message: "type mismatch",
          span: span,
          labels: labels,
          notes: notes
        )
      end

      # Create an undefined variable error
      def self.undefined_variable(name:, span:, similar: nil)
        suggestions = []
        if similar
          suggestions << "did you mean `#{similar}`?"
        end

        new(
          severity: :error,
          code: "E004",
          message: "undefined variable `#{name}`",
          span: span,
          suggestions: suggestions
        )
      end

      # Create an undefined method error
      def self.undefined_method(name:, receiver_type:, span:)
        new(
          severity: :error,
          code: "E005",
          message: "undefined method `#{name}` for type #{receiver_type}",
          span: span
        )
      end

      # Create a parse error
      def self.parse_error(message:, span:)
        new(
          severity: :error,
          code: "E010",
          message: message,
          span: span
        )
      end

      # Create a circular dependency error
      def self.circular_dependency(cycle:, span:)
        cycle_str = cycle.join(" -> ")
        new(
          severity: :error,
          code: "E020",
          message: "circular dependency detected",
          span: span,
          notes: ["dependency cycle: #{cycle_str}"]
        )
      end

      # Create a file not found error
      def self.file_not_found(path:, span:)
        new(
          severity: :error,
          code: "E021",
          message: "file not found: #{path}",
          span: span
        )
      end

      # Create a codegen error
      def self.codegen_error(message:, span: nil)
        new(
          severity: :error,
          code: "E030",
          message: message,
          span: span
        )
      end

      # Create an arity mismatch error
      def self.arity_mismatch(expected:, found:, span:)
        new(
          severity: :error,
          code: "E002",
          message: "wrong number of arguments (given #{found}, expected #{expected})",
          span: span
        )
      end

      # Create an occurs check error (infinite type)
      def self.occurs_check(type_var:, type:, span:)
        new(
          severity: :error,
          code: "E003",
          message: "cannot construct infinite type: #{type_var} ~ #{type}",
          span: span
        )
      end
    end
  end
end
