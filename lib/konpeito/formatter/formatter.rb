# frozen_string_literal: true

require "prism"
require "stringio"

module Konpeito
  module Formatter
    class Formatter
      INDENT_SIZE = 2

      def initialize(source, filepath: nil)
        @source = source
        @filepath = filepath
        @result = Prism.parse(source, filepath: filepath)
        @comments = @result.comments.dup
        @output = StringIO.new
        @indent = 0
        @line_started = false
        @last_was_newline = false
        @current_line = 1
      end

      def format
        visit(@result.value)
        flush_remaining_comments
        result = @output.string
        # Ensure trailing newline
        result += "\n" unless result.end_with?("\n")
        # Collapse 3+ consecutive newlines into 2
        result.gsub(/\n{3,}/, "\n\n")
      end

      private

      # --- Core emit helpers ---

      def emit(str)
        return if str.nil? || str.empty?
        if !@line_started
          @output << (" " * (INDENT_SIZE * @indent))
          @line_started = true
        end
        @output << str
        @last_was_newline = false
      end

      def emit_newline
        @output << "\n"
        @line_started = false
        @last_was_newline = true
        @current_line += 1
      end

      def emit_blank_line
        # Ensure we end current line if needed, then add one blank line
        unless @last_was_newline
          emit_newline
        end
        @output << "\n"
        @current_line += 1
      end

      def indent
        @indent += 1
      end

      def dedent
        @indent -= 1
        @indent = 0 if @indent < 0
      end

      # --- Comment handling ---

      def emit_leading_comments(node)
        return unless node.respond_to?(:location)
        target_line = node.location.start_line
        last_comment_line = nil

        while (comment = @comments.first) && comment.location.start_line < target_line
          @comments.shift

          # Preserve blank line between comments/before this comment
          if last_comment_line && comment.location.start_line - last_comment_line > 1
            emit_blank_line
          end

          emit(comment.location.slice)
          emit_newline
          last_comment_line = comment.location.end_line
        end

        # Preserve blank line between last comment and the node
        if last_comment_line && node.location.start_line - last_comment_line > 1
          emit_blank_line
        end
      end

      def emit_inline_comment(node)
        return unless node.respond_to?(:location)
        end_line = node.location.end_line

        if (comment = @comments.first) && comment.location.start_line == end_line
          @comments.shift
          emit(" ")
          emit(comment.location.slice)
        end
      end

      def flush_remaining_comments
        @comments.each do |comment|
          emit(comment.location.slice)
          emit_newline
        end
        @comments.clear
      end

      # --- Visit dispatch ---

      def visit(node)
        return unless node

        method_name = :"visit_#{node.type}"
        if respond_to?(method_name, true)
          send(method_name, node)
        else
          # Fallback: emit original source
          emit(node.location.slice)
        end
      end

      def visit_list(nodes, separator: nil)
        nodes.each_with_index do |node, i|
          visit(node)
          if separator && i < nodes.size - 1
            emit(separator)
          end
        end
      end

      # --- Node visitors ---

      def visit_program_node(node)
        visit(node.statements)
      end

      def visit_statements_node(node)
        body = node.body
        body.each_with_index do |stmt, i|
          emit_leading_comments(stmt)
          visit(stmt)
          emit_inline_comment(stmt)
          emit_newline unless i == body.size - 1 && @last_was_newline

          # Preserve blank lines between statements based on original source
          if i < body.size - 1
            next_stmt = body[i + 1]
            current_end = stmt.location.end_line
            # Check for leading comments on next node
            next_start = next_stmt.location.start_line
            if @comments.first && @comments.first.location.start_line < next_start
              next_start = @comments.first.location.start_line
            end

            if next_start - current_end > 1 || needs_blank_line_between?(stmt, next_stmt)
              emit_blank_line
            end
          end
        end
      end

      def needs_blank_line_between?(a, b)
        [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode].any? { |k| a.is_a?(k) || b.is_a?(k) }
      end

      # --- Literals ---

      def visit_integer_node(node)
        emit(node.location.slice)
      end

      def visit_float_node(node)
        emit(node.location.slice)
      end

      def visit_rational_node(node)
        emit(node.location.slice)
      end

      def visit_imaginary_node(node)
        emit(node.location.slice)
      end

      def visit_string_node(node)
        emit(node.location.slice)
      end

      def visit_interpolated_string_node(node)
        emit(node.location.slice)
      end

      def visit_symbol_node(node)
        emit(node.location.slice)
      end

      def visit_interpolated_symbol_node(node)
        emit(node.location.slice)
      end

      def visit_regular_expression_node(node)
        emit(node.location.slice)
      end

      def visit_interpolated_regular_expression_node(node)
        emit(node.location.slice)
      end

      def visit_x_string_node(node)
        emit(node.location.slice)
      end

      def visit_true_node(node)
        emit("true")
      end

      def visit_false_node(node)
        emit("false")
      end

      def visit_nil_node(node)
        emit("nil")
      end

      def visit_self_node(node)
        emit("self")
      end

      def visit_source_file_node(node)
        emit("__FILE__")
      end

      def visit_source_line_node(node)
        emit("__LINE__")
      end

      def visit_source_encoding_node(node)
        emit("__ENCODING__")
      end

      # --- Variables ---

      def visit_local_variable_read_node(node)
        emit(node.name.to_s)
      end

      def visit_local_variable_write_node(node)
        emit(node.name.to_s)
        emit(" = ")
        visit(node.value)
      end

      def visit_local_variable_operator_write_node(node)
        emit(node.name.to_s)
        emit(" #{node.binary_operator}= ")
        visit(node.value)
      end

      def visit_local_variable_and_write_node(node)
        emit(node.name.to_s)
        emit(" &&= ")
        visit(node.value)
      end

      def visit_local_variable_or_write_node(node)
        emit(node.name.to_s)
        emit(" ||= ")
        visit(node.value)
      end

      def visit_local_variable_target_node(node)
        emit(node.name.to_s)
      end

      def visit_instance_variable_read_node(node)
        emit(node.name.to_s)
      end

      def visit_instance_variable_write_node(node)
        emit(node.name.to_s)
        emit(" = ")
        visit(node.value)
      end

      def visit_instance_variable_operator_write_node(node)
        emit(node.name.to_s)
        emit(" #{node.binary_operator}= ")
        visit(node.value)
      end

      def visit_instance_variable_and_write_node(node)
        emit(node.name.to_s)
        emit(" &&= ")
        visit(node.value)
      end

      def visit_instance_variable_or_write_node(node)
        emit(node.name.to_s)
        emit(" ||= ")
        visit(node.value)
      end

      def visit_instance_variable_target_node(node)
        emit(node.name.to_s)
      end

      def visit_class_variable_read_node(node)
        emit(node.name.to_s)
      end

      def visit_class_variable_write_node(node)
        emit(node.name.to_s)
        emit(" = ")
        visit(node.value)
      end

      def visit_class_variable_operator_write_node(node)
        emit(node.name.to_s)
        emit(" #{node.binary_operator}= ")
        visit(node.value)
      end

      def visit_class_variable_and_write_node(node)
        emit(node.name.to_s)
        emit(" &&= ")
        visit(node.value)
      end

      def visit_class_variable_or_write_node(node)
        emit(node.name.to_s)
        emit(" ||= ")
        visit(node.value)
      end

      def visit_global_variable_read_node(node)
        emit(node.name.to_s)
      end

      def visit_global_variable_write_node(node)
        emit(node.name.to_s)
        emit(" = ")
        visit(node.value)
      end

      def visit_constant_read_node(node)
        emit(node.name.to_s)
      end

      def visit_constant_write_node(node)
        emit(node.name.to_s)
        emit(" = ")
        visit(node.value)
      end

      def visit_constant_path_node(node)
        if node.parent
          visit(node.parent)
          emit("::")
        else
          emit("::")
        end
        emit(node.name.to_s)
      end

      def visit_constant_path_write_node(node)
        visit(node.target)
        emit(" = ")
        visit(node.value)
      end

      # --- Method definitions ---

      def visit_def_node(node)
        emit("def ")
        if node.receiver
          visit(node.receiver)
          emit(".")
        end
        emit(node.name.to_s)

        if node.parameters
          emit("(")
          visit(node.parameters)
          emit(")")
        end

        if node.body
          emit_newline
          indent
          visit(node.body)
          emit_newline unless @last_was_newline
          dedent
          emit("end")
        else
          emit_newline
          emit("end")
        end
      end

      def visit_parameters_node(node)
        params = []

        node.requireds.each { |p| params << p }
        node.optionals.each { |p| params << p }
        params << node.rest if node.rest
        node.posts.each { |p| params << p }
        node.keywords.each { |p| params << p }
        params << node.keyword_rest if node.keyword_rest
        params << node.block if node.block

        params.each_with_index do |param, i|
          visit(param)
          emit(", ") if i < params.size - 1
        end
      end

      def visit_required_parameter_node(node)
        emit(node.name.to_s)
      end

      def visit_optional_parameter_node(node)
        emit(node.name.to_s)
        emit(" = ")
        visit(node.value)
      end

      def visit_rest_parameter_node(node)
        emit("*")
        emit(node.name.to_s) if node.name
      end

      def visit_keyword_rest_parameter_node(node)
        emit("**")
        emit(node.name.to_s) if node.name
      end

      def visit_required_keyword_parameter_node(node)
        emit(node.name.to_s)
        emit(":")
      end

      def visit_optional_keyword_parameter_node(node)
        emit(node.name.to_s)
        emit(": ")
        visit(node.value)
      end

      def visit_block_parameter_node(node)
        emit("&")
        emit(node.name.to_s) if node.name
      end

      # --- Class / Module ---

      def visit_class_node(node)
        emit("class ")
        visit(node.constant_path)
        if node.superclass
          emit(" < ")
          visit(node.superclass)
        end
        emit_newline

        if node.body
          indent
          visit(node.body)
          emit_newline unless @last_was_newline
          dedent
        end

        emit("end")
      end

      def visit_module_node(node)
        emit("module ")
        visit(node.constant_path)
        emit_newline

        if node.body
          indent
          visit(node.body)
          emit_newline unless @last_was_newline
          dedent
        end

        emit("end")
      end

      def visit_singleton_class_node(node)
        emit("class << ")
        visit(node.expression)
        emit_newline

        if node.body
          indent
          visit(node.body)
          emit_newline unless @last_was_newline
          dedent
        end

        emit("end")
      end

      # --- Control flow ---

      def visit_if_node(node)
        # Ternary or modifier form — fall back to source
        if node.location.slice.include?("?") && !node.location.slice.strip.start_with?("if")
          emit(node.location.slice)
          return
        end

        # Check for modifier if (single-line "expr if cond")
        src = node.location.slice.strip
        if !src.start_with?("if") && !src.start_with?("elsif")
          emit(node.location.slice)
          return
        end

        if src.start_with?("elsif")
          emit("elsif ")
        else
          emit("if ")
        end
        visit(node.predicate)
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end

        if node.subsequent
          visit_if_subsequent(node.subsequent)
        end

        # Only top-level if gets 'end', elsif doesn't
        emit("end") unless src.start_with?("elsif")
      end

      def visit_if_subsequent(node)
        case node
        when Prism::IfNode
          # elsif
          emit("elsif ")
          visit(node.predicate)
          emit_newline
          if node.statements
            indent
            visit(node.statements)
            emit_newline unless @last_was_newline
            dedent
          end
          visit_if_subsequent(node.subsequent) if node.subsequent
        when Prism::ElseNode
          visit_else_node(node)
        end
      end

      def visit_else_node(node)
        emit("else")
        emit_newline
        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end
      end

      def visit_unless_node(node)
        emit("unless ")
        visit(node.predicate)
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end

        if node.else_clause
          visit_else_node(node.else_clause)
        end

        emit("end")
      end

      def visit_while_node(node)
        emit("while ")
        visit(node.predicate)
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end

        emit("end")
      end

      def visit_until_node(node)
        emit("until ")
        visit(node.predicate)
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end

        emit("end")
      end

      def visit_for_node(node)
        emit("for ")
        visit(node.index)
        emit(" in ")
        visit(node.collection)
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end

        emit("end")
      end

      def visit_case_node(node)
        emit("case ")
        visit(node.predicate) if node.predicate
        emit_newline

        node.conditions.each do |cond|
          visit(cond)
        end

        if node.else_clause
          visit_else_node(node.else_clause)
        end

        emit("end")
      end

      def visit_when_node(node)
        emit("when ")
        visit_list(node.conditions, separator: ", ")
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end
      end

      def visit_case_match_node(node)
        emit("case ")
        visit(node.predicate) if node.predicate
        emit_newline

        node.conditions.each do |cond|
          visit(cond)
        end

        if node.else_clause
          visit_else_node(node.else_clause)
        end

        emit("end")
      end

      def visit_in_node(node)
        emit("in ")
        visit(node.pattern)
        if node.statements
          emit_newline
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        else
          emit_newline
        end
      end

      # --- Method calls ---

      def visit_call_node(node)
        # Handle special operator calls
        name = node.name.to_s

        if node.receiver
          visit(node.receiver)

          if name == "[]"
            emit("[")
            visit(node.arguments) if node.arguments
            emit("]")
            visit(node.block) if node.block
            return
          elsif name == "[]="
            emit("[")
            args = node.arguments.arguments
            visit(args.first)
            emit("] = ")
            visit(args.last)
            return
          end

          # Binary operators
          if binary_operator?(name) && node.arguments && node.arguments.arguments.size == 1
            emit(" #{name} ")
            visit(node.arguments.arguments.first)
            visit(node.block) if node.block
            return
          end

          # Unary operators
          if unary_operator?(name) && (!node.arguments || node.arguments.arguments.empty?)
            emit(name)
            return
          end

          # Safe navigation
          if node.call_operator_loc && node.call_operator_loc.slice == "&."
            emit("&.")
          else
            emit(".")
          end
        end

        emit(name)

        if node.opening_loc
          # Explicit parentheses in source
          emit("(")
          visit(node.arguments) if node.arguments
          emit(")")
        elsif node.arguments
          # No parentheses in source — preserve that style
          emit(" ")
          visit(node.arguments)
        end

        visit(node.block) if node.block
      end

      def binary_operator?(name)
        %w[+ - * / % ** == != < > <= >= <=> << >> & | ^ =~ !~ === .. ...].include?(name)
      end

      def unary_operator?(name)
        %w[-@ +@].include?(name)
      end

      def visit_arguments_node(node)
        node.arguments.each_with_index do |arg, i|
          visit(arg)
          emit(", ") if i < node.arguments.size - 1
        end
      end

      # --- Blocks ---

      def visit_block_node(node)
        # Determine brace vs do/end style
        single_line = single_line_block?(node)

        if single_line
          emit(" { ")
          if node.parameters
            emit("|")
            visit(node.parameters)
            emit("| ")
          end
          if node.body.is_a?(Prism::StatementsNode)
            visit_list(node.body.body, separator: "; ")
          elsif node.body
            visit(node.body)
          end
          emit(" }")
        else
          emit(" do")
          if node.parameters
            emit(" |")
            visit(node.parameters)
            emit("|")
          end
          emit_newline
          if node.body
            indent
            visit(node.body)
            emit_newline unless @last_was_newline
            dedent
          end
          emit("end")
        end
      end

      def single_line_block?(node)
        return false unless node.body
        # If the block fits on one line in source, keep it that way
        node.location.start_line == node.location.end_line
      end

      def visit_block_parameters_node(node)
        params = node.parameters
        if params
          visit(params)
        end
      end

      def visit_lambda_node(node)
        emit("->")
        if node.parameters
          emit("(")
          visit(node.parameters)
          emit(")")
        end

        if node.body && node.location.start_line == node.location.end_line
          emit(" { ")
          visit(node.body)
          emit(" }")
        else
          emit(" do")
          emit_newline
          if node.body
            indent
            visit(node.body)
            emit_newline unless @last_was_newline
            dedent
          end
          emit("end")
        end
      end

      # --- Exception handling ---

      def visit_begin_node(node)
        emit("begin")
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end

        visit(node.rescue_clause) if node.rescue_clause

        if node.else_clause
          visit_else_node(node.else_clause)
        end

        if node.ensure_clause
          visit(node.ensure_clause)
        end

        emit("end")
      end

      def visit_rescue_node(node)
        emit("rescue")
        if node.exceptions && !node.exceptions.empty?
          emit(" ")
          visit_list(node.exceptions, separator: ", ")
        end
        if node.reference
          emit(" => ")
          visit(node.reference)
        end
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end

        visit(node.subsequent) if node.subsequent
      end

      def visit_ensure_node(node)
        emit("ensure")
        emit_newline

        if node.statements
          indent
          visit(node.statements)
          emit_newline unless @last_was_newline
          dedent
        end
      end

      def visit_rescue_modifier_node(node)
        visit(node.expression)
        emit(" rescue ")
        visit(node.rescue_expression)
      end

      # --- Return / Break / Next ---

      def visit_return_node(node)
        emit("return")
        if node.arguments
          emit(" ")
          visit(node.arguments)
        end
      end

      def visit_break_node(node)
        emit("break")
        if node.arguments
          emit(" ")
          visit(node.arguments)
        end
      end

      def visit_next_node(node)
        emit("next")
        if node.arguments
          emit(" ")
          visit(node.arguments)
        end
      end

      def visit_yield_node(node)
        emit("yield")
        if node.arguments
          emit("(")
          visit(node.arguments)
          emit(")")
        end
      end

      # --- Array / Hash ---

      def visit_array_node(node)
        # Detect %w / %i literals
        src = node.location.slice
        if src.start_with?("%w") || src.start_with?("%i") || src.start_with?("%W") || src.start_with?("%I")
          emit(src)
          return
        end

        emit("[")
        node.elements.each_with_index do |elem, i|
          visit(elem)
          emit(", ") if i < node.elements.size - 1
        end
        emit("]")
      end

      def visit_hash_node(node)
        emit("{")
        unless node.elements.empty?
          emit(" ")
          node.elements.each_with_index do |elem, i|
            visit(elem)
            emit(", ") if i < node.elements.size - 1
          end
          emit(" ")
        end
        emit("}")
      end

      def visit_assoc_node(node)
        visit(node.key)
        # Symbol key with shorthand: { foo: bar } vs { "foo" => bar }
        if node.key.is_a?(Prism::SymbolNode) && node.operator_loc.nil?
          emit(" ")
        else
          emit(" => ")
        end
        visit(node.value)
      end

      def visit_assoc_splat_node(node)
        emit("**")
        visit(node.value) if node.value
      end

      def visit_splat_node(node)
        emit("*")
        visit(node.expression) if node.expression
      end

      # --- Range ---

      def visit_range_node(node)
        visit(node.left) if node.left
        if node.exclude_end?
          emit("...")
        else
          emit("..")
        end
        visit(node.right) if node.right
      end

      # --- Assignments ---

      def visit_multi_write_node(node)
        node.lefts.each_with_index do |target, i|
          visit(target)
          emit(", ") if i < node.lefts.size - 1
        end
        if node.rest
          emit(", ") unless node.lefts.empty?
          visit(node.rest)
        end
        emit(" = ")
        visit(node.value)
      end

      # --- Require ---

      def visit_call_or_write_node(node)
        emit(node.location.slice)
      end

      # --- Super ---

      def visit_super_node(node)
        emit("super")
        if node.arguments
          emit("(")
          visit(node.arguments)
          emit(")")
        elsif node.opening_loc
          emit("()")
        end
        visit(node.block) if node.block
      end

      def visit_forwarding_super_node(node)
        emit("super")
      end

      # --- Defined? ---

      def visit_defined_node(node)
        emit("defined?(")
        visit(node.value)
        emit(")")
      end

      # --- Alias ---

      def visit_alias_method_node(node)
        emit("alias ")
        visit(node.new_name)
        emit(" ")
        visit(node.old_name)
      end

      # --- Parentheses ---

      def visit_parentheses_node(node)
        emit("(")
        visit(node.body) if node.body
        emit(")")
      end

      # --- Keyword Hash (bare hash in arguments) ---

      def visit_keyword_hash_node(node)
        node.elements.each_with_index do |elem, i|
          visit(elem)
          emit(", ") if i < node.elements.size - 1
        end
      end

      # --- Embedded statements in strings ---

      def visit_embedded_statements_node(node)
        emit(node.location.slice)
      end

      # --- Numbered/it parameters ---

      def visit_numbered_parameters_node(node)
        # Implicit, no output
      end

      def visit_it_parameters_node(node)
        # Implicit, no output
      end

      def visit_it_local_variable_read_node(node)
        emit("it")
      end

      # --- And/Or ---

      def visit_and_node(node)
        visit(node.left)
        # Use && vs 'and' based on source
        if node.operator_loc.slice == "and"
          emit(" and ")
        else
          emit(" && ")
        end
        visit(node.right)
      end

      def visit_or_node(node)
        visit(node.left)
        if node.operator_loc.slice == "or"
          emit(" or ")
        else
          emit(" || ")
        end
        visit(node.right)
      end

      # --- Not ---

      def visit_call_and_write_node(node)
        emit(node.location.slice)
      end

      # --- Misc ---

      def visit_frozen_string_literal_comment(node)
        emit(node.location.slice)
      end

      def visit_heredoc_node(node)
        emit(node.location.slice)
      end

      def visit_match_predicate_node(node)
        visit(node.value)
        emit(" in ")
        visit(node.pattern)
      end

      def visit_match_required_node(node)
        visit(node.value)
        emit(" => ")
        visit(node.pattern)
      end

      # Pattern nodes
      def visit_find_pattern_node(node)
        emit(node.location.slice)
      end

      def visit_array_pattern_node(node)
        emit(node.location.slice)
      end

      def visit_hash_pattern_node(node)
        emit(node.location.slice)
      end

      def visit_pinned_variable_node(node)
        emit("^")
        visit(node.variable)
      end

      def visit_pinned_expression_node(node)
        emit("^(")
        visit(node.expression)
        emit(")")
      end

      def visit_capture_pattern_node(node)
        visit(node.value)
        emit(" => ")
        visit(node.target)
      end

      def visit_alternation_pattern_node(node)
        visit(node.left)
        emit(" | ")
        visit(node.right)
      end

      # --- Ternary (inline if) ---

      def visit_if_node_ternary(node)
        visit(node.predicate)
        emit(" ? ")
        visit(node.statements)
        emit(" : ")
        visit(node.else_clause.statements) if node.else_clause
      end
    end
  end
end
