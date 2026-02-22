# frozen_string_literal: true

require_relative "types"
require_relative "unification"

module Konpeito
  module TypeChecker
    # Hindley-Milner style type inference
    # Uses Algorithm W with constraint generation and unification
    class HMInferrer
      attr_reader :errors, :unifier, :node_types, :diagnostics, :ivar_types, :inference_errors,
                  :unresolved_type_warnings

      def initialize(rbs_loader = nil, file_path: nil, source: nil)
        @rbs_loader = rbs_loader
        @file_path = file_path
        @source = source
        @errors = []
        @diagnostics = []  # Diagnostic objects for rich error messages
        @unifier = Unifier.new
        @env = [{}]  # Stack of name -> TypeScheme
        @function_types = {}  # Function name -> FunctionType
        @class_init_types = {}  # ClassName -> FunctionType for initialize
        @node_types = {}  # Node location -> Type (for AST building)
        @current_class_name = nil  # Current class context for ivar tracking
        @current_method_name = nil  # Current method name for super resolution
        @class_parents = {}  # ClassName -> ParentClassName (for super type propagation)
        @ivar_types = {}  # { "ClassName" => { "@name" => Type } }
        @in_class_collect = false  # Track if inside class during signature collection
        @collect_class_name = nil  # Current class name during signature collection
        @inference_errors = []  # Collected type inference errors
        @global_var_types = {}  # Global variable type tracking
        @cvar_types = {}  # Class variable tracking: { "ClassName" => { "@@var" => Type } }
        @deferred_constraints = []  # Deferred method resolution for TypeVar receivers
        @keyword_param_vars = {}  # func_key => { :param_name => TypeVar }
        @unresolved_type_warnings = []  # Warnings for types that survived inference
        @polymorphic_methods = {}  # qualified_key => TypeScheme for instance methods
      end

      # Main entry: infer types for a program AST
      def analyze(node)
        # First pass: collect function signatures
        collect_function_signatures(node)

        # Second pass: infer and unify
        infer(node)

        # Third pass: resolve deferred constraints (TypeVar receivers now resolved by call-sites)
        resolve_deferred_constraints

        # Fourth pass: resolve ivar types using unification results
        resolve_ivar_types!

        # Fifth pass: validate all types are resolved (Kotlin-style: no TypeVar survives to codegen)
        validate_all_types_resolved!
      end

      # Infer type of an expression
      # Infer type of a node
      # @param node [Prism::Node] the AST node
      # @param statement_position [Boolean] if true, the result of this node is not used
      #   (e.g., non-last statements in a block). In statement position, if/unless
      #   branches don't need to have consistent types.
      def infer(node, statement_position: false)
        return Types::UNTYPED unless node

        method_name = :"infer_#{node_type(node)}"
        type = if respond_to?(method_name, true)
          # Pass statement_position to if/unless handlers
          if [:infer_if, :infer_unless].include?(method_name)
            send(method_name, node, statement_position: statement_position)
          else
            send(method_name, node)
          end
        else
          Types::UNTYPED
        end

        # Record type for this node (by location key)
        record_node_type(node, type)
        type
      rescue UnificationError => e
        @errors << e
        record_diagnostic_from_unification_error(e, node)
        record_node_type(node, Types::UNTYPED)
        Types::UNTYPED
      end

      # Record a diagnostic from a UnificationError
      def record_diagnostic_from_unification_error(error, node)
        return unless @file_path

        actual_node = error.node || node
        span = create_span_from_node(actual_node)
        return unless span

        diagnostic = Diagnostics::Diagnostic.type_mismatch(
          expected: format_type(error.type1),
          found: format_type(error.type2),
          span: span
        )
        @diagnostics << diagnostic
      end

      # Create a SourceSpan from a Prism node
      def create_span_from_node(node)
        return nil unless node&.respond_to?(:location) && node.location

        Diagnostics::SourceSpan.from_prism_location(
          node.location,
          file_path: @file_path,
          source: @source
        )
      end

      # Format a type for display
      def format_type(type)
        case type
        when TypeVar
          if type.instance
            format_type(type.instance)
          else
            type.to_s
          end
        when FunctionType
          params = type.param_types.map { |t| format_type(t) }.join(", ")
          "(#{params}) -> #{format_type(type.return_type)}"
        when Types::ClassInstance
          if type.type_args.empty?
            type.name.to_s
          else
            args = type.type_args.map { |a| format_type(a) }.join(", ")
            "#{type.name}[#{args}]"
          end
        else
          type.to_s
        end
      end

      # Get the finalized type for a node
      def type_for(node)
        return Types::UNTYPED unless node

        key = node_key(node)
        type = @node_types[key]
        type ? finalize(type) : Types::UNTYPED
      end

      # Get final type after applying all substitutions
      def finalize(type)
        @unifier.apply(type)
      end

      private

      def node_type(node)
        node.class.name.split("::").last.sub(/Node$/, "").gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      # Record type for a node (keyed by location)
      def record_node_type(node, type)
        key = node_key(node)
        @node_types[key] = type if key
      end

      # Extract full constant path name from ConstantPathNode
      # e.g., Java::Konpeito::Canvas::Canvas → "Java::Konpeito::Canvas::Canvas"
      def extract_constant_path_name(node)
        parts = []
        current = node
        while current.is_a?(Prism::ConstantPathNode)
          parts.unshift(current.name.to_s)
          current = current.parent
        end
        parts.unshift(current.name.to_s) if current.respond_to?(:name)
        parts.join("::")
      end

      # Generate unique key for a node based on its location
      def node_key(node)
        # Use object_id for unique keys — avoids collisions across merged files
        # (different files can have nodes at same byte offsets)
        node.object_id
      end

      # Environment management
      def push_env
        @env.push({})
      end

      def pop_env
        @env.pop
      end

      def lookup(name)
        @env.reverse_each do |scope|
          return scope[name.to_sym] if scope.key?(name.to_sym)
        end
        nil
      end

      def bind(name, type)
        # For now, bind monomorphic types
        # Full let-polymorphism would generalize here
        @env.last[name.to_sym] = TypeScheme.new([], type)
      end

      def bind_scheme(name, scheme)
        @env.last[name.to_sym] = scheme
      end

      # Collect function signatures (first pass)
      # NOTE: Uses node_type() dispatch instead of case/when because
      # Prism::Node === check returns false in Ruby 4.0 for merged ASTs
      def collect_function_signatures(node)
        return unless node

        ntype = node_type(node)
        case ntype
        when "program"
          node.statements.body.each { |n| collect_function_signatures(n) }
        when "statements"
          node.body.each { |n| collect_function_signatures(n) }
        when "def"
          # Try to get type signature from RBS first
          actual_param_count = (node.parameters&.requireds || []).size
          func_type = get_rbs_function_type(node.name.to_sym, class_name: @collect_class_name)

          # Reject RBS type if param count doesn't match actual code
          # (e.g., inherited Object#initialize has 0 params but user def has params)
          if func_type && func_type.param_types.size != actual_param_count
            func_type = nil
          end
          # Also reject RBS type if method has rest param but RBS doesn't account for it
          # (ensures rest_param_type TypeVar gets created for *args methods)
          has_rest = node.parameters&.rest.is_a?(Prism::RestParameterNode) && node.parameters.rest.name
          if func_type && has_rest && !func_type.rest_param_type
            func_type = nil
          end

          # Keep untyped return types as UNTYPED (not replaced with TypeVar).
          # When RBS explicitly declares untyped, the return value may depend on
          # runtime polymorphism (e.g., overridden methods) that HM can't track.

          # Keep untyped param types as UNTYPED (not replaced with TypeVar).
          # UNTYPED means "any type is acceptable" — method calls on UNTYPED receivers
          # are allowed without constraint. TypeVar replacement would create unresolvable
          # type variables when HM can't determine the type from method body alone
          # (e.g., duck-typed painter/event params in UI frameworks).

          unless func_type
            # Create fresh type variables for parameters and return
            param_types = (node.parameters&.requireds || []).map { TypeVar.new }
            return_type = TypeVar.new
            rest_param_type = nil
            if node.parameters&.rest.is_a?(Prism::RestParameterNode) && node.parameters.rest.name
              rest_param_type = TypeVar.new
            end
            func_type = FunctionType.new(param_types, return_type, rest_param_type: rest_param_type)
          end

          # Create TypeVars for keyword parameters (both required and optional)
          keywords = node.parameters&.keywords || []
          unless keywords.empty?
            kw_vars = {}
            keywords.each do |kw|
              kw_vars[kw.name] = TypeVar.new(kw.name.to_s)
            end
            # Store with both qualified and unqualified keys
            if @in_class_collect && @collect_class_name
              @keyword_param_vars[:"#{@collect_class_name}##{node.name}"] = kw_vars
            end
            @keyword_param_vars[node.name.to_sym] = kw_vars
          end

          # Use class-qualified key for class methods to avoid cross-class collision
          if @in_class_collect && @collect_class_name
            qualified_key = :"#{@collect_class_name}##{node.name}"
            @function_types[qualified_key] = func_type
            @class_init_types[@collect_class_name] = func_type if node.name.to_sym == :initialize

            # When overriding a parent method, unify parameter TypeVars
            # so that call-site type info flows to all overrides
            parent_cls = @class_parents[@collect_class_name]
            while parent_cls
              parent_key = :"#{parent_cls}##{node.name}"
              parent_func = @function_types[parent_key]
              if parent_func.is_a?(FunctionType)
                parent_func.param_types.zip(func_type.param_types).each do |parent_t, child_t|
                  if parent_t && child_t
                    begin
                      @unifier.unify(parent_t, child_t)
                    rescue UnificationError
                      # Different param types — acceptable for polymorphic overrides
                    end
                  end
                end
                # Also unify rest_param_types if both have them
                if parent_func.rest_param_type && func_type.rest_param_type
                  begin
                    @unifier.unify(parent_func.rest_param_type, func_type.rest_param_type)
                  rescue UnificationError
                  end
                end
                break
              end
              parent_cls = @class_parents[parent_cls]
            end
          end
          @function_types[node.name.to_sym] = func_type

          if @in_class_collect
            is_class_method = node.receiver.is_a?(Prism::SelfNode) rescue false
            is_initialize = node.name.to_sym == :initialize
            if is_class_method || is_initialize
              # Class methods and initialize: monomorphic binding — call-site unification
              # flows into method body. This allows argument types (e.g., Array from call
              # site) to be visible in method body.
              bind_scheme(node.name, TypeScheme.new([], func_type))
            else
              # Instance methods: polymorphic binding — each call site gets fresh type
              # variables. This allows methods like []= to accept different types at
              # different call sites (e.g., c["name"] = "Alice"; c["age"] = 30).
              all_vars = collect_type_vars(func_type)
              scheme = TypeScheme.new(all_vars, func_type)
              bind_scheme(node.name, scheme)
              # Mark this method as polymorphic for receiver-based call resolution.
              # The actual scheme will be created lazily at the first call site,
              # after body inference has established internal TypeVar linkages.
              if @collect_class_name && !all_vars.empty?
                @polymorphic_methods[:"#{@collect_class_name}##{node.name}"] = true
              end
            end
          else
            # Top-level functions: generalize to type scheme (all type vars are quantified)
            all_vars = collect_type_vars(func_type)
            bind_scheme(node.name, TypeScheme.new(all_vars, func_type))
          end
        when "class"
          old_in_class = @in_class_collect
          old_class_name = @collect_class_name
          @in_class_collect = true
          @collect_class_name = (node.constant_path.name.to_s rescue nil)
          # Track parent class for super type propagation
          parent_name = nil
          if @collect_class_name && node.superclass
            parent_name = node.superclass.name.to_s rescue nil
            @class_parents[@collect_class_name] = parent_name if parent_name
          end
          # Register user-defined class hierarchy for subtype checking
          if @collect_class_name
            ancestors = []
            current_parent = parent_name
            while current_parent
              ancestors << current_parent.to_sym
              current_parent = @class_parents[current_parent]
            end
            ancestors << :Object unless ancestors.include?(:Object)
            Types::ClassInstance.register_class_hierarchy(@collect_class_name, ancestors)
          end
          collect_function_signatures(node.body) if node.body
          @in_class_collect = old_in_class
          @collect_class_name = old_class_name
        end
      end

      # Get function type from RBS if available
      def get_rbs_function_type(method_name, class_name: nil)
        return nil unless @rbs_loader&.loaded?

        # Try class-specific lookup first (for methods defined inside a class)
        if class_name
          begin
            method_types = @rbs_loader.direct_method_type(class_name.to_sym, method_name)
            if method_types && !method_types.empty?
              return convert_rbs_method_type(method_types.first)
            end
          rescue
            # Ignore errors from class-specific lookup
          end
        end

        # Try TopLevel using direct lookup (avoids inheritance conflicts)
        method_types = @rbs_loader.direct_method_type(:TopLevel, method_name)
        if method_types && !method_types.empty?
          return convert_rbs_method_type(method_types.first)
        end

        # Fall back to Object and Kernel using full definition builder
        %i[Object Kernel].each do |klass|
          begin
            method_types = @rbs_loader.method_type(klass, method_name)
            next unless method_types && !method_types.empty?

            return convert_rbs_method_type(method_types.first)
          rescue RBS::DuplicatedMethodDefinitionError
            # Skip classes with method conflicts (e.g., Object/Kernel from stdlib)
            next
          end
        end

        nil
      end

      # Convert RBS method type to internal FunctionType
      def convert_rbs_method_type(method_type)
        # Guard against UntypedFunction
        if method_type.type.is_a?(RBS::Types::UntypedFunction)
          return Types::FunctionType.new([], Types::UNTYPED)
        end

        param_types = method_type.type.required_positionals.map do |param|
          rbs_type_to_internal(param.type)
        end

        return_type = rbs_type_to_internal(method_type.type.return_type)

        # Extract rest_param_type from RBS rest_positionals (*args)
        rest_param_type = nil
        if method_type.type.rest_positionals
          rest_param_type = rbs_type_to_internal(method_type.type.rest_positionals.type)
        end

        FunctionType.new(param_types, return_type, rest_param_type: rest_param_type)
      end

      # Convert RBS type to internal type
      def rbs_type_to_internal(rbs_type)
        case rbs_type
        when RBS::Types::ClassInstance
          name = rbs_type.name.name
          args = rbs_type.args.map { |a| rbs_type_to_internal(a) }
          Types::ClassInstance.new(name, args)
        when RBS::Types::Variable
          TypeVar.new(rbs_type.name.to_s)
        when RBS::Types::Bases::Nil, RBS::Types::Bases::Void
          Types::NIL
        when RBS::Types::Bases::Bool
          Types::BOOL
        when RBS::Types::Bases::Any, RBS::Types::Bases::Top
          Types::UNTYPED
        when RBS::Types::Optional
          inner = rbs_type_to_internal(rbs_type.type)
          Types.optional(inner)
        when RBS::Types::Union
          types = rbs_type.types.map { |t| rbs_type_to_internal(t) }
          Types.union(*types)
        when RBS::Types::Alias
          case rbs_type.name.name
          when :string then Types::STRING
          when :int then Types::INTEGER
          when :float then Types::FLOAT
          when :bool then Types::BOOL
          else Types::UNTYPED
          end
        else
          Types::UNTYPED
        end
      end

      # Collect type variables from a type
      def collect_type_vars(type)
        vars = []
        case type
        when TypeVar
          vars << type
        when FunctionType
          type.param_types.each { |t| vars.concat(collect_type_vars(t)) }
          vars.concat(collect_type_vars(type.rest_param_type)) if type.rest_param_type
          vars.concat(collect_type_vars(type.return_type))
        when Types::ClassInstance
          type.type_args.each { |t| vars.concat(collect_type_vars(t)) }
        end
        vars.uniq
      end

      # Literals
      def infer_integer(_node)
        Types::INTEGER
      end

      def infer_float(_node)
        Types::FLOAT
      end

      def infer_string(_node)
        Types::STRING
      end

      def infer_symbol(_node)
        Types::SYMBOL
      end

      def infer_interpolated_string(node)
        # Infer types for embedded expressions (for side effects and error detection)
        node.parts.each do |part|
          case part
          when Prism::EmbeddedStatementsNode
            infer(part.statements) if part.statements
          end
        end
        Types::STRING
      end

      def infer_interpolated_symbol(node)
        # Infer types for embedded expressions
        node.parts.each do |part|
          case part
          when Prism::EmbeddedStatementsNode
            infer(part.statements) if part.statements
          end
        end
        Types::SYMBOL
      end

      def infer_regular_expression(_node)
        Types::REGEXP
      end

      # Constant lookup (e.g., NativeHash, Array, etc.)
      # Returns a special ClassType to represent the class itself (for class method calls)
      def infer_constant_read(node)
        class_name = node.name.to_sym

        # Check if this constant was bound as a value constant (e.g., EXPANDING = 2).
        # Value constants return their concrete type (Integer, Float, etc.).
        # Class constants (Column, Widget, etc.) are not bound via infer_constant_write,
        # so lookup returns nil and we fall through to ClassSingleton.
        scheme = lookup(class_name)
        if scheme
          result = scheme.instantiate
          return result unless result.is_a?(FunctionType)
        end

        # Return a singleton type that represents the class (not an instance)
        # This will be used to look up class methods (singleton methods)
        # Works both with and without RBS - user-defined classes are always ClassSingleton
        Types::ClassSingleton.new(class_name)
      end

      # ConstantPathNode: Java::Konpeito::Canvas::Canvas
      def infer_constant_path(node)
        name = extract_constant_path_name(node)
        Types::ClassSingleton.new(name.to_sym)
      end

      def infer_constant_write(node)
        value_type = infer(node.value)
        # Track the alias in env for later lookups
        bind(node.name.to_s, value_type)
        value_type
      end

      def infer_interpolated_regular_expression(node)
        # Infer types for embedded expressions
        node.parts.each do |part|
          case part
          when Prism::EmbeddedStatementsNode
            infer(part.statements) if part.statements
          end
        end
        Types::REGEXP
      end

      def infer_true(_node)
        Types::TRUE_CLASS
      end

      def infer_false(_node)
        Types::FALSE_CLASS
      end

      def infer_nil(_node)
        Types::NIL
      end

      # Variables
      def infer_local_variable_read(node)
        scheme = lookup(node.name)
        if scheme
          scheme.instantiate
        else
          # Unknown variable, create fresh type var
          tv = TypeVar.new(node.name.to_s)
          bind(node.name, tv)
          tv
        end
      end

      # it block parameter (Ruby 3.4+) - reads the implicit _it_param
      def infer_it_local_variable_read(_node)
        scheme = lookup(:_it_param)
        if scheme
          scheme.instantiate
        else
          tv = TypeVar.new("_it_param")
          bind(:_it_param, tv)
          tv
        end
      end

      def infer_local_variable_write(node)
        value_type = infer(node.value)
        existing = lookup(node.name)

        if existing
          existing_type = existing.instantiate
          if existing_type.is_a?(FunctionType)
            # Local variable shadows a method name (e.g., `bg = value` shadows `def bg(c)`)
            # In Ruby, local variables always take precedence over methods.
            # Create a new local variable binding instead of unifying with the method type.
            bind(node.name, value_type)
          else
            # Variable already exists, unify with new value
            @unifier.unify(existing_type, value_type)
          end
          value_type
        else
          # New variable
          bind(node.name, value_type)
          value_type
        end
      end

      # Array
      def infer_array(node)
        if node.elements.empty?
          Types.array(TypeVar.new)
        else
          element_type = TypeVar.new
          heterogeneous = false
          has_unresolved_typevar = false
          node.elements.each do |elem|
            elem_type = infer(elem)
            # Don't unify unresolved TypeVars (e.g., from deferred constraints) with
            # concrete element types. This prevents contamination: in [i, line, 0],
            # if line is a deferred TypeVar, unifying it with Integer (from i/0) would
            # incorrectly set line's type to Integer when it should be String.
            resolved_elem = @unifier.apply(elem_type)
            if resolved_elem.is_a?(TypeVar)
              has_unresolved_typevar = true
              next
            end
            begin
              @unifier.unify(element_type, elem_type)
            rescue UnificationError
              # Heterogeneous array (e.g., [widget, point]) — use untyped element
              heterogeneous = true
            end
          end
          if heterogeneous || has_unresolved_typevar
            Types.array(Types::UNTYPED)
          else
            Types.array(@unifier.apply(element_type))
          end
        end
      end

      # Hash
      def infer_hash(node)
        if node.elements.empty?
          Types.hash_type(TypeVar.new, TypeVar.new)
        else
          key_type = TypeVar.new
          value_type = TypeVar.new
          key_fallback = false
          value_fallback = false

          node.elements.each do |elem|
            if elem.is_a?(Prism::AssocNode)
              begin
                @unifier.unify(key_type, infer(elem.key)) unless key_fallback
              rescue UnificationError
                # Mixed key types (e.g., String and Symbol keys) — fall back to UNTYPED
                key_fallback = true
              end
              begin
                @unifier.unify(value_type, infer(elem.value)) unless value_fallback
              rescue UnificationError
                # Mixed value types (e.g., {name: "alice", age: 30}) — fall back to UNTYPED
                # This is common in Ruby and should not be a compilation error.
                value_fallback = true
              end
            end
          end

          resolved_key = key_fallback ? Types::UNTYPED : @unifier.apply(key_type)
          resolved_value = value_fallback ? Types::UNTYPED : @unifier.apply(value_type)
          Types.hash_type(resolved_key, resolved_value)
        end
      end

      # Unify keyword args from call site with function's keyword param TypeVars
      # Unify call-site argument types with function parameter types,
      # including excess args against rest_param_type (for *args methods).
      def unify_call_args(func_type, arg_types)
        # Unify required params
        func_type.param_types.zip(arg_types).each do |param_t, arg_t|
          @unifier.unify(param_t, arg_t) if arg_t && param_t
        end
        # Unify excess args with rest_param_type
        if func_type.rest_param_type && arg_types.size > func_type.param_types.size
          arg_types[func_type.param_types.size..].each do |arg_t|
            @unifier.unify(func_type.rest_param_type, arg_t) if arg_t
          end
        end
      end

      def unify_keyword_args(node, func_key)
        return unless node.arguments

        kw_vars = @keyword_param_vars[func_key]
        return unless kw_vars

        node.arguments.arguments.each do |arg|
          next unless arg.is_a?(Prism::KeywordHashNode)

          arg.elements.each do |elem|
            next unless elem.is_a?(Prism::AssocNode)

            # Extract keyword name from the key
            key_name = case elem.key
            when Prism::SymbolNode then elem.key.unescaped.to_sym
            else next
            end

            param_var = kw_vars[key_name]
            next unless param_var

            value_type = infer(elem.value)
            begin
              @unifier.unify(param_var, value_type)
            rescue UnificationError
              # Type mismatch for keyword arg — continue
            end
          end
        end
      end

      # Method call - this is where unification shines
      def infer_call(node)
        # Get receiver type
        receiver_type = node.receiver ? infer(node.receiver) : Types::UNTYPED
        receiver_type = @unifier.apply(receiver_type)

        # Get argument types
        arg_types = []
        if node.arguments
          arg_types = node.arguments.arguments.map { |arg| infer(arg) }
        end

        method_name = node.name.to_sym

        # Try to find function in our environment (for self-calls / top-level functions only)
        # Do NOT use bare lookup for receiver calls — it would match wrong class methods
        unless node.receiver
          # For self-calls in a class, prefer class-qualified lookup first
          # Walk up class hierarchy to find inherited methods
          scheme = nil
          if @current_class_name
            cls = @current_class_name
            while cls
              func_type = @function_types[:"#{cls}##{method_name}"]
              if func_type.is_a?(FunctionType)
                # Monomorphic binding — self-calls share TypeVars with the method definition
                scheme = TypeScheme.new([], func_type)
                break
              end
              cls = @class_parents[cls]
            end
          end
          scheme ||= lookup(method_name)
          unless scheme
            # Fallback: look up in @function_types (unqualified)
            func_type = @function_types[method_name]
            if func_type.is_a?(FunctionType)
              scheme = TypeScheme.new([], func_type)
            end
          end
          if scheme
            func_type = scheme.instantiate
            if func_type.is_a?(FunctionType)
              unify_call_args(func_type, arg_types)
              # For generalized schemes with deferred constraints, propagate
              # call-site arg types to resolve body's deferred method calls.
              # Returns the resolved return type directly (without modifying original TypeVars).
              resolved_ret = nil
              if !scheme.type_vars.empty? && !@deferred_constraints.empty?
                resolved_ret = propagate_call_site_types(scheme, arg_types)
              end
              # Unify keyword args from call site
              unify_keyword_args(node, method_name)
              if @current_class_name
                unify_keyword_args(node, :"#{@current_class_name}##{method_name}")
              end
              infer_block_body_without_rbs(node.block) if node.block
              return resolved_ret || @unifier.apply(func_type.return_type)
            end
          end
        end

        # Receiver-based call on user class: look up class-qualified method type
        # Walk up class hierarchy to find inherited methods
        if node.receiver && receiver_type.is_a?(Types::ClassInstance)
          class_name = receiver_type.name.to_s
          cls = class_name
          func_type = nil
          polymorphic_scheme = nil
          while cls
            qualified_key = :"#{cls}##{method_name}"
            # Check if this method has polymorphic binding (instance methods)
            polymorphic_scheme = @polymorphic_methods[qualified_key]
            func_type = @function_types[qualified_key]
            break if func_type.is_a?(FunctionType)
            cls = @class_parents[cls]
          end
          if func_type.is_a?(FunctionType)
            if polymorphic_scheme
              # Polymorphic instance methods: try unification but allow type mismatches.
              # If a type mismatch occurs (e.g., []= called with String then Integer),
              # fall through to dynamic dispatch (UNTYPED return).
              begin
                unify_call_args(func_type, arg_types)
                unify_keyword_args(node, :"#{class_name}##{method_name}")
                infer_block_body_without_rbs(node.block) if node.block
                return @unifier.apply(func_type.return_type)
              rescue UnificationError
                # Type mismatch on polymorphic instance method — fall through to
                # dynamic dispatch. This handles cases like c["name"] = "Alice"
                # followed by c["age"] = 30 where val type differs across calls.
                infer_block_body_without_rbs(node.block) if node.block
                return Types::UNTYPED
              end
            else
              # Monomorphic binding: call-site types flow into method body
              unify_call_args(func_type, arg_types)
              unify_keyword_args(node, :"#{class_name}##{method_name}")
              infer_block_body_without_rbs(node.block) if node.block
              return @unifier.apply(func_type.return_type)
            end
          end
        end

        # NOTE: Structural type resolution heuristic (resolve_typevar_receiver) was removed.
        # TypeVar receivers now fall through to the deferred constraint path below,
        # which resolves them after call-sites provide concrete types (Kotlin-style).

        # Built-in operators (check BEFORE RBS lookup to ensure correct types)
        # This ensures comparison operators return bool, not Numeric from RBS
        result = infer_builtin_method(receiver_type, method_name, arg_types)
        return result if result

        # Try RBS lookup for receiver's methods
        if @rbs_loader&.loaded? && receiver_type.is_a?(Types::ClassInstance)
          rbs_result = infer_from_rbs(receiver_type, method_name, arg_types, node)
          return rbs_result if rbs_result
        end

        # JVM interop: look up method signatures from @jvm_classes (classpath introspection)
        # Must be checked BEFORE infer_singleton_method to avoid matching inherited Kernel#open etc.
        if @rbs_loader && receiver_type.is_a?(Types::ClassSingleton)
          jvm_result = infer_jvm_class_method(receiver_type.name, method_name, arg_types)
          return jvm_result if jvm_result
        end

        # JVM interop: instance method lookup on Java class instances
        if @rbs_loader && receiver_type.is_a?(Types::ClassInstance)
          jvm_result = infer_jvm_instance_method(receiver_type.name, method_name, arg_types)
          return jvm_result if jvm_result
        end

        # Try RBS lookup for singleton methods (class methods like NativeHash.new)
        # Only for generic types, not for built-in types like NativeArray
        if @rbs_loader&.loaded? && receiver_type.is_a?(Types::ClassSingleton)
          # Skip for known native types that are handled specially by HIR builder
          unless %i[NativeArray NativeClass].include?(receiver_type.name)
            rbs_result = infer_singleton_method(receiver_type.name, method_name, arg_types, node)
            return rbs_result if rbs_result
          end
        end

        # Standard library singleton method type inference
        if receiver_type.is_a?(Types::ClassSingleton)
          stdlib_result = infer_stdlib_singleton_method(receiver_type.name, method_name, arg_types)
          return stdlib_result if stdlib_result
        end

        # User-defined class .new → returns ClassInstance of that class
        # Unify argument types with initialize parameter types (like Kotlin constructor calls)
        if receiver_type.is_a?(Types::ClassSingleton) && method_name == :new
          init_type = @class_init_types[receiver_type.name.to_s]
          if init_type
            unify_call_args(init_type, arg_types)
          end
          return Types::ClassInstance.new(receiver_type.name)
        end

        # User-defined class methods (def self.xxx) — look up in @function_types
        if receiver_type.is_a?(Types::ClassSingleton)
          class_name = receiver_type.name.to_s
          func_key = :"#{class_name}##{method_name}"
          func_type = @function_types[func_key]
          if func_type.is_a?(FunctionType)
            unify_call_args(func_type, arg_types)
            return func_type.return_type
          end
        end

        # User-defined instance method calls — look up in @function_types
        if receiver_type.is_a?(Types::ClassInstance)
          class_name = receiver_type.name.to_s
          func_key = :"#{class_name}##{method_name}"
          func_type = @function_types[func_key]
          # Also check parent classes
          unless func_type
            parent = @class_parents[class_name]
            while parent && !func_type
              func_type = @function_types[:"#{parent}##{method_name}"]
              parent = @class_parents[parent]
            end
          end
          if func_type.is_a?(FunctionType)
            unify_call_args(func_type, arg_types)
            return func_type.return_type
          end
        end

        # Built-in methods that don't need a specific receiver type
        return Types::BOOL if method_name == :block_given? && !node.receiver

        # UNTYPED receiver: any method call is allowed (RBS escape hatch).
        # This handles duck-typed params like painter, event objects in UI frameworks.
        if receiver_type == Types::UNTYPED
          return Types::UNTYPED
        end

        # Deferred constraint: if receiver is an unresolved TypeVar, defer resolution
        # until after all call-sites have unified their types (Kotlin-style deferred resolution)
        resolved_receiver = @unifier.apply(receiver_type)
        # UNTYPED after resolution (TypeVar unified with UNTYPED)
        return Types::UNTYPED if resolved_receiver == Types::UNTYPED
        if resolved_receiver.is_a?(TypeVar)
          result_var = TypeVar.new
          @deferred_constraints << {
            receiver: resolved_receiver,
            method_name: method_name,
            arg_types: arg_types,
            result_var: result_var,
            node: node
          }
          return result_var
        end

        # Unknown method on concrete type — immediate error
        @inference_errors ||= []
        recv_desc = resolved_receiver.to_s
        @inference_errors << "Cannot resolve method '#{method_name}' on #{recv_desc}"
        TypeVar.new
      end

      # Attempt to resolve a method call on a now-concrete receiver type.
      # Used by deferred constraint resolution after TypeVars are unified.
      # Returns the resolved return type, or nil if unresolvable.
      def try_resolve_method(receiver_type, method_name, arg_types, node = nil)
        # UNTYPED receiver: any method call is allowed
        return Types::UNTYPED if receiver_type == Types::UNTYPED

        # Built-in operators
        result = infer_builtin_method(receiver_type, method_name, arg_types)
        return result if result

        # RBS lookup
        if @rbs_loader&.loaded? && receiver_type.is_a?(Types::ClassInstance)
          rbs_result = infer_from_rbs(receiver_type, method_name, arg_types, node)
          return rbs_result if rbs_result
        end

        # JVM interop
        if @rbs_loader && receiver_type.is_a?(Types::ClassInstance)
          jvm_result = infer_jvm_instance_method(receiver_type.name, method_name, arg_types)
          return jvm_result if jvm_result
        end

        # User-defined instance methods
        if receiver_type.is_a?(Types::ClassInstance)
          class_name = receiver_type.name.to_s
          cls = class_name
          func_type = nil
          while cls
            func_type = @function_types[:"#{cls}##{method_name}"]
            break if func_type.is_a?(FunctionType)
            cls = @class_parents[cls]
          end
          if func_type.is_a?(FunctionType)
            unify_call_args(func_type, arg_types)
            return @unifier.apply(func_type.return_type)
          end
        end

        nil
      end

      # Propagate call-site argument types into a generalized function's deferred constraints.
      # Uses a LOCAL solutions map (no modification of original TypeVars) to preserve polymorphism.
      # Returns the resolved return type, or nil if unresolvable.
      def propagate_call_site_types(scheme, arg_types)
        original_type = scheme.type
        return nil unless original_type.is_a?(FunctionType)

        # Build solutions: original param TypeVar ID → concrete type from call site
        solutions = {}
        original_type.param_types.zip(arg_types).each do |orig_param, arg_t|
          orig = orig_param
          orig = orig.prune if orig.is_a?(TypeVar)
          if orig.is_a?(TypeVar) && arg_t && !arg_t.is_a?(TypeVar)
            solutions[orig.id] = arg_t
          end
        end
        # Collect excess args for rest_param_type
        if original_type.rest_param_type
          rest_tv = original_type.rest_param_type
          rest_tv = rest_tv.prune if rest_tv.is_a?(TypeVar)
          if rest_tv.is_a?(TypeVar)
            excess = arg_types[original_type.param_types.size..]
            if excess && !excess.empty?
              concrete = excess.find { |t| !t.is_a?(TypeVar) }
              solutions[rest_tv.id] = concrete if concrete
            end
          end
        end
        return nil if solutions.empty?

        # Iteratively resolve deferred constraints using local solutions map
        5.times do
          changed = false
          @deferred_constraints.each do |constraint|
            receiver = resolve_with_solutions(constraint[:receiver], solutions)
            next if receiver.is_a?(TypeVar)

            # Skip if already resolved in this pass
            result_var = constraint[:result_var]
            pruned_result = result_var.is_a?(TypeVar) ? result_var.prune : result_var
            result_id = pruned_result.is_a?(TypeVar) ? pruned_result.id : nil
            next if result_id && solutions[result_id]

            resolved_args = constraint[:arg_types].map { |t| resolve_with_solutions(t, solutions) }
            result_type = try_resolve_method(receiver, constraint[:method_name], resolved_args, constraint[:node])
            if result_type
              solutions[result_id] = result_type if result_id
              changed = true
            end
          end
          break unless changed
        end

        # Return the resolved return type (without modifying original TypeVars)
        orig_ret = original_type.return_type
        orig_ret = orig_ret.prune if orig_ret.is_a?(TypeVar)
        resolved_ret = resolve_with_solutions(orig_ret, solutions)
        resolved_ret.is_a?(TypeVar) ? nil : resolved_ret
      end

      # Resolve a type using a local solutions map, falling back to unifier.
      def resolve_with_solutions(type, solutions)
        if type.is_a?(TypeVar)
          pruned = type.prune
          return pruned unless pruned.is_a?(TypeVar)
          return solutions[pruned.id] || pruned
        end
        type
      end

      # Resolve deferred constraints iteratively until fixed-point.
      # After all call-sites have unified TypeVars, deferred method calls
      # on now-concrete receivers can be resolved (Kotlin-style deferred resolution).
      def resolve_deferred_constraints
        max_iterations = 10  # Safety limit to prevent infinite loops
        iteration = 0

        while iteration < max_iterations
          changed = false
          iteration += 1

          @deferred_constraints.reject! do |constraint|
            receiver = @unifier.apply(constraint[:receiver])
            next false if receiver.is_a?(TypeVar)  # Still unresolved

            # Receiver is now concrete — try to resolve the method
            resolved_args = constraint[:arg_types].map { |t| @unifier.apply(t) }
            result_type = try_resolve_method(
              receiver,
              constraint[:method_name],
              resolved_args,
              constraint[:node]
            )

            if result_type
              # Successfully resolved — unify with the placeholder result TypeVar
              begin
                @unifier.unify(constraint[:result_var], result_type)
              rescue UnificationError
                # Type mismatch — record as error
                @inference_errors << "Type mismatch resolving deferred '#{constraint[:method_name]}' on #{receiver}"
              end
              changed = true
              true  # Remove from deferred list
            else
              # Method not found even on concrete type — record error and remove
              @inference_errors << "Cannot resolve method '#{constraint[:method_name]}' on #{receiver}"
              changed = true
              true  # Remove
            end
          end

          break unless changed
        end

        # Any remaining deferred constraints (receiver still TypeVar) → errors
        @deferred_constraints.each do |constraint|
          receiver = @unifier.apply(constraint[:receiver])
          @inference_errors << "Cannot resolve method '#{constraint[:method_name]}' on #{receiver}"
        end
        @deferred_constraints.clear

        # Path-compress all function types: ensure TypeVars resolved through
        # deferred constraints are visible via the unification chain.
        @function_types.each do |_key, func_type|
          next unless func_type.is_a?(FunctionType)
          func_type.param_types.each { |pt| @unifier.apply(pt) }
          @unifier.apply(func_type.rest_param_type) if func_type.rest_param_type
          @unifier.apply(func_type.return_type)
        end
      end

      # Look up method type from JVM class registry (for classpath-introspected methods)
      def infer_jvm_class_method(class_name, method_name, arg_types)
        return nil unless @rbs_loader.respond_to?(:jvm_classes)

        jvm_info = @rbs_loader.jvm_classes[class_name.to_s]
        return nil unless jvm_info

        # .new → returns ClassInstance of this class
        if method_name == :new && jvm_info[:constructor_params]
          ctor_params = jvm_info[:constructor_params].map { |t| jvm_tag_to_hm_type(t) }
          ctor_params.zip(arg_types).each do |param_t, arg_t|
            @unifier.unify(param_t, arg_t) if arg_t && param_t
          end
          return Types::ClassInstance.new(class_name)
        end

        method_info = jvm_info[:static_methods]&.dig(method_name.to_s)
        return nil unless method_info

        param_types = (method_info[:params] || []).map { |t| jvm_tag_to_hm_type(t) }
        return_type = jvm_tag_to_hm_type(method_info[:return] || :void)

        # Unify argument types with parameter types
        param_types.zip(arg_types).each do |param_t, arg_t|
          @unifier.unify(param_t, arg_t) if arg_t && param_t
        end

        return_type
      end

      # Look up instance method type from JVM class registry
      def infer_jvm_instance_method(class_name, method_name, arg_types)
        return nil unless @rbs_loader.respond_to?(:jvm_classes)

        jvm_info = @rbs_loader.jvm_classes[class_name.to_s]
        return nil unless jvm_info

        method_info = jvm_info[:methods]&.dig(method_name.to_s)
        return nil unless method_info

        param_types = (method_info[:params] || []).map { |t| jvm_tag_to_hm_type(t) }
        return_type = jvm_tag_to_hm_type(method_info[:return] || :void)

        param_types.zip(arg_types).each do |param_t, arg_t|
          @unifier.unify(param_t, arg_t) if arg_t && param_t
        end

        return_type
      end

      # Convert JVM type tag to HM type
      def jvm_tag_to_hm_type(tag)
        case tag
        when :i64 then Types::INTEGER
        when :double then Types::FLOAT
        when :string then Types::STRING
        when :i8 then Types::BOOL
        when :void then Types::UNTYPED
        when :value then Types::UNTYPED
        else Types::UNTYPED
        end
      end

      # Infer types for standard library class methods
      def infer_stdlib_singleton_method(class_name, method_name, arg_types)
        case class_name
        when :File
          case method_name
          when :read, :readlines then Types::STRING
          when :write then Types::INTEGER
          when :exist?, :exists?, :file?, :directory?, :symlink?, :readable?, :writable?
            Types::BOOL
          when :delete, :unlink then Types::INTEGER
          when :open then Types::UNTYPED
          when :basename, :dirname, :extname, :expand_path, :join, :absolute_path
            Types::STRING
          when :size then Types::INTEGER
          when :mtime, :atime, :ctime then Types::TIME
          end
        when :Dir
          case method_name
          when :glob then Types.array(Types::STRING)
          when :mkdir then Types::INTEGER
          when :exist?, :exists? then Types::BOOL
          when :pwd, :getwd, :home then Types::STRING
          when :entries, :children then Types.array(Types::STRING)
          end
        when :Time
          case method_name
          when :now, :new, :at, :mktime, :local, :utc, :gm then Types::TIME
          end
        when :ENV
          case method_name
          when :[], :fetch then Types::STRING
          when :keys, :values then Types.array(Types::STRING)
          when :has_key?, :key?, :include? then Types::BOOL
          end
        end
      end

      # Look up singleton method (class method) type from RBS
      def infer_singleton_method(class_name, method_name, arg_types, node)
        # Get singleton method types from RBS
        method_types = @rbs_loader.method_type(class_name, method_name, singleton: true)
        return nil unless method_types && !method_types.empty?

        # Select best overload based on argument types
        method_type = select_overload(method_types, arg_types)

        # Get class type parameters from RBS for substitution
        substitution = build_singleton_method_substitution(class_name, method_type)

        # Guard against UntypedFunction (which lacks required_positionals)
        return Types::UNTYPED if method_type.type.is_a?(RBS::Types::UntypedFunction)

        # Unify argument types with parameter types from RBS
        rbs_params = method_type.type.required_positionals + method_type.type.optional_positionals
        arg_types.each_with_index do |arg_type, i|
          next unless rbs_params[i]
          expected_type = substitute_rbs_type(rbs_params[i].type, substitution)
          @unifier.unify(arg_type, expected_type)
        end

        # Convert and return the return type
        return_type = substitute_rbs_type(method_type.type.return_type, substitution)

        # Handle block if present
        if node.block && method_type.block
          infer_block_for_rbs(node.block, method_type.block, substitution)
        end

        @unifier.apply(return_type)
      end

      # Build substitution map for singleton method type parameters
      def build_singleton_method_substitution(class_name, method_type)
        substitution = {}

        # Get class type parameters from RBS
        type_name = RBS::TypeName.new(name: class_name, namespace: RBS::Namespace.root)
        class_decl = @rbs_loader.environment.class_decls[type_name]

        if class_decl
          params = class_decl.decls.first.decl.type_params
          params.each do |param|
            # For singleton methods, type params are not bound to instances
            # They stay as type variables unless specified in return type
            substitution[param.name] = TypeVar.new(param.name.to_s)
          end
        end

        # Handle method-level type parameters
        if method_type.type_params && !method_type.type_params.empty?
          method_type.type_params.each do |param|
            substitution[param.name] = TypeVar.new(param.name.to_s)
          end
        end

        substitution
      end

      # Look up method type from RBS and instantiate type parameters
      def infer_from_rbs(receiver_type, method_name, arg_types, node)
        class_name = receiver_type.name
        type_args = receiver_type.type_args

        # Get method types from RBS
        method_types = @rbs_loader.method_type(class_name, method_name)
        return nil unless method_types && !method_types.empty?

        # Select best overload based on argument types
        method_type = select_overload(method_types, arg_types)

        # Build substitution map from type parameters to actual type arguments
        substitution = build_type_substitution(class_name, type_args)
        substitution[:__self__] = receiver_type

        # Handle method-level type parameters (like `map: [U] { (T) -> U } -> Array[U]`)
        if method_type.type_params && !method_type.type_params.empty?
          method_type.type_params.each do |param|
            # Create fresh type variable for each method type parameter
            substitution[param.name] = TypeVar.new(param.name.to_s)
          end
        end

        # Guard against UntypedFunction (which lacks required_positionals)
        return Types::UNTYPED if method_type.type.is_a?(RBS::Types::UntypedFunction)

        # Unify argument types with parameter types from RBS
        # This allows us to infer argument types from method signatures
        rbs_params = method_type.type.required_positionals + method_type.type.optional_positionals
        arg_types.each_with_index do |arg_type, i|
          next unless rbs_params[i]
          expected_type = substitute_rbs_type(rbs_params[i].type, substitution)
          @unifier.unify(arg_type, expected_type)
        end

        # Substitute and convert return type
        return_type = substitute_rbs_type(method_type.type.return_type, substitution)

        # Handle block if present (for methods like map)
        if node.block && method_type.block
          infer_block_for_rbs(node.block, method_type.block, substitution)
        end

        @unifier.apply(return_type)
      end

      # Build substitution map from class type parameters to actual types
      def build_type_substitution(class_name, type_args)
        substitution = {}

        # Get class type parameters from RBS
        type_name = RBS::TypeName.new(name: class_name, namespace: RBS::Namespace.root)
        class_decl = @rbs_loader.environment.class_decls[type_name]

        if class_decl
          params = class_decl.decls.first.decl.type_params
          params.each_with_index do |param, i|
            if type_args[i]
              substitution[param.name] = type_args[i]
            else
              substitution[param.name] = TypeVar.new(param.name.to_s)
            end
          end
        end

        substitution
      end

      # Convert RBS type to our internal type, applying substitution
      def substitute_rbs_type(rbs_type, substitution)
        case rbs_type
        when RBS::Types::Variable
          # Type variable - look up in substitution
          substitution[rbs_type.name] || TypeVar.new(rbs_type.name.to_s)

        when RBS::Types::Alias
          # Type alias - resolve common ones
          case rbs_type.name.name
          when :string then Types::STRING
          when :int then Types::INTEGER
          when :float then Types::FLOAT
          when :bool, :boolish then Types::BOOL
          when :array then Types.array(Types::UNTYPED)
          when :hash then Types.hash_type(Types::UNTYPED, Types::UNTYPED)
          else Types::UNTYPED
          end

        when RBS::Types::ClassInstance
          name = rbs_type.name.name
          # Check if this is a type parameter reference (looks like ClassInstance but is actually a type variable)
          # This happens when RBS parses K, V in NativeHash[K, V] as ClassInstance instead of Variable
          if substitution.key?(name)
            substitution[name]
          else
            # Use fully qualified name for nested classes (e.g., Ractor::Port instead of Port)
            qualified_name = rbs_qualified_name(rbs_type.name)
            # Recursively substitute type arguments
            args = rbs_type.args.map { |a| substitute_rbs_type(a, substitution) }
            Types::ClassInstance.new(qualified_name, args)
          end

        when RBS::Types::Bases::Nil, RBS::Types::Bases::Void
          Types::NIL

        when RBS::Types::Bases::Bool
          Types::BOOL

        when RBS::Types::Bases::Any, RBS::Types::Bases::Top
          Types::UNTYPED

        when RBS::Types::Bases::Bottom
          Types::BOTTOM

        when RBS::Types::Bases::Self
          # Resolve to receiver type when available
          substitution[:__self__] || Types::UNTYPED

        when RBS::Types::Optional
          # T? becomes Union[T, nil]
          inner = substitute_rbs_type(rbs_type.type, substitution)
          Types.optional(inner)

        when RBS::Types::Union
          types = rbs_type.types.map { |t| substitute_rbs_type(t, substitution) }
          Types.union(*types)

        when RBS::Types::Tuple
          types = rbs_type.types.map { |t| substitute_rbs_type(t, substitution) }
          Types::Tuple.new(types)

        when RBS::Types::Literal
          # For integer literals, preserve the value (important for StaticArray[T, N] where N is a literal)
          # For other literals, convert to the base type
          case rbs_type.literal
          when Integer
            Types::Literal.new(rbs_type.literal)
          when Float then Types::FLOAT
          when String then Types::STRING
          when Symbol then Types::SYMBOL
          when true then Types::TRUE_CLASS
          when false then Types::FALSE_CLASS
          else Types::UNTYPED
          end

        else
          Types::UNTYPED
        end
      end

      # Convert RBS::TypeName to a qualified symbol (e.g., :"Ractor::Port" for nested classes)
      def rbs_qualified_name(type_name)
        ns = type_name.namespace
        if ns.path.empty?
          type_name.name
        else
          :"#{ns.path.map(&:to_s).join("::")}::#{type_name.name}"
        end
      end

      # Select the best overload based on argument types
      def select_overload(method_types, arg_types)
        return method_types.first if method_types.size == 1

        # Score each overload by how well it matches argument types
        scored = method_types.map do |mt|
          score = 0
          next [mt, 0] if mt.type.is_a?(RBS::Types::UntypedFunction)

          rbs_params = mt.type.required_positionals + mt.type.optional_positionals

          arg_types.each_with_index do |arg_type, i|
            next unless rbs_params[i]
            rbs_param_type = rbs_params[i].type
            arg_type = @unifier.apply(arg_type)

            # Check if argument type matches parameter type
            score += overload_match_score(arg_type, rbs_param_type)
          end

          [mt, score]
        end

        # Return the overload with highest score
        scored.max_by { |_, score| score }&.first || method_types.first
      end

      # Score how well an argument type matches an RBS parameter type
      def overload_match_score(arg_type, rbs_param_type)
        case rbs_param_type
        when RBS::Types::Alias
          # Resolve common aliases: ::int -> Integer, ::string -> String, etc.
          resolved = resolve_rbs_alias(rbs_param_type)
          return overload_match_score(arg_type, resolved) if resolved
        when RBS::Types::ClassInstance
          param_name = rbs_param_type.name.name
          if arg_type.is_a?(Types::ClassInstance)
            # Exact match
            return 10 if arg_type.name == param_name
            # Check for common numeric hierarchy
            return 5 if numeric_compatible?(arg_type.name, param_name)
          end
        when RBS::Types::Bases::Any
          return 1  # Any matches anything but with low priority
        end

        0
      end

      # Resolve RBS type aliases to their underlying ClassInstance types
      def resolve_rbs_alias(alias_type)
        alias_name = alias_type.name.name
        class_name = case alias_name
                     when :int then :Integer
                     when :string then :String
                     when :float then :Float
                     when :bool then :Bool
                     when :boolish then :Bool
                     end
        return nil unless class_name
        RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: class_name, namespace: RBS::Namespace.root),
          args: [],
          location: alias_type.location
        )
      end

      def numeric_compatible?(arg_name, param_name)
        numerics = %i[Integer Float Rational Complex Numeric]
        numerics.include?(arg_name) && numerics.include?(param_name)
      end

      # Infer block type for methods like map
      def infer_block_for_rbs(block_node, rbs_block, substitution)
        # The block's return type should unify with the RBS block's return type
        # For example: map's block { (Elem) -> U } means block returns U

        # BlockArgumentNode (&blk) has no parameters or body — skip block inference entirely
        return Types::UNTYPED if block_node.is_a?(Prism::BlockArgumentNode)

        push_env

        # Bind block parameters (skip if UntypedFunction)
        # BlockArgumentNode (&blk) does not have a parameters method - skip it
        if !block_node.is_a?(Prism::BlockArgumentNode) && block_node.respond_to?(:parameters) && block_node.parameters && rbs_block.type.respond_to?(:required_positionals)
          if block_node.parameters.is_a?(Prism::NumberedParametersNode)
            # Numbered block parameters (_1, _2, ...)
            rbs_positionals = rbs_block.type.required_positionals
            block_node.parameters.maximum.times do |i|
              if rbs_positionals[i]
                param_type = substitute_rbs_type(rbs_positionals[i].type, substitution)
                bind(:"_#{i + 1}", param_type)
              end
            end
          elsif block_node.parameters.is_a?(Prism::ItParametersNode)
            # it block parameter (Ruby 3.4+)
            rbs_positionals = rbs_block.type.required_positionals
            if rbs_positionals[0]
              param_type = substitute_rbs_type(rbs_positionals[0].type, substitution)
              bind(:_it_param, param_type)
            end
          else
            block_node.parameters.parameters&.requireds&.zip(
              rbs_block.type.required_positionals
            )&.each do |param, rbs_param|
              if param.respond_to?(:name) && rbs_param
                param_type = substitute_rbs_type(rbs_param.type, substitution)
                bind(param.name, param_type)
              end
            end
          end
        end

        # Infer block body
        body_type = block_node.body ? infer(block_node.body) : Types::NIL

        # Unify with expected return type (skip if UntypedFunction or void)
        if rbs_block.type.respond_to?(:return_type)
          rbs_ret = rbs_block.type.return_type
          # RBS void means "return value is irrelevant" — don't constrain block return type
          unless rbs_ret.is_a?(RBS::Types::Bases::Void)
            expected_return = substitute_rbs_type(rbs_ret, substitution)
            @unifier.unify(expected_return, body_type)
          end
        end

        pop_env
      end

      # Infer block body without RBS block type info.
      # Block parameters become fresh TypeVars; captured variables retain outer scope types.
      def infer_block_body_without_rbs(block_node)
        push_env
        if block_node.parameters
          if block_node.parameters.is_a?(Prism::NumberedParametersNode)
            block_node.parameters.maximum.times do |i|
              bind(:"_#{i + 1}", TypeVar.new)
            end
          elsif block_node.parameters.is_a?(Prism::ItParametersNode)
            bind(:it, TypeVar.new)
          elsif block_node.parameters.respond_to?(:parameters) && block_node.parameters.parameters
            block_node.parameters.parameters.requireds&.each do |param|
              if param.respond_to?(:name) && param.name
                bind(param.name.to_sym, TypeVar.new)
              end
            end
          end
        end
        infer(block_node.body) if block_node.body
        pop_env
      end

      def infer_builtin_method(receiver_type, method_name, arg_types)
        receiver_type = @unifier.apply(receiver_type)
        arg_type = arg_types.first ? @unifier.apply(arg_types.first) : nil

        case method_name
        when :call
          # .call on any receiver (block/proc/lambda stored in ivar) returns UNTYPED
          # This handles patterns like @click_handler.call, @callback.call(args)
          return Types::UNTYPED
        when :+, :-, :*, :/, :%
          # If receiver is a type variable and arg is concrete, unify
          if receiver_type.is_a?(TypeVar) && arg_type
            if arg_type == Types::INTEGER || arg_type == Types::FLOAT
              @unifier.unify(receiver_type, arg_type)
              return arg_type
            elsif arg_type == Types::STRING && method_name == :+
              @unifier.unify(receiver_type, Types::STRING)
              return Types::STRING
            end
          end

          if receiver_type == Types::INTEGER
            if arg_type == Types::FLOAT
              return Types::FLOAT
            end
            # Unify arg with Integer if it's a type variable
            if arg_type.is_a?(TypeVar)
              @unifier.unify(arg_type, Types::INTEGER)
            end
            return Types::INTEGER
          elsif receiver_type == Types::FLOAT
            # Unify arg with Float if it's a type variable
            if arg_type.is_a?(TypeVar)
              @unifier.unify(arg_type, Types::FLOAT)
            end
            return Types::FLOAT
          elsif receiver_type == Types::STRING && method_name == :+
            # String#+ requires String argument
            if arg_type.is_a?(TypeVar)
              @unifier.unify(arg_type, Types::STRING)
            end
            return Types::STRING
          end
        when :==, :!=, :<, :>, :<=, :>=
          # If receiver is a type variable and arg is concrete, unify
          if receiver_type.is_a?(TypeVar) && arg_type
            if arg_type == Types::INTEGER
              @unifier.unify(receiver_type, Types::INTEGER)
            elsif arg_type == Types::FLOAT
              @unifier.unify(receiver_type, Types::FLOAT)
            elsif arg_type == Types::STRING
              @unifier.unify(receiver_type, Types::STRING)
            end
          end
          # If arg is a type variable and receiver is concrete, unify
          if arg_type && arg_type.is_a?(TypeVar)
            if receiver_type == Types::INTEGER
              @unifier.unify(arg_type, Types::INTEGER)
            elsif receiver_type == Types::FLOAT
              @unifier.unify(arg_type, Types::FLOAT)
            elsif receiver_type == Types::STRING
              @unifier.unify(arg_type, Types::STRING)
            end
          end
          return Types::BOOL
        when :!
          return Types::BOOL
        when :to_s, :inspect
          return Types::STRING
        when :to_i
          return Types::INTEGER
        when :to_f
          return Types::FLOAT
        when :size, :length, :count
          return Types::INTEGER
        # String methods
        when :split, :chars
          return Types.array(Types::STRING) if receiver_type == Types::STRING
        when :bytes
          return Types.array(Types::INTEGER) if receiver_type == Types::STRING
        when :strip, :lstrip, :rstrip, :upcase, :downcase, :capitalize,
             :gsub, :sub, :chomp, :chop, :squeeze, :reverse, :tr, :delete,
             :encode, :freeze, :dup, :clone
          return Types::STRING if receiver_type == Types::STRING
        when :include?, :start_with?, :end_with?, :match?, :empty?,
             :ascii_only?, :frozen?, :nil?, :is_a?, :kind_of?,
             :even?, :odd?, :zero?, :positive?, :negative?
          return Types::BOOL
        when :abs
          return Types::INTEGER if receiver_type == Types::INTEGER
          return Types::FLOAT if receiver_type == Types::FLOAT
        when :index, :rindex, :ord
          return Types::INTEGER if receiver_type == Types::STRING
        when :scan
          return Types.array(Types::STRING) if receiver_type == Types::STRING
        when :match
          return Types::MATCH_DATA if receiver_type == Types::STRING || receiver_type == Types::REGEXP
        when :[], :slice
          return Types::STRING if receiver_type == Types::STRING
          # Array element access returns the element type
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
            return receiver_type.type_args&.first || Types::UNTYPED
          end
        # Array methods
        when :first, :last, :sample
          # first(n) / last(n) / sample(n) with argument return Array, without return element
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
            if arg_types.size > 0
              # With argument: returns Array (e.g., [1,2,3].first(2) => [1,2])
              return receiver_type
            else
              # Without argument: returns element type
              return receiver_type.type_args&.first || Types::UNTYPED
            end
          end
        when :min, :max, :pop, :shift
          # Return element type if known, otherwise untyped
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
            return receiver_type.type_args&.first || Types::UNTYPED
          end
        when :flatten, :compact, :uniq, :sort, :reverse, :rotate, :shuffle
          return receiver_type if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
        when :push, :<<, :append, :unshift, :prepend
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
            # Unify the array's element TypeVar with the pushed value's type
            elem_type = receiver_type.type_args&.first
            if elem_type && arg_type
              @unifier.unify(elem_type, arg_type)
            end
            return receiver_type
          end
        when :join
          return Types::STRING if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
        when :sum
          return Types::INTEGER if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Array
        # Hash methods
        when :keys
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Hash
            key_type = receiver_type.type_args&.first || Types::UNTYPED
            return Types.array(key_type)
          end
        when :values
          if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Hash
            val_type = receiver_type.type_args&.[](1) || Types::UNTYPED
            return Types.array(val_type)
          end
        when :has_key?, :key?, :has_value?, :value?
          return Types::BOOL if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Hash
        when :merge
          return receiver_type if receiver_type.is_a?(Types::ClassInstance) && receiver_type.name == :Hash
        # MatchData methods
        when :captures
          return Types.array(Types::STRING) if receiver_type == Types::MATCH_DATA
        when :pre_match, :post_match
          return Types::STRING if receiver_type == Types::MATCH_DATA
        end

        nil
      end

      # Method definition
      def infer_def(node)
        push_env
        old_method_name = @current_method_name
        @current_method_name = node.name.to_s

        # Bind parameters with their type variables
        # Use class-qualified key first to avoid cross-class collision
        func_type = nil
        if @current_class_name
          func_type = @function_types[:"#{@current_class_name}##{node.name}"]
        end
        func_type ||= @function_types[node.name.to_sym]

        if func_type && node.parameters
          requireds = node.parameters.requireds || []
          requireds.zip(func_type.param_types).each do |param, param_type|
            if param.respond_to?(:name)
              # Record the parameter type for HIR generation
              record_node_type(param, param_type)
              bind(param.name, param_type)
            end
          end
        end

        # Rest parameter (*args) is Array — use FunctionType's rest_param_type if available
        # so call-site arg types flow through to the rest param element type
        if node.parameters&.rest.is_a?(Prism::RestParameterNode) && node.parameters.rest.name
          rest_element_type = func_type&.rest_param_type || TypeVar.new
          rest_type = Types.array(rest_element_type)
          record_node_type(node.parameters.rest, rest_type)
          bind(node.parameters.rest.name, rest_type)
        end

        # Keyword parameters (required and optional)
        keywords = node.parameters&.keywords || []
        func_key = @current_class_name ? :"#{@current_class_name}##{node.name}" : node.name.to_sym
        kw_vars = @keyword_param_vars[func_key] || {}
        keywords.each do |kw|
          kw_type = kw_vars[kw.name] || TypeVar.new(kw.name.to_s)
          record_node_type(kw, kw_type)
          bind(kw.name, kw_type)

          # For optional keyword params, infer default value type and unify
          if kw.respond_to?(:value) && kw.value
            default_type = infer(kw.value)
            begin
              @unifier.unify(kw_type, default_type)
            rescue UnificationError
              # Default value type conflicts — keep the TypeVar
            end
          end
        end

        # Keyword rest parameter (**kwargs) is always Hash
        if node.parameters&.keyword_rest.is_a?(Prism::KeywordRestParameterNode) && node.parameters.keyword_rest.name
          kwrest_type = Types.hash_type(Types::SYMBOL, TypeVar.new)
          record_node_type(node.parameters.keyword_rest, kwrest_type)
          bind(node.parameters.keyword_rest.name, kwrest_type)
        end

        # Infer body type
        body_type = if node.body
          infer(node.body)
        else
          Types::NIL
        end

        # Unify with return type
        if func_type
          @unifier.unify(func_type.return_type, body_type)
        end

        @current_method_name = old_method_name
        pop_env
        Types::SYMBOL
      end

      # ==============================================
      # Flow-sensitive type narrowing
      # ==============================================

      # Analyze a predicate expression to determine what type narrowing to apply
      # Returns a hash describing the narrowing, or nil if no narrowing applies
      def analyze_predicate(node)
        case node
        when Prism::LocalVariableReadNode
          # Simple truthiness check: `if x`
          { var_name: node.name.to_sym, narrowing: :truthy }
        when Prism::CallNode
          analyze_call_predicate(node)
        when Prism::AndNode
          # `if a && b` - both conditions must be true in then-branch
          left = analyze_predicate(node.left)
          right = analyze_predicate(node.right)
          { type: :and, left: left, right: right }
        when Prism::OrNode
          # `if a || b` - either condition may be true (conservative)
          left = analyze_predicate(node.left)
          right = analyze_predicate(node.right)
          { type: :or, left: left, right: right }
        else
          nil
        end
      end

      # Analyze a method call predicate (e.g., `x == nil`, `x.nil?`)
      def analyze_call_predicate(node)
        # Handle `x == nil`, `x != nil`, `x.nil?`
        if node.receiver.is_a?(Prism::LocalVariableReadNode)
          var_name = node.receiver.name.to_sym

          case node.name.to_sym
          when :==
            # `x == nil` -> then: x is nil, else: x is non-nil
            if nil_literal?(node.arguments&.arguments&.first)
              return { var_name: var_name, narrowing: :nil_check }
            end
          when :!=
            # `x != nil` -> then: x is non-nil, else: x is nil
            if nil_literal?(node.arguments&.arguments&.first)
              return { var_name: var_name, narrowing: :not_nil_check }
            end
          when :nil?
            # `x.nil?` -> then: x is nil, else: x is non-nil
            return { var_name: var_name, narrowing: :nil_check }
          end
        end

        # Handle `nil == x`, `nil != x`
        if nil_literal?(node.receiver) && node.arguments&.arguments&.first.is_a?(Prism::LocalVariableReadNode)
          var_name = node.arguments.arguments.first.name.to_sym
          case node.name.to_sym
          when :==
            return { var_name: var_name, narrowing: :nil_check }
          when :!=
            return { var_name: var_name, narrowing: :not_nil_check }
          end
        end

        nil
      end

      # Check if a node is a nil literal
      def nil_literal?(node)
        node.is_a?(Prism::NilNode)
      end

      # Apply narrowing for the then-branch
      # Returns an array of narrowing records for restoration
      def apply_then_narrowing(pred_info)
        return [] unless pred_info

        case pred_info[:type]
        when :and
          # Both conditions are true: apply both narrowings
          left_narrowings = apply_then_narrowing(pred_info[:left])
          right_narrowings = apply_then_narrowing(pred_info[:right])
          left_narrowings + right_narrowings
        when :or
          # Either condition may be true: conservative, no narrowing
          []
        else
          apply_single_narrowing(pred_info, :then)
        end
      end

      # Apply narrowing for the else-branch
      # Returns an array of narrowing records for restoration
      def apply_else_narrowing(pred_info)
        return [] unless pred_info

        case pred_info[:type]
        when :and
          # At least one condition is false: conservative, no narrowing
          []
        when :or
          # Both conditions are false: apply opposite narrowings
          left_narrowings = apply_else_narrowing(pred_info[:left])
          right_narrowings = apply_else_narrowing(pred_info[:right])
          left_narrowings + right_narrowings
        else
          apply_single_narrowing(pred_info, :else)
        end
      end

      # Apply a single narrowing based on the predicate info and branch
      def apply_single_narrowing(pred_info, branch)
        var_name = pred_info[:var_name]
        return [] unless var_name

        scheme = lookup(var_name)
        return [] unless scheme

        current_type = scheme.is_a?(TypeScheme) ? scheme.type : scheme
        return [] unless narrowable_type?(current_type)

        narrowed_type = case [pred_info[:narrowing], branch]
        when [:truthy, :then], [:not_nil_check, :then], [:nil_check, :else]
          # Variable is non-nil
          remove_nil_from_type(current_type)
        when [:nil_check, :then], [:not_nil_check, :else], [:truthy, :else]
          # For truthy else: variable could be nil or false
          # For nil_check then: variable is definitely nil
          if pred_info[:narrowing] == :nil_check && branch == :then
            Types::NIL
          else
            # Conservative: don't narrow for truthy else (could be nil or false)
            return []
          end
        else
          return []
        end

        return [] if narrowed_type == current_type

        original = scheme
        bind(var_name, narrowed_type)
        [{ var_name: var_name, original: original }]
      end

      # Check if a type can be narrowed (has nil in it)
      def narrowable_type?(type)
        type = type.type if type.is_a?(TypeScheme)
        return true if type.is_a?(Types::Union) && type.types.include?(Types::NIL)
        false
      end

      # Remove nil from a union type
      def remove_nil_from_type(type)
        type = type.type if type.is_a?(TypeScheme)
        return type unless type.is_a?(Types::Union)

        non_nil_types = type.types.reject { |t| t == Types::NIL }
        return type if non_nil_types.size == type.types.size  # No nil to remove

        if non_nil_types.size == 1
          non_nil_types.first
        else
          Types::Union.new(non_nil_types)
        end
      end

      # Restore narrowed variables to their original types
      def restore_narrowings(narrowings)
        return unless narrowings

        narrowings.each do |record|
          if record[:original].is_a?(TypeScheme)
            bind_scheme(record[:var_name], record[:original])
          else
            bind(record[:var_name], record[:original])
          end
        end
      end

      # Control flow
      # @param statement_position [Boolean] if true, the if expression's result is not used,
      #   so we don't require type consistency between branches
      def infer_if(node, statement_position: false)
        # Infer predicate type (for side effects like type errors)
        infer(node.predicate)

        # Analyze predicate for type narrowing
        pred_info = analyze_predicate(node.predicate)

        # Apply narrowing for then-branch
        then_narrowings = apply_then_narrowing(pred_info)

        # In statement position, propagate to child statements
        then_type = if node.statements
          infer_statements_node(node.statements, all_statement_position: statement_position)
        else
          Types::NIL
        end

        # Restore and apply else-branch narrowing
        restore_narrowings(then_narrowings)
        else_narrowings = apply_else_narrowing(pred_info)

        else_type = if node.subsequent
          infer_subsequent(node.subsequent, statement_position: statement_position)
        else
          Types::NIL
        end

        # Restore else narrowings
        restore_narrowings(else_narrowings)

        if statement_position
          # In statement position, the result is not used,
          # so we don't require type consistency between branches.
          # Just return nil as the statement's "result".
          Types::NIL
        else
          # In expression position, both branches must have compatible types
          result_type = TypeVar.new
          @unifier.unify(result_type, then_type)
          @unifier.unify(result_type, else_type)
          @unifier.apply(result_type)
        end
      end

      # unless is the opposite of if: swap then/else narrowing
      # @param statement_position [Boolean] if true, the unless expression's result is not used
      def infer_unless(node, statement_position: false)
        # Infer predicate type (for side effects like type errors)
        infer(node.predicate)

        # Analyze predicate for type narrowing
        pred_info = analyze_predicate(node.predicate)

        # For unless, the body executes when predicate is falsy
        # So apply else-branch narrowing for the body
        body_narrowings = apply_else_narrowing(pred_info)

        # In statement position, propagate to child statements
        body_type = if node.statements
          infer_statements_node(node.statements, all_statement_position: statement_position)
        else
          Types::NIL
        end

        # Restore and apply then-branch narrowing for else (consequent)
        restore_narrowings(body_narrowings)
        else_narrowings = apply_then_narrowing(pred_info)

        else_type = if node.else_clause
          infer_else(node.else_clause, statement_position: statement_position)
        else
          Types::NIL
        end

        # Restore else narrowings
        restore_narrowings(else_narrowings)

        if statement_position
          # In statement position, the result is not used
          Types::NIL
        else
          # Both branches must have compatible types
          result_type = TypeVar.new
          @unifier.unify(result_type, body_type)
          @unifier.unify(result_type, else_type)
          @unifier.apply(result_type)
        end
      end

      # Infer type for else/elsif clause, with statement_position propagation
      def infer_subsequent(node, statement_position: false)
        case node
        when Prism::ElseNode
          infer_else(node, statement_position: statement_position)
        when Prism::IfNode
          # elsif case - recursively process as if
          infer_if(node, statement_position: statement_position)
        else
          infer(node)
        end
      end

      def infer_else(node, statement_position: false)
        if node.statements
          infer_statements_node(node.statements, all_statement_position: statement_position)
        else
          Types::NIL
        end
      end

      def infer_and(node)
        left_type = infer(node.left)
        right_type = infer(node.right)
        # a && b: if a is falsy, result is a; if a is truthy, result is b
        if left_type == right_type
          right_type
        elsif always_falsy_type?(left_type)
          left_type
        elsif always_truthy_type?(left_type)
          right_type
        else
          Types::Union.new([left_type, right_type])
        end
      end

      def infer_or(node)
        left_type = infer(node.left)
        right_type = infer(node.right)
        # a || b: if a is truthy, result is a; if a is falsy, result is b
        if left_type == right_type
          left_type
        elsif always_truthy_type?(left_type)
          left_type
        elsif always_falsy_type?(left_type)
          right_type
        else
          Types::Union.new([left_type, right_type])
        end
      end

      # NilClass and FalseClass are always falsy in Ruby
      def always_falsy_type?(type)
        type.is_a?(Types::NilType) ||
          (type.is_a?(Types::ClassInstance) && type.name == :FalseClass)
      end

      # Everything except nil, false, and bool is always truthy in Ruby
      def always_truthy_type?(type)
        return false if type.is_a?(Types::NilType)
        return false if type.is_a?(Types::BoolType)
        return false if type.is_a?(Types::ClassInstance) && type.name == :FalseClass
        return false if type.is_a?(Types::Union)
        true
      end

      # Compound assignment operators
      def infer_local_variable_operator_write(node)
        existing = lookup(node.name)
        var_type = existing ? existing.instantiate : TypeVar.new
        value_type = infer(node.value)
        # The result type is the return type of the operator call
        # For simplicity, use var_type (e.g., Integer += Integer => Integer)
        var_type
      end

      def infer_local_variable_or_write(node)
        existing = lookup(node.name)
        var_type = existing ? existing.instantiate : TypeVar.new
        value_type = infer(node.value)
        # x ||= val: if x is falsy, x becomes val; if truthy, x stays
        result = if var_type == value_type
          var_type
        elsif always_falsy_type?(var_type)
          value_type
        elsif always_truthy_type?(var_type)
          var_type
        else
          Types::Union.new([var_type, value_type])
        end
        bind(node.name, result)
        result
      end

      def infer_local_variable_and_write(node)
        existing = lookup(node.name)
        var_type = existing ? existing.instantiate : TypeVar.new
        value_type = infer(node.value)
        # x &&= val: if x is truthy, x becomes val; if falsy, x stays
        result = if var_type == value_type
          value_type
        elsif always_truthy_type?(var_type)
          value_type
        elsif always_falsy_type?(var_type)
          var_type
        else
          Types::Union.new([var_type, value_type])
        end
        bind(node.name, result)
        result
      end

      def infer_instance_variable_write(node)
        value_type = infer(node.value)
        if @current_class_name
          @ivar_types[@current_class_name] ||= {}
          existing = @ivar_types[@current_class_name][node.name.to_s]
          if existing && existing != Types::UNTYPED
            if value_type == Types::NIL
              # Keep existing type when assigning nil — nilableを意味する
            elsif existing == Types::NIL || (existing.is_a?(TypeVar) && existing.prune.is_a?(TypeVar))
              # Existing is nil or unresolved TypeVar → replace with concrete type
              if existing.is_a?(TypeVar)
                # Unify TypeVar with concrete type so all references update
                @unifier.unify(existing, value_type)
              else
                @ivar_types[@current_class_name][node.name.to_s] = value_type
              end
            else
              # Existing is concrete type — unify (supports subtype-aware unification)
              begin
                @unifier.unify(existing, value_type)
              rescue UnificationError
                @inference_errors ||= []
                @inference_errors << "Instance variable #{node.name} in #{@current_class_name} has conflicting types: #{existing} vs #{value_type}"
              end
            end
          else
            # First assignment to this ivar
            if value_type == Types::NIL
              # Store TypeVar for nil — will be unified when concrete type is assigned
              @ivar_types[@current_class_name][node.name.to_s] = TypeVar.new
            else
              @ivar_types[@current_class_name][node.name.to_s] = value_type
            end
          end
        end
        value_type
      end

      def infer_instance_variable_read(node)
        if @current_class_name
          # Check current class and parent classes for ivar types
          cls = @current_class_name
          while cls
            if @ivar_types[cls]
              type = @ivar_types[cls][node.name.to_s]
              return type if type && type != Types::UNTYPED
            end
            cls = @class_parents[cls]
          end
        end
        # RBS fallback (check current class and parent classes)
        if @rbs_loader && @current_class_name
          cls = @current_class_name
          while cls
            native_type = @rbs_loader.native_class_type(cls) rescue nil
            if native_type&.respond_to?(:fields)
              field_sym = node.name.to_s.sub(/^@/, "").to_sym
              ftype = native_type.fields[field_sym]
              return rbs_field_to_type(ftype) if ftype
            end
            cls = @class_parents[cls]
          end
        end
        # Return TypeVar so that later write can resolve this
        if @current_class_name
          @ivar_types[@current_class_name] ||= {}
          tv = TypeVar.new
          @ivar_types[@current_class_name][node.name.to_s] ||= tv
          @ivar_types[@current_class_name][node.name.to_s]
        else
          Types::UNTYPED
        end
      end

      def infer_instance_variable_operator_write(node)
        value_type = infer(node.value)
        # Read existing ivar type, the operator result should have the same type
        existing = nil
        if @current_class_name && @ivar_types[@current_class_name]
          existing = @ivar_types[@current_class_name][node.name.to_s]
        end
        existing || value_type
      end

      def infer_instance_variable_or_write(node)
        value_type = infer(node.value)
        if @current_class_name
          @ivar_types[@current_class_name] ||= {}
          existing = @ivar_types[@current_class_name][node.name.to_s]
          if existing && existing != Types::UNTYPED
            existing
          else
            @ivar_types[@current_class_name][node.name.to_s] = value_type
            value_type
          end
        else
          value_type
        end
      end

      def infer_instance_variable_and_write(node)
        value_type = infer(node.value)
        value_type
      end

      def infer_class_variable_write(node)
        value_type = infer(node.value)
        cls = @current_class_name || "__toplevel__"
        @cvar_types[cls] ||= {}
        existing = @cvar_types[cls][node.name.to_s]
        if existing && existing != Types::UNTYPED && existing != Types::NIL
          # Unify with existing type (ignore nil assignments)
          unless value_type == Types::NIL
            begin
              @unifier.unify(existing, value_type)
            rescue UnificationError
              # Keep existing type on conflict
            end
          end
        else
          @cvar_types[cls][node.name.to_s] = value_type == Types::NIL ? TypeVar.new : value_type
        end
        value_type
      end

      def infer_class_variable_read(node)
        cls = @current_class_name || "__toplevel__"
        # Check current class
        if @cvar_types[cls]
          type = @cvar_types[cls][node.name.to_s]
          return type if type && type != Types::UNTYPED
        end
        # Check parent classes
        if @current_class_name
          parent = @class_parents[@current_class_name]
          while parent
            if @cvar_types[parent]
              type = @cvar_types[parent][node.name.to_s]
              return type if type && type != Types::UNTYPED
            end
            parent = @class_parents[parent]
          end
        end
        # Check __toplevel__ (class variables defined outside class body)
        if cls != "__toplevel__" && @cvar_types["__toplevel__"]
          type = @cvar_types["__toplevel__"][node.name.to_s]
          return type if type && type != Types::UNTYPED
        end
        TypeVar.new
      end

      def infer_class_variable_operator_write(node)
        value_type = infer(node.value)
        cls = @current_class_name || "__toplevel__"
        @cvar_types[cls] ||= {}
        existing = @cvar_types[cls][node.name.to_s]
        existing || value_type
      end

      def infer_class_variable_or_write(node)
        value_type = infer(node.value)
        cls = @current_class_name || "__toplevel__"
        @cvar_types[cls] ||= {}
        existing = @cvar_types[cls][node.name.to_s]
        if existing && existing != Types::UNTYPED
          existing
        else
          @cvar_types[cls][node.name.to_s] = value_type
          value_type
        end
      end

      def infer_class_variable_and_write(node)
        value_type = infer(node.value)
        value_type
      end

      def infer_until(node)
        infer(node.predicate)
        infer_statements_node(node.statements, all_statement_position: true) if node.statements
        Types::NIL
      end

      def infer_break(node)
        if node.arguments&.arguments&.any?
          infer(node.arguments.arguments.first)
        end
        Types::BOTTOM
      end

      def infer_next(node)
        if node.arguments&.arguments&.any?
          infer(node.arguments.arguments.first)
        end
        Types::BOTTOM
      end

      def infer_case(node)
        # Infer the predicate (value being matched)
        infer(node.predicate) if node.predicate

        # Collect types from all when branches
        branch_types = []
        node.conditions&.each do |when_clause|
          # Infer condition expressions (for side effects / type checking)
          when_clause.conditions&.each { |cond| infer(cond) }
          # Infer body type
          if when_clause.statements
            body_type = infer_statements_node(when_clause.statements)
            branch_types << body_type
          end
        end

        # Infer else clause
        if node.else_clause&.statements
          else_type = infer_statements_node(node.else_clause.statements)
          branch_types << else_type
        end

        return Types::NIL if branch_types.empty?

        # Unify all branch types
        result_type = branch_types.first
        branch_types[1..].each do |bt|
          begin
            @unifier.unify(result_type, bt)
          rescue UnificationError
            # Different branch types — return the first one
            # (like if/else with different types)
          end
        end
        @unifier.apply(result_type)
      end

      def infer_range(node)
        infer(node.left) if node.left
        infer(node.right) if node.right
        Types::RANGE
      end

      def infer_global_variable_read(node)
        @global_var_types ||= {}
        existing = @global_var_types[node.name.to_s]
        if existing
          existing
        else
          # Create TypeVar placeholder — will be unified when the global var is written later
          tv = TypeVar.new(node.name.to_s)
          @global_var_types[node.name.to_s] = tv
          tv
        end
      end

      def infer_global_variable_write(node)
        value_type = infer(node.value)
        @global_var_types ||= {}
        existing = @global_var_types[node.name.to_s]
        if existing
          # Unify with existing type (might be a forward-reference TypeVar)
          begin
            @unifier.unify(existing, value_type)
          rescue UnificationError
            # Conflicting types — overwrite with new value
            @global_var_types[node.name.to_s] = value_type
          end
        else
          @global_var_types[node.name.to_s] = value_type
        end
        value_type
      end

      def infer_multi_write(node)
        value_type = infer(node.value) if node.value
        # Multi-write returns the RHS value
        value_type || Types::NIL
      end

      def infer_super(node)
        arg_types = (node.arguments&.arguments || []).map { |arg| infer(arg) }

        # Unify argument types with parent class's method parameter types
        if @current_class_name && @current_method_name
          parent_class = @class_parents[@current_class_name]
          if parent_class
            parent_key = :"#{parent_class}##{@current_method_name}"
            parent_func = @function_types[parent_key]
            if parent_func
              unify_call_args(parent_func, arg_types) if parent_func.is_a?(FunctionType)
              resolved = @unifier.prune(parent_func.return_type)
              return resolved unless resolved.is_a?(TypeVar)
            end
          end
        end

        Types::UNTYPED
      end

      def infer_forwarding_super(_node)
        # Bare `super` forwards all parameters from the current method to the parent
        if @current_class_name && @current_method_name
          parent_class = @class_parents[@current_class_name]
          if parent_class
            current_key = :"#{@current_class_name}##{@current_method_name}"
            current_func = @function_types[current_key]
            parent_key = :"#{parent_class}##{@current_method_name}"
            parent_func = @function_types[parent_key]
            if current_func && parent_func
              parent_func.param_types.zip(current_func.param_types).each do |parent_t, current_t|
                @unifier.unify(parent_t, current_t) if parent_t && current_t
              end
              resolved = @unifier.prune(parent_func.return_type)
              return resolved unless resolved.is_a?(TypeVar)
            end
          end
        end

        Types::UNTYPED
      end

      def infer_while(node)
        infer(node.predicate)
        # While loop body's result is never used (while returns nil),
        # so treat all statements as statement_position
        infer_statements_node(node.statements, all_statement_position: true) if node.statements
        Types::NIL
      end

      def infer_return(node)
        if node.arguments&.arguments&.any?
          infer(node.arguments.arguments.first)
        else
          Types::NIL
        end
      end

      # Handler for ProgramNode (called via infer dispatcher)
      def infer_program(node)
        infer_statements_node(node.statements)
      end

      def infer_statements(node)
        infer_statements_node(node)
      end

      # Infer types for a statements node
      # @param node [Prism::StatementsNode] the statements node
      # @param all_statement_position [Boolean] if true, treat ALL statements
      #   (including the last) as statement position. Use this when the
      #   parent construct doesn't use the result (e.g., if in statement position)
      def infer_statements_node(node, all_statement_position: false)
        return Types::NIL unless node&.body&.any?

        statements = node.body

        if all_statement_position
          # All statements are in statement position (result not used)
          statements.each do |stmt|
            infer(stmt, statement_position: true)
          end
          Types::NIL
        else
          # All statements except the last are in "statement position"
          # (their result is not used), so they don't need type consistency
          # for if/unless branches.
          statements[0..-2].each do |stmt|
            infer(stmt, statement_position: true)
          end

          # The last statement's type is the result of the block
          infer(statements.last)
        end
      end

      def infer_class(node)
        old_class = @current_class_name
        @current_class_name = (node.constant_path.name.to_s rescue nil)
        # Track parent class for super type propagation
        if @current_class_name && node.superclass
          parent_name = node.superclass.name.to_s rescue nil
          @class_parents[@current_class_name] = parent_name if parent_name
        end
        push_env
        infer(node.body) if node.body
        pop_env
        @current_class_name = old_class
        Types::NIL
      end

      def infer_singleton_class(node)
        push_env
        infer(node.body) if node.body
        pop_env
        Types::NIL
      end

      def infer_self(node)
        if @current_class_name
          type = Types::ClassInstance.new(@current_class_name.to_sym)
        else
          type = Types::UNTYPED
        end
        record_node_type(node, type)
        type
      end

      def infer_parentheses(node)
        node.body ? infer(node.body) : Types::NIL
      end

      def rbs_field_to_type(ftype)
        case ftype.to_s.to_sym
        when :Int64, :Integer then Types::INTEGER
        when :Float64, :Float then Types::FLOAT
        when :Bool then Types::BOOL
        when :String then Types::STRING
        else Types::UNTYPED
        end
      end

      def resolve_ivar_types!
        @ivar_types.each do |class_name, ivars|
          ivars.each do |ivar_name, type|
            next unless type
            resolved = @unifier.apply(type)
            @ivar_types[class_name][ivar_name] = resolved
          end
        end
      end

      # Kotlin-style validation: ensure all types are resolved after inference.
      # Any surviving TypeVar indicates incomplete type resolution.
      def validate_all_types_resolved!
        @unresolved_type_warnings = []

        # Check function param/return types
        @function_types.each do |func_name, func_type|
          next unless func_type.is_a?(FunctionType)

          func_type.param_types.each_with_index do |pt, i|
            resolved = @unifier.apply(pt)
            if unresolved_typevar?(resolved)
              @unresolved_type_warnings << {
                kind: :param,
                function: func_name.to_s,
                index: i,
                typevar: resolved.to_s
              }
            end
          end

          ret = @unifier.apply(func_type.return_type)
          if unresolved_typevar?(ret)
            @unresolved_type_warnings << {
              kind: :return,
              function: func_name.to_s,
              typevar: ret.to_s
            }
          end
        end
      end

      # Check if a type contains an unresolved TypeVar
      def unresolved_typevar?(type)
        case type
        when TypeVar
          pruned = type.prune
          pruned.is_a?(TypeVar) && !pruned.instance
        when FunctionType
          type.param_types.any? { |t| unresolved_typevar?(t) } ||
            unresolved_typevar?(type.return_type)
        when Types::ClassInstance
          type.type_args.any? { |t| unresolved_typevar?(t) }
        else
          false
        end
      end
    end
  end
end
