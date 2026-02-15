# frozen_string_literal: true

module Konpeito
  module AST
    # Wrapper for Prism AST nodes with type information
    class TypedNode
      attr_reader :node, :type, :children

      def initialize(node, type, children = [])
        @node = node
        @type = type
        @children = children
      end

      def location
        node.location
      end

      def node_type
        node.class.name.split("::").last.sub(/Node$/, "").gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
      end

      def inspect
        "#<TypedNode #{node_type} : #{type}>"
      end
    end

    # Builds a typed AST from Prism AST
    class TypedASTBuilder < Visitor
      attr_reader :inferrer, :rbs_loader, :use_hm

      def initialize(rbs_loader, use_hm: true, file_path: nil, source: nil)
        @rbs_loader = rbs_loader
        @use_hm = use_hm
        @file_path = file_path
        @source = source

        if use_hm
          @hm_inferrer = TypeChecker::HMInferrer.new(rbs_loader, file_path: file_path, source: source)
          @inferrer = nil  # Will use HM inferrer
        else
          @hm_inferrer = nil
          @inferrer = TypeChecker::Inferrer.new(rbs_loader)
        end
      end

      # Get diagnostics from the HM inferrer
      def diagnostics
        @hm_inferrer&.diagnostics || []
      end

      def build(ast)
        # If using HM inference, run whole-program analysis first
        if @use_hm && @hm_inferrer
          @hm_inferrer.analyze(ast)
        end

        visit(ast)
      end

      # Get type for a node (uses HM inferrer if available)
      def infer_type(node)
        if @use_hm && @hm_inferrer
          @hm_inferrer.type_for(node)
        else
          @inferrer.infer(node)
        end
      end

      private

      def visit(node)
        return nil unless node

        method_name = :"visit_#{node_type(node)}"
        if respond_to?(method_name, true)
          send(method_name, node)
        else
          visit_default(node)
        end
      end

      def visit_default(node)
        type = infer_type(node)
        children = node.compact_child_nodes.map { |child| visit(child) }.compact
        TypedNode.new(node, type, children)
      end

      def visit_program(node)
        type = infer_type(node)
        children = [visit(node.statements)].compact
        TypedNode.new(node, type, children)
      end

      def visit_statements(node)
        type = infer_type(node)
        children = node.body.map { |stmt| visit(stmt) }.compact
        TypedNode.new(node, type, children)
      end

      def visit_def(node)
        # Create a new scope for method body
        type = infer_type(node)

        children = []
        children << visit(node.parameters) if node.parameters
        children << visit(node.body) if node.body
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_class(node)
        type = infer_type(node)

        children = []
        children << visit(node.constant_path) if node.constant_path
        children << visit(node.superclass) if node.superclass
        children << visit(node.body) if node.body
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_module(node)
        type = infer_type(node)

        children = []
        children << visit(node.constant_path) if node.constant_path
        children << visit(node.body) if node.body
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_if(node)
        type = infer_type(node)

        children = []
        children << visit(node.predicate)
        children << visit(node.statements) if node.statements
        children << visit(node.subsequent) if node.subsequent
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_unless(node)
        type = infer_type(node)

        children = []
        children << visit(node.predicate)
        children << visit(node.statements) if node.statements
        children << visit(node.else_clause) if node.else_clause
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_and(node)
        type = infer_type(node)

        children = []
        children << visit(node.left)
        children << visit(node.right)
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_or(node)
        type = infer_type(node)

        children = []
        children << visit(node.left)
        children << visit(node.right)
        children.compact!

        TypedNode.new(node, type, children)
      end

      # Compound assignment visitors
      def visit_local_variable_operator_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_local_variable_or_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_local_variable_and_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_instance_variable_operator_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_instance_variable_or_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_instance_variable_and_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_class_variable_operator_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_class_variable_or_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_class_variable_and_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_while(node)
        type = infer_type(node)

        children = []
        children << visit(node.predicate)
        children << visit(node.statements) if node.statements
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_until(node)
        type = infer_type(node)

        children = []
        children << visit(node.predicate)
        children << visit(node.statements) if node.statements
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_break(node)
        type = infer_type(node)
        children = []
        children << visit(node.arguments) if node.arguments
        children.compact!
        TypedNode.new(node, type, children)
      end

      def visit_next(node)
        type = infer_type(node)
        children = []
        children << visit(node.arguments) if node.arguments
        children.compact!
        TypedNode.new(node, type, children)
      end

      def visit_range(node)
        type = infer_type(node)
        children = []
        children << visit(node.left) if node.left
        children << visit(node.right) if node.right
        children.compact!
        TypedNode.new(node, type, children)
      end

      def visit_global_variable_read(node)
        type = infer_type(node)
        TypedNode.new(node, type, [])
      end

      def visit_global_variable_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_multi_write(node)
        type = infer_type(node)
        children = []
        # Visit the value (RHS)
        children << visit(node.value) if node.value
        children.compact!
        TypedNode.new(node, type, children)
      end

      def visit_super(node)
        type = infer_type(node)
        children = []
        children << visit(node.arguments) if node.arguments
        children.compact!
        TypedNode.new(node, type, children)
      end

      def visit_forwarding_super(node)
        type = infer_type(node)
        TypedNode.new(node, type, [])
      end

      def visit_case(node)
        type = infer_type(node)

        children = []
        children << visit(node.predicate) if node.predicate
        node.conditions.each { |cond| children << visit(cond) }
        children << visit(node.else_clause) if node.else_clause
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_when(node)
        type = infer_type(node)

        children = []
        node.conditions.each { |cond| children << visit(cond) }
        children << visit(node.statements) if node.statements
        children.compact!

        TypedNode.new(node, type, children)
      end

      # ========================================
      # Pattern Matching visitors
      # ========================================

      # case/in statement
      def visit_case_match(node)
        type = infer_type(node)

        children = []
        children << visit(node.predicate) if node.predicate
        node.conditions.each { |cond| children << visit(cond) }
        children << visit(node.else_clause) if node.else_clause
        children.compact!

        TypedNode.new(node, type, children)
      end

      # in clause
      def visit_in(node)
        type = infer_type(node)

        children = []
        children << visit(node.pattern) if node.pattern
        children << visit(node.statements) if node.statements
        children.compact!

        TypedNode.new(node, type, children)
      end

      # expr in pattern (returns boolean)
      def visit_match_predicate(node)
        type = TypeChecker::Types::BOOL

        children = []
        children << visit(node.value)
        children << visit(node.pattern)
        children.compact!

        TypedNode.new(node, type, children)
      end

      # expr => pattern (raises on failure)
      def visit_match_required(node)
        type = infer_type(node)

        children = []
        children << visit(node.value)
        children << visit(node.pattern)
        children.compact!

        TypedNode.new(node, type, children)
      end

      # [a, b, *rest] pattern
      def visit_array_pattern(node)
        type = TypeChecker::Types::UNTYPED

        children = []
        children << visit(node.constant) if node.constant
        node.requireds.each { |req| children << visit(req) }
        children << visit(node.rest) if node.rest
        node.posts.each { |post| children << visit(post) }
        children.compact!

        TypedNode.new(node, type, children)
      end

      # {x:, y: pattern} pattern
      def visit_hash_pattern(node)
        type = TypeChecker::Types::UNTYPED

        children = []
        children << visit(node.constant) if node.constant
        node.elements.each { |elem| children << visit(elem) }
        children << visit(node.rest) if node.rest
        children.compact!

        TypedNode.new(node, type, children)
      end

      # a | b pattern
      def visit_alternation_pattern(node)
        type = TypeChecker::Types::UNTYPED

        children = []
        children << visit(node.left)
        children << visit(node.right)
        children.compact!

        TypedNode.new(node, type, children)
      end

      # pattern => var capture
      def visit_capture_pattern(node)
        type = TypeChecker::Types::UNTYPED

        children = []
        children << visit(node.value)
        children << visit(node.target)
        children.compact!

        TypedNode.new(node, type, children)
      end

      # ^var pinned pattern
      def visit_pinned_variable(node)
        type = TypeChecker::Types::UNTYPED

        children = []
        children << visit(node.variable)
        children.compact!

        TypedNode.new(node, type, children)
      end

      # ^(expr) pinned expression
      def visit_pinned_expression(node)
        type = TypeChecker::Types::UNTYPED

        children = []
        children << visit(node.expression)
        children.compact!

        TypedNode.new(node, type, children)
      end

      # [*a, pattern, *b] find pattern
      def visit_find_pattern(node)
        type = TypeChecker::Types::UNTYPED

        children = []
        children << visit(node.left) if node.left
        node.requireds.each { |req| children << visit(req) }
        children << visit(node.right) if node.right
        children.compact!

        TypedNode.new(node, type, children)
      end

      # *rest splat
      def visit_splat(node)
        type = TypeChecker::Types::UNTYPED
        children = []
        children << visit(node.expression) if node.expression
        children.compact!
        TypedNode.new(node, type, children)
      end

      # **rest keyword splat (in pattern context)
      def visit_assoc_splat(node)
        type = TypeChecker::Types::UNTYPED
        children = []
        children << visit(node.value) if node.value
        children.compact!
        TypedNode.new(node, type, children)
      end

      # x: in hash pattern (shorthand)
      def visit_no_keywords(node)
        type = TypeChecker::Types::UNTYPED
        TypedNode.new(node, type, [])
      end

      def visit_call(node)
        type = infer_type(node)

        children = []
        children << visit(node.receiver) if node.receiver
        children << visit(node.arguments) if node.arguments
        children << visit(node.block) if node.block
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_arguments(node)
        type = TypeChecker::Types::UNTYPED
        children = node.arguments.map { |arg| visit(arg) }.compact
        TypedNode.new(node, type, children)
      end

      def visit_block(node)
        type = infer_type(node)

        children = []
        children << visit(node.parameters) if node.parameters
        children << visit(node.body) if node.body
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_array(node)
        type = infer_type(node)
        children = node.elements.map { |elem| visit(elem) }.compact
        TypedNode.new(node, type, children)
      end

      def visit_hash(node)
        type = infer_type(node)
        children = node.elements.map { |elem| visit(elem) }.compact
        TypedNode.new(node, type, children)
      end

      def visit_assoc(node)
        type = TypeChecker::Types::UNTYPED
        children = [visit(node.key), visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_begin(node)
        type = infer_type(node)

        children = []
        children << visit(node.statements) if node.statements
        children << visit(node.rescue_clause) if node.rescue_clause
        children << visit(node.else_clause) if node.else_clause
        children << visit(node.ensure_clause) if node.ensure_clause
        children.compact!

        TypedNode.new(node, type, children)
      end

      def visit_rescue(node)
        type = infer_type(node)

        children = []
        node.exceptions&.each { |ex| children << visit(ex) }
        children << visit(node.statements) if node.statements
        children << visit(node.subsequent) if node.subsequent
        children.compact!

        TypedNode.new(node, type, children)
      end

      # Terminal nodes (no children)
      %i[
        integer float string symbol true false nil
        local_variable_read instance_variable_read class_variable_read
        constant_read self source_file source_line
      ].each do |name|
        define_method(:"visit_#{name}") do |node|
          type = infer_type(node)
          TypedNode.new(node, type, [])
        end
      end

      # Assignment nodes
      def visit_local_variable_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_instance_variable_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_class_variable_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_constant_write(node)
        type = infer_type(node)
        children = [visit(node.value)].compact
        TypedNode.new(node, type, children)
      end

      def visit_return(node)
        type = infer_type(node)
        children = node.arguments ? [visit(node.arguments)] : []
        children.compact!
        TypedNode.new(node, type, children)
      end
    end
  end
end
