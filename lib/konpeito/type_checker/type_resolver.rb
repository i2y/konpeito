# frozen_string_literal: true

require "set"
require_relative "types"
require_relative "unification"

module Konpeito
  module TypeChecker
    # Pre-codegen validation pass: checks for remaining unresolved TypeVars in HIR.
    #
    # This pass runs between type inference (HM) and code generation. It attempts
    # to resolve TypeVars that HM couldn't determine using:
    #   1. Class hierarchy information (parent method signatures)
    #   2. Call-site argument types (supplements HM unification)
    #
    # Structural typing heuristics (e.g., "find class by method set") are intentionally
    # NOT used — per Kotlin-style design, all types must be resolved by type inference.
    # If resolution fails, it collects actionable error messages directing the user
    # to add RBS type annotations for the specific parameters/variables involved.
    class TypeResolver
      attr_reader :errors

      def initialize(hir_program, hm_inferrer: nil, rbs_loader: nil, jvm_interop_classes: nil, monomorphizer: nil)
        @hir = hir_program
        @hm_inferrer = hm_inferrer
        @rbs_loader = rbs_loader
        @jvm_interop_classes = jvm_interop_classes || {}
        @monomorphizer = monomorphizer
        @errors = []

        # Collect class info from HIR
        @class_methods = {}  # "ClassName" => Set of method names
        @class_parents = {}  # "ClassName" => "ParentName"
        collect_class_info
      end

      # Run the type resolution pass.
      # Returns true if all types were resolved, false if errors remain.
      def resolve!
        @errors.clear

        # Propagate types from parent method signatures to overriding methods
        resolve_parent_method_params

        # Resolve TypeVar parameters using call-site argument types
        resolve_call_site_params

        # Structural typing heuristic was removed per Kotlin-style design.
        # All types must be resolved by HM inference + RBS, not by guessing from method names.

        # Scan remaining unresolved TypeVars and collect error messages
        collect_unresolved_errors

        @errors.empty?
      end

      private

      def collect_class_info
        @hir.classes.each do |class_def|
          name = class_def.name.to_s
          @class_parents[name] = class_def.superclass.to_s if class_def.respond_to?(:superclass) && class_def.superclass
          @class_methods[name] = Set.new
        end

        @hir.functions.each do |func|
          if func.owner_class
            @class_methods[func.owner_class.to_s] ||= Set.new
            method_name = func.name.to_s.sub(/^#{Regexp.escape(func.owner_class.to_s)}#/, "")
            @class_methods[func.owner_class.to_s].add(method_name)
          end
        end
      end

      # Propagate parameter types from parent class methods to child overrides
      def resolve_parent_method_params
        @hir.functions.each do |func|
          next unless func.owner_class
          next if func.params.empty?

          unresolved_params = func.params.select { |p| unresolved?(p.type) }
          next if unresolved_params.empty?

          parent_name = @class_parents[func.owner_class.to_s]
          while parent_name
            method_name = func.name.to_s.sub(/^#{Regexp.escape(func.owner_class.to_s)}#/, "")
            parent_func = @hir.functions.find { |f|
              f.owner_class.to_s == parent_name &&
                f.name.to_s == "#{parent_name}##{method_name}"
            }

            if parent_func && parent_func.params.size == func.params.size
              func.params.each_with_index do |param, i|
                parent_param = parent_func.params[i]
                if unresolved?(param.type) && !unresolved?(parent_param.type)
                  begin
                    unifier = Unifier.new
                    unifier.unify(param.type, parent_param.type)
                  rescue UnificationError
                    # Incompatible types — skip
                  end
                end
              end
              break
            end

            parent_name = @class_parents[parent_name]
          end
        end
      end

      # Try to resolve parameter TypeVars from call-site argument types
      def resolve_call_site_params
        @hir.functions.each do |func|
          func.body.each do |bb|
            bb.instructions.each do |inst|
              next unless inst.is_a?(HIR::Call)
              next unless inst.args

              target_name = inst.method_name.to_s
              # Try to find the function being called (for self/top-level calls)
              target_func = nil
              if inst.receiver.nil? || inst.receiver.is_a?(HIR::SelfRef)
                target_func = @hir.functions.find { |f| f.name.to_s == target_name }
              end
              next unless target_func

              inst.args.each_with_index do |arg, i|
                next if i >= target_func.params.size
                param = target_func.params[i]
                next unless unresolved?(param.type)

                arg_type = infer_instruction_type(arg)
                next unless arg_type && !unresolved?(arg_type)

                begin
                  unifier = Unifier.new
                  unifier.unify(param.type, arg_type)
                rescue UnificationError
                  # Incompatible — skip
                end
              end
            end
          end
        end
      end

      # Scan all HIR instructions and collect errors for remaining unresolved types
      def collect_unresolved_errors
        seen_typevars = Set.new  # Track TypeVar IDs to avoid duplicate errors

        @hir.functions.each do |func|
          # Skip polymorphic functions (type erasure is expected, not an error).
          # These have monomorphized specializations with concrete types.
          next if function_is_polymorphic?(func.name.to_s)

          collect_unresolved_from_blocks(func.body, func, seen_typevars)
        end
      end

      # Check if a function is polymorphic or a monomorphized specialization.
      # - Original polymorphic functions have TypeVar params (type erasure, expected).
      # - Monomorphized copies (e.g., add_Integer_Integer) share TypeVar references
      #   from the original but receive concrete types via params — not an error.
      def function_is_polymorphic?(func_name)
        return false unless @monomorphizer
        # Original polymorphic function (has specializations)
        return true if @monomorphizer.specializations.any? { |key, _| key[0] == func_name }
        # Monomorphized copy (is a specialization of another function)
        return true if @monomorphizer.specializations.any? { |_, name| name == func_name }
        false
      end

      def collect_unresolved_from_blocks(blocks, func, seen_typevars)
        blocks.each do |bb|
          bb.instructions.each do |inst|
            # Recurse into block bodies
            if inst.respond_to?(:block) && inst.block && inst.block.respond_to?(:body)
              collect_unresolved_from_blocks(inst.block.body, func, seen_typevars)
            end

            next unless inst.is_a?(HIR::Call)
            next unless inst.receiver
            next unless unresolved?(inst.receiver.type)
            # .call on block/proc variables is handled at codegen as invokevirtual.
            # The receiver TypeVar represents a captured block — not an inference failure.
            next if inst.method_name.to_s == "call"

            recv_type = inst.receiver.type.prune
            next unless recv_type.is_a?(TypeVar)
            next if seen_typevars.include?(recv_type.id)

            seen_typevars.add(recv_type.id)

            location = format_location(func)
            method_name = inst.method_name.to_s

            @errors << format_error(
              location: location,
              method_name: method_name,
              receiver_type: recv_type.to_s,
              hint: suggest_fix(func, inst)
            )
          end
        end
      end

      def format_error(location:, method_name:, receiver_type:, hint:)
        msg = "#{location}: cannot resolve receiver type for .#{method_name} (type: #{receiver_type})"
        msg += "\n    #{hint}" if hint
        msg
      end

      def suggest_fix(func, inst)
        if func.owner_class
          method_name = func.name.to_s.sub(/^#{Regexp.escape(func.owner_class.to_s)}#/, "")
          param_name = extract_param_name(inst.receiver)

          if param_name
            "Add RBS type annotation for parameter '#{param_name}' in #{func.owner_class}##{method_name}"
          else
            "Add RBS type annotations for #{func.owner_class}##{method_name}"
          end
        else
          "Add RBS type annotations to resolve the receiver type"
        end
      end

      def extract_param_name(inst)
        if inst.respond_to?(:name)
          inst.name.to_s
        elsif inst.respond_to?(:var_name)
          inst.var_name.to_s
        else
          nil
        end
      end

      def format_location(func)
        if func.owner_class
          method_name = func.name.to_s.sub(/^#{Regexp.escape(func.owner_class.to_s)}#/, "")
          "#{func.owner_class}##{method_name}"
        else
          func.name.to_s
        end
      end

      def unresolved?(type)
        return false unless type
        if type.is_a?(TypeVar)
          pruned = type.prune
          pruned.is_a?(TypeVar) && !pruned.instance
        else
          false
        end
      end

      def prune(type)
        if type.is_a?(TypeVar)
          type.prune
        else
          type
        end
      end

      def infer_instruction_type(inst)
        return nil unless inst
        return nil unless inst.respond_to?(:type)
        type = inst.type
        return nil unless type
        # Prune TypeVars to get concrete type
        type.is_a?(TypeVar) ? type.prune : type
      end
    end
  end
end
