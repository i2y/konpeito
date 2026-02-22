# frozen_string_literal: true

module Konpeito
  module Codegen
    # Monomorphizer generates specialized versions of polymorphic functions
    # for specific type instantiations.
    #
    # Example:
    #   def identity(x)
    #     x
    #   end
    #
    #   identity(42)       # generates identity_Integer
    #   identity("hello")  # generates identity_String
    #
    class Monomorphizer
      attr_reader :specializations, :call_sites, :union_dispatches

      def initialize(hir_program, type_info)
        @hir_program = hir_program
        @type_info = type_info  # HMInferrer
        @specializations = {}   # { [func_name, type_args] => specialized_name }
        @call_sites = []        # Array of { call: HIR::Call, types: [...] }
        @union_call_sites = []  # Calls requiring runtime dispatch
        @union_dispatches = {}  # { [func_name, original_types] => dispatch_info }
        @generated_functions = {}
      end

      # Analyze the HIR program to find monomorphization opportunities
      def analyze
        @hir_program.functions.each do |func|
          analyze_function(func)
        end

        # Determine which specializations to generate
        determine_specializations
      end

      # Apply monomorphization transformations
      def transform
        # Generate specialized function copies
        generate_specialized_functions

        # Rewrite call sites to use specialized functions
        rewrite_call_sites
      end

      # Get the specialized function name for a call
      def specialized_name(func_name, arg_types)
        key = [func_name.to_s, arg_types.map(&:to_s)]
        @specializations[key]
      end

      private

      def analyze_function(func)
        func.body.each do |block|
          block.instructions.each do |inst|
            analyze_instruction(inst, func)
          end
        end
      end

      def analyze_instruction(inst, context_func)
        case inst
        when HIR::Call
          analyze_call(inst, context_func)
        end
      end

      def analyze_call(call, context_func)
        # Only specialize self-calls (calls on the same instance)
        # Cross-class calls like h.add(1, 2) should not be specialized as direct calls
        return unless self_receiver?(call.receiver)

        # Check if this is a call to a local function that could be specialized
        target_func = find_function(call.method_name)
        return unless target_func
        return if target_func.params.empty?

        # Skip functions with rest params (*args) or keyword_rest (**kwargs)
        # Rest params collect arguments into an array; specializing by element type is incorrect
        return if target_func.params.any? { |p| p.rest || p.keyword_rest }

        # Get parameter types from target function (may include Union types from RBS)
        param_types = target_func.params.map(&:type)

        # Get concrete argument types at this call site
        arg_types = call.args.map { |arg| get_concrete_type(arg) }

        # Check if any PARAMETER has a Union type (from RBS definition)
        has_union_param = param_types.any? { |t| union_type?(t) }

        # Also check if any argument has a Union type (from type inference)
        has_union_arg = arg_types.any? { |t| union_type?(t) }

        if has_union_param || has_union_arg
          # Use parameter types for expansion (they contain the full Union info)
          types_to_expand = param_types.each_with_index.map do |param_type, i|
            if union_type?(param_type)
              param_type
            elsif i < arg_types.size && union_type?(arg_types[i])
              arg_types[i]
            else
              arg_types[i] || param_type
            end
          end

          # Expand union types into all possible combinations
          expand_union_types(types_to_expand).each do |concrete_types|
            @call_sites << {
              call: call,
              context: context_func,
              target: target_func.name,
              types: concrete_types,
              union_dispatch: true,
              original_types: types_to_expand
            }
          end
        else
          # Skip if any type is still polymorphic
          return if arg_types.any? { |t| polymorphic_type?(t) }

          @call_sites << {
            call: call,
            context: context_func,
            target: target_func.name,
            types: arg_types,
            union_dispatch: false
          }
        end
      end

      # Check if a receiver is self (same instance)
      # For monomorphization, we must be strict: only SelfRef is considered self
      def self_receiver?(receiver)
        receiver.is_a?(HIR::SelfRef)
      end

      def find_function(name)
        @hir_program.functions.find { |f| f.name.to_s == name.to_s }
      end

      def get_concrete_type(hir_value)
        case hir_value
        when HIR::Instruction
          hir_value.type
        when HIR::Node
          hir_value.type
        else
          TypeChecker::Types::UNTYPED
        end
      end

      def polymorphic_type?(type)
        return true if type.nil?
        return true if type.is_a?(TypeChecker::Types::Untyped)
        return true if type.respond_to?(:id) && type.class.name.include?("TypeVar")
        false
      end

      # Check if a type is a Union type
      def union_type?(type)
        type.is_a?(TypeChecker::Types::Union)
      end

      # Expand union types into all possible combinations
      # Example: [Integer, Union[String, Float]] => [[Integer, String], [Integer, Float]]
      def expand_union_types(types)
        combinations = [[]]
        types.each do |type|
          if union_type?(type)
            new_combinations = []
            combinations.each do |combo|
              type.types.each { |member| new_combinations << (combo + [member]) }
            end
            combinations = new_combinations
          else
            combinations = combinations.map { |c| c + [type] }
          end
        end
        combinations
      end

      def determine_specializations
        # Group call sites by (function, types)
        grouped = @call_sites.group_by { |cs| [cs[:target], cs[:types]] }

        # Detect functions called with inconsistent arg types across call sites.
        # If the same param position receives different types at different sites
        # (e.g., assert_equal called with both Integer and String as first arg),
        # monomorphization is not useful — skip the function entirely.
        skip_functions = detect_inconsistent_call_sites
        skip_functions.merge(detect_nil_compared_functions)

        grouped.each do |(func_name, types), sites|
          next if types.any? { |t| t == TypeChecker::Types::UNTYPED || t.is_a?(TypeChecker::Types::Untyped) }
          next if skip_functions.include?(func_name.to_s)
          # Skip if any type is an unresolved RBS type parameter (Elem, K, V, etc.)
          next if types.any? { |t| t.is_a?(TypeChecker::Types::ClassInstance) && RBS_TYPE_PARAMS.include?(t.name) }

          type_suffix = types.map { |t| type_to_suffix(t) }.join("_")
          specialized = "#{func_name}_#{type_suffix}"

          key = [func_name.to_s, types.map(&:to_s)]
          @specializations[key] = specialized

          # Track if this came from union expansion
          if sites.any? { |s| s[:union_dispatch] }
            @union_call_sites << {
              call: sites.first[:call],
              target: func_name,
              original_types: sites.first[:original_types],
              concrete_types: types,
              specialized_name: specialized
            }
          end
        end

        # Group union call sites by original call
        consolidate_union_dispatches
      end

      # Returns true if the given param is compared with nil in the function body.
      # Functions that check params against nil are designed to handle nil values,
      # so creating type-specialized copies that unbox params is incorrect.
      def param_compared_with_nil?(func, param_name)
        func.body.each do |bb|
          bb.instructions.each do |inst|
            next unless inst.is_a?(HIR::Call)
            if inst.method_name == "=="
              # Check: param == nil
              recv = inst.receiver
              if recv.is_a?(HIR::LoadLocal)
                var_name = recv.var.respond_to?(:name) ? recv.var.name.to_s : recv.var.to_s
                if var_name == param_name && inst.args.first.is_a?(HIR::NilLit)
                  return true
                end
              end
              # Check: nil == param
              if recv.is_a?(HIR::NilLit) && inst.args.first.is_a?(HIR::LoadLocal)
                arg_var = inst.args.first.var
                arg_name = arg_var.respond_to?(:name) ? arg_var.name.to_s : arg_var.to_s
                return true if arg_name == param_name
              end
            end
            # Check: param.nil?
            if inst.method_name == "nil?" && inst.receiver.is_a?(HIR::LoadLocal)
              var_name = inst.receiver.var.respond_to?(:name) ? inst.receiver.var.name.to_s : inst.receiver.var.to_s
              return true if var_name == param_name
              return true
            end
          end
        end
        false
      end

      # Returns Set of function names that should skip monomorphization
      # because they compare parameters with nil.
      def detect_nil_compared_functions
        skip = Set.new
        @hir_program.functions.each do |func|
          func.params.each do |param|
            if param_compared_with_nil?(func, param.name.to_s)
              skip.add(func.name.to_s)
              break
            end
          end
        end
        skip
      end

      # Detect functions where different call sites pass different types for
      # the same parameter position. These functions should not be monomorphized
      # because specialized variants would have incompatible signatures.
      def detect_inconsistent_call_sites
        # Group non-union call sites by target function
        by_func = @call_sites.reject { |cs| cs[:union_dispatch] }
                             .group_by { |cs| cs[:target].to_s }

        skip = Set.new
        by_func.each do |func_name, sites|
          next if sites.size <= 1
          # Check each param position for type consistency
          max_arity = sites.map { |s| s[:types].size }.max
          max_arity.times do |i|
            types_at_i = sites.map { |s| s[:types][i]&.to_s }.compact.uniq
            if types_at_i.size > 1
              skip.add(func_name)
              break
            end
          end
        end
        skip
      end

      # Group union call sites by their original (pre-expansion) call
      def consolidate_union_dispatches
        @union_dispatches = {}

        # Group by (target, original_types)
        grouped = @union_call_sites
          .select { |s| s[:original_types] }
          .group_by { |s| [s[:target], s[:original_types].map(&:to_s)] }

        grouped.each do |(target, original_type_strs), sites|
          # Build a mapping from concrete types to specialized function names
          specializations = {}
          sites.each do |site|
            concrete_key = site[:concrete_types].map(&:to_s)
            specializations[concrete_key] = site[:specialized_name]
          end

          # Find union positions (which argument indices have Union types)
          original_types = sites.first[:original_types]
          union_positions = original_types.each_with_index
            .select { |t, _i| union_type?(t) }
            .map { |_, i| i }

          key = [target.to_s, original_type_strs]
          @union_dispatches[key] = {
            call: sites.first[:call],
            target: target,
            original_types: original_types,
            union_positions: union_positions,
            specializations: specializations
          }
        end
      end

      # RBS type parameter names that should not be used as monomorphized suffixes
      # These are unresolved generic type variables, not concrete Ruby classes
      RBS_TYPE_PARAMS = Set.new(%w[Elem K V U T S R E A B C D N M].map(&:to_sym)).freeze

      def type_to_suffix(type)
        case type
        when TypeChecker::Types::ClassInstance
          # If the type name is an unresolved RBS type parameter (Elem, K, V, etc.),
          # treat it as untyped to avoid generating rb_const_get("Elem") at runtime
          if RBS_TYPE_PARAMS.include?(type.name)
            "Any"
          else
            type.name.to_s
          end
        when TypeChecker::Types::NilType
          "Nil"
        when TypeChecker::Types::BoolType
          "Bool"
        else
          type.to_s.gsub(/[^a-zA-Z0-9]/, "_")
        end
      end

      def generate_specialized_functions
        @specializations.each do |(func_name, type_strs), specialized_name|
          original = find_function(func_name)
          next unless original

          # Parse type strings back to types (for comparison in call sites)
          types = @call_sites
            .find { |cs| cs[:target].to_s == func_name && cs[:types].map(&:to_s) == type_strs }
            &.dig(:types)
          next unless types

          specialized = clone_function(original, specialized_name, types)
          @generated_functions[specialized_name] = specialized
          @hir_program.functions << specialized
        end
      end

      def clone_function(original, new_name, param_types)
        # Create specialized parameter list with concrete types
        specialized_params = original.params.each_with_index.map do |param, i|
          HIR::Param.new(
            name: param.name,
            type: param_types[i] || param.type,
            default_value: param.default_value,
            rest: param.rest,
            keyword: param.keyword,
            block: param.block
          )
        end

        # Deep clone the body blocks
        specialized_body = deep_clone_blocks(original.body)

        HIR::Function.new(
          name: new_name,
          params: specialized_params,
          body: specialized_body,
          return_type: original.return_type,
          is_instance_method: original.is_instance_method,
          owner_class: original.owner_class
        )
      end

      def deep_clone_blocks(blocks)
        # Create a simple deep copy of blocks
        # In a full implementation, we'd update type information throughout
        blocks.map do |block|
          new_block = HIR::BasicBlock.new(label: block.label)
          block.instructions.each do |inst|
            new_block.add_instruction(clone_instruction(inst))
          end
          new_block.set_terminator(clone_terminator(block.terminator)) if block.terminator
          new_block
        end
      end

      def clone_instruction(inst)
        # Simple shallow clone for now
        # A full implementation would update types based on specialization
        inst.dup
      rescue TypeError
        # If dup fails, return the original
        inst
      end

      def clone_terminator(term)
        term.dup
      rescue TypeError
        term
      end

      def rewrite_call_sites
        # Track which calls have already been processed (for Union calls that appear multiple times)
        processed_calls = Set.new

        @call_sites.each do |site|
          call = site[:call]
          next if processed_calls.include?(call.object_id)

          if site[:union_dispatch]
            # For union dispatch calls, set the dispatch info instead of a single specialized target
            dispatch_key = [site[:target].to_s, site[:original_types].map(&:to_s)]
            dispatch_info = @union_dispatches[dispatch_key]
            if dispatch_info
              call.instance_variable_set(:@union_dispatch_info, dispatch_info)
              processed_calls.add(call.object_id)
            end
          else
            # Regular monomorphized call
            key = [site[:target].to_s, site[:types].map(&:to_s)]
            specialized_name = @specializations[key]
            next unless specialized_name

            call.instance_variable_set(:@specialized_target, specialized_name)
            processed_calls.add(call.object_id)
          end
        end
      end
    end
  end
end
