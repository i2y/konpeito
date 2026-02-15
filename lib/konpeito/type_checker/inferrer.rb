# frozen_string_literal: true

require_relative "types"

module Konpeito
  module TypeChecker
    # Type inference engine
    # Traverses Prism AST and infers types for expressions
    class Inferrer
      attr_reader :rbs_loader, :errors

      def initialize(rbs_loader)
        @rbs_loader = rbs_loader
        @errors = []
        @scopes = [{}]  # Stack of variable -> type mappings
        @current_class = nil  # Current class context
        @instance_var_types = {}  # class_name -> { ivar_name -> type }
      end

      # Infer the type of an AST node
      def infer(node)
        return Types::UNTYPED unless node

        method_name = :"infer_#{node_type(node)}"
        if respond_to?(method_name, true)
          send(method_name, node)
        else
          # Unknown node type, return untyped
          Types::UNTYPED
        end
      end

      # Get the inferred type for a local variable
      def variable_type(name)
        @scopes.reverse_each do |scope|
          return scope[name.to_sym] if scope.key?(name.to_sym)
        end
        nil
      end

      # Set the type for a local variable in current scope
      def set_variable_type(name, type)
        @scopes.last[name.to_sym] = type
      end

      private

      def node_type(node)
        node.class.name.split("::").last.sub(/Node$/, "").gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      def with_scope
        @scopes.push({})
        result = yield
        @scopes.pop
        result
      end

      # Literal types
      def infer_integer(node)
        Types::INTEGER
      end

      def infer_float(node)
        Types::FLOAT
      end

      def infer_string(node)
        Types::STRING
      end

      def infer_symbol(node)
        Types::SYMBOL
      end

      def infer_true(node)
        Types::TRUE_CLASS
      end

      def infer_false(node)
        Types::FALSE_CLASS
      end

      def infer_nil(node)
        Types::NIL
      end

      def infer_interpolated_string(node)
        Types::STRING
      end

      def infer_interpolated_symbol(node)
        Types::SYMBOL
      end

      # Array literal
      def infer_array(node)
        if node.elements.empty?
          Types.array(Types::UNTYPED)
        else
          element_types = node.elements.map { |e| infer(e) }.uniq
          element_type = if element_types.size == 1
            element_types.first
          else
            Types.union(*element_types)
          end
          Types.array(element_type)
        end
      end

      # Hash literal
      def infer_hash(node)
        if node.elements.empty?
          Types.hash_type(Types::UNTYPED, Types::UNTYPED)
        else
          key_types = []
          value_types = []

          node.elements.each do |element|
            if element.is_a?(Prism::AssocNode)
              key_types << infer(element.key)
              value_types << infer(element.value)
            end
          end

          key_type = key_types.uniq.size == 1 ? key_types.first : Types.union(*key_types.uniq)
          value_type = value_types.uniq.size == 1 ? value_types.first : Types.union(*value_types.uniq)

          Types.hash_type(key_type, value_type)
        end
      end

      # Range literal
      def infer_range(node)
        Types::ClassInstance.new(:Range, [infer(node.left)])
      end

      # Variable access
      def infer_local_variable_read(node)
        variable_type(node.name) || Types::UNTYPED
      end

      def infer_local_variable_write(node)
        value_type = infer(node.value)
        set_variable_type(node.name, value_type)
        value_type
      end

      def infer_local_variable_and_write(node)
        existing = variable_type(node.name) || Types::UNTYPED
        value_type = infer(node.value)
        # Result is union of nil (if existing was falsy) and value
        Types.union(existing, value_type)
      end

      def infer_local_variable_or_write(node)
        existing = variable_type(node.name) || Types::UNTYPED
        value_type = infer(node.value)
        set_variable_type(node.name, Types.union(existing, value_type))
        Types.union(existing, value_type)
      end

      def infer_instance_variable_read(node)
        return Types::UNTYPED unless @current_class

        ivar_name = node.name.to_s

        # Check cached instance variable types for this class
        if @instance_var_types[@current_class]&.key?(ivar_name)
          return @instance_var_types[@current_class][ivar_name]
        end

        # Check NativeClass field definitions from RBS
        if @rbs_loader&.native_class?(@current_class)
          native_type = @rbs_loader.native_class_type(@current_class)
          field_name = ivar_name.delete_prefix("@").to_sym
          if native_type.fields.key?(field_name)
            return native_field_to_type(native_type.fields[field_name])
          end
        end

        Types::UNTYPED
      end

      def infer_instance_variable_write(node)
        value_type = infer(node.value)

        # Track the type if we're in a class context
        if @current_class
          @instance_var_types[@current_class] ||= {}
          ivar_name = node.name.to_s
          existing_type = @instance_var_types[@current_class][ivar_name]
          @instance_var_types[@current_class][ivar_name] =
            existing_type ? Types.union(existing_type, value_type) : value_type
        end

        value_type
      end

      # Convert NativeClass field type to internal Type
      def native_field_to_type(field_type)
        case field_type
        when :i64 then Types::ClassInstance.new(:Integer)
        when :double then Types::ClassInstance.new(:Float)
        when :bool then Types::BOOL
        when :value then Types::UNTYPED  # Could be any VALUE
        else Types::UNTYPED
        end
      end

      def infer_class_variable_read(_node)
        Types::UNTYPED
      end

      def infer_class_variable_write(node)
        infer(node.value)
      end

      def infer_constant_read(node)
        name = node.name.to_sym
        if rbs_loader.type_exists?(name)
          # It's a class/module constant, return its singleton type
          Types::ClassInstance.new(name)
        else
          Types::UNTYPED
        end
      end

      # Control flow
      def infer_if(node)
        infer(node.predicate)

        then_type = node.statements ? infer_statements(node.statements) : Types::NIL
        else_type = node.subsequent ? infer(node.subsequent) : Types::NIL

        Types.union(then_type, else_type)
      end

      def infer_unless(node)
        infer(node.predicate)

        then_type = node.statements ? infer_statements(node.statements) : Types::NIL
        else_type = node.else_clause ? infer(node.else_clause) : Types::NIL

        Types.union(then_type, else_type)
      end

      def infer_else(node)
        node.statements ? infer_statements(node.statements) : Types::NIL
      end

      def infer_while(node)
        infer(node.predicate)
        infer_statements(node.statements) if node.statements
        Types::NIL
      end

      def infer_until(node)
        infer(node.predicate)
        infer_statements(node.statements) if node.statements
        Types::NIL
      end

      def infer_case(node)
        infer(node.predicate) if node.predicate

        branch_types = []
        node.conditions.each do |condition|
          branch_types << infer(condition)
        end

        if node.else_clause
          branch_types << infer(node.else_clause)
        else
          branch_types << Types::NIL
        end

        Types.union(*branch_types)
      end

      def infer_when(node)
        node.statements ? infer_statements(node.statements) : Types::NIL
      end

      # Method call
      def infer_call(node)
        receiver_type = node.receiver ? infer(node.receiver) : self_type

        # Try to get method return type from RBS
        if receiver_type.is_a?(Types::ClassInstance)
          method_types = rbs_loader.method_type(receiver_type.name, node.name)
          if method_types && !method_types.empty?
            return_type = rbs_type_to_internal(method_types.first.type.return_type)
            return return_type
          end
        end

        # Special cases for common methods
        case node.name
        when :+, :-, :*, :/, :%
          infer_arithmetic(node, receiver_type)
        when :==, :!=, :<, :>, :<=, :>=
          Types::BOOL
        when :to_s, :inspect
          Types::STRING
        when :to_i
          Types::INTEGER
        when :to_f
          Types::FLOAT
        when :to_a
          Types.array(Types::UNTYPED)
        when :to_h
          Types.hash_type(Types::UNTYPED, Types::UNTYPED)
        when :map, :collect
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
            Types.array(Types::UNTYPED)  # Need block return type
          else
            Types::UNTYPED
          end
        when :select, :filter, :reject
          receiver_type
        when :first, :last
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
            if receiver_type.type_args.any?
              Types.optional(receiver_type.type_args.first)
            else
              Types.optional(Types::UNTYPED)
            end
          else
            Types::UNTYPED
          end
        else
          Types::UNTYPED
        end
      end

      def infer_arithmetic(node, receiver_type)
        return Types::UNTYPED unless receiver_type.is_a?(Types::ClassInstance)

        case receiver_type.name
        when :Integer
          arg_type = node.arguments&.arguments&.first ? infer(node.arguments.arguments.first) : Types::UNTYPED
          if arg_type.is_a?(Types::ClassInstance) && arg_type.name == :Float
            Types::FLOAT
          else
            Types::INTEGER
          end
        when :Float
          Types::FLOAT
        when :String
          node.name == :+ ? Types::STRING : Types::UNTYPED
        else
          Types::UNTYPED
        end
      end

      # Method definition
      def infer_def(node)
        with_scope do
          # Add parameters to scope
          if node.parameters
            infer_parameters(node.parameters)
          end

          # Infer body type
          if node.body
            infer(node.body)
          else
            Types::NIL
          end
        end

        Types::SYMBOL  # def returns method name as symbol
      end

      def infer_parameters(node)
        node.requireds&.each do |param|
          set_variable_type(param.name, Types::UNTYPED) if param.respond_to?(:name)
        end

        node.optionals&.each do |param|
          if param.respond_to?(:name)
            value_type = param.respond_to?(:value) ? infer(param.value) : Types::UNTYPED
            set_variable_type(param.name, value_type)
          end
        end

        if node.rest && node.rest.respond_to?(:name) && node.rest.name
          set_variable_type(node.rest.name, Types.array(Types::UNTYPED))
        end

        node.keywords&.each do |param|
          if param.respond_to?(:name)
            value_type = param.respond_to?(:value) && param.value ? infer(param.value) : Types::UNTYPED
            set_variable_type(param.name, value_type)
          end
        end

        if node.keyword_rest && node.keyword_rest.respond_to?(:name) && node.keyword_rest.name
          set_variable_type(node.keyword_rest.name, Types.hash_type(Types::SYMBOL, Types::UNTYPED))
        end

        if node.block && node.block.respond_to?(:name) && node.block.name
          set_variable_type(node.block.name, Types::UNTYPED)
        end
      end

      # Class/Module definition
      def infer_class(node)
        # Extract class name
        class_name = extract_constant_name(node.constant_path)
        old_class = @current_class
        @current_class = class_name

        # Load instance variable types from RBS if available
        load_ivar_types_from_rbs(class_name) if @rbs_loader&.loaded?

        with_scope do
          infer(node.body) if node.body
        end

        @current_class = old_class
        Types::NIL
      end

      # Extract class/module name from constant path
      def extract_constant_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          parts = []
          current = node
          while current.is_a?(Prism::ConstantPathNode)
            parts.unshift(current.name.to_s) if current.respond_to?(:name)
            current = current.parent
          end
          parts.unshift(current.name.to_s) if current.respond_to?(:name)
          parts.join("::")
        else
          "Unknown"
        end
      end

      # Load instance variable types from RBS class definition
      def load_ivar_types_from_rbs(class_name)
        @instance_var_types[class_name] ||= {}
        # RBS instance variable types are loaded on-demand when accessed
      end

      def infer_module(node)
        with_scope do
          infer(node.body) if node.body
        end
        Types::NIL
      end

      # Blocks
      def infer_block(node)
        with_scope do
          if node.parameters
            # Add block parameters to scope
            node.parameters.parameters&.requireds&.each do |param|
              set_variable_type(param.name, Types::UNTYPED) if param.respond_to?(:name)
            end
          end

          node.body ? infer(node.body) : Types::NIL
        end
      end

      def infer_lambda(node)
        # Lambda is a Proc
        Types::ClassInstance.new(:Proc)
      end

      # Statements
      def infer_program(node)
        infer_statements(node.statements)
      end

      def infer_statements(node)
        return Types::NIL unless node&.body&.any?
        node.body.map { |stmt| infer(stmt) }.last
      end

      def infer_begin(node)
        result_type = node.statements ? infer_statements(node.statements) : Types::NIL

        if node.rescue_clause
          rescue_type = infer(node.rescue_clause)
          result_type = Types.union(result_type, rescue_type)
        end

        if node.ensure_clause
          infer(node.ensure_clause)
        end

        result_type
      end

      def infer_rescue(node)
        node.statements ? infer_statements(node.statements) : Types::NIL
      end

      def infer_ensure(node)
        node.statements ? infer_statements(node.statements) : Types::NIL
      end

      def infer_return(node)
        if node.arguments
          types = node.arguments.arguments.map { |arg| infer(arg) }
          types.size == 1 ? types.first : Types::Tuple.new(types)
        else
          Types::NIL
        end
      end

      def infer_yield(node)
        Types::UNTYPED  # Depends on block
      end

      def infer_break(node)
        Types::BOTTOM
      end

      def infer_next(node)
        Types::BOTTOM
      end

      def infer_parentheses(node)
        node.body ? infer(node.body) : Types::NIL
      end

      # Helpers
      def self_type
        @current_class ? Types::ClassInstance.new(@current_class.to_sym) : Types::UNTYPED
      end

      def rbs_type_to_internal(rbs_type)
        case rbs_type
        when RBS::Types::ClassInstance
          name = rbs_type.name.name
          args = rbs_type.args.map { |a| rbs_type_to_internal(a) }
          Types::ClassInstance.new(name, args)
        when RBS::Types::Bases::Void, RBS::Types::Bases::Nil
          Types::NIL
        when RBS::Types::Bases::Any
          Types::UNTYPED
        when RBS::Types::Bases::Bool
          Types::BOOL
        when RBS::Types::Union
          types = rbs_type.types.map { |t| rbs_type_to_internal(t) }
          Types.union(*types)
        when RBS::Types::Optional
          Types.optional(rbs_type_to_internal(rbs_type.type))
        when RBS::Types::Literal
          Types::Literal.new(rbs_type.literal)
        else
          Types::UNTYPED
        end
      end
    end
  end
end
