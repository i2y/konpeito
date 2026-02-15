# frozen_string_literal: true

require "prism"

module Konpeito
  module Parser
    class PrismAdapter
      class << self
        def parse(source, filepath: "(eval)")
          result = Prism.parse(source, filepath: filepath)

          unless result.success?
            errors = result.errors.map { |e| format_error(e, filepath) }
            raise ParseError, "Parse errors:\n#{errors.join("\n")}"
          end

          result.value
        end

        def parse_file(filepath)
          source = File.read(filepath)
          parse(source, filepath: filepath)
        end

        # Detect require and require_relative calls in AST
        # Returns array of { type: :require | :require_relative, name: String }
        def detect_requires(ast)
          requires = []
          visitor = RequireVisitor.new(requires)
          visitor.visit(ast)
          requires
        end

        private

        def format_error(error, filepath)
          loc = error.location
          "  #{filepath}:#{loc.start_line}:#{loc.start_column}: #{error.message}"
        end
      end

      # Visitor to detect require/require_relative calls
      class RequireVisitor < Prism::Visitor
        def initialize(requires)
          @requires = requires
        end

        def visit_call_node(node)
          if node.receiver.nil? && %w[require require_relative].include?(node.name.to_s)
            arg = node.arguments&.arguments&.first
            if arg.is_a?(Prism::StringNode)
              @requires << {
                type: node.name.to_sym,
                name: arg.unescaped,
                line: node.location.start_line,
                column: node.location.start_column
              }
            end
          end
          super
        end
      end
    end
  end
end
