# frozen_string_literal: true

module Konpeito
  module Codegen
    # Optimizes loops in HIR by:
    # 1. Detecting natural loop structures (while/until)
    # 2. Hoisting loop-invariant instructions to a preheader block
    # 3. Recognizing known-pure method calls that can be safely moved
    #
    # This complements LLVM's opt passes which cannot optimize opaque
    # rb_funcallv calls. HIR-level LICM can hoist calls like .length/.size
    # that we know are side-effect-free.
    class LoopOptimizer
      # Methods known to be pure (no side effects, same result for same args)
      PURE_METHODS = Set.new(%i[
        length size count frozen? nil? empty?
        first last class is_a? kind_of? instance_of?
        equal? respond_to? object_id hash
        abs ceil floor round truncate
        even? odd? zero? positive? negative?
        integer? float? finite? infinite? nan?
        to_i to_f to_r to_c
        min max minmax
        ascii_only? encoding bytesize
        key? has_key? include? member?
        keys values
      ]).freeze

      attr_reader :hoisted_count

      def initialize(hir_program)
        @hir_program = hir_program
        @hoisted_count = 0
      end

      def optimize
        @hir_program.functions.each do |func|
          optimize_function(func)
        end
      end

      private

      # Represents a natural loop in the CFG
      LoopInfo = Struct.new(:header, :body_blocks, :exit_block, :preheader_source, keyword_init: true)

      def optimize_function(func)
        block_map = build_block_map(func)
        loops = detect_loops(func, block_map)

        loops.each do |loop_info|
          hoist_invariants(func, loop_info, block_map)
        end
      end

      # Build a map from block label to BasicBlock
      def build_block_map(func)
        map = {}
        func.body.each { |block| map[block.label] = block }
        map
      end

      # Detect natural loops by finding back edges (Jump from body → cond)
      def detect_loops(func, block_map)
        loops = []

        func.body.each_with_index do |block, idx|
          # Look for the pattern:
          #   block_before → Jump(while_cond)
          #   while_cond → Branch(while_body, while_exit)
          #   while_body → Jump(while_cond)  [back edge]
          next unless block.label =~ /^(while|until)_cond/

          cond_block = block
          term = cond_block.terminator
          next unless term.is_a?(HIR::Branch)

          # Determine body and exit based on loop type
          if cond_block.label.start_with?("while_cond")
            body_label = term.then_block
            exit_label = term.else_block
          else # until_cond - condition is inverted
            body_label = term.else_block
            exit_label = term.then_block
          end

          body_block = block_map[body_label]
          next unless body_block

          # Verify back edge exists (body → cond)
          back_edge = has_back_edge?(body_block, cond_block.label, block_map)
          next unless back_edge

          # Find the block that jumps to cond (preheader source)
          preheader = find_preheader_source(func, cond_block.label, body_label, block_map)

          # Collect all blocks that form the loop body
          body_blocks = collect_loop_body_blocks(cond_block.label, body_label, block_map)

          loops << LoopInfo.new(
            header: cond_block,
            body_blocks: body_blocks,
            exit_block: block_map[exit_label],
            preheader_source: preheader
          )
        end

        loops
      end

      # Check if a block (or any successor within the loop) has a back edge to header
      def has_back_edge?(block, header_label, block_map)
        return true if block.terminator.is_a?(HIR::Jump) && block.terminator.target == header_label
        if block.terminator.is_a?(HIR::Branch)
          return true if block.terminator.then_block == header_label
          return true if block.terminator.else_block == header_label
        end
        false
      end

      # Find the block that jumps to the loop header (not from within the loop)
      def find_preheader_source(func, header_label, body_label, block_map)
        func.body.each do |block|
          next if block.label == body_label
          next if block.label == header_label
          next if block.label =~ /^(while|until)_body/ && block.terminator.is_a?(HIR::Jump) && block.terminator.target == header_label

          if block.terminator.is_a?(HIR::Jump) && block.terminator.target == header_label
            return block
          end
        end
        nil
      end

      # Collect all basic blocks that are part of the loop body
      def collect_loop_body_blocks(header_label, body_label, block_map)
        body_block = block_map[body_label]
        return [body_block] unless body_block

        # Simple: just return the body block for now
        # For nested structures (if/else inside loop), we'd need to trace all reachable blocks
        # that eventually jump back to the header
        blocks = [body_block]
        visited = Set.new([header_label, body_label])

        # BFS to find all blocks within the loop
        queue = []
        term = body_block.terminator
        if term.is_a?(HIR::Branch)
          queue << term.then_block unless visited.include?(term.then_block)
          queue << term.else_block unless visited.include?(term.else_block)
        end

        while (label = queue.shift)
          next if visited.include?(label)
          visited << label

          block = block_map[label]
          next unless block

          # Check if this block is within the loop (eventually reaches header)
          if block_reaches_header?(block, header_label, block_map, Set.new)
            blocks << block
            term = block.terminator
            if term.is_a?(HIR::Jump)
              queue << term.target unless visited.include?(term.target)
            elsif term.is_a?(HIR::Branch)
              queue << term.then_block unless visited.include?(term.then_block)
              queue << term.else_block unless visited.include?(term.else_block)
            end
          end
        end

        blocks
      end

      # Check if a block can reach the loop header (part of the loop)
      def block_reaches_header?(block, header_label, block_map, visited)
        return false if visited.include?(block.label)
        visited << block.label

        term = block.terminator
        return false unless term

        if term.is_a?(HIR::Jump)
          return true if term.target == header_label
          next_block = block_map[term.target]
          return next_block && block_reaches_header?(next_block, header_label, block_map, visited)
        elsif term.is_a?(HIR::Branch)
          return true if term.then_block == header_label || term.else_block == header_label
          then_block = block_map[term.then_block]
          else_block = block_map[term.else_block]
          (then_block && block_reaches_header?(then_block, header_label, block_map, visited)) ||
            (else_block && block_reaches_header?(else_block, header_label, block_map, visited))
        else
          false
        end
      end

      # Hoist loop-invariant instructions from loop body to preheader
      def hoist_invariants(func, loop_info, block_map)
        return unless loop_info.preheader_source

        # Collect variables modified inside the loop (cond + body blocks)
        modified_vars = collect_modified_vars(loop_info)

        # Collect variables used in the loop condition
        cond_vars = collect_referenced_vars_in_block(loop_info.header)

        # Find invariant instructions in the loop condition block
        # (most common: arr.length in `while i < arr.length`)
        invariants_from_cond = find_invariant_instructions(
          loop_info.header, modified_vars, loop_info
        )

        # Find invariant instructions in body blocks
        invariants_from_body = []
        loop_info.body_blocks.each do |body_block|
          invariants_from_body.concat(
            find_invariant_instructions(body_block, modified_vars, loop_info)
          )
        end

        all_invariants = invariants_from_cond + invariants_from_body
        return if all_invariants.empty?

        # Move invariant instructions to the preheader
        preheader = loop_info.preheader_source
        all_invariants.each do |inv|
          source_block = inv[:block]
          inst = inv[:instruction]

          # Remove from source block
          source_block.instructions.delete(inst)

          # Add to preheader (before terminator, which is conceptually at the end)
          preheader.instructions << inst

          @hoisted_count += 1
        end
      end

      # Collect all variables that are written to inside the loop
      def collect_modified_vars(loop_info)
        modified = Set.new

        all_blocks = [loop_info.header] + loop_info.body_blocks
        all_blocks.each do |block|
          block.instructions.each do |inst|
            case inst
            when HIR::StoreLocal
              modified << inst.var.to_s
            when HIR::StoreInstanceVar
              modified << inst.name.to_s
            when HIR::StoreClassVar
              modified << inst.name.to_s
            end

            # Instructions that produce results are also "modified"
            if inst.respond_to?(:result_var) && inst.result_var
              modified << inst.result_var.to_s
            end
          end
        end

        modified
      end

      # Collect variables referenced in a block's instructions
      def collect_referenced_vars_in_block(block)
        vars = Set.new
        block.instructions.each do |inst|
          collect_vars_from_instruction(inst, vars)
        end
        # Also check terminator condition
        if block.terminator.is_a?(HIR::Branch) && block.terminator.condition
          collect_vars_from_instruction(block.terminator.condition, vars)
        end
        vars
      end

      # Collect variable references from an instruction
      def collect_vars_from_instruction(inst, vars)
        case inst
        when HIR::LoadLocal
          vars << inst.var.to_s
        when HIR::LoadInstanceVar
          vars << inst.name.to_s
        when HIR::Call
          collect_vars_from_instruction(inst.receiver, vars) if inst.receiver
          inst.args.each { |arg| collect_vars_from_instruction(arg, vars) }
        end
      end

      # Find instructions that are invariant (don't depend on loop-modified vars)
      def find_invariant_instructions(block, modified_vars, loop_info)
        invariants = []

        block.instructions.each do |inst|
          next unless invariant_instruction?(inst, modified_vars, loop_info)

          invariants << { block: block, instruction: inst }
        end

        invariants
      end

      # Check if an instruction is loop-invariant
      def invariant_instruction?(inst, modified_vars, loop_info)
        case inst
        when HIR::Call
          # Only hoist calls to known-pure methods
          return false unless PURE_METHODS.include?(inst.method_name.to_sym)

          # Check that the receiver doesn't depend on loop-modified vars
          return false unless operand_invariant?(inst.receiver, modified_vars)

          # Check that all args don't depend on loop-modified vars
          return false unless inst.args.all? { |arg| operand_invariant?(arg, modified_vars) }

          # Don't hoist if the result_var is used as a store target in the loop
          # (it shouldn't be, but safety check)
          if inst.result_var
            return false if modified_vars.include?(inst.result_var.to_s)
          end

          true

        when HIR::Literal, HIR::IntegerLit, HIR::FloatLit, HIR::StringLit,
             HIR::SymbolLit, HIR::NilLit, HIR::BoolLit
          # Literals are always invariant, but they're cheap to compute
          # Only hoist if they have a result_var that's used in the loop
          false  # Not worth hoisting literals

        else
          false
        end
      end

      # Check if an operand (receiver/arg) doesn't depend on loop-modified vars
      def operand_invariant?(operand, modified_vars)
        case operand
        when HIR::LoadLocal
          !modified_vars.include?(operand.var.to_s)
        when HIR::LoadInstanceVar
          !modified_vars.include?(operand.name.to_s)
        when HIR::SelfRef
          true  # self doesn't change
        when HIR::Literal, HIR::IntegerLit, HIR::FloatLit,
             HIR::StringLit, HIR::SymbolLit, HIR::NilLit, HIR::BoolLit
          true  # Literals are invariant
        when HIR::Call
          # Nested call: check recursively
          PURE_METHODS.include?(operand.method_name.to_sym) &&
            operand_invariant?(operand.receiver, modified_vars) &&
            operand.args.all? { |arg| operand_invariant?(arg, modified_vars) }
        else
          false  # Unknown operand types are assumed variant
        end
      end
    end
  end
end
