# frozen_string_literal: true

module Konpeito
  module Codegen
    # Profiling instrumentation for LLVM IR code generation.
    # Inserts function entry/exit probes that call into C runtime
    # for collecting call counts and execution time.
    class Profiler
      attr_reader :function_ids

      def initialize(llvm_module, builder)
        @mod = llvm_module
        @builder = builder
        @function_ids = {}  # function_name => unique_id
        @next_id = 0

        declare_runtime_functions
      end

      # Declare external C runtime functions for profiling
      def declare_runtime_functions
        ptr_type = LLVM::Pointer(LLVM::Int8)

        # void konpeito_profile_enter(int func_id, const char* func_name)
        @profile_enter = @mod.functions.add(
          "konpeito_profile_enter",
          [LLVM::Int32, ptr_type],
          LLVM.Void
        )

        # void konpeito_profile_exit(int func_id)
        @profile_exit = @mod.functions.add(
          "konpeito_profile_exit",
          [LLVM::Int32],
          LLVM.Void
        )

        # void konpeito_profile_init(int num_functions, const char* output_path)
        @profile_init = @mod.functions.add(
          "konpeito_profile_init",
          [LLVM::Int32, ptr_type],
          LLVM.Void
        )

        # void konpeito_profile_finalize(void)
        @profile_finalize = @mod.functions.add(
          "konpeito_profile_finalize",
          [],
          LLVM.Void
        )
      end

      # Register a function for profiling and return its ID
      def register_function(name)
        return @function_ids[name] if @function_ids.key?(name)

        id = @next_id
        @next_id += 1
        @function_ids[name] = id
        id
      end

      # Insert entry probe at function start
      # Call this right after positioning builder at entry block
      def insert_entry_probe(function_name)
        func_id = register_function(function_name)

        # Use global_string_pointer to create a string constant and get its pointer
        func_name_ptr = @builder.global_string_pointer(function_name)

        @builder.call(@profile_enter, LLVM::Int32.from_i(func_id), func_name_ptr)
      end

      # Insert exit probe before return instruction
      # Call this before generating return instruction
      def insert_exit_probe(function_name)
        func_id = @function_ids[function_name]
        return unless func_id

        @builder.call(@profile_exit, LLVM::Int32.from_i(func_id))
      end

      # Generate initialization call (called once at module init)
      def generate_init_call(builder, output_path)
        num_funcs = LLVM::Int32.from_i(@function_ids.size)

        # Use global_string_pointer to create a string constant and get its pointer
        path_ptr = builder.global_string_pointer(output_path)

        builder.call(@profile_init, num_funcs, path_ptr)
      end

      # Get total number of registered functions
      def num_functions
        @function_ids.size
      end
    end
  end
end
