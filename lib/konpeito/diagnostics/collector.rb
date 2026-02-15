# frozen_string_literal: true

require_relative "diagnostic"
require_relative "renderer"

module Konpeito
  module Diagnostics
    # Collects diagnostics from various compilation phases
    class Collector
      attr_reader :diagnostics

      def initialize
        @diagnostics = []
        @source_cache = {}  # file_path -> source content
      end

      # Register source content for a file
      def register_source(file_path, content)
        @source_cache[file_path] = content
      end

      # Get cached source content
      def source_for(file_path)
        @source_cache[file_path] ||= File.exist?(file_path) ? File.read(file_path) : nil
      end

      # Add a diagnostic
      def add(diagnostic)
        @diagnostics << diagnostic
      end

      # Create and add a type mismatch error
      def type_mismatch(expected:, found:, node:, file_path:)
        span = span_from_node(node, file_path)
        add(Diagnostic.type_mismatch(expected: expected, found: found, span: span))
      end

      # Create and add an undefined variable error
      def undefined_variable(name:, node:, file_path:, similar: nil)
        span = span_from_node(node, file_path)
        add(Diagnostic.undefined_variable(name: name, span: span, similar: similar))
      end

      # Create and add a parse error
      def parse_error(message:, location:, file_path:)
        span = span_from_location(location, file_path)
        add(Diagnostic.parse_error(message: message, span: span))
      end

      # Create and add a circular dependency error
      def circular_dependency(cycle:, file_path:, line: 1)
        span = SourceSpan.new(
          file_path: file_path,
          start_line: line,
          start_column: 0,
          source: source_for(file_path)
        )
        add(Diagnostic.circular_dependency(cycle: cycle, span: span))
      end

      # Create and add a file not found error
      def file_not_found(path:, from_file:, line: 1)
        span = SourceSpan.new(
          file_path: from_file,
          start_line: line,
          start_column: 0,
          source: source_for(from_file)
        )
        add(Diagnostic.file_not_found(path: path, span: span))
      end

      # Create and add a codegen error
      def codegen_error(message:, node: nil, file_path: nil)
        span = node && file_path ? span_from_node(node, file_path) : nil
        add(Diagnostic.codegen_error(message: message, span: span))
      end

      # Create and add an arity mismatch error
      def arity_mismatch(expected:, found:, node:, file_path:)
        span = span_from_node(node, file_path)
        add(Diagnostic.arity_mismatch(expected: expected, found: found, span: span))
      end

      # Check if there are any errors
      def errors?
        @diagnostics.any?(&:error?)
      end

      # Get only errors
      def errors
        @diagnostics.select(&:error?)
      end

      # Get only warnings
      def warnings
        @diagnostics.select(&:warning?)
      end

      # Render all diagnostics
      def render(color: true, io: $stderr)
        renderer = DiagnosticRenderer.new(color: color, io: io)
        renderer.render_all(@diagnostics)
      end

      # Clear all diagnostics
      def clear
        @diagnostics.clear
      end

      private

      def span_from_node(node, file_path)
        return nil unless node.respond_to?(:location) && node.location

        span_from_location(node.location, file_path)
      end

      def span_from_location(location, file_path)
        SourceSpan.from_prism_location(
          location,
          file_path: file_path,
          source: source_for(file_path)
        )
      end
    end
  end
end
