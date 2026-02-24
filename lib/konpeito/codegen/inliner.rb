# frozen_string_literal: true

module Konpeito
  module Codegen
    # Inlines small functions at call sites to eliminate call overhead
    # and enable further optimizations.
    #
    # Inlining criteria:
    # - Function body has <= MAX_INLINE_INSTRUCTIONS instructions
    # - No recursion (direct or indirect)
    # - Not a class method (for simplicity)
    #
    class Inliner
      MAX_INLINE_INSTRUCTIONS = 10
      MAX_INLINE_DEPTH = 3

      attr_reader :inlined_count

      def initialize(hir_program)
        @hir_program = hir_program
        @functions = {}  # name -> HIR::Function
        @inline_candidates = {}  # name -> true/false
        @call_graph = {}  # name -> Set of called function names
        @inlined_count = 0
        @current_depth = 0
      end

      # Analyze and transform the HIR program
      def optimize
        build_function_map
        build_call_graph
        identify_candidates
        inline_functions
      end

      private

      def build_function_map
        @hir_program.functions.each do |func|
          @functions[func.name.to_s] = func
        end
      end

      def build_call_graph
        @hir_program.functions.each do |func|
          calls = Set.new
          func.body.each do |block|
            block.instructions.each do |inst|
              if inst.is_a?(HIR::Call) && self_call?(inst)
                calls << inst.method_name.to_s
              end
            end
          end
          @call_graph[func.name.to_s] = calls
        end
      end

      def self_call?(inst)
        inst.receiver.is_a?(HIR::SelfRef) ||
          (inst.receiver.is_a?(HIR::Instruction) &&
           inst.receiver.type.is_a?(TypeChecker::Types::Untyped))
      end

      def identify_candidates
        @functions.each do |name, func|
          @inline_candidates[name] = should_inline?(func)
        end
      end

      def should_inline?(func)
        # Skip main function
        return false if func.name.to_s == "__main__"

        # Skip class methods for now
        return false if func.owner_class

        # Skip functions with rest params (*args), keyword_rest (**kwargs), or block params (&blk)
        # The inliner doesn't support rest param array aggregation or block capture context
        return false if func.params.any? { |p| p.rest || p.keyword_rest || p.block }

        # Skip functions with multiple blocks (contains if/while/etc.)
        # These have complex control flow that can't be simply inlined
        return false if func.body.size > 1

        # Skip functions with Branch terminators (if statements)
        # The inliner doesn't support control flow structures
        func.body.each do |block|
          return false if block.terminator.is_a?(HIR::Branch)
        end

        # Skip functions containing block calls (captures need complex transformation)
        # Skip functions containing yield (need KBlock parameter handling)
        # Skip functions containing BeginRescue (exception handling has complex sub-block structure)
        # Skip functions containing ThreadNew/FiberNew (callbacks reference specific allocas)
        func.body.each do |block|
          block.instructions.each do |inst|
            return false if inst.is_a?(HIR::Call) && inst.block
            return false if inst.is_a?(HIR::Yield)
            return false if inst.is_a?(HIR::BeginRescue)
            return false if inst.is_a?(HIR::CaseStatement)
            return false if inst.is_a?(HIR::CaseMatchStatement)
            return false if inst.is_a?(HIR::ThreadNew)
            return false if inst.is_a?(HIR::FiberNew)
          end
        end

        # Count instructions
        instruction_count = func.body.sum { |block| block.instructions.size }
        return false if instruction_count > MAX_INLINE_INSTRUCTIONS

        # Check for recursion
        return false if recursive?(func.name.to_s, Set.new)

        true
      end

      def recursive?(func_name, visited)
        return true if visited.include?(func_name)
        visited = visited + [func_name]

        calls = @call_graph[func_name] || Set.new
        calls.any? { |callee| recursive?(callee, visited) }
      end

      def inline_functions
        # Process each function
        @hir_program.functions.each do |func|
          @current_depth = 0
          inline_in_function(func)
        end
      end

      def inline_in_function(func)
        return if @current_depth >= MAX_INLINE_DEPTH

        changed = true
        while changed
          changed = false

          func.body.each do |block|
            new_instructions = []

            block.instructions.each do |inst|
              if inst.is_a?(HIR::Call) && can_inline_call?(inst)
                # Inline this call
                inlined = inline_call(inst, func)
                new_instructions.concat(inlined)
                changed = true
                @inlined_count += 1
              else
                new_instructions << inst
              end
            end

            # Replace instructions in block
            block.instance_variable_set(:@instructions, new_instructions)
          end
        end
      end

      def can_inline_call?(inst)
        return false unless self_call?(inst)

        # Don't inline calls with splat arguments - they need rb_apply
        return false if inst.args.any? { |a| a.is_a?(HIR::SplatArg) }

        callee_name = inst.method_name.to_s
        @inline_candidates[callee_name] == true
      end

      def inline_call(call_inst, caller_func)
        callee = @functions[call_inst.method_name.to_s]
        return [call_inst] unless callee

        @current_depth += 1

        # Create a unique prefix for inlined variables
        prefix = "inline_#{@inlined_count}_"

        # Map callee parameters to call arguments
        param_map = {}
        callee.params.each_with_index do |param, i|
          if call_inst.args[i]
            param_map[param.name] = call_inst.args[i]
          elsif param.default_value
            # Use the default value for missing optional args
            default_hir = prism_to_hir_literal(param.default_value)
            param_map[param.name] = default_hir if default_hir
          end
        end
        # Also map keyword arguments by name
        if call_inst.respond_to?(:keyword_args) && call_inst.has_keyword_args?
          call_inst.keyword_args.each do |kw_name, kw_value|
            # Find the callee param with matching name
            callee.params.each do |param|
              if param.name.to_s == kw_name.to_s
                param_map[param.name] = kw_value
              end
            end
          end
        end

        # Clone and transform instructions from callee
        result_instructions = []
        final_value = nil

        callee.body.each do |block|
          block.instructions.each do |inst|
            cloned = clone_and_rename(inst, prefix, param_map)
            result_instructions << cloned if cloned
            final_value = cloned
          end

          # Handle return in terminator
          if block.terminator.is_a?(HIR::Return)
            ret_value = block.terminator.value
            if ret_value
              final_value = transform_value(ret_value, prefix, param_map)
            end
          end
        end

        # Store result if needed
        if call_inst.result_var && final_value
          store = HIR::StoreLocal.new(
            var: HIR::LocalVar.new(name: call_inst.result_var),
            value: final_value,
            type: call_inst.type
          )
          result_instructions << store
        end

        @current_depth -= 1
        result_instructions
      end

      # Convert a Prism AST default value node to an HIR literal node.
      # Assigns a result_var so the LLVM generator can generate it properly.
      def prism_to_hir_literal(prism_node)
        @default_var_counter ||= 0
        @default_var_counter += 1
        rv = "_default_#{@default_var_counter}"

        case prism_node
        when Prism::IntegerNode
          HIR::IntegerLit.new(value: prism_node.value, result_var: rv)
        when Prism::FloatNode
          HIR::FloatLit.new(value: prism_node.value, result_var: rv)
        when Prism::StringNode
          HIR::StringLit.new(value: prism_node.unescaped, result_var: rv)
        when Prism::SymbolNode
          HIR::SymbolLit.new(value: prism_node.value, result_var: rv)
        when Prism::NilNode
          HIR::NilLit.new(result_var: rv)
        when Prism::TrueNode
          HIR::BoolLit.new(value: true, result_var: rv)
        when Prism::FalseNode
          HIR::BoolLit.new(value: false, result_var: rv)
        else
          nil
        end
      end

      def clone_and_rename(inst, prefix, param_map)
        case inst
        when HIR::LoadLocal
          # Check if this is a parameter reference
          if param_map.key?(inst.var.name)
            # Return the argument value directly
            return nil if inst.result_var.nil?

            # Store the argument value in the result variable
            return HIR::StoreLocal.new(
              var: HIR::LocalVar.new(name: prefix + inst.result_var),
              value: param_map[inst.var.name],
              type: inst.type
            )
          end

          # Regular local variable
          new_var = HIR::LocalVar.new(
            name: prefix + inst.var.name,
            type: inst.var.type
          )
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::LoadLocal.new(var: new_var, type: inst.type, result_var: new_result)

        when HIR::StoreLocal
          new_var = HIR::LocalVar.new(
            name: prefix + inst.var.name,
            type: inst.var.type
          )
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::StoreLocal.new(var: new_var, value: new_value, type: inst.type)

        when HIR::Call
          new_receiver = transform_value(inst.receiver, prefix, param_map)
          new_args = inst.args.map { |a| transform_value(a, prefix, param_map) }
          new_result = inst.result_var ? prefix + inst.result_var : nil

          HIR::Call.new(
            receiver: new_receiver,
            method_name: inst.method_name,
            args: new_args,
            block: inst.block,
            type: inst.type,
            result_var: new_result,
            safe_navigation: inst.safe_navigation
          )

        when HIR::IntegerLit, HIR::FloatLit, HIR::StringLit,
             HIR::SymbolLit, HIR::BoolLit
          new_result = inst.result_var ? prefix + inst.result_var : nil
          inst.class.new(value: inst.value, result_var: new_result)

        when HIR::NilLit
          # NilLit doesn't have a value parameter
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::NilLit.new(result_var: new_result)

        when HIR::SelfRef
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::SelfRef.new(type: inst.type, result_var: new_result)

        when HIR::StringConcat
          # Transform all parts to handle parameter substitution
          new_parts = inst.parts.map { |part| transform_value(part, prefix, param_map) }
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::StringConcat.new(parts: new_parts, result_var: new_result)

        when HIR::RangeLit
          new_left = transform_value(inst.left, prefix, param_map)
          new_right = transform_value(inst.right, prefix, param_map)
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::RangeLit.new(
            left: new_left, right: new_right,
            exclusive: inst.exclusive, type: inst.type, result_var: new_result
          )

        when HIR::ArrayLit
          new_elements = inst.elements.map { |e| transform_value(e, prefix, param_map) }
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::ArrayLit.new(
            elements: new_elements, result_var: new_result
          )

        when HIR::HashLit
          new_pairs = inst.pairs.map { |k, v| [transform_value(k, prefix, param_map), transform_value(v, prefix, param_map)] }
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::HashLit.new(
            pairs: new_pairs, result_var: new_result
          )

        when HIR::LoadGlobalVar
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::LoadGlobalVar.new(name: inst.name, type: inst.type, result_var: new_result)

        when HIR::StoreGlobalVar
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::StoreGlobalVar.new(name: inst.name, value: new_value, type: inst.type)

        when HIR::LoadClassVar
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::LoadClassVar.new(name: inst.name, type: inst.type, result_var: new_result)

        when HIR::StoreClassVar
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::StoreClassVar.new(name: inst.name, value: new_value, type: inst.type)

        when HIR::RegexpLit
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::RegexpLit.new(pattern: inst.pattern, options: inst.options, result_var: new_result)

        when HIR::NativeArrayAlloc
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_size = transform_value(inst.size, prefix, param_map)
          HIR::NativeArrayAlloc.new(
            size: new_size,
            element_type: inst.element_type,
            result_var: new_result
          )

        when HIR::StaticArrayAlloc
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_initial = inst.initial_value ? transform_value(inst.initial_value, prefix, param_map) : nil
          HIR::StaticArrayAlloc.new(
            element_type: inst.element_type,
            size: inst.size,
            initial_value: new_initial,
            result_var: new_result
          )

        when HIR::NativeArrayGet
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_array = transform_value(inst.array, prefix, param_map)
          new_index = transform_value(inst.index, prefix, param_map)
          HIR::NativeArrayGet.new(
            array: new_array, index: new_index,
            element_type: inst.element_type, result_var: new_result
          )

        when HIR::NativeArraySet
          new_array = transform_value(inst.array, prefix, param_map)
          new_index = transform_value(inst.index, prefix, param_map)
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::NativeArraySet.new(
            array: new_array, index: new_index, value: new_value,
            element_type: inst.element_type
          )

        when HIR::NativeArrayLength
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_array = transform_value(inst.array, prefix, param_map)
          HIR::NativeArrayLength.new(array: new_array, result_var: new_result)

        when HIR::StaticArrayGet
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_array = transform_value(inst.array, prefix, param_map)
          new_index = transform_value(inst.index, prefix, param_map)
          HIR::StaticArrayGet.new(
            array: new_array, index: new_index,
            element_type: inst.element_type, size: inst.size, result_var: new_result
          )

        when HIR::StaticArraySet
          new_array = transform_value(inst.array, prefix, param_map)
          new_index = transform_value(inst.index, prefix, param_map)
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::StaticArraySet.new(
            array: new_array, index: new_index, value: new_value,
            element_type: inst.element_type, size: inst.size
          )

        when HIR::StaticArraySize
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_array = transform_value(inst.array, prefix, param_map)
          HIR::StaticArraySize.new(
            array: new_array, size: inst.size, result_var: new_result
          )

        when HIR::ConstantLookup
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::ConstantLookup.new(name: inst.name, scope: inst.scope, type: inst.type, result_var: new_result)

        when HIR::NativeNew
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_args = inst.args.map { |a| transform_value(a, prefix, param_map) }
          HIR::NativeNew.new(class_type: inst.class_type, result_var: new_result, args: new_args)

        when HIR::NativeFieldGet
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_object = transform_value(inst.object, prefix, param_map)
          HIR::NativeFieldGet.new(object: new_object, field_name: inst.field_name,
                                  class_type: inst.class_type, result_var: new_result)

        when HIR::NativeFieldSet
          new_object = transform_value(inst.object, prefix, param_map)
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::NativeFieldSet.new(object: new_object, field_name: inst.field_name,
                                  value: new_value, class_type: inst.class_type)

        when HIR::NativeMethodCall
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_receiver = transform_value(inst.receiver, prefix, param_map)
          new_args = inst.args.map { |a| transform_value(a, prefix, param_map) }
          HIR::NativeMethodCall.new(
            receiver: new_receiver, method_name: inst.method_name,
            args: new_args, class_type: inst.class_type,
            method_sig: inst.method_sig, owner_class: inst.owner_class,
            result_var: new_result
          )

        when HIR::LoadInstanceVar
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::LoadInstanceVar.new(name: inst.name, type: inst.type, result_var: new_result)

        when HIR::StoreInstanceVar
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::StoreInstanceVar.new(name: inst.name, value: new_value, type: inst.type)

        when HIR::StoreConstant
          new_value = transform_value(inst.value, prefix, param_map)
          HIR::StoreConstant.new(name: inst.name, value: new_value, scope: inst.scope, type: inst.type)

        when HIR::DefinedCheck
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::DefinedCheck.new(check_type: inst.check_type, name: inst.name, type: inst.type, result_var: new_result)

        when HIR::SuperCall
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_args = inst.args.map { |a| transform_value(a, prefix, param_map) }
          HIR::SuperCall.new(args: new_args, type: inst.type, result_var: new_result)

        when HIR::ProcNew
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_block_def = clone_block_def(inst.block_def, prefix, param_map)
          HIR::ProcNew.new(block_def: new_block_def, result_var: new_result)

        when HIR::ProcCall
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_proc = transform_value(inst.proc_value, prefix, param_map)
          new_args = inst.args.map { |a| transform_value(a, prefix, param_map) }
          HIR::ProcCall.new(proc_value: new_proc, args: new_args, type: inst.type, result_var: new_result)

        when HIR::FiberNew
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_block_def = clone_block_def(inst.block_def, prefix, param_map)
          HIR::FiberNew.new(block_def: new_block_def, result_var: new_result)

        when HIR::FiberResume
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_fiber = transform_value(inst.fiber, prefix, param_map)
          new_args = inst.args.map { |a| transform_value(a, prefix, param_map) }
          HIR::FiberResume.new(fiber: new_fiber, args: new_args, type: inst.type, result_var: new_result)

        when HIR::FiberYield
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_args = inst.args.map { |a| transform_value(a, prefix, param_map) }
          HIR::FiberYield.new(args: new_args, type: inst.type, result_var: new_result)

        when HIR::FiberAlive
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_fiber = transform_value(inst.fiber, prefix, param_map)
          HIR::FiberAlive.new(fiber: new_fiber, result_var: new_result)

        when HIR::FiberCurrent
          new_result = inst.result_var ? prefix + inst.result_var : nil
          HIR::FiberCurrent.new(result_var: new_result)

        when HIR::MultiWriteExtract
          new_result = inst.result_var ? prefix + inst.result_var : nil
          new_array = transform_value(inst.array, prefix, param_map)
          HIR::MultiWriteExtract.new(array: new_array, index: inst.index, type: inst.type, result_var: new_result)

        else
          # For other instructions, just return as-is with renamed result
          inst
        end
      end

      def transform_value(value, prefix, param_map)
        case value
        when HIR::LoadLocal
          if param_map.key?(value.var.name)
            param_map[value.var.name]
          else
            new_var = HIR::LocalVar.new(
              name: prefix + value.var.name,
              type: value.var.type
            )
            HIR::LoadLocal.new(var: new_var, type: value.type, result_var: nil)
          end
        when HIR::StringLit
          # Clone literal with new result_var (don't convert to LoadLocal reference)
          new_result = value.result_var ? prefix + value.result_var : nil
          HIR::StringLit.new(value: value.value, result_var: new_result)
        when HIR::IntegerLit
          new_result = value.result_var ? prefix + value.result_var : nil
          HIR::IntegerLit.new(value: value.value, result_var: new_result)
        when HIR::FloatLit
          new_result = value.result_var ? prefix + value.result_var : nil
          HIR::FloatLit.new(value: value.value, result_var: new_result)
        when HIR::BoolLit
          new_result = value.result_var ? prefix + value.result_var : nil
          HIR::BoolLit.new(value: value.value, result_var: new_result)
        when HIR::SymbolLit
          new_result = value.result_var ? prefix + value.result_var : nil
          HIR::SymbolLit.new(value: value.value, result_var: new_result)
        when HIR::NilLit
          new_result = value.result_var ? prefix + value.result_var : nil
          HIR::NilLit.new(result_var: new_result)
        when HIR::Instruction
          if value.result_var
            # Create a LoadLocal to reference the renamed variable
            new_var = HIR::LocalVar.new(
              name: prefix + value.result_var,
              type: value.type
            )
            HIR::LoadLocal.new(var: new_var, type: value.type, result_var: nil)
          else
            value
          end
        when String
          # Variable name reference - create a LoadLocal
          var_name = if param_map.key?(value)
                       # If it's a parameter, use the argument directly
                       return param_map[value]
                     else
                       prefix + value
                     end
          new_var = HIR::LocalVar.new(name: var_name, type: TypeChecker::Types::UNTYPED)
          HIR::LoadLocal.new(var: new_var, type: TypeChecker::Types::UNTYPED, result_var: nil)
        else
          value
        end
      end

      # Deep-clone a BlockDef, renaming captured (non-block-local) variables.
      # Block parameters are NOT renamed (they are local to the closure).
      def clone_block_def(block_def, prefix, param_map)
        return block_def unless block_def

        block_param_names = Set.new(block_def.params.map { |p| p.name.to_s })

        new_body = block_def.body.map do |bb|
          if bb.respond_to?(:instructions)
            new_bb = HIR::BasicBlock.new(label: bb.label)
            bb.instructions.each do |bi|
              new_inst = clone_block_instruction(bi, prefix, param_map, block_param_names)
              new_bb.add_instruction(new_inst) if new_inst
            end
            new_bb.set_terminator(bb.terminator) if bb.terminator
            new_bb
          else
            clone_block_instruction(bb, prefix, param_map, block_param_names)
          end
        end

        HIR::BlockDef.new(
          params: block_def.params,
          body: new_body,
          captures: block_def.captures,
          is_lambda: block_def.is_lambda
        )
      end

      # Clone a single instruction inside a block body, renaming captured vars.
      def clone_block_instruction(inst, prefix, param_map, block_param_names)
        case inst
        when HIR::LoadLocal
          var_name = inst.var.name.to_s
          if block_param_names.include?(var_name)
            # Block-local parameter: don't rename
            inst
          else
            # Captured variable: rename with prefix
            new_var = HIR::LocalVar.new(
              name: prefix + var_name,
              type: inst.var.type
            )
            HIR::LoadLocal.new(var: new_var, type: inst.type, result_var: inst.result_var)
          end
        when HIR::StoreLocal
          var_name = inst.var.name.to_s
          new_value = clone_block_value(inst.value, prefix, param_map, block_param_names)
          if block_param_names.include?(var_name)
            HIR::StoreLocal.new(var: inst.var, value: new_value, type: inst.type)
          else
            new_var = HIR::LocalVar.new(name: prefix + var_name, type: inst.var.type)
            HIR::StoreLocal.new(var: new_var, value: new_value, type: inst.type)
          end
        when HIR::Call
          new_receiver = clone_block_value(inst.receiver, prefix, param_map, block_param_names)
          new_args = inst.args.map { |a| clone_block_value(a, prefix, param_map, block_param_names) }
          HIR::Call.new(
            receiver: new_receiver, method_name: inst.method_name,
            args: new_args, block: inst.block,
            type: inst.type, result_var: inst.result_var
          )
        else
          # Other instructions: return as-is (literals, etc.)
          inst
        end
      end

      # Clone a value reference inside a block, renaming captured variables.
      def clone_block_value(value, prefix, param_map, block_param_names)
        case value
        when HIR::LoadLocal
          var_name = value.var.name.to_s
          if block_param_names.include?(var_name)
            value
          else
            new_var = HIR::LocalVar.new(name: prefix + var_name, type: value.var.type)
            HIR::LoadLocal.new(var: new_var, type: value.type, result_var: nil)
          end
        else
          value
        end
      end
    end
  end
end
