# frozen_string_literal: true

require "set"
require_relative "nodes"

module Konpeito
  module HIR
    # Simple wrapper to collect basic blocks for block bodies
    # Used as a temporary @current_function during block compilation
    class BlockBodyCollector
      attr_reader :body

      def initialize(body)
        @body = body
      end
    end

    # Builds HIR from TypedAST
    class Builder
      attr_reader :program

      def initialize(rbs_loader: nil)
        @program = Program.new
        @current_function = nil
        @current_block = nil
        @current_class = nil  # Current class context
        @current_class_def = nil  # Current ClassDef node being built
        @current_module = nil  # Current module context
        @block_counter = 0
        @var_counter = 0
        @local_vars = {}  # name -> LocalVar
        @instance_vars = {}  # class_name -> Set of ivar names
        @class_vars = {}  # class_name -> Set of cvar names (@@var)
        @rbs_loader = rbs_loader  # For NativeClass detection
        @native_class_vars = {}  # var_name -> NativeClassType (track native class assignments)
        @native_array_vars = {}  # var_name -> element_type (track NativeArray assignments)
        @extern_class_vars = {}  # var_name -> ExternClassType (track extern class assignments)
        @simd_class_vars = {}    # var_name -> SIMDClassType (track SIMD class assignments)
        @loop_stack = []         # Stack of { cond_label:, exit_label: } for break/next
        @current_visibility = :public  # Current method visibility in class body
        @instance_var_types = {}  # class_name -> { ivar_name -> field_tag } (HM-inferred)
      end

      def build(typed_ast)
        visit(typed_ast)
        @program
      end

      private

      def visit(typed_node)
        return nil unless typed_node

        method_name = :"visit_#{typed_node.node_type}"
        if respond_to?(method_name, true)
          send(method_name, typed_node)
        else
          visit_default(typed_node)
        end
      end

      # Known structural node types that safely pass through visit_default
      PASSTHROUGH_NODE_TYPES = Set.new(%i[
        statements program scope arguments required_parameter
      ]).freeze

      def visit_default(typed_node)
        # Warn about unhandled non-structural node types
        unless PASSTHROUGH_NODE_TYPES.include?(typed_node.node_type) || typed_node.children.any?
          loc = typed_node.node.location if typed_node.node.respond_to?(:location)
          if loc
            warn "[konpeito] warning: unsupported syntax '#{typed_node.node.class.name.split("::").last}' at line #{loc.start_line} (ignored)"
          end
        end

        # Process children and return last value
        result = nil
        typed_node.children.each do |child|
          result = visit(child)
        end
        result
      end

      def visit_alias_method(typed_node)
        # alias keyword outside class body - track on current class if in class context
        if @current_class_def
          new_name = extract_alias_name(typed_node.node.new_name)
          old_name = extract_alias_name(typed_node.node.old_name)
          @current_class_def.aliases << [new_name, old_name] if new_name && old_name
        end
        NilLit.new
      end

      def visit_defined(typed_node)
        node = typed_node.node
        value_node = node.value
        result_var = new_temp_var

        check_type, name = case value_node
        when Prism::LocalVariableReadNode
          [:local_variable, value_node.name.to_s]
        when Prism::ConstantReadNode
          [:constant, value_node.name.to_s]
        when Prism::ConstantPathNode
          [:constant, value_node.full_name]
        when Prism::GlobalVariableReadNode
          [:global_variable, value_node.name.to_s]
        when Prism::InstanceVariableReadNode
          [:instance_variable, value_node.name.to_s]
        when Prism::ClassVariableReadNode
          [:class_variable, value_node.name.to_s]
        when Prism::CallNode
          [:method, value_node.name.to_s]
        when Prism::NilNode
          [:expression, "nil"]
        when Prism::TrueNode
          [:expression, "true"]
        when Prism::FalseNode
          [:expression, "false"]
        when Prism::IntegerNode, Prism::FloatNode, Prism::StringNode, Prism::SymbolNode
          [:expression, "expression"]
        else
          [:expression, "expression"]
        end

        inst = DefinedCheck.new(
          check_type: check_type,
          name: name,
          type: TypeChecker::Types::UNTYPED,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      def visit_program(typed_node)
        # Create a main function for top-level code
        main_func = Function.new(
          name: "__main__",
          params: [],
          body: [],
          is_instance_method: false
        )

        with_function(main_func) do
          entry = new_block("entry")
          set_current_block(entry)

          result = visit(typed_node.children.first)  # statements

          # Add return if not already terminated
          unless @current_block.terminator
            @current_block.set_terminator(Return.new(value: result))
          end
        end

        @program.functions << main_func
      end

      def visit_statements(typed_node)
        result = nil
        typed_node.children.each do |child|
          result = visit(child)
        end
        result
      end

      def visit_def(typed_node)
        node = typed_node.node
        name = node.name.to_s

        # Extract typed parameter information from children
        params_typed_node = typed_node.children.find { |c| c.node_type == :parameters }
        param_types = extract_param_types(params_typed_node)

        # For NativeClass methods, use RBS method signature types instead of inference
        # Only apply when the class has actual native fields (not just methods)
        native_class_type = @current_class && @rbs_loader&.native_class_type(@current_class)
        method_sig = native_class_type&.methods&.[](name.to_sym)

        if native_class_type && method_sig && native_class_type.fields.any?
          # Override param_types with RBS method signature types
          param_types = build_native_method_param_types(node.parameters, method_sig)
        end

        params = []
        if node.parameters
          params = build_params(node.parameters, param_types)
        end

        # Extract source location for debug info
        func_location = SourceLocation.from_prism(node.location)

        func = Function.new(
          name: name,
          params: params,
          body: [],
          return_type: typed_node.type,
          is_instance_method: true,
          owner_class: @current_class,
          owner_module: @current_module,
          location: func_location
        )

        with_function(func) do
          entry = new_block("entry")
          set_current_block(entry)

          # Add parameters to local vars
          # native_class_type and method_sig are already looked up above
          params.each_with_index do |param, i|
            @local_vars[param.name] = LocalVar.new(name: param.name, type: param.type)

            # Track NativeClass parameters for field access detection
            native_type = resolve_native_class_type(param.type)

            # If not resolved from param.type, try looking up from method signature
            if native_type.nil? && method_sig
              param_type_sym = method_sig.param_types[i]
              if param_type_sym == :Self
                native_type = native_class_type
              elsif param_type_sym.is_a?(Symbol) && @rbs_loader&.native_class?(param_type_sym)
                native_type = @rbs_loader.native_class_type(param_type_sym)
              end
            end

            if native_type
              @native_class_vars[param.name] = native_type
            end
          end

          # Visit body
          body_child = typed_node.children.find { |c| c.node_type != :parameters }
          result = body_child ? visit(body_child) : NilLit.new

          unless @current_block.terminator
            @current_block.set_terminator(Return.new(value: result))
          end
        end

        @program.functions << func
        SymbolLit.new(value: name.to_sym)
      end

      # Extract parameter name -> type mapping from typed parameters node
      def extract_param_types(params_typed_node)
        return {} unless params_typed_node

        type_map = {}
        params_typed_node.children.each do |param_typed|
          param_node = param_typed.node
          if param_node.respond_to?(:name)
            type_map[param_node.name.to_s] = param_typed.type
          end
        end
        type_map
      end

      # Build param_types hash from RBS method signature for NativeClass methods
      # Converts NativeMethodType symbols (:Float64, :Int64) to internal type representations
      def build_native_method_param_types(params_node, method_sig)
        return {} unless params_node && method_sig

        type_map = {}
        param_names = []

        # Collect parameter names from the AST
        params_node.requireds&.each do |req|
          if req.respond_to?(:name)
            param_names << req.name.to_s
          end
        end

        params_node.optionals&.each do |opt|
          if opt.respond_to?(:name)
            param_names << opt.name.to_s
          end
        end

        # Map parameter names to their RBS types
        param_names.each_with_index do |name, i|
          next if i >= method_sig.param_types.size

          native_type = method_sig.param_types[i]
          type_map[name] = native_type_to_internal(native_type)
        end

        type_map
      end

      # Convert NativeMethodType type symbol to internal type representation
      def native_type_to_internal(native_type)
        case native_type
        when :Int64, :Integer
          TypeChecker::Types::INTEGER
        when :Float64, :Float
          TypeChecker::Types::FLOAT
        when :Bool
          TypeChecker::Types::BOOL
        when :String
          TypeChecker::Types::STRING
        when :Self
          # Return UNTYPED for now, the actual type will be resolved later
          TypeChecker::Types::UNTYPED
        when :Void
          TypeChecker::Types::NIL
        when Symbol
          # It's a reference to another NativeClass
          if @rbs_loader&.native_class?(native_type)
            TypeChecker::Types::ClassInstance.new(native_type)
          else
            TypeChecker::Types::UNTYPED
          end
        else
          TypeChecker::Types::UNTYPED
        end
      end

      def build_params(params_node, param_types = {})
        result = []

        params_node.requireds&.each do |req|
          if req.respond_to?(:name)
            param_name = req.name.to_s
            param_type = param_types[param_name] || TypeChecker::Types::UNTYPED
            result << Param.new(name: param_name, type: param_type)
          end
        end

        params_node.optionals&.each do |opt|
          if opt.respond_to?(:name)
            param_name = opt.name.to_s
            param_type = param_types[param_name] || TypeChecker::Types::UNTYPED
            result << Param.new(
              name: param_name,
              type: param_type,
              default_value: opt.value
            )
          end
        end

        if params_node.rest && params_node.rest.respond_to?(:name) && params_node.rest.name
          param_name = params_node.rest.name.to_s
          param_type = param_types[param_name] || TypeChecker::Types.array(TypeChecker::Types::UNTYPED)
          result << Param.new(
            name: param_name,
            type: param_type,
            rest: true
          )
        end

        params_node.keywords&.each do |kw|
          if kw.respond_to?(:name)
            param_name = kw.name.to_s
            param_type = param_types[param_name] || TypeChecker::Types::UNTYPED
            # OptionalKeywordParameterNode has value, RequiredKeywordParameterNode does not
            default_value = kw.respond_to?(:value) ? kw.value : nil
            result << Param.new(
              name: param_name,
              type: param_type,
              keyword: true,
              default_value: default_value
            )
          end
        end

        # Handle keyword_rest (**kwargs)
        if params_node.keyword_rest && params_node.keyword_rest.respond_to?(:name) && params_node.keyword_rest.name
          param_name = params_node.keyword_rest.name.to_s
          param_type = param_types[param_name] || TypeChecker::Types.hash(TypeChecker::Types::SYMBOL, TypeChecker::Types::UNTYPED)
          result << Param.new(
            name: param_name,
            type: param_type,
            keyword_rest: true
          )
        end

        if params_node.block && params_node.block.respond_to?(:name) && params_node.block.name
          param_name = params_node.block.name.to_s
          param_type = param_types[param_name] || TypeChecker::Types::ClassInstance.new(:Proc)
          result << Param.new(
            name: param_name,
            type: param_type,
            block: true
          )
        end

        result
      end

      # Known Ruby core classes that can be reopened
      RUBY_CORE_CLASSES = %w[
        Object String Integer Float Array Hash Symbol Regexp
        Numeric Comparable Enumerable Kernel IO File Dir
        Range NilClass TrueClass FalseClass Proc Method
        Thread Fiber Mutex ConditionVariable Queue SizedQueue
        Encoding ENV Process Signal
      ].to_set.freeze

      def visit_class(typed_node)
        node = typed_node.node
        name = extract_constant_name(node.constant_path)

        superclass = node.superclass ? extract_constant_name(node.superclass) : nil

        # Initialize instance vars tracking for this class
        @instance_vars[name] ||= Set.new

        # Check if this is reopening an existing class
        existing_class_def = @program.classes.find { |cd| cd.name == name }
        if existing_class_def
          # Merge into existing class definition
          class_def = existing_class_def
        else
          class_def = ClassDef.new(
            name: name,
            superclass: superclass,
            method_names: [],
            instance_vars: [],
            included_modules: [],
            extended_modules: [],
            prepended_modules: []
          )
          # Mark as reopened if it's a known Ruby core class
          class_def.reopened = true if RUBY_CORE_CLASSES.include?(name)
        end

        # Visit body within class context
        old_class = @current_class
        old_class_def = @current_class_def
        old_visibility = @current_visibility
        @current_class = name
        @current_class_def = class_def
        @current_visibility = :public

        if typed_node.children.any?
          body_child = typed_node.children.last
          if body_child&.node_type == :statements
            body_child.children.each do |child|
              if child.node_type == :def
                visit(child)
                method_name = child.node.name.to_s
                if singleton_method?(child)
                  class_def.singleton_methods << method_name unless class_def.singleton_methods.include?(method_name)
                  # Mark the FunctionDef as singleton (not instance) method
                  func = @program.functions.last
                  func.is_instance_method = false if func && func.name.to_s == method_name
                else
                  class_def.method_names << method_name unless class_def.method_names.include?(method_name)
                  # Track visibility
                  case @current_visibility
                  when :private
                    class_def.private_methods << method_name
                  when :protected
                    class_def.protected_methods << method_name
                  end
                end
              elsif child.node_type == :singleton_class
                # class << self - treat contained defs as singleton methods
                process_singleton_class_body(child, class_def)
              elsif visibility_modifier?(child)
                handle_visibility_modifier(child, class_def)
              elsif include_statement?(child)
                # Handle include statement
                module_name = extract_include_module_name(child)
                class_def.included_modules << module_name if module_name
              elsif extend_statement?(child)
                # Handle extend statement
                module_name = extract_include_module_name(child)
                class_def.extended_modules << module_name if module_name
              elsif prepend_statement?(child)
                # Handle prepend statement
                module_name = extract_include_module_name(child)
                class_def.prepended_modules << module_name if module_name
              elsif child.node_type == :alias_method
                # Handle alias keyword: alias new_name old_name
                new_name = extract_alias_name(child.node.new_name)
                old_name = extract_alias_name(child.node.old_name)
                class_def.aliases << [new_name, old_name] if new_name && old_name
              elsif alias_method_call?(child)
                # Handle alias_method :new_name, :old_name
                names = extract_alias_method_args(child)
                class_def.aliases << names if names
              elsif attr_reader_statement?(child)
                # Handle attr_reader - generate getter methods
                attr_names = extract_attr_reader_names(child)
                attr_names.each do |attr_name|
                  generate_attr_reader_method(attr_name, class_def)
                end
              elsif attr_writer_statement?(child)
                # Handle attr_writer - generate setter methods
                attr_names = extract_attr_reader_names(child)
                attr_names.each do |attr_name|
                  generate_attr_writer_method(attr_name, class_def)
                end
              elsif attr_accessor_statement?(child)
                # Handle attr_accessor - generate both getter and setter
                attr_names = extract_attr_reader_names(child)
                attr_names.each do |attr_name|
                  generate_attr_reader_method(attr_name, class_def)
                  generate_attr_writer_method(attr_name, class_def)
                end
              elsif child.node_type == :constant_write
                # Constant assignment in class body (e.g., PI = 3)
                const_name = child.node.name.to_s
                value_node = visit_literal_value(child.children.first)
                class_def.body_constants << [const_name, value_node]
              elsif child.node_type == :class_variable_write
                # Class variable initialization in class body (e.g., @@count = 0)
                cvar_name = child.node.name.to_s
                value_node = visit_literal_value(child.children.first)
                class_def.body_class_vars << [cvar_name, value_node]
                # Also track class variable for the class
                @class_vars[name] ||= Set.new
                @class_vars[name] << cvar_name
              else
                visit(child)
              end
            end
          end
        end

        @current_class = old_class
        @current_class_def = old_class_def
        @current_visibility = old_visibility

        # Collect instance variables found during class body processing
        class_def.instance_vars.concat(@instance_vars[name].to_a)

        # Propagate HM-inferred ivar types to ClassDef
        if @instance_var_types[name]
          @instance_var_types[name].each do |ivar_name, field_tag|
            next unless field_tag
            clean_name = ivar_name.sub(/^@/, "")
            class_def.instance_var_types[clean_name] = field_tag
          end
        end

        # Only add if not already in the list (reopened classes reuse existing)
        @program.classes << class_def unless existing_class_def
        NilLit.new
      end

      # Check if a node is an include statement
      def include_statement?(typed_node)
        return false unless typed_node.node_type == :call
        return false unless typed_node.node.name.to_s == "include"
        return false unless typed_node.node.receiver.nil?  # include is called without a receiver
        true
      end

      # Check if a node is an extend statement
      def extend_statement?(typed_node)
        return false unless typed_node.node_type == :call
        return false unless typed_node.node.name.to_s == "extend"
        return false unless typed_node.node.receiver.nil?
        true
      end

      # Check if a node is a prepend statement
      def prepend_statement?(typed_node)
        return false unless typed_node.node_type == :call
        return false unless typed_node.node.name.to_s == "prepend"
        return false unless typed_node.node.receiver.nil?
        true
      end

      # Check if a node is a visibility modifier (private/protected/public)
      def visibility_modifier?(typed_node)
        return false unless typed_node.node_type == :call
        name = typed_node.node.name.to_s
        return false unless %w[private protected public].include?(name)
        return false unless typed_node.node.receiver.nil?
        true
      end

      # Handle visibility modifier: bare form sets state, argument form marks specific methods
      def handle_visibility_modifier(typed_node, class_def)
        name = typed_node.node.name.to_s
        visibility = name.to_sym

        # Check if there are arguments (e.g., `private :foo, :bar`)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child&.children&.any?
          # Per-method form: mark specific methods
          args_child.children.each do |arg|
            method_name = if arg.node_type == :symbol
                            arg.node.value.to_s
                          elsif arg.node_type == :string
                            arg.node.unescaped.to_s
                          end
            next unless method_name

            case visibility
            when :private
              class_def.private_methods << method_name
              class_def.protected_methods.delete(method_name)
            when :protected
              class_def.protected_methods << method_name
              class_def.private_methods.delete(method_name)
            when :public
              class_def.private_methods.delete(method_name)
              class_def.protected_methods.delete(method_name)
            end
          end
        else
          # Bare form: set visibility for subsequent methods
          @current_visibility = visibility
        end
      end

      # Check if a node is an alias_method call
      def alias_method_call?(typed_node)
        return false unless typed_node.node_type == :call
        return false unless typed_node.node.name.to_s == "alias_method"
        return false unless typed_node.node.receiver.nil?
        true
      end

      # Extract name from alias keyword's SymbolNode/InterpolatedSymbolNode
      def extract_alias_name(node)
        if node.is_a?(Prism::SymbolNode)
          node.value.to_s
        else
          nil
        end
      end

      # Extract [new_name, old_name] from alias_method call arguments
      def extract_alias_method_args(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        return nil unless args_child&.children&.size&.>=(2)

        new_name_node = args_child.children[0]
        old_name_node = args_child.children[1]

        new_name = if new_name_node.node_type == :symbol
                     new_name_node.node.value.to_s
                   end
        old_name = if old_name_node.node_type == :symbol
                     old_name_node.node.value.to_s
                   end

        (new_name && old_name) ? [new_name, old_name] : nil
      end

      # Extract the module name from an include statement
      def extract_include_module_name(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        return nil unless args_child&.children&.any?

        first_arg = args_child.children.first
        return nil unless first_arg.node_type == :constant_read

        first_arg.node.name.to_s
      end

      # Check if a node is an attr_reader statement
      def attr_reader_statement?(typed_node)
        return false unless typed_node.node_type == :call
        return false unless typed_node.node.name.to_s == "attr_reader"
        return false unless typed_node.node.receiver.nil?
        true
      end

      # Check if a node is an attr_writer statement
      def attr_writer_statement?(typed_node)
        return false unless typed_node.node_type == :call
        return false unless typed_node.node.name.to_s == "attr_writer"
        return false unless typed_node.node.receiver.nil?
        true
      end

      # Check if a node is an attr_accessor statement
      def attr_accessor_statement?(typed_node)
        return false unless typed_node.node_type == :call
        return false unless typed_node.node.name.to_s == "attr_accessor"
        return false unless typed_node.node.receiver.nil?
        true
      end

      # Extract attribute names from attr_reader/attr_writer/attr_accessor
      def extract_attr_reader_names(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        return [] unless args_child&.children&.any?

        args_child.children.filter_map do |arg|
          next unless arg.node_type == :symbol
          arg.node.value.to_s
        end
      end

      # Generate a getter method for attr_reader
      def generate_attr_reader_method(attr_name, class_def)
        ivar_name = "@#{attr_name}"

        # Track instance variable
        @instance_vars[@current_class] ||= Set.new
        @instance_vars[@current_class] << ivar_name

        # Create a simple getter function
        func = Function.new(
          name: attr_name,
          params: [],
          body: [],
          return_type: TypeChecker::Types::UNTYPED,
          is_instance_method: true,
          owner_class: @current_class
        )

        with_function(func) do
          entry = new_block("entry")
          set_current_block(entry)

          # Load and return the instance variable
          result_var = new_temp_var
          inst = LoadInstanceVar.new(name: ivar_name, type: TypeChecker::Types::UNTYPED, result_var: result_var)
          emit(inst)

          @current_block.set_terminator(Return.new(value: inst))
        end

        @program.functions << func
        class_def.method_names << attr_name
      end

      # Generate a setter method for attr_writer
      def generate_attr_writer_method(attr_name, class_def)
        ivar_name = "@#{attr_name}"
        setter_name = "#{attr_name}="

        # Track instance variable
        @instance_vars[@current_class] ||= Set.new
        @instance_vars[@current_class] << ivar_name

        # Create a setter function with one parameter
        func = Function.new(
          name: setter_name,
          params: [Param.new(name: "value", type: TypeChecker::Types::UNTYPED)],
          body: [],
          return_type: TypeChecker::Types::UNTYPED,
          is_instance_method: true,
          owner_class: @current_class
        )

        with_function(func) do
          entry = new_block("entry")
          set_current_block(entry)

          # Add parameter to local vars
          @local_vars["value"] = LocalVar.new(name: "value", type: TypeChecker::Types::UNTYPED)

          # Load the parameter value
          result_var = new_temp_var
          load_inst = LoadLocal.new(
            var: @local_vars["value"],
            type: TypeChecker::Types::UNTYPED,
            result_var: result_var
          )
          emit(load_inst)

          # Store to instance variable
          store_inst = StoreInstanceVar.new(
            name: ivar_name,
            value: load_inst,
            type: TypeChecker::Types::UNTYPED
          )
          emit(store_inst)

          # Return the value
          @current_block.set_terminator(Return.new(value: load_inst))
        end

        @program.functions << func
        class_def.method_names << setter_name
      end

      def visit_module(typed_node)
        node = typed_node.node
        name = extract_constant_name(node.constant_path)

        method_names = []
        singleton_method_names = []
        module_constants = {}

        # Visit body within module context
        old_module = @current_module
        @current_module = name

        if typed_node.children.any?
          body_child = typed_node.children.last
          if body_child&.node_type == :statements
            body_child.children.each do |child|
              if child.node_type == :def
                visit(child)
                method_name = child.node.name.to_s
                # Check if this is a singleton method (def self.method)
                if singleton_method?(child)
                  singleton_method_names << method_name
                  # Mark the FunctionDef as singleton (not instance) method
                  func = @program.functions.last
                  func.is_instance_method = false if func && func.name.to_s == method_name
                else
                  method_names << method_name
                end
              elsif child.node_type == :singleton_class
                # class << self in module - collect singleton methods
                child.children.each do |sc_body|
                  next unless sc_body.node_type == :statements

                  sc_body.children.each do |sc_child|
                    if sc_child.node_type == :def
                      visit(sc_child)
                      singleton_method_names << sc_child.node.name.to_s
                    else
                      visit(sc_child)
                    end
                  end
                end
              elsif child.node_type == :constant_write
                # Handle constant assignment within module
                const_name = child.node.name.to_s
                module_constants[const_name] = visit_literal_value(child.children.first)
              elsif child.node_type == :class_variable_write
                # Handle class variable initialization within module
                # (modules can have class variables too)
                visit(child)
              else
                visit(child)
              end
            end
          end
        end

        @current_module = old_module

        module_def = ModuleDef.new(
          name: name,
          methods: method_names,
          singleton_methods: singleton_method_names,
          constants: module_constants
        )

        @program.modules << module_def
        NilLit.new
      end

      # Check if a def node is a singleton method (def self.method)
      def singleton_method?(typed_node)
        return false unless typed_node.node_type == :def
        receiver = typed_node.node.receiver
        receiver.is_a?(Prism::SelfNode)
      end

      # Process body of `class << self` - treat defs as singleton methods
      def process_singleton_class_body(typed_node, class_or_module_def)
        return unless typed_node.node.expression.is_a?(Prism::SelfNode)

        typed_node.children.each do |body_child|
          next unless body_child.node_type == :statements

          body_child.children.each do |child|
            if child.node_type == :def
              visit(child)
              method_name = child.node.name.to_s
              class_or_module_def.singleton_methods << method_name
            elsif attr_reader_statement?(child)
              attr_names = extract_attr_reader_names(child)
              attr_names.each do |attr_name|
                generate_attr_reader_method(attr_name, class_or_module_def)
                class_or_module_def.singleton_methods << attr_name
              end
            elsif attr_writer_statement?(child)
              attr_names = extract_attr_reader_names(child)
              attr_names.each do |attr_name|
                generate_attr_writer_method(attr_name, class_or_module_def)
                class_or_module_def.singleton_methods << "#{attr_name}="
              end
            elsif attr_accessor_statement?(child)
              attr_names = extract_attr_reader_names(child)
              attr_names.each do |attr_name|
                generate_attr_reader_method(attr_name, class_or_module_def)
                generate_attr_writer_method(attr_name, class_or_module_def)
                class_or_module_def.singleton_methods << attr_name
                class_or_module_def.singleton_methods << "#{attr_name}="
              end
            else
              visit(child)
            end
          end
        end
      end

      def extract_constant_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          parts = []
          current = node
          while current.is_a?(Prism::ConstantPathNode)
            parts.unshift(current.name.to_s)
            current = current.parent
          end
          parts.unshift(current.name.to_s) if current.respond_to?(:name)
          parts.join("::")
        else
          node.to_s
        end
      end

      def hm_type_to_field_tag(type)
        # Resolve TypeVars to their unified concrete types
        resolved = type
        if resolved.is_a?(TypeChecker::TypeVar)
          resolved = resolved.prune
        end
        case resolved
        when TypeChecker::Types::INTEGER then :Integer
        when TypeChecker::Types::FLOAT then :Float64
        when TypeChecker::Types::STRING then :String
        when TypeChecker::Types::BOOL then :Bool
        else
          # Check for parametric types (Array, Hash) and user-defined classes
          if resolved.is_a?(TypeChecker::Types::ClassInstance)
            case resolved.name
            when :Array then :Array
            when :Hash then :Hash
            else resolved.name.to_s  # User-defined class name (e.g., "Person")
            end
          else
            nil
          end
        end
      end

      # Literals
      def visit_integer(typed_node)
        result_var = new_temp_var
        inst = IntegerLit.new(value: typed_node.node.value, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_float(typed_node)
        result_var = new_temp_var
        inst = FloatLit.new(value: typed_node.node.value, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_string(typed_node)
        result_var = new_temp_var
        inst = StringLit.new(value: typed_node.node.unescaped, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_interpolated_string(typed_node)
        # Use typed_node.children which are properly typed versions of the parts
        parts = typed_node.children.map do |typed_part|
          case typed_part.node
          when Prism::StringNode
            result_var = new_temp_var
            inst = StringLit.new(value: typed_part.node.unescaped, result_var: result_var)
            emit(inst)
            inst
          when Prism::EmbeddedStatementsNode
            # Visit the embedded statements (which are typed children of the EmbeddedStatementsNode)
            expr_result = visit_embedded_statements(typed_part)
            next nil unless expr_result

            # Call to_s on the result to ensure it's a String
            result_var = new_temp_var
            inst = Call.new(
              receiver: expr_result,
              method_name: "to_s",
              args: [],
              type: TypeChecker::Types::STRING,
              result_var: result_var
            )
            emit(inst)
            inst
          end
        end.compact

        return nil if parts.empty?

        # If only one part, just return it
        if parts.size == 1
          return parts.first
        end

        # Concatenate all parts
        result_var = new_temp_var
        inst = StringConcat.new(parts: parts, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_embedded_statements(typed_embedded)
        # The typed_embedded contains a typed StatementsNode as its child
        return nil if typed_embedded.children.empty?

        # The first child is the typed StatementsNode
        typed_statements = typed_embedded.children.first
        return nil unless typed_statements

        # Visit each statement in the typed statements
        result = nil
        if typed_statements.children.any?
          typed_statements.children.each do |typed_stmt|
            result = visit(typed_stmt)
          end
        elsif typed_statements.node.is_a?(Prism::StatementsNode)
          # Fallback: if children are empty but node has body, the statements might be simple literals
          # that got typed but have no children themselves
          result = visit(typed_statements)
        end
        result
      end

      def visit_symbol(typed_node)
        result_var = new_temp_var
        inst = SymbolLit.new(value: typed_node.node.value, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_regular_expression(typed_node)
        node = typed_node.node
        # Calculate options from Prism flags
        options = 0
        options |= Regexp::IGNORECASE if node.ignore_case?
        options |= Regexp::EXTENDED if node.extended?
        options |= Regexp::MULTILINE if node.multi_line?

        result_var = new_temp_var
        inst = RegexpLit.new(
          pattern: node.unescaped,
          options: options,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      def visit_true(typed_node)
        result_var = new_temp_var
        inst = BoolLit.new(value: true, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_false(typed_node)
        result_var = new_temp_var
        inst = BoolLit.new(value: false, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_nil(typed_node)
        result_var = new_temp_var
        inst = NilLit.new(result_var: result_var)
        emit(inst)
        inst
      end

      def visit_array(typed_node)
        elements = typed_node.children.map { |child| visit(child) }
        result_var = new_temp_var

        element_type = if typed_node.type.is_a?(TypeChecker::Types::ClassInstance) &&
                          typed_node.type.type_args.any?
          typed_node.type.type_args.first
        else
          TypeChecker::Types::UNTYPED
        end

        inst = ArrayLit.new(
          elements: elements,
          element_type: element_type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      def visit_hash(typed_node)
        pairs = []
        typed_node.children.each do |child|
          if child.node_type == :assoc
            key = visit(child.children[0])
            value = visit(child.children[1])
            pairs << [key, value]
          end
        end

        result_var = new_temp_var
        inst = HashLit.new(pairs: pairs, result_var: result_var)
        emit(inst)
        inst
      end

      # Variables
      def visit_local_variable_read(typed_node)
        name = typed_node.node.name.to_s
        var = @local_vars[name] ||= LocalVar.new(name: name, type: typed_node.type)
        result_var = new_temp_var
        inst = LoadLocal.new(var: var, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      # it block parameter (Ruby 3.4+) - reads the implicit _it_param
      def visit_it_local_variable_read(typed_node)
        var = @local_vars["_it_param"] ||= LocalVar.new(name: "_it_param", type: typed_node.type)
        result_var = new_temp_var
        inst = LoadLocal.new(var: var, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_local_variable_write(typed_node)
        name = typed_node.node.name.to_s
        value = visit(typed_node.children.first)

        # Determine the actual type based on the assigned value
        actual_type = typed_node.type
        if value.is_a?(FiberNew)
          actual_type = TypeChecker::Types::FIBER
        elsif value.is_a?(ThreadNew)
          actual_type = TypeChecker::Types::THREAD
        elsif value.is_a?(MutexNew)
          actual_type = TypeChecker::Types::MUTEX
        elsif value.is_a?(QueueNew)
          actual_type = TypeChecker::Types::QUEUE
        elsif value.is_a?(ConditionVariableNew)
          actual_type = TypeChecker::Types::CONDITION_VARIABLE
        elsif value.is_a?(SizedQueueNew)
          actual_type = TypeChecker::Types::SIZED_QUEUE
        elsif value.is_a?(RactorNew)
          actual_type = TypeChecker::Types::RACTOR
        elsif value.is_a?(RactorPortNew)
          actual_type = TypeChecker::Types::RACTOR_PORT
        end

        var = @local_vars[name] ||= LocalVar.new(name: name, type: actual_type)
        # Update the type if this is a reassignment with a different type
        if var.type != actual_type
          var = LocalVar.new(name: name, type: actual_type)
          @local_vars[name] = var
        end

        inst = StoreLocal.new(var: var, value: value, type: actual_type)
        emit(inst)

        # Track NativeClass assignments for field access detection
        if value.is_a?(NativeNew)
          @native_class_vars[name] = value.class_type
        end

        # Track JSONParseAs results - they also produce NativeClass instances
        if value.is_a?(JSONParseAs)
          @native_class_vars[name] = value.target_class
        end

        # Track NativeArray assignments with element type
        if value.is_a?(NativeArrayAlloc)
          @native_array_vars[name] = value.element_type
        end

        # Track JSONParseArrayAs results as NativeArray
        if value.is_a?(JSONParseArrayAs)
          @native_array_vars[name] = value.element_class
        end

        # Also track Call results that return NativeArray types
        if value.is_a?(Call)
          element_type = extract_native_array_element_type(value.type)
          if element_type
            @native_array_vars[name] = element_type
          end
        end

        # Track ExternClass assignments
        if value.is_a?(ExternConstructorCall)
          @extern_class_vars[name] = value.extern_type
        end

        # Track SIMDClass assignments
        if value.is_a?(SIMDNew)
          @simd_class_vars[name] = value.simd_type
        end

        # Track ByteBuffer assignments
        if value.is_a?(ByteBufferAlloc)
          byte_buffer_vars[name] = true
        end

        # Track StringBuffer assignments
        if value.is_a?(StringBufferAlloc)
          string_buffer_vars[name] = true
        end

        # Track ByteSlice assignments
        if value.is_a?(ByteBufferSlice)
          byte_slice_vars[name] = true
        end

        # Track NativeString assignments
        if value.is_a?(NativeStringFromRuby) || value.is_a?(NativeStringByteSlice) || value.is_a?(NativeStringCharSlice)
          native_string_vars[name] = true
        end

        # Track StaticArray assignments
        if value.is_a?(StaticArrayAlloc)
          static_array_vars[name] = {
            element_type: value.element_type,
            size: value.size
          }
        end

        # Track Slice assignments
        if value.is_a?(SliceAlloc) || value.is_a?(SliceEmpty) || value.is_a?(ToSlice) ||
           value.is_a?(SliceSubslice) || value.is_a?(SliceCopyFrom) || value.is_a?(SliceFill)
          slice_vars[name] = { element_type: value.element_type }
        end

        # Track NativeHash assignments
        if value.is_a?(NativeHashAlloc) || value.is_a?(NativeHashClear)
          native_hash_vars[name] = { key_type: value.key_type, value_type: value.value_type }
        end

        value  # Assignment returns the value
      end

      def visit_instance_variable_read(typed_node)
        name = typed_node.node.name.to_s

        # Track instance variable for current class
        if @current_class
          @instance_vars[@current_class] ||= Set.new
          @instance_vars[@current_class] << name
        end

        result_var = new_temp_var
        inst = LoadInstanceVar.new(name: name, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_instance_variable_write(typed_node)
        name = typed_node.node.name.to_s

        # Track instance variable for current class
        if @current_class
          @instance_vars[@current_class] ||= Set.new
          @instance_vars[@current_class] << name

          # Collect HM-inferred ivar type
          if typed_node.type && typed_node.type != TypeChecker::Types::UNTYPED
            @instance_var_types[@current_class] ||= {}
            field_tag = hm_type_to_field_tag(typed_node.type)
            if field_tag
              existing = @instance_var_types[@current_class][name]
              if existing && existing != field_tag
                @instance_var_types[@current_class][name] = nil  # type conflict
              else
                @instance_var_types[@current_class][name] = field_tag
              end
            end
          end
        end

        value = visit(typed_node.children.first)
        inst = StoreInstanceVar.new(name: name, value: value, type: typed_node.type)
        emit(inst)
        value
      end

      def visit_class_variable_read(typed_node)
        name = typed_node.node.name.to_s  # e.g., "@@counter"

        # Track class variable for current class
        if @current_class
          @class_vars[@current_class] ||= Set.new
          @class_vars[@current_class] << name
        end

        result_var = new_temp_var
        inst = LoadClassVar.new(name: name, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_class_variable_write(typed_node)
        name = typed_node.node.name.to_s  # e.g., "@@counter"

        # Track class variable for current class
        if @current_class
          @class_vars[@current_class] ||= Set.new
          @class_vars[@current_class] << name
        end

        value = visit(typed_node.children.first)
        inst = StoreClassVar.new(name: name, value: value, type: typed_node.type)
        emit(inst)
        value
      end

      # Compound assignment operators

      def visit_local_variable_operator_write(typed_node)
        name = typed_node.node.name.to_s
        operator = typed_node.node.binary_operator.to_s

        # Load current value
        var = @local_vars[name] ||= LocalVar.new(name: name, type: typed_node.type)
        load_var = new_temp_var
        load_inst = LoadLocal.new(var: var, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        # Visit the RHS value
        rhs = visit(typed_node.children.first)

        # Call the operator method: x.+(rhs)
        call_var = new_temp_var
        call_inst = Call.new(
          receiver: load_inst,
          method_name: operator,
          args: [rhs],
          type: typed_node.type,
          result_var: call_var
        )
        emit(call_inst)

        # Store the result back
        store_inst = StoreLocal.new(var: var, value: call_inst, type: typed_node.type)
        emit(store_inst)
        call_inst
      end

      def visit_local_variable_or_write(typed_node)
        name = typed_node.node.name.to_s

        # Load current value
        var = @local_vars[name] ||= LocalVar.new(name: name, type: typed_node.type)
        load_var = new_temp_var
        load_inst = LoadLocal.new(var: var, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        # Short-circuit: if truthy, keep; if falsy, evaluate and assign RHS
        assign_block = new_block("or_write_assign")
        merge_block = new_block("or_write_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: load_inst,
          then_block: merge_block.label,
          else_block: assign_block.label
        ))

        # Assign block (current value is falsy)
        set_current_block(assign_block)
        rhs = visit(typed_node.children.first)
        store_inst = StoreLocal.new(var: var, value: rhs, type: typed_node.type)
        emit(store_inst)
        assign_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        # Merge
        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => load_inst,
            assign_exit_block.label => rhs
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_local_variable_and_write(typed_node)
        name = typed_node.node.name.to_s

        # Load current value
        var = @local_vars[name] ||= LocalVar.new(name: name, type: typed_node.type)
        load_var = new_temp_var
        load_inst = LoadLocal.new(var: var, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        # Short-circuit: if truthy, evaluate and assign RHS; if falsy, keep
        assign_block = new_block("and_write_assign")
        merge_block = new_block("and_write_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: load_inst,
          then_block: assign_block.label,
          else_block: merge_block.label
        ))

        # Assign block (current value is truthy)
        set_current_block(assign_block)
        rhs = visit(typed_node.children.first)
        store_inst = StoreLocal.new(var: var, value: rhs, type: typed_node.type)
        emit(store_inst)
        assign_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        # Merge
        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => load_inst,
            assign_exit_block.label => rhs
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_instance_variable_operator_write(typed_node)
        name = typed_node.node.name.to_s
        operator = typed_node.node.binary_operator.to_s

        if @current_class
          @instance_vars[@current_class] ||= Set.new
          @instance_vars[@current_class] << name
        end

        # Load current value
        load_var = new_temp_var
        load_inst = LoadInstanceVar.new(name: name, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        # Visit the RHS value
        rhs = visit(typed_node.children.first)

        # Call the operator method
        call_var = new_temp_var
        call_inst = Call.new(
          receiver: load_inst,
          method_name: operator,
          args: [rhs],
          type: typed_node.type,
          result_var: call_var
        )
        emit(call_inst)

        # Store the result back
        store_inst = StoreInstanceVar.new(name: name, value: call_inst, type: typed_node.type)
        emit(store_inst)
        call_inst
      end

      def visit_instance_variable_or_write(typed_node)
        name = typed_node.node.name.to_s

        if @current_class
          @instance_vars[@current_class] ||= Set.new
          @instance_vars[@current_class] << name
        end

        load_var = new_temp_var
        load_inst = LoadInstanceVar.new(name: name, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        assign_block = new_block("ivar_or_write_assign")
        merge_block = new_block("ivar_or_write_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: load_inst,
          then_block: merge_block.label,
          else_block: assign_block.label
        ))

        set_current_block(assign_block)
        rhs = visit(typed_node.children.first)
        store_inst = StoreInstanceVar.new(name: name, value: rhs, type: typed_node.type)
        emit(store_inst)
        assign_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => load_inst,
            assign_exit_block.label => rhs
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_instance_variable_and_write(typed_node)
        name = typed_node.node.name.to_s

        if @current_class
          @instance_vars[@current_class] ||= Set.new
          @instance_vars[@current_class] << name
        end

        load_var = new_temp_var
        load_inst = LoadInstanceVar.new(name: name, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        assign_block = new_block("ivar_and_write_assign")
        merge_block = new_block("ivar_and_write_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: load_inst,
          then_block: assign_block.label,
          else_block: merge_block.label
        ))

        set_current_block(assign_block)
        rhs = visit(typed_node.children.first)
        store_inst = StoreInstanceVar.new(name: name, value: rhs, type: typed_node.type)
        emit(store_inst)
        assign_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => load_inst,
            assign_exit_block.label => rhs
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_class_variable_operator_write(typed_node)
        name = typed_node.node.name.to_s
        operator = typed_node.node.binary_operator.to_s

        if @current_class
          @class_vars[@current_class] ||= Set.new
          @class_vars[@current_class] << name
        end

        load_var = new_temp_var
        load_inst = LoadClassVar.new(name: name, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        rhs = visit(typed_node.children.first)

        call_var = new_temp_var
        call_inst = Call.new(
          receiver: load_inst,
          method_name: operator,
          args: [rhs],
          type: typed_node.type,
          result_var: call_var
        )
        emit(call_inst)

        store_inst = StoreClassVar.new(name: name, value: call_inst, type: typed_node.type)
        emit(store_inst)
        call_inst
      end

      def visit_class_variable_or_write(typed_node)
        name = typed_node.node.name.to_s

        if @current_class
          @class_vars[@current_class] ||= Set.new
          @class_vars[@current_class] << name
        end

        load_var = new_temp_var
        load_inst = LoadClassVar.new(name: name, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        assign_block = new_block("cvar_or_write_assign")
        merge_block = new_block("cvar_or_write_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: load_inst,
          then_block: merge_block.label,
          else_block: assign_block.label
        ))

        set_current_block(assign_block)
        rhs = visit(typed_node.children.first)
        store_inst = StoreClassVar.new(name: name, value: rhs, type: typed_node.type)
        emit(store_inst)
        assign_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => load_inst,
            assign_exit_block.label => rhs
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_class_variable_and_write(typed_node)
        name = typed_node.node.name.to_s

        if @current_class
          @class_vars[@current_class] ||= Set.new
          @class_vars[@current_class] << name
        end

        load_var = new_temp_var
        load_inst = LoadClassVar.new(name: name, type: typed_node.type, result_var: load_var)
        emit(load_inst)

        assign_block = new_block("cvar_and_write_assign")
        merge_block = new_block("cvar_and_write_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: load_inst,
          then_block: assign_block.label,
          else_block: merge_block.label
        ))

        set_current_block(assign_block)
        rhs = visit(typed_node.children.first)
        store_inst = StoreClassVar.new(name: name, value: rhs, type: typed_node.type)
        emit(store_inst)
        assign_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => load_inst,
            assign_exit_block.label => rhs
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_constant_read(typed_node)
        name = typed_node.node.name.to_s
        result_var = new_temp_var
        inst = ConstantLookup.new(name: name, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_constant_path(typed_node)
        name = extract_constant_name(typed_node.node)
        result_var = new_temp_var
        inst = ConstantLookup.new(name: name, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_constant_write(typed_node)
        name = typed_node.node.name.to_s
        value = visit(typed_node.children.first)

        # Track Java:: path aliases for JVM interop
        if value.is_a?(ConstantLookup) && value.name.to_s.start_with?("Java::")
          @java_aliases ||= {}
          @java_aliases[name] = value.name.to_s
        end

        # Determine scope (module/class context)
        scope = @current_module || @current_class

        # Track top-level constants (scope == nil) for static Init registration in native backend.
        # __main__ is never called from Init, so top-level constants must be set explicitly.
        if scope.nil?
          literal_node = visit_literal_value(typed_node.children.first)
          @program.toplevel_constants << [name, literal_node]
        end

        inst = StoreConstant.new(name: name, value: value, scope: scope, type: typed_node.type)
        emit(inst)
        value
      end

      # Method call
      def visit_call(typed_node)
        node = typed_node.node

        # Check for NativeArray.new(size) pattern
        if native_array_new_call?(typed_node)
          return visit_native_array_new(typed_node)
        end

        # Check for NativeArray element access: arr[i] or arr[i]= for NativeArray[NativeClass]
        if native_array_element_access?(typed_node)
          return visit_native_array_element_access(typed_node)
        end

        # Check for NativeClass.new pattern
        if native_class_new_call?(typed_node)
          return visit_native_class_new(typed_node)
        end

        # Check for NativeClass field access (getter/setter)
        if native_class_field_access?(typed_node)
          return visit_native_class_field_access(typed_node)
        end

        # Check for NativeClass method call (not field access)
        if native_class_method_call?(typed_node)
          return visit_native_method_call(typed_node)
        end

        # Check for ByteBuffer.new(capacity) pattern
        if byte_buffer_new_call?(typed_node)
          return visit_byte_buffer_new(typed_node)
        end

        # Check for ByteBuffer method call ([], []=, <<, write, index_of, etc.)
        if byte_buffer_method_call?(typed_node)
          return visit_byte_buffer_method(typed_node)
        end

        # Check for StringBuffer.new(capacity) pattern
        if string_buffer_new_call?(typed_node)
          return visit_string_buffer_new(typed_node)
        end

        # Check for StringBuffer method call (<<, to_s, etc.)
        if string_buffer_method_call?(typed_node)
          return visit_string_buffer_method(typed_node)
        end

        # Check for KonpeitoJSON.parse_as(json, TargetClass) pattern
        if konpeito_json_parse_as_call?(typed_node)
          return visit_konpeito_json_parse_as(typed_node)
        end

        # Check for KonpeitoJSON.parse_array_as(json, ElementClass) pattern
        if konpeito_json_parse_array_as_call?(typed_node)
          return visit_konpeito_json_parse_array_as(typed_node)
        end

        # Check for NativeString.from(str) pattern
        if native_string_from_call?(typed_node)
          return visit_native_string_from(typed_node)
        end

        # Check for NativeString method call (byte_at, byte_length, etc.)
        if native_string_method_call?(typed_node)
          return visit_native_string_method(typed_node)
        end

        # Check for ByteSlice method call ([], length, to_s)
        if byte_slice_method_call?(typed_node)
          return visit_byte_slice_method(typed_node)
        end

        # Check for StaticArray.new call (e.g., StaticArray4Float.new)
        if static_array_new_call?(typed_node)
          return visit_static_array_new(typed_node)
        end

        # Check for StaticArray method call ([], []=, size)
        if static_array_method_call?(typed_node)
          return visit_static_array_method(typed_node)
        end

        # Check for Slice.new call (e.g., SliceInt64.new, SliceFloat64.new)
        if slice_new_call?(typed_node)
          return visit_slice_new(typed_node)
        end

        # Check for Slice.empty call
        if slice_empty_call?(typed_node)
          return visit_slice_empty(typed_node)
        end

        # Check for Slice method call ([], []=, size, subslice, copy_from, fill)
        if slice_method_call?(typed_node)
          return visit_slice_method(typed_node)
        end

        # Check for NativeArray/StaticArray to_slice conversion
        if to_slice_call?(typed_node)
          return visit_to_slice(typed_node)
        end

        # Check for NativeHash.new call (e.g., NativeHashStringInteger.new)
        if native_hash_new_call?(typed_node)
          return visit_native_hash_new(typed_node)
        end

        # Check for NativeHash method call ([], []=, size, has_key?, delete, clear, keys, values, each)
        if native_hash_method_call?(typed_node)
          return visit_native_hash_method(typed_node)
        end

        # Check for @cfunc annotated method call (direct C function call)
        if cfunc_method_call?(typed_node)
          return visit_cfunc_call(typed_node)
        end

        # Check for ExternClass constructor call
        if extern_class_constructor_call?(typed_node)
          return visit_extern_constructor_call(typed_node)
        end

        # Check for ExternClass instance method call
        if extern_class_method_call?(typed_node)
          return visit_extern_method_call(typed_node)
        end

        # Check for SIMDClass.new pattern
        if simd_class_new_call?(typed_node)
          return visit_simd_class_new(typed_node)
        end

        # Check for SIMDClass field access
        if simd_class_field_access?(typed_node)
          return visit_simd_field_access(typed_node)
        end

        # Check for SIMDClass method call
        if simd_class_method_call?(typed_node)
          return visit_simd_method_call(typed_node)
        end

        # Check for Fiber.new { ... } pattern
        if fiber_new_call?(typed_node)
          return visit_fiber_new(typed_node)
        end

        # Check for Fiber.yield(...) pattern
        if fiber_yield_call?(typed_node)
          return visit_fiber_yield(typed_node)
        end

        # Check for Fiber.current pattern
        if fiber_current_call?(typed_node)
          return visit_fiber_current(typed_node)
        end

        # Check for fiber.resume(...) pattern
        if fiber_resume_call?(typed_node)
          return visit_fiber_resume(typed_node)
        end

        # Check for fiber.alive? pattern
        if fiber_alive_call?(typed_node)
          return visit_fiber_alive(typed_node)
        end

        # Check for Thread.new { ... } pattern
        if thread_new_call?(typed_node)
          return visit_thread_new(typed_node)
        end

        # Check for Thread.current pattern
        if thread_current_call?(typed_node)
          return visit_thread_current(typed_node)
        end

        # Check for thread.join pattern
        if thread_join_call?(typed_node)
          return visit_thread_join(typed_node)
        end

        # Check for thread.value pattern
        if thread_value_call?(typed_node)
          return visit_thread_value(typed_node)
        end

        # Check for Mutex.new pattern
        if mutex_new_call?(typed_node)
          return visit_mutex_new(typed_node)
        end

        # Check for mutex.lock pattern
        if mutex_lock_call?(typed_node)
          return visit_mutex_lock(typed_node)
        end

        # Check for mutex.unlock pattern
        if mutex_unlock_call?(typed_node)
          return visit_mutex_unlock(typed_node)
        end

        # Check for mutex.synchronize { ... } pattern
        if mutex_synchronize_call?(typed_node)
          return visit_mutex_synchronize(typed_node)
        end

        # Check for Queue.new pattern
        if queue_new_call?(typed_node)
          return visit_queue_new(typed_node)
        end

        # Check for queue.push or queue.<< pattern
        if queue_push_call?(typed_node)
          return visit_queue_push(typed_node)
        end

        # Check for queue.pop pattern
        if queue_pop_call?(typed_node)
          return visit_queue_pop(typed_node)
        end

        # Check for ConditionVariable.new pattern
        if cv_new_call?(typed_node)
          return visit_cv_new(typed_node)
        end

        # Check for cv.wait(mutex) pattern
        if cv_wait_call?(typed_node)
          return visit_cv_wait(typed_node)
        end

        # Check for cv.signal pattern
        if cv_signal_call?(typed_node)
          return visit_cv_signal(typed_node)
        end

        # Check for cv.broadcast pattern
        if cv_broadcast_call?(typed_node)
          return visit_cv_broadcast(typed_node)
        end

        # Check for SizedQueue.new(max) pattern
        if sized_queue_new_call?(typed_node)
          return visit_sized_queue_new(typed_node)
        end

        # Check for sized_queue.push pattern
        if sized_queue_push_call?(typed_node)
          return visit_sized_queue_push(typed_node)
        end

        # Check for sized_queue.pop pattern
        if sized_queue_pop_call?(typed_node)
          return visit_sized_queue_pop(typed_node)
        end

        # Check for Ractor.new { ... } pattern
        if ractor_new_call?(typed_node)
          return visit_ractor_new(typed_node)
        end

        # Check for Ractor.receive pattern
        if ractor_receive_call?(typed_node)
          return visit_ractor_receive(typed_node)
        end

        # Check for Ractor.current pattern
        if ractor_current_call?(typed_node)
          return visit_ractor_current(typed_node)
        end

        # Check for Ractor.main pattern
        if ractor_main_call?(typed_node)
          return visit_ractor_main(typed_node)
        end

        # Check for Ractor.select pattern
        if ractor_select_call?(typed_node)
          return visit_ractor_select(typed_node)
        end

        # Check for Ractor.make_shareable pattern
        if ractor_make_sharable_call?(typed_node)
          return visit_ractor_make_sharable(typed_node)
        end

        # Check for Ractor.shareable? pattern
        if ractor_sharable_call?(typed_node)
          return visit_ractor_sharable(typed_node)
        end

        # Check for Ractor[:key] pattern
        if ractor_local_get_call?(typed_node)
          return visit_ractor_local_get(typed_node)
        end

        # Check for Ractor[:key] = value pattern
        if ractor_local_set_call?(typed_node)
          return visit_ractor_local_set(typed_node)
        end

        # Check for ractor.send / ractor << msg pattern
        if ractor_send_call?(typed_node)
          return visit_ractor_send(typed_node)
        end

        # Check for ractor.join pattern
        if ractor_join_call?(typed_node)
          return visit_ractor_join(typed_node)
        end

        # Check for ractor.value pattern
        if ractor_value_call?(typed_node)
          return visit_ractor_value(typed_node)
        end

        # Check for ractor.close pattern
        if ractor_close_call?(typed_node)
          return visit_ractor_close(typed_node)
        end

        # Check for ractor.name pattern
        if ractor_name_call?(typed_node)
          return visit_ractor_name(typed_node)
        end

        # Check for ractor.monitor(port) pattern
        if ractor_monitor_call?(typed_node)
          return visit_ractor_monitor(typed_node)
        end

        # Check for ractor.unmonitor(port) pattern
        if ractor_unmonitor_call?(typed_node)
          return visit_ractor_unmonitor(typed_node)
        end

        # Check for Ractor::Port.new pattern
        if ractor_port_new_call?(typed_node)
          return visit_ractor_port_new(typed_node)
        end

        # Check for port.send / port << msg pattern
        if ractor_port_send_call?(typed_node)
          return visit_ractor_port_send(typed_node)
        end

        # Check for port.receive pattern
        if ractor_port_receive_call?(typed_node)
          return visit_ractor_port_receive(typed_node)
        end

        # Check for port.close pattern
        if ractor_port_close_call?(typed_node)
          return visit_ractor_port_close(typed_node)
        end

        # String literal constant folding: "a" + "b" => "ab"
        if string_literal_concat?(typed_node)
          return fold_string_literals(typed_node)
        end

        # String concatenation chain optimization: a + b + c + d
        # Only optimize chains of 3 or more (2 elements are handled efficiently by rb_str_plus)
        if (concat_parts = detect_string_concat_chain(typed_node))
          return emit_string_concat_chain(concat_parts)
        end

        # Get receiver
        receiver = if typed_node.children.any? && typed_node.children.first.node.is_a?(Prism::Node) &&
                      !typed_node.children.first.node.is_a?(Prism::ArgumentsNode) &&
                      !typed_node.children.first.node.is_a?(Prism::BlockNode)
          visit(typed_node.children.first)
        else
          SelfRef.new(type: TypeChecker::Types::UNTYPED)
        end

        # Get arguments and keyword arguments
        args = []
        keyword_args = {}
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            # Check if this is a keyword hash argument
            if arg.node.is_a?(Prism::KeywordHashNode)
              # Extract keyword arguments from the hash
              # arg.children are typed AssocNode wrappers; each has children[0]=key, children[1]=value
              arg.node.elements.each_with_index do |elem, ei|
                if elem.is_a?(Prism::AssocNode) && elem.key.is_a?(Prism::SymbolNode)
                  key_name = elem.key.unescaped.to_sym
                  # Navigate through the typed AssocNode to get the typed value child
                  typed_assoc = arg.children[ei]
                  if typed_assoc && typed_assoc.children && typed_assoc.children.size >= 2
                    value_typed = typed_assoc.children[1]
                    keyword_args[key_name] = visit(value_typed)
                  else
                    # Fallback: create typed node for the value
                    keyword_args[key_name] = visit_node_directly(elem.value)
                  end
                end
              end
            elsif arg.node.is_a?(Prism::SplatNode)
              # Splat argument at call site
              inner = arg.children.first
              expr = inner ? visit(inner) : NilLit.new
              result_var = new_temp_var
              splat = SplatArg.new(expression: expr, type: arg.type, result_var: result_var)
              emit(splat)
              args << splat
            else
              args << visit(arg)
            end
          end
        end

        # Get block
        block = nil
        block_child = typed_node.children.find { |c| c.node_type == :block }
        if block_child
          block = visit_block_def(block_child)
        end

        # Handle &blk block argument reference (e.g., arr.map(&blk)) or
        # &:symbol Symbol#to_proc (e.g., arr.map(&:upcase))
        unless block
          block_arg_child = typed_node.children.find { |c| c.node_type == :block_argument }
          if block_arg_child
            blk_node = block_arg_child.node
            if blk_node.respond_to?(:expression) && blk_node.expression
              expr = blk_node.expression

              if expr.is_a?(Prism::SymbolNode)
                # &:method_name — Symbol#to_proc: create { |x| x.method_name }
                sym_method = expr.value.to_s
                param_name = "__sym_proc_param"
                param = Param.new(name: param_name, type: TypeChecker::Types::UNTYPED)
                param_var = LocalVar.new(name: param_name, type: TypeChecker::Types::UNTYPED)
                param_load = LoadLocal.new(var: param_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
                call_inst = Call.new(
                  receiver: param_load,
                  method_name: sym_method,
                  args: [],
                  type: TypeChecker::Types::UNTYPED,
                  result_var: new_temp_var
                )
                bb = BasicBlock.new(label: "sym_proc_body")
                bb.add_instruction(param_load)
                bb.add_instruction(call_inst)
                block = BlockDef.new(
                  params: [param],
                  body: [bb],
                  captures: []
                )
              else
                blk_name = expr.name.to_s
                # Create a wrapper BlockDef: { |__block_arg_param| blk.call(__block_arg_param) }
                # Load blk from captures inside the block body (not from outer scope)
                param_name = "__block_arg_param"
                param = Param.new(name: param_name, type: TypeChecker::Types::UNTYPED)
                param_var = LocalVar.new(name: param_name, type: TypeChecker::Types::UNTYPED)
                param_load = LoadLocal.new(var: param_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
                blk_local_var = LocalVar.new(name: blk_name, type: TypeChecker::Types::UNTYPED)
                blk_load = LoadLocal.new(var: blk_local_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
                call_inst = Call.new(
                  receiver: blk_load,
                  method_name: "call",
                  args: [param_load],
                  type: TypeChecker::Types::UNTYPED,
                  result_var: new_temp_var
                )
                # Wrap in a BasicBlock (BlockDef.body expects Array[BasicBlock])
                bb = BasicBlock.new(label: "block_arg_body")
                bb.add_instruction(blk_load)
                bb.add_instruction(param_load)
                bb.add_instruction(call_inst)
                block = BlockDef.new(
                  params: [param],
                  body: [bb],
                  captures: [Capture.new(name: blk_name, type: TypeChecker::Types::UNTYPED)]
                )
              end
            end
          end
        end

        result_var = new_temp_var
        is_safe_nav = node.respond_to?(:safe_navigation?) && node.safe_navigation?
        inst = Call.new(
          receiver: receiver,
          method_name: node.name.to_s,
          args: args,
          block: block,
          keyword_args: keyword_args,
          type: typed_node.type,
          result_var: result_var,
          safe_navigation: is_safe_nav
        )
        emit(inst)
        inst
      end

      # Visit a raw Prism node when typed node is not available
      def visit_node_directly(node)
        case node
        when Prism::IntegerNode
          result_var = new_temp_var
          inst = IntegerLit.new(value: node.value, result_var: result_var)
          emit(inst)
          inst
        when Prism::FloatNode
          result_var = new_temp_var
          inst = FloatLit.new(value: node.value, result_var: result_var)
          emit(inst)
          inst
        when Prism::StringNode
          result_var = new_temp_var
          inst = StringLit.new(value: node.unescaped, result_var: result_var)
          emit(inst)
          inst
        when Prism::SymbolNode
          result_var = new_temp_var
          inst = SymbolLit.new(value: node.unescaped, result_var: result_var)
          emit(inst)
          inst
        when Prism::NilNode
          result_var = new_temp_var
          inst = NilLit.new(result_var: result_var)
          emit(inst)
          inst
        when Prism::TrueNode
          result_var = new_temp_var
          inst = BoolLit.new(value: true, result_var: result_var)
          emit(inst)
          inst
        when Prism::FalseNode
          result_var = new_temp_var
          inst = BoolLit.new(value: false, result_var: result_var)
          emit(inst)
          inst
        else
          # For complex nodes, create a typed node wrapper and visit normally
          # This is a fallback and may not work for all cases
          NilLit.new(result_var: new_temp_var)
        end
      end

      # Check if this is a NativeArray.new(size) call
      # We detect by name pattern since type inference may not have resolved NativeArrayType yet
      def native_array_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is NativeArray constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "NativeArray"
      end

      # Check if this is a NativeArray element access: arr[i] where arr is NativeArray[NativeClass]
      def native_array_element_access?(typed_node)
        method_name = typed_node.node.name.to_s
        return false unless method_name == "[]" || method_name == "[]="

        # Check if receiver is a local variable that's a NativeArray
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        element_type = @native_array_vars[var_name]

        # Only handle NativeArray[NativeClass] here
        # Primitive arrays are handled in LLVM generator
        element_type.is_a?(TypeChecker::Types::NativeClassType)
      end

      # Handle NativeArray element access for NativeClass elements
      def visit_native_array_element_access(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        element_type = @native_array_vars[var_name]

        # Visit the array receiver to get the array reference
        array_ref = visit(receiver_child)

        # Get the index argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        index_arg = args_child && args_child.children.any? ? visit(args_child.children.first) : IntegerLit.new(value: 0)

        method_name = typed_node.node.name.to_s

        if method_name == "[]"
          # arr[i] - return pointer to element
          result_var = new_temp_var
          inst = NativeArrayGet.new(
            array: array_ref,
            index: index_arg,
            element_type: element_type,
            result_var: result_var
          )
          emit(inst)
          inst
        else
          # arr[i]= - set element (for NativeClass, this would copy the struct)
          # For now, we don't support arr[i] = point (copying structs)
          # Users should use arr[i].x = value instead
          raise NotImplementedError, "NativeArray[NativeClass] assignment not supported. Use arr[i].field = value instead."
        end
      end

      # Handle NativeArray.new(size) allocation
      def visit_native_array_new(typed_node)
        # Determine element type from the type if available
        element_type = extract_native_array_element_type(typed_node.type) ||
                       extract_native_array_element_type(@current_function&.return_type) ||
                       extract_native_array_element_from_rbs ||
                       infer_native_class_element_from_context ||
                       :Float64  # Default to Float64

        # Get size argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        size_arg = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          # Default size of 0 if not specified
          IntegerLit.new(value: 0, result_var: new_temp_var).tap { |lit| emit(lit) }
        end

        result_var = new_temp_var
        inst = NativeArrayAlloc.new(
          size: size_arg,
          element_type: element_type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Check if this is a NativeClass.new call
      # Native-first: All classes with field definitions are native unless @boxed
      def native_class_new_call?(typed_node)
        return false unless @rbs_loader
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is a constant that's a registered NativeClass
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        class_name = receiver_child.node.name.to_s

        # @boxed classes use VALUE path (not native)
        return false if @rbs_loader.boxed_class?(class_name)

        @rbs_loader.native_class?(class_name)
      end

      # Handle NativeClass.new allocation
      def visit_native_class_new(typed_node)
        receiver_child = typed_node.children.first
        class_name = receiver_child.node.name.to_s
        class_type = @rbs_loader.native_class_type(class_name)

        # Collect constructor arguments from the arguments node
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            args << visit(arg)
          end
        end

        result_var = new_temp_var
        inst = NativeNew.new(
          class_type: class_type,
          result_var: result_var,
          args: args
        )
        emit(inst)

        inst
      end

      # Check if this is a NativeClass field access
      def native_class_field_access?(typed_node)
        return false unless @rbs_loader

        # If the call has a block argument, it's a method call, not a field access
        block_child = typed_node.children.find { |c| c.node_type == :block }
        return false if block_child

        # If the call has explicit arguments (not setter), it's a method call
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        method_name = typed_node.node.name.to_s
        if args_child && !method_name.end_with?("=")
          return false
        end

        # Get the receiver and try to resolve its native class type
        receiver_child = typed_node.children.first
        native_class_type = resolve_native_class_type_from_receiver(receiver_child)
        return false unless native_class_type

        # Check if the method name matches a field name
        field_name = method_name.chomp("=")  # Remove = suffix for setters

        native_class_type.field_type(field_name) != nil
      end

      # Resolve NativeClassType from a receiver node
      def resolve_native_class_type_from_receiver(receiver_child)
        return nil unless receiver_child

        # First, check if receiver is a local variable that was assigned from NativeClass.new
        if receiver_child.node_type == :local_variable_read
          var_name = receiver_child.node.name.to_s
          if @native_class_vars[var_name]
            return @native_class_vars[var_name]
          end
        end

        # Check if receiver is a NativeArray element access: arr[i]
        # If arr is NativeArray[NativeClass], then arr[i] returns a NativeClass
        if receiver_child.node_type == :call && receiver_child.node.name.to_s == "[]"
          array_receiver = receiver_child.children.first
          if array_receiver&.node_type == :local_variable_read
            array_var_name = array_receiver.node.name.to_s
            element_type = @native_array_vars[array_var_name]
            if element_type.is_a?(TypeChecker::Types::NativeClassType)
              return element_type
            end
          end
        end

        # Then check the type from TypedAST
        receiver_type = receiver_child.type
        resolve_native_class_type(receiver_type)
      end

      # Resolve a type to NativeClassType if applicable
      # Native-first: Excludes @boxed classes
      def resolve_native_class_type(type)
        return type if type.is_a?(TypeChecker::Types::NativeClassType)

        # Check if it's a ClassInstance that's actually a NativeClass
        if type.is_a?(TypeChecker::Types::ClassInstance)
          # @boxed classes use VALUE path (not native)
          return nil if @rbs_loader&.boxed_class?(type.name)

          if @rbs_loader&.native_class?(type.name)
            return @rbs_loader.native_class_type(type.name)
          end
        end

        nil
      end

      # Extract element type from a NativeArray type
      # Returns the element type (Symbol like :Float64 or NativeClassType), or nil if not NativeArray
      def extract_native_array_element_type(type)
        return nil unless type

        # Direct NativeArrayType
        if type.is_a?(TypeChecker::Types::NativeArrayType)
          return type.element_type
        end

        # ClassInstance for NativeArray with type args
        if type.is_a?(TypeChecker::Types::ClassInstance) && type.name == :NativeArray
          if type.type_args.any?
            elem_type = type.type_args.first
            # Check if element is a NativeClass
            if elem_type.is_a?(TypeChecker::Types::ClassInstance) && @rbs_loader&.native_class?(elem_type.name)
              return @rbs_loader.native_class_type(elem_type.name)
            elsif elem_type.is_a?(TypeChecker::Types::NativeClassType)
              return elem_type
            elsif elem_type.is_a?(TypeChecker::Types::ClassInstance)
              # Map standard types
              case elem_type.name
              when :Float then :Float64
              when :Integer then :Int64
              else nil
              end
            end
          end
        end

        nil
      end

      # Extract element type from RBS return type of NativeArray.new
      # Falls back to checking the RBS `self.new` return type when HM inferrer
      # doesn't propagate type_args on ClassInstance(:NativeArray)
      def extract_native_array_element_from_rbs
        return nil unless @rbs_loader

        method_types = @rbs_loader.method_type_direct(:NativeArray, :new, singleton: true)
        return nil unless method_types&.any?

        method_types.each do |mt|
          ret_type = mt.type.return_type
          if ret_type.is_a?(RBS::Types::ClassInstance) && ret_type.name.name.to_s == "NativeArray"
            if ret_type.args.any?
              arg = ret_type.args.first
              if arg.is_a?(RBS::Types::ClassInstance)
                case arg.name.name.to_s
                when "Integer" then return :Int64
                when "Float" then return :Float64
                else
                  # Check if it's a NativeClass
                  class_name = arg.name.name.to_sym
                  if @rbs_loader.native_class?(class_name)
                    return @rbs_loader.native_class_type(class_name)
                  end
                end
              end
            end
          end
        end

        nil
      end

      # Infer NativeClass element type from context
      # If there's exactly one @native class available, use it as the element type
      # This is a simple heuristic for when type info is not available
      def infer_native_class_element_from_context
        return nil unless @rbs_loader

        native_classes = @rbs_loader.native_classes
        return nil if native_classes.empty?

        # If there's exactly one native class, use it
        if native_classes.size == 1
          return native_classes.values.first
        end

        # Multiple native classes - can't decide without more context
        nil
      end

      # Handle NativeClass field access (getter or setter)
      def visit_native_class_field_access(typed_node)
        receiver_child = typed_node.children.first
        receiver = visit(receiver_child)
        native_class_type = resolve_native_class_type_from_receiver(receiver_child)
        method_name = typed_node.node.name.to_s

        if method_name.end_with?("=")
          # Setter: point.x = value
          field_name = method_name.chomp("=")
          args_child = typed_node.children.find { |c| c.node_type == :arguments }
          value = args_child && args_child.children.any? ? visit(args_child.children.first) : NilLit.new

          inst = NativeFieldSet.new(
            object: receiver,
            field_name: field_name,
            value: value,
            class_type: native_class_type
          )
          emit(inst)
          inst
        else
          # Getter: point.x
          result_var = new_temp_var
          inst = NativeFieldGet.new(
            object: receiver,
            field_name: method_name,
            class_type: native_class_type,
            result_var: result_var
          )
          emit(inst)
          inst
        end
      end

      # Check if this is a NativeClass method call (not field access)
      def native_class_method_call?(typed_node)
        return false unless @rbs_loader

        # If the call has a block argument, fall through to generic visit_call
        # which handles blocks properly (NativeMethodCall doesn't support blocks)
        block_child = typed_node.children.find { |c| c.node_type == :block }
        return false if block_child

        # Get the receiver and try to resolve its native class type
        receiver_child = typed_node.children.first
        native_class_type = resolve_native_class_type_from_receiver(receiver_child)
        return false unless native_class_type

        # Get method name (excluding setters which are handled as field access)
        method_name = typed_node.node.name.to_s
        return false if method_name.end_with?("=")

        # Make sure it's not a field getter
        return false if native_class_type.field_type(method_name)

        # Check if method exists on this class or its superclasses
        native_classes_registry = @rbs_loader.native_classes
        method_sig = native_class_type.lookup_method(method_name, native_classes_registry)
        method_sig != nil
      end

      # Check if this is a @cfunc annotated method call
      # Format: ClassName.method_name(args)
      # Requires @cfunc annotation in RBS
      def cfunc_method_call?(typed_node)
        return false unless @rbs_loader
        return false unless typed_node.node.respond_to?(:name)

        method_name = typed_node.node.name.to_sym

        # Get receiver to determine class name
        receiver_child = typed_node.children.first
        return false unless receiver_child

        # Check if receiver is a constant reference (singleton call)
        class_name = extract_class_name_from_receiver(receiver_child)
        return false unless class_name

        # Check if this method is a cfunc
        @rbs_loader.cfunc_method?(class_name, method_name, singleton: true)
      end

      # Extract class name from a receiver node (for constant references like FastMath.sin)
      def extract_class_name_from_receiver(receiver_node)
        return nil unless receiver_node

        case receiver_node.node
        when Prism::ConstantReadNode
          receiver_node.node.name.to_sym
        when Prism::ConstantPathNode
          # Handle nested constants like Foo::Bar
          receiver_node.node.full_name.to_sym
        else
          nil
        end
      end

      # Visit a @cfunc method call and generate CFuncCall instruction
      def visit_cfunc_call(typed_node)
        method_name = typed_node.node.name.to_sym
        receiver_child = typed_node.children.first
        class_name = extract_class_name_from_receiver(receiver_child)

        # Get CFuncType from RBS loader
        cfunc_type = @rbs_loader.cfunc_method(class_name, method_name, singleton: true)

        # Get arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            args << visit(arg)
          end
        end

        result_var = new_temp_var
        inst = CFuncCall.new(
          c_func_name: cfunc_type.c_func_name,
          args: args,
          cfunc_type: cfunc_type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # ExternClass methods
      # ========================================

      # Check if this is an ExternClass constructor call: ExternClass.method()
      def extern_class_constructor_call?(typed_node)
        return false unless @rbs_loader
        return false unless typed_node.node.respond_to?(:name)

        method_name = typed_node.node.name.to_sym

        # Get receiver to determine class name
        receiver_child = typed_node.children.first
        return false unless receiver_child

        # Check if receiver is a constant reference
        class_name = extract_class_name_from_receiver(receiver_child)
        return false unless class_name

        # Check if this class is an extern class
        return false unless @rbs_loader.extern_class?(class_name)

        # Check if this method is a constructor
        extern_type = @rbs_loader.extern_class_type(class_name)
        extern_type.constructor?(method_name)
      end

      # Check if this is an ExternClass instance method call
      def extern_class_method_call?(typed_node)
        return false unless @rbs_loader
        return false unless typed_node.node.respond_to?(:name)

        # Get receiver
        receiver_child = typed_node.children.first
        return false unless receiver_child

        # Check if receiver is a local variable that's an extern class
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        @extern_class_vars.key?(var_name)
      end

      # Visit ExternClass constructor call
      def visit_extern_constructor_call(typed_node)
        method_name = typed_node.node.name.to_sym
        receiver_child = typed_node.children.first
        class_name = extract_class_name_from_receiver(receiver_child)

        extern_type = @rbs_loader.extern_class_type(class_name)
        method_sig = extern_type.lookup_method(method_name)

        # Get arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            args << visit(arg)
          end
        end

        result_var = new_temp_var
        inst = ExternConstructorCall.new(
          extern_type: extern_type,
          c_func_name: method_sig.c_func_name,
          args: args,
          method_sig: method_sig,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ExternClass instance method call
      def visit_extern_method_call(typed_node)
        method_name = typed_node.node.name.to_sym

        # Get receiver
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        extern_type = @extern_class_vars[var_name]

        receiver = visit(receiver_child)
        method_sig = extern_type.lookup_method(method_name)

        # Get arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            args << visit(arg)
          end
        end

        result_var = new_temp_var
        inst = ExternMethodCall.new(
          receiver: receiver,
          c_func_name: method_sig.c_func_name,
          args: args,
          extern_type: extern_type,
          method_sig: method_sig,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # ByteBuffer methods
      # ========================================

      # Track ByteBuffer variables
      def byte_buffer_vars
        @byte_buffer_vars ||= {}
      end

      # Check if this is a ByteBuffer.new(capacity) call
      def byte_buffer_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "ByteBuffer"
      end

      # Check if this is a ByteBuffer method call
      def byte_buffer_method_call?(typed_node)
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        byte_buffer_vars.key?(var_name)
      end

      # Handle ByteBuffer.new(capacity)
      def visit_byte_buffer_new(typed_node)
        # Get capacity argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        capacity = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          IntegerLit.new(value: 256, result_var: new_temp_var).tap { |lit| emit(lit) }
        end

        result_var = new_temp_var
        inst = ByteBufferAlloc.new(capacity: capacity, result_var: result_var)
        emit(inst)
        inst
      end

      # Handle ByteBuffer method calls ([], []=, <<, write, index_of, to_s, length)
      def visit_byte_buffer_method(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        buffer = visit(receiver_child)

        method_name = typed_node.node.name.to_s
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        args = args_child ? args_child.children.map { |c| visit(c) } : []

        result_var = new_temp_var

        case method_name
        when "[]"
          # buf[index] -> byte
          index = args.first || IntegerLit.new(value: 0)
          inst = ByteBufferGet.new(buffer: buffer, index: index, result_var: result_var)
          emit(inst)
          inst

        when "[]="
          # buf[index] = byte
          index = args[0] || IntegerLit.new(value: 0)
          byte = args[1] || IntegerLit.new(value: 0)
          inst = ByteBufferSet.new(buffer: buffer, index: index, byte: byte)
          emit(inst)
          inst

        when "<<", "write"
          # buf << byte or buf << string or buf.write(string)
          value = args.first
          # Determine append type from the value type
          append_type = case value
          when StringLit then :string
          when IntegerLit then :byte
          else
            # Check the typed node's argument type
            arg_type = args_child&.children&.first&.type
            if arg_type == TypeChecker::Types::STRING
              :string
            elsif arg_type == TypeChecker::Types::INTEGER
              :byte
            elsif arg_type.is_a?(TypeChecker::Types::ByteBufferType)
              :buffer
            else
              :string  # Default to string
            end
          end
          inst = ByteBufferAppend.new(buffer: buffer, value: value, append_type: append_type, result_var: result_var)
          emit(inst)
          inst

        when "write_bytes"
          # buf.write_bytes(other_buffer)
          other_buffer = args.first
          inst = ByteBufferAppend.new(buffer: buffer, value: other_buffer, append_type: :buffer, result_var: result_var)
          emit(inst)
          inst

        when "index_of"
          # buf.index_of(byte) or buf.index_of(byte, start_offset)
          pattern = args.first
          start_offset = args[1]
          inst = ByteBufferIndexOf.new(
            buffer: buffer,
            pattern: pattern,
            search_type: :byte,
            start_offset: start_offset,
            result_var: result_var
          )
          emit(inst)
          inst

        when "index_of_seq"
          # buf.index_of_seq("\r\n")
          pattern = args.first
          start_offset = args[1]
          inst = ByteBufferIndexOf.new(
            buffer: buffer,
            pattern: pattern,
            search_type: :sequence,
            start_offset: start_offset,
            result_var: result_var
          )
          emit(inst)
          inst

        when "to_s"
          # buf.to_s
          inst = ByteBufferToString.new(buffer: buffer, result_var: result_var)
          emit(inst)
          inst

        when "to_ascii_string"
          # buf.to_ascii_string (faster for ASCII-only)
          inst = ByteBufferToString.new(buffer: buffer, ascii_only: true, result_var: result_var)
          emit(inst)
          inst

        when "length"
          # buf.length
          inst = ByteBufferLength.new(buffer: buffer, result_var: result_var)
          emit(inst)
          inst

        when "slice"
          # buf.slice(start, length) -> ByteSlice
          start_pos = args[0] || IntegerLit.new(value: 0)
          length = args[1] || IntegerLit.new(value: 0)
          inst = ByteBufferSlice.new(buffer: buffer, start: start_pos, length: length, result_var: result_var)
          emit(inst)
          inst

        when "clear"
          # buf.clear - returns self (the buffer)
          # Just return the buffer reference for now
          buffer

        else
          # Unknown method - fall back to regular call
          visit_call_default(typed_node)
        end
      end

      # ========================================
      # StringBuffer methods
      # ========================================

      # Track StringBuffer variables
      def string_buffer_vars
        @string_buffer_vars ||= {}
      end

      # Check if this is a StringBuffer.new(capacity) call
      def string_buffer_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "StringBuffer"
      end

      # Check if this is a StringBuffer method call
      def string_buffer_method_call?(typed_node)
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        string_buffer_vars.key?(var_name)
      end

      # Handle StringBuffer.new(capacity)
      def visit_string_buffer_new(typed_node)
        # Get capacity argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        capacity = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          nil  # Use default capacity
        end

        result_var = new_temp_var
        inst = StringBufferAlloc.new(capacity: capacity, result_var: result_var)
        emit(inst)
        inst
      end

      # Handle StringBuffer method calls (<<, to_s, length)
      def visit_string_buffer_method(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        buffer = visit(receiver_child)

        method_name = typed_node.node.name.to_s
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        args = args_child ? args_child.children.map { |c| visit(c) } : []

        result_var = new_temp_var

        case method_name
        when "<<", "append"
          # buf << string
          value = args.first
          inst = StringBufferAppend.new(buffer: buffer, value: value, result_var: result_var)
          emit(inst)
          inst

        when "append_line"
          # buf.append_line(string) - appends string + "\n"
          # For now, we'll emit two appends
          value = args.first
          inst1 = StringBufferAppend.new(buffer: buffer, value: value, result_var: new_temp_var)
          emit(inst1)
          newline = StringLit.new(value: "\n", result_var: new_temp_var)
          emit(newline)
          inst2 = StringBufferAppend.new(buffer: inst1, value: newline, result_var: result_var)
          emit(inst2)
          inst2

        when "to_s"
          # buf.to_s -> String
          inst = StringBufferToString.new(buffer: buffer, result_var: result_var)
          emit(inst)
          inst

        when "length"
          # buf.length -> Integer
          inst = StringBufferLength.new(buffer: buffer, result_var: result_var)
          emit(inst)
          inst

        when "clear"
          # buf.clear - returns self
          buffer

        else
          # Unknown method - fall back to regular call
          visit_call_default(typed_node)
        end
      end

      # ========================================
      # NativeString methods
      # UTF-8 native string with byte and character level operations
      # ========================================

      # Track NativeString variables
      def native_string_vars
        @native_string_vars ||= {}
      end

      # Check if this is a KonpeitoJSON.parse_as(json, TargetClass) call
      def konpeito_json_parse_as_call?(typed_node)
        return false unless typed_node.node.name.to_s == "parse_as"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "KonpeitoJSON"
      end

      # Handle KonpeitoJSON.parse_as(json_string, TargetClass)
      def visit_konpeito_json_parse_as(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        unless args_child && args_child.children.length >= 2
          raise "KonpeitoJSON.parse_as requires (json_string, TargetClass) arguments"
        end

        # First argument: JSON string
        json_expr = visit(args_child.children[0])

        # Second argument: Target class (constant)
        target_class_node = args_child.children[1]
        unless target_class_node.node_type == :constant_read
          raise "KonpeitoJSON.parse_as second argument must be a class constant"
        end

        target_class_name = target_class_node.node.name.to_s.to_sym
        target_class_type = @rbs_loader&.native_classes&.[](target_class_name)

        unless target_class_type.is_a?(TypeChecker::Types::NativeClassType)
          raise "KonpeitoJSON.parse_as target class '#{target_class_name}' must be a NativeClass"
        end

        result_var = new_temp_var
        inst = JSONParseAs.new(
          json_expr: json_expr,
          target_class: target_class_type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Check if this is a KonpeitoJSON.parse_array_as(json, ElementClass) call
      def konpeito_json_parse_array_as_call?(typed_node)
        return false unless typed_node.node.name.to_s == "parse_array_as"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "KonpeitoJSON"
      end

      # Handle KonpeitoJSON.parse_array_as(json_string, ElementClass)
      def visit_konpeito_json_parse_array_as(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        unless args_child && args_child.children.length >= 2
          raise "KonpeitoJSON.parse_array_as requires (json_string, ElementClass) arguments"
        end

        # First argument: JSON string
        json_expr = visit(args_child.children[0])

        # Second argument: Element class (constant)
        element_class_node = args_child.children[1]
        unless element_class_node.node_type == :constant_read
          raise "KonpeitoJSON.parse_array_as second argument must be a class constant"
        end

        element_class_name = element_class_node.node.name.to_s.to_sym
        element_class_type = @rbs_loader&.native_classes&.[](element_class_name)

        unless element_class_type.is_a?(TypeChecker::Types::NativeClassType)
          raise "KonpeitoJSON.parse_array_as element class '#{element_class_name}' must be a NativeClass"
        end

        result_var = new_temp_var
        inst = JSONParseArrayAs.new(
          json_expr: json_expr,
          element_class: element_class_type,
          result_var: result_var
        )
        emit(inst)

        # Track as native_array variable
        @native_array_vars ||= {}
        @native_array_vars[result_var] = element_class_type

        inst
      end

      # Check if this is a NativeString.from(str) call
      def native_string_from_call?(typed_node)
        return false unless typed_node.node.name.to_s == "from"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "NativeString"
      end

      # Check if this is a NativeString method call
      def native_string_method_call?(typed_node)
        receiver_child = typed_node.children.first
        return false unless receiver_child

        # Check if receiver is a local variable that we know is a NativeString
        if receiver_child.node_type == :local_variable_read
          var_name = receiver_child.node.name.to_s
          return true if native_string_vars.key?(var_name)
        end

        # Check if receiver is a NativeString method call that returns NativeString
        # This handles method chaining like: ns.byte_slice(0, len).to_s
        if receiver_child.node_type == :call
          receiver_method = receiver_child.node.name.to_s
          # byte_slice and char_slice return NativeString
          if receiver_method == "byte_slice" || receiver_method == "char_slice"
            # Check if the receiver of that call is a NativeString
            nested_receiver = receiver_child.children.first
            if nested_receiver&.node_type == :local_variable_read
              var_name = nested_receiver.node.name.to_s
              return true if native_string_vars.key?(var_name)
            end
          end
        end

        # Also check if the receiver's type is NativeStringType (as fallback)
        if receiver_child.respond_to?(:type) && receiver_child.type
          # Resolve TypeVar if necessary
          resolved_type = receiver_child.type
          if resolved_type.respond_to?(:prune)
            resolved_type = resolved_type.prune
          end
          return true if resolved_type.is_a?(TypeChecker::Types::NativeStringType)
        end

        false
      end

      # Handle NativeString.from(str)
      def visit_native_string_from(typed_node)
        # Get string argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        string = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          raise "NativeString.from requires a string argument"
        end

        result_var = new_temp_var
        inst = NativeStringFromRuby.new(string: string, result_var: result_var)
        emit(inst)
        inst
      end

      # Handle NativeString method calls
      def visit_native_string_method(typed_node)
        receiver_child = typed_node.children.first
        # Visit the receiver - this works for both local variables and chained method calls
        native_string = visit(receiver_child)

        method_name = typed_node.node.name.to_s
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        args = args_child ? args_child.children.map { |c| visit(c) } : []

        result_var = new_temp_var

        case method_name
        # Byte-level operations (fast, O(1) or O(n) with memchr)
        when "byte_at"
          index = args.first || IntegerLit.new(value: 0)
          inst = NativeStringByteAt.new(native_string: native_string, index: index, result_var: result_var)
          emit(inst)
          inst

        when "byte_length"
          inst = NativeStringByteLength.new(native_string: native_string, result_var: result_var)
          emit(inst)
          inst

        when "byte_index_of"
          byte = args[0]
          start_offset = args[1]  # Optional
          inst = NativeStringByteIndexOf.new(
            native_string: native_string,
            byte: byte,
            start_offset: start_offset,
            result_var: result_var
          )
          emit(inst)
          inst

        when "byte_slice"
          start = args[0] || IntegerLit.new(value: 0)
          length = args[1] || IntegerLit.new(value: 0)
          inst = NativeStringByteSlice.new(
            native_string: native_string,
            start: start,
            length: length,
            result_var: result_var
          )
          emit(inst)
          inst

        # Character-level operations (UTF-8 aware)
        when "char_at"
          index = args.first || IntegerLit.new(value: 0)
          inst = NativeStringCharAt.new(native_string: native_string, index: index, result_var: result_var)
          emit(inst)
          inst

        when "char_length"
          inst = NativeStringCharLength.new(native_string: native_string, result_var: result_var)
          emit(inst)
          inst

        when "char_index_of"
          needle = args.first
          inst = NativeStringCharIndexOf.new(native_string: native_string, needle: needle, result_var: result_var)
          emit(inst)
          inst

        when "char_slice"
          start = args[0] || IntegerLit.new(value: 0)
          length = args[1] || IntegerLit.new(value: 0)
          inst = NativeStringCharSlice.new(
            native_string: native_string,
            start: start,
            length: length,
            result_var: result_var
          )
          emit(inst)
          inst

        # Inspection methods
        when "ascii_only?"
          inst = NativeStringAsciiOnly.new(native_string: native_string, result_var: result_var)
          emit(inst)
          inst

        when "starts_with?"
          prefix = args.first
          inst = NativeStringStartsWith.new(native_string: native_string, prefix: prefix, result_var: result_var)
          emit(inst)
          inst

        when "ends_with?"
          suffix = args.first
          inst = NativeStringEndsWith.new(native_string: native_string, suffix: suffix, result_var: result_var)
          emit(inst)
          inst

        when "valid_encoding?"
          inst = NativeStringValidEncoding.new(native_string: native_string, result_var: result_var)
          emit(inst)
          inst

        # Conversion
        when "to_s"
          inst = NativeStringToRuby.new(native_string: native_string, result_var: result_var)
          emit(inst)
          inst

        when "=="
          other = args.first
          inst = NativeStringCompare.new(native_string: native_string, other: other, result_var: result_var)
          emit(inst)
          inst

        else
          # Unknown method - fall back to regular call
          visit_call_default(typed_node)
        end
      end

      # ========================================
      # ByteSlice methods
      # Zero-copy view into ByteBuffer
      # ========================================

      # Track ByteSlice variables
      def byte_slice_vars
        @byte_slice_vars ||= {}
      end

      # Check if this is a ByteSlice method call
      def byte_slice_method_call?(typed_node)
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        byte_slice_vars.key?(var_name)
      end

      # Handle ByteSlice method calls ([], length, to_s)
      def visit_byte_slice_method(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        slice = visit(receiver_child)

        method_name = typed_node.node.name.to_s
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        args = args_child ? args_child.children.map { |c| visit(c) } : []

        result_var = new_temp_var

        case method_name
        when "[]"
          # slice[index] -> byte
          index = args.first || IntegerLit.new(value: 0)
          inst = ByteSliceGet.new(slice: slice, index: index, result_var: result_var)
          emit(inst)
          inst

        when "length"
          # slice.length -> Integer
          inst = ByteSliceLength.new(slice: slice, result_var: result_var)
          emit(inst)
          inst

        when "to_s"
          # slice.to_s -> String
          inst = ByteSliceToString.new(slice: slice, result_var: result_var)
          emit(inst)
          inst

        else
          # Unknown method - fall back to regular call
          visit_call_default(typed_node)
        end
      end

      # ========================================
      # StaticArray methods
      # Fixed-size stack-allocated arrays
      # ========================================

      # Track StaticArray variables: var_name -> { element_type:, size: }
      def static_array_vars
        @static_array_vars ||= {}
      end

      # Check if this is a StaticArray.new call
      # Supports both legacy syntax (StaticArray4Float.new) and generic syntax (StaticArray[Float, 4].new)
      def static_array_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        class_name = receiver_child.node.name.to_s

        # Check generic syntax first - look up RBS for type info
        if class_name == "StaticArray"
          info = extract_static_array_type_info(typed_node.type)
          return true if info
        end

        # Fall back to legacy class name encoding
        class_name.match?(/\AStaticArray\d+(Float|Int)\z/)
      end

      # Parse StaticArray class name to extract element type and size (legacy syntax)
      def parse_static_array_class_name(class_name)
        match = class_name.to_s.match(/\AStaticArray(\d+)(Float|Int)\z/)
        return nil unless match

        size = match[1].to_i
        element_type = match[2] == "Float" ? :Float64 : :Int64
        { element_type: element_type, size: size }
      end

      # Extract StaticArray type info from a ClassInstance with generic args
      # e.g., ClassInstance(:StaticArray, [Float, 4]) -> { element_type: :Float64, size: 4 }
      def extract_static_array_type_info(type)
        return nil unless type.is_a?(TypeChecker::Types::ClassInstance)
        return nil unless type.name == :StaticArray
        return nil unless type.type_args.size == 2

        element_type = convert_element_type_arg(type.type_args[0])
        size = extract_size_from_type_arg(type.type_args[1])

        return nil unless element_type && size

        { element_type: element_type, size: size }
      end

      # Convert element type argument to internal type symbol
      def convert_element_type_arg(type_arg)
        case type_arg
        when TypeChecker::Types::ClassInstance
          case type_arg.name
          when :Float, :Float64 then :Float64
          when :Integer, :Int64 then :Int64
          else nil
          end
        when Symbol
          case type_arg
          when :Float, :Float64 then :Float64
          when :Integer, :Int64 then :Int64
          else nil
          end
        else
          nil
        end
      end

      # Extract size from type argument (integer literal or type)
      def extract_size_from_type_arg(type_arg)
        case type_arg
        when Integer
          type_arg
        when TypeChecker::Types::Literal
          # Extract value from Literal type (e.g., StaticArray[Float, 4])
          type_arg.value if type_arg.value.is_a?(Integer)
        when TypeChecker::Types::ClassInstance
          # Try to parse as integer constant
          type_arg.name.to_s.to_i if type_arg.name.to_s.match?(/\A\d+\z/)
        else
          type_arg.to_s.to_i if type_arg.to_s.match?(/\A\d+\z/)
        end
      end

      # Check if this is a StaticArray method call
      def static_array_method_call?(typed_node)
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        static_array_vars.key?(var_name)
      end

      # Handle StaticArray.new(optional_initial_value)
      def visit_static_array_new(typed_node)
        receiver_child = typed_node.children.first
        class_name = receiver_child.node.name.to_s

        # Try generic type info first (from inferred type)
        info = extract_static_array_type_info(typed_node.type)
        # Fall back to legacy class name encoding
        info ||= parse_static_array_class_name(class_name)

        raise "Cannot determine StaticArray type info" unless info

        # Get optional initial value argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        initial_value = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          nil
        end

        result_var = new_temp_var
        inst = StaticArrayAlloc.new(
          element_type: info[:element_type],
          size: info[:size],
          initial_value: initial_value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Handle StaticArray method calls ([], []=, size)
      def visit_static_array_method(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        info = static_array_vars[var_name]
        array = visit(receiver_child)

        method_name = typed_node.node.name.to_s
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        args = args_child ? args_child.children.map { |c| visit(c) } : []

        result_var = new_temp_var

        case method_name
        when "[]"
          # arr[index] -> element
          index = args.first || IntegerLit.new(value: 0)
          inst = StaticArrayGet.new(
            array: array,
            index: index,
            element_type: info[:element_type],
            size: info[:size],
            result_var: result_var
          )
          emit(inst)
          inst

        when "[]="
          # arr[index] = value
          index = args[0] || IntegerLit.new(value: 0)
          value = args[1] || IntegerLit.new(value: 0)
          inst = StaticArraySet.new(
            array: array,
            index: index,
            value: value,
            element_type: info[:element_type],
            size: info[:size]
          )
          emit(inst)
          inst

        when "size", "length"
          # arr.size -> Integer (compile-time constant)
          inst = StaticArraySize.new(
            array: array,
            size: info[:size],
            result_var: result_var
          )
          emit(inst)
          inst

        else
          # Unknown method - fall back to regular call
          visit_call_default(typed_node)
        end
      end

      # ========================================
      # Slice[T] methods
      # Generic bounds-checked pointer view
      # ========================================

      # Track Slice variables: var_name -> { element_type: }
      def slice_vars
        @slice_vars ||= {}
      end

      # Check if this is a Slice.new call
      # Supports both legacy syntax (SliceInt64.new) and generic syntax (Slice[Int64].new)
      def slice_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        class_name = receiver_child.node.name.to_s

        # Check generic syntax first
        return true if class_name == "Slice" && extract_slice_type_info(typed_node.type)

        # Fall back to legacy class name encoding
        class_name.match?(/\ASlice(Int64|Float64)\z/)
      end

      # Check if this is a Slice.empty call
      def slice_empty_call?(typed_node)
        return false unless typed_node.node.name.to_s == "empty"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        class_name = receiver_child.node.name.to_s

        # Check generic syntax first
        return true if class_name == "Slice" && extract_slice_type_info(typed_node.type)

        # Fall back to legacy class name encoding
        class_name.match?(/\ASlice(Int64|Float64)\z/)
      end

      # Parse Slice class name to extract element type (legacy syntax)
      def parse_slice_class_name(class_name)
        match = class_name.to_s.match(/\ASlice(Int64|Float64)\z/)
        return nil unless match

        element_type = match[1] == "Float64" ? :Float64 : :Int64
        { element_type: element_type }
      end

      # Extract Slice type info from a ClassInstance with generic args
      # e.g., ClassInstance(:Slice, [Int64]) -> { element_type: :Int64 }
      def extract_slice_type_info(type)
        return nil unless type.is_a?(TypeChecker::Types::ClassInstance)
        return nil unless type.name == :Slice
        return nil unless type.type_args.size == 1

        element_type = convert_element_type_arg(type.type_args[0])
        return nil unless element_type

        { element_type: element_type }
      end

      # Check if this is a Slice method call
      def slice_method_call?(typed_node)
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        slice_vars.key?(var_name)
      end

      # Check if this is a to_slice call on NativeArray or StaticArray
      def to_slice_call?(typed_node)
        return false unless typed_node.node.name.to_s == "to_slice"

        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        native_array_vars.key?(var_name) || static_array_vars.key?(var_name)
      end

      # Handle Slice.new(size)
      def visit_slice_new(typed_node)
        receiver_child = typed_node.children.first
        class_name = receiver_child.node.name.to_s

        # Try generic type info first (from inferred type)
        info = extract_slice_type_info(typed_node.type)
        # Fall back to legacy class name encoding
        info ||= parse_slice_class_name(class_name)

        raise "Cannot determine Slice type info" unless info

        # Get size argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        size = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          IntegerLit.new(value: 0)
        end

        result_var = new_temp_var
        inst = SliceAlloc.new(
          size: size,
          element_type: info[:element_type],
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Handle Slice.empty
      def visit_slice_empty(typed_node)
        receiver_child = typed_node.children.first
        class_name = receiver_child.node.name.to_s

        # Try generic type info first (from inferred type)
        info = extract_slice_type_info(typed_node.type)
        # Fall back to legacy class name encoding
        info ||= parse_slice_class_name(class_name)

        raise "Cannot determine Slice type info" unless info

        result_var = new_temp_var
        inst = SliceEmpty.new(
          element_type: info[:element_type],
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Handle Slice method calls ([], []=, size, subslice, copy_from, fill)
      def visit_slice_method(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        info = slice_vars[var_name]
        slice = visit(receiver_child)

        method_name = typed_node.node.name.to_s
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        args = args_child ? args_child.children.map { |c| visit(c) } : []

        result_var = new_temp_var

        case method_name
        when "[]"
          if args.size == 2
            # slice[start, count] -> subslice
            start_idx = args[0]
            count = args[1]
            inst = SliceSubslice.new(
              slice: slice,
              start: start_idx,
              count: count,
              element_type: info[:element_type],
              result_var: result_var
            )
            emit(inst)
            inst
          else
            # slice[index] -> element
            index = args.first || IntegerLit.new(value: 0)
            inst = SliceGet.new(
              slice: slice,
              index: index,
              element_type: info[:element_type],
              result_var: result_var
            )
            emit(inst)
            inst
          end

        when "[]="
          # slice[index] = value
          index = args[0] || IntegerLit.new(value: 0)
          value = args[1] || IntegerLit.new(value: 0)
          inst = SliceSet.new(
            slice: slice,
            index: index,
            value: value,
            element_type: info[:element_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "size", "length"
          # slice.size -> Integer
          inst = SliceSize.new(
            slice: slice,
            result_var: result_var
          )
          emit(inst)
          inst

        when "copy_from"
          # slice.copy_from(source) -> self
          source = args.first
          inst = SliceCopyFrom.new(
            dest: slice,
            source: source,
            element_type: info[:element_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "fill"
          # slice.fill(value) -> self
          value = args.first || IntegerLit.new(value: 0)
          inst = SliceFill.new(
            slice: slice,
            value: value,
            element_type: info[:element_type],
            result_var: result_var
          )
          emit(inst)
          inst

        else
          # Unknown method - fall back to regular call
          visit_call_default(typed_node)
        end
      end

      # Handle NativeArray/StaticArray to_slice conversion
      def visit_to_slice(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        source = visit(receiver_child)

        # Determine source kind and element type
        source_kind = if native_array_vars.key?(var_name)
          :native_array
        else
          :static_array
        end

        element_type = if source_kind == :native_array
          native_array_vars[var_name]
        else
          static_array_vars[var_name][:element_type]
        end

        result_var = new_temp_var
        inst = ToSlice.new(
          source: source,
          element_type: element_type,
          source_kind: source_kind,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # NativeHash methods
      # ========================================

      # Track NativeHash variables: var_name -> { key_type:, value_type: }
      def native_hash_vars
        @native_hash_vars ||= {}
      end

      # Parse NativeHash class name (e.g., NativeHashStringInteger -> { key_type: :String, value_type: :Integer })
      def parse_native_hash_class_name(class_name)
        # Pattern: NativeHash<KeyType><ValueType>
        # KeyType: String, Symbol, Integer
        # ValueType: Integer, Float, Bool, String, Object, Array, Hash, or a NativeClass name
        match = class_name.to_s.match(/\ANativeHash(String|Symbol|Integer)(\w+)\z/)
        return nil unless match

        key_type = match[1].to_sym
        value_str = match[2]

        # Map value type
        value_type = case value_str
                     when "Integer" then :Integer
                     when "Float" then :Float
                     when "Bool" then :Bool
                     when "String" then :String
                     when "Object" then :Object
                     when "Array" then :Array
                     when "Hash" then :Hash
                     else
                       # Could be a NativeClass name
                       if @rbs_loader&.native_class?(value_str.to_sym)
                         @rbs_loader.native_class_type(value_str.to_sym)
                       else
                         value_str.to_sym
                       end
                     end

        { key_type: key_type, value_type: value_type }
      end

      # Extract NativeHash type info from a ClassInstance with generic args
      # e.g., ClassInstance(:NativeHash, [String, Integer]) -> { key_type: :String, value_type: :Integer }
      def extract_native_hash_type_info(type)
        return nil unless type.is_a?(TypeChecker::Types::ClassInstance)
        return nil unless type.name == :NativeHash
        return nil unless type.type_args.size == 2

        key_type = convert_type_arg_to_native_type(type.type_args[0])
        value_type = convert_type_arg_to_native_type(type.type_args[1])

        { key_type: key_type, value_type: value_type }
      end

      # Convert a type argument to internal native type symbol
      def convert_type_arg_to_native_type(type_arg)
        case type_arg
        when TypeChecker::Types::ClassInstance
          name = type_arg.name
          case name
          when :Integer, :Int64 then :Integer
          when :Float, :Float64 then :Float
          when :Bool, :bool then :Bool
          when :String then :String
          when :Symbol then :Symbol
          when :Array then :Array
          when :Hash then :Hash
          when :Object then :Object
          else
            # Could be a NativeClass
            if @rbs_loader&.native_class?(name)
              @rbs_loader.native_class_type(name)
            else
              name
            end
          end
        when Symbol
          type_arg
        else
          type_arg.to_s.to_sym
        end
      end

      # Check if this is a NativeHash.new call
      # Supports both legacy syntax (NativeHashStringInteger.new) and generic syntax (NativeHash[String, Integer].new)
      def native_hash_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        class_name = receiver_child.node.name.to_s

        # Check generic syntax first (NativeHash with type args from inferred type)
        return true if class_name == "NativeHash" && extract_native_hash_type_info(typed_node.type)

        # Fall back to legacy class name encoding
        parse_native_hash_class_name(class_name) != nil
      end

      # Check if this is a NativeHash method call
      def native_hash_method_call?(typed_node)
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        native_hash_vars.key?(var_name)
      end

      # Handle NativeHash.new(capacity)
      def visit_native_hash_new(typed_node)
        receiver_child = typed_node.children.first
        class_name = receiver_child.node.name.to_s

        # Try generic type info first (from inferred type)
        info = extract_native_hash_type_info(typed_node.type)
        # Fall back to legacy class name encoding
        info ||= parse_native_hash_class_name(class_name)

        raise "Cannot determine NativeHash type info" unless info

        # Get optional capacity argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        capacity = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          nil  # Default capacity (16)
        end

        result_var = new_temp_var
        inst = NativeHashAlloc.new(
          key_type: info[:key_type],
          value_type: info[:value_type],
          capacity: capacity,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Handle NativeHash method calls ([], []=, size, has_key?, delete, clear, keys, values, each)
      def visit_native_hash_method(typed_node)
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        info = native_hash_vars[var_name]
        hash_var = visit(receiver_child)

        method_name = typed_node.node.name.to_s
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        args = args_child ? args_child.children.map { |c| visit(c) } : []

        result_var = new_temp_var

        case method_name
        when "[]"
          key = args.first
          inst = NativeHashGet.new(
            hash_var: hash_var,
            key: key,
            key_type: info[:key_type],
            value_type: info[:value_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "[]="
          key = args[0]
          value = args[1]
          inst = NativeHashSet.new(
            hash_var: hash_var,
            key: key,
            value: value,
            key_type: info[:key_type],
            value_type: info[:value_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "size", "length"
          inst = NativeHashSize.new(
            hash_var: hash_var,
            result_var: result_var
          )
          emit(inst)
          inst

        when "has_key?", "key?", "include?", "member?"
          key = args.first
          inst = NativeHashHasKey.new(
            hash_var: hash_var,
            key: key,
            key_type: info[:key_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "delete"
          key = args.first
          inst = NativeHashDelete.new(
            hash_var: hash_var,
            key: key,
            key_type: info[:key_type],
            value_type: info[:value_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "clear"
          inst = NativeHashClear.new(
            hash_var: hash_var,
            key_type: info[:key_type],
            value_type: info[:value_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "keys"
          inst = NativeHashKeys.new(
            hash_var: hash_var,
            key_type: info[:key_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "values"
          inst = NativeHashValues.new(
            hash_var: hash_var,
            key_type: info[:key_type],
            value_type: info[:value_type],
            result_var: result_var
          )
          emit(inst)
          inst

        when "each"
          # Handle each with block
          block_child = typed_node.children.find { |c| c.node_type == :block }
          if block_child
            visit_native_hash_each(typed_node, hash_var, info)
          else
            # No block - return enumerator (fall back to Ruby)
            visit_method_call(typed_node)
          end

        else
          # Unknown method - fall back to Ruby call
          visit_method_call(typed_node)
        end
      end

      # Handle NativeHash#each { |k, v| ... }
      def visit_native_hash_each(typed_node, hash_var, info)
        block_child = typed_node.children.find { |c| c.node_type == :block }
        return visit_method_call(typed_node) unless block_child

        # Get block parameters
        params_child = block_child.children.find { |c| c.node_type == :block_parameters }
        param_names = if params_child
          params_child.children
            .select { |c| c.node_type == :required_parameter }
            .map { |c| c.node.name.to_s }
        else
          ["k", "v"]
        end

        key_var = param_names[0] || "k"
        value_var = param_names[1] || "v"

        # Build block body — save/restore @current_block so NativeHashEach
        # is emitted into the original block, not the loop body block
        saved_block = @current_block
        body_child = block_child.children.find { |c| c.node_type == :statements }
        block_body = []

        if body_child
          # Create a new basic block for the iteration body
          loop_bb = BasicBlock.new(label: "hash_each_body_#{@block_counter}")
          @current_block = loop_bb
          block_body << loop_bb

          body_child.children.each do |stmt|
            visit(stmt)
          end
        end
        @current_block = saved_block

        result_var = new_temp_var
        inst = NativeHashEach.new(
          hash_var: hash_var,
          key_type: info[:key_type],
          value_type: info[:value_type],
          block_params: [key_var, value_var],
          block_body: block_body,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # SIMDClass methods
      # ========================================

      # Check if this is a SIMDClass.new call
      def simd_class_new_call?(typed_node)
        return false unless @rbs_loader
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is a constant that's a SIMD class
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        class_name = receiver_child.node.name.to_sym
        @rbs_loader.simd_class?(class_name)
      end

      # Check if this is SIMDClass field access (getter or setter)
      def simd_class_field_access?(typed_node)
        return false unless @rbs_loader
        return false unless typed_node.node.respond_to?(:name)

        method_name = typed_node.node.name.to_s

        # Get receiver
        receiver_child = typed_node.children.first
        return false unless receiver_child

        # Check if receiver is a local variable that's a SIMD class
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        simd_type = @simd_class_vars[var_name]
        return false unless simd_type

        # Check if method name is a field name (getter or setter)
        field_name = method_name.chomp("=").to_sym
        simd_type.field?(field_name)
      end

      # Check if this is a SIMDClass method call (not field access)
      def simd_class_method_call?(typed_node)
        return false unless @rbs_loader
        return false unless typed_node.node.respond_to?(:name)

        method_name = typed_node.node.name.to_sym

        # Get receiver
        receiver_child = typed_node.children.first
        return false unless receiver_child

        # Check if receiver is a local variable that's a SIMD class
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        simd_type = @simd_class_vars[var_name]
        return false unless simd_type

        # Check if it's a method (not a field accessor)
        field_name = method_name.to_s.chomp("=").to_sym
        return false if simd_type.field?(field_name)

        # Check if method is defined
        simd_type.lookup_method(method_name) != nil
      end

      # Visit SIMDClass.new call
      def visit_simd_class_new(typed_node)
        receiver_child = typed_node.children.first
        class_name = receiver_child.node.name.to_sym
        simd_type = @rbs_loader.simd_class_type(class_name)

        result_var = new_temp_var
        inst = SIMDNew.new(
          simd_type: simd_type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit SIMDClass field access (getter or setter)
      def visit_simd_field_access(typed_node)
        method_name = typed_node.node.name.to_s
        is_setter = method_name.end_with?("=")
        field_name = method_name.chomp("=").to_sym

        # Get receiver
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        simd_type = @simd_class_vars[var_name]

        receiver = visit(receiver_child)

        if is_setter
          # Setter: v.x = value
          args_child = typed_node.children.find { |c| c.node_type == :arguments }
          value = args_child && args_child.children.any? ? visit(args_child.children.first) : nil

          inst = SIMDFieldSet.new(
            object: receiver,
            field_name: field_name,
            value: value,
            simd_type: simd_type
          )
          emit(inst)
          inst
        else
          # Getter: v.x
          result_var = new_temp_var
          inst = SIMDFieldGet.new(
            object: receiver,
            field_name: field_name,
            simd_type: simd_type,
            result_var: result_var
          )
          emit(inst)
          inst
        end
      end

      # Visit SIMDClass method call
      def visit_simd_method_call(typed_node)
        method_name = typed_node.node.name.to_sym

        # Get receiver
        receiver_child = typed_node.children.first
        var_name = receiver_child.node.name.to_s
        simd_type = @simd_class_vars[var_name]

        receiver = visit(receiver_child)
        method_sig = simd_type.lookup_method(method_name)

        # Get arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            args << visit(arg)
          end
        end

        result_var = new_temp_var
        inst = SIMDMethodCall.new(
          receiver: receiver,
          method_name: method_name,
          args: args,
          simd_type: simd_type,
          method_sig: method_sig,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # Fiber operations
      # ========================================

      # Check if this is a Fiber.new { ... } call
      def fiber_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is Fiber constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Fiber"
      end

      # Check if this is a Fiber.yield(...) call
      def fiber_yield_call?(typed_node)
        return false unless typed_node.node.name.to_s == "yield"

        # Check if receiver is Fiber constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Fiber"
      end

      # Check if this is a Fiber.current call
      def fiber_current_call?(typed_node)
        return false unless typed_node.node.name.to_s == "current"

        # Check if receiver is Fiber constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Fiber"
      end

      # Check if this is a fiber.resume(...) call
      def fiber_resume_call?(typed_node)
        return false unless typed_node.node.name.to_s == "resume"

        # Check if receiver is a local variable
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        # Check if the variable's type is Fiber
        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Fiber
      end

      # Check if this is a fiber.alive? call
      def fiber_alive_call?(typed_node)
        return false unless typed_node.node.name.to_s == "alive?"

        # Check if receiver is a local variable
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        # Check if the variable's type is Fiber
        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Fiber
      end

      # Visit Fiber.new { ... } call
      def visit_fiber_new(typed_node)
        # Extract block from Fiber.new { ... }
        block_child = typed_node.children.find { |c| c.node_type == :block }

        # Build block def (reuse existing block building infrastructure)
        block_def = if block_child
          visit_block_def(block_child)
        else
          # No block provided - create empty block
          BlockDef.new(params: [], body: [], captures: [])
        end

        result_var = new_temp_var
        inst = FiberNew.new(
          block_def: block_def,
          result_var: result_var
        )
        emit(inst)

        # Track this variable as holding a Fiber
        # This will be stored by visit_write_local
        inst
      end

      # Visit Fiber.yield(...) call
      def visit_fiber_yield(typed_node)
        # Get arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            args << visit(arg)
          end
        end

        result_var = new_temp_var
        inst = FiberYield.new(
          args: args,
          type: TypeChecker::Types::UNTYPED,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Fiber.current call
      def visit_fiber_current(_typed_node)
        result_var = new_temp_var
        inst = FiberCurrent.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit fiber.resume(...) call
      def visit_fiber_resume(typed_node)
        # Get receiver (the fiber)
        receiver_child = typed_node.children.first
        fiber = visit(receiver_child)

        # Get arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg|
            args << visit(arg)
          end
        end

        result_var = new_temp_var
        inst = FiberResume.new(
          fiber: fiber,
          args: args,
          type: TypeChecker::Types::UNTYPED,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit fiber.alive? call
      def visit_fiber_alive(typed_node)
        # Get receiver (the fiber)
        receiver_child = typed_node.children.first
        fiber = visit(receiver_child)

        result_var = new_temp_var
        inst = FiberAlive.new(
          fiber: fiber,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # Thread operations
      # ========================================

      # Check if this is a Thread.new { ... } call
      def thread_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is Thread constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Thread"
      end

      # Check if this is a Thread.current call
      def thread_current_call?(typed_node)
        return false unless typed_node.node.name.to_s == "current"

        # Check if receiver is Thread constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Thread"
      end

      # Check if this is a thread.join call
      def thread_join_call?(typed_node)
        return false unless typed_node.node.name.to_s == "join"

        # Check if receiver is a local variable with Thread type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Thread
      end

      # Check if this is a thread.value call
      def thread_value_call?(typed_node)
        return false unless typed_node.node.name.to_s == "value"

        # Check if receiver is a local variable with Thread type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Thread
      end

      # Visit Thread.new { ... } call
      def visit_thread_new(typed_node)
        # Extract block from Thread.new { ... }
        block_child = typed_node.children.find { |c| c.node_type == :block }

        # Build block def (reuse existing block building infrastructure)
        block_def = if block_child
          visit_block_def(block_child)
        else
          # No block provided - create empty block
          BlockDef.new(params: [], body: [], captures: [])
        end

        result_var = new_temp_var
        inst = ThreadNew.new(
          block_def: block_def,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Thread.current call
      def visit_thread_current(_typed_node)
        result_var = new_temp_var
        inst = ThreadCurrent.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit thread.join call
      def visit_thread_join(typed_node)
        # Get receiver (the thread)
        receiver_child = typed_node.children.first
        thread = visit(receiver_child)

        # Get optional timeout argument
        timeout = nil
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child && args_child.children.any?
          timeout = visit(args_child.children.first)
        end

        result_var = new_temp_var
        inst = ThreadJoin.new(
          thread: thread,
          timeout: timeout,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit thread.value call
      def visit_thread_value(typed_node)
        # Get receiver (the thread)
        receiver_child = typed_node.children.first
        thread = visit(receiver_child)

        result_var = new_temp_var
        inst = ThreadValue.new(
          thread: thread,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # Mutex operations
      # ========================================

      # Check if this is a Mutex.new call
      def mutex_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is Mutex constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Mutex"
      end

      # Check if this is a mutex.lock call
      def mutex_lock_call?(typed_node)
        return false unless typed_node.node.name.to_s == "lock"

        # Check if receiver is a local variable with Mutex type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Mutex
      end

      # Check if this is a mutex.unlock call
      def mutex_unlock_call?(typed_node)
        return false unless typed_node.node.name.to_s == "unlock"

        # Check if receiver is a local variable with Mutex type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Mutex
      end

      # Check if this is a mutex.synchronize { ... } call
      def mutex_synchronize_call?(typed_node)
        return false unless typed_node.node.name.to_s == "synchronize"

        # Check if receiver is a local variable with Mutex type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Mutex
      end

      # Visit Mutex.new call
      def visit_mutex_new(_typed_node)
        result_var = new_temp_var
        inst = MutexNew.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit mutex.lock call
      def visit_mutex_lock(typed_node)
        # Get receiver (the mutex)
        receiver_child = typed_node.children.first
        mutex = visit(receiver_child)

        result_var = new_temp_var
        inst = MutexLock.new(
          mutex: mutex,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit mutex.unlock call
      def visit_mutex_unlock(typed_node)
        # Get receiver (the mutex)
        receiver_child = typed_node.children.first
        mutex = visit(receiver_child)

        result_var = new_temp_var
        inst = MutexUnlock.new(
          mutex: mutex,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit mutex.synchronize { ... } call
      def visit_mutex_synchronize(typed_node)
        # Get receiver (the mutex)
        receiver_child = typed_node.children.first
        mutex = visit(receiver_child)

        # Extract block
        block_child = typed_node.children.find { |c| c.node_type == :block }
        block_def = if block_child
          visit_block_def(block_child)
        else
          BlockDef.new(params: [], body: [], captures: [])
        end

        result_var = new_temp_var
        inst = MutexSynchronize.new(
          mutex: mutex,
          block_def: block_def,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # Queue operations
      # ========================================

      # Check if this is a Queue.new call
      def queue_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is Queue constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Queue"
      end

      # Check if this is a queue.push or queue.<< call
      def queue_push_call?(typed_node)
        method_name = typed_node.node.name.to_s
        return false unless method_name == "push" || method_name == "<<" || method_name == "enq"

        # Check if receiver is a local variable with Queue type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Queue
      end

      # Check if this is a queue.pop call
      def queue_pop_call?(typed_node)
        method_name = typed_node.node.name.to_s
        return false unless method_name == "pop" || method_name == "shift" || method_name == "deq"

        # Check if receiver is a local variable with Queue type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Queue
      end

      # Visit Queue.new call
      def visit_queue_new(_typed_node)
        result_var = new_temp_var
        inst = QueueNew.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit queue.push call
      def visit_queue_push(typed_node)
        # Get receiver (the queue)
        receiver_child = typed_node.children.first
        queue = visit(receiver_child)

        # Get value to push
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        value = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = QueuePush.new(
          queue: queue,
          value: value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit queue.pop call
      def visit_queue_pop(typed_node)
        # Get receiver (the queue)
        receiver_child = typed_node.children.first
        queue = visit(receiver_child)

        # Get optional non_block argument
        non_block = nil
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child && args_child.children.any?
          non_block = visit(args_child.children.first)
        end

        result_var = new_temp_var
        inst = QueuePop.new(
          queue: queue,
          non_block: non_block,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # ConditionVariable operations
      # ========================================

      # Check if this is a ConditionVariable.new call
      def cv_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is ConditionVariable constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "ConditionVariable"
      end

      # Check if this is a cv.wait(mutex) call
      def cv_wait_call?(typed_node)
        return false unless typed_node.node.name.to_s == "wait"

        # Check if receiver is a local variable with ConditionVariable type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :ConditionVariable
      end

      # Check if this is a cv.signal call
      def cv_signal_call?(typed_node)
        return false unless typed_node.node.name.to_s == "signal"

        # Check if receiver is a local variable with ConditionVariable type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :ConditionVariable
      end

      # Check if this is a cv.broadcast call
      def cv_broadcast_call?(typed_node)
        return false unless typed_node.node.name.to_s == "broadcast"

        # Check if receiver is a local variable with ConditionVariable type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :ConditionVariable
      end

      # Visit ConditionVariable.new call
      def visit_cv_new(_typed_node)
        result_var = new_temp_var
        inst = ConditionVariableNew.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit cv.wait(mutex) call
      def visit_cv_wait(typed_node)
        # Get receiver (the cv)
        receiver_child = typed_node.children.first
        cv = visit(receiver_child)

        # Get mutex argument (required)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        mutex = nil
        timeout = nil

        if args_child && args_child.children.any?
          mutex = visit(args_child.children.first)
          # Optional timeout argument
          if args_child.children.size > 1
            timeout = visit(args_child.children[1])
          end
        end

        result_var = new_temp_var
        inst = ConditionVariableWait.new(
          cv: cv,
          mutex: mutex,
          timeout: timeout,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit cv.signal call
      def visit_cv_signal(typed_node)
        # Get receiver (the cv)
        receiver_child = typed_node.children.first
        cv = visit(receiver_child)

        result_var = new_temp_var
        inst = ConditionVariableSignal.new(
          cv: cv,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit cv.broadcast call
      def visit_cv_broadcast(typed_node)
        # Get receiver (the cv)
        receiver_child = typed_node.children.first
        cv = visit(receiver_child)

        result_var = new_temp_var
        inst = ConditionVariableBroadcast.new(
          cv: cv,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # SizedQueue operations
      # ========================================

      # Check if this is a SizedQueue.new(max) call
      def sized_queue_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        # Check if receiver is SizedQueue constant
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "SizedQueue"
      end

      # Check if this is a sized_queue.push call
      def sized_queue_push_call?(typed_node)
        method_name = typed_node.node.name.to_s
        return false unless method_name == "push" || method_name == "<<" || method_name == "enq"

        # Check if receiver is a local variable with SizedQueue type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :SizedQueue
      end

      # Check if this is a sized_queue.pop call
      def sized_queue_pop_call?(typed_node)
        method_name = typed_node.node.name.to_s
        return false unless method_name == "pop" || method_name == "shift" || method_name == "deq"

        # Check if receiver is a local variable with SizedQueue type
        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :SizedQueue
      end

      # Visit SizedQueue.new(max) call
      def visit_sized_queue_new(typed_node)
        # Get max size argument
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        max_size = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          IntLit.new(value: 0, result_var: new_temp_var)  # Default to unlimited
        end

        result_var = new_temp_var
        inst = SizedQueueNew.new(
          max_size: max_size,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit sized_queue.push call
      def visit_sized_queue_push(typed_node)
        # Get receiver (the queue)
        receiver_child = typed_node.children.first
        queue = visit(receiver_child)

        # Get value to push
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        value = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = SizedQueuePush.new(
          queue: queue,
          value: value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit sized_queue.pop call
      def visit_sized_queue_pop(typed_node)
        # Get receiver (the queue)
        receiver_child = typed_node.children.first
        queue = visit(receiver_child)

        # Get optional non_block argument
        non_block = nil
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child && args_child.children.any?
          non_block = visit(args_child.children.first)
        end

        result_var = new_temp_var
        inst = SizedQueuePop.new(
          queue: queue,
          non_block: non_block,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # ========================================
      # Ractor detection predicates
      # ========================================

      # Check if this is a Ractor.new { ... } call
      def ractor_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a Ractor.receive call
      def ractor_receive_call?(typed_node)
        return false unless typed_node.node.name.to_s == "receive"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a Ractor.current call
      def ractor_current_call?(typed_node)
        return false unless typed_node.node.name.to_s == "current"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a Ractor.main call
      def ractor_main_call?(typed_node)
        return false unless typed_node.node.name.to_s == "main"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a Ractor.select call
      def ractor_select_call?(typed_node)
        return false unless typed_node.node.name.to_s == "select"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a ractor.send or ractor << msg call
      def ractor_send_call?(typed_node)
        method_name = typed_node.node.name.to_s
        return false unless method_name == "send" || method_name == "<<"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Ractor
      end

      # Check if this is a ractor.join call
      def ractor_join_call?(typed_node)
        return false unless typed_node.node.name.to_s == "join"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Ractor
      end

      # Check if this is a ractor.value call
      def ractor_value_call?(typed_node)
        return false unless typed_node.node.name.to_s == "value"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Ractor
      end

      # Check if this is a ractor.close call
      def ractor_close_call?(typed_node)
        return false unless typed_node.node.name.to_s == "close"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Ractor
      end

      # Check if this is a ractor.name call
      def ractor_name_call?(typed_node)
        return false unless typed_node.node.name.to_s == "name"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Ractor
      end

      # Check if this is a Ractor[:key] call (class-level [])
      def ractor_local_get_call?(typed_node)
        return false unless typed_node.node.name.to_s == "[]"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a Ractor[:key] = value call (class-level []=)
      def ractor_local_set_call?(typed_node)
        return false unless typed_node.node.name.to_s == "[]="

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a Ractor.make_shareable call
      def ractor_make_sharable_call?(typed_node)
        return false unless typed_node.node.name.to_s == "make_shareable"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a Ractor.shareable? call
      def ractor_sharable_call?(typed_node)
        return false unless typed_node.node.name.to_s == "shareable?"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_read

        receiver_child.node.name.to_s == "Ractor"
      end

      # Check if this is a ractor.monitor(port) call
      def ractor_monitor_call?(typed_node)
        return false unless typed_node.node.name.to_s == "monitor"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Ractor
      end

      # Check if this is a ractor.unmonitor(port) call
      def ractor_unmonitor_call?(typed_node)
        return false unless typed_node.node.name.to_s == "unmonitor"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :Ractor
      end

      # Check if this is a Ractor::Port.new call
      def ractor_port_new_call?(typed_node)
        return false unless typed_node.node.name.to_s == "new"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :constant_path

        extract_constant_name(receiver_child.node) == "Ractor::Port"
      end

      # Check if this is a port.send or port << msg call
      def ractor_port_send_call?(typed_node)
        method_name = typed_node.node.name.to_s
        return false unless method_name == "send" || method_name == "<<"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :"Ractor::Port"
      end

      # Check if this is a port.receive call
      def ractor_port_receive_call?(typed_node)
        return false unless typed_node.node.name.to_s == "receive"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :"Ractor::Port"
      end

      # Check if this is a port.close call
      def ractor_port_close_call?(typed_node)
        return false unless typed_node.node.name.to_s == "close"

        receiver_child = typed_node.children.first
        return false unless receiver_child
        return false unless receiver_child.node_type == :local_variable_read

        var_name = receiver_child.node.name.to_s
        local_var = @local_vars[var_name]
        return false unless local_var

        local_var.type.is_a?(TypeChecker::Types::ClassInstance) &&
          local_var.type.name == :"Ractor::Port"
      end

      # ========================================
      # Ractor visitor methods
      # ========================================

      # Visit Ractor.new { ... } call
      def visit_ractor_new(typed_node)
        block_child = typed_node.children.find { |c| c.node_type == :block }

        block_def = if block_child
          visit_block_def(block_child)
        else
          BlockDef.new(params: [], body: [], captures: [])
        end

        # Extract args and name: keyword passed to Ractor.new
        args = []
        name_inst = nil
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg_child|
            # Check for keyword hash (name: "worker")
            if arg_child.node_type == :keyword_hash
              arg_child.children.each do |kv|
                if kv.node_type == :assoc && kv.children.first&.node_type == :symbol
                  key_name = kv.children.first.node.value.to_s
                  if key_name == "name"
                    name_inst = visit(kv.children.last)
                  end
                end
              end
            else
              args << visit(arg_child)
            end
          end
        end

        result_var = new_temp_var
        inst = RactorNew.new(
          block_def: block_def,
          args: args,
          name: name_inst,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Ractor.receive call
      def visit_ractor_receive(_typed_node)
        result_var = new_temp_var
        inst = RactorReceive.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit Ractor.current call
      def visit_ractor_current(_typed_node)
        result_var = new_temp_var
        inst = RactorCurrent.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit Ractor.main call
      def visit_ractor_main(_typed_node)
        result_var = new_temp_var
        inst = RactorMain.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit Ractor.select call
      def visit_ractor_select(typed_node)
        sources = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args_child.children.each do |arg_child|
            sources << visit(arg_child)
          end
        end

        result_var = new_temp_var
        inst = RactorSelect.new(
          sources: sources,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ractor.send(msg) / ractor << msg call
      def visit_ractor_send(typed_node)
        receiver_child = typed_node.children.first
        ractor = visit(receiver_child)

        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        value = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorSend.new(
          ractor: ractor,
          value: value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ractor.join call
      def visit_ractor_join(typed_node)
        receiver_child = typed_node.children.first
        ractor = visit(receiver_child)

        result_var = new_temp_var
        inst = RactorJoin.new(
          ractor: ractor,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ractor.value call
      def visit_ractor_value(typed_node)
        receiver_child = typed_node.children.first
        ractor = visit(receiver_child)

        result_var = new_temp_var
        inst = RactorValue.new(
          ractor: ractor,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ractor.close call
      def visit_ractor_close(typed_node)
        receiver_child = typed_node.children.first
        ractor = visit(receiver_child)

        result_var = new_temp_var
        inst = RactorClose.new(
          ractor: ractor,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ractor.name call
      def visit_ractor_name(typed_node)
        receiver_child = typed_node.children.first
        ractor = visit(receiver_child)

        result_var = new_temp_var
        inst = RactorName.new(
          ractor: ractor,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Ractor[:key] call
      def visit_ractor_local_get(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        key = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorLocalGet.new(
          key: key,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Ractor[:key] = value call
      def visit_ractor_local_set(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child && args_child.children.size >= 2
          key = visit(args_child.children[0])
          value = visit(args_child.children[1])
        else
          key = NilLit.new(result_var: new_temp_var)
          value = NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorLocalSet.new(
          key: key,
          value: value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Ractor.make_shareable(obj) call
      def visit_ractor_make_sharable(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        value = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorMakeSharable.new(
          value: value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Ractor.shareable?(obj) call
      def visit_ractor_sharable(typed_node)
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        value = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorSharable.new(
          value: value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ractor.monitor(port) call
      def visit_ractor_monitor(typed_node)
        receiver_child = typed_node.children.first
        ractor = visit(receiver_child)

        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        port = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorMonitor.new(
          ractor: ractor,
          port: port,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit ractor.unmonitor(port) call
      def visit_ractor_unmonitor(typed_node)
        receiver_child = typed_node.children.first
        ractor = visit(receiver_child)

        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        port = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorUnmonitor.new(
          ractor: ractor,
          port: port,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit Ractor::Port.new call
      def visit_ractor_port_new(_typed_node)
        result_var = new_temp_var
        inst = RactorPortNew.new(result_var: result_var)
        emit(inst)
        inst
      end

      # Visit port.send(msg) / port << msg call
      def visit_ractor_port_send(typed_node)
        receiver_child = typed_node.children.first
        port = visit(receiver_child)

        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        value = if args_child && args_child.children.any?
          visit(args_child.children.first)
        else
          NilLit.new(result_var: new_temp_var)
        end

        result_var = new_temp_var
        inst = RactorPortSend.new(
          port: port,
          value: value,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit port.receive call
      def visit_ractor_port_receive(typed_node)
        receiver_child = typed_node.children.first
        port = visit(receiver_child)

        result_var = new_temp_var
        inst = RactorPortReceive.new(
          port: port,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Visit port.close call
      def visit_ractor_port_close(typed_node)
        receiver_child = typed_node.children.first
        port = visit(receiver_child)

        result_var = new_temp_var
        inst = RactorPortClose.new(
          port: port,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Check if this is a string literal concatenation: "a" + "b"
      def string_literal_concat?(typed_node)
        return false unless typed_node.node.name.to_s == "+"

        # Check receiver is a string literal
        receiver_child = typed_node.children.first
        return false unless receiver_child&.node_type == :string

        # Check argument is a string literal
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        return false unless args_child&.children&.size == 1

        arg = args_child.children.first
        arg&.node_type == :string
      end

      # Fold string literal concatenation at compile time
      def fold_string_literals(typed_node)
        receiver_child = typed_node.children.first
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        arg_child = args_child.children.first

        left_value = receiver_child.node.unescaped
        right_value = arg_child.node.unescaped

        result_var = new_temp_var
        inst = StringLit.new(value: left_value + right_value, result_var: result_var)
        emit(inst)
        inst
      end

      # Detect string concatenation chain: a + b + c + d
      # Returns array of typed_node parts if chain has 3+ elements, nil otherwise
      def detect_string_concat_chain(typed_node)
        return nil unless string_plus_call?(typed_node)

        # Only optimize if the receiver type is String
        receiver_child = typed_node.children.first
        receiver_type = receiver_child&.type
        return nil unless receiver_type == TypeChecker::Types::STRING

        parts = []
        current = typed_node

        # Walk up the chain collecting parts
        while string_plus_call?(current)
          args_child = current.children.find { |c| c.node_type == :arguments }
          if args_child&.children&.size == 1
            parts.unshift(args_child.children.first)
          else
            break
          end
          current = current.children.first  # Move to receiver
        end

        # Add the first element (not a + call)
        parts.unshift(current)

        # Only return if we have 3+ parts (worth optimizing)
        parts.size >= 3 ? parts : nil
      end

      # Check if typed_node is a String#+ call
      def string_plus_call?(typed_node)
        return false unless typed_node.respond_to?(:node)
        return false unless typed_node.node.respond_to?(:name)
        return false unless typed_node.node.name.to_s == "+"
        return false unless typed_node.node_type == :call

        # Check receiver type is String
        receiver_child = typed_node.children.first
        receiver_type = receiver_child&.type
        receiver_type == TypeChecker::Types::STRING
      end

      # Emit optimized string concatenation chain
      def emit_string_concat_chain(parts)
        # Visit each part to get HIR instructions
        visited_parts = parts.map { |part| visit(part) }

        result_var = new_temp_var
        inst = StringConcat.new(parts: visited_parts, result_var: result_var)
        emit(inst)
        inst
      end

      # Handle NativeClass method call
      def visit_native_method_call(typed_node)
        receiver_child = typed_node.children.first
        receiver = visit(receiver_child)
        native_class_type = resolve_native_class_type_from_receiver(receiver_child)
        method_name = typed_node.node.name.to_sym

        # Get method signature and owner class using Wren-style lookup
        native_classes_registry = @rbs_loader.native_classes
        method_sig = native_class_type.lookup_method(method_name, native_classes_registry)
        owner_class = native_class_type.find_method_owner(method_name, native_classes_registry)

        # Get arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args = args_child.children.map { |arg| visit(arg) }
        end

        result_var = new_temp_var
        inst = NativeMethodCall.new(
          receiver: receiver,
          method_name: method_name,
          args: args,
          class_type: native_class_type,
          method_sig: method_sig,
          owner_class: owner_class,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      def visit_block_def(typed_node)
        params = []
        if typed_node.node.parameters
          if typed_node.node.parameters.is_a?(Prism::NumberedParametersNode)
            # Numbered block parameters (_1, _2, ...)
            max = typed_node.node.parameters.maximum
            max.times do |i|
              params << Param.new(name: "_#{i + 1}", type: TypeChecker::Types::UNTYPED)
            end
          elsif typed_node.node.parameters.is_a?(Prism::ItParametersNode)
            # it block parameter (Ruby 3.4+)
            params << Param.new(name: "_it_param", type: TypeChecker::Types::UNTYPED)
          else
            params = build_block_params(typed_node.node.parameters)
          end
        end

        # Save current scope (including native_class_vars to prevent cross-block leakage)
        saved_local_vars = @local_vars.dup
        saved_native_class_vars = @native_class_vars.dup
        saved_current_block = @current_block
        saved_function = @current_function

        # Create a temporary container for block body
        # Don't add blocks to the current function - they'll be stored in BlockDef
        block_body = []
        @block_counter += 1
        entry = BasicBlock.new(label: "block_entry_#{@block_counter}")
        block_body << entry
        @current_block = entry

        # Create a temporary pseudo-function to collect block's basic blocks
        # Use a simple wrapper class that responds to body
        @current_function = BlockBodyCollector.new(block_body)

        # Add block parameters to local variables
        params.each do |param|
          @local_vars[param.name] = LocalVar.new(name: param.name, type: param.type)
        end

        # Compile block body
        body_result = nil
        typed_node.children.each do |child|
          # Skip block parameters node
          next if child.node.is_a?(Prism::BlockParametersNode) ||
                  child.node.is_a?(Prism::NumberedParametersNode) ||
                  child.node.is_a?(Prism::ItParametersNode)
          body_result = visit(child)
        end

        # Collect all blocks generated for this block body
        body_blocks = @current_function.body

        # Detect captured variables (variables from outer scope used in block)
        captures = detect_captured_variables(saved_local_vars)

        # Restore outer scope
        @local_vars = saved_local_vars
        @native_class_vars = saved_native_class_vars
        @current_block = saved_current_block
        @current_function = saved_function

        BlockDef.new(params: params, body: body_blocks, captures: captures)
      end

      # Lambda literal: ->(x) { x * 2 }
      def visit_lambda(typed_node)
        # Build block def from lambda body
        block_def = build_lambda_block(typed_node)

        # Create ProcNew instruction to wrap the block as a Proc object
        result_var = new_temp_var
        inst = ProcNew.new(block_def: block_def, result_var: result_var)
        emit(inst)
        inst
      end

      # Build a BlockDef from a lambda node
      def build_lambda_block(typed_node)
        params = []
        if typed_node.node.parameters
          if typed_node.node.parameters.is_a?(Prism::NumberedParametersNode)
            max = typed_node.node.parameters.maximum
            max.times do |i|
              params << Param.new(name: "_#{i + 1}", type: TypeChecker::Types::UNTYPED)
            end
          elsif typed_node.node.parameters.is_a?(Prism::ItParametersNode)
            params << Param.new(name: "_it_param", type: TypeChecker::Types::UNTYPED)
          else
            params = build_block_params(typed_node.node.parameters)
          end
        end

        # Save current scope (including native_class_vars to prevent cross-block leakage)
        saved_local_vars = @local_vars.dup
        saved_native_class_vars = @native_class_vars.dup
        saved_current_block = @current_block
        saved_function = @current_function

        # Create a temporary container for lambda body
        block_body = []
        @block_counter += 1
        entry = BasicBlock.new(label: "lambda_entry_#{@block_counter}")
        block_body << entry
        @current_block = entry

        # Create a temporary pseudo-function to collect lambda's basic blocks
        @current_function = BlockBodyCollector.new(block_body)

        # Add lambda parameters to local variables
        params.each do |param|
          @local_vars[param.name] = LocalVar.new(name: param.name, type: param.type)
        end

        # Compile lambda body
        body_result = nil
        typed_node.children.each do |child|
          # Skip parameters node
          next if child.node.is_a?(Prism::BlockParametersNode) ||
                  child.node.is_a?(Prism::NumberedParametersNode)
          body_result = visit(child)
        end

        # Collect all blocks generated for this lambda body
        body_blocks = @current_function.body

        # Detect captured variables
        captures = detect_captured_variables(saved_local_vars)

        # Restore outer scope
        @local_vars = saved_local_vars
        @native_class_vars = saved_native_class_vars
        @current_block = saved_current_block
        @current_function = saved_function

        BlockDef.new(params: params, body: body_blocks, captures: captures, is_lambda: true)
      end

      # Detect variables from outer scope that are used in the block
      def detect_captured_variables(outer_vars)
        # For now, capture all outer variables that exist
        # A more sophisticated approach would analyze actual usage
        outer_vars.keys.map do |name|
          Capture.new(name: name, type: outer_vars[name].type)
        end
      end

      def build_block_params(params_node)
        result = []
        params_node.parameters&.requireds&.each do |param|
          if param.respond_to?(:name)
            result << Param.new(name: param.name.to_s, type: TypeChecker::Types::UNTYPED)
          end
        end
        result
      end

      # Logical operators
      def visit_and(typed_node)
        # a && b: short-circuit evaluation
        # Evaluate left; if truthy, evaluate and return right; if falsy, return left
        left_val = visit(typed_node.children[0])

        right_block = new_block("and_right")
        merge_block = new_block("and_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: left_val,
          then_block: right_block.label,
          else_block: merge_block.label
        ))

        # Right branch (left was truthy)
        set_current_block(right_block)
        right_val = visit(typed_node.children[1])
        right_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        # Merge
        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => left_val,
            right_exit_block.label => right_val
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_or(typed_node)
        # a || b: short-circuit evaluation
        # Evaluate left; if truthy, return left; if falsy, evaluate and return right
        left_val = visit(typed_node.children[0])

        right_block = new_block("or_right")
        merge_block = new_block("or_merge")

        left_exit_block = @current_block
        @current_block.set_terminator(Branch.new(
          condition: left_val,
          then_block: merge_block.label,
          else_block: right_block.label
        ))

        # Right branch (left was falsy)
        set_current_block(right_block)
        right_val = visit(typed_node.children[1])
        right_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        # Merge
        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            left_exit_block.label => left_val,
            right_exit_block.label => right_val
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      # Control flow
      def visit_if(typed_node)
        condition = visit(typed_node.children[0])

        then_block = new_block("if_then")
        else_block = new_block("if_else")
        merge_block = new_block("if_merge")

        @current_block.set_terminator(Branch.new(
          condition: condition,
          then_block: then_block.label,
          else_block: else_block.label
        ))

        # Then branch
        set_current_block(then_block)
        then_result = typed_node.children[1] ? visit(typed_node.children[1]) : NilLit.new
        then_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        # Else branch
        set_current_block(else_block)
        else_result = typed_node.children[2] ? visit(typed_node.children[2]) : NilLit.new
        else_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        # Merge block with phi
        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            then_exit_block.label => then_result,
            else_exit_block.label => else_result
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_unless(typed_node)
        # Unless is just if with branches swapped
        condition = visit(typed_node.children[0])

        then_block = new_block("unless_then")
        else_block = new_block("unless_else")
        merge_block = new_block("unless_merge")

        # Note: branches are swapped compared to if
        @current_block.set_terminator(Branch.new(
          condition: condition,
          then_block: else_block.label,  # Swapped
          else_block: then_block.label   # Swapped
        ))

        # Then branch (executed when condition is false)
        set_current_block(then_block)
        then_result = typed_node.children[1] ? visit(typed_node.children[1]) : NilLit.new
        then_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        # Else branch (executed when condition is true)
        set_current_block(else_block)
        else_result = typed_node.children[2] ? visit(typed_node.children[2]) : NilLit.new
        else_exit_block = @current_block
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: merge_block.label))
        end

        set_current_block(merge_block)
        result_var = new_temp_var
        phi = Phi.new(
          incoming: {
            then_exit_block.label => then_result,
            else_exit_block.label => else_result
          },
          type: typed_node.type,
          result_var: result_var
        )
        emit(phi)
        phi
      end

      def visit_while(typed_node)
        cond_block = new_block("while_cond")
        body_block = new_block("while_body")
        exit_block = new_block("while_exit")

        # Initialize break value variable (for break-with-value support)
        break_val_name = "_break_val_#{exit_block.label}"
        break_val_var = LocalVar.new(name: break_val_name, type: TypeChecker::Types::UNTYPED)
        @local_vars[break_val_name] = break_val_var
        nil_init = NilLit.new(result_var: new_temp_var)
        emit(nil_init)
        emit(StoreLocal.new(var: break_val_var, value: nil_init, type: TypeChecker::Types::UNTYPED))

        @current_block.set_terminator(Jump.new(target: cond_block.label))

        # Condition
        set_current_block(cond_block)
        condition = visit(typed_node.children[0])
        @current_block.set_terminator(Branch.new(
          condition: condition,
          then_block: body_block.label,
          else_block: exit_block.label
        ))

        # Body
        set_current_block(body_block)
        @loop_stack.push({ cond_label: cond_block.label, exit_label: exit_block.label, break_val_var: break_val_var })
        visit(typed_node.children[1]) if typed_node.children[1]
        @loop_stack.pop
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: cond_block.label))
        end

        # Exit - load break value as loop result
        set_current_block(exit_block)
        load_break = LoadLocal.new(var: break_val_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
        emit(load_break)
        load_break
      end

      def visit_until(typed_node)
        cond_block = new_block("until_cond")
        body_block = new_block("until_body")
        exit_block = new_block("until_exit")

        # Initialize break value variable (for break-with-value support)
        break_val_name = "_break_val_#{exit_block.label}"
        break_val_var = LocalVar.new(name: break_val_name, type: TypeChecker::Types::UNTYPED)
        @local_vars[break_val_name] = break_val_var
        nil_init = NilLit.new(result_var: new_temp_var)
        emit(nil_init)
        emit(StoreLocal.new(var: break_val_var, value: nil_init, type: TypeChecker::Types::UNTYPED))

        @current_block.set_terminator(Jump.new(target: cond_block.label))

        # Condition
        set_current_block(cond_block)
        condition = visit(typed_node.children[0])
        # Inverted: exit when truthy, body when falsy
        @current_block.set_terminator(Branch.new(
          condition: condition,
          then_block: exit_block.label,
          else_block: body_block.label
        ))

        # Body
        set_current_block(body_block)
        @loop_stack.push({ cond_label: cond_block.label, exit_label: exit_block.label, break_val_var: break_val_var })
        visit(typed_node.children[1]) if typed_node.children[1]
        @loop_stack.pop
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: cond_block.label))
        end

        # Exit - load break value as loop result
        set_current_block(exit_block)
        load_break = LoadLocal.new(var: break_val_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
        emit(load_break)
        load_break
      end

      def visit_break(typed_node)
        if @loop_stack.any?
          loop_info = @loop_stack.last

          # Evaluate break value if present, otherwise nil
          if typed_node.children.any? && typed_node.children[0]
            break_val = visit(typed_node.children[0])
          else
            break_val = NilLit.new(result_var: new_temp_var)
            emit(break_val)
          end

          # Store break value for the loop to return
          if loop_info[:break_val_var]
            emit(StoreLocal.new(var: loop_info[:break_val_var], value: break_val, type: TypeChecker::Types::UNTYPED))
          end

          @current_block.set_terminator(Jump.new(target: loop_info[:exit_label]))
          # Create unreachable block for any code after break
          set_current_block(new_block("after_break"))
        end
        NilLit.new
      end

      def visit_next(typed_node)
        if @loop_stack.any?
          target = @loop_stack.last[:next_label] || @loop_stack.last[:cond_label]
          @current_block.set_terminator(Jump.new(target: target))
          # Create unreachable block for any code after next
          set_current_block(new_block("after_next"))
        end
        NilLit.new
      end

      def visit_for(typed_node)
        # Desugar for loop to index-based while loop:
        #   for x in collection do body end
        # =>
        #   _for_arr = collection.to_a   (or collection if array)
        #   _for_len = _for_arr.length
        #   _for_idx = 0
        #   while _for_idx < _for_len
        #     x = _for_arr[_for_idx]
        #     <body>
        #     _for_idx = _for_idx + 1
        #   end
        #
        # This supports break/next inside the for body (unlike block-based each).

        node = typed_node.node

        # Extract loop variable name from index (LocalVariableTargetNode)
        index_name = node.index.name.to_s

        # Visit collection
        collection_child = typed_node.children.find do |c|
          c.node_type != :local_variable_target && c.node_type != :statements
        end
        collection = visit(collection_child) if collection_child

        # Use unique suffixes for for-loop internal variables (supports nesting)
        for_id = new_temp_var

        # Convert to array via .to_a (handles Range and other Enumerables)
        arr_var = new_temp_var
        to_a_call = Call.new(
          receiver: collection,
          method_name: "to_a",
          args: [],
          type: TypeChecker::Types::UNTYPED,
          result_var: arr_var
        )
        emit(to_a_call)
        for_arr_name = "_for_arr_#{for_id}"
        for_arr_var = LocalVar.new(name: for_arr_name, type: TypeChecker::Types::UNTYPED)
        @local_vars[for_arr_name] = for_arr_var
        emit(StoreLocal.new(var: for_arr_var, value: to_a_call, type: TypeChecker::Types::UNTYPED))

        # _for_len = _for_arr.length
        len_var = new_temp_var
        arr_load = LoadLocal.new(var: for_arr_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
        emit(arr_load)
        len_call = Call.new(
          receiver: arr_load,
          method_name: "length",
          args: [],
          type: TypeChecker::Types::INTEGER,
          result_var: len_var
        )
        emit(len_call)
        for_len_name = "_for_len_#{for_id}"
        for_len_var = LocalVar.new(name: for_len_name, type: TypeChecker::Types::INTEGER)
        @local_vars[for_len_name] = for_len_var
        emit(StoreLocal.new(var: for_len_var, value: len_call, type: TypeChecker::Types::INTEGER))

        # _for_idx = 0
        zero_lit = IntegerLit.new(value: 0, result_var: new_temp_var)
        emit(zero_lit)
        for_idx_name = "_for_idx_#{for_id}"
        for_idx_var = LocalVar.new(name: for_idx_name, type: TypeChecker::Types::INTEGER)
        @local_vars[for_idx_name] = for_idx_var
        emit(StoreLocal.new(var: for_idx_var, value: zero_lit, type: TypeChecker::Types::INTEGER))

        # Create blocks
        cond_block = new_block("for_cond")
        body_block = new_block("for_body")
        incr_block = new_block("for_incr")
        exit_block = new_block("for_exit")

        # Initialize break value variable to the collection (for returns collection on normal exit)
        # break overrides this with nil or the break value
        break_val_name = "_break_val_#{exit_block.label}"
        break_val_var = LocalVar.new(name: break_val_name, type: TypeChecker::Types::UNTYPED)
        @local_vars[break_val_name] = break_val_var
        arr_ref = LoadLocal.new(var: for_arr_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
        emit(arr_ref)
        emit(StoreLocal.new(var: break_val_var, value: arr_ref, type: TypeChecker::Types::UNTYPED))

        @current_block.set_terminator(Jump.new(target: cond_block.label))

        # Condition: _for_idx < _for_len
        set_current_block(cond_block)
        idx_load_cond = LoadLocal.new(var: for_idx_var, type: TypeChecker::Types::INTEGER, result_var: new_temp_var)
        emit(idx_load_cond)
        len_load_cond = LoadLocal.new(var: for_len_var, type: TypeChecker::Types::INTEGER, result_var: new_temp_var)
        emit(len_load_cond)
        cmp_var = new_temp_var
        cmp_call = Call.new(
          receiver: idx_load_cond,
          method_name: "<",
          args: [len_load_cond],
          type: TypeChecker::Types::BOOL,
          result_var: cmp_var
        )
        emit(cmp_call)
        @current_block.set_terminator(Branch.new(
          condition: cmp_call,
          then_block: body_block.label,
          else_block: exit_block.label
        ))

        # Body: x = _for_arr[_for_idx]; <body>
        set_current_block(body_block)

        # x = _for_arr[_for_idx]
        arr_load_body = LoadLocal.new(var: for_arr_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
        emit(arr_load_body)
        idx_load_body = LoadLocal.new(var: for_idx_var, type: TypeChecker::Types::INTEGER, result_var: new_temp_var)
        emit(idx_load_body)
        elem_var = new_temp_var
        elem_call = Call.new(
          receiver: arr_load_body,
          method_name: "[]",
          args: [idx_load_body],
          type: TypeChecker::Types::UNTYPED,
          result_var: elem_var
        )
        emit(elem_call)
        loop_var = LocalVar.new(name: index_name, type: TypeChecker::Types::UNTYPED)
        @local_vars[index_name] = loop_var
        emit(StoreLocal.new(var: loop_var, value: elem_call, type: TypeChecker::Types::UNTYPED))

        # Push loop stack with next_label pointing to increment block
        @loop_stack.push({
          cond_label: cond_block.label,
          exit_label: exit_block.label,
          next_label: incr_block.label,
          break_val_var: break_val_var
        })

        # Compile body statements
        body_child = typed_node.children.find { |c| c.node_type == :statements }
        if body_child
          body_child.children.each do |stmt|
            visit(stmt)
          end
        end

        @loop_stack.pop

        # Jump to increment block (unless body already terminated via break/next)
        unless @current_block.terminator
          @current_block.set_terminator(Jump.new(target: incr_block.label))
        end

        # Increment block: _for_idx = _for_idx + 1
        set_current_block(incr_block)
        idx_load_incr = LoadLocal.new(var: for_idx_var, type: TypeChecker::Types::INTEGER, result_var: new_temp_var)
        emit(idx_load_incr)
        one_lit = IntegerLit.new(value: 1, result_var: new_temp_var)
        emit(one_lit)
        add_var = new_temp_var
        add_call = Call.new(
          receiver: idx_load_incr,
          method_name: "+",
          args: [one_lit],
          type: TypeChecker::Types::INTEGER,
          result_var: add_var
        )
        emit(add_call)
        emit(StoreLocal.new(var: for_idx_var, value: add_call, type: TypeChecker::Types::INTEGER))
        @current_block.set_terminator(Jump.new(target: cond_block.label))

        # Exit - load break value as loop result
        set_current_block(exit_block)
        load_break = LoadLocal.new(var: break_val_var, type: TypeChecker::Types::UNTYPED, result_var: new_temp_var)
        emit(load_break)
        load_break
      end

      # Range literal
      def visit_range(typed_node)
        left = typed_node.children[0] ? visit(typed_node.children[0]) : NilLit.new
        right = typed_node.children[1] ? visit(typed_node.children[1]) : NilLit.new
        exclusive = typed_node.node.is_a?(Prism::RangeNode) && typed_node.node.exclude_end?

        result_var = new_temp_var
        inst = RangeLit.new(
          left: left,
          right: right,
          exclusive: exclusive,
          type: typed_node.type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Global variable read/write
      def visit_global_variable_read(typed_node)
        name = typed_node.node.name.to_s
        result_var = new_temp_var
        inst = LoadGlobalVar.new(name: name, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_global_variable_write(typed_node)
        name = typed_node.node.name.to_s
        value = visit(typed_node.children.first)
        inst = StoreGlobalVar.new(name: name, value: value, type: typed_node.type)
        emit(inst)
        value
      end

      # Super call
      def visit_super(typed_node)
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args = args_child.children.map { |arg| visit(arg) }
        end

        result_var = new_temp_var
        inst = SuperCall.new(args: args, forward_args: false, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_forwarding_super(typed_node)
        result_var = new_temp_var
        inst = SuperCall.new(args: [], forward_args: true, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      # Multiple assignment
      def visit_multi_write(typed_node)
        # RHS value
        rhs = visit(typed_node.children.first)

        lefts = typed_node.node.lefts
        rest = typed_node.node.rest
        rights = typed_node.node.rights

        # Process left targets (before splat)
        lefts.each_with_index do |target, i|
          emit_multi_write_target(target, rhs, i)
        end

        # Process splat target: *rest
        if rest && rest.is_a?(Prism::SplatNode) && rest.expression
          target = rest.expression
          if target.is_a?(Prism::LocalVariableTargetNode)
            name = target.name.to_s
            splat_var = new_temp_var
            end_offset = rights ? rights.length : 0
            splat_inst = MultiWriteSplat.new(
              array: rhs, start_index: lefts.length, end_offset: end_offset,
              type: TypeChecker::Types::UNTYPED, result_var: splat_var
            )
            emit(splat_inst)

            var = @local_vars[name] ||= LocalVar.new(name: name, type: TypeChecker::Types::UNTYPED)
            store_inst = StoreLocal.new(var: var, value: splat_inst, type: TypeChecker::Types::UNTYPED)
            emit(store_inst)
          end
        end

        # Process right targets (after splat) — use negative indices from end
        if rights && !rights.empty?
          rights.each_with_index do |target, i|
            # Use negative index: rights[0] = arr[-rights.length], rights[1] = arr[-(rights.length-1)], etc.
            neg_index = -(rights.length - i)
            emit_multi_write_target(target, rhs, neg_index)
          end
        end

        rhs
      end

      def emit_multi_write_target(target, rhs, index)
        case target
        when Prism::LocalVariableTargetNode
          name = target.name.to_s
          elem_var = new_temp_var
          elem_inst = MultiWriteExtract.new(array: rhs, index: index, type: TypeChecker::Types::UNTYPED, result_var: elem_var)
          emit(elem_inst)

          var = @local_vars[name] ||= LocalVar.new(name: name, type: TypeChecker::Types::UNTYPED)
          store_inst = StoreLocal.new(var: var, value: elem_inst, type: TypeChecker::Types::UNTYPED)
          emit(store_inst)
        end
      end

      def visit_return(typed_node)
        value = typed_node.children.any? ? visit(typed_node.children.first) : NilLit.new
        @current_block.set_terminator(Return.new(value: value))
        value
      end

      def visit_self(typed_node)
        result_var = new_temp_var
        inst = SelfRef.new(type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_yield(typed_node)
        # Get yield arguments
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args = args_child.children.map { |arg| visit(arg) }
        end

        result_var = new_temp_var
        inst = Yield.new(args: args, type: typed_node.type, result_var: result_var)
        emit(inst)
        inst
      end

      def visit_begin(typed_node)
        # Handle begin/rescue/else/ensure blocks
        # Uses rb_rescue2 for exception handling

        # Find the statements (try block)
        statements_child = typed_node.children.find { |c| c.node_type == :statements }

        # Find rescue clause
        rescue_child = typed_node.children.find { |c| c.node_type == :rescue }

        # Find else clause (runs if no exception)
        else_child = typed_node.children.find { |c| c.node_type == :else }

        # Find ensure clause
        ensure_child = typed_node.children.find { |c| c.node_type == :ensure }

        result_var = new_temp_var

        # Collect try instructions (without creating new blocks)
        try_instructions = []
        if statements_child
          statements_child.children.each do |stmt|
            inst = visit(stmt)
            try_instructions << inst if inst
          end
        end

        # Record instruction count after try body - everything emitted after this
        # belongs to rescue/else/ensure (including sub-expressions)
        non_try_start_idx = @current_block.instructions.size

        # Build rescue clauses
        rescue_clauses = []
        if rescue_child
          rescue_clauses = build_rescue_clauses(rescue_child)
        end

        # Collect else instructions
        else_instructions = []
        if else_child
          else_statements = else_child.children.find { |c| c.node_type == :statements }
          if else_statements
            else_statements.children.each do |stmt|
              inst = visit(stmt)
              else_instructions << inst if inst
            end
          end
        end

        # Collect ensure instructions
        ensure_instructions = []
        if ensure_child
          ensure_statements = ensure_child.children.find { |c| c.node_type == :statements }
          if ensure_statements
            ensure_statements.children.each do |stmt|
              inst = visit(stmt)
              ensure_instructions << inst if inst
            end
          end
        end

        # Collect ALL instruction object_ids emitted during rescue/else/ensure visitation
        # This includes sub-expression instructions (e.g. StringLit for literal args)
        non_try_ids = Set.new
        @current_block.instructions[non_try_start_idx..].each do |i|
          non_try_ids << i.object_id
        end

        inst = BeginRescue.new(
          try_blocks: try_instructions,
          rescue_clauses: rescue_clauses,
          else_blocks: else_instructions,
          ensure_blocks: ensure_instructions,
          type: typed_node.type,
          result_var: result_var
        )
        inst.non_try_instruction_ids = non_try_ids
        emit(inst)
        inst
      end

      # Build rescue clauses from a rescue TypedNode
      # Handles chained rescue clauses via subsequent
      def build_rescue_clauses(rescue_typed_node)
        clauses = []
        current = rescue_typed_node

        while current
          # Extract exception classes from children
          exception_classes = []
          current.children.each do |child|
            if child.node_type == :constant_read || child.node_type == :constant_path
              exception_classes << extract_exception_class_name(child)
            end
          end

          # Extract exception variable from Prism AST node directly
          # node.reference is LocalVariableTargetNode for "=> e"
          exception_var = nil
          if current.node.respond_to?(:reference) && current.node.reference
            exception_var = current.node.reference.name.to_s
          end

          # Collect body instructions
          body_instructions = []
          statements_child = current.children.find { |c| c.node_type == :statements }
          if statements_child
            statements_child.children.each do |stmt|
              inst = visit(stmt)
              body_instructions << inst if inst
            end
          end

          clauses << RescueClause.new(
            exception_classes: exception_classes,
            exception_var: exception_var,
            body_blocks: body_instructions  # Now stores instructions, not blocks
          )

          # Follow linked list of rescue nodes via subsequent
          subsequent_child = current.children.find { |c| c.node_type == :rescue }
          current = subsequent_child
        end

        clauses
      end

      def visit_case(typed_node)
        # Handle case/when/else statements
        # case x
        # when 1 then "one"
        # when 2, 3 then "small"
        # else "other"
        # end

        result_var = new_temp_var

        # Find predicate (first child that's not when/else)
        predicate = nil
        typed_node.children.each do |child|
          unless [:when, :else].include?(child.node_type)
            predicate = visit(child)
            break
          end
        end

        # Record instruction count after predicate - everything after is when/else sub-instructions
        sub_start_idx = @current_block.instructions.size

        # Build when clauses
        when_clauses = []
        typed_node.children.select { |c| c.node_type == :when }.each do |when_child|
          when_clause = build_when_clause(when_child)
          when_clauses << when_clause
        end

        # Build else body
        else_body = nil
        else_child = typed_node.children.find { |c| c.node_type == :else }
        if else_child
          else_body = []
          else_statements = else_child.children.find { |c| c.node_type == :statements }
          if else_statements
            else_statements.children.each do |stmt|
              inst = visit(stmt)
              else_body << inst if inst
            end
          end
        end

        # Collect ALL instruction IDs emitted during when/else visitation
        sub_ids = Set.new
        @current_block.instructions[sub_start_idx..].each do |i|
          sub_ids << i.object_id
        end

        inst = CaseStatement.new(
          predicate: predicate,
          when_clauses: when_clauses,
          else_body: else_body,
          type: typed_node.type,
          result_var: result_var
        )
        inst.sub_instruction_ids = sub_ids
        emit(inst)
        inst
      end

      def build_when_clause(when_typed_node)
        # Extract conditions and body from when clause
        conditions = []
        body = []

        when_typed_node.children.each do |child|
          if child.node_type == :statements
            # This is the body
            child.children.each do |stmt|
              inst = visit(stmt)
              body << inst if inst
            end
          else
            # This is a condition
            conditions << visit(child)
          end
        end

        WhenClause.new(conditions: conditions, body: body)
      end

      # ========================================
      # Pattern Matching (case/in) support
      # ========================================

      def visit_case_match(typed_node)
        # Handle case/in pattern matching statements
        # case x
        # in 1 then "one"
        # in Integer => n then n.to_s
        # in [a, b] then a + b
        # else "other"
        # end

        result_var = new_temp_var

        # Find predicate (first non-in/else child)
        predicate = nil
        typed_node.children.each do |child|
          unless [:in, :else].include?(child.node_type)
            predicate = visit(child)
            break
          end
        end

        # Build in clauses
        in_clauses = []
        typed_node.children.select { |c| c.node_type == :in }.each do |in_child|
          in_clause = build_in_clause(in_child)
          in_clauses << in_clause
        end

        # Build else body
        # Use with_emit_to to redirect emitted instructions to the else_body array
        else_body = nil
        else_child = typed_node.children.find { |c| c.node_type == :else }
        if else_child
          else_body = []
          else_statements = else_child.children.find { |c| c.node_type == :statements }
          if else_statements
            with_emit_to(else_body) do
              else_statements.children.each do |stmt|
                visit(stmt)
              end
            end
          end
        end

        inst = CaseMatchStatement.new(
          predicate: predicate,
          in_clauses: in_clauses,
          else_body: else_body,
          type: typed_node.type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      def build_in_clause(in_typed_node)
        # Extract pattern, guard, and body from in clause
        # in pattern [if guard] then body
        pattern = nil
        guard = nil
        body = []
        bindings = {}

        # First pass: build pattern and collect bindings
        # In Prism, "in n if condition" is represented as InNode.pattern = IfNode
        # where IfNode.statements contains the actual pattern and IfNode.predicate is the guard
        in_typed_node.children.each do |child|
          next if child.node_type == :statements

          # First non-statements child is the pattern (or IfNode containing pattern + guard)
          if pattern.nil?
            if child.node_type == :if
              # This is a guard pattern: "in pattern if condition"
              # IfNode structure: children[0] = guard (CallNode), children[1] = StatementsNode containing pattern
              prism_if = child.node

              # Extract actual pattern from IfNode > StatementsNode > pattern
              statements_typed = child.children.find { |c| c.node_type == :statements }
              if statements_typed && !statements_typed.children.empty?
                pattern_typed = statements_typed.children.first
                if pattern_typed
                  pattern = build_pattern(pattern_typed)
                  bindings.merge!(pattern.bindings)
                end
              end

              # Extract guard condition (CallNode is direct child of IfNode)
              guard_typed = child.children.find { |c| c.node_type == :call }
              if guard_typed
                without_emit do
                  guard = visit(guard_typed)
                end
              end
            else
              pattern = build_pattern(child)
              bindings.merge!(pattern.bindings)
            end
          end
        end

        # Add pattern variables to scope before processing body
        bindings.each_key do |var_name|
          @local_vars[var_name] = LocalVar.new(name: var_name, type: TypeChecker::Types::UNTYPED)
        end

        # Second pass: build body with pattern variables in scope
        # Use with_emit_to to redirect emitted instructions to the body array
        # instead of the current block. This ensures that StoreLocal instructions
        # (from variable assignments like `captured = a`) are properly captured.
        with_emit_to(body) do
          in_typed_node.children.each do |child|
            case child.node_type
            when :statements
              # This is the body
              child.children.each do |stmt|
                visit(stmt)
              end
            end
          end
        end

        InClause.new(pattern: pattern, guard: guard, body: body, bindings: bindings)
      end

      def build_pattern(typed_node)
        # Convert TypedNode to HIR Pattern
        case typed_node.node_type
        when :integer, :float, :string, :symbol, :nil, :true, :false
          build_literal_pattern(typed_node)
        when :constant_read, :constant_path
          build_constant_pattern(typed_node)
        when :local_variable_target
          build_variable_pattern(typed_node)
        when :array_pattern
          build_array_pattern(typed_node)
        when :hash_pattern
          build_hash_pattern(typed_node)
        when :alternation_pattern
          build_alternation_pattern(typed_node)
        when :capture_pattern
          build_capture_pattern(typed_node)
        when :pinned_variable
          build_pinned_pattern(typed_node)
        when :pinned_expression
          build_pinned_expression_pattern(typed_node)
        when :find_pattern
          build_find_pattern(typed_node)
        when :splat
          build_rest_pattern(typed_node)
        when :assoc_splat
          build_keyword_rest_pattern(typed_node)
        when :if
          # Guard pattern: pattern if condition
          # In Prism, this appears as IfNode in certain contexts
          build_pattern(typed_node.children.first)
        else
          # Fallback: treat as literal pattern for unknown nodes
          # This handles cases like implicit variable binding (just identifier)
          if typed_node.node.respond_to?(:name)
            build_variable_pattern_from_name(typed_node.node.name.to_s)
          else
            # Create a literal pattern from the visited value
            value = visit(typed_node)
            LiteralPattern.new(value: value)
          end
        end
      end

      def build_literal_pattern(typed_node)
        value = visit(typed_node)
        LiteralPattern.new(value: value)
      end

      def build_constant_pattern(typed_node)
        constant_name = extract_pattern_constant_name(typed_node)
        narrowed_type = constant_name_to_type(constant_name)
        ConstantPattern.new(constant_name: constant_name, narrowed_type: narrowed_type)
      end

      # Convert a constant name (e.g., "Integer", "String") to an internal type
      # Used for type narrowing in pattern matching
      def constant_name_to_type(name)
        case name
        when "Integer" then TypeChecker::Types::INTEGER
        when "Float" then TypeChecker::Types::FLOAT
        when "String" then TypeChecker::Types::STRING
        when "Symbol" then TypeChecker::Types::SYMBOL
        when "Array" then TypeChecker::Types.array(TypeChecker::Types::UNTYPED)
        when "Hash" then TypeChecker::Types.hash_type(TypeChecker::Types::UNTYPED, TypeChecker::Types::UNTYPED)
        when "NilClass" then TypeChecker::Types::NIL
        when "TrueClass" then TypeChecker::Types::TRUE_CLASS
        when "FalseClass" then TypeChecker::Types::FALSE_CLASS
        when "Regexp" then TypeChecker::Types::REGEXP
        else
          # For user-defined classes, create a ClassInstance
          TypeChecker::Types::ClassInstance.new(name.to_sym)
        end
      end

      def build_variable_pattern(typed_node)
        name = typed_node.node.name.to_s
        VariablePattern.new(name: name)
      end

      def build_variable_pattern_from_name(name)
        VariablePattern.new(name: name)
      end

      def build_array_pattern(typed_node)
        constant = nil
        requireds = []
        rest = nil
        posts = []
        bindings = {}

        # Check for constant (e.g., Point[x, y])
        constant_child = typed_node.children.find { |c| [:constant_read, :constant_path].include?(c.node_type) }
        if constant_child
          constant = extract_pattern_constant_name(constant_child)
        end

        # Process requireds, rest, and posts from Prism node structure
        prism_node = typed_node.node
        if prism_node.respond_to?(:requireds)
          prism_node.requireds.each do |req|
            req_child = typed_node.children.find { |c| c.node == req }
            if req_child
              pattern = build_pattern(req_child)
              requireds << pattern
              bindings.merge!(pattern.bindings)
            end
          end
        end

        if prism_node.respond_to?(:rest) && prism_node.rest
          rest_child = typed_node.children.find { |c| c.node == prism_node.rest }
          if rest_child
            rest = build_rest_pattern(rest_child)
            bindings.merge!(rest.bindings)
          end
        end

        if prism_node.respond_to?(:posts)
          prism_node.posts.each do |post|
            post_child = typed_node.children.find { |c| c.node == post }
            if post_child
              pattern = build_pattern(post_child)
              posts << pattern
              bindings.merge!(pattern.bindings)
            end
          end
        end

        ArrayPattern.new(
          constant: constant,
          requireds: requireds,
          rest: rest,
          posts: posts,
          bindings: bindings
        )
      end

      def build_hash_pattern(typed_node)
        constant = nil
        elements = []
        rest = nil
        bindings = {}

        # Check for constant
        constant_child = typed_node.children.find { |c| [:constant_read, :constant_path].include?(c.node_type) }
        if constant_child
          constant = extract_pattern_constant_name(constant_child)
        end

        prism_node = typed_node.node
        if prism_node.respond_to?(:elements)
          prism_node.elements.each do |elem|
            elem_child = typed_node.children.find { |c| c.node == elem }
            if elem_child
              hash_elem = build_hash_pattern_element(elem_child)
              elements << hash_elem
              # Collect bindings from element
              if hash_elem.value_pattern
                bindings.merge!(hash_elem.value_pattern.bindings)
              else
                # Shorthand {x:} binds x
                bindings[hash_elem.key] = TypeChecker::Types::UNTYPED
              end
            end
          end
        end

        if prism_node.respond_to?(:rest) && prism_node.rest
          rest_child = typed_node.children.find { |c| c.node == prism_node.rest }
          if rest_child
            rest = build_keyword_rest_pattern(rest_child)
            bindings.merge!(rest.bindings)
          end
        end

        HashPattern.new(
          constant: constant,
          elements: elements,
          rest: rest,
          bindings: bindings
        )
      end

      def build_hash_pattern_element(typed_node)
        prism_node = typed_node.node
        key = nil
        value_pattern = nil

        if prism_node.respond_to?(:key)
          # Get key as string
          key_node = prism_node.key
          if key_node.respond_to?(:value)
            key = key_node.value.to_s
          elsif key_node.respond_to?(:name)
            key = key_node.name.to_s
          elsif key_node.respond_to?(:unescaped)
            key = key_node.unescaped.to_s
          end
        end

        if prism_node.respond_to?(:value) && prism_node.value
          # Check for implicit shorthand pattern {x:} which uses ImplicitNode
          if prism_node.value.class.name.to_s.include?("ImplicitNode")
            # Shorthand pattern: {x:} binds value to variable 'x'
            # value_pattern remains nil, handled by compile_hash_pattern as shorthand
          else
            value_child = typed_node.children.find { |c| c.node == prism_node.value }
            if value_child
              value_pattern = build_pattern(value_child)
            end
          end
        end

        HashPatternElement.new(key: key, value_pattern: value_pattern)
      end

      def build_alternation_pattern(typed_node)
        alternatives = []
        bindings = {}

        # Flatten the alternation tree
        collect_alternation_patterns(typed_node, alternatives, bindings)

        AlternationPattern.new(alternatives: alternatives, bindings: bindings)
      end

      def collect_alternation_patterns(typed_node, alternatives, bindings)
        if typed_node.node_type == :alternation_pattern
          # Left and right children
          typed_node.children.each do |child|
            collect_alternation_patterns(child, alternatives, bindings)
          end
        else
          pattern = build_pattern(typed_node)
          alternatives << pattern
          bindings.merge!(pattern.bindings)
        end
      end

      def build_capture_pattern(typed_node)
        prism_node = typed_node.node
        value_pattern = nil
        target = nil

        # value child is the pattern
        if prism_node.respond_to?(:value)
          value_child = typed_node.children.find { |c| c.node == prism_node.value }
          if value_child
            value_pattern = build_pattern(value_child)
          end
        end

        # target is the variable to bind
        if prism_node.respond_to?(:target)
          target_node = prism_node.target
          if target_node.respond_to?(:name)
            target = target_node.name.to_s
          end
        end

        CapturePattern.new(value_pattern: value_pattern, target: target)
      end

      def build_pinned_pattern(typed_node)
        prism_node = typed_node.node
        variable_name = nil

        if prism_node.respond_to?(:variable)
          var_node = prism_node.variable
          if var_node.respond_to?(:name)
            variable_name = var_node.name.to_s
          end
        end

        PinnedPattern.new(variable_name: variable_name)
      end

      def build_pinned_expression_pattern(typed_node)
        # ^(expr) - treat the expression result as a value to match
        # For now, build as a pinned pattern with the expression
        prism_node = typed_node.node
        if prism_node.respond_to?(:expression)
          expr_child = typed_node.children.find { |c| c.node == prism_node.expression }
          if expr_child
            # Create a literal pattern with the expression value
            value = visit(expr_child)
            return LiteralPattern.new(value: value)
          end
        end
        # Fallback
        LiteralPattern.new(value: NilLit.new)
      end

      def build_find_pattern(typed_node)
        # [*pre, pattern, *post] find pattern
        # Not commonly used, basic implementation
        prism_node = typed_node.node
        requireds = []
        bindings = {}

        if prism_node.respond_to?(:requireds)
          prism_node.requireds.each do |req|
            req_child = typed_node.children.find { |c| c.node == req }
            if req_child
              pattern = build_pattern(req_child)
              requireds << pattern
              bindings.merge!(pattern.bindings)
            end
          end
        end

        # For simplicity, treat find pattern as array pattern with wildcards
        ArrayPattern.new(
          requireds: requireds,
          bindings: bindings
        )
      end

      def build_rest_pattern(typed_node)
        name = nil
        prism_node = typed_node.node

        if prism_node.respond_to?(:expression) && prism_node.expression
          expr = prism_node.expression
          if expr.respond_to?(:name)
            name = expr.name.to_s
          end
        end

        RestPattern.new(name: name)
      end

      def build_keyword_rest_pattern(typed_node)
        name = nil
        prism_node = typed_node.node

        if prism_node.respond_to?(:value) && prism_node.value
          val = prism_node.value
          if val.respond_to?(:name)
            name = val.name.to_s
          end
        end

        bindings = name ? { name => TypeChecker::Types::HASH } : {}
        RestPattern.new(name: name, bindings: bindings)
      end

      def extract_pattern_constant_name(typed_node)
        case typed_node.node_type
        when :constant_read
          typed_node.node.name.to_s
        when :constant_path
          parts = []
          node = typed_node.node
          while node
            parts.unshift(node.name.to_s) if node.respond_to?(:name)
            node = node.respond_to?(:parent) ? node.parent : nil
          end
          parts.join("::")
        else
          nil
        end
      end

      def visit_match_predicate(typed_node)
        # expr in pattern (returns boolean)
        result_var = new_temp_var

        value = visit(typed_node.children[0])
        pattern = build_pattern(typed_node.children[1])

        inst = MatchPredicate.new(
          value: value,
          pattern: pattern,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      def visit_match_required(typed_node)
        # expr => pattern (raises on failure)
        result_var = new_temp_var

        value = visit(typed_node.children[0])
        pattern = build_pattern(typed_node.children[1])

        inst = MatchRequired.new(
          value: value,
          pattern: pattern,
          type: typed_node.type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Extract exception class name from a constant read or constant path TypedNode
      def extract_exception_class_name(typed_node)
        case typed_node.node_type
        when :constant_read
          typed_node.node.name.to_s
        when :constant_path
          # Handle nested constants like Module::Error
          parts = []
          node = typed_node.node
          while node
            parts.unshift(node.name.to_s) if node.respond_to?(:name)
            node = node.respond_to?(:parent) ? node.parent : nil
          end
          parts.join("::")
        else
          "StandardError"
        end
      end

      def visit_raise(typed_node)
        # Handle raise statements
        # For now, just call Kernel#raise via method call
        args = []
        args_child = typed_node.children.find { |c| c.node_type == :arguments }
        if args_child
          args = args_child.children.map { |arg| visit(arg) }
        end

        result_var = new_temp_var
        inst = Call.new(
          receiver: SelfRef.new(type: TypeChecker::Types::UNTYPED),
          method_name: "raise",
          args: args,
          type: typed_node.type,
          result_var: result_var
        )
        emit(inst)
        inst
      end

      # Helpers
      def with_function(func)
        old_function = @current_function
        old_block = @current_block
        old_vars = @local_vars
        old_native_class_vars = @native_class_vars.dup

        @current_function = func
        @current_block = nil
        @local_vars = {}
        @native_class_vars = {}

        yield

        @current_function = old_function
        @current_block = old_block
        @local_vars = old_vars
        @native_class_vars = old_native_class_vars
      end

      def new_block(prefix = "block")
        @block_counter += 1
        block = BasicBlock.new(label: "#{prefix}_#{@block_counter}")
        @current_function.body << block
        block
      end

      def set_current_block(block)
        @current_block = block
      end

      def emit(instruction)
        return if @suppress_emit
        if @emit_collector
          @emit_collector << instruction
        else
          @current_block.add_instruction(instruction) if @current_block
        end
      end

      def without_emit
        old_suppress = @suppress_emit
        @suppress_emit = true
        result = yield
        @suppress_emit = old_suppress
        result
      end

      # Redirect emitted instructions to the given array instead of the current block.
      # Used for building case/in clause bodies where we need to capture all emitted
      # instructions (including StoreLocal from variable assignments) without adding
      # them to the current basic block.
      def with_emit_to(collector)
        old_collector = @emit_collector
        @emit_collector = collector
        yield
      ensure
        @emit_collector = old_collector
      end

      # Extract a literal value from a typed node without emitting instructions.
      # Used for class/module body constant and class variable initializations.
      # Returns an HIR literal node (IntegerLit, FloatLit, StringLit, etc.) or visits the node.
      def visit_literal_value(typed_node)
        return NilLit.new unless typed_node

        case typed_node.node_type
        when :integer
          IntegerLit.new(value: typed_node.node.value)
        when :float
          FloatLit.new(value: typed_node.node.value)
        when :string
          StringLit.new(value: typed_node.node.unescaped)
        when :symbol
          SymbolLit.new(value: typed_node.node.value.to_s)
        when :true
          BoolLit.new(value: true)
        when :false
          BoolLit.new(value: false)
        when :nil
          NilLit.new
        else
          # For non-literal values, try visiting but suppress emit
          without_emit { visit(typed_node) }
        end
      end

      def new_temp_var
        @var_counter += 1
        "t#{@var_counter}"
      end
    end
  end
end
