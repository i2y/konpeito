# frozen_string_literal: true

require "set"
require_relative "builtin_methods"

module Konpeito
  module Codegen
    # Generates LLVM IR from HIR
    class LLVMGenerator
      attr_reader :mod, :builder, :hir_program

      def initialize(module_name: "konpeito", monomorphizer: nil, rbs_loader: nil, debug: false, profile: false, source_file: nil)
        begin
          require "llvm/core"
          require "llvm/execution_engine"
          require "llvm/transforms/scalar"
        rescue LoadError
          raise LoadError,
            "ruby-llvm gem is required for native compilation (--target native).\n" \
            "Install with: gem install ruby-llvm\n" \
            "For JVM-only usage, use: konpeito build --target jvm"
        end

        LLVM.init_jit

        @mod = LLVM::Module.new(module_name)
        @builder = LLVM::Builder.new
        @functions = {}
        @blocks = {}
        @variables = {}           # For SSA values (temps, etc.)
        @variable_allocas = {}    # For local variables (alloca-based for loop safety)
        @variable_types = {}      # Track unboxed types: :i64, :double, or :value
        @hir_program = nil
        @monomorphizer = monomorphizer
        @rbs_loader = rbs_loader
        @current_hir_func = nil   # Current HIR function for type lookup
        @debug = debug
        @profile = profile
        @source_file = source_file
        @dibuilder = nil          # DIBuilder for debug info
        @profiler = nil           # Profiler for instrumentation
        @variadic_functions = {}  # Track functions with **kwargs or *args
        @comparison_result_vars = Set.new  # Track variables holding comparison results (0/1 boolean)

        # Register all NativeClass types from RBS upfront
        register_native_classes_from_rbs
      end

      # Register all NativeClass types from RBS loader so they're known before generating functions
      def register_native_classes_from_rbs
        return unless @rbs_loader

        @rbs_loader.native_classes.each do |_name, class_type|
          register_native_class_type(class_type)
        end
      end

      attr_reader :profiler, :variadic_functions

      def generate(hir_program)
        @hir_program = hir_program

        # Initialize debug info builder if debug mode is enabled
        if @debug && @source_file
          require_relative "debug_info"
          @dibuilder = DIBuilder.new(@mod)
          @dibuilder.create_compile_unit(
            filename: File.basename(@source_file),
            directory: File.dirname(File.expand_path(@source_file))
          )
        end

        # Initialize profiler if profile mode is enabled
        if @profile
          require_relative "profiler"
          @profiler = Profiler.new(@mod, @builder)
        end

        # Declare external CRuby functions
        declare_cruby_functions

        # Scan HIR to register NativeClassTypes before code generation
        scan_for_native_class_types(hir_program)

        # Generate vtables for classes that use them
        generate_vtables

        # First pass: declare all functions (needed for forward references / monomorphization)
        hir_program.functions.each do |func|
          declare_function(func)
        end

        # Second pass: generate code for each function
        hir_program.functions.each do |func|
          generate_function_body(func)
        end

        # Finalize debug info
        if @dibuilder
          @dibuilder.finalize
        end

        @mod
      end

      # Declare a function (create LLVM function without body)
      def declare_function(hir_func)
        native_class_type = detect_native_class_for_function(hir_func)

        if native_class_type
          declare_native_function(hir_func, native_class_type)
        else
          declare_ruby_function(hir_func)
        end
      end

      # Declare a native function signature
      def declare_native_function(hir_func, native_class_type)
        struct_type = get_or_create_native_class_struct(native_class_type)
        method_sig = native_class_type.methods[hir_func.name.to_sym]

        # Build parameter types: first is struct pointer for self
        param_types = [LLVM::Pointer(struct_type)]

        hir_func.params.each_with_index do |param, i|
          param_type_sym = method_sig&.param_types&.[](i) || :Float64
          llvm_type = case param_type_sym
          when :Int64 then LLVM::Int64
          when :Float64 then LLVM::Double
          else LLVM::Pointer(LLVM::Int8)  # Other NativeClass
          end
          param_types << llvm_type
        end

        # Return type - return struct by value for :Self to avoid use-after-free
        return_type_sym = method_sig&.return_type || :Float64
        return_type = case return_type_sym
        when :Int64 then LLVM::Int64
        when :Float64 then LLVM::Double
        when :Void then LLVM.Void
        when :Self then struct_type  # Return struct by value
        else
          # Another NativeClass - return struct by value
          other_struct = get_or_create_native_class_struct(
            @native_class_type_registry[return_type_sym] || native_class_type
          )
          other_struct
        end

        mangled = mangle_name(hir_func)
        func = @mod.functions.add(mangled, param_types, return_type)
        @functions[hir_func.name] = func
        @functions[mangled] = func
        @native_method_funcs ||= {}
        @native_method_funcs[mangled] = func
      end

      # Declare a standard Ruby function signature
      def declare_ruby_function(hir_func)
        # Count regular parameters (non-keyword, non-keyword_rest, non-rest)
        regular_params = hir_func.params.reject { |p| p.keyword || p.keyword_rest || p.rest }
        keyword_params = hir_func.params.select(&:keyword)
        keyword_rest_param = hir_func.params.find(&:keyword_rest)
        rest_param = hir_func.params.find(&:rest)

        mangled = mangle_name(hir_func)

        # Use variadic signature for functions with:
        # - **kwargs only (no regular params)
        # - *args parameter
        needs_variadic = (keyword_rest_param && regular_params.empty? && keyword_params.empty?) || rest_param

        if needs_variadic
          # Variadic signature: VALUE func(int argc, VALUE *argv, VALUE self)
          param_types = [LLVM::Int32, LLVM::Pointer(value_type), value_type]
          @variadic_functions[mangled] = {
            keyword_rest: keyword_rest_param ? keyword_rest_param.name : nil,
            rest: rest_param ? rest_param.name : nil,
            regular_count: regular_params.size,
            keyword_count: keyword_params.size
          }
        else
          # Standard signature: VALUE func(VALUE self, VALUE arg1, ...)
          # +1 for self, +1 for kwargs hash if has keyword params or keyword_rest
          num_params = regular_params.size + 1
          num_params += 1 if keyword_params.any? || keyword_rest_param
          param_types = [value_type] * num_params
        end

        return_type = value_type
        func = @mod.functions.add(mangled, param_types, return_type)
        @functions[hir_func.name] = func
        @functions[mangled] = func
      end

      # Scan HIR to find and register NativeClassTypes
      def scan_for_native_class_types(hir_program)
        @native_class_type_registry ||= {}

        hir_program.functions.each do |func|
          func.body.each do |block|
            block.instructions.each do |inst|
              case inst
              when HIR::NativeNew
                register_native_class_type(inst.class_type)
              when HIR::NativeMethodCall
                register_native_class_type(inst.class_type)
                register_native_class_type(inst.owner_class) if inst.owner_class
              when HIR::NativeFieldGet, HIR::NativeFieldSet
                register_native_class_type(inst.class_type)
              when HIR::NativeArrayAlloc
                if inst.element_type.is_a?(TypeChecker::Types::NativeClassType)
                  register_native_class_type(inst.element_type)
                end
              end
            end
          end
        end
      end

      # Auto-generate NativeClassType from HM-inferred ivar types (RBS-free classes)
      def auto_generate_native_class_types(hir_program)
        hir_program.classes.each do |class_def|
          class_name_sym = class_def.name.to_s.to_sym
          next if @native_class_type_registry[class_name_sym]
          next if class_def.instance_var_types.empty?

          fields = {}
          class_def.instance_var_types.each do |fname, ftype|
            fields[fname.to_sym] = ftype.to_sym
          end
          next if fields.empty?

          native_type = TypeChecker::Types::NativeClassType.new(
            class_def.name.to_s, fields, {},
            superclass: class_def.superclass
          )
          register_native_class_type(native_type)
        end
      end

      # Generate vtables for all classes that use vtable dispatch
      def generate_vtables
        @vtables ||= {}
        @native_class_type_registry ||= {}

        @native_class_type_registry.each do |class_name, class_type|
          next unless class_type.uses_vtable?(@native_class_type_registry)

          generate_vtable_for_class(class_type)
        end
      end

      # Generate vtable for a single class
      def generate_vtable_for_class(class_type)
        @vtables ||= {}
        return @vtables[class_type.name] if @vtables[class_type.name]

        vtable_entries = class_type.vtable_methods(@native_class_type_registry)
        return nil if vtable_entries.empty?

        # Create vtable type: array of function pointers
        func_ptr_type = LLVM::Pointer(LLVM::Int8)
        vtable_type = LLVM::Type.struct([func_ptr_type] * vtable_entries.size, false, "VTable_#{class_type.name}")

        # Create initializer values - we'll populate these when functions are generated
        # For now, create null pointers that will be filled in later
        @vtable_entries ||= {}
        @vtable_entries[class_type.name] = vtable_entries

        # Create the vtable global (initially with null pointers, updated later)
        vtable_global = @mod.globals.add(vtable_type, "vtable_#{class_type.name}") do |var|
          var.linkage = :internal
          # Initialize with null pointers - will be updated in finalize_vtables
        end

        @vtables[class_type.name] = {
          global: vtable_global,
          type: vtable_type,
          entries: vtable_entries
        }

        vtable_global
      end

      # Get the vtable global for a class (creates if needed)
      def get_vtable_for_class(class_type)
        @vtables ||= {}
        @vtables[class_type.name]
      end

      # Generate a vtable-based virtual method call
      # @param class_type [NativeClassType] The static type of the receiver
      # @param method_name [Symbol] Method name to call
      # @param method_sig [NativeMethodType] Method signature
      # @param receiver_ptr [LLVM::Value] Pointer to the receiver object
      # @param call_args [Array<LLVM::Value>] All call arguments including receiver
      def generate_vtable_call(class_type, method_name, method_sig, receiver_ptr, call_args)
        # Get vtable index for this method
        vtable_idx = class_type.vtable_index(method_name, @native_class_type_registry)
        return @qnil unless vtable_idx

        # Load vptr from object (first field)
        llvm_struct = get_or_create_native_class_struct(class_type)
        vptr_field_ptr = @builder.struct_gep2(llvm_struct, receiver_ptr, 0, "vptr_field_ptr")
        vptr = @builder.load2(LLVM::Pointer(LLVM::Int8), vptr_field_ptr, "vptr")

        # Build function type for the method
        struct_type = get_or_create_native_class_struct(class_type)
        param_types = [LLVM::Pointer(struct_type)]  # self pointer

        method_sig.param_types.each do |param_type|
          llvm_type = case param_type
          when :Int64 then LLVM::Int64
          when :Float64 then LLVM::Double
          else LLVM::Pointer(LLVM::Int8)
          end
          param_types << llvm_type
        end

        # Return type - return struct by value for :Self
        return_type = case method_sig.return_type
        when :Int64 then LLVM::Int64
        when :Float64 then LLVM::Double
        when :Void then LLVM.Void
        when :Self then struct_type
        else
          other_struct = get_or_create_native_class_struct(
            @native_class_type_registry[method_sig.return_type] || class_type
          )
          other_struct
        end

        func_type = LLVM::Type.function(param_types, return_type)

        # Cast vptr to vtable pointer type (array of function pointers)
        func_ptr_type = LLVM::Pointer(func_type)
        vtable_ptr_type = LLVM::Pointer(func_ptr_type)
        typed_vptr = @builder.bit_cast(vptr, vtable_ptr_type, "typed_vptr")

        # Index into vtable to get function pointer
        vtable_entry_ptr = @builder.gep(typed_vptr, [LLVM::Int32.from_i(vtable_idx)], "vtable_entry_ptr")
        func_ptr = @builder.load2(func_ptr_type, vtable_entry_ptr, "func_ptr")

        # Indirect call through function pointer
        @builder.call(func_type, func_ptr, *call_args, "#{method_name}_vcall")
      end

      def to_ir
        @mod.to_s
      end

      def write_bitcode(filename)
        @mod.write_bitcode(filename)
      end

      private

      # Type helpers
      def value_type
        # VALUE is typically a pointer-sized integer (uintptr_t)
        LLVM::Int64
      end

      def id_type
        # ID is typically uint32 or uint64
        LLVM::Int64
      end

      def int_type
        LLVM::Int64
      end

      def ptr_type
        LLVM::Pointer(LLVM::Int8)
      end

      def bool_type
        LLVM::Int1
      end

      # Declare CRuby API functions
      def declare_cruby_functions
        # rb_intern - convert string to Symbol ID
        @rb_intern = @mod.functions.add("rb_intern", [ptr_type], id_type)

        # rb_funcall - call a method on an object
        # VALUE rb_funcall(VALUE recv, ID mid, int argc, ...)
        # We'll use rb_funcallv for variadic args: VALUE rb_funcallv(VALUE recv, ID mid, int argc, VALUE *argv)
        @rb_funcallv = @mod.functions.add("rb_funcallv", [value_type, id_type, LLVM::Int32, LLVM::Pointer(value_type)], value_type)

        # rb_int2inum - convert C int to Ruby Integer
        @rb_int2inum = @mod.functions.add("rb_int2inum", [int_type], value_type) do |fn|
          fn.linkage = :external
        end

        # rb_num2long - convert Ruby Integer to C long
        @rb_num2long = @mod.functions.add("rb_num2long", [value_type], int_type)

        # rb_num2dbl - convert Ruby Numeric to C double
        @rb_num2dbl = @mod.functions.add("rb_num2dbl", [value_type], LLVM::Double)

        # rb_float_new - create Ruby Float from C double
        @rb_float_new = @mod.functions.add("rb_float_new", [LLVM::Double], value_type)

        # rb_str_new - create Ruby String from ptr and length
        # VALUE rb_str_new(const char *ptr, long len)
        @rb_str_new = @mod.functions.add("rb_str_new", [ptr_type, LLVM::Int64], value_type)

        # rb_utf8_str_new - create Ruby String from ptr and length with UTF-8 encoding
        # VALUE rb_utf8_str_new(const char *ptr, long len)
        @rb_utf8_str_new = @mod.functions.add("rb_utf8_str_new", [ptr_type, LLVM::Int64], value_type)

        # rb_str_new_cstr - create Ruby String from C string
        @rb_str_new_cstr = @mod.functions.add("rb_str_new_cstr", [ptr_type], value_type)

        # rb_str_dup - duplicate Ruby String
        @rb_str_dup = @mod.functions.add("rb_str_dup", [value_type], value_type)

        # rb_str_hash - get hash value of Ruby String
        @rb_str_hash = @mod.functions.add("rb_str_hash", [value_type], value_type)

        # rb_str_concat - append string (mutating)
        @rb_str_concat = @mod.functions.add("rb_str_concat", [value_type, value_type], value_type)

        # rb_str_buf_new - create string buffer with capacity
        # VALUE rb_str_buf_new(long capa)
        @rb_str_buf_new = @mod.functions.add("rb_str_buf_new", [LLVM::Int64], value_type)

        # rb_str_cat - append C string with length
        # VALUE rb_str_cat(VALUE str, const char *ptr, long len)
        @rb_str_cat = @mod.functions.add("rb_str_cat", [value_type, ptr_type, LLVM::Int64], value_type)

        # rb_str_buf_append - append VALUE string to buffer
        # VALUE rb_str_buf_append(VALUE str, VALUE str2)
        @rb_str_buf_append = @mod.functions.add("rb_str_buf_append", [value_type, value_type], value_type)

        # rb_str_length - get string length
        # VALUE rb_str_length(VALUE str) - returns Fixnum
        @rb_str_length = @mod.functions.add("rb_str_length", [value_type], value_type)

        # rb_str_equal - compare strings (=== inline optimization)
        @rb_str_equal = @mod.functions.add("rb_str_equal", [value_type, value_type], value_type)

        # rb_string_value_cstr - get C string from Ruby String
        # char *rb_string_value_cstr(volatile VALUE *ptr)
        @rb_string_value_cstr = @mod.functions.add("rb_string_value_cstr", [LLVM::Pointer(value_type)], ptr_type)

        # rb_id2sym - convert ID to Symbol
        @rb_id2sym = @mod.functions.add("rb_id2sym", [id_type], value_type)

        # rb_reg_new_str - create Regexp from string pattern with options
        # VALUE rb_reg_new_str(VALUE str, int options)
        @rb_reg_new_str = @mod.functions.add("rb_reg_new_str", [value_type, int_type], value_type)

        # rb_ary_new_capa - create Array with capacity
        @rb_ary_new_capa = @mod.functions.add("rb_ary_new_capa", [int_type], value_type)

        # rb_ary_push - push element to Array
        @rb_ary_push = @mod.functions.add("rb_ary_push", [value_type, value_type], value_type)

        # rb_ary_new_from_values - create Array from VALUE array (*args support)
        @rb_ary_new_from_values = @mod.functions.add("rb_ary_new_from_values",
          [LLVM::Int64, LLVM::Pointer(value_type)], value_type)

        # rb_hash_new - create new Hash
        @rb_hash_new = @mod.functions.add("rb_hash_new", [], value_type)

        # rb_hash_aset - set Hash key-value
        @rb_hash_aset = @mod.functions.add("rb_hash_aset", [value_type, value_type, value_type], value_type)

        # rb_hash_lookup2 - lookup Hash key with default value (for keyword arguments)
        # VALUE rb_hash_lookup2(VALUE hash, VALUE key, VALUE def)
        @rb_hash_lookup2 = @mod.functions.add("rb_hash_lookup2", [value_type, value_type, value_type], value_type)

        # rb_ary_entry - get Array element at index (more efficient than rb_ary_aref for single index)
        # VALUE rb_ary_entry(VALUE ary, long offset)
        @rb_ary_entry = @mod.functions.add("rb_ary_entry", [value_type, int_type], value_type)

        # rb_array_len - get Array length
        # long rb_array_len(VALUE ary)
        @rb_array_len = @mod.functions.add("rb_array_len", [value_type], int_type)

        # rb_ary_store - set Array element at index
        # void rb_ary_store(VALUE ary, long idx, VALUE val)
        @rb_ary_store = @mod.functions.add("rb_ary_store", [value_type, int_type, value_type], LLVM.Void)

        # rb_ary_new - create new empty Array (using rb_ary_new_capa with 0 capacity)
        # VALUE rb_ary_new(void)
        @rb_ary_new = @mod.functions.add("rb_ary_new", [], value_type)

        # rb_ary_subseq - get subarray (for rest patterns)
        # VALUE rb_ary_subseq(VALUE ary, long beg, long len)
        @rb_ary_subseq = @mod.functions.add("rb_ary_subseq", [value_type, int_type, int_type], value_type)

        # rb_ary_concat - concatenate two arrays
        # VALUE rb_ary_concat(VALUE ary, VALUE other)
        @rb_ary_concat = @mod.functions.add("rb_ary_concat", [value_type, value_type], value_type)

        # rb_apply - call method with args array
        # VALUE rb_apply(VALUE recv, ID mid, VALUE args)
        @rb_apply = @mod.functions.add("rb_apply", [value_type, id_type, value_type], value_type)

        # Array mutation methods
        # VALUE rb_ary_unshift(VALUE ary, VALUE item)
        @rb_ary_unshift = @mod.functions.add("rb_ary_unshift", [value_type, value_type], value_type)
        # VALUE rb_ary_delete(VALUE ary, VALUE item)
        @rb_ary_delete = @mod.functions.add("rb_ary_delete", [value_type, value_type], value_type)
        # VALUE rb_ary_delete_at(VALUE ary, long pos)
        @rb_ary_delete_at = @mod.functions.add("rb_ary_delete_at", [value_type, int_type], value_type)

        # Symbol methods
        # VALUE rb_sym2str(VALUE sym)
        @rb_sym2str = @mod.functions.add("rb_sym2str", [value_type], value_type)

        # Qundef - undefined value (used for keyword arg default detection)
        # In CRuby: Qundef = 52 (0x34)
        @qundef = LLVM::Int64.from_i(52)

        # Qnil, Qtrue, Qfalse are constants
        # In CRuby: Qnil = 8, Qtrue = 20, Qfalse = 0 (may vary by Ruby version)
        # Ruby 4.0 special constants (with USE_FLONUM=1):
        # - Qfalse = 0x00 (0)
        # - Qnil   = 0x04 (4)
        # - Qtrue  = 0x14 (20)
        @qnil = LLVM::Int64.from_i(4)   # Qnil
        @qtrue = LLVM::Int64.from_i(20) # Qtrue
        @qfalse = LLVM::Int64.from_i(0) # Qfalse

        # Class definition functions
        # VALUE rb_define_class(const char *name, VALUE super)
        @rb_define_class = @mod.functions.add("rb_define_class", [ptr_type, value_type], value_type)

        # VALUE rb_define_class_under(VALUE outer, const char *name, VALUE super)
        @rb_define_class_under = @mod.functions.add("rb_define_class_under", [value_type, ptr_type, value_type], value_type)

        # void rb_define_method(VALUE klass, const char *name, VALUE (*func)(...), int argc)
        @rb_define_method = @mod.functions.add("rb_define_method", [value_type, ptr_type, ptr_type, LLVM::Int32], LLVM.Void)

        # Instance variable functions
        # VALUE rb_ivar_get(VALUE obj, ID id)
        @rb_ivar_get = @mod.functions.add("rb_ivar_get", [value_type, id_type], value_type)

        # VALUE rb_ivar_set(VALUE obj, ID id, VALUE val)
        @rb_ivar_set = @mod.functions.add("rb_ivar_set", [value_type, id_type, value_type], value_type)

        # Class variable functions
        # VALUE rb_cvar_get(VALUE klass, ID id)
        @rb_cvar_get = @mod.functions.add("rb_cvar_get", [value_type, id_type], value_type)

        # void rb_cvar_set(VALUE klass, ID id, VALUE val)
        @rb_cvar_set = @mod.functions.add("rb_cvar_set", [value_type, id_type, value_type], LLVM.Void)

        # VALUE rb_class_of(VALUE obj) - get class of object
        @rb_class_of = @mod.functions.add("rb_class_of", [value_type], value_type)

        # Block/Yield functions
        # VALUE rb_yield(VALUE val) - yield with single value
        @rb_yield = @mod.functions.add("rb_yield", [value_type], value_type)

        # VALUE rb_yield_values(int argc, ...) - yield with multiple values (variadic)
        # We'll use rb_yield_values2 instead: VALUE rb_yield_values2(int argc, const VALUE *argv)
        @rb_yield_values2 = @mod.functions.add("rb_yield_values2", [LLVM::Int32, LLVM::Pointer(value_type)], value_type)

        # int rb_block_given_p(void) - check if block is given
        @rb_block_given_p = @mod.functions.add("rb_block_given_p", [], LLVM::Int32)

        # rb_block_call - call method with block callback
        # VALUE rb_block_call(VALUE obj, ID mid, int argc, const VALUE *argv,
        #                     rb_block_call_func_t proc, VALUE data2)
        # Block callback signature: VALUE func(VALUE yielded_arg, VALUE data2, int argc, VALUE *argv, VALUE blockarg)
        block_callback_type = LLVM::Type.function(
          [value_type, value_type, LLVM::Int32, LLVM::Pointer(value_type), value_type],
          value_type)
        @rb_block_call = @mod.functions.add("rb_block_call",
          [value_type, id_type, LLVM::Int32, LLVM::Pointer(value_type),
           LLVM::Pointer(block_callback_type), value_type],
          value_type)

        # Proc functions
        # VALUE rb_proc_new(rb_block_call_func_t func, VALUE val)
        # Creates a Proc object from a C callback function
        proc_callback_type = LLVM::Type.function(
          [value_type, value_type, LLVM::Int32, LLVM::Pointer(value_type), value_type],
          value_type)
        @rb_proc_new = @mod.functions.add("rb_proc_new",
          [LLVM::Pointer(proc_callback_type), value_type],
          value_type)

        # VALUE rb_proc_call(VALUE proc, VALUE args)
        # Calls a Proc with arguments packed in an Array
        @rb_proc_call = @mod.functions.add("rb_proc_call",
          [value_type, value_type],
          value_type)

        # Fiber functions
        # VALUE rb_fiber_new(rb_block_call_func_t func, VALUE obj)
        # Creates a Fiber from a block callback function
        fiber_callback_type = LLVM::Type.function(
          [value_type, value_type, LLVM::Int32, LLVM::Pointer(value_type), value_type],
          value_type)
        @rb_fiber_new = @mod.functions.add("rb_fiber_new",
          [LLVM::Pointer(fiber_callback_type), value_type],
          value_type)

        # VALUE rb_fiber_resume(VALUE fiber, int argc, const VALUE *argv)
        # Resume a fiber with arguments
        @rb_fiber_resume = @mod.functions.add("rb_fiber_resume",
          [value_type, LLVM::Int32, LLVM::Pointer(value_type)],
          value_type)

        # VALUE rb_fiber_yield(int argc, const VALUE *argv)
        # Yield from current fiber
        @rb_fiber_yield = @mod.functions.add("rb_fiber_yield",
          [LLVM::Int32, LLVM::Pointer(value_type)],
          value_type)

        # VALUE rb_fiber_current(void)
        # Get the current fiber
        @rb_fiber_current = @mod.functions.add("rb_fiber_current", [], value_type)

        # VALUE rb_fiber_alive_p(VALUE fiber)
        # Check if fiber is alive
        @rb_fiber_alive_p = @mod.functions.add("rb_fiber_alive_p", [value_type], value_type)

        # Thread functions
        # VALUE rb_thread_create(VALUE (*fn)(void *), void *arg)
        # Creates a Thread from a callback function
        # The callback signature is: VALUE func(void*)
        thread_callback_type = LLVM::Type.function(
          [LLVM::Pointer(LLVM::Int8)],
          value_type)
        @rb_thread_create = @mod.functions.add("rb_thread_create",
          [LLVM::Pointer(thread_callback_type), LLVM::Pointer(LLVM::Int8)],
          value_type)

        # VALUE rb_thread_current(void)
        # Get the current thread
        @rb_thread_current = @mod.functions.add("rb_thread_current", [], value_type)

        # VALUE rb_thread_join(VALUE thread, VALUE limit)
        # Note: This is actually a method call, we use rb_funcallv
        # But we can use Thread#value which has a simpler interface

        # Mutex functions
        # VALUE rb_mutex_new(void)
        @rb_mutex_new = @mod.functions.add("rb_mutex_new", [], value_type)

        # VALUE rb_mutex_lock(VALUE mutex)
        @rb_mutex_lock = @mod.functions.add("rb_mutex_lock", [value_type], value_type)

        # VALUE rb_mutex_unlock(VALUE mutex)
        @rb_mutex_unlock = @mod.functions.add("rb_mutex_unlock", [value_type], value_type)

        # Queue class constant (for rb_funcallv calls)
        @rb_cQueue = @mod.globals.add(value_type, "rb_cQueue") do |var|
          var.linkage = :external
        end

        # Thread class constant
        @rb_cThread = @mod.globals.add(value_type, "rb_cThread") do |var|
          var.linkage = :external
        end

        # Mutex class constant
        @rb_cMutex = @mod.globals.add(value_type, "rb_cMutex") do |var|
          var.linkage = :external
        end

        # Exception handling functions
        # VALUE rb_ensure(VALUE (*b_proc)(VALUE), VALUE data1,
        #                 VALUE (*e_proc)(VALUE), VALUE data2)
        ensure_callback_type = LLVM::Type.function([value_type], value_type)
        @rb_ensure = @mod.functions.add("rb_ensure",
          [LLVM::Pointer(ensure_callback_type), value_type,
           LLVM::Pointer(ensure_callback_type), value_type],
          value_type)

        # VALUE rb_rescue2(VALUE (*b_proc)(VALUE), VALUE data1,
        #                  VALUE (*r_proc)(VALUE, VALUE), VALUE data2,
        #                  ...) - variadic, ends with (VALUE)0
        # MUST be declared as variadic for correct ARM64 calling convention
        rescue_body_type = LLVM::Type.function([value_type], value_type)
        rescue_handler_type = LLVM::Type.function([value_type, value_type], value_type)
        rb_rescue2_type = LLVM::Type.function(
          [LLVM::Pointer(rescue_body_type), value_type,
           LLVM::Pointer(rescue_handler_type), value_type],
          value_type, varargs: true)
        @rb_rescue2 = @mod.functions.add("rb_rescue2", rb_rescue2_type)

        # rb_protect - execute code with exception protection
        # VALUE rb_protect(VALUE (*func)(VALUE), VALUE arg, int *state)
        protect_callback_type = LLVM::Type.function([value_type], value_type)
        @rb_protect = @mod.functions.add("rb_protect",
          [LLVM::Pointer(protect_callback_type), value_type, LLVM::Pointer(LLVM::Int32)],
          value_type)

        # rb_errinfo - get current exception ($!)
        # VALUE rb_errinfo(void)
        @rb_errinfo = @mod.functions.add("rb_errinfo", [], value_type)

        # rb_set_errinfo - clear exception state
        # void rb_set_errinfo(VALUE err)
        @rb_set_errinfo = @mod.functions.add("rb_set_errinfo", [value_type], LLVM.Void)

        # rb_jump_tag - re-raise exception with saved state
        # void rb_jump_tag(int state) __attribute__((noreturn))
        @rb_jump_tag = @mod.functions.add("rb_jump_tag", [LLVM::Int32], LLVM.Void)

        # VALUE rb_raise(VALUE exc, const char *fmt, ...)
        @rb_raise = @mod.functions.add("rb_raise", [value_type, ptr_type], LLVM.Void)

        # rb_eStandardError global
        @rb_eStandardError = @mod.globals.add(value_type, "rb_eStandardError") do |var|
          var.linkage = :external
        end

        # rb_eRuntimeError global
        @rb_eRuntimeError = @mod.globals.add(value_type, "rb_eRuntimeError") do |var|
          var.linkage = :external
        end

        # rb_eArgError global (CRuby's ArgumentError class)
        @rb_eArgumentError = @mod.globals.add(value_type, "rb_eArgError") do |var|
          var.linkage = :external
        end

        # rb_cObject global
        @rb_cObject = @mod.globals.add(value_type, "rb_cObject") do |var|
          var.linkage = :external
        end

        # rb_const_get - lookup constant under a module
        # VALUE rb_const_get(VALUE module, ID name)
        @rb_const_get = @mod.functions.add("rb_const_get", [value_type, id_type], value_type)

        # Range, Global vars, Super
        @rb_range_new = @mod.functions.add("rb_range_new", [value_type, value_type, LLVM::Int32], value_type)
        @rb_gv_get = @mod.functions.add("rb_gv_get", [ptr_type], value_type)
        @rb_gv_set = @mod.functions.add("rb_gv_set", [ptr_type, value_type], value_type)
        @rb_call_super = @mod.functions.add("rb_call_super", [LLVM::Int32, LLVM::Pointer(value_type)], value_type)

        # rb_const_set - define a constant under a module
        # void rb_const_set(VALUE module, ID name, VALUE value)
        @rb_const_set = @mod.functions.add("rb_const_set", [value_type, id_type, value_type], LLVM.Void)

        # rb_obj_is_kind_of - check if object is instance of class (for union type dispatch)
        # VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass)
        @rb_obj_is_kind_of = @mod.functions.add("rb_obj_is_kind_of", [value_type, value_type], value_type)

        # rb_path2class - lookup class by path string
        # VALUE rb_path2class(const char *path)
        @rb_path2class = @mod.functions.add("rb_path2class", [ptr_type], value_type)

        # rb_cInteger, rb_cFloat, rb_cString - class constants for common types
        @rb_cInteger = @mod.globals.add(value_type, "rb_cInteger") do |var|
          var.linkage = :external
        end
        @rb_cFloat = @mod.globals.add(value_type, "rb_cFloat") do |var|
          var.linkage = :external
        end
        @rb_cString = @mod.globals.add(value_type, "rb_cString") do |var|
          var.linkage = :external
        end
        @rb_cSymbol = @mod.globals.add(value_type, "rb_cSymbol") do |var|
          var.linkage = :external
        end
        @rb_cArray = @mod.globals.add(value_type, "rb_cArray") do |var|
          var.linkage = :external
        end
        @rb_cHash = @mod.globals.add(value_type, "rb_cHash") do |var|
          var.linkage = :external
        end
        @rb_cNilClass = @mod.globals.add(value_type, "rb_cNilClass") do |var|
          var.linkage = :external
        end
        @rb_cTrueClass = @mod.globals.add(value_type, "rb_cTrueClass") do |var|
          var.linkage = :external
        end
        @rb_cFalseClass = @mod.globals.add(value_type, "rb_cFalseClass") do |var|
          var.linkage = :external
        end

        # memset for zero-initializing structs/arrays
        # void *memset(void *s, int c, size_t n)
        @memset = @mod.functions.add("memset",
          [LLVM::Pointer(LLVM::Int8), LLVM::Int32, LLVM::Int64],
          LLVM::Pointer(LLVM::Int8))

        # yyjson functions for JSON parsing
        declare_yyjson_functions

        # Declare builtin methods for direct calls (devirtualization)
        declare_builtin_methods
      end

      # Declare yyjson wrapper functions for JSON parsing
      # Uses konpeito_yyjson_* wrappers for inline functions
      def declare_yyjson_functions
        # konpeito_yyjson_read(const char *dat, size_t len, yyjson_read_flag flg)
        @yyjson_read = @mod.functions.add("konpeito_yyjson_read",
          [ptr_type, LLVM::Int64, LLVM::Int32], ptr_type)

        # konpeito_yyjson_doc_get_root(yyjson_doc *doc)
        @yyjson_doc_get_root = @mod.functions.add("konpeito_yyjson_doc_get_root",
          [ptr_type], ptr_type)

        # konpeito_yyjson_doc_free(yyjson_doc *doc)
        @yyjson_doc_free = @mod.functions.add("konpeito_yyjson_doc_free",
          [ptr_type], LLVM.Void)

        # konpeito_yyjson_obj_get(yyjson_val *obj, const char *key)
        @yyjson_obj_get = @mod.functions.add("konpeito_yyjson_obj_get",
          [ptr_type, ptr_type], ptr_type)

        # konpeito_yyjson_get_sint(yyjson_val *val)
        @yyjson_get_sint = @mod.functions.add("konpeito_yyjson_get_sint",
          [ptr_type], LLVM::Int64)

        # konpeito_yyjson_get_uint(yyjson_val *val)
        @yyjson_get_uint = @mod.functions.add("konpeito_yyjson_get_uint",
          [ptr_type], LLVM::Int64)

        # konpeito_yyjson_get_real(yyjson_val *val)
        @yyjson_get_real = @mod.functions.add("konpeito_yyjson_get_real",
          [ptr_type], LLVM::Double)

        # konpeito_yyjson_get_bool(yyjson_val *val)
        @yyjson_get_bool = @mod.functions.add("konpeito_yyjson_get_bool",
          [ptr_type], LLVM::Int1)

        # konpeito_yyjson_get_str(yyjson_val *val)
        @yyjson_get_str = @mod.functions.add("konpeito_yyjson_get_str",
          [ptr_type], ptr_type)

        # konpeito_yyjson_get_len(yyjson_val *val)
        @yyjson_get_len = @mod.functions.add("konpeito_yyjson_get_len",
          [ptr_type], LLVM::Int64)

        # Array iteration
        # konpeito_yyjson_arr_size(yyjson_val *arr)
        @yyjson_arr_size = @mod.functions.add("konpeito_yyjson_arr_size",
          [ptr_type], LLVM::Int64)

        # konpeito_yyjson_arr_get(yyjson_val *arr, size_t idx)
        @yyjson_arr_get = @mod.functions.add("konpeito_yyjson_arr_get",
          [ptr_type, LLVM::Int64], ptr_type)
      end

      # Declare CRuby builtin method functions for direct calls
      # All functions use simple convention: VALUE func(VALUE recv, VALUE arg1, ...)
      def declare_builtin_methods
        @builtin_funcs = {}

        # Iterate through all builtin methods and declare them
        Codegen::BUILTIN_METHODS.each do |_class_name, methods|
          methods.each do |_method_name, info|
            c_func = info[:c_func]
            next unless c_func
            next if @builtin_funcs[c_func]
            # Skip special conv types - they are declared in declare_cruby_functions
            next if [:ary_store, :ary_delete_at, :ary_entry].include?(info[:conv])

            # Check if function already exists in module (declared elsewhere)
            existing_func = @mod.functions[c_func]
            if existing_func
              @builtin_funcs[c_func] = existing_func
              next
            end

            arity = info[:arity]
            # Simple convention: VALUE func(VALUE recv, VALUE arg1, ...)
            param_types = [value_type] * (arity + 1)  # +1 for receiver
            @builtin_funcs[c_func] = @mod.functions.add(c_func, param_types, value_type)
          end
        end
      end

      def generate_function_body(hir_func)
        # Check if this is a NativeClass method
        native_class_type = detect_native_class_for_function(hir_func)

        if native_class_type
          generate_native_function_body(hir_func, native_class_type)
        else
          generate_ruby_function_body(hir_func)
        end
      end

      # Detect if a function belongs to a NativeClass
      # Native-first: Excludes @boxed classes
      def detect_native_class_for_function(hir_func)
        return nil unless hir_func.owner_class

        # Check if we have a struct type for this class (indicates it's a NativeClass)
        @native_class_structs ||= {}
        class_name = hir_func.owner_class.to_sym

        # @boxed classes use VALUE path (not native)
        return nil if @rbs_loader&.boxed_class?(class_name)

        # Look for a matching NativeClassType from method calls in the HIR
        @native_class_type_registry ||= {}
        @native_class_type_registry[class_name]
      end

      # Register a NativeClassType for function detection
      def register_native_class_type(class_type)
        @native_class_type_registry ||= {}
        @native_class_type_registry[class_type.name] = class_type
      end

      # Generate a function for a NativeClass method
      # Uses struct pointer for self, unboxed parameters
      def generate_native_function_body(hir_func, native_class_type)
        method_sig = native_class_type.methods[hir_func.name.to_sym]

        # Get the already-declared function
        mangled = mangle_name(hir_func)
        func = @functions[mangled]

        # Clear variables for this function
        @variables = {}
        @variable_allocas = {}
        @variable_types = {}
        @current_function = func
        @current_hir_func = hir_func
        @current_native_class = native_class_type  # Track for self field access

        # Create basic blocks
        hir_func.body.each do |hir_block|
          llvm_block = func.basic_blocks.append(hir_block.label)
          @blocks[hir_block.label] = llvm_block
        end

        entry_block = @blocks[hir_func.body.first.label]
        @builder.position_at_end(entry_block)

        # Store self pointer for field access
        @variables["self"] = func.params[0]
        @variable_types["self"] = :native_class
        @native_class_types ||= {}
        @native_class_types["self"] = native_class_type

        # Store parameters (already unboxed)
        hir_func.params.each_with_index do |param, i|
          param_value = func.params[i + 1]  # +1 to skip self
          param_type_sym = method_sig&.param_types&.[](i) || :Float64

          # Determine type tag based on parameter type
          type_tag = case param_type_sym
          when :Int64 then :i64
          when :Float64 then :double
          else
            # Another NativeClass type - mark as native_class
            :native_class
          end

          @variables[param.name] = param_value
          @variable_types[param.name] = type_tag

          # Track the NativeClass type for parameters that are NativeClass instances
          if type_tag == :native_class
            @native_class_types ||= {}
            @native_class_types[param.name] = @native_class_type_registry[param_type_sym] if @native_class_type_registry
          end
        end

        # Insert profiling entry probe after parameter setup
        insert_profile_entry_probe(hir_func)

        # Track blocks with Return terminators so phi nodes can skip them
        @return_blocks = Set.new
        hir_func.body.each do |hir_block|
          @return_blocks << hir_block.label if hir_block.terminator.is_a?(HIR::Return)
        end

        # Generate code for each block
        hir_func.body.each do |hir_block|
          generate_block(func, hir_block)
        end

        optimize_function(func)
        @current_native_class = nil

        func
      end

      # Generate a standard Ruby function
      def generate_ruby_function_body(hir_func)
        # Get the already-declared function
        mangled = mangle_name(hir_func)
        func = @functions[mangled]

        # Clear variables for this function
        @variables = {}
        @variable_allocas = {}
        @variable_types = {}
        @current_function = func
        @current_hir_func = hir_func

        # Create debug info for function if debug mode enabled
        @current_subprogram = nil
        if @dibuilder && hir_func.location
          @current_subprogram = @dibuilder.create_function(
            name: hir_func.name,
            linkage_name: mangled,
            line: hir_func.location.line || 1
          )
          @dibuilder.attach_subprogram(func, @current_subprogram)
        end

        # Create basic blocks
        hir_func.body.each do |hir_block|
          llvm_block = func.basic_blocks.append(hir_block.label)
          @blocks[hir_block.label] = llvm_block
        end

        # Position at entry block to create allocas
        entry_block = @blocks[hir_func.body.first.label]
        @builder.position_at_end(entry_block)

        # Collect all local variables with their types
        local_vars_with_types = collect_local_variables_with_types(hir_func)

        # Create allocas for all local variables with appropriate types
        # Integer -> i64 (unboxed), Float -> double (unboxed), others -> VALUE (boxed)
        local_vars_with_types.each do |var_name, var_type|
          llvm_type, type_tag = llvm_type_for_ruby_type(var_type)
          alloca = @builder.alloca(llvm_type, var_name)
          @variable_allocas[var_name] = alloca
          @variable_types[var_name] = type_tag
        end

        # Separate regular, keyword, and keyword_rest parameters
        regular_params = hir_func.params.reject { |p| p.keyword || p.keyword_rest || p.rest }
        keyword_params = hir_func.params.select(&:keyword)
        keyword_rest_param = hir_func.params.find(&:keyword_rest)

        # Check if this is a variadic function
        variadic_info = @variadic_functions[mangled]

        if variadic_info
          # Variadic signature: VALUE func(int argc, VALUE *argv, VALUE self)
          argc_param = func.params[0]      # int argc
          argv_param = func.params[1]      # VALUE *argv
          self_param = func.params[2]      # VALUE self

          # Store self
          @variables["self"] = self_param
          @variable_types["self"] = :value

          # Handle leading regular parameters (before *args)
          # These are extracted from argv[0], argv[1], etc.
          if variadic_info[:regular_count] > 0
            regular_params.each_with_index do |param, i|
              alloca = @variable_allocas[param.name]
              next unless alloca

              # Get argv[i]
              param_ptr = @builder.gep2(value_type, argv_param, [LLVM::Int32.from_i(i)], "param_#{param.name}_ptr")
              boxed_value = @builder.load2(value_type, param_ptr, "param_#{param.name}")

              type_tag = @variable_types[param.name]

              # Unbox parameter if it's a numeric type
              value_to_store = case type_tag
              when :i64
                @builder.call(@rb_num2long, boxed_value)
              when :double
                @builder.call(@rb_num2dbl, boxed_value)
              else
                boxed_value
              end

              @builder.store(value_to_store, alloca)
            end
          end

          # Handle **kwargs extraction
          if variadic_info[:keyword_rest]
            # Create block structure for argc check
            current_func = @builder.insert_block.parent
            has_kwargs_block = current_func.basic_blocks.append("has_kwargs")
            no_kwargs_block = current_func.basic_blocks.append("no_kwargs")
            continue_block = current_func.basic_blocks.append("kwargs_continue")

            # Check if argc > 0
            has_args = @builder.icmp(:sgt, argc_param, LLVM::Int32.from_i(0))
            @builder.cond(has_args, has_kwargs_block, no_kwargs_block)

            # Block: has kwargs - extract from argv
            @builder.position_at_end(has_kwargs_block)
            # Get last element: argv[argc - 1]
            last_index = @builder.sub(argc_param, LLVM::Int32.from_i(1), "last_idx")
            kwargs_ptr = @builder.gep2(value_type, argv_param, [last_index], "kwargs_ptr")
            kwargs_from_argv = @builder.load2(value_type, kwargs_ptr, "kwargs_val")
            @builder.br(continue_block)

            # Block: no kwargs - create empty hash
            @builder.position_at_end(no_kwargs_block)
            empty_hash = @builder.call(@rb_hash_new)
            @builder.br(continue_block)

            # Continue block: merge with phi
            @builder.position_at_end(continue_block)
            kwargs_hash = @builder.phi(value_type, { has_kwargs_block => kwargs_from_argv, no_kwargs_block => empty_hash }, "kwargs_hash")

            # Store the kwargs hash in the parameter
            alloca = @variable_allocas[variadic_info[:keyword_rest]]
            if alloca
              @builder.store(kwargs_hash, alloca)
            else
              @variables[variadic_info[:keyword_rest]] = kwargs_hash
              @variable_types[variadic_info[:keyword_rest]] = :value
            end

            # Remap the entry HIR block to kwargs_continue so subsequent code
            # is generated in the correct block (after the variadic prologue)
            @blocks[hir_func.body.first.label] = continue_block
          end

          # Handle *args extraction
          if variadic_info[:rest]
            rest_param_name = variadic_info[:rest]
            regular_count = variadic_info[:regular_count]

            # Calculate the number of rest arguments: rest_count = argc - regular_count
            # (For simplicity, we assume **kwargs takes the last argument if present)
            kwargs_adjustment = variadic_info[:keyword_rest] ? 1 : 0

            # Create the rest array from argv elements
            # rb_ary_new_from_values(rest_count, argv + regular_count)
            rest_count_i32 = @builder.sub(argc_param, LLVM::Int32.from_i(regular_count + kwargs_adjustment), "rest_count_i32")
            rest_count = @builder.sext(rest_count_i32, LLVM::Int64, "rest_count")

            # Check if rest_count > 0 to avoid creating array with negative size
            current_func = @builder.insert_block.parent
            has_rest_block = current_func.basic_blocks.append("has_rest")
            no_rest_block = current_func.basic_blocks.append("no_rest")
            rest_continue_block = current_func.basic_blocks.append("rest_continue")

            has_rest = @builder.icmp(:sgt, rest_count_i32, LLVM::Int32.from_i(0))
            @builder.cond(has_rest, has_rest_block, no_rest_block)

            # Block: has rest args
            @builder.position_at_end(has_rest_block)
            rest_ptr = @builder.gep2(value_type, argv_param, [LLVM::Int32.from_i(regular_count)], "rest_ptr")
            rest_array_from_values = @builder.call(@rb_ary_new_from_values, rest_count, rest_ptr)
            @builder.br(rest_continue_block)

            # Block: no rest args - create empty array
            @builder.position_at_end(no_rest_block)
            empty_array = @builder.call(@rb_ary_new)
            @builder.br(rest_continue_block)

            # Continue: merge with phi
            @builder.position_at_end(rest_continue_block)
            rest_array = @builder.phi(value_type, { has_rest_block => rest_array_from_values, no_rest_block => empty_array }, "rest_array")

            # Store the rest array
            alloca = @variable_allocas[rest_param_name]
            if alloca
              @builder.store(rest_array, alloca)
            else
              @variables[rest_param_name] = rest_array
              @variable_types[rest_param_name] = :value
            end

            # Remap entry block to rest_continue
            @blocks[hir_func.body.first.label] = rest_continue_block
          end
        else
          # Standard fixed-arity path
          # Store initial values for regular parameters (unbox if needed)
          regular_params.each_with_index do |param, i|
            alloca = @variable_allocas[param.name]
            next unless alloca

            boxed_value = func.params[i + 1]  # +1 to skip self
          type_tag = @variable_types[param.name]

          # Unbox parameter if it's a numeric type
          value_to_store = case type_tag
          when :i64
            @builder.call(@rb_num2long, boxed_value)
          when :double
            @builder.call(@rb_num2dbl, boxed_value)
          else
            boxed_value
          end

          @builder.store(value_to_store, alloca)
        end

        # Handle keyword parameters - extract from the trailing Hash argument
        if keyword_params.any?
          # The kwargs hash is the last parameter
          kwargs_hash_param_index = regular_params.size + 1  # +1 for self
          kwargs_hash = func.params[kwargs_hash_param_index]

          keyword_params.each do |param|
            alloca = @variable_allocas[param.name]
            next unless alloca

            type_tag = @variable_types[param.name]

            # Create Symbol key for lookup
            key_str_ptr = @builder.global_string_pointer(param.name)
            key_id = @builder.call(@rb_intern, key_str_ptr)
            key_sym = @builder.call(@rb_id2sym, key_id)

            # Determine default value
            default_value = if param.default_value
              generate_keyword_default_value(param.default_value)
            else
              # Required keyword - use Qundef to detect missing
              @qundef
            end

            # Lookup value in kwargs hash
            value = @builder.call(@rb_hash_lookup2, kwargs_hash, key_sym, default_value)

            # For required keywords (no default), check if value == Qundef and raise ArgumentError
            unless param.default_value
              # Get current function for basic block creation
              current_func = @builder.insert_block.parent

              # Create blocks for the conditional
              error_block = current_func.basic_blocks.append("kwarg_missing_#{param.name}")
              continue_block = current_func.basic_blocks.append("kwarg_ok_#{param.name}")

              # Check if value == Qundef (missing keyword)
              is_missing = @builder.icmp(:eq, value, @qundef)
              @builder.cond(is_missing, error_block, continue_block)

              # Generate error block: raise ArgumentError
              @builder.position_at_end(error_block)

              # Load rb_eArgumentError
              arg_error_class = @builder.load2(value_type, @rb_eArgumentError, "rb_eArgumentError")

              # Create error message string: "missing keyword: <name>"
              error_msg = "missing keyword: #{param.name}"
              error_msg_ptr = @builder.global_string_pointer(error_msg)

              # Call rb_raise(rb_eArgumentError, "missing keyword: name")
              @builder.call(@rb_raise, arg_error_class, error_msg_ptr)

              # rb_raise never returns, but LLVM needs a terminator
              @builder.unreachable

              # Continue normal execution
              @builder.position_at_end(continue_block)
            end

            # Unbox if needed
            value_to_store = case type_tag
            when :i64
              @builder.call(@rb_num2long, value)
            when :double
              @builder.call(@rb_num2dbl, value)
            else
              value
            end

            @builder.store(value_to_store, alloca)
          end
        end

          # Handle keyword_rest parameter (**kwargs)
          if keyword_rest_param
            alloca = @variable_allocas[keyword_rest_param.name]
            if alloca
              # The kwargs hash is the last parameter
              kwargs_hash_param_index = regular_params.size + 1  # +1 for self
              kwargs_hash = func.params[kwargs_hash_param_index]

              # For keyword_rest, store the entire kwargs hash
              # Note: In a full implementation, we should remove named keyword args from this hash
              # For now, we store the full hash (this is correct if there are no named keyword params)
              @builder.store(kwargs_hash, alloca)
            end
          end

          # After keyword processing, remap entry block to current position.
          # Required keyword params create branch blocks (kwarg_missing/kwarg_ok),
          # leaving the builder positioned in a continuation block rather than
          # the original entry block. Function body code must be generated there.
          if keyword_params.any? { |p| !p.default_value }
            @blocks[hir_func.body.first.label] = @builder.insert_block
          end
        end  # End of variadic_info else block

        # Insert profiling entry probe after parameter setup
        insert_profile_entry_probe(hir_func)

        # Sort blocks to ensure phi dependencies are satisfied
        # Blocks with phi nodes referencing results from other blocks must come after those blocks
        sorted_blocks = sort_blocks_by_phi_dependencies(hir_func.body)

        # Track blocks with Return terminators so phi nodes can skip them
        # (a block that returns doesn't branch to the merge block)
        @return_blocks = Set.new
        sorted_blocks.each do |hir_block|
          @return_blocks << hir_block.label if hir_block.terminator.is_a?(HIR::Return)
        end

        # Generate code for each block in dependency order
        sorted_blocks.each do |hir_block|
          generate_block(func, hir_block)
        end

        # Apply mem2reg optimization to convert allocas to SSA
        optimize_function(func)

        func
      end

      # Topologically sort blocks based on phi dependencies
      # Ensures blocks are generated after the blocks their phi nodes reference
      def sort_blocks_by_phi_dependencies(blocks)
        # Build a map of block label -> block
        block_map = blocks.each_with_object({}) { |b, h| h[b.label] = b }

        # Build dependency graph: block -> blocks it depends on (via phi incoming values)
        dependencies = {}
        blocks.each do |block|
          deps = Set.new
          block.instructions.each do |inst|
            next unless inst.is_a?(HIR::Phi)

            inst.incoming.each do |label, value|
              # If the incoming value is from a result_var in another block,
              # we depend on that block being generated first
              if value.respond_to?(:result_var) && value.result_var
                # Find which block defines this result_var
                blocks.each do |other_block|
                  next if other_block.label == block.label

                  other_block.instructions.each do |other_inst|
                    if other_inst.respond_to?(:result_var) && other_inst.result_var == value.result_var
                      deps << other_block.label
                    end
                  end
                end
              end
            end
          end
          dependencies[block.label] = deps
        end

        # Topological sort using Kahn's algorithm
        in_degree = Hash.new(0)
        dependencies.each do |block_label, deps|
          deps.each do |dep_label|
            in_degree[block_label] += 1 if block_map[dep_label]
          end
        end

        # Start with blocks that have no dependencies
        queue = blocks.select { |b| in_degree[b.label] == 0 }
        sorted = []

        while queue.any?
          # Take the first available block (preserves original order when possible)
          current = queue.shift
          sorted << current

          # For each block that depends on current, decrease its in-degree
          blocks.each do |block|
            if dependencies[block.label]&.include?(current.label)
              in_degree[block.label] -= 1
              if in_degree[block.label] == 0 && !sorted.include?(block) && !queue.include?(block)
                queue << block
              end
            end
          end
        end

        # If some blocks weren't added (cycle), add them in original order
        remaining = blocks - sorted
        sorted + remaining
      end

      def collect_local_variables_with_types(hir_func)
        vars = {}

        # Add parameters with their types
        hir_func.params.each do |p|
          vars[p.name] = p.type
        end

        # Scan all blocks for StoreLocal instructions
        hir_func.body.each do |block|
          block.instructions.each do |inst|
            if inst.is_a?(HIR::StoreLocal)
              # Use the type from the value being stored, or existing type
              value_type = inst.value.respond_to?(:type) ? inst.value.type : nil
              vars[inst.var.name] ||= value_type || inst.var.type
            end
          end
        end

        vars
      end

      # Collect local variables used in a block definition
      # Similar to collect_local_variables_with_types but for block bodies
      def collect_local_variables_in_block(block_def)
        vars = {}

        # Scan all basic blocks for StoreLocal instructions
        block_def.body.each do |basic_block|
          basic_block.instructions.each do |inst|
            if inst.is_a?(HIR::StoreLocal)
              # Use the type from the value being stored, or existing type
              value_type = inst.value.respond_to?(:type) ? inst.value.type : nil
              vars[inst.var.name] ||= value_type || inst.var.type
            end
          end
        end

        vars
      end

      def llvm_type_for_ruby_type(ruby_type)
        # Resolve TypeVar first
        ruby_type = resolve_type_var(ruby_type)

        if integer_type?(ruby_type)
          [LLVM::Int64, :i64]
        elsif float_type?(ruby_type)
          [LLVM::Double, :double]
        else
          [value_type, :value]
        end
      end

      def optimize_function(func)
        # Note: mem2reg optimization is applied by llc during compilation
        # with the -O2 flag in cruby_backend.rb
        # The allocas created here will be converted to proper SSA form
        # by LLVM's optimization passes automatically
      end

      # Sanitize a Ruby method name to a valid C/LLVM identifier
      # Operators get distinctive names to avoid collisions
      OPERATOR_NAME_MAP = {
        "+" => "op_plus", "-" => "op_minus", "*" => "op_mul", "/" => "op_div",
        "%" => "op_mod", "**" => "op_pow", "==" => "op_eq", "!=" => "op_neq",
        "<" => "op_lt", ">" => "op_gt", "<=" => "op_le", ">=" => "op_ge",
        "<=>" => "op_cmp", "<<" => "op_lshift", ">>" => "op_rshift",
        "&" => "op_and", "|" => "op_or", "^" => "op_xor", "~" => "op_not",
        "[]" => "op_aref", "[]=" => "op_aset", "+@" => "op_uplus", "-@" => "op_uminus",
      }.freeze

      def sanitize_c_name(name)
        return OPERATOR_NAME_MAP[name] if OPERATOR_NAME_MAP.key?(name)
        name.gsub(/[^a-zA-Z0-9_]/, "_")
      end

      def mangle_name(hir_func)
        # Mangle method name for CRuby extension
        # Include class or module name for instance methods
        name = sanitize_c_name(hir_func.name.to_s)
        if hir_func.owner_class
          owner = hir_func.owner_class.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
          "rn_#{owner}_#{name}"
        elsif hir_func.owner_module
          owner = hir_func.owner_module.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
          "rn_#{owner}_#{name}"
        else
          "rn_#{name}"
        end
      end

      def generate_block(func, hir_block)
        llvm_block = @blocks[hir_block.label]
        @builder.position_at_end(llvm_block)

        # Collect instructions that are owned by BeginRescue nodes
        # These will be generated inside callbacks, not in the main function
        rescue_owned = collect_rescue_owned_instructions(hir_block.instructions)

        # Generate instructions
        hir_block.instructions.each do |inst|
          next if rescue_owned.include?(inst.object_id)
          generate_instruction(inst)
        end

        # Generate terminator
        generate_terminator(hir_block.terminator) if hir_block.terminator
      end

      # Collect all instructions that are owned by BeginRescue nodes
      # These instructions will be generated inside try/rescue callbacks,
      # not in the main function body
      def collect_rescue_owned_instructions(instructions)
        owned = Set.new
        instructions.each do |inst|
          next unless inst.is_a?(HIR::BeginRescue)

          # Try block instructions
          inst.try_blocks&.each { |i| owned << i.object_id }

          # Rescue clause body instructions
          inst.rescue_clauses&.each do |clause|
            clause.body_blocks&.each { |i| owned << i.object_id }
          end

          # Else block instructions
          inst.else_blocks&.each { |i| owned << i.object_id }

          # Ensure block instructions
          inst.ensure_blocks&.each { |i| owned << i.object_id }
        end
        owned
      end

      def generate_instruction(inst)
        case inst
        when HIR::IntegerLit
          generate_integer_lit(inst)
        when HIR::FloatLit
          generate_float_lit(inst)
        when HIR::StringLit
          generate_string_lit(inst)
        when HIR::StringConcat
          generate_string_concat(inst)
        when HIR::SymbolLit
          generate_symbol_lit(inst)
        when HIR::RegexpLit
          generate_regexp_lit(inst)
        when HIR::BoolLit
          generate_bool_lit(inst)
        when HIR::NilLit
          generate_nil_lit(inst)
        when HIR::ArrayLit
          generate_array_lit(inst)
        when HIR::HashLit
          generate_hash_lit(inst)
        when HIR::LoadLocal
          generate_load_local(inst)
        when HIR::StoreLocal
          generate_store_local(inst)
        when HIR::LoadInstanceVar
          generate_load_instance_var(inst)
        when HIR::StoreInstanceVar
          generate_store_instance_var(inst)
        when HIR::LoadClassVar
          generate_load_class_var(inst)
        when HIR::StoreClassVar
          generate_store_class_var(inst)
        when HIR::StoreConstant
          generate_store_constant(inst)
        when HIR::Call
          generate_call(inst)
        when HIR::SelfRef
          generate_self_ref(inst)
        when HIR::Phi
          generate_phi(inst)
        when HIR::Yield
          generate_yield(inst)
        when HIR::ProcNew
          generate_proc_new(inst)
        when HIR::ProcCall
          generate_proc_call(inst)
        when HIR::FiberNew
          generate_fiber_new(inst)
        when HIR::FiberResume
          generate_fiber_resume(inst)
        when HIR::FiberYield
          generate_fiber_yield(inst)
        when HIR::FiberAlive
          generate_fiber_alive(inst)
        when HIR::FiberCurrent
          generate_fiber_current(inst)
        when HIR::ThreadNew
          generate_thread_new(inst)
        when HIR::ThreadJoin
          generate_thread_join(inst)
        when HIR::ThreadValue
          generate_thread_value(inst)
        when HIR::ThreadCurrent
          generate_thread_current(inst)
        when HIR::MutexNew
          generate_mutex_new(inst)
        when HIR::MutexLock
          generate_mutex_lock(inst)
        when HIR::MutexUnlock
          generate_mutex_unlock(inst)
        when HIR::MutexSynchronize
          generate_mutex_synchronize(inst)
        when HIR::QueueNew
          generate_queue_new(inst)
        when HIR::QueuePush
          generate_queue_push(inst)
        when HIR::QueuePop
          generate_queue_pop(inst)
        when HIR::ConditionVariableNew
          generate_cv_new(inst)
        when HIR::ConditionVariableWait
          generate_cv_wait(inst)
        when HIR::ConditionVariableSignal
          generate_cv_signal(inst)
        when HIR::ConditionVariableBroadcast
          generate_cv_broadcast(inst)
        when HIR::SizedQueueNew
          generate_sized_queue_new(inst)
        when HIR::SizedQueuePush
          generate_sized_queue_push(inst)
        when HIR::SizedQueuePop
          generate_sized_queue_pop(inst)
        when HIR::NativeArrayAlloc
          generate_native_array_alloc(inst)
        when HIR::NativeArrayGet
          generate_native_array_get(inst)
        when HIR::NativeArraySet
          generate_native_array_set(inst)
        when HIR::NativeArrayLength
          generate_native_array_length(inst)
        when HIR::StaticArrayAlloc
          generate_static_array_alloc(inst)
        when HIR::StaticArrayGet
          generate_static_array_get(inst)
        when HIR::StaticArraySet
          generate_static_array_set(inst)
        when HIR::StaticArraySize
          generate_static_array_size(inst)
        when HIR::NativeNew
          generate_native_new(inst)
        when HIR::NativeFieldGet
          generate_native_field_get(inst)
        when HIR::NativeFieldSet
          generate_native_field_set(inst)
        when HIR::NativeMethodCall
          generate_native_method_call(inst)
        when HIR::CFuncCall
          generate_cfunc_call(inst)
        when HIR::ExternConstructorCall
          generate_extern_constructor_call(inst)
        when HIR::ExternMethodCall
          generate_extern_method_call(inst)
        when HIR::SIMDNew
          generate_simd_new(inst)
        when HIR::SIMDFieldGet
          generate_simd_field_get(inst)
        when HIR::SIMDFieldSet
          generate_simd_field_set(inst)
        when HIR::SIMDMethodCall
          generate_simd_method_call(inst)
        # ByteBuffer operations
        when HIR::ByteBufferAlloc
          generate_byte_buffer_alloc(inst)
        when HIR::ByteBufferGet
          generate_byte_buffer_get(inst)
        when HIR::ByteBufferSet
          generate_byte_buffer_set(inst)
        when HIR::ByteBufferLength
          generate_byte_buffer_length(inst)
        when HIR::ByteBufferAppend
          generate_byte_buffer_append(inst)
        when HIR::ByteBufferIndexOf
          generate_byte_buffer_index_of(inst)
        when HIR::ByteBufferToString
          generate_byte_buffer_to_string(inst)
        when HIR::ByteBufferSlice
          generate_byte_buffer_slice(inst)
        # ByteSlice operations
        when HIR::ByteSliceGet
          generate_byte_slice_get(inst)
        when HIR::ByteSliceLength
          generate_byte_slice_length(inst)
        when HIR::ByteSliceToString
          generate_byte_slice_to_string(inst)
        # Slice[T] operations
        when HIR::SliceAlloc
          generate_slice_alloc(inst)
        when HIR::SliceEmpty
          generate_slice_empty(inst)
        when HIR::SliceGet
          generate_slice_get(inst)
        when HIR::SliceSet
          generate_slice_set(inst)
        when HIR::SliceSize
          generate_slice_size(inst)
        when HIR::SliceSubslice
          generate_slice_subslice(inst)
        when HIR::SliceCopyFrom
          generate_slice_copy_from(inst)
        when HIR::SliceFill
          generate_slice_fill(inst)
        when HIR::ToSlice
          generate_to_slice(inst)
        # StringBuffer operations
        when HIR::StringBufferAlloc
          generate_string_buffer_alloc(inst)
        when HIR::StringBufferAppend
          generate_string_buffer_append(inst)
        when HIR::StringBufferLength
          generate_string_buffer_length(inst)
        when HIR::StringBufferToString
          generate_string_buffer_to_string(inst)
        # NativeString operations
        when HIR::NativeStringFromRuby
          generate_native_string_from_ruby(inst)
        when HIR::NativeStringByteAt
          generate_native_string_byte_at(inst)
        when HIR::NativeStringByteLength
          generate_native_string_byte_length(inst)
        when HIR::NativeStringByteIndexOf
          generate_native_string_byte_index_of(inst)
        when HIR::NativeStringByteSlice
          generate_native_string_byte_slice(inst)
        when HIR::NativeStringCharAt
          generate_native_string_char_at(inst)
        when HIR::NativeStringCharLength
          generate_native_string_char_length(inst)
        when HIR::NativeStringCharIndexOf
          generate_native_string_char_index_of(inst)
        when HIR::NativeStringCharSlice
          generate_native_string_char_slice(inst)
        when HIR::NativeStringAsciiOnly
          generate_native_string_ascii_only(inst)
        when HIR::NativeStringStartsWith
          generate_native_string_starts_with(inst)
        when HIR::NativeStringEndsWith
          generate_native_string_ends_with(inst)
        when HIR::NativeStringValidEncoding
          generate_native_string_valid_encoding(inst)
        when HIR::NativeStringToRuby
          generate_native_string_to_ruby(inst)
        when HIR::NativeStringCompare
          generate_native_string_compare(inst)
        # JSON operations
        when HIR::JSONParseAs
          generate_json_parse_as(inst)
        when HIR::JSONParseArrayAs
          generate_json_parse_array_as(inst)
        # NativeHash operations
        when HIR::NativeHashAlloc
          generate_native_hash_alloc(inst)
        when HIR::NativeHashGet
          generate_native_hash_get(inst)
        when HIR::NativeHashSet
          generate_native_hash_set(inst)
        when HIR::NativeHashSize
          generate_native_hash_size(inst)
        when HIR::NativeHashHasKey
          generate_native_hash_has_key(inst)
        when HIR::NativeHashDelete
          generate_native_hash_delete(inst)
        when HIR::NativeHashClear
          generate_native_hash_clear(inst)
        when HIR::NativeHashKeys
          generate_native_hash_keys(inst)
        when HIR::NativeHashValues
          generate_native_hash_values(inst)
        when HIR::NativeHashEach
          generate_native_hash_each(inst)
        when HIR::BeginRescue
          generate_begin_rescue(inst)
        when HIR::CaseStatement
          generate_case_statement(inst)
        when HIR::CaseMatchStatement
          generate_case_match_statement(inst)
        when HIR::MatchPredicate
          generate_match_predicate(inst)
        when HIR::MatchRequired
          generate_match_required(inst)
        when HIR::ConstantLookup
          generate_constant_lookup(inst)
        when HIR::RangeLit
          generate_range_lit(inst)
        when HIR::LoadGlobalVar
          generate_load_global_var(inst)
        when HIR::StoreGlobalVar
          generate_store_global_var(inst)
        when HIR::SplatArg
          # SplatArg is handled by generate_call, just store the expression value
          val = get_value_as_ruby(inst.expression)
          @variables[inst.result_var] = val if inst.result_var
        when HIR::DefinedCheck
          generate_defined_check(inst)
        when HIR::SuperCall
          generate_super_call(inst)
        when HIR::MultiWriteExtract
          generate_multi_write_extract(inst)
        else
          # Unknown instruction, store nil
          if inst.result_var
            @variables[inst.result_var] = @qnil
          end
        end
      end

      def generate_integer_lit(inst)
        # Keep as unboxed i64 - will be boxed only when needed
        c_int = LLVM::Int64.from_i(inst.value)
        if inst.result_var
          @variables[inst.result_var] = c_int
          @variable_types[inst.result_var] = :i64
        end
        c_int
      end

      def generate_float_lit(inst)
        # Keep as unboxed double - will be boxed only when needed
        c_double = LLVM::Double.from_f(inst.value)
        if inst.result_var
          @variables[inst.result_var] = c_double
          @variable_types[inst.result_var] = :double
        end
        c_double
      end

      def generate_string_lit(inst)
        # Create global string constant
        str_ptr = @builder.global_string_pointer(inst.value)
        ruby_str = @builder.call(@rb_str_new_cstr, str_ptr)
        @variables[inst.result_var] = ruby_str if inst.result_var
        ruby_str
      end

      # Generate optimized string concatenation chain with buffer pre-allocation
      # Use rb_str_buf_new to pre-allocate buffer based on static length
      # This avoids multiple memory reallocations during concatenation
      def generate_string_concat(inst)
        parts = inst.parts
        return @qnil if parts.empty?

        # Separate static (StringLit) and dynamic parts
        # Calculate static length at compile time
        static_length = 0
        part_info = parts.map do |part|
          if part.is_a?(HIR::StringLit)
            static_length += part.value.bytesize
            { type: :static, value: part.value, length: part.value.bytesize }
          else
            { type: :dynamic, hir: part }
          end
        end

        # Generate dynamic parts first (they may need to_s conversion)
        # and collect their lengths
        dynamic_values = []
        dynamic_lengths = []

        part_info.each do |info|
          next if info[:type] == :static

          if info[:hir].is_a?(HIR::Instruction)
            generate_instruction(info[:hir])
          end
          val = get_value_as_ruby(info[:hir])

          # Convert to string if needed (for non-string interpolated values)
          val_type = info[:hir].respond_to?(:type) ? info[:hir].type : nil
          unless val_type == TypeChecker::Types::STRING
            to_s_ptr = @builder.global_string_pointer("to_s")
            to_s_id = @builder.call(@rb_intern, to_s_ptr)
            val = @builder.call(@rb_funcallv, val, to_s_id, LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
          end

          dynamic_values << val
          # Get string length (returns Fixnum, need to unbox)
          len_val = @builder.call(@rb_str_length, val)
          # Unbox Fixnum: (value >> 1)
          len_i64 = @builder.ashr(len_val, LLVM::Int64.from_i(1))
          dynamic_lengths << len_i64
        end

        # If only one part, just return it
        if parts.size == 1
          result = if part_info.first[:type] == :static
            str_ptr = @builder.global_string_pointer(part_info.first[:value])
            @builder.call(@rb_str_new_cstr, str_ptr)
          else
            dynamic_values.first
          end
          @variables[inst.result_var] = result if inst.result_var
          return result
        end

        # Calculate total length: static_length + sum of dynamic lengths
        total_length = LLVM::Int64.from_i(static_length)
        dynamic_lengths.each do |len|
          total_length = @builder.add(total_length, len)
        end

        # Pre-allocate buffer with total capacity
        result = @builder.call(@rb_str_buf_new, total_length)

        # Append each part using efficient methods
        dynamic_idx = 0
        part_info.each do |info|
          if info[:type] == :static
            # Static string: use rb_str_cat with known length
            str_ptr = @builder.global_string_pointer(info[:value])
            len = LLVM::Int64.from_i(info[:length])
            @builder.call(@rb_str_cat, result, str_ptr, len)
          else
            # Dynamic string: use rb_str_buf_append
            @builder.call(@rb_str_buf_append, result, dynamic_values[dynamic_idx])
            dynamic_idx += 1
          end
        end

        @variables[inst.result_var] = result if inst.result_var
        result
      end

      def generate_symbol_lit(inst)
        # First get the ID, then convert to Symbol VALUE
        str_ptr = @builder.global_string_pointer(inst.value.to_s)
        id = @builder.call(@rb_intern, str_ptr)
        ruby_sym = @builder.call(@rb_id2sym, id)
        @variables[inst.result_var] = ruby_sym if inst.result_var
        ruby_sym
      end

      def generate_regexp_lit(inst)
        # Create Ruby String from pattern
        str_ptr = @builder.global_string_pointer(inst.pattern)
        pattern_str = @builder.call(@rb_str_new_cstr, str_ptr)

        # Create Regexp from string with options
        options = LLVM::Int32.from_i(inst.options)
        regexp = @builder.call(@rb_reg_new_str, pattern_str, options)

        @variables[inst.result_var] = regexp if inst.result_var
        regexp
      end

      def generate_bool_lit(inst)
        value = inst.value ? @qtrue : @qfalse
        @variables[inst.result_var] = value if inst.result_var
        value
      end

      def generate_nil_lit(inst)
        @variables[inst.result_var] = @qnil if inst.result_var
        @qnil
      end

      def generate_array_lit(inst)
        # Create array with capacity
        capacity = LLVM::Int64.from_i(inst.elements.size)
        ary = @builder.call(@rb_ary_new_capa, capacity)

        # Push each element (must be boxed VALUEs)
        inst.elements.each do |elem|
          elem_value = get_value_as_ruby(elem)
          @builder.call(@rb_ary_push, ary, elem_value)
        end

        @variables[inst.result_var] = ary if inst.result_var
        ary
      end

      def generate_hash_lit(inst)
        hash = @builder.call(@rb_hash_new)

        inst.pairs.each do |key, value|
          key_value = get_value_as_ruby(key)
          val_value = get_value_as_ruby(value)
          @builder.call(@rb_hash_aset, hash, key_value, val_value)
        end

        @variables[inst.result_var] = hash if inst.result_var
        hash
      end

      def generate_load_local(inst)
        var_name = inst.var.name
        type_tag = @variable_types[var_name] || :value

        # Special handling for NativeArray: don't load from alloca, use stored pointer
        if type_tag == :native_array
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :native_array
            # Also copy length metadata
            if @variables["#{var_name}_len"]
              @variables["#{inst.result_var}_len"] = @variables["#{var_name}_len"]
            end
            # Also copy NativeClass element type if present
            @native_array_class_types ||= {}
            if @native_array_class_types[var_name]
              @native_array_class_types[inst.result_var] = @native_array_class_types[var_name]
            end
          end
          return value
        end

        # Special handling for ByteBuffer: use stored pointer directly
        if type_tag == :byte_buffer
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :byte_buffer
          end
          return value
        end

        # Special handling for StringBuffer: use stored VALUE directly
        if type_tag == :string_buffer
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :string_buffer
          end
          return value
        end

        # Special handling for ByteSlice: use stored pointer directly
        if type_tag == :byte_slice
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :byte_slice
          end
          return value
        end

        # Special handling for NativeString: use stored pointer directly
        if type_tag == :native_string
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :native_string
          end
          return value
        end

        # Special handling for Slice[T]: use stored pointer directly
        if type_tag == :slice_int64 || type_tag == :slice_float64
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = type_tag
          end
          return value
        end

        # Special handling for StaticArray: use stored pointer directly
        if type_tag == :static_array
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :static_array
            # Copy type metadata
            @static_array_types ||= {}
            if @static_array_types[var_name]
              @static_array_types[inst.result_var] = @static_array_types[var_name]
            end
          end
          return value
        end

        # Special handling for NativeHash: use stored pointer directly
        if type_tag == :native_hash
          value = @variables[var_name]
          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :native_hash
            # Copy type metadata
            @native_hash_types ||= {}
            if @native_hash_types[var_name]
              @native_hash_types[inst.result_var] = @native_hash_types[var_name]
            end
          end
          return value
        end

        # Special handling for NativeClass: load pointer from alloca
        if type_tag == :native_class
          alloca = @variable_allocas[var_name]
          value = if alloca
            @builder.load2(ptr_type, alloca, "#{var_name}_ptr")
          else
            @variables[var_name] || LLVM::Pointer(LLVM::Int8).null
          end

          if inst.result_var
            @variables[inst.result_var] = value
            @variable_types[inst.result_var] = :native_class
            # Also copy class type metadata
            @native_class_types ||= {}
            if @native_class_types[var_name]
              @native_class_types[inst.result_var] = @native_class_types[var_name]
            end
          end
          return value
        end

        # Normal case: load from alloca
        alloca = @variable_allocas[var_name]
        value = if alloca
          llvm_type = case type_tag
          when :i64 then LLVM::Int64
          when :double then LLVM::Double
          when :i8 then LLVM::Int8
          else value_type
          end
          @builder.load2(llvm_type, alloca, var_name)
        else
          @variables[var_name] || @qnil
        end

        # Store with type tag for later use
        if inst.result_var
          @variables[inst.result_var] = value
          @variable_types[inst.result_var] = type_tag
        end
        value
      end

      def generate_store_local(inst)
        var_name = inst.var.name

        # Get value and its type
        value, source_type = get_value_with_type(inst.value)

        # Special handling for NativeArray: propagate the type and store pointer directly
        if source_type == :native_array
          # For NativeArray, we store the pointer and propagate the type
          @variables[var_name] = value
          @variable_types[var_name] = :native_array

          # Also copy the length metadata
          src_var = get_source_var_name(inst.value)
          if src_var && @variables["#{src_var}_len"]
            @variables["#{var_name}_len"] = @variables["#{src_var}_len"]
          end

          # Copy NativeClass element type if present
          @native_array_class_types ||= {}
          if src_var && @native_array_class_types[src_var]
            @native_array_class_types[var_name] = @native_array_class_types[src_var]
          end

          return value
        end

        # Special handling for ByteBuffer: store pointer directly
        if source_type == :byte_buffer
          @variables[var_name] = value
          @variable_types[var_name] = :byte_buffer
          return value
        end

        # Special handling for StringBuffer: store VALUE directly
        if source_type == :string_buffer
          @variables[var_name] = value
          @variable_types[var_name] = :string_buffer
          return value
        end

        # Special handling for ByteSlice: store pointer directly
        if source_type == :byte_slice
          @variables[var_name] = value
          @variable_types[var_name] = :byte_slice
          return value
        end

        # Special handling for NativeString: store pointer directly
        if source_type == :native_string
          @variables[var_name] = value
          @variable_types[var_name] = :native_string
          return value
        end

        # Special handling for Slice[T]: store pointer directly
        if source_type == :slice_int64 || source_type == :slice_float64
          @variables[var_name] = value
          @variable_types[var_name] = source_type
          return value
        end

        # Special handling for StaticArray: store pointer directly
        if source_type == :static_array
          @variables[var_name] = value
          @variable_types[var_name] = :static_array
          # Copy type metadata
          @static_array_types ||= {}
          src_var = get_source_var_name(inst.value)
          if src_var && @static_array_types[src_var]
            @static_array_types[var_name] = @static_array_types[src_var]
          end
          return value
        end

        # Special handling for NativeHash: store pointer directly
        if source_type == :native_hash
          @variables[var_name] = value
          @variable_types[var_name] = :native_hash
          # Copy type metadata
          @native_hash_types ||= {}
          src_var = get_source_var_name(inst.value)
          if src_var && @native_hash_types[src_var]
            @native_hash_types[var_name] = @native_hash_types[src_var]
          end
          return value
        end

        # Special handling for NativeClass: store pointer to alloca for loop safety
        if source_type == :native_class
          # Create alloca if not exists
          alloca = @variable_allocas[var_name]
          unless alloca
            # Need to insert at entry block for alloca
            entry_block = @current_function.basic_blocks.first
            current_block = @builder.insert_block

            # Position at start of entry block
            if entry_block.instructions.first
              @builder.position_before(entry_block.instructions.first)
            else
              @builder.position_at_end(entry_block)
            end

            alloca = @builder.alloca(ptr_type, var_name)
            @variable_allocas[var_name] = alloca

            # Restore position
            @builder.position_at_end(current_block)
          end

          # Store pointer to alloca
          @builder.store(value, alloca)

          # Also store in @variables for immediate access (before next load)
          @variables[var_name] = value
          @variable_types[var_name] = :native_class

          # Also copy the class type metadata
          src_var = get_source_var_name(inst.value)
          @native_class_types ||= {}
          if src_var && @native_class_types[src_var]
            @native_class_types[var_name] = @native_class_types[src_var]
          end

          return value
        end

        # Normal case: preserve unboxed types when possible
        # If source is unboxed (:double, :i64) and no existing target type, keep it unboxed
        target_type = @variable_types[var_name]
        if target_type.nil?
          # New variable - preserve unboxed type from source
          target_type = case source_type
          when :double, :i64, :i8
            source_type
          else
            :value
          end
        elsif target_type == :value && %i[double i64 i8].include?(source_type)
          # Upgrade from VALUE to unboxed type
          # This handles intermediate variables like `dx = x2 - x1` where the
          # type was initially unknown but unboxed arithmetic produced an unboxed result
          target_type = source_type
          # Need to recreate alloca with the new unboxed type
          @variable_allocas.delete(var_name)
        elsif %i[double i64 i8].include?(target_type) && source_type == :value && inst.value.is_a?(HIR::Phi)
          # Downgrade from unboxed to VALUE type for phi nodes with mixed types.
          # This happens when a phi with mixed types (e.g., bool + int from &&/||)
          # stores into a variable that was pre-allocated as unboxed based on static
          # type analysis. The phi resolves to :value at codegen time, so we must
          # widen the variable to :value to avoid unsafe unboxing (e.g., rb_num2long on Qfalse).
          target_type = :value
          @variable_allocas.delete(var_name)
        end

        value_to_store = convert_value(value, source_type, target_type)

        # Create or get alloca with appropriate type
        # All local variables use allocas to support block capture
        alloca = @variable_allocas[var_name]
        unless alloca
          # Create alloca at entry block for proper domination
          entry_block = @current_function.basic_blocks.first
          current_block = @builder.insert_block

          if entry_block.instructions.first
            @builder.position_before(entry_block.instructions.first)
          else
            @builder.position_at_end(entry_block)
          end

          llvm_type = case target_type
          when :double then LLVM::Double
          when :i64 then LLVM::Int64
          when :i8 then LLVM::Int8
          else value_type  # VALUE for Ruby objects
          end

          alloca = @builder.alloca(llvm_type, var_name)
          @variable_allocas[var_name] = alloca

          @builder.position_at_end(current_block)
        end

        @builder.store(value_to_store, alloca)

        @variables[var_name] = value_to_store
        @variable_types[var_name] = target_type

        # Propagate comparison result flag through variable assignments
        src_var = inst.value.respond_to?(:result_var) ? inst.value.result_var : nil
        if src_var && @comparison_result_vars.include?(src_var)
          @comparison_result_vars.add(var_name)
        end

        value_to_store
      end

      def get_source_var_name(hir_value)
        case hir_value
        when HIR::Instruction
          hir_value.result_var
        when String
          hir_value
        else
          nil
        end
      end

      def get_value_with_type(hir_value)
        case hir_value
        when HIR::LoadLocal
          # For LoadLocal: try result_var first, then fall back to var.name
          # This handles pattern-bound variables where the LoadLocal hasn't been generated yet
          if hir_value.result_var && @variables.key?(hir_value.result_var)
            value = @variables[hir_value.result_var]
            type_tag = @variable_types[hir_value.result_var] || :value
            [value, type_tag]
          else
            # Fall back to var.name (for pattern-bound variables or inliner-created refs)
            var_name = hir_value.var.name
            value = @variables[var_name] || @qnil
            type_tag = @variable_types[var_name] || :value
            [value, type_tag]
          end
        when HIR::Instruction
          if hir_value.result_var
            # Check if instruction was already generated
            if @variables.key?(hir_value.result_var)
              value = @variables[hir_value.result_var]
              type_tag = @variable_types[hir_value.result_var] || :value
              [value, type_tag]
            else
              # Instruction hasn't been generated yet - generate it now
              # This handles cases like pattern match bodies where args haven't been emitted
              generate_instruction(hir_value)
              value = @variables[hir_value.result_var] || @qnil
              type_tag = @variable_types[hir_value.result_var] || :value
              [value, type_tag]
            end
          else
            [@qnil, :value]
          end
        when String
          value = @variables[hir_value] || @qnil
          type_tag = @variable_types[hir_value] || :value
          [value, type_tag]
        else
          [@qnil, :value]
        end
      end

      def convert_value(value, from_type, to_type)
        return value if from_type == to_type

        case [from_type, to_type]
        when [:value, :i64]
          @builder.call(@rb_num2long, value)
        when [:value, :double]
          @builder.call(@rb_num2dbl, value)
        when [:value, :i8]
          # RTEST: (value & ~Qnil) != 0
          not_qnil = @builder.xor(@qnil, LLVM::Int64.from_i(-1))
          masked = @builder.and(value, not_qnil)
          is_truthy = @builder.icmp(:ne, masked, LLVM::Int64.from_i(0))
          @builder.zext(is_truthy, LLVM::Int8)
        when [:i64, :value]
          @builder.call(@rb_int2inum, value)
        when [:double, :value]
          @builder.call(@rb_float_new, value)
        when [:i8, :value]
          # Convert bool to Ruby true/false
          is_true = @builder.icmp(:ne, value, LLVM::Int8.from_i(0))
          @builder.select(is_true, @qtrue, @qfalse)
        when [:i64, :double]
          @builder.si2fp(value, LLVM::Double)
        when [:double, :i64]
          @builder.fp2si(value, LLVM::Int64)
        when [:i8, :i64]
          @builder.zext(value, LLVM::Int64)
        when [:i64, :i8]
          @builder.trunc(value, LLVM::Int8)
        else
          value
        end
      end

      # Unboxed type tags that can be used in optimized phi nodes
      UNBOXED_TYPE_TAGS = [:i64, :double, :i8].freeze

      # Compute the common type tag for phi node incoming values
      # Returns an unboxed type if all values share it, otherwise :value
      def compute_phi_type_tag(incoming_data)
        return :value if incoming_data.empty?

        type_tags = incoming_data.map { |_, _, tag| tag }.uniq

        # If all values have the same unboxed type, use it
        if type_tags.size == 1 && UNBOXED_TYPE_TAGS.include?(type_tags.first)
          return type_tags.first
        end

        # If mixing :i64 and :double, promote to :double
        if type_tags.sort == [:double, :i64]
          return :double
        end

        # Otherwise, box everything
        :value
      end

      # Convert type tag to LLVM type
      def type_tag_to_llvm_type(type_tag)
        case type_tag
        when :i64 then LLVM::Int64
        when :double then LLVM::Double
        when :i8 then LLVM::Int8
        else value_type
        end
      end

      # Get the LLVM value and type tag for an instruction result
      def get_result_with_type(llvm_value, hir_inst)
        if hir_inst.respond_to?(:result_var) && hir_inst.result_var
          type_tag = @variable_types[hir_inst.result_var] || :value
          [llvm_value, type_tag]
        else
          infer_type_from_llvm_value(llvm_value)
        end
      end

      # Infer type tag from LLVM value (useful for constants)
      def infer_type_from_llvm_value(val)
        return [@qnil, :value] if val.nil?

        if val.is_a?(LLVM::Constant)
          case val.type
          when LLVM::Int64 then [val, :i64]
          when LLVM::Double then [val, :double]
          when LLVM::Int8 then [val, :i8]
          else [val, :value]
          end
        else
          [val, :value]
        end
      end

      # Convert phi incoming values to target type, inserting conversions in source blocks
      # This ensures phi nodes are at the top of merge blocks (LLVM requirement)
      def convert_phi_incoming_values(incoming_data, target_type_tag, merge_block)
        result = {}

        incoming_data.each do |block, value, type_tag|
          if type_tag == target_type_tag
            # No conversion needed
            result[block] = value
          else
            # Need to insert conversion in the source block before the br
            # Find the last instruction (terminator: br, ret, etc.)
            instructions_array = block.instructions.to_a
            terminator = instructions_array.last

            if terminator
              # Position before the terminator to insert conversion
              @builder.position_before(terminator)
              converted_value = convert_value(value, type_tag, target_type_tag)
              result[block] = converted_value
            else
              # No terminator yet, just convert (shouldn't normally happen)
              result[block] = convert_value(value, type_tag, target_type_tag)
            end
          end
        end

        result
      end

      def get_or_create_alloca(var_name)
        @variable_allocas[var_name]
      end

      def generate_load_instance_var(inst)
        # Check if we're inside a NativeClass method
        if @current_native_class
          return generate_native_self_field_get(inst)
        end

        # Get self (first parameter)
        func = @builder.insert_block.parent
        self_value = func.params[0]

        # Get ivar ID
        ivar_name_ptr = @builder.global_string_pointer(inst.name)
        ivar_id = @builder.call(@rb_intern, ivar_name_ptr)

        # rb_ivar_get(self, id)
        result = @builder.call(@rb_ivar_get, self_value, ivar_id)
        @variables[inst.result_var] = result if inst.result_var
        result
      end

      def generate_store_instance_var(inst)
        # Check if we're inside a NativeClass method
        if @current_native_class
          return generate_native_self_field_set(inst)
        end

        # Get self (first parameter)
        func = @builder.insert_block.parent
        self_value = func.params[0]

        # Get ivar ID
        ivar_name_ptr = @builder.global_string_pointer(inst.name)
        ivar_id = @builder.call(@rb_intern, ivar_name_ptr)

        # Get value (must be boxed VALUE for CRuby API)
        value = get_value_as_ruby(inst.value)

        # rb_ivar_set(self, id, value)
        @builder.call(@rb_ivar_set, self_value, ivar_id, value)
        value
      end

      def generate_load_class_var(inst)
        # Get class VALUE
        klass_value = get_current_class_value

        # Get cvar ID
        cvar_name_ptr = @builder.global_string_pointer(inst.name)
        cvar_id = @builder.call(@rb_intern, cvar_name_ptr)

        # rb_cvar_get(klass, id)
        result = @builder.call(@rb_cvar_get, klass_value, cvar_id)
        @variables[inst.result_var] = result if inst.result_var
        result
      end

      def generate_store_class_var(inst)
        # Get class VALUE
        klass_value = get_current_class_value

        # Get cvar ID
        cvar_name_ptr = @builder.global_string_pointer(inst.name)
        cvar_id = @builder.call(@rb_intern, cvar_name_ptr)

        # Get value (must be boxed VALUE for CRuby API)
        value = get_value_as_ruby(inst.value)

        # rb_cvar_set(klass, id, value)
        @builder.call(@rb_cvar_set, klass_value, cvar_id, value)
        value
      end

      def generate_store_constant(inst)
        # Get value (must be boxed VALUE for CRuby API)
        value = get_value_as_ruby(inst.value)

        # Determine scope (module/class or top-level Object)
        if inst.scope
          # Get the module/class VALUE
          scope_name_ptr = @builder.global_string_pointer(inst.scope.to_s)
          scope_id = @builder.call(@rb_intern, scope_name_ptr)
          rb_cobject = @builder.load2(value_type, @rb_cObject, "rb_cObject")
          scope_value = @builder.call(@rb_const_get, rb_cobject, scope_id)
        else
          # Top-level: use rb_cObject
          scope_value = @builder.load2(value_type, @rb_cObject, "rb_cObject")
        end

        # Get constant ID
        const_name_ptr = @builder.global_string_pointer(inst.name)
        const_id = @builder.call(@rb_intern, const_name_ptr)

        # rb_const_set(scope, id, value)
        @builder.call(@rb_const_set, scope_value, const_id, value)
        value
      end

      # Get the VALUE representing the current class for class variable access
      def get_current_class_value
        func = @builder.insert_block.parent

        # Check if this is a class method (singleton method)
        if @current_hir_func&.class_method?
          # For class methods, self IS the class
          func.params[0]
        elsif @current_hir_func&.owner_class
          # For instance methods, get the class from self using rb_class_of
          self_value = func.params[0]
          @builder.call(@rb_class_of, self_value)
        else
          # Top-level: use rb_cObject (need to load the global)
          @builder.load2(value_type, @rb_cObject, "rb_cObject")
        end
      end

      # Load field from self in a NativeClass method (unboxed access)
      def generate_native_self_field_get(inst)
        class_type = @current_native_class
        field_name = inst.name.delete_prefix("@").to_sym

        base_index = class_type.field_index(field_name)
        return generate_fallback_ivar_get(inst) unless base_index

        # Adjust for vptr if using vtable
        field_index = class_uses_vtable?(class_type) ? base_index + 1 : base_index
        field_type_tag = class_type.llvm_field_type_tag(field_name)
        llvm_struct = get_or_create_native_class_struct(class_type)

        # Get self pointer (first parameter)
        func = @builder.insert_block.parent
        self_ptr = func.params[0]

        # Determine LLVM type for the field
        llvm_field_type = case field_type_tag
        when :i64 then LLVM::Int64
        when :double then LLVM::Double
        when :i8 then LLVM::Int8
        else value_type
        end

        # GEP to get field pointer
        field_ptr = @builder.struct_gep2(llvm_struct, self_ptr, field_index, "#{field_name}_ptr")

        # Load field value
        field_value = @builder.load2(llvm_field_type, field_ptr, "#{field_name}_val")

        if inst.result_var
          @variables[inst.result_var] = field_value
          @variable_types[inst.result_var] = field_type_tag
        end

        field_value
      end

      # Store field to self in a NativeClass method (unboxed access)
      def generate_native_self_field_set(inst)
        class_type = @current_native_class
        field_name = inst.name.delete_prefix("@").to_sym

        base_index = class_type.field_index(field_name)
        return generate_fallback_ivar_set(inst) unless base_index

        # Adjust for vptr if using vtable
        field_index = class_uses_vtable?(class_type) ? base_index + 1 : base_index
        field_type_tag = class_type.llvm_field_type_tag(field_name)
        llvm_struct = get_or_create_native_class_struct(class_type)

        # Get self pointer (first parameter)
        func = @builder.insert_block.parent
        self_ptr = func.params[0]

        # Get value to store
        store_value, value_type = get_value_with_type(inst.value)
        converted_value = convert_value(store_value, value_type, field_type_tag)

        # GEP to get field pointer
        field_ptr = @builder.struct_gep2(llvm_struct, self_ptr, field_index, "#{field_name}_ptr")

        # Store value
        @builder.store(converted_value, field_ptr)

        converted_value
      end

      # Fallback to rb_ivar_get when field not found
      def generate_fallback_ivar_get(inst)
        func = @builder.insert_block.parent
        self_value = func.params[0]
        ivar_name_ptr = @builder.global_string_pointer(inst.name)
        ivar_id = @builder.call(@rb_intern, ivar_name_ptr)
        result = @builder.call(@rb_ivar_get, self_value, ivar_id)
        @variables[inst.result_var] = result if inst.result_var
        result
      end

      # Fallback to rb_ivar_set when field not found
      def generate_fallback_ivar_set(inst)
        func = @builder.insert_block.parent
        self_value = func.params[0]
        ivar_name_ptr = @builder.global_string_pointer(inst.name)
        ivar_id = @builder.call(@rb_intern, ivar_name_ptr)
        value = get_value_as_ruby(inst.value)
        @builder.call(@rb_ivar_set, self_value, ivar_id, value)
        value
      end

      def generate_call(inst)
        # Safe navigation operator (&.)
        if inst.safe_navigation
          return generate_safe_navigation_call(inst)
        end

        # Handle special methods
        if inst.method_name == "block_given?"
          # Use rb_block_given_p() which returns int (0 or non-zero)
          int_result = @builder.call(@rb_block_given_p)
          # Convert to Ruby boolean
          is_given = @builder.icmp(:ne, int_result, LLVM::Int32.from_i(0))
          result = @builder.select(is_given, @qtrue, @qfalse)
          @variables[inst.result_var] = result if inst.result_var
          return result
        end

        # Handle Proc#call - optimize calls on Proc objects
        if inst.method_name == "call" && proc_type?(get_type(inst.receiver))
          result = generate_proc_call_from_call_inst(inst)
          @variables[inst.result_var] = result if inst.result_var
          return result
        end

        # Handle NativeArray method calls
        # Check both HIR type and tracked variable type
        receiver_type = get_type(inst.receiver)
        native_array_type = detect_native_array_type(inst.receiver, receiver_type)
        if native_array_type
          result = generate_native_array_call(inst, native_array_type)
          return result if result
        end

        # Try unboxed unary method optimization (abs, even?, odd?, etc.)
        if can_use_unboxed_unary?(inst)
          return generate_unboxed_unary(inst)
        end

        # Try unboxed arithmetic optimization
        if can_use_unboxed_arithmetic?(inst)
          # generate_unboxed_arithmetic sets @variables and @variable_types internally
          return generate_unboxed_arithmetic(inst)
        end

        # Check for union type dispatch (runtime type checking)
        if (union_dispatch_info = inst.instance_variable_get(:@union_dispatch_info))
          result = generate_union_dispatch_call(inst, union_dispatch_info)
          @variables[inst.result_var] = result if inst.result_var
          @variable_types[inst.result_var] = :value  # Union results are always boxed
          return result
        end

        # Skip direct call optimizations when splat args are present
        has_splat = inst.args.any? { |a| a.is_a?(HIR::SplatArg) }

        unless has_splat
          # Check for monomorphized function call (direct call optimization)
          if (specialized_target = inst.instance_variable_get(:@specialized_target))
            result = generate_direct_call(inst, specialized_target)
            @variables[inst.result_var] = result if inst.result_var
            return result
          end

          # Check if we can call a local function directly
          local_func = @functions[inst.method_name]
          if local_func && self_receiver?(inst.receiver)
            result = generate_direct_call(inst, inst.method_name)
            @variables[inst.result_var] = result if inst.result_var
            return result
          end
        end

        # Try builtin method direct call (devirtualization)
        receiver_type = get_type(inst.receiver)
        builtin = lookup_builtin_method(receiver_type, inst.method_name)

        # If no builtin found but we have a block, try to find by method name
        # This handles cases where type is unresolved (type variable) but method is known
        if builtin.nil? && inst.block
          builtin = lookup_block_iterator_by_name(inst.method_name)
        end

        if builtin
          # Check if this is a block iterator method with a block
          if builtin[:conv] == :block_iterator && inst.block
            result = generate_block_iterator_call(inst, builtin)
            @variables[inst.result_var] = result if inst.result_var
            return result
          elsif builtin[:conv] == :ary_entry && inst.args.size == 1
            # Array#[] - rb_ary_entry(VALUE ary, long offset)
            result = generate_array_index_get(inst)
            @variables[inst.result_var] = result if inst.result_var
            return result
          elsif builtin[:conv] == :ary_store && inst.args.size == 2
            # Array#[]= - rb_ary_store(VALUE ary, long idx, VALUE val)
            result = generate_array_index_set(inst)
            @variables[inst.result_var] = result if inst.result_var
            return result
          elsif builtin[:conv] == :ary_delete_at && inst.args.size == 1
            # Array#delete_at - rb_ary_delete_at(VALUE ary, long pos)
            result = generate_array_delete_at(inst)
            @variables[inst.result_var] = result if inst.result_var
            return result
          elsif builtin[:conv] == :simple && builtin[:arity] == inst.args.size
            result = generate_builtin_call(inst, builtin)
            @variables[inst.result_var] = result if inst.result_var
            return result
          end
        end

        # Get receiver as Ruby VALUE (box if needed)
        receiver = get_value_as_ruby(inst.receiver)

        # Get method ID
        method_ptr = @builder.global_string_pointer(inst.method_name)
        method_id = @builder.call(@rb_intern, method_ptr)

        # Build keyword arguments hash if present
        kwargs_hash = nil
        if inst.has_keyword_args?
          kwargs_hash = build_keyword_args_hash(inst.keyword_args)
        end

        # Check if any argument is a splat
        has_splat = inst.args.any? { |a| a.is_a?(HIR::SplatArg) }

        if has_splat
          # Use rb_apply with a combined args array
          result = generate_splat_call(inst, receiver, method_id, kwargs_hash)
        else
          # Calculate total argc (regular args + optional kwargs hash)
          total_args = inst.args.dup
          total_args << kwargs_hash if kwargs_hash

          argc = LLVM::Int32.from_i(total_args.size)

          if total_args.empty?
            # No arguments - pass null pointer
            argv = LLVM::Pointer(value_type).null
          else
            # Allocate array on stack for arguments
            argv = @builder.alloca(LLVM::Array(value_type, total_args.size))

            total_args.each_with_index do |arg, i|
              # Get argument as Ruby VALUE (box if needed)
              # kwargs_hash is already a VALUE, others need conversion
              arg_value = arg.is_a?(LLVM::Value) ? arg : get_value_as_ruby(arg)
              ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(arg_value, ptr)
            end

            # Cast to VALUE*
            argv = @builder.bit_cast(argv, LLVM::Pointer(value_type))
          end

          result = @builder.call(@rb_funcallv, receiver, method_id, argc, argv)
        end

        @variables[inst.result_var] = result if inst.result_var
        result
      end

      # Generate call with splat expansion using rb_apply
      def generate_splat_call(inst, receiver, method_id, kwargs_hash)
        # Build a Ruby Array containing all arguments
        args_array = @builder.call(@rb_ary_new)

        inst.args.each do |arg|
          if arg.is_a?(HIR::SplatArg)
            # Concat the splat array into the args array
            splat_value = get_value_as_ruby(arg.expression)
            # Convert to array if not already (rb_ary_to_ary)
            @builder.call(@rb_ary_concat, args_array, splat_value)
          else
            # Push regular arg
            arg_value = get_value_as_ruby(arg)
            @builder.call(@rb_ary_push, args_array, arg_value)
          end
        end

        # Append kwargs hash if present
        if kwargs_hash
          @builder.call(@rb_ary_push, args_array, kwargs_hash)
        end

        @builder.call(@rb_apply, receiver, method_id, args_array)
      end

      # Generate safe navigation call (obj&.method)
      # If receiver is nil, return nil without calling the method
      def generate_safe_navigation_call(inst)
        func = @builder.insert_block.parent

        # Get receiver as VALUE
        receiver = get_value_as_ruby(inst.receiver)

        # Compare receiver with Qnil
        is_nil = @builder.icmp(:eq, receiver, @qnil)

        safe_call_bb = func.basic_blocks.append("safe_call")
        safe_nil_bb = func.basic_blocks.append("safe_nil")
        safe_merge_bb = func.basic_blocks.append("safe_merge")

        @builder.cond(is_nil, safe_nil_bb, safe_call_bb)

        # Non-nil path: perform the normal call
        @builder.position_at_end(safe_call_bb)
        # Temporarily clear safe_navigation to avoid infinite recursion
        original_safe_nav = inst.instance_variable_get(:@safe_navigation)
        inst.instance_variable_set(:@safe_navigation, false)
        call_result = generate_call(inst)
        inst.instance_variable_set(:@safe_navigation, original_safe_nav)
        # Get the current block (may have changed during generate_call)
        call_exit_bb = @builder.insert_block
        @builder.br(safe_merge_bb)

        # Nil path: return nil
        @builder.position_at_end(safe_nil_bb)
        @builder.br(safe_merge_bb)

        # Merge
        @builder.position_at_end(safe_merge_bb)
        phi = @builder.phi(value_type, { call_exit_bb => call_result, safe_nil_bb => @qnil })
        @variables[inst.result_var] = phi if inst.result_var
        phi
      end

      # Generate a call with union type dispatch
      # Creates runtime type checks and dispatches to specialized functions
      def generate_union_dispatch_call(inst, dispatch_info)
        func = @builder.insert_block.parent
        specializations = dispatch_info[:specializations]
        union_positions = dispatch_info[:union_positions]
        target = dispatch_info[:target]

        # Get arguments as Ruby VALUEs
        arg_values = inst.args.map { |arg| get_value_as_ruby(arg) }

        # Get self/receiver
        receiver = get_value_as_ruby(inst.receiver)

        # Create blocks for each specialization check and fallback
        spec_list = specializations.to_a
        check_blocks = spec_list.map.with_index { |_, i| func.basic_blocks.append("union_check_#{i}") }
        match_blocks = spec_list.map.with_index { |_, i| func.basic_blocks.append("union_match_#{i}") }
        fallback_block = func.basic_blocks.append("union_fallback")
        merge_block = func.basic_blocks.append("union_merge")

        # Jump to first check
        @builder.br(check_blocks[0])

        # Track results for PHI node
        results = []

        spec_list.each_with_index do |(type_strs, specialized_name), idx|
          # Position at check block
          @builder.position_at_end(check_blocks[idx])

          # Generate type checks for each union position
          all_match = generate_union_type_checks(arg_values, type_strs, union_positions)

          # Next block is either next check or fallback
          next_block = idx < spec_list.size - 1 ? check_blocks[idx + 1] : fallback_block

          @builder.cond(all_match, match_blocks[idx], next_block)

          # Position at match block and call specialized function
          @builder.position_at_end(match_blocks[idx])

          specialized_func = @functions[specialized_name]
          if specialized_func
            # Call the specialized function
            call_args = [receiver] + arg_values
            result = @builder.call(specialized_func, *call_args)

            # Box result if needed (specialized functions may return unboxed values)
            result = box_if_unboxed(result, specialized_func)
          else
            # Fallback to rb_funcallv if specialized function not found
            result = generate_funcallv(receiver, target.to_s, arg_values)
          end

          results << [result, match_blocks[idx]]
          @builder.br(merge_block)
        end

        # Generate fallback block (use rb_funcallv)
        @builder.position_at_end(fallback_block)
        fallback_result = generate_funcallv(receiver, target.to_s, arg_values)
        results << [fallback_result, fallback_block]
        @builder.br(merge_block)

        # Generate merge block with PHI node
        @builder.position_at_end(merge_block)
        phi_incoming = {}
        results.each do |(result, block)|
          phi_incoming[block] = result
        end
        @builder.phi(value_type, phi_incoming, "union_result")
      end

      # Generate type checks for union positions
      # Returns an i1 value that is true if all type checks pass
      def generate_union_type_checks(arg_values, type_strs, union_positions)
        checks = union_positions.map do |pos|
          expected_type = type_strs[pos]
          arg_value = arg_values[pos]
          generate_single_type_check(arg_value, expected_type)
        end

        # AND all checks together
        if checks.empty?
          LLVM::TRUE
        else
          checks.reduce { |acc, check| @builder.and(acc, check) }
        end
      end

      # Generate a single type check
      # Returns an i1 value that is true if the value matches the expected type
      def generate_single_type_check(value, type_str)
        # Get the Ruby class constant for the type
        class_value = get_ruby_class_for_type(type_str)

        # Call rb_obj_is_kind_of
        is_kind = @builder.call(@rb_obj_is_kind_of, value, class_value)

        # rb_obj_is_kind_of returns Qtrue/Qfalse, convert to i1
        @builder.icmp(:ne, is_kind, @qfalse)
      end

      # Get the Ruby class VALUE for a type name
      def get_ruby_class_for_type(type_str)
        # Use predefined class globals for common types
        case type_str
        when "Integer"
          @builder.load2(value_type, @rb_cInteger, "rb_cInteger")
        when "Float"
          @builder.load2(value_type, @rb_cFloat, "rb_cFloat")
        when "String"
          @builder.load2(value_type, @rb_cString, "rb_cString")
        when "Symbol"
          @builder.load2(value_type, @rb_cSymbol, "rb_cSymbol")
        when "Array"
          @builder.load2(value_type, @rb_cArray, "rb_cArray")
        when "Hash"
          @builder.load2(value_type, @rb_cHash, "rb_cHash")
        when "NilClass"
          @builder.load2(value_type, @rb_cNilClass, "rb_cNilClass")
        when "TrueClass"
          @builder.load2(value_type, @rb_cTrueClass, "rb_cTrueClass")
        when "FalseClass"
          @builder.load2(value_type, @rb_cFalseClass, "rb_cFalseClass")
        else
          # For other types, use rb_path2class
          type_ptr = @builder.global_string_pointer(type_str)
          @builder.call(@rb_path2class, type_ptr)
        end
      end

      # Generate a rb_funcallv call as fallback
      def generate_funcallv(receiver, method_name, arg_values)
        method_ptr = @builder.global_string_pointer(method_name)
        method_id = @builder.call(@rb_intern, method_ptr)

        argc = LLVM::Int32.from_i(arg_values.size)

        if arg_values.empty?
          argv = LLVM::Pointer(value_type).null
        else
          argv = @builder.alloca(LLVM::Array(value_type, arg_values.size))
          arg_values.each_with_index do |arg, i|
            ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
            @builder.store(arg, ptr)
          end
          argv = @builder.bit_cast(argv, LLVM::Pointer(value_type))
        end

        @builder.call(@rb_funcallv, receiver, method_id, argc, argv)
      end

      # Box a value if it's unboxed (based on function return type analysis)
      def box_if_unboxed(result, func)
        # Check the return type from the function's LLVM type
        return_type = func.function_type.return_type

        if return_type == LLVM::Int64
          # Could be either unboxed i64 or VALUE - check if it's a known unboxed function
          # For now, assume specialized functions return VALUE
          result
        elsif return_type == LLVM::Double
          # Unboxed double, box it
          @builder.call(@rb_float_new, result)
        else
          result
        end
      end

      # Build a Ruby Hash from keyword arguments
      # Returns an LLVM VALUE representing the Hash
      def build_keyword_args_hash(keyword_args)
        # Create new hash
        hash = @builder.call(@rb_hash_new)

        # Add each keyword argument
        keyword_args.each do |key_name, value_inst|
          # Convert key name to Ruby Symbol
          key_str_ptr = @builder.global_string_pointer(key_name.to_s)
          key_id = @builder.call(@rb_intern, key_str_ptr)
          key_sym = @builder.call(@rb_id2sym, key_id)

          # Get value as Ruby VALUE
          value = get_value_as_ruby(value_inst)

          # Set key-value pair
          @builder.call(@rb_hash_aset, hash, key_sym, value)
        end

        hash
      end

      # Generate a call with block using rb_block_call
      # rb_block_call(VALUE obj, ID mid, int argc, const VALUE *argv,
      #               rb_block_call_func_t proc, VALUE data2)
      def generate_block_iterator_call(inst, builtin)
        # Try inline loop optimization for reduce/inject
        if [:reduce, :inject].include?(inst.method_name.to_sym) && can_inline_reduce?(inst)
          result = generate_inline_reduce(inst)
          return result if result
        end

        # Try inline loop optimization for each/map/select
        if [:each, :map, :collect, :select, :filter, :reject].include?(inst.method_name.to_sym) && can_inline_array_loop?(inst)
          result = generate_inline_array_loop(inst)
          return result if result
        end

        # Try inline optimization for Integer#times
        if inst.method_name.to_sym == :times && can_inline_integer_times?(inst)
          result = generate_inline_integer_times(inst)
          return result if result
        end

        # Try inline optimization for find/detect (early termination)
        if [:find, :detect].include?(inst.method_name.to_sym) && can_inline_array_predicate?(inst)
          result = generate_inline_array_find(inst)
          return result if result
        end

        # Try inline optimization for any?/all?/none? (early termination)
        if [:any?, :all?, :none?].include?(inst.method_name.to_sym) && can_inline_array_predicate?(inst)
          result = generate_inline_array_predicate(inst)
          return result if result
        end

        # Try inline optimization for Range enumerable methods
        if can_inline_range_loop?(inst)
          method_sym = inst.method_name.to_sym
          if method_sym == :each
            result = generate_inline_range_each(inst)
            return result if result
          elsif [:map, :collect].include?(method_sym)
            result = generate_inline_range_map(inst)
            return result if result
          elsif [:select, :filter].include?(method_sym)
            result = generate_inline_range_select(inst)
            return result if result
          elsif [:reduce, :inject].include?(method_sym)
            result = generate_inline_range_reduce(inst)
            return result if result
          end
        end

        # Fallback to rb_block_call
        generate_rb_block_call(inst, builtin)
      end

      # Check if reduce/inject can be inlined
      def can_inline_reduce?(inst)
        # Ensure we're in a valid function context
        return false unless @builder&.insert_block

        return false unless inst.block
        return false unless inst.block.params.size == 2  # |acc, elem|

        # Check if receiver type is Array
        receiver_type = inst.receiver.respond_to?(:type) ? inst.receiver.type : nil
        return false unless is_array_type?(receiver_type)

        # Check block body is simple (single basic block with simple operations)
        return false unless inst.block.body.is_a?(::Array) && inst.block.body.size == 1

        true
      end

      # Check if each/map/select can be inlined
      def can_inline_array_loop?(inst)
        # Ensure we're in a valid function context
        return false unless @builder&.insert_block

        return false unless inst.block
        return false unless inst.block.params.size == 1  # |elem|

        # Check if receiver type is Array
        receiver_type = inst.receiver.respond_to?(:type) ? inst.receiver.type : nil
        return false unless is_array_type?(receiver_type)

        true
      end

      # Check if a type is an Array type
      def is_array_type?(type)
        return false unless type

        # ClassInstance with name :Array
        if type.is_a?(TypeChecker::Types::ClassInstance) && type.name == :Array
          return true
        end

        false
      end

      # Get the element type from an Array type
      # Returns :i64 for Integer, :double for Float, :value for others
      def get_array_element_unboxed_type(type)
        return :value unless type
        return :value unless type.is_a?(TypeChecker::Types::ClassInstance) && type.name == :Array
        return :value unless type.type_args && !type.type_args.empty?

        elem_type = type.type_args.first
        case elem_type
        when TypeChecker::Types::ClassInstance
          case elem_type.name
          when :Integer then :i64
          when :Float then :double
          else :value
          end
        else
          :value
        end
      end

      # Generate inline reduce loop instead of rb_block_call
      # This eliminates callback overhead for simple accumulator patterns
      # When element type is Integer/Float, uses unboxed arithmetic for 2-5x speedup
      def generate_inline_reduce(inst)
        receiver = get_value_as_ruby(inst.receiver)
        block = inst.block
        acc_param = block.params[0].name   # accumulator param name
        elem_param = block.params[1].name  # element param name

        # Detect element type for unboxed optimization
        receiver_type = inst.receiver.respond_to?(:type) ? inst.receiver.type : nil
        elem_unboxed_type = get_array_element_unboxed_type(receiver_type)
        use_unboxed = elem_unboxed_type != :value

        # Get initial value
        initial_value = if inst.args.any?
          get_value_as_ruby(inst.args.first)
        else
          @qnil
        end

        # Get array length
        length_id = @builder.call(@rb_intern, @builder.global_string_pointer("length"))
        length_value = @builder.call(@rb_funcallv, receiver, length_id, LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
        arr_len = @builder.call(@rb_num2long, length_value)

        # Determine accumulator type and allocate
        if use_unboxed
          llvm_type = elem_unboxed_type == :i64 ? LLVM::Int64 : LLVM::Double
          acc_alloca = @builder.alloca(llvm_type, "reduce_acc_unboxed")
          # Unbox initial value
          initial_unboxed = if elem_unboxed_type == :i64
            @builder.call(@rb_num2long, initial_value)
          else
            @builder.call(@rb_num2dbl, initial_value)
          end
          @builder.store(initial_unboxed, acc_alloca)
        else
          acc_alloca = @builder.alloca(value_type, "reduce_acc")
          @builder.store(initial_value, acc_alloca)
        end

        idx_alloca = @builder.alloca(LLVM::Int64, "reduce_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("reduce_cond")
        loop_body = func.basic_blocks.append("reduce_body")
        loop_end = func.basic_blocks.append("reduce_end")

        @builder.br(loop_cond)

        # Loop condition: idx < len
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Get current element (always as VALUE first)
        elem_value = @builder.call(@rb_ary_entry, receiver, current_idx)

        # Load accumulator and prepare variables
        if use_unboxed
          llvm_type = elem_unboxed_type == :i64 ? LLVM::Int64 : LLVM::Double
          acc_unboxed = @builder.load2(llvm_type, acc_alloca, "acc_unboxed")
          # Unbox element
          elem_unboxed = if elem_unboxed_type == :i64
            @builder.call(@rb_num2long, elem_value)
          else
            @builder.call(@rb_num2dbl, elem_value)
          end

          # Set up variables with unboxed types
          saved_vars = @variables.dup
          saved_types = @variable_types.dup
          saved_allocas = @variable_allocas.dup
          @variables[acc_param] = acc_unboxed
          @variables[elem_param] = elem_unboxed
          @variable_types[acc_param] = elem_unboxed_type
          @variable_types[elem_param] = elem_unboxed_type
          @variable_allocas.delete(acc_param)
          @variable_allocas.delete(elem_param)
        else
          acc = @builder.load2(value_type, acc_alloca, "acc")
          saved_vars = @variables.dup
          saved_types = @variable_types.dup
          saved_allocas = @variable_allocas.dup
          @variables[acc_param] = acc
          @variables[elem_param] = elem_value
          @variable_types[acc_param] = :value
          @variable_types[elem_param] = :value
          @variable_allocas.delete(acc_param)
          @variable_allocas.delete(elem_param)
        end

        # Generate block body instructions
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            body_result = generate_instruction(body_inst)
          end
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Store result back to accumulator
        new_acc = body_result || (use_unboxed ? (elem_unboxed_type == :i64 ? LLVM::Int64.from_i(0) : LLVM::Double.from_f(0.0)) : @qnil)

        if use_unboxed
          # Keep unboxed throughout the loop
          llvm_type = elem_unboxed_type == :i64 ? LLVM::Int64 : LLVM::Double
          # Ensure result is unboxed
          if new_acc.is_a?(LLVM::Value)
            if new_acc.type == llvm_type
              @builder.store(new_acc, acc_alloca)
            elsif new_acc.type == value_type
              # Need to unbox the result
              unboxed_result = if elem_unboxed_type == :i64
                @builder.call(@rb_num2long, new_acc)
              else
                @builder.call(@rb_num2dbl, new_acc)
              end
              @builder.store(unboxed_result, acc_alloca)
            else
              # Type mismatch - convert
              @builder.store(new_acc, acc_alloca)
            end
          end
        else
          # Box if needed
          if new_acc.is_a?(LLVM::Value) && new_acc.type == LLVM::Double
            new_acc = @builder.call(@rb_float_new, new_acc)
          end
          @builder.store(new_acc, acc_alloca)
        end

        # Increment index
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: return final result
        @builder.position_at_end(loop_end)
        if use_unboxed
          llvm_type = elem_unboxed_type == :i64 ? LLVM::Int64 : LLVM::Double
          final_unboxed = @builder.load2(llvm_type, acc_alloca, "reduce_result_unboxed")
          # Box the final result
          if elem_unboxed_type == :i64
            @builder.call(@rb_int2inum, final_unboxed)
          else
            @builder.call(@rb_float_new, final_unboxed)
          end
        else
          @builder.load2(value_type, acc_alloca, "reduce_result")
        end
      end

      # Generate inline array loop for each/map/select
      # When element type is Integer/Float, uses unboxed arithmetic for speedup
      def generate_inline_array_loop(inst)
        receiver = get_value_as_ruby(inst.receiver)
        block = inst.block
        elem_param = block.params[0].name
        method_sym = inst.method_name.to_sym

        # Detect element type for unboxed optimization
        receiver_type = inst.receiver.respond_to?(:type) ? inst.receiver.type : nil
        elem_unboxed_type = get_array_element_unboxed_type(receiver_type)
        # Use unboxed for map/collect/select/filter where block does arithmetic
        use_unboxed = elem_unboxed_type != :value && [:map, :collect, :select, :filter].include?(method_sym)

        # Get array length
        length_id = @builder.call(@rb_intern, @builder.global_string_pointer("length"))
        length_value = @builder.call(@rb_funcallv, receiver, length_id, LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
        arr_len = @builder.call(@rb_num2long, length_value)

        # Allocate index
        idx_alloca = @builder.alloca(LLVM::Int64, "loop_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # For map/select, create result array
        result_array = nil
        if [:map, :collect, :select, :filter, :reject].include?(method_sym)
          result_array = @builder.call(@rb_ary_new)
        end

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("#{method_sym}_cond")
        loop_body = func.basic_blocks.append("#{method_sym}_body")
        loop_end = func.basic_blocks.append("#{method_sym}_end")

        @builder.br(loop_cond)

        # Loop condition: idx < len
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Get current element (always as VALUE first)
        elem_value = @builder.call(@rb_ary_entry, receiver, current_idx)

        # Set up variables for block body
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        if use_unboxed
          # Unbox element for arithmetic
          elem_unboxed = if elem_unboxed_type == :i64
            @builder.call(@rb_num2long, elem_value)
          else
            @builder.call(@rb_num2dbl, elem_value)
          end
          @variables[elem_param] = elem_unboxed
          @variable_types[elem_param] = elem_unboxed_type
        else
          @variables[elem_param] = elem_value
          @variable_types[elem_param] = :value
        end
        @variable_allocas.delete(elem_param)

        # Generate block body instructions
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            body_result = generate_instruction(body_inst)
          end
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Handle result based on method type
        case method_sym
        when :map, :collect
          # Push block result to result array (box if unboxed)
          mapped_val = if body_result
            if use_unboxed && body_result.is_a?(LLVM::Value)
              if body_result.type == LLVM::Int64
                @builder.call(@rb_int2inum, body_result)
              elsif body_result.type == LLVM::Double
                @builder.call(@rb_float_new, body_result)
              else
                ensure_ruby_value(body_result)
              end
            else
              ensure_ruby_value(body_result)
            end
          else
            @qnil
          end
          @builder.call(@rb_ary_push, result_array, mapped_val)
        when :select, :filter
          # Push element if block returns truthy
          # Handle unboxed results (e.g., x % 2 returns i64)
          should_include = if body_result.is_a?(LLVM::Value)
            if body_result.type == LLVM::Int64
              # Unboxed i64: truthy if non-zero (for conditions like x % 2 == 0)
              @builder.icmp(:ne, body_result, LLVM::Int64.from_i(0))
            elsif body_result.type == LLVM::Int1
              # Already a boolean
              body_result
            else
              # Boxed VALUE: check for truthy
              select_val = ensure_ruby_value(body_result)
              is_truthy = @builder.icmp(:ne, select_val, @qfalse)
              is_not_nil = @builder.icmp(:ne, select_val, @qnil)
              @builder.and(is_truthy, is_not_nil)
            end
          else
            # Default: not truthy
            LLVM::Int1.from_i(0)
          end

          # Conditional push
          then_block = func.basic_blocks.append("select_push")
          cont_block = func.basic_blocks.append("select_cont")
          @builder.cond(should_include, then_block, cont_block)

          @builder.position_at_end(then_block)
          @builder.call(@rb_ary_push, result_array, elem_value)
          @builder.br(cont_block)

          @builder.position_at_end(cont_block)
        when :reject
          # Push element if block returns falsy
          # Handle unboxed results
          is_falsy = if body_result.is_a?(LLVM::Value)
            if body_result.type == LLVM::Int64
              # Unboxed i64: falsy if zero
              @builder.icmp(:eq, body_result, LLVM::Int64.from_i(0))
            elsif body_result.type == LLVM::Int1
              # Boolean: negate
              @builder.icmp(:eq, body_result, LLVM::Int1.from_i(0))
            else
              # Boxed VALUE: check for falsy
              reject_val = ensure_ruby_value(body_result)
              @builder.or(
                @builder.icmp(:eq, reject_val, @qfalse),
                @builder.icmp(:eq, reject_val, @qnil)
              )
            end
          else
            # Default: falsy
            LLVM::Int1.from_i(1)
          end

          then_block = func.basic_blocks.append("reject_push")
          cont_block = func.basic_blocks.append("reject_cont")
          @builder.cond(is_falsy, then_block, cont_block)

          @builder.position_at_end(then_block)
          @builder.call(@rb_ary_push, result_array, elem_value)
          @builder.br(cont_block)

          @builder.position_at_end(cont_block)
        when :each
          # Just execute, no result collection
        end

        # Increment index
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end
        @builder.position_at_end(loop_end)

        # Return result
        case method_sym
        when :map, :collect, :select, :filter, :reject
          result_array
        when :each
          receiver  # each returns self
        end
      end

      # Check if Integer#times can be inlined
      def can_inline_integer_times?(inst)
        # Ensure we're in a valid function context
        return false unless @builder&.insert_block

        return false unless inst.block
        # times takes 0 or 1 block param (|i| or no param)
        return false unless inst.block.params.size <= 1

        # Check if receiver type is Integer
        receiver_type = inst.receiver.respond_to?(:type) ? inst.receiver.type : nil
        return false unless is_integer_type?(receiver_type)

        true
      end

      # Check if a type is an Integer type
      def is_integer_type?(type)
        return false unless type

        if type.is_a?(TypeChecker::Types::ClassInstance) && type.name == :Integer
          return true
        end

        # Also check for the singleton INTEGER type
        type == TypeChecker::Types::INTEGER
      end

      # Check if find/detect/any?/all?/none? can be inlined
      def can_inline_array_predicate?(inst)
        # Ensure we're in a valid function context
        return false unless @builder&.insert_block

        return false unless inst.block
        return false unless inst.block.params.size == 1  # |elem|

        # Check if receiver type is Array
        receiver_type = inst.receiver.respond_to?(:type) ? inst.receiver.type : nil
        return false unless is_array_type?(receiver_type)

        true
      end

      # Generate truthy check for a value
      # Returns an i1 (boolean) indicating if the value is truthy
      def generate_truthy_check(value)
        if value.is_a?(LLVM::Value)
          case value.type
          when LLVM::Int1
            # Already a boolean
            value
          when LLVM::Int8
            # Bool field (stored as i8): non-zero is truthy
            @builder.icmp(:ne, value, LLVM::Int8.from_i(0))
          when LLVM::Int64
            # Could be unboxed integer or VALUE
            # For VALUE: not nil and not false
            # Check if this looks like an unboxed integer (large positive number)
            # For safety, check against Qnil and Qfalse
            not_nil = @builder.icmp(:ne, value, @qnil)
            not_false = @builder.icmp(:ne, value, @qfalse)
            @builder.and(not_nil, not_false)
          when LLVM::Double
            # Unboxed double: non-zero is truthy
            @builder.fcmp(:one, value, LLVM::Double.from_f(0.0))
          else
            # Generic VALUE: not nil and not false
            val = ensure_ruby_value(value)
            not_nil = @builder.icmp(:ne, val, @qnil)
            not_false = @builder.icmp(:ne, val, @qfalse)
            @builder.and(not_nil, not_false)
          end
        else
          # Non-LLVM value, assume false
          LLVM::Int1.from_i(0)
        end
      end

      # Generate inline Integer#times loop
      # n.times { |i| ... } becomes: for i = 0; i < n; i++ { ... }
      def generate_inline_integer_times(inst)
        receiver = get_value_as_ruby(inst.receiver)
        block = inst.block

        # Convert receiver to i64 for loop counter
        n = @builder.call(@rb_num2long, receiver)

        # Allocate loop index
        idx_alloca = @builder.alloca(LLVM::Int64, "times_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("times_cond")
        loop_body = func.basic_blocks.append("times_body")
        loop_end = func.basic_blocks.append("times_end")

        @builder.br(loop_cond)

        # Loop condition: idx < n
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, n)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Set up block parameter (if any)
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        if block.params.size == 1
          elem_param = block.params[0].name
          # Pass index as unboxed i64
          @variables[elem_param] = current_idx
          @variable_types[elem_param] = :i64
          @variable_allocas.delete(elem_param)
        end

        # Generate block body instructions
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            generate_instruction(body_inst)
          end
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Increment index
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: return receiver (times returns self)
        @builder.position_at_end(loop_end)
        receiver
      end

      # Generate inline Array#find/detect loop with early termination
      # arr.find { |x| cond } becomes: for each elem, if cond then return elem; return nil
      def generate_inline_array_find(inst)
        receiver = get_value_as_ruby(inst.receiver)
        block = inst.block
        elem_param = block.params[0].name

        # Detect element type for potential unboxed optimization
        receiver_type = inst.receiver.respond_to?(:type) ? inst.receiver.type : nil
        elem_unboxed_type = get_array_element_unboxed_type(receiver_type)

        # Get array length
        length_id = @builder.call(@rb_intern, @builder.global_string_pointer("length"))
        length_value = @builder.call(@rb_funcallv, receiver, length_id, LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
        arr_len = @builder.call(@rb_num2long, length_value)

        # Allocate index
        idx_alloca = @builder.alloca(LLVM::Int64, "find_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("find_cond")
        loop_body = func.basic_blocks.append("find_body")
        found_block = func.basic_blocks.append("find_found")
        loop_end = func.basic_blocks.append("find_end")

        @builder.br(loop_cond)

        # Loop condition: idx < len
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Get current element (always as VALUE)
        elem_value = @builder.call(@rb_ary_entry, receiver, current_idx)

        # Set up block parameter
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        @variables[elem_param] = elem_value
        @variable_types[elem_param] = :value
        @variable_allocas.delete(elem_param)

        # Generate block body instructions
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            body_result = generate_instruction(body_inst)
          end
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Check if result is truthy
        is_truthy = generate_truthy_check(body_result)

        # Increment index before branching (needed for next iteration)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)

        # Branch based on truthy check
        @builder.cond(is_truthy, found_block, loop_cond)

        # Found block: return the element
        @builder.position_at_end(found_block)
        @builder.br(loop_end)

        # Loop end: phi node for result
        @builder.position_at_end(loop_end)
        phi_incoming = {
          found_block => elem_value,
          loop_cond => @qnil
        }
        @builder.phi(value_type, phi_incoming, "find_result")
      end

      # Generate inline Array#any?/all?/none? loop with early termination
      def generate_inline_array_predicate(inst)
        receiver = get_value_as_ruby(inst.receiver)
        block = inst.block
        elem_param = block.params[0].name
        method_sym = inst.method_name.to_sym

        # Get array length
        length_id = @builder.call(@rb_intern, @builder.global_string_pointer("length"))
        length_value = @builder.call(@rb_funcallv, receiver, length_id, LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
        arr_len = @builder.call(@rb_num2long, length_value)

        # Allocate index
        idx_alloca = @builder.alloca(LLVM::Int64, "pred_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("#{method_sym}_cond")
        loop_body = func.basic_blocks.append("#{method_sym}_body")
        early_exit = func.basic_blocks.append("#{method_sym}_early")
        loop_end = func.basic_blocks.append("#{method_sym}_end")

        @builder.br(loop_cond)

        # Loop condition: idx < len
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Get current element (always as VALUE)
        elem_value = @builder.call(@rb_ary_entry, receiver, current_idx)

        # Set up block parameter
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        @variables[elem_param] = elem_value
        @variable_types[elem_param] = :value
        @variable_allocas.delete(elem_param)

        # Generate block body instructions
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            body_result = generate_instruction(body_inst)
          end
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Check if result is truthy
        is_truthy = generate_truthy_check(body_result)

        # Increment index before branching
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)

        # Determine early exit condition based on method
        # any?: exit early if truthy (found one)
        # all?: exit early if falsy (found counter-example)
        # none?: exit early if truthy (found one that shouldn't exist)
        case method_sym
        when :any?
          # Exit early if truthy
          @builder.cond(is_truthy, early_exit, loop_cond)
        when :all?
          # Exit early if falsy
          @builder.cond(is_truthy, loop_cond, early_exit)
        when :none?
          # Exit early if truthy
          @builder.cond(is_truthy, early_exit, loop_cond)
        end

        # Early exit block
        @builder.position_at_end(early_exit)
        early_result = case method_sym
        when :any? then @qtrue   # Found truthy element
        when :all? then @qfalse  # Found falsy element
        when :none? then @qfalse # Found truthy element (should be none)
        end
        @builder.br(loop_end)

        # Loop end (completed without early exit)
        @builder.position_at_end(loop_end)
        default_result = case method_sym
        when :any? then @qfalse  # No truthy element found
        when :all? then @qtrue   # All elements were truthy
        when :none? then @qtrue  # No truthy element found
        end

        phi_incoming = {
          early_exit => early_result,
          loop_cond => default_result
        }
        @builder.phi(value_type, phi_incoming, "#{method_sym}_result")
      end

      # Fallback: generate rb_block_call
      def generate_rb_block_call(inst, builtin)
        # Get receiver as Ruby VALUE
        receiver = get_value_as_ruby(inst.receiver)

        # Get method ID
        method_ptr = @builder.global_string_pointer(inst.method_name)
        method_id = @builder.call(@rb_intern, method_ptr)

        # Prepare arguments array (for methods like upto/downto that take args)
        argc = LLVM::Int32.from_i(inst.args.size)

        if inst.args.empty?
          argv = LLVM::Pointer(value_type).null
        else
          argv = @builder.alloca(LLVM::Array(value_type, inst.args.size))
          inst.args.each_with_index do |arg, i|
            arg_value = get_value_as_ruby(arg)
            ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
            @builder.store(arg_value, ptr)
          end
          argv = @builder.bit_cast(argv, LLVM::Pointer(value_type))
        end

        # Create capture struct for closure variables
        captures = inst.block.captures.select { |c| @variable_allocas[c.name] }
        capture_data = create_capture_struct(captures)

        # Collect type info for captured variables
        capture_types = {}
        captures.each do |capture|
          capture_types[capture.name] = @variable_types[capture.name] || :value
        end

        # Generate block callback function
        block_func = generate_block_callback(inst.block, inst.method_name, captures, capture_types)

        # Call rb_block_call with capture data
        result = @builder.call(@rb_block_call,
          receiver, method_id, argc, argv, block_func, capture_data)

        result
      end

      # Create a struct containing pointers to captured variables
      def create_capture_struct(captures)
        return @qnil if captures.empty?

        # Create struct with VALUE* for each captured variable
        # We store pointers to the allocas so the callback can read/write them
        num_captures = captures.size

        # Allocate array of pointers (VALUE*)
        ptr_type = LLVM::Pointer(value_type)
        array_type = LLVM::Array(ptr_type, num_captures)
        capture_array = @builder.alloca(array_type, "captures")

        captures.each_with_index do |capture, i|
          alloca = @variable_allocas[capture.name]
          next unless alloca

          # Store pointer to the variable's alloca
          elem_ptr = @builder.gep2(array_type, capture_array,
            [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)], "capture_#{capture.name}_ptr")
          @builder.store(alloca, elem_ptr)
        end

        # Cast to VALUE for passing as data2
        @builder.ptr2int(capture_array, value_type)
      end

      # Generate a callback function for rb_block_call
      # Signature: VALUE func(VALUE yielded_arg, VALUE data2, int argc, VALUE *argv, VALUE blockarg)
      def generate_block_callback(block_def, method_name, captures = [], capture_types = {})
        return nil unless block_def

        # Create a unique name for the callback
        @block_counter ||= 0
        @block_counter += 1
        callback_name = "block_callback_#{method_name}_#{@block_counter}"

        # Define callback function
        # VALUE func(VALUE yielded_arg, VALUE data2, int argc, VALUE *argv, VALUE blockarg)
        callback_func = @mod.functions.add(callback_name,
          [value_type, value_type, LLVM::Int32, LLVM::Pointer(value_type), value_type],
          value_type)

        # Save current builder state
        saved_block = @builder.insert_block
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        # Create entry block for callback
        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        # Reset variable tracking for callback scope
        @variables = {}
        @variable_types = {}
        @variable_allocas = {}

        # Setup captured variable access through data2 pointer
        # data2 is a pointer to array of VALUE* (pointers to captured variables)
        unless captures.empty?
          ptr_type = LLVM::Pointer(value_type)
          array_type = LLVM::Array(ptr_type, captures.size)
          captures_ptr = @builder.int2ptr(callback_func.params[1],
            LLVM::Pointer(array_type), "captures_ptr")

          captures.each_with_index do |capture, i|
            # Get pointer to the pointer (VALUE**)
            elem_ptr_ptr = @builder.gep2(array_type, captures_ptr,
              [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)], "cap_#{capture.name}_ptr_ptr")
            # Load the pointer to the variable (VALUE*)
            elem_ptr = @builder.load2(ptr_type, elem_ptr_ptr, "cap_#{capture.name}_ptr")

            # Store in variable_allocas so LoadLocal/StoreLocal can use it
            @variable_allocas[capture.name] = elem_ptr
            # Preserve the original type from outer scope
            @variable_types[capture.name] = capture_types[capture.name] || :value
          end
        end

        # Bind block parameters to yielded values
        # For single-parameter blocks, use yielded_arg directly
        # For multi-parameter blocks, check argc at runtime:
        #   - If argc >= params.size: extract from argv (e.g., Array#each_with_index yields 2 values)
        #   - If argc < params.size: destructure yielded_arg with rb_ary_entry (e.g., Hash#each yields [k,v] pair)
        if block_def.params.size == 1
          param_name = block_def.params.first.name
          @variables[param_name] = callback_func.params[0]  # yielded_arg
          @variable_types[param_name] = :value
        elsif block_def.params.size > 1
          # Create allocas for each parameter
          param_allocas = block_def.params.map do |param|
            alloca = @builder.alloca(value_type, "#{param.name}_alloca")
            alloca
          end

          # Runtime argc check: argc >= params.size?
          argc_val = callback_func.params[2]  # int argc
          argc_enough = @builder.icmp(:sge, argc_val, LLVM::Int32.from_i(block_def.params.size), "argc_enough")

          argv_block = callback_func.basic_blocks.append("argv_extract")
          destruct_block = callback_func.basic_blocks.append("destruct_extract")
          params_done_block = callback_func.basic_blocks.append("params_done")

          @builder.cond(argc_enough, argv_block, destruct_block)

          # argv path: extract from argv directly
          @builder.position_at_end(argv_block)
          block_def.params.each_with_index do |param, i|
            ptr = @builder.gep2(value_type, callback_func.params[3],
              [LLVM::Int32.from_i(i)], "argv_#{param.name}_ptr")
            val = @builder.load2(value_type, ptr, "argv_#{param.name}")
            @builder.store(val, param_allocas[i])
          end
          @builder.br(params_done_block)

          # destructure path: extract from yielded_arg using rb_ary_entry
          @builder.position_at_end(destruct_block)
          block_def.params.each_with_index do |param, i|
            val = @builder.call(@rb_ary_entry, callback_func.params[0],
              LLVM::Int64.from_i(i), "destruct_#{param.name}")
            @builder.store(val, param_allocas[i])
          end
          @builder.br(params_done_block)

          # Continue with loaded values
          @builder.position_at_end(params_done_block)
          block_def.params.each_with_index do |param, i|
            val = @builder.load2(value_type, param_allocas[i], param.name)
            @variables[param.name] = val
            @variable_types[param.name] = :value
          end
        end

        # Pre-allocate allocas for block-local variables
        # This ensures that variables assigned inside the block have proper allocas
        # Skip variables that are already defined (captures and block parameters)
        block_local_vars = collect_local_variables_in_block(block_def)
        capture_names = captures.map(&:name)
        param_names = block_def.params.map(&:name)
        excluded_names = capture_names + param_names

        block_local_vars.each do |var_name, var_type|
          next if excluded_names.include?(var_name)
          next if @variable_allocas[var_name]  # Already has an alloca

          # Create alloca with appropriate type
          llvm_type, type_tag = llvm_type_for_ruby_type(var_type)
          alloca = @builder.alloca(llvm_type, "blk_#{var_name}")
          @variable_allocas[var_name] = alloca
          @variable_types[var_name] = type_tag
        end

        # Compile block body
        result = @qnil
        result_type = :value
        last_inst = nil
        block_def.body.each do |basic_block|
          basic_block.instructions.each do |hir_inst|
            result = generate_instruction(hir_inst)
            last_inst = hir_inst
          end
        end

        # Determine result type from last instruction
        # Special handling for StoreLocal: get type from var.name since it has no result_var
        if last_inst.is_a?(HIR::StoreLocal)
          var_name = last_inst.var.name
          result_type = @variable_types[var_name] || :value
        elsif last_inst && last_inst.respond_to?(:result_var) && last_inst.result_var
          result_type = @variable_types[last_inst.result_var] || :value
        end

        # Return the result, converting to VALUE if necessary
        result = @qnil if result.nil?
        # Box the result if it's unboxed
        if result.is_a?(LLVM::Value) && result_type != :value
          result = convert_value(result, result_type, :value)
        end
        @builder.ret(result.is_a?(LLVM::Value) ? result : @qnil)

        # Restore builder state
        @builder.position_at_end(saved_block) if saved_block
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        callback_func
      end

      # Generate a Proc object from a block definition
      def generate_proc_new(inst)
        block_def = inst.block_def
        return @qnil unless block_def

        # Prepare captures - get current values of captured variables
        captures = block_def.captures
        capture_types = {}
        captures.each do |cap|
          capture_types[cap.name] = @variable_types[cap.name]
        end

        # Create the callback function (same as block callback)
        callback_func = generate_block_callback(block_def, "proc", captures, capture_types)

        # Setup captures data if there are any
        if captures.empty?
          captures_data = LLVM::Int64.from_i(0)  # NULL for no captures
        else
          # Allocate array of pointers to captured variables
          ptr_type = LLVM::Pointer(value_type)
          array_type = LLVM::Array(ptr_type, captures.size)
          captures_array = @builder.alloca(array_type, "proc_captures")

          captures.each_with_index do |capture, i|
            # Get the alloca for this captured variable
            alloca = @variable_allocas[capture.name]
            if alloca
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(alloca, ptr)
            else
              # Variable not found, store null
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(LLVM::Pointer(value_type).null, ptr)
            end
          end

          captures_data = @builder.ptr2int(captures_array, LLVM::Int64, "captures_int")
        end

        # Call rb_proc_new to create the Proc object
        result = @builder.call(@rb_proc_new, callback_func, captures_data)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate a call to a Proc object (from ProcCall HIR instruction)
      def generate_proc_call(inst)
        # Get the Proc value
        proc_value = get_value_as_ruby(inst.proc_value)

        # Build arguments array for rb_proc_call
        if inst.args.empty?
          args_array = @builder.call(@rb_ary_new_capa, LLVM::Int64.from_i(0))
        else
          args_array = @builder.call(@rb_ary_new_capa, LLVM::Int64.from_i(inst.args.size))
          inst.args.each do |arg|
            arg_value = get_value_as_ruby(arg)
            @builder.call(@rb_ary_push, args_array, arg_value)
          end
        end

        # Call rb_proc_call
        result = @builder.call(@rb_proc_call, proc_value, args_array)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate Proc#call from a regular Call instruction
      def generate_proc_call_from_call_inst(inst)
        # Get the Proc value
        proc_value = get_value_as_ruby(inst.receiver)

        # Build arguments array for rb_proc_call
        if inst.args.empty?
          args_array = @builder.call(@rb_ary_new_capa, LLVM::Int64.from_i(0))
        else
          args_array = @builder.call(@rb_ary_new_capa, LLVM::Int64.from_i(inst.args.size))
          inst.args.each do |arg|
            arg_value = get_value_as_ruby(arg)
            @builder.call(@rb_ary_push, args_array, arg_value)
          end
        end

        # Call rb_proc_call
        @builder.call(@rb_proc_call, proc_value, args_array)
      end

      # Check if a type is a Proc type
      def proc_type?(type)
        return false unless type

        case type
        when TypeChecker::Types::ClassInstance
          type.name == :Proc || type.name.to_s == "Proc"
        when TypeChecker::Types::ProcType
          true
        else
          false
        end
      end

      # ========================================
      # Fiber operations
      # ========================================

      # Generate a Fiber object from a block definition
      def generate_fiber_new(inst)
        block_def = inst.block_def
        return @qnil unless block_def

        # Prepare captures - get current values of captured variables
        captures = block_def.captures
        capture_types = {}
        captures.each do |cap|
          capture_types[cap.name] = @variable_types[cap.name]
        end

        # Create the callback function (same pattern as proc/block callback)
        callback_func = generate_block_callback(block_def, "fiber", captures, capture_types)

        # Setup captures data if there are any
        if captures.empty?
          captures_data = LLVM::Int64.from_i(0)  # NULL for no captures
        else
          # Allocate array of pointers to captured variables
          ptr_type = LLVM::Pointer(value_type)
          array_type = LLVM::Array(ptr_type, captures.size)
          captures_array = @builder.alloca(array_type, "fiber_captures")

          captures.each_with_index do |capture, i|
            # Get the alloca for this captured variable
            alloca = @variable_allocas[capture.name]
            if alloca
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(alloca, ptr)
            else
              # Variable not found, store null
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(LLVM::Pointer(value_type).null, ptr)
            end
          end

          captures_data = @builder.ptr2int(captures_array, LLVM::Int64, "captures_int")
        end

        # Call rb_fiber_new to create the Fiber object
        result = @builder.call(@rb_fiber_new, callback_func, captures_data)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate fiber.resume(args) call
      def generate_fiber_resume(inst)
        # Get the fiber value
        fiber_value = get_value_as_ruby(inst.fiber)

        # Build arguments array
        argc = LLVM::Int32.from_i(inst.args.size)

        if inst.args.empty?
          # No arguments - use null pointer
          argv = LLVM::Pointer(value_type).null
        else
          # Allocate array for arguments
          array_type = LLVM::Array(value_type, inst.args.size)
          argv_array = @builder.alloca(array_type, "fiber_resume_args")

          inst.args.each_with_index do |arg, i|
            arg_value = get_value_as_ruby(arg)
            ptr = @builder.gep(argv_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
            @builder.store(arg_value, ptr)
          end

          # Get pointer to first element
          argv = @builder.gep(argv_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)])
        end

        # Call rb_fiber_resume
        result = @builder.call(@rb_fiber_resume, fiber_value, argc, argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate Fiber.yield(args) call
      def generate_fiber_yield(inst)
        # Build arguments array
        argc = LLVM::Int32.from_i(inst.args.size)

        if inst.args.empty?
          # No arguments - use null pointer
          argv = LLVM::Pointer(value_type).null
        else
          # Allocate array for arguments
          array_type = LLVM::Array(value_type, inst.args.size)
          argv_array = @builder.alloca(array_type, "fiber_yield_args")

          inst.args.each_with_index do |arg, i|
            arg_value = get_value_as_ruby(arg)
            ptr = @builder.gep(argv_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
            @builder.store(arg_value, ptr)
          end

          # Get pointer to first element
          argv = @builder.gep(argv_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)])
        end

        # Call rb_fiber_yield
        result = @builder.call(@rb_fiber_yield, argc, argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate fiber.alive? call
      def generate_fiber_alive(inst)
        # Get the fiber value
        fiber_value = get_value_as_ruby(inst.fiber)

        # Call rb_fiber_alive_p
        result = @builder.call(@rb_fiber_alive_p, fiber_value)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate Fiber.current call
      def generate_fiber_current(inst)
        # Call rb_fiber_current
        result = @builder.call(@rb_fiber_current)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # ========================================
      # Thread operations
      # ========================================

      # Generate Thread.new { ... } call
      def generate_thread_new(inst)
        block_def = inst.block_def
        return @qnil unless block_def

        # Prepare captures
        captures = block_def.captures
        capture_types = {}
        captures.each do |cap|
          capture_types[cap.name] = @variable_types[cap.name]
        end

        # Create thread-specific callback (different signature from fiber/proc)
        callback_func = generate_thread_callback(block_def, captures, capture_types)

        # Setup captures data (pass as intptr_t, cast back in callback)
        if captures.empty?
          captures_data = LLVM::Int64.from_i(0)
        else
          ptr_type = LLVM::Pointer(value_type)
          array_type = LLVM::Array(ptr_type, captures.size)
          captures_array = @builder.alloca(array_type, "thread_captures")

          captures.each_with_index do |capture, i|
            alloca = @variable_allocas[capture.name]
            if alloca
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(alloca, ptr)
            else
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(LLVM::Pointer(value_type).null, ptr)
            end
          end

          captures_data = @builder.ptr2int(captures_array, LLVM::Int64, "captures_int")
        end

        # Call rb_thread_create - pass captures as intptr_t (void* compatible)
        captures_ptr = @builder.int2ptr(captures_data, LLVM::Pointer(LLVM::Int8), "captures_ptr")
        result = @builder.call(@rb_thread_create, callback_func, captures_ptr)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate thread callback function with correct signature: VALUE func(void*)
      def generate_thread_callback(block_def, captures = [], capture_types = {})
        return nil unless block_def

        # Create a unique name for the callback
        @thread_callback_counter ||= 0
        @thread_callback_counter += 1
        callback_name = "thread_callback_#{@thread_callback_counter}"

        # Thread callback signature: VALUE func(void* arg)
        callback_func = @mod.functions.add(callback_name,
          [LLVM::Pointer(LLVM::Int8)],
          value_type)

        # Save current builder state
        saved_block = @builder.insert_block
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        # Create entry block for callback
        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        # Reset variable tracking for callback scope
        @variables = {}
        @variable_types = {}
        @variable_allocas = {}

        # Setup captured variable access through void* arg
        unless captures.empty?
          # The void* arg contains captures array pointer (cast from intptr_t)
          ptr_type = LLVM::Pointer(value_type)
          array_type = LLVM::Array(ptr_type, captures.size)

          # Convert void* (i8*) to intptr_t, then to the array pointer type
          arg_int = @builder.ptr2int(callback_func.params[0], LLVM::Int64, "arg_int")
          captures_ptr = @builder.int2ptr(arg_int, LLVM::Pointer(array_type), "captures_ptr")

          captures.each_with_index do |capture, i|
            # Get pointer to the pointer (VALUE**)
            elem_ptr_ptr = @builder.gep2(array_type, captures_ptr,
              [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)], "cap_#{capture.name}_ptr_ptr")
            # Load the pointer to the variable (VALUE*)
            elem_ptr = @builder.load2(ptr_type, elem_ptr_ptr, "cap_#{capture.name}_ptr")

            # Store in variable_allocas so LoadLocal/StoreLocal can use it
            @variable_allocas[capture.name] = elem_ptr
            # Preserve the original type from outer scope
            @variable_types[capture.name] = capture_types[capture.name] || :value
          end
        end

        # Compile block body
        result = @qnil
        result_type = :value
        last_inst = nil
        block_def.body.each do |basic_block|
          basic_block.instructions.each do |hir_inst|
            result = generate_instruction(hir_inst)
            last_inst = hir_inst
          end
        end

        # Determine result type from last instruction
        if last_inst.is_a?(HIR::StoreLocal)
          var_name = last_inst.var.name
          result_type = @variable_types[var_name] || :value
        elsif last_inst && last_inst.respond_to?(:result_var) && last_inst.result_var
          result_type = @variable_types[last_inst.result_var] || :value
        end

        # Return the result, converting to VALUE if necessary
        result = @qnil if result.nil?
        if result.is_a?(LLVM::Value) && result_type != :value
          result = convert_value(result, result_type, :value)
        end
        @builder.ret(result.is_a?(LLVM::Value) ? result : @qnil)

        # Restore builder state
        @builder.position_at_end(saved_block) if saved_block
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        callback_func
      end

      # Generate Thread.current call
      def generate_thread_current(inst)
        result = @builder.call(@rb_thread_current)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate thread.join call
      def generate_thread_join(inst)
        thread_value = get_value_as_ruby(inst.thread)

        # Call thread.join via rb_funcallv
        method_ptr = @builder.global_string_pointer("join")
        method_id = @builder.call(@rb_intern, method_ptr)

        if inst.timeout
          timeout_value = get_value_as_ruby(inst.timeout)
          argv = @builder.alloca(value_type, "join_arg")
          @builder.store(timeout_value, argv)
          result = @builder.call(@rb_funcallv, thread_value, method_id, LLVM::Int32.from_i(1), argv)
        else
          argv = LLVM::Pointer(value_type).null
          result = @builder.call(@rb_funcallv, thread_value, method_id, LLVM::Int32.from_i(0), argv)
        end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate thread.value call
      def generate_thread_value(inst)
        thread_value = get_value_as_ruby(inst.thread)

        # Call thread.value via rb_funcallv
        method_ptr = @builder.global_string_pointer("value")
        method_id = @builder.call(@rb_intern, method_ptr)
        argv = LLVM::Pointer(value_type).null
        result = @builder.call(@rb_funcallv, thread_value, method_id, LLVM::Int32.from_i(0), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # ========================================
      # Mutex operations
      # ========================================

      # Generate Mutex.new call
      def generate_mutex_new(inst)
        result = @builder.call(@rb_mutex_new)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate mutex.lock call
      def generate_mutex_lock(inst)
        mutex_value = get_value_as_ruby(inst.mutex)
        result = @builder.call(@rb_mutex_lock, mutex_value)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate mutex.unlock call
      def generate_mutex_unlock(inst)
        mutex_value = get_value_as_ruby(inst.mutex)
        result = @builder.call(@rb_mutex_unlock, mutex_value)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate mutex.synchronize { ... } call
      # Uses rb_ensure for exception-safe unlock
      def generate_mutex_synchronize(inst)
        mutex_value = get_value_as_ruby(inst.mutex)
        block_def = inst.block_def

        # Call rb_mutex_lock first
        @builder.call(@rb_mutex_lock, mutex_value)

        # Prepare captures for the block
        captures = block_def.captures
        capture_types = {}
        captures.each do |cap|
          capture_types[cap.name] = @variable_types[cap.name]
        end

        # Generate body callback (executes block body)
        body_callback = generate_mutex_body_callback(block_def, captures, capture_types)

        # Generate ensure callback (unlocks mutex)
        ensure_callback = generate_mutex_ensure_callback

        # Setup captures data if there are any
        if captures.empty?
          captures_data = LLVM::Int64.from_i(0)  # NULL for no captures
        else
          # Allocate array of pointers to captured variables
          ptr_type = LLVM::Pointer(value_type)
          array_type = LLVM::Array(ptr_type, captures.size)
          captures_array = @builder.alloca(array_type, "sync_captures")

          captures.each_with_index do |capture, i|
            alloca = @variable_allocas[capture.name]
            if alloca
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(alloca, ptr)
            else
              ptr = @builder.gep(captures_array, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
              @builder.store(LLVM::Pointer(value_type).null, ptr)
            end
          end

          captures_data = @builder.ptr2int(captures_array, LLVM::Int64, "sync_captures_int")
        end

        # Call rb_ensure(body_callback, captures_data, ensure_callback, mutex)
        # This ensures ensure_callback is called even if body_callback raises
        result = @builder.call(@rb_ensure,
          body_callback, captures_data,
          ensure_callback, mutex_value)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate callback for mutex.synchronize body
      def generate_mutex_body_callback(block_def, captures = [], capture_types = {})
        @mutex_body_counter ||= 0
        @mutex_body_counter += 1
        callback_name = "mutex_body_callback_#{@mutex_body_counter}"

        # VALUE callback(VALUE data) - data is pointer to captures array
        callback_type = LLVM::Type.function([value_type], value_type)
        callback_func = @mod.functions.add(callback_name, [value_type], value_type)

        # Save current builder state
        saved_block = @builder.insert_block
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        # Create entry block
        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        # Reset variable tracking
        @variables = {}
        @variable_types = {}
        @variable_allocas = {}

        # Setup captured variable access
        unless captures.empty?
          ptr_type = LLVM::Pointer(value_type)
          array_type = LLVM::Array(ptr_type, captures.size)
          captures_ptr = @builder.int2ptr(callback_func.params[0],
            LLVM::Pointer(array_type), "captures_ptr")

          captures.each_with_index do |capture, i|
            elem_ptr_ptr = @builder.gep2(array_type, captures_ptr,
              [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)], "cap_#{capture.name}_ptr_ptr")
            elem_ptr = @builder.load2(ptr_type, elem_ptr_ptr, "cap_#{capture.name}_ptr")

            @variable_allocas[capture.name] = elem_ptr
            @variable_types[capture.name] = capture_types[capture.name] || :value
          end
        end

        # Pre-allocate allocas for block-local variables
        block_local_vars = collect_local_variables_in_block(block_def)
        capture_names = captures.map(&:name)
        param_names = block_def.params.map(&:name)
        excluded_names = capture_names + param_names

        block_local_vars.each do |var_name, var_type|
          next if excluded_names.include?(var_name)
          next if @variable_allocas[var_name]

          llvm_type, type_tag = llvm_type_for_ruby_type(var_type)
          alloca = @builder.alloca(llvm_type, "sync_blk_#{var_name}")
          @variable_allocas[var_name] = alloca
          @variable_types[var_name] = type_tag
        end

        # Execute block body
        result = @qnil
        result_type = :value
        last_inst = nil

        block_def.body.each do |basic_block|
          basic_block.instructions.each do |hir_inst|
            result = generate_instruction(hir_inst) || result
            last_inst = hir_inst
          end
        end

        # Determine result type
        if last_inst.is_a?(HIR::StoreLocal)
          var_name = last_inst.var.name
          result_type = @variable_types[var_name] || :value
        elsif last_inst && last_inst.respond_to?(:result_var) && last_inst.result_var
          result_type = @variable_types[last_inst.result_var] || :value
        end

        # Box result if needed
        result = @qnil if result.nil?
        if result.is_a?(LLVM::Value) && result_type != :value
          result = convert_value(result, result_type, :value)
        end
        @builder.ret(result.is_a?(LLVM::Value) ? result : @qnil)

        # Restore builder state
        @builder.position_at_end(saved_block) if saved_block
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        callback_func
      end

      # Generate callback for mutex unlock (ensure part)
      def generate_mutex_ensure_callback
        @mutex_ensure_counter ||= 0
        @mutex_ensure_counter += 1
        callback_name = "mutex_ensure_callback_#{@mutex_ensure_counter}"

        # VALUE callback(VALUE mutex) - mutex is passed as data2
        callback_func = @mod.functions.add(callback_name, [value_type], value_type)

        # Save current builder state
        saved_block = @builder.insert_block

        # Create entry block
        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        # Call rb_mutex_unlock(mutex)
        @builder.call(@rb_mutex_unlock, callback_func.params[0])

        # Return Qnil
        @builder.ret(@qnil)

        # Restore builder state
        @builder.position_at_end(saved_block) if saved_block

        callback_func
      end

      # ========================================
      # Queue operations
      # ========================================

      # Generate Queue.new call
      def generate_queue_new(inst)
        # Call Queue.new via rb_funcallv on rb_cQueue
        method_ptr = @builder.global_string_pointer("new")
        method_id = @builder.call(@rb_intern, method_ptr)
        queue_class = @builder.load2(value_type, @rb_cQueue, "queue_class")
        argv = LLVM::Pointer(value_type).null
        result = @builder.call(@rb_funcallv, queue_class, method_id, LLVM::Int32.from_i(0), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate queue.push call
      def generate_queue_push(inst)
        queue_value = get_value_as_ruby(inst.queue)
        value = get_value_as_ruby(inst.value)

        # Call queue.push via rb_funcallv
        method_ptr = @builder.global_string_pointer("push")
        method_id = @builder.call(@rb_intern, method_ptr)
        argv = @builder.alloca(value_type, "push_arg")
        @builder.store(value, argv)
        result = @builder.call(@rb_funcallv, queue_value, method_id, LLVM::Int32.from_i(1), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate queue.pop call
      def generate_queue_pop(inst)
        queue_value = get_value_as_ruby(inst.queue)

        # Call queue.pop via rb_funcallv
        method_ptr = @builder.global_string_pointer("pop")
        method_id = @builder.call(@rb_intern, method_ptr)

        if inst.non_block
          non_block_value = get_value_as_ruby(inst.non_block)
          argv = @builder.alloca(value_type, "pop_arg")
          @builder.store(non_block_value, argv)
          result = @builder.call(@rb_funcallv, queue_value, method_id, LLVM::Int32.from_i(1), argv)
        else
          argv = LLVM::Pointer(value_type).null
          result = @builder.call(@rb_funcallv, queue_value, method_id, LLVM::Int32.from_i(0), argv)
        end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # ========================================
      # ConditionVariable operations
      # ========================================

      # Generate ConditionVariable.new call
      def generate_cv_new(inst)
        # Get ConditionVariable class via rb_path2class
        class_name_ptr = @builder.global_string_pointer("Thread::ConditionVariable")
        cv_class = @builder.call(@rb_path2class, class_name_ptr)

        # Call ConditionVariable.new via rb_funcallv
        method_ptr = @builder.global_string_pointer("new")
        method_id = @builder.call(@rb_intern, method_ptr)
        argv = LLVM::Pointer(value_type).null
        result = @builder.call(@rb_funcallv, cv_class, method_id, LLVM::Int32.from_i(0), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate cv.wait(mutex) call
      def generate_cv_wait(inst)
        cv_value = get_value_as_ruby(inst.cv)
        mutex_value = get_value_as_ruby(inst.mutex)

        # Call cv.wait(mutex) via rb_funcallv
        method_ptr = @builder.global_string_pointer("wait")
        method_id = @builder.call(@rb_intern, method_ptr)

        if inst.timeout
          timeout_value = get_value_as_ruby(inst.timeout)
          argv = @builder.alloca(LLVM::Array(value_type, 2), "wait_args")
          ptr0 = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)])
          ptr1 = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)])
          @builder.store(mutex_value, ptr0)
          @builder.store(timeout_value, ptr1)
          result = @builder.call(@rb_funcallv, cv_value, method_id, LLVM::Int32.from_i(2), ptr0)
        else
          argv = @builder.alloca(value_type, "wait_arg")
          @builder.store(mutex_value, argv)
          result = @builder.call(@rb_funcallv, cv_value, method_id, LLVM::Int32.from_i(1), argv)
        end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate cv.signal call
      def generate_cv_signal(inst)
        cv_value = get_value_as_ruby(inst.cv)

        # Call cv.signal via rb_funcallv
        method_ptr = @builder.global_string_pointer("signal")
        method_id = @builder.call(@rb_intern, method_ptr)
        argv = LLVM::Pointer(value_type).null
        result = @builder.call(@rb_funcallv, cv_value, method_id, LLVM::Int32.from_i(0), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate cv.broadcast call
      def generate_cv_broadcast(inst)
        cv_value = get_value_as_ruby(inst.cv)

        # Call cv.broadcast via rb_funcallv
        method_ptr = @builder.global_string_pointer("broadcast")
        method_id = @builder.call(@rb_intern, method_ptr)
        argv = LLVM::Pointer(value_type).null
        result = @builder.call(@rb_funcallv, cv_value, method_id, LLVM::Int32.from_i(0), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # ========================================
      # SizedQueue operations
      # ========================================

      # Generate SizedQueue.new(max) call
      def generate_sized_queue_new(inst)
        max_size = get_value_as_ruby(inst.max_size)

        # Get SizedQueue class via rb_path2class
        class_name_ptr = @builder.global_string_pointer("Thread::SizedQueue")
        sq_class = @builder.call(@rb_path2class, class_name_ptr)

        # Call SizedQueue.new(max) via rb_funcallv
        method_ptr = @builder.global_string_pointer("new")
        method_id = @builder.call(@rb_intern, method_ptr)
        argv = @builder.alloca(value_type, "new_arg")
        @builder.store(max_size, argv)
        result = @builder.call(@rb_funcallv, sq_class, method_id, LLVM::Int32.from_i(1), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate sized_queue.push call
      def generate_sized_queue_push(inst)
        queue_value = get_value_as_ruby(inst.queue)
        value = get_value_as_ruby(inst.value)

        # Call queue.push via rb_funcallv
        method_ptr = @builder.global_string_pointer("push")
        method_id = @builder.call(@rb_intern, method_ptr)
        argv = @builder.alloca(value_type, "push_arg")
        @builder.store(value, argv)
        result = @builder.call(@rb_funcallv, queue_value, method_id, LLVM::Int32.from_i(1), argv)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate sized_queue.pop call
      def generate_sized_queue_pop(inst)
        queue_value = get_value_as_ruby(inst.queue)

        # Call queue.pop via rb_funcallv
        method_ptr = @builder.global_string_pointer("pop")
        method_id = @builder.call(@rb_intern, method_ptr)

        if inst.non_block
          non_block_value = get_value_as_ruby(inst.non_block)
          argv = @builder.alloca(value_type, "pop_arg")
          @builder.store(non_block_value, argv)
          result = @builder.call(@rb_funcallv, queue_value, method_id, LLVM::Int32.from_i(1), argv)
        else
          argv = LLVM::Pointer(value_type).null
          result = @builder.call(@rb_funcallv, queue_value, method_id, LLVM::Int32.from_i(0), argv)
        end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Type-directed optimizations: Unboxed Arithmetic
      UNBOXED_INTEGER_OPS = %w[+ - * / % << >> & | ^].freeze
      UNBOXED_INTEGER_CMP = %w[< <= > >= == !=].freeze
      UNBOXED_FLOAT_OPS = %w[+ - * /].freeze
      UNBOXED_FLOAT_CMP = %w[< <= > >= == !=].freeze

      def can_use_unboxed_arithmetic?(inst)
        return false unless inst.args.size == 1

        receiver_type = get_effective_type(inst.receiver)
        arg_type = get_effective_type(inst.args.first)

        if integer_type_or_i64?(receiver_type) && integer_type_or_i64?(arg_type)
          UNBOXED_INTEGER_OPS.include?(inst.method_name) ||
            UNBOXED_INTEGER_CMP.include?(inst.method_name)
        elsif float_type_or_double?(receiver_type) && float_type_or_double?(arg_type)
          UNBOXED_FLOAT_OPS.include?(inst.method_name) ||
            UNBOXED_FLOAT_CMP.include?(inst.method_name)
        elsif float_type_or_double?(receiver_type) && integer_type_or_i64?(arg_type)
          UNBOXED_FLOAT_OPS.include?(inst.method_name) ||
            UNBOXED_FLOAT_CMP.include?(inst.method_name)
        elsif integer_type_or_i64?(receiver_type) && float_type_or_double?(arg_type)
          UNBOXED_FLOAT_OPS.include?(inst.method_name) ||
            UNBOXED_FLOAT_CMP.include?(inst.method_name)
        else
          false
        end
      end

      # Get effective type, checking both HIR type and tracked variable type
      def get_effective_type(hir_value)
        # For LoadLocal, check the source variable's type
        if hir_value.is_a?(HIR::LoadLocal)
          source_var = hir_value.var.name
          if @variable_types[source_var]
            return @variable_types[source_var]
          end
        end

        # Check result_var type if available
        var_name = case hir_value
        when HIR::Instruction
          hir_value.result_var
        when String
          hir_value
        else
          nil
        end

        if var_name && @variable_types[var_name]
          return @variable_types[var_name]  # Returns :i64, :double, or :value
        end

        # Fall back to HIR type
        get_type(hir_value)
      end

      def integer_type_or_i64?(type)
        type == :i64 || integer_type?(type)
      end

      def float_type_or_double?(type)
        type == :double || float_type?(type)
      end

      def generate_unboxed_arithmetic(inst)
        # Use get_effective_unboxed_type to check @variable_types for inline loop variables
        receiver_effective_type = get_effective_unboxed_type(inst.receiver)
        arg_effective_type = get_effective_unboxed_type(inst.args.first)

        # Check if it's a comparison operation
        is_comparison = UNBOXED_INTEGER_CMP.include?(inst.method_name)

        # Both Integer (i64) -> i64 arithmetic/comparison
        if receiver_effective_type == :i64 && arg_effective_type == :i64
          if is_comparison
            generate_unboxed_integer_cmp(inst)
          else
            generate_unboxed_integer_op(inst)
          end
        else
          # Float or mixed -> double arithmetic/comparison
          if is_comparison
            generate_unboxed_float_cmp(inst)
          else
            generate_unboxed_float_op(inst)
          end
        end
      end

      def generate_unboxed_integer_cmp(inst)
        receiver_value, receiver_type_tag = get_value_with_type(inst.receiver)
        arg_value, arg_type_tag = get_value_with_type(inst.args.first)

        left = receiver_type_tag == :i64 ? receiver_value : @builder.call(@rb_num2long, receiver_value)
        right = arg_type_tag == :i64 ? arg_value : @builder.call(@rb_num2long, arg_value)

        # Perform comparison, returns i1
        cmp_result = case inst.method_name
        when "<"
          @builder.icmp(:slt, left, right)
        when "<="
          @builder.icmp(:sle, left, right)
        when ">"
          @builder.icmp(:sgt, left, right)
        when ">="
          @builder.icmp(:sge, left, right)
        when "=="
          @builder.icmp(:eq, left, right)
        when "!="
          @builder.icmp(:ne, left, right)
        else
          raise "Unknown comparison: #{inst.method_name}"
        end

        # Extend to i64 for consistency (0 or 1)
        result = @builder.zext(cmp_result, LLVM::Int64)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :i64
          @comparison_result_vars.add(inst.result_var)
        end
        result
      end

      def generate_unboxed_float_cmp(inst)
        receiver_type = get_type(inst.receiver)
        arg_type = get_type(inst.args.first)

        receiver_value, receiver_type_tag = get_value_with_type(inst.receiver)
        arg_value, arg_type_tag = get_value_with_type(inst.args.first)

        # Convert to double
        left = case receiver_type_tag
        when :double then receiver_value
        when :i64 then @builder.si2fp(receiver_value, LLVM::Double)
        else
          if integer_type?(receiver_type)
            int_val = @builder.call(@rb_num2long, receiver_value)
            @builder.si2fp(int_val, LLVM::Double)
          else
            @builder.call(@rb_num2dbl, receiver_value)
          end
        end

        right = case arg_type_tag
        when :double then arg_value
        when :i64 then @builder.si2fp(arg_value, LLVM::Double)
        else
          if integer_type?(arg_type)
            int_val = @builder.call(@rb_num2long, arg_value)
            @builder.si2fp(int_val, LLVM::Double)
          else
            @builder.call(@rb_num2dbl, arg_value)
          end
        end

        # Perform comparison
        cmp_result = case inst.method_name
        when "<"
          @builder.fcmp(:olt, left, right)
        when "<="
          @builder.fcmp(:ole, left, right)
        when ">"
          @builder.fcmp(:ogt, left, right)
        when ">="
          @builder.fcmp(:oge, left, right)
        when "=="
          @builder.fcmp(:oeq, left, right)
        when "!="
          @builder.fcmp(:one, left, right)
        else
          raise "Unknown comparison: #{inst.method_name}"
        end

        result = @builder.zext(cmp_result, LLVM::Int64)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :i64
          @comparison_result_vars.add(inst.result_var)
        end
        result
      end

      def generate_unboxed_integer_op(inst)
        # Get values with their type tags
        receiver_value, receiver_type_tag = get_value_with_type(inst.receiver)
        arg_value, arg_type_tag = get_value_with_type(inst.args.first)

        # Convert to i64 only if not already unboxed
        left = receiver_type_tag == :i64 ? receiver_value : @builder.call(@rb_num2long, receiver_value)
        right = arg_type_tag == :i64 ? arg_value : @builder.call(@rb_num2long, arg_value)

        # Perform native i64 operation
        result = case inst.method_name
        when "+"
          @builder.add(left, right)
        when "-"
          @builder.sub(left, right)
        when "*"
          @builder.mul(left, right)
        when "/"
          @builder.sdiv(left, right)
        when "%"
          @builder.srem(left, right)
        when "<<"
          shift_amt = @builder.trunc(right, LLVM::Int32)
          @builder.shl(left, @builder.zext(shift_amt, LLVM::Int64))
        when ">>"
          shift_amt = @builder.trunc(right, LLVM::Int32)
          @builder.ashr(left, @builder.zext(shift_amt, LLVM::Int64))
        when "&"
          @builder.and(left, right)
        when "|"
          @builder.or(left, right)
        when "^"
          @builder.xor(left, right)
        else
          raise "Unknown integer operation: #{inst.method_name}"
        end

        # Store as unboxed i64 - will be boxed only when needed
        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :i64
        end
        result
      end

      def generate_unboxed_float_op(inst)
        receiver_type = get_type(inst.receiver)
        arg_type = get_type(inst.args.first)

        receiver_value, receiver_type_tag = get_value_with_type(inst.receiver)
        arg_value, arg_type_tag = get_value_with_type(inst.args.first)

        # Convert to double, handling already-unboxed values
        left = case receiver_type_tag
        when :double
          receiver_value
        when :i64
          @builder.si2fp(receiver_value, LLVM::Double)
        else
          if integer_type?(receiver_type)
            int_val = @builder.call(@rb_num2long, receiver_value)
            @builder.si2fp(int_val, LLVM::Double)
          else
            @builder.call(@rb_num2dbl, receiver_value)
          end
        end

        right = case arg_type_tag
        when :double
          arg_value
        when :i64
          @builder.si2fp(arg_value, LLVM::Double)
        else
          if integer_type?(arg_type)
            int_val = @builder.call(@rb_num2long, arg_value)
            @builder.si2fp(int_val, LLVM::Double)
          else
            @builder.call(@rb_num2dbl, arg_value)
          end
        end

        # Perform native double operation
        result = case inst.method_name
        when "+"
          @builder.fadd(left, right)
        when "-"
          @builder.fsub(left, right)
        when "*"
          @builder.fmul(left, right)
        when "/"
          @builder.fdiv(left, right)
        else
          raise "Unknown float operation: #{inst.method_name}"
        end

        # Store as unboxed double
        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :double
        end
        result
      end

      # Unboxed unary method constants
      UNBOXED_INTEGER_UNARY = %w[abs even? odd? zero? positive? negative?].freeze
      UNBOXED_FLOAT_UNARY = %w[abs zero? positive? negative?].freeze

      # Check if a method call can use unboxed unary optimization
      def can_use_unboxed_unary?(inst)
        return false unless inst.args.empty?

        receiver_type = get_effective_type(inst.receiver)

        if integer_type_or_i64?(receiver_type)
          UNBOXED_INTEGER_UNARY.include?(inst.method_name)
        elsif float_type_or_double?(receiver_type)
          UNBOXED_FLOAT_UNARY.include?(inst.method_name)
        else
          false
        end
      end

      # Generate unboxed unary operation
      def generate_unboxed_unary(inst)
        receiver_type = get_effective_type(inst.receiver)

        if integer_type_or_i64?(receiver_type)
          generate_unboxed_integer_unary(inst)
        else
          generate_unboxed_float_unary(inst)
        end
      end

      # Generate unboxed integer unary operations
      def generate_unboxed_integer_unary(inst)
        receiver_value, receiver_type_tag = get_value_with_type(inst.receiver)

        # Convert to i64 if needed
        val = case receiver_type_tag
        when :i64
          receiver_value
        else
          @builder.call(@rb_num2long, receiver_value)
        end

        case inst.method_name
        when "abs"
          # abs(x) = x < 0 ? -x : x
          is_neg = @builder.icmp(:slt, val, LLVM::Int64.from_i(0))
          neg_val = @builder.sub(LLVM::Int64.from_i(0), val)
          result = @builder.select(is_neg, neg_val, val)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :i64
          end
          result
        when "even?"
          # even?(x) = (x & 1) == 0
          bit = @builder.and(val, LLVM::Int64.from_i(1))
          is_even = @builder.icmp(:eq, bit, LLVM::Int64.from_i(0))
          result = @builder.select(is_even, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        when "odd?"
          # odd?(x) = (x & 1) != 0
          bit = @builder.and(val, LLVM::Int64.from_i(1))
          is_odd = @builder.icmp(:ne, bit, LLVM::Int64.from_i(0))
          result = @builder.select(is_odd, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        when "zero?"
          is_zero = @builder.icmp(:eq, val, LLVM::Int64.from_i(0))
          result = @builder.select(is_zero, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        when "positive?"
          is_pos = @builder.icmp(:sgt, val, LLVM::Int64.from_i(0))
          result = @builder.select(is_pos, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        when "negative?"
          is_neg = @builder.icmp(:slt, val, LLVM::Int64.from_i(0))
          result = @builder.select(is_neg, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        else
          raise "Unknown integer unary: #{inst.method_name}"
        end
      end

      # Generate unboxed float unary operations
      def generate_unboxed_float_unary(inst)
        receiver_value, receiver_type_tag = get_value_with_type(inst.receiver)

        # Convert to double if needed
        val = case receiver_type_tag
        when :double
          receiver_value
        when :i64
          @builder.si2fp(receiver_value, LLVM::Double)
        else
          @builder.call(@rb_num2dbl, receiver_value)
        end

        case inst.method_name
        when "abs"
          # abs(x) = x < 0.0 ? -x : x
          zero = LLVM::Double.from_f(0.0)
          is_neg = @builder.fcmp(:olt, val, zero)
          neg_val = @builder.fsub(zero, val)
          result = @builder.select(is_neg, neg_val, val)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :double
          end
          result
        when "zero?"
          is_zero = @builder.fcmp(:oeq, val, LLVM::Double.from_f(0.0))
          result = @builder.select(is_zero, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        when "positive?"
          is_pos = @builder.fcmp(:ogt, val, LLVM::Double.from_f(0.0))
          result = @builder.select(is_pos, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        when "negative?"
          is_neg = @builder.fcmp(:olt, val, LLVM::Double.from_f(0.0))
          result = @builder.select(is_neg, @qtrue, @qfalse)
          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value
          end
          result
        else
          raise "Unknown float unary: #{inst.method_name}"
        end
      end

      # Generate Array#[] using rb_ary_entry
      def generate_array_index_get(inst)
        receiver = get_value_as_ruby(inst.receiver)
        # Convert index to long (rb_ary_entry takes long, not VALUE)
        idx_value = get_value_as_ruby(inst.args[0])
        idx_long = @builder.call(@rb_num2long, idx_value)
        # VALUE rb_ary_entry(VALUE ary, long offset)
        @builder.call(@rb_ary_entry, receiver, idx_long)
      end

      # Generate Array#[]= using rb_ary_store
      def generate_array_index_set(inst)
        receiver = get_value_as_ruby(inst.receiver)
        # Convert index to long (rb_ary_store takes long, not VALUE)
        idx_value = get_value_as_ruby(inst.args[0])
        idx_long = @builder.call(@rb_num2long, idx_value)
        # Get value to store
        val = get_value_as_ruby(inst.args[1])
        # void rb_ary_store(VALUE ary, long idx, VALUE val)
        @builder.call(@rb_ary_store, receiver, idx_long, val)
        # Return the stored value (Ruby semantics: arr[i] = v returns v)
        val
      end

      # Generate Array#delete_at using rb_ary_delete_at
      def generate_array_delete_at(inst)
        receiver = get_value_as_ruby(inst.receiver)
        # Convert index to long
        idx_value = get_value_as_ruby(inst.args[0])
        idx_long = @builder.call(@rb_num2long, idx_value)
        # VALUE rb_ary_delete_at(VALUE ary, long pos)
        @builder.call(@rb_ary_delete_at, receiver, idx_long)
      end

      # Check if a Range iteration can be inlined
      def can_inline_range_loop?(inst)
        return false unless @builder&.insert_block
        return false unless inst.block
        return false unless inst.block.params.size >= 1

        # Check if receiver is a Range by looking at the HIR instruction
        receiver_inst = find_hir_instruction(inst.receiver)
        return true if receiver_inst.is_a?(HIR::RangeLit)

        # Check tracked type
        receiver_type = get_type(inst.receiver)
        return true if receiver_type == TypeChecker::Types::RANGE
        return true if receiver_type.is_a?(TypeChecker::Types::ClassInstance) && receiver_type.name == :Range

        false
      end

      # Generate inline Range#each loop
      def generate_inline_range_each(inst)
        range_info = get_range_info(inst)
        return nil unless range_info

        start_val, end_val, exclusive = range_info
        block = inst.block

        # Allocate loop counter
        idx_alloca = @builder.alloca(LLVM::Int64, "range_idx")
        @builder.store(start_val, idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("range_cond")
        loop_body = func.basic_blocks.append("range_body")
        loop_end = func.basic_blocks.append("range_end")

        @builder.br(loop_cond)

        # Loop condition: idx < end (exclusive) or idx <= end (inclusive)
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "range_i")
        cond = if exclusive
          @builder.icmp(:slt, current_idx, end_val)
        else
          @builder.icmp(:sle, current_idx, end_val)
        end
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        if block.params.size >= 1
          elem_param = block.params[0].name
          @variables[elem_param] = current_idx
          @variable_types[elem_param] = :i64
          @variable_allocas.delete(elem_param)
        end

        # Generate block body
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            generate_instruction(body_inst)
          end
        end

        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Increment counter
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: return receiver
        @builder.position_at_end(loop_end)
        get_value_as_ruby(inst.receiver)
      end

      # Generate inline Range#map
      def generate_inline_range_map(inst)
        range_info = get_range_info(inst)
        return nil unless range_info

        start_val, end_val, exclusive = range_info
        block = inst.block

        # Create result array
        result_ary = @builder.call(@rb_ary_new)

        # Allocate loop counter
        idx_alloca = @builder.alloca(LLVM::Int64, "range_map_idx")
        @builder.store(start_val, idx_alloca)

        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("range_map_cond")
        loop_body = func.basic_blocks.append("range_map_body")
        loop_end = func.basic_blocks.append("range_map_end")

        @builder.br(loop_cond)

        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "range_i")
        cond = if exclusive
          @builder.icmp(:slt, current_idx, end_val)
        else
          @builder.icmp(:sle, current_idx, end_val)
        end
        @builder.cond(cond, loop_body, loop_end)

        @builder.position_at_end(loop_body)

        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        if block.params.size >= 1
          elem_param = block.params[0].name
          @variables[elem_param] = current_idx
          @variable_types[elem_param] = :i64
          @variable_allocas.delete(elem_param)
        end

        # Generate block body and collect result
        last_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            last_result = generate_instruction(body_inst)
          end
        end

        # Push block result to array
        block_result = last_result ? get_value_as_ruby_from_llvm(last_result) : @qnil
        @builder.call(@rb_ary_push, result_ary, block_result)

        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        @builder.position_at_end(loop_end)

        if inst.result_var
          @variables[inst.result_var] = result_ary
          @variable_types[inst.result_var] = :value
        end
        result_ary
      end

      # Generate inline Range#select
      def generate_inline_range_select(inst)
        range_info = get_range_info(inst)
        return nil unless range_info

        start_val, end_val, exclusive = range_info
        block = inst.block

        result_ary = @builder.call(@rb_ary_new)

        idx_alloca = @builder.alloca(LLVM::Int64, "range_sel_idx")
        @builder.store(start_val, idx_alloca)

        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("range_sel_cond")
        loop_body = func.basic_blocks.append("range_sel_body")
        loop_push = func.basic_blocks.append("range_sel_push")
        loop_next = func.basic_blocks.append("range_sel_next")
        loop_end = func.basic_blocks.append("range_sel_end")

        @builder.br(loop_cond)

        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "range_i")
        cond = if exclusive
          @builder.icmp(:slt, current_idx, end_val)
        else
          @builder.icmp(:sle, current_idx, end_val)
        end
        @builder.cond(cond, loop_body, loop_end)

        @builder.position_at_end(loop_body)

        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        if block.params.size >= 1
          elem_param = block.params[0].name
          @variables[elem_param] = current_idx
          @variable_types[elem_param] = :i64
          @variable_allocas.delete(elem_param)
        end

        last_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            last_result = generate_instruction(body_inst)
          end
        end

        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Check if result is truthy
        block_result = last_result || @qnil
        is_truthy = generate_truthy_check(block_result)
        @builder.cond(is_truthy, loop_push, loop_next)

        @builder.position_at_end(loop_push)
        boxed_idx = @builder.call(@rb_int2inum, current_idx)
        @builder.call(@rb_ary_push, result_ary, boxed_idx)
        @builder.br(loop_next)

        @builder.position_at_end(loop_next)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        @builder.position_at_end(loop_end)

        if inst.result_var
          @variables[inst.result_var] = result_ary
          @variable_types[inst.result_var] = :value
        end
        result_ary
      end

      # Generate inline Range#reduce
      def generate_inline_range_reduce(inst)
        range_info = get_range_info(inst)
        return nil unless range_info
        return nil unless inst.block.params.size == 2  # |acc, elem|

        start_val, end_val, exclusive = range_info
        block = inst.block

        # Get initial value
        initial = if inst.args.size > 0
          get_value_with_type(inst.args.first)
        else
          nil
        end

        # Allocate accumulator
        acc_alloca = @builder.alloca(LLVM::Int64, "range_reduce_acc")
        if initial
          init_val, init_type = initial
          init_i64 = init_type == :i64 ? init_val : @builder.call(@rb_num2long, init_val)
          @builder.store(init_i64, acc_alloca)
        else
          @builder.store(start_val, acc_alloca)
        end

        # If no initial value, start from start+1
        idx_alloca = @builder.alloca(LLVM::Int64, "range_reduce_idx")
        if initial
          @builder.store(start_val, idx_alloca)
        else
          @builder.store(@builder.add(start_val, LLVM::Int64.from_i(1)), idx_alloca)
        end

        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("range_reduce_cond")
        loop_body = func.basic_blocks.append("range_reduce_body")
        loop_end = func.basic_blocks.append("range_reduce_end")

        @builder.br(loop_cond)

        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "range_i")
        cond = if exclusive
          @builder.icmp(:slt, current_idx, end_val)
        else
          @builder.icmp(:sle, current_idx, end_val)
        end
        @builder.cond(cond, loop_body, loop_end)

        @builder.position_at_end(loop_body)

        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        # Set block params: |acc, elem|
        acc_param = block.params[0].name
        elem_param = block.params[1].name

        current_acc = @builder.load2(LLVM::Int64, acc_alloca, "acc")
        @variables[acc_param] = current_acc
        @variable_types[acc_param] = :i64
        @variable_allocas.delete(acc_param)

        @variables[elem_param] = current_idx
        @variable_types[elem_param] = :i64
        @variable_allocas.delete(elem_param)

        # Generate block body
        last_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each do |body_inst|
            last_result = generate_instruction(body_inst)
          end
        end

        # Store result back to accumulator
        if last_result
          new_acc = if @variable_types[block.body.last&.instructions&.last&.result_var] == :i64
            @variables[block.body.last.instructions.last.result_var]
          elsif last_result.is_a?(LLVM::Value) && last_result.type == LLVM::Int64
            last_result
          else
            @builder.call(@rb_num2long, get_value_as_ruby_from_llvm(last_result))
          end
          @builder.store(new_acc, acc_alloca)
        end

        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        @builder.position_at_end(loop_end)
        final_acc = @builder.load2(LLVM::Int64, acc_alloca, "final_acc")

        if inst.result_var
          @variables[inst.result_var] = final_acc
          @variable_types[inst.result_var] = :i64
        end
        final_acc
      end

      # Helper to extract range start/end/exclusive info
      def get_range_info(inst)
        receiver_inst = find_hir_instruction(inst.receiver)

        if receiver_inst.is_a?(HIR::RangeLit)
          # Direct access to RangeLit operands
          left_value, left_type = get_value_with_type(receiver_inst.left)
          right_value, right_type = get_value_with_type(receiver_inst.right)

          start_val = left_type == :i64 ? left_value : @builder.call(@rb_num2long, left_value)
          end_val = right_type == :i64 ? right_value : @builder.call(@rb_num2long, right_value)

          [start_val, end_val, receiver_inst.exclusive]
        else
          # For Range objects, call first/last methods
          receiver = get_value_as_ruby(inst.receiver)

          first_ptr = @builder.global_string_pointer("first")
          first_id = @builder.call(@rb_intern, first_ptr)
          argc_zero = LLVM::Int32.from_i(0)
          null_argv = LLVM::Pointer(value_type).null
          first_val = @builder.call(@rb_funcallv, receiver, first_id, argc_zero, null_argv)
          start_val = @builder.call(@rb_num2long, first_val)

          last_ptr = @builder.global_string_pointer("last")
          last_id = @builder.call(@rb_intern, last_ptr)
          last_val = @builder.call(@rb_funcallv, receiver, last_id, argc_zero, null_argv)
          end_val = @builder.call(@rb_num2long, last_val)

          # For non-literal ranges, check exclude_end?
          excl_ptr = @builder.global_string_pointer("exclude_end?")
          excl_id = @builder.call(@rb_intern, excl_ptr)
          excl_val = @builder.call(@rb_funcallv, receiver, excl_id, argc_zero, null_argv)
          # exclude_end? returns true/false - check if truthy
          # For simplicity, assume inclusive if not a literal
          [start_val, end_val, false]
        end
      end

      # Helper to find the HIR instruction for a given value reference
      def find_hir_instruction(hir_value)
        case hir_value
        when HIR::RangeLit
          hir_value
        when HIR::Instruction
          hir_value
        else
          nil
        end
      end

      # Helper to convert LLVM value to Ruby VALUE based on known type
      def get_value_as_ruby_from_llvm(llvm_val)
        return llvm_val unless llvm_val.is_a?(LLVM::Value)

        case llvm_val.type
        when LLVM::Int64
          @builder.call(@rb_int2inum, llvm_val)
        when LLVM::Double
          @builder.call(@rb_float_new, llvm_val)
        else
          llvm_val
        end
      end

      def get_type(hir_value)
        case hir_value
        when HIR::Instruction
          hir_value.type
        when HIR::Node
          hir_value.type
        else
          TypeChecker::Types::UNTYPED
        end
      end

      # Resolve TypeVar to its concrete type if unified
      def resolve_type_var(type)
        return type unless type.is_a?(TypeChecker::TypeVar)

        # Follow the chain of instantiated type variables
        resolved = type.prune
        if resolved.is_a?(TypeChecker::TypeVar)
          resolved.instance || resolved
        else
          resolved
        end
      end

      def integer_type?(type)
        return false unless type
        type = resolve_type_var(type)
        return true if type == TypeChecker::Types::INTEGER
        type.is_a?(TypeChecker::Types::ClassInstance) && type.name == :Integer
      end

      def float_type?(type)
        return false unless type
        type = resolve_type_var(type)
        return true if type == TypeChecker::Types::FLOAT
        type.is_a?(TypeChecker::Types::ClassInstance) && type.name == :Float
      end

      # Get the effective unboxed type for a value, considering @variable_types
      # Returns :i64, :double, or nil
      def get_effective_unboxed_type(hir_value)
        # First check if this is a LoadLocal with a variable that has an unboxed type
        if hir_value.is_a?(HIR::LoadLocal)
          var_name = hir_value.result_var || hir_value.var.name
          type_tag = @variable_types[var_name]
          return type_tag if type_tag == :i64 || type_tag == :double
        end

        # Check HIR type
        hir_type = get_type(hir_value)
        if integer_type?(hir_type)
          :i64
        elsif float_type?(hir_type)
          :double
        else
          nil
        end
      end

      def self_receiver?(receiver)
        # Only SelfRef is considered self for direct function calls
        # Untyped receivers could be any object, not necessarily self
        receiver.is_a?(HIR::SelfRef)
      end

      # Generate direct function call (bypassing rb_funcallv)
      def generate_direct_call(inst, func_name)
        target = @functions[func_name.to_s] || @functions[func_name.to_sym]
        return generate_fallback_call(inst) unless target

        # Get self (first argument)
        func = @builder.insert_block.parent
        self_value = func.params[0]

        # Build argument list: [self, arg1, arg2, ...]
        # Use get_value_as_ruby to ensure arguments are boxed Ruby VALUES
        call_args = [self_value]
        inst.args.each do |arg|
          call_args << get_value_as_ruby(arg)
        end

        result = @builder.call(target, *call_args)

        # Set type tag if this is a native method call
        # Check if we're calling a method on self that's a NativeClass method
        if @current_native_class && inst.result_var
          method_sig = @current_native_class.methods[func_name.to_sym]
          if method_sig
            result_type_tag = case method_sig.return_type
            when :Int64 then :i64
            when :Float64 then :double
            when :Self then :native_class
            else :value
            end
            @variable_types[inst.result_var] = result_type_tag
          end
        end

        result
      end

      # Look up a builtin method for direct call (devirtualization)
      def lookup_builtin_method(receiver_type, method_name)
        return nil unless receiver_type

        class_name = case receiver_type
        when TypeChecker::Types::ClassInstance
          receiver_type.name
        when TypeChecker::Types
          # Check for common types
          case receiver_type
          when TypeChecker::Types::STRING then :String
          when TypeChecker::Types::INTEGER then :Integer
          when TypeChecker::Types::FLOAT then :Float
          when TypeChecker::Types::ARRAY then :Array
          when TypeChecker::Types::HASH then :Hash
          when TypeChecker::Types::SYMBOL then :Symbol
          else nil
          end
        else
          nil
        end

        return nil unless class_name

        Codegen.lookup(class_name, method_name)
      end

      # Look up a block iterator method by name alone
      # Used when receiver type is unresolved but method name is a known iterator
      def lookup_block_iterator_by_name(method_name)
        method_sym = method_name.to_sym

        # Check common iterator methods across types
        BLOCK_ITERATOR_METHODS.each do |class_name|
          builtin = Codegen.lookup(class_name, method_sym)
          return builtin if builtin && builtin[:conv] == :block_iterator
        end

        nil
      end

      # Classes that have block iterator methods
      BLOCK_ITERATOR_METHODS = [:Integer, :Array, :Hash, :Range, :Enumerable].freeze

      # Generate a direct call to a CRuby builtin method
      # All builtin methods use simple convention: func(VALUE recv, VALUE arg1, ...)
      def generate_builtin_call(inst, builtin)
        c_func = builtin[:c_func]
        func = @builtin_funcs[c_func]
        return generate_fallback_call(inst) unless func

        # Get receiver as boxed VALUE
        receiver = get_value(inst.receiver)

        # Get arguments as boxed VALUEs
        args = inst.args.map { |arg| get_value(arg) }

        @builder.call(func, receiver, *args)
      end

      def generate_fallback_call(inst)
        # Fall back to rb_funcallv
        receiver = get_value(inst.receiver)

        method_ptr = @builder.global_string_pointer(inst.method_name)
        method_id = @builder.call(@rb_intern, method_ptr)

        argc = LLVM::Int32.from_i(inst.args.size)

        if inst.args.empty?
          argv = LLVM::Pointer(value_type).null
        else
          argv = @builder.alloca(LLVM::Array(value_type, inst.args.size))

          inst.args.each_with_index do |arg, i|
            arg_value = get_value(arg)
            ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
            @builder.store(arg_value, ptr)
          end

          argv = @builder.bit_cast(argv, LLVM::Pointer(value_type))
        end

        @builder.call(@rb_funcallv, receiver, method_id, argc, argv)
      end

      def generate_self_ref(inst)
        # Self is the first parameter of the function
        func = @builder.insert_block.parent
        self_param = func.params[0]

        if inst.result_var
          @variables[inst.result_var] = self_param

          # Track type appropriately
          if @current_native_class
            @variable_types[inst.result_var] = :native_class
            @native_class_types ||= {}
            @native_class_types[inst.result_var] = @current_native_class
          else
            @variable_types[inst.result_var] = :value
          end
        end

        self_param
      end

      def generate_constant_lookup(inst)
        # Look up a constant (typically a class name)
        # Use rb_const_get(rb_cObject, rb_intern(name))
        const_name_ptr = @builder.global_string_pointer(inst.name)
        const_id = @builder.call(@rb_intern, const_name_ptr)

        # Load rb_cObject (for top-level constants)
        rb_cobject_val = @builder.load2(value_type, @rb_cObject, "rb_cObject")

        # Look up the constant
        result = @builder.call(@rb_const_get, rb_cobject_val, const_id)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Range literal
      def generate_range_lit(inst)
        left_val = get_value_as_ruby(inst.left)
        right_val = get_value_as_ruby(inst.right)
        exclusive_flag = LLVM::Int32.from_i(inst.exclusive ? 1 : 0)

        result = @builder.call(@rb_range_new, left_val, right_val, exclusive_flag)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end
        result
      end

      # Global variable read
      def generate_load_global_var(inst)
        name_ptr = @builder.global_string_pointer(inst.name)
        result = @builder.call(@rb_gv_get, name_ptr)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end
        result
      end

      # Global variable write
      def generate_store_global_var(inst)
        name_ptr = @builder.global_string_pointer(inst.name)
        val = get_value_as_ruby(inst.value)
        @builder.call(@rb_gv_set, name_ptr, val)
      end

      # Multi-write array element extraction
      def generate_multi_write_extract(inst)
        array_val = get_value_as_ruby(inst.array)
        index_val = LLVM::Int64.from_i(inst.index)
        result = @builder.call(@rb_ary_entry, array_val, index_val)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end
        result
      end

      # Generate defined? check
      def generate_defined_check(inst)
        func = @builder.insert_block.parent

        case inst.check_type
        when :local_variable
          # In AOT compilation, local variables are always known at compile time
          str_ptr = @builder.global_string_pointer("local-variable")
          result = @builder.call(@rb_str_new_cstr, str_ptr)
        when :constant
          # Use rb_const_defined to check at runtime
          rb_const_defined = @mod.functions["rb_const_defined"] || @mod.functions.add(
            "rb_const_defined",
            [value_type, value_type],
            LLVM::Int32
          )
          rb_cobject_val = @builder.load2(value_type, @rb_cObject, "rb_cObject")
          name_ptr = @builder.global_string_pointer(inst.name)
          name_id = @builder.call(@rb_intern, name_ptr)
          is_defined = @builder.call(rb_const_defined, rb_cobject_val, name_id)
          is_true = @builder.icmp(:ne, is_defined, LLVM::Int32.from_i(0))

          defined_bb = func.basic_blocks.append("defined_yes")
          undefined_bb = func.basic_blocks.append("defined_no")
          merge_bb = func.basic_blocks.append("defined_merge")

          @builder.cond(is_true, defined_bb, undefined_bb)

          @builder.position_at_end(defined_bb)
          str_ptr = @builder.global_string_pointer("constant")
          defined_val = @builder.call(@rb_str_new_cstr, str_ptr)
          @builder.br(merge_bb)

          @builder.position_at_end(undefined_bb)
          @builder.br(merge_bb)

          @builder.position_at_end(merge_bb)
          result = @builder.phi(value_type, { defined_bb => defined_val, undefined_bb => @qnil })
        when :method
          # Use rb_respond_to to check if method exists
          rb_respond_to = @mod.functions["rb_respond_to"] || @mod.functions.add(
            "rb_respond_to",
            [value_type, value_type],
            LLVM::Int32
          )
          # Check on main object (self)
          self_val = @variables["self"] || @builder.call(@rb_funcallv, @rb_cObject,
            @builder.call(@rb_intern, @builder.global_string_pointer("new")),
            LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
          name_ptr = @builder.global_string_pointer(inst.name)
          name_id = @builder.call(@rb_intern, name_ptr)
          is_defined = @builder.call(rb_respond_to, self_val, name_id)
          is_true = @builder.icmp(:ne, is_defined, LLVM::Int32.from_i(0))

          defined_bb = func.basic_blocks.append("defined_method_yes")
          undefined_bb = func.basic_blocks.append("defined_method_no")
          merge_bb = func.basic_blocks.append("defined_method_merge")

          @builder.cond(is_true, defined_bb, undefined_bb)

          @builder.position_at_end(defined_bb)
          str_ptr = @builder.global_string_pointer("method")
          defined_val = @builder.call(@rb_str_new_cstr, str_ptr)
          @builder.br(merge_bb)

          @builder.position_at_end(undefined_bb)
          @builder.br(merge_bb)

          @builder.position_at_end(merge_bb)
          result = @builder.phi(value_type, { defined_bb => defined_val, undefined_bb => @qnil })
        when :global_variable
          rb_gv_defined = @mod.functions["rb_f_global_variables"] || begin
            # Fallback: just return the string since global vars are always "defined"
            str_ptr = @builder.global_string_pointer("global-variable")
            result = @builder.call(@rb_str_new_cstr, str_ptr)
            @variables[inst.result_var] = result if inst.result_var
            return result
          end
        else
          # For other types, return "expression" as a safe default
          str_ptr = @builder.global_string_pointer("expression")
          result = @builder.call(@rb_str_new_cstr, str_ptr)
        end

        @variables[inst.result_var] = result if inst.result_var
        result
      end

      def generate_super_call(inst)
        if inst.args.empty? && !inst.forward_args
          # super with no args
          result = @builder.call(@rb_call_super, LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
        else
          args = inst.args.map { |a| get_value_as_ruby(a) }
          argc = args.size

          # Allocate argv on stack
          argv = @builder.array_alloca(value_type, LLVM::Int32.from_i(argc))
          args.each_with_index do |arg, i|
            ptr = @builder.gep2(value_type, argv, [LLVM::Int32.from_i(i)])
            @builder.store(arg, ptr)
          end

          result = @builder.call(@rb_call_super, LLVM::Int32.from_i(argc), argv)
        end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end
        result
      end

      def generate_yield(inst)
        result = if inst.args.empty?
          # yield with no arguments - pass Qnil
          @builder.call(@rb_yield, @qnil)
        elsif inst.args.size == 1
          # yield with single argument
          arg_value = get_value(inst.args.first)
          @builder.call(@rb_yield, arg_value)
        else
          # yield with multiple arguments - use rb_yield_values2
          argc = LLVM::Int32.from_i(inst.args.size)

          # Allocate array on stack
          argv = @builder.alloca(LLVM::Array(value_type, inst.args.size))

          inst.args.each_with_index do |arg, i|
            arg_value = get_value(arg)
            ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(i)])
            @builder.store(arg_value, ptr)
          end

          # Cast to VALUE*
          argv_ptr = @builder.bit_cast(argv, LLVM::Pointer(value_type))
          @builder.call(@rb_yield_values2, argc, argv_ptr)
        end

        @variables[inst.result_var] = result if inst.result_var
        result
      end

      def generate_begin_rescue(inst)
        # Generate try/rescue/ensure using rb_rescue2
        #
        # CRuby API:
        # VALUE rb_rescue2(VALUE (*b_proc)(VALUE), VALUE data1,
        #                  VALUE (*r_proc)(VALUE, VALUE), VALUE data2,
        #                  VALUE exception_class, ..., (VALUE)0);

        # If no rescue clauses, just execute try and ensure inline
        if inst.rescue_clauses.nil? || inst.rescue_clauses.empty?
          return generate_begin_rescue_inline(inst)
        end

        # Generate try callback function
        @rescue_counter ||= 0
        @rescue_counter += 1
        try_func = generate_rescue_try_callback(inst.try_blocks, @rescue_counter)

        # Collect exception classes
        exception_classes = []
        inst.rescue_clauses.each do |clause|
          clause.exception_classes.each do |exc_name|
            exc_val = get_exception_class_value(exc_name)
            exception_classes << exc_val
          end
        end
        exception_classes.uniq!

        has_else = inst.else_blocks && !inst.else_blocks.empty?

        # If else blocks present, use a global flag to detect if rescue ran
        # A module-level global i32 is set to 1 by the rescue callback
        if has_else
          flag_global = @mod.globals.add(LLVM::Int32, "rescue_else_flag_#{@rescue_counter}")
          flag_global.initializer = LLVM::Int32.from_i(0)
          @builder.store(LLVM::Int32.from_i(0), flag_global)

          rescue_func = generate_rescue_handler_with_global_flag_callback(inst.rescue_clauses, @rescue_counter, flag_global)
          args = [try_func, @qnil, rescue_func, @qnil]
        else
          rescue_func = generate_rescue_handler_callback(inst.rescue_clauses, @rescue_counter)
          args = [try_func, @qnil, rescue_func, @qnil]
        end

        args.concat(exception_classes)
        args << LLVM::Int64.from_i(0)  # Terminator

        # Declare rb_rescue2 with correct number of arguments
        rescue2_func = declare_rb_rescue2_variadic(exception_classes.size)
        result = @builder.call(rescue2_func, *args)

        # Execute else blocks if no exception was raised
        if has_else
          flag_val = @builder.load2(LLVM::Int32, flag_global, "flag_val")
          had_exception = @builder.icmp(:ne, flag_val, LLVM::Int32.from_i(0), "had_exception")

          else_bb = @current_function.basic_blocks.append("rescue_else")
          after_else_bb = @current_function.basic_blocks.append("after_rescue_else")

          # Save the block before cond for phi
          no_else_bb = @builder.insert_block
          @builder.cond(had_exception, after_else_bb, else_bb)

          @builder.position_at_end(else_bb)
          else_result = @qnil
          inst.else_blocks.each do |else_inst|
            else_result = generate_instruction(else_inst)
          end
          else_end_bb = @builder.insert_block
          @builder.br(after_else_bb)

          @builder.position_at_end(after_else_bb)
          # When else runs, use else_result; when exception was caught, use rb_rescue2 result
          result = @builder.phi(value_type, { no_else_bb => result, else_end_bb => else_result }, "rescue_else_phi")
        end

        # Execute ensure instructions (always runs)
        if inst.ensure_blocks && !inst.ensure_blocks.empty?
          inst.ensure_blocks.each do |ensure_inst|
            generate_instruction(ensure_inst)
          end
        end

        # Store result
        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate inline try/ensure when no rescue clauses
      def generate_begin_rescue_inline(inst)
        result = @qnil

        # Execute try instructions
        if inst.try_blocks && !inst.try_blocks.empty?
          inst.try_blocks.each do |try_inst|
            result = generate_instruction(try_inst)
          end
        end

        # Execute else instructions (runs if no exception)
        if inst.else_blocks && !inst.else_blocks.empty?
          inst.else_blocks.each do |else_inst|
            result = generate_instruction(else_inst)
          end
        end

        # Execute ensure instructions (always runs)
        if inst.ensure_blocks && !inst.ensure_blocks.empty?
          inst.ensure_blocks.each do |ensure_inst|
            generate_instruction(ensure_inst)
          end
        end

        # Store result
        if inst.result_var
          @variables[inst.result_var] = result || @qnil
          @variable_types[inst.result_var] = :value
        end

        result || @qnil
      end

      # Generate try callback function: VALUE func(VALUE data)
      def generate_rescue_try_callback(try_instructions, counter)
        callback_name = "rescue_try_#{counter}"

        # VALUE func(VALUE data)
        callback_func = @mod.functions.add(callback_name, [value_type], value_type)

        # Save current builder state
        saved_block = @builder.insert_block
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        # Create entry block for callback
        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        # Reset variable tracking for callback scope
        @variables = {}
        @variable_types = {}
        @variable_allocas = {}

        result = @qnil

        # Generate try instructions
        if try_instructions && !try_instructions.empty?
          try_instructions.each do |inst|
            result = generate_instruction(inst)
          end
        end

        # Return the result (or Qnil)
        @builder.ret(result || @qnil)

        # Restore builder state
        @builder.position_at_end(saved_block) if saved_block
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        callback_func
      end

      # Generate rescue handler callback: VALUE func(VALUE exception, VALUE data)
      def generate_rescue_handler_callback(rescue_clauses, counter)
        callback_name = "rescue_handler_#{counter}"

        # VALUE func(VALUE exception, VALUE data)
        callback_func = @mod.functions.add(callback_name, [value_type, value_type], value_type)

        # Save current builder state
        saved_block = @builder.insert_block
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        # Create entry block for callback
        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        # Reset variable tracking for callback scope
        @variables = {}
        @variable_types = {}
        @variable_allocas = {}

        # Get exception parameter
        # CRuby rescue callback: (VALUE data2, VALUE exception)
        exception_val = callback_func.params[1]

        # Match exception class to find correct handler
        if rescue_clauses && !rescue_clauses.empty?
          # Create blocks for each rescue clause and a fallback
          clause_blocks = rescue_clauses.map.with_index do |_, i|
            callback_func.basic_blocks.append("rescue_check_#{i}")
          end
          body_blocks = rescue_clauses.map.with_index do |_, i|
            callback_func.basic_blocks.append("rescue_body_#{i}")
          end
          merge_block = callback_func.basic_blocks.append("rescue_merge")
          fallback_block = callback_func.basic_blocks.append("rescue_fallback")

          # Allocate result variable
          result_alloca = @builder.alloca(value_type, "rescue_result")
          @builder.store(@qnil, result_alloca)

          # Jump to first check
          @builder.br(clause_blocks[0])

          # Generate check and body for each clause
          rescue_clauses.each_with_index do |clause, i|
            # Check block: test if exception matches any of the clause's exception classes
            @builder.position_at_end(clause_blocks[i])

            # Build OR of all exception class checks for this clause
            match_result = nil
            clause.exception_classes.each do |exc_class_name|
              exc_class = get_exception_class_value(exc_class_name)
              # rb_obj_is_kind_of returns Qtrue/Qfalse
              is_match = @builder.call(@rb_obj_is_kind_of, exception_val, exc_class)
              # Compare with Qfalse
              is_match_bool = @builder.icmp(:ne, is_match, @qfalse)

              if match_result.nil?
                match_result = is_match_bool
              else
                match_result = @builder.or(match_result, is_match_bool)
              end
            end

            # If no exception classes specified, match StandardError
            if match_result.nil?
              std_error = @builder.load2(value_type, @rb_eStandardError, "StandardError")
              is_match = @builder.call(@rb_obj_is_kind_of, exception_val, std_error)
              match_result = @builder.icmp(:ne, is_match, @qfalse)
            end

            # Branch to body or next check
            next_block = i < rescue_clauses.size - 1 ? clause_blocks[i + 1] : fallback_block
            @builder.cond(match_result, body_blocks[i], next_block)

            # Body block: execute rescue body
            @builder.position_at_end(body_blocks[i])

            # Reset variables for this body
            @variables = {}
            @variable_types = {}
            @variable_allocas = {}

            # Bind exception variable if specified
            if clause.exception_var
              @variables[clause.exception_var] = exception_val
              @variable_types[clause.exception_var] = :value
            end

            # Generate rescue body instructions
            body_result = @qnil
            clause.body_blocks.each do |inst|
              body_result = generate_instruction(inst)
            end

            # Store result and jump to merge
            @builder.store(body_result || @qnil, result_alloca)
            @builder.br(merge_block)
          end

          # Fallback block: return Qnil (exception was handled by rb_rescue2 but no clause matched)
          @builder.position_at_end(fallback_block)
          @builder.store(@qnil, result_alloca)
          @builder.br(merge_block)

          # Merge block: return result
          @builder.position_at_end(merge_block)
          result = @builder.load2(value_type, result_alloca, "final_result")
          @builder.ret(result)
        else
          # No rescue clauses, just return Qnil
          @builder.ret(@qnil)
        end

        # Restore builder state
        @builder.position_at_end(saved_block) if saved_block
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        callback_func
      end

      # Generate rescue handler callback that sets a global flag when called
      # The flag_global is an LLVM global variable that is set to 1 when rescue is invoked
      def generate_rescue_handler_with_global_flag_callback(rescue_clauses, counter, flag_global)
        callback_name = "rescue_handler_gflag_#{counter}"
        callback_func = @mod.functions.add(callback_name, [value_type, value_type], value_type)

        saved_block = @builder.insert_block
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        @variables = {}
        @variable_types = {}
        @variable_allocas = {}

        # CRuby rescue callback: (VALUE data2, VALUE exception)
        exception_val = callback_func.params[1]

        # Set the global flag to 1 (rescue was invoked)
        @builder.store(LLVM::Int32.from_i(1), flag_global)

        # Same rescue matching logic as generate_rescue_handler_callback
        if rescue_clauses && !rescue_clauses.empty?
          clause_blocks = rescue_clauses.map.with_index do |_, i|
            callback_func.basic_blocks.append("rescue_check_#{i}")
          end
          body_blocks = rescue_clauses.map.with_index do |_, i|
            callback_func.basic_blocks.append("rescue_body_#{i}")
          end
          merge_block = callback_func.basic_blocks.append("rescue_merge")
          fallback_block = callback_func.basic_blocks.append("rescue_fallback")

          result_alloca = @builder.alloca(value_type, "rescue_result")
          @builder.store(@qnil, result_alloca)

          @builder.br(clause_blocks[0])

          rescue_clauses.each_with_index do |clause, i|
            @builder.position_at_end(clause_blocks[i])

            match_result = nil
            clause.exception_classes.each do |exc_class_name|
              exc_class = get_exception_class_value(exc_class_name)
              is_match = @builder.call(@rb_obj_is_kind_of, exception_val, exc_class)
              is_match_bool = @builder.icmp(:ne, is_match, @qfalse)
              if match_result.nil?
                match_result = is_match_bool
              else
                match_result = @builder.or(match_result, is_match_bool)
              end
            end

            if match_result.nil?
              std_error = @builder.load2(value_type, @rb_eStandardError, "StandardError")
              is_match = @builder.call(@rb_obj_is_kind_of, exception_val, std_error)
              match_result = @builder.icmp(:ne, is_match, @qfalse)
            end

            next_block = i < rescue_clauses.size - 1 ? clause_blocks[i + 1] : fallback_block
            @builder.cond(match_result, body_blocks[i], next_block)

            @builder.position_at_end(body_blocks[i])
            @variables = {}
            @variable_types = {}
            @variable_allocas = {}

            if clause.exception_var
              @variables[clause.exception_var] = exception_val
              @variable_types[clause.exception_var] = :value
            end

            body_result = @qnil
            clause.body_blocks.each do |inst|
              body_result = generate_instruction(inst)
            end

            @builder.store(body_result || @qnil, result_alloca)
            @builder.br(merge_block)
          end

          @builder.position_at_end(fallback_block)
          @builder.store(@qnil, result_alloca)
          @builder.br(merge_block)

          @builder.position_at_end(merge_block)
          result = @builder.load2(value_type, result_alloca, "final_result")
          @builder.ret(result)
        else
          @builder.ret(@qnil)
        end

        @builder.position_at_end(saved_block) if saved_block
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        callback_func
      end

      # Legacy: Generate rescue handler callback that sets a flag when called (ptr2int approach)
      # The data parameter (second arg) is a pointer to an i32 flag, cast to VALUE
      def generate_rescue_handler_with_flag_callback(rescue_clauses, counter)
        callback_name = "rescue_handler_flag_#{counter}"
        callback_func = @mod.functions.add(callback_name, [value_type, value_type], value_type)

        saved_block = @builder.insert_block
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup

        entry = callback_func.basic_blocks.append("entry")
        @builder.position_at_end(entry)

        @variables = {}
        @variable_types = {}
        @variable_allocas = {}

        # CRuby rescue callback: (VALUE data2, VALUE exception)
        data_val = callback_func.params[0]
        exception_val = callback_func.params[1]

        # Set the flag: data is a pointer to i32, cast from VALUE
        flag_ptr = @builder.int2ptr(data_val, LLVM::Pointer(LLVM::Int32), "flag_ptr")
        @builder.store(LLVM::Int32.from_i(1), flag_ptr)

        # Same rescue matching logic as generate_rescue_handler_callback
        if rescue_clauses && !rescue_clauses.empty?
          clause_blocks = rescue_clauses.map.with_index do |_, i|
            callback_func.basic_blocks.append("rescue_check_#{i}")
          end
          body_blocks = rescue_clauses.map.with_index do |_, i|
            callback_func.basic_blocks.append("rescue_body_#{i}")
          end
          merge_block = callback_func.basic_blocks.append("rescue_merge")
          fallback_block = callback_func.basic_blocks.append("rescue_fallback")

          result_alloca = @builder.alloca(value_type, "rescue_result")
          @builder.store(@qnil, result_alloca)

          @builder.br(clause_blocks[0])

          rescue_clauses.each_with_index do |clause, i|
            @builder.position_at_end(clause_blocks[i])

            match_result = nil
            clause.exception_classes.each do |exc_class_name|
              exc_class = get_exception_class_value(exc_class_name)
              is_match = @builder.call(@rb_obj_is_kind_of, exception_val, exc_class)
              is_match_bool = @builder.icmp(:ne, is_match, @qfalse)
              if match_result.nil?
                match_result = is_match_bool
              else
                match_result = @builder.or(match_result, is_match_bool)
              end
            end

            if match_result.nil?
              std_error = @builder.load2(value_type, @rb_eStandardError, "StandardError")
              is_match = @builder.call(@rb_obj_is_kind_of, exception_val, std_error)
              match_result = @builder.icmp(:ne, is_match, @qfalse)
            end

            next_block = i < rescue_clauses.size - 1 ? clause_blocks[i + 1] : fallback_block
            @builder.cond(match_result, body_blocks[i], next_block)

            @builder.position_at_end(body_blocks[i])
            @variables = {}
            @variable_types = {}
            @variable_allocas = {}

            if clause.exception_var
              @variables[clause.exception_var] = exception_val
              @variable_types[clause.exception_var] = :value
            end

            body_result = @qnil
            clause.body_blocks.each do |inst|
              body_result = generate_instruction(inst)
            end

            @builder.store(body_result || @qnil, result_alloca)
            @builder.br(merge_block)
          end

          @builder.position_at_end(fallback_block)
          @builder.store(@qnil, result_alloca)
          @builder.br(merge_block)

          @builder.position_at_end(merge_block)
          result = @builder.load2(value_type, result_alloca, "final_result")
          @builder.ret(result)
        else
          @builder.ret(@qnil)
        end

        @builder.position_at_end(saved_block) if saved_block
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        callback_func
      end

      # Generate case/when statement
      # Uses === (case equality) for matching
      def generate_case_statement(inst)
        # If no when clauses, return nil or execute else body
        if inst.when_clauses.nil? || inst.when_clauses.empty?
          if inst.else_body && !inst.else_body.empty?
            result = @qnil
            inst.else_body.each do |else_inst|
              result = generate_instruction(else_inst)
            end
            @variables[inst.result_var] = result if inst.result_var
            return result
          else
            @variables[inst.result_var] = @qnil if inst.result_var
            return @qnil
          end
        end

        # Get predicate value (boxed for === calls)
        predicate_val = nil
        if inst.predicate
          predicate_val = get_value_as_ruby(inst.predicate)
        end

        # Create merge block
        merge_block = @builder.insert_block.parent.basic_blocks.append("case_merge")

        # Track incoming values for phi node with type info for optimization
        incoming_data = []  # Array of [block, value, type_tag]

        # Generate each when clause
        inst.when_clauses.each_with_index do |when_clause, i|
          when_body_block = @builder.insert_block.parent.basic_blocks.append("when_body_#{i}")
          next_check_block = @builder.insert_block.parent.basic_blocks.append("when_check_#{i + 1}")

          # Check all conditions in this when clause (OR them together)
          match_result = nil
          when_clause.conditions.each do |cond|
            cond_val = get_value_as_ruby(cond)

            # Call === on the condition value with predicate as argument
            # cond === predicate (pass cond HIR for inline optimization)
            cond_match = if predicate_val
              call_case_equality(cond_val, predicate_val, receiver_hir: cond)
            else
              # Case without predicate - evaluate condition as truthy
              cond_val
            end

            if match_result.nil?
              match_result = cond_match
            else
              # OR with previous conditions
              # Convert to boolean if needed
              prev_bool = match_result.type == LLVM::Int1 ? match_result : ruby_to_bool(match_result)
              curr_bool = ruby_to_bool(cond_match)
              match_result = @builder.or(prev_bool, curr_bool)
            end
          end

          # Convert match result to i1 for branch
          match_bool = match_result.is_a?(LLVM::Value) && match_result.type == LLVM::Int1 ? match_result : ruby_to_bool(match_result)

          @builder.cond(match_bool, when_body_block, next_check_block)

          # Generate when body
          @builder.position_at_end(when_body_block)
          body_result = @qnil
          body_type_tag = :value
          when_clause.body.each do |body_inst|
            body_result = generate_instruction(body_inst)
          end
          # Get the type tag for the result
          if body_result
            body_result, body_type_tag = get_result_with_type(body_result, when_clause.body.last)
          else
            body_result = @qnil
            body_type_tag = :value
          end
          incoming_data << [@builder.insert_block, body_result, body_type_tag]
          @builder.br(merge_block)

          # Move to next check block
          @builder.position_at_end(next_check_block)
        end

        # Generate else body or nil
        if inst.else_body && !inst.else_body.empty?
          else_result = @qnil
          else_type_tag = :value
          inst.else_body.each do |else_inst|
            else_result = generate_instruction(else_inst)
          end
          if else_result
            else_result, else_type_tag = get_result_with_type(else_result, inst.else_body.last)
          else
            else_result = @qnil
            else_type_tag = :value
          end
          incoming_data << [@builder.insert_block, else_result, else_type_tag]
        else
          incoming_data << [@builder.insert_block, @qnil, :value]
        end
        @builder.br(merge_block)

        # Compute the optimal phi type
        result_type_tag = compute_phi_type_tag(incoming_data)
        llvm_phi_type = type_tag_to_llvm_type(result_type_tag)

        # Convert values to the target type in their source blocks (before br)
        converted_incoming = convert_phi_incoming_values(incoming_data, result_type_tag, merge_block)

        # Create phi node at merge
        @builder.position_at_end(merge_block)
        result = @builder.phi(llvm_phi_type, converted_incoming)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = result_type_tag
        end
        result
      end

      # Call === (case equality) on receiver with argument
      # Call case equality with optimized inline comparison for basic types
      def call_case_equality(receiver, arg, receiver_hir: nil)
        # Try to inline for known types
        if receiver_hir.is_a?(HIR::IntegerLit)
          # Integer === arg: Check if arg is a Fixnum with same value
          return inline_integer_case_eq(receiver_hir.value, arg)
        elsif receiver_hir.is_a?(HIR::StringLit)
          # String === arg: Use rb_str_equal
          return inline_string_case_eq(receiver, arg)
        elsif receiver_hir.is_a?(HIR::ConstantLookup)
          # Class/Module === arg: Use rb_obj_is_kind_of
          return inline_class_case_eq(receiver, arg)
        end

        # Fallback to rb_funcallv for dynamic cases
        method_ptr = @builder.global_string_pointer("===")
        method_id = @builder.call(@rb_intern, method_ptr)

        argc = LLVM::Int32.from_i(1)
        argv = @builder.alloca(LLVM::Array(value_type, 1))
        ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)])
        @builder.store(arg, ptr)
        argv = @builder.bit_cast(argv, LLVM::Pointer(value_type))

        @builder.call(@rb_funcallv, receiver, method_id, argc, argv)
      end

      # Inline Integer === arg comparison
      def inline_integer_case_eq(expected_value, arg)
        # Check if arg is a Fixnum: RB_FIXNUM_P(arg) && FIX2LONG(arg) == expected
        # Fixnum check: (arg & 1) == 1 (Fixnum has LSB set)
        is_fixnum = @builder.and(arg, LLVM::Int64.from_i(1))
        is_fixnum_bool = @builder.icmp(:eq, is_fixnum, LLVM::Int64.from_i(1))

        # Extract the value: FIX2LONG(arg) = (arg >> 1)
        arg_value = @builder.ashr(arg, LLVM::Int64.from_i(1))

        # Compare values
        values_equal = @builder.icmp(:eq, arg_value, LLVM::Int64.from_i(expected_value))

        # Result is true if both checks pass
        result_bool = @builder.and(is_fixnum_bool, values_equal)

        # Convert i1 to VALUE (Qtrue/Qfalse)
        @builder.select(result_bool, @qtrue, @qfalse)
      end

      # Inline String === arg comparison
      def inline_string_case_eq(receiver, arg)
        # Use rb_str_equal which returns Qtrue/Qfalse
        @builder.call(@rb_str_equal, receiver, arg)
      end

      # Inline Class === arg comparison (checks if arg is instance of class)
      def inline_class_case_eq(klass, arg)
        # Use rb_obj_is_kind_of(arg, klass) which returns int (0 or non-zero)
        result_int = @builder.call(@rb_obj_is_kind_of, arg, klass)
        # Convert int to VALUE
        is_true = @builder.icmp(:ne, result_int, LLVM::Int32.from_i(0))
        @builder.select(is_true, @qtrue, @qfalse)
      end

      # Generate LLVM value for keyword argument default from Prism AST node
      def generate_keyword_default_value(prism_node)
        case prism_node
        when Prism::StringNode
          str_ptr = @builder.global_string_pointer(prism_node.unescaped)
          @builder.call(@rb_str_new_cstr, str_ptr)
        when Prism::IntegerNode
          @builder.call(@rb_int2inum, LLVM::Int64.from_i(prism_node.value))
        when Prism::FloatNode
          @builder.call(@rb_float_new, LLVM::Double.from_f(prism_node.value))
        when Prism::NilNode
          @qnil
        when Prism::TrueNode
          @qtrue
        when Prism::FalseNode
          @qfalse
        when Prism::SymbolNode
          sym_ptr = @builder.global_string_pointer(prism_node.value)
          sym_id = @builder.call(@rb_intern, sym_ptr)
          @builder.call(@rb_id2sym, sym_id)
        else
          @qnil
        end
      end

      # Convert Ruby VALUE to i1 boolean
      def ruby_to_bool(value)
        # In Ruby, only nil and false are falsy
        # Qnil = 0x08, Qfalse = 0x00 (on 64-bit systems)
        # A simple check: value != Qnil && value != Qfalse
        cmp_nil = @builder.icmp(:ne, value, @qnil)
        cmp_false = @builder.icmp(:ne, value, @qfalse)
        @builder.and(cmp_nil, cmp_false)
      end

      # ========================================
      # Pattern Matching Code Generation
      # ========================================

      # Generate case/in pattern matching statement
      def generate_case_match_statement(inst)
        # If no in clauses, return nil or execute else body
        if inst.in_clauses.nil? || inst.in_clauses.empty?
          if inst.else_body && !inst.else_body.empty?
            result = @qnil
            inst.else_body.each do |else_inst|
              result = generate_instruction(else_inst)
            end
            @variables[inst.result_var] = result if inst.result_var
            return result
          else
            # No else and no clauses - raise NoMatchingPatternError
            raise_no_matching_pattern_error(get_value_as_ruby(inst.predicate))
            @variables[inst.result_var] = @qnil if inst.result_var
            return @qnil
          end
        end

        # Get predicate value
        predicate_val = get_value_as_ruby(inst.predicate)

        # Create merge block
        merge_block = @builder.insert_block.parent.basic_blocks.append("match_merge")

        # Track incoming values for phi node with type info for optimization
        incoming_data = []  # Array of [block, value, type_tag]

        # Generate each in clause
        inst.in_clauses.each_with_index do |in_clause, i|
          match_block = @builder.insert_block.parent.basic_blocks.append("in_match_#{i}")
          body_block = @builder.insert_block.parent.basic_blocks.append("in_body_#{i}")
          next_check_block = @builder.insert_block.parent.basic_blocks.append("in_next_#{i}")

          # Jump to match block
          @builder.br(match_block)
          @builder.position_at_end(match_block)

          # Compile pattern match - returns [match_bool, bound_vars_hash]
          match_bool, bound_vars = compile_pattern(in_clause.pattern, predicate_val)

          # Check guard if present
          if in_clause.guard
            guard_check_block = @builder.insert_block.parent.basic_blocks.append("guard_#{i}")
            @builder.cond(match_bool, guard_check_block, next_check_block)

            @builder.position_at_end(guard_check_block)
            # Bind variables for guard evaluation
            bound_vars.each do |name, val|
              @variables[name] = val
              @variable_types[name] = :value
            end
            guard_val = generate_instruction(in_clause.guard)
            guard_val_ruby = get_value_as_ruby_from_value(guard_val)
            guard_bool = ruby_to_bool(guard_val_ruby)
            @builder.cond(guard_bool, body_block, next_check_block)
          else
            @builder.cond(match_bool, body_block, next_check_block)
          end

          # Generate body
          @builder.position_at_end(body_block)

          # Bind pattern variables
          bound_vars.each do |name, val|
            @variables[name] = val
            @variable_types[name] = :value
          end

          # Apply type narrowing for ConstantPattern
          # If the pattern is a type check (e.g., `in Integer`), narrow the predicate variable's type
          predicate_var_name = extract_predicate_var_name(inst.predicate)
          original_predicate_type = nil
          if predicate_var_name && in_clause.pattern.is_a?(HIR::ConstantPattern) && in_clause.pattern.narrowed_type
            original_predicate_type = @variable_types[predicate_var_name]
            @variable_types[predicate_var_name] = type_to_internal_tag(in_clause.pattern.narrowed_type)
          end

          body_result = @qnil
          body_type_tag = :value
          in_clause.body.each do |body_inst|
            body_result = generate_instruction(body_inst)
          end

          # Restore original predicate type after body generation
          if original_predicate_type
            @variable_types[predicate_var_name] = original_predicate_type
          end

          # Get the type tag for the result
          if body_result
            body_result, body_type_tag = get_result_with_type(body_result, in_clause.body.last)
          else
            body_result = @qnil
            body_type_tag = :value
          end

          incoming_data << [@builder.insert_block, body_result, body_type_tag]
          @builder.br(merge_block)

          # Move to next check
          @builder.position_at_end(next_check_block)
        end

        # Else or NoMatchingPatternError
        if inst.else_body && !inst.else_body.empty?
          else_result = @qnil
          else_type_tag = :value
          inst.else_body.each { |else_inst| else_result = generate_instruction(else_inst) }
          if else_result
            else_result, else_type_tag = get_result_with_type(else_result, inst.else_body.last)
          else
            else_result = @qnil
            else_type_tag = :value
          end
          incoming_data << [@builder.insert_block, else_result, else_type_tag]
          @builder.br(merge_block)
        else
          # Raise NoMatchingPatternError
          raise_no_matching_pattern_error(predicate_val)
          incoming_data << [@builder.insert_block, @qnil, :value]
          @builder.br(merge_block)
        end

        # Compute the optimal phi type
        result_type_tag = compute_phi_type_tag(incoming_data)
        llvm_phi_type = type_tag_to_llvm_type(result_type_tag)

        # Convert values to the target type in their source blocks (before br)
        converted_incoming = convert_phi_incoming_values(incoming_data, result_type_tag, merge_block)

        # Create phi node at merge
        @builder.position_at_end(merge_block)
        result = @builder.phi(llvm_phi_type, converted_incoming)

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = result_type_tag
        end
        result
      end

      # Extract variable name from predicate instruction for type narrowing
      def extract_predicate_var_name(predicate)
        case predicate
        when HIR::LoadLocal
          # LoadLocal has a LocalVar in .var, which has .name
          predicate.var.name.to_sym
        when HIR::Param
          predicate.name.to_sym
        else
          nil
        end
      end

      # Convert an internal type to a type tag for @variable_types
      def type_to_internal_tag(type)
        case type
        when TypeChecker::Types::ClassInstance
          case type.name
          when :Integer then :i64
          when :Float then :double
          else :value
          end
        when TypeChecker::Types::NativeArrayType
          case type.element_type
          when :Int64 then :native_array_i64
          when :Float64 then :native_array_f64
          else :native_array
          end
        else
          :value
        end
      end

      # Compile a pattern, returns [match_bool (i1), bound_vars_hash]
      def compile_pattern(pattern, value)
        case pattern
        when HIR::LiteralPattern
          compile_literal_pattern(pattern, value)
        when HIR::VariablePattern
          compile_variable_pattern(pattern, value)
        when HIR::ConstantPattern
          compile_constant_pattern(pattern, value)
        when HIR::AlternationPattern
          compile_alternation_pattern(pattern, value)
        when HIR::ArrayPattern
          compile_array_pattern(pattern, value)
        when HIR::HashPattern
          compile_hash_pattern(pattern, value)
        when HIR::CapturePattern
          compile_capture_pattern(pattern, value)
        when HIR::PinnedPattern
          compile_pinned_pattern(pattern, value)
        when HIR::RestPattern
          # Rest pattern always matches and binds the value
          compile_rest_pattern(pattern, value)
        else
          # Unknown pattern - match anything
          [LLVM::Int1.from_i(1), {}]
        end
      end

      # Literal pattern: use === for matching
      def compile_literal_pattern(pattern, value)
        literal_val = generate_instruction(pattern.value)
        literal_val = get_value_as_ruby_from_value(literal_val)
        match_result = call_case_equality(literal_val, value)
        match_bool = ruby_to_bool(match_result)
        [match_bool, {}]
      end

      # Variable pattern: always matches, binds the value
      def compile_variable_pattern(pattern, value)
        bound_vars = { pattern.name => value }
        [LLVM::TRUE, bound_vars]
      end

      # Constant/Type pattern: use === for matching (e.g., Integer === value)
      def compile_constant_pattern(pattern, value)
        # Get the constant value
        const_val = get_constant_value(pattern.constant_name)
        # Call === on the constant
        match_result = call_case_equality(const_val, value)
        match_bool = ruby_to_bool(match_result)
        [match_bool, {}]
      end

      # Alternation pattern: match any of the alternatives
      def compile_alternation_pattern(pattern, value)
        match_result = LLVM::FALSE
        bound_vars = {}

        pattern.alternatives.each do |alt|
          alt_match, alt_vars = compile_pattern(alt, value)
          match_result = @builder.or(match_result, alt_match)
          # Note: in alternation, variables from different branches should be the same
          # For simplicity, we take the first binding
          bound_vars.merge!(alt_vars) if bound_vars.empty?
        end

        [match_result, bound_vars]
      end

      # Array pattern: call deconstruct and match elements
      # Refactored to linear flow - eliminates phi node predecessor issues
      def compile_array_pattern(pattern, value)
        bound_vars = {}

        # Initialize match result as true
        match_result = LLVM::TRUE

        # Step 1: Type check (if constant specified)
        if pattern.constant
          const_val = get_constant_value(pattern.constant)
          type_match = call_case_equality(const_val, value)
          type_bool = ruby_to_bool(type_match)
          match_result = @builder.and(match_result, type_bool)
        end

        # Step 2: Call deconstruct
        deconstruct_id = intern_method("deconstruct")
        argc = LLVM::Int32.from_i(0)
        argv = LLVM::Pointer(value_type).null
        deconstructed = @builder.call(@rb_funcallv, value, deconstruct_id, argc, argv)

        # Step 3: Check array length
        required_count = pattern.requireds.size + pattern.posts.size
        arr_len = call_array_length(deconstructed)

        len_ok = if pattern.rest
          # At least required_count elements
          @builder.icmp(:sge, arr_len, LLVM::Int64.from_i(required_count))
        else
          # Exactly required_count elements
          @builder.icmp(:eq, arr_len, LLVM::Int64.from_i(required_count))
        end
        match_result = @builder.and(match_result, len_ok)

        # Step 4: Match each required element
        pattern.requireds.each_with_index do |elem_pattern, i|
          elem = call_array_entry(deconstructed, LLVM::Int64.from_i(i))
          elem_match, elem_vars = compile_pattern(elem_pattern, elem)
          match_result = @builder.and(match_result, elem_match)
          bound_vars.merge!(elem_vars)
        end

        # Step 5: Handle rest pattern
        if pattern.rest && pattern.rest.name
          # Extract rest elements into new array
          rest_start = LLVM::Int64.from_i(pattern.requireds.size)
          rest_len = @builder.sub(arr_len, LLVM::Int64.from_i(required_count))
          rest_arr = create_array_slice(deconstructed, rest_start, rest_len)
          bound_vars[pattern.rest.name] = rest_arr
        end

        # Step 6: Match post elements
        pattern.posts.each_with_index do |post_pattern, i|
          # Index from end: arr_len - posts.size + i
          offset = LLVM::Int64.from_i(pattern.posts.size - i)
          post_idx = @builder.sub(arr_len, offset)
          elem = call_array_entry(deconstructed, post_idx)
          elem_match, elem_vars = compile_pattern(post_pattern, elem)
          match_result = @builder.and(match_result, elem_match)
          bound_vars.merge!(elem_vars)
        end

        [match_result, bound_vars]
      end

      # Hash pattern: call deconstruct_keys and match elements
      # Refactored to linear flow - eliminates phi node predecessor issues
      def compile_hash_pattern(pattern, value)
        bound_vars = {}

        # Initialize match result as true
        match_result = LLVM::TRUE

        # Step 1: Type check (if constant specified)
        if pattern.constant
          const_val = get_constant_value(pattern.constant)
          type_match = call_case_equality(const_val, value)
          type_bool = ruby_to_bool(type_match)
          match_result = @builder.and(match_result, type_bool)
        end

        # Step 2: Create keys array for deconstruct_keys
        keys_array = create_keys_array(pattern.elements.map(&:key))

        # Step 3: Call deconstruct_keys
        deconstruct_keys_id = intern_method("deconstruct_keys")
        argc = LLVM::Int32.from_i(1)
        argv = @builder.alloca(LLVM::Array(value_type, 1))
        ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)])
        @builder.store(keys_array, ptr)
        argv_ptr = @builder.bit_cast(argv, LLVM::Pointer(value_type))
        deconstructed = @builder.call(@rb_funcallv, value, deconstruct_keys_id, argc, argv_ptr)

        # Step 4: Match each key-value pair
        pattern.elements.each do |elem|
          key_sym = create_symbol(elem.key)
          val = call_hash_lookup(deconstructed, key_sym)

          # Check if key present (val != Qundef)
          present = @builder.icmp(:ne, val, @qundef)
          match_result = @builder.and(match_result, present)

          if elem.value_pattern
            # Match value against pattern
            val_match, val_vars = compile_pattern(elem.value_pattern, val)
            match_result = @builder.and(match_result, val_match)
            bound_vars.merge!(val_vars)
          else
            # Shorthand: bind key name to value
            bound_vars[elem.key] = val
          end
        end

        # Step 5: Handle rest pattern
        if pattern.rest && pattern.rest.name
          # For simplicity, bind rest to the whole hash (proper impl would filter)
          bound_vars[pattern.rest.name] = deconstructed
        end

        [match_result, bound_vars]
      end

      # Capture pattern: match inner pattern and bind to variable
      def compile_capture_pattern(pattern, value)
        inner_match, inner_vars = compile_pattern(pattern.value_pattern, value)
        bound_vars = inner_vars.dup
        bound_vars[pattern.target] = value
        [inner_match, bound_vars]
      end

      # Pinned pattern: match against existing variable value
      def compile_pinned_pattern(pattern, value)
        # Get the variable value - check both @variables and @variable_allocas
        var_name = pattern.variable_name
        var_val = @variables[var_name]

        # If not in @variables, try to load from alloca (for parameters)
        if var_val.nil?
          alloca = @variable_allocas[var_name]
          if alloca
            type_tag = @variable_types[var_name] || :value
            llvm_type = case type_tag
            when :i64 then LLVM::Int64
            when :double then LLVM::Double
            when :i8 then LLVM::Int8
            else value_type
            end
            var_val = @builder.load2(llvm_type, alloca, var_name)
          end
        end

        if var_val.nil?
          # Variable not found, fail
          return [LLVM::Int1.from_i(0), {}]
        end

        var_val = get_value_as_ruby_from_value(var_val)

        # Use == for comparison
        eq_id = intern_method("==")
        argc = LLVM::Int32.from_i(1)
        argv = @builder.alloca(LLVM::Array(value_type, 1))
        ptr = @builder.gep(argv, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)])
        @builder.store(value, ptr)
        argv_ptr = @builder.bit_cast(argv, LLVM::Pointer(value_type))
        eq_result = @builder.call(@rb_funcallv, var_val, eq_id, argc, argv_ptr)
        match_bool = ruby_to_bool(eq_result)

        [match_bool, {}]
      end

      # Rest pattern: always matches
      def compile_rest_pattern(pattern, value)
        bound_vars = {}
        if pattern.name
          bound_vars[pattern.name] = value
        end
        [LLVM::Int1.from_i(1), bound_vars]
      end

      # Generate match predicate: expr in pattern (returns boolean)
      def generate_match_predicate(inst)
        value = get_value_as_ruby(inst.value)
        match_bool, _bound_vars = compile_pattern(inst.pattern, value)

        # Convert i1 to Ruby boolean
        result = @builder.select(match_bool, @qtrue, @qfalse)

        @variables[inst.result_var] = result if inst.result_var
        @variable_types[inst.result_var] = :value if inst.result_var
        result
      end

      # Generate match required: expr => pattern (raises on failure)
      def generate_match_required(inst)
        value = get_value_as_ruby(inst.value)
        match_bool, bound_vars = compile_pattern(inst.pattern, value)

        # Create blocks for success/failure
        current_fn = @builder.insert_block.parent
        success_block = current_fn.basic_blocks.append("match_req_success")
        fail_block = current_fn.basic_blocks.append("match_req_fail")

        @builder.cond(match_bool, success_block, fail_block)

        @builder.position_at_end(fail_block)
        raise_no_matching_pattern_error(value)
        @builder.unreachable

        @builder.position_at_end(success_block)

        # Bind pattern variables
        bound_vars.each do |name, val|
          @variables[name] = val
          @variable_types[name] = :value
        end

        @variables[inst.result_var] = value if inst.result_var
        @variable_types[inst.result_var] = :value if inst.result_var
        value
      end

      # Helper: raise NoMatchingPatternError
      def raise_no_matching_pattern_error(value)
        # rb_raise(rb_eNoMatchingPatternError, "...")
        # For simplicity, we'll raise RuntimeError with a message
        exc_class = get_exception_class_value("NoMatchingPatternError")
        msg_ptr = @builder.global_string_pointer("no matching pattern")

        # Use rb_raise
        @builder.call(@rb_raise, exc_class, msg_ptr)
      end

      # Helper: get constant value by name
      def get_constant_value(name)
        return @qnil if name.nil?

        # Handle common constants
        case name
        when "Integer"
          @builder.load2(value_type, @rb_cInteger, "rb_cInteger")
        when "String"
          @builder.load2(value_type, @rb_cString, "rb_cString")
        when "Float"
          @builder.load2(value_type, @rb_cFloat, "rb_cFloat")
        when "Array"
          @builder.load2(value_type, @rb_cArray, "rb_cArray")
        when "Hash"
          @builder.load2(value_type, @rb_cHash, "rb_cHash")
        when "Symbol"
          @builder.load2(value_type, @rb_cSymbol, "rb_cSymbol")
        when "NilClass"
          @builder.load2(value_type, @rb_cNilClass, "rb_cNilClass")
        when "TrueClass"
          @builder.load2(value_type, @rb_cTrueClass, "rb_cTrueClass")
        when "FalseClass"
          @builder.load2(value_type, @rb_cFalseClass, "rb_cFalseClass")
        else
          # Look up via rb_const_get
          rb_cObject = @builder.load2(value_type, @rb_cObject, "rb_cObject")
          name_ptr = @builder.global_string_pointer(name)
          name_id = @builder.call(@rb_intern, name_ptr)
          @builder.call(@rb_const_get, rb_cObject, name_id)
        end
      end

      # Helper: intern a method name
      def intern_method(name)
        method_ptr = @builder.global_string_pointer(name)
        @builder.call(@rb_intern, method_ptr)
      end

      # Helper: call array length
      def call_array_length(arr)
        # Use rb_funcallv to call length method instead of rb_array_len
        # (rb_array_len is not exported from libruby)
        length_id = @builder.call(@rb_intern, @builder.global_string_pointer("length"))
        length_value = @builder.call(@rb_funcallv, arr, length_id, LLVM::Int32.from_i(0), LLVM::Pointer(value_type).null)
        @builder.call(@rb_num2long, length_value)
      end

      # Helper: call rb_ary_entry
      def call_array_entry(arr, idx)
        @builder.call(@rb_ary_entry, arr, idx)
      end

      # Helper: create array slice (for rest pattern)
      def create_array_slice(arr, start_idx, len)
        # rb_ary_subseq(arr, start, len)
        unless @rb_ary_subseq
          @rb_ary_subseq = @mod.functions.add("rb_ary_subseq", [value_type, LLVM::Int64, LLVM::Int64], value_type)
        end
        @builder.call(@rb_ary_subseq, arr, start_idx, len)
      end

      # Helper: create keys array for deconstruct_keys
      def create_keys_array(keys)
        # Create Ruby array with symbol keys
        arr = @builder.call(@rb_ary_new)
        keys.each do |key|
          key_sym = create_symbol(key)
          @builder.call(@rb_ary_push, arr, key_sym)
        end
        arr
      end

      # Helper: create Ruby symbol
      def create_symbol(name)
        name_ptr = @builder.global_string_pointer(name.to_s)
        id = @builder.call(@rb_intern, name_ptr)
        @builder.call(@rb_id2sym, id)
      end

      # Helper: call rb_hash_lookup2 with Qundef as default
      def call_hash_lookup(hash, key)
        @builder.call(@rb_hash_lookup2, hash, key, @qundef)
      end

      # Helper: convert arbitrary value to Ruby VALUE
      def get_value_as_ruby_from_value(val)
        return @qnil if val.nil?

        # Check if value needs boxing
        if val.is_a?(LLVM::Value)
          # Constants (like LLVM::Int64.from_i(1)) need boxing
          # Instruction results (like rb_str_new_cstr calls) are already VALUEs
          if val.is_a?(LLVM::Constant)
            case val.type
            when LLVM::Int64
              @builder.call(@rb_int2inum, val)
            when LLVM::Double
              @builder.call(@rb_float_new, val)
            else
              val
            end
          else
            # Not a constant - assume it's already a boxed VALUE
            val
          end
        else
          val
        end
      end

      # Get VALUE for exception class by name
      def get_exception_class_value(exc_name)
        case exc_name
        when "StandardError"
          @builder.load2(value_type, @rb_eStandardError, "StandardError")
        when "RuntimeError"
          @builder.load2(value_type, @rb_eRuntimeError, "RuntimeError")
        else
          # Look up the exception class via rb_const_get
          rb_cObject = @builder.load2(value_type, @rb_cObject, "rb_cObject")
          name_ptr = @builder.global_string_pointer(exc_name)
          name_id = @builder.call(@rb_intern, name_ptr)
          @builder.call(@rb_const_get, rb_cObject, name_id)
        end
      end

      # Declare rb_rescue2 with the correct number of exception class arguments
      def declare_rb_rescue2_variadic(num_exceptions)
        func_name = "rb_rescue2"

        # Check if already declared
        existing = @mod.functions[func_name]
        if existing
          return existing
        end

        # rb_rescue2 is a variadic C function:
        # VALUE rb_rescue2(VALUE (*b_proc)(VALUE), VALUE data1,
        #                  VALUE (*r_proc)(VALUE, VALUE), VALUE data2, ...)
        # The variadic part is: exception classes..., (VALUE)0 terminator
        # On ARM64, variadic args use different calling convention (stack vs registers),
        # so we MUST declare this as variadic for correct behavior.

        # try callback: VALUE (*)(VALUE)
        try_type = LLVM::Type.function([value_type], value_type)
        # rescue callback: VALUE (*)(VALUE, VALUE)
        rescue_type = LLVM::Type.function([value_type, value_type], value_type)

        # Fixed parameter types (before the variadic part)
        param_types = [
          LLVM::Pointer(try_type),   # try func
          value_type,                 # data1
          LLVM::Pointer(rescue_type), # rescue func
          value_type,                 # data2
        ]

        # Create variadic function type
        func_type = LLVM::Type.function(param_types, value_type, varargs: true)
        @mod.functions.add(func_name, func_type)
      end

      def generate_phi(inst)
        # Collect incoming values with their type tags for optimization
        incoming_data = []

        inst.incoming.each do |label, hir_value|
          llvm_block = @blocks[label]
          next unless llvm_block
          # Skip blocks with Return terminators — they don't branch to the
          # merge block, so they cannot be predecessors in the phi node.
          next if @return_blocks&.include?(label)
          llvm_value, type_tag = get_value_with_type(hir_value)
          incoming_data << [llvm_block, llvm_value, type_tag]
        end

        if incoming_data.empty?
          @variables[inst.result_var] = @qnil if inst.result_var
          @variable_types[inst.result_var] = :value if inst.result_var
          return @qnil
        end

        # Determine the optimal phi type (unboxed if all incoming values match)
        result_type_tag = compute_phi_type_tag(incoming_data)
        llvm_phi_type = type_tag_to_llvm_type(result_type_tag)

        # Remember current position (merge block)
        merge_block = @builder.insert_block

        # Convert values to the target type in their source blocks (before br)
        incoming = convert_phi_incoming_values(incoming_data, result_type_tag, merge_block)

        # Position back at merge block and create phi
        @builder.position_at_end(merge_block)
        phi = @builder.phi(llvm_phi_type, incoming)

        if inst.result_var
          @variables[inst.result_var] = phi
          @variable_types[inst.result_var] = result_type_tag
        end

        phi
      end

      def generate_terminator(term)
        case term
        when HIR::Return
          # Insert profiling exit probe before return
          insert_profile_exit_probe

          if @current_native_class
            # Native method: return unboxed value
            generate_native_return(term)
          elsif term.value
            value, type_tag = get_value_with_type(term.value)
            # Box the value before returning to Ruby
            boxed = convert_value(value, type_tag, :value)
            @builder.ret(boxed)
          else
            @builder.ret(@qnil)
          end
        when HIR::Branch
          condition, cond_type = get_value_with_type(term.condition)

          is_truthy = case cond_type
          when :i64
            if comparison_result?(term.condition)
              # Comparison result (0=false, 1=true): use C-style truthiness
              @builder.icmp(:ne, condition, LLVM::Int64.from_i(0))
            else
              # Ruby: all integers (including 0) are truthy.
              # Box to VALUE and use Ruby truthiness (RTEST).
              boxed = @builder.call(@rb_int2inum, condition)
              ruby_to_bool(boxed)
            end
          when :double
            if comparison_result?(term.condition)
              # Comparison result: use C-style truthiness
              @builder.fcmp(:one, condition, LLVM::Double.from_f(0.0))
            else
              # Ruby: all floats (including 0.0) are truthy.
              # Box to VALUE and use Ruby truthiness (RTEST).
              boxed = @builder.call(@rb_float_new, condition)
              ruby_to_bool(boxed)
            end
          when :i8
            # For i8 (Bool field), non-zero is truthy
            @builder.icmp(:ne, condition, LLVM::Int8.from_i(0))
          else
            # For VALUE, use RTEST: (condition & ~Qnil) != 0
            not_qnil = @builder.xor(@qnil, LLVM::Int64.from_i(-1))
            masked = @builder.and(condition, not_qnil)
            @builder.icmp(:ne, masked, LLVM::Int64.from_i(0))
          end

          then_block = @blocks[term.then_block]
          else_block = @blocks[term.else_block]
          @builder.cond(is_truthy, then_block, else_block)
        when HIR::Jump
          target = @blocks[term.target]
          @builder.br(target)
        end
      end

      # Check if an HIR condition node represents a comparison result (boolean 0/1)
      # rather than a raw integer/float value.
      # In Ruby, only nil and false are falsy — integers (including 0) and floats are always truthy.
      COMPARISON_METHODS = %w[== != < > <= >=].freeze

      def comparison_result?(hir_condition)
        case hir_condition
        when HIR::Call
          COMPARISON_METHODS.include?(hir_condition.method_name)
        when HIR::LoadLocal
          var_name = hir_condition.var&.name
          @comparison_result_vars.include?(var_name)
        when HIR::Instruction
          hir_condition.result_var && @comparison_result_vars.include?(hir_condition.result_var)
        else
          false
        end
      end

      # Generate return for a native method (unboxed return value)
      def generate_native_return(term)
        method_name = @current_hir_func&.name&.to_sym
        method_sig = @current_native_class.methods[method_name]
        return_type_sym = method_sig&.return_type || :Float64

        if return_type_sym == :Void
          # Void return
          @builder.ret_void
        elsif term.value
          value, type_tag = get_value_with_type(term.value)

          # Convert to expected return type
          expected_tag = case return_type_sym
          when :Int64 then :i64
          when :Float64 then :double
          when :Self then :native_class
          else :native_class
          end

          if expected_tag == :native_class
            # Return struct by value - load from pointer
            struct_type = get_or_create_native_class_struct(@current_native_class)
            struct_value = @builder.load2(struct_type, value, "return_val")
            @builder.ret(struct_value)
          else
            converted = convert_value(value, type_tag, expected_tag)
            @builder.ret(converted)
          end
        else
          # No value but not void - return zero
          case return_type_sym
          when :Int64
            @builder.ret(LLVM::Int64.from_i(0))
          when :Float64
            @builder.ret(LLVM::Double.from_f(0.0))
          else
            @builder.ret_void
          end
        end
      end

      def get_value(hir_value)
        case hir_value
        when HIR::LoadLocal
          # For LoadLocal: if it has a result_var, use that (instruction was generated)
          # If no result_var (inliner-created reference), use var.name
          if hir_value.result_var
            @variables[hir_value.result_var] || @qnil
          else
            # Inliner-created LoadLocal with no result_var - look up by var.name
            @variables[hir_value.var.name] || @qnil
          end
        when HIR::Instruction
          # Already generated, get from variables
          if hir_value.result_var
            @variables[hir_value.result_var] || @qnil
          else
            @qnil
          end
        when String
          # Variable name
          @variables[hir_value] || @qnil
        else
          @qnil
        end
      end

      # Get value as a Ruby VALUE (i64), boxing native types if needed
      # This should be used when the value will be passed to CRuby functions
      def get_value_as_ruby(hir_value)
        value, type_tag = get_value_with_type(hir_value)
        convert_value(value, type_tag, :value)
      end

      # Ensure an LLVM value is a Ruby VALUE, boxing if needed
      # Used for inline loop results where type may be unboxed
      def ensure_ruby_value(llvm_val)
        return @qnil unless llvm_val
        return llvm_val unless llvm_val.is_a?(LLVM::Value)

        case llvm_val.type
        when LLVM::Double
          @builder.call(@rb_float_new, llvm_val)
        when LLVM::Int64
          # Could be VALUE or unboxed i64 - assume VALUE for now
          # Proper tracking would require type metadata
          llvm_val
        else
          llvm_val
        end
      end

      # ========================================
      # NativeArray LLVM IR Generation
      # ========================================

      # Detect if a receiver is a NativeArray
      # Returns the NativeArrayType if it is, nil otherwise
      def detect_native_array_type(receiver, hir_type)
        # First check HIR type
        return hir_type if hir_type.is_a?(TypeChecker::Types::NativeArrayType)

        # Check if the receiver variable is tracked as a NativeArray
        var_name = get_receiver_var_name(receiver)
        if var_name && @variable_types[var_name] == :native_array
          # Get the element type from the original allocation if available
          # Default to Float64 for simplicity
          return TypeChecker::Types::NativeArrayType.new(:Float64)
        end

        nil
      end

      # Handle NativeArray method calls ([], []=, length, Enumerable methods)
      # Returns nil if not a NativeArray operation (fall through to normal call)
      def generate_native_array_call(inst, array_type)
        element_type = array_type.element_type
        method_name = inst.method_name

        case method_name
        when "[]"
          # arr[i] - get element
          return nil unless inst.args.size == 1
          generate_native_array_get_call(inst, element_type)
        when "[]="
          # arr[i] = value - set element
          return nil unless inst.args.size == 2
          generate_native_array_set_call(inst, element_type)
        when "length", "size"
          # arr.length - get length
          generate_native_array_length_call(inst)
        # Enumerable methods
        when "each"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_each(inst, element_type)
        when "reduce", "inject"
          return nil unless inst.block && inst.block.params.size == 2
          generate_native_array_reduce(inst, element_type)
        when "map", "collect"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_map(inst, element_type)
        when "select", "filter"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_select(inst, element_type, false)
        when "reject"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_select(inst, element_type, true)
        when "find", "detect"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_find(inst, element_type)
        when "any?"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_predicate(inst, element_type, :any)
        when "all?"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_predicate(inst, element_type, :all)
        when "none?"
          return nil unless inst.block && inst.block.params.size == 1
          generate_native_array_predicate(inst, element_type, :none)
        when "sum"
          generate_native_array_sum(inst, element_type)
        when "min"
          generate_native_array_minmax(inst, element_type, :min)
        when "max"
          generate_native_array_minmax(inst, element_type, :max)
        else
          # Not a NativeArray operation we can optimize
          nil
        end
      end

      # Generate NativeArray element access: arr[i]
      def generate_native_array_get_call(inst, element_type)
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer from receiver
        array_ptr = get_native_array_ptr(inst.receiver)

        # Get index value
        index_value, index_type = get_value_with_type(inst.args.first)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Normalize negative indices
        index_i64 = normalize_native_index(index_i64, inst.receiver)

        # GEP to get element pointer
        elem_ptr = @builder.gep(array_ptr, [index_i64], "elem_ptr")

        # Load element
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        if inst.result_var
          @variables[inst.result_var] = elem_value
          @variable_types[inst.result_var] = type_tag
        end

        elem_value
      end

      # Generate NativeArray element assignment: arr[i] = value
      def generate_native_array_set_call(inst, element_type)
        # Get array pointer from receiver
        array_ptr = get_native_array_ptr(inst.receiver)

        # Get index value
        index_value, index_type = get_value_with_type(inst.args[0])
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Normalize negative indices
        index_i64 = normalize_native_index(index_i64, inst.receiver)

        # Get value to store
        store_value, value_type = get_value_with_type(inst.args[1])
        target_type = element_type == :Int64 ? :i64 : :double
        converted_value = convert_value(store_value, value_type, target_type)

        # GEP to get element pointer
        elem_ptr = @builder.gep(array_ptr, [index_i64], "elem_ptr")

        # Store element
        @builder.store(converted_value, elem_ptr)

        # Return the stored value (like Ruby assignment)
        if inst.result_var
          @variables[inst.result_var] = converted_value
          @variable_types[inst.result_var] = target_type
        end

        converted_value
      end

      # Normalize negative index to positive (index + length if negative)
      def normalize_native_index(index_i64, receiver)
        receiver_var = get_receiver_var_name(receiver)
        len_value = @variables["#{receiver_var}_len"]
        return index_i64 unless len_value

        func = @builder.insert_block.parent
        is_negative = @builder.icmp(:slt, index_i64, LLVM::Int64.from_i(0))

        neg_bb = func.basic_blocks.append("idx_neg")
        pos_bb = func.basic_blocks.append("idx_pos")
        merge_bb = func.basic_blocks.append("idx_merge")

        @builder.cond(is_negative, neg_bb, pos_bb)

        @builder.position_at_end(neg_bb)
        normalized = @builder.add(len_value, index_i64, "neg_idx")
        @builder.br(merge_bb)

        @builder.position_at_end(pos_bb)
        @builder.br(merge_bb)

        @builder.position_at_end(merge_bb)
        @builder.phi(LLVM::Int64, { neg_bb => normalized, pos_bb => index_i64 })
      end

      # Normalize negative index for StaticArray (compile-time known size)
      def normalize_static_index(index_i64, size)
        func = @builder.insert_block.parent
        is_negative = @builder.icmp(:slt, index_i64, LLVM::Int64.from_i(0))

        neg_bb = func.basic_blocks.append("sidx_neg")
        pos_bb = func.basic_blocks.append("sidx_pos")
        merge_bb = func.basic_blocks.append("sidx_merge")

        @builder.cond(is_negative, neg_bb, pos_bb)

        @builder.position_at_end(neg_bb)
        normalized = @builder.add(LLVM::Int64.from_i(size), index_i64, "neg_sidx")
        @builder.br(merge_bb)

        @builder.position_at_end(pos_bb)
        @builder.br(merge_bb)

        @builder.position_at_end(merge_bb)
        @builder.phi(LLVM::Int64, { neg_bb => normalized, pos_bb => index_i64 })
      end

      # Generate NativeArray length access: arr.length
      def generate_native_array_length_call(inst)
        # Get the array's stored length
        receiver_var = get_receiver_var_name(inst.receiver)
        len_value = @variables["#{receiver_var}_len"]

        # If no length stored, fall back to qnil (shouldn't happen in valid code)
        len_value ||= LLVM::Int64.from_i(0)

        if inst.result_var
          @variables[inst.result_var] = len_value
          @variable_types[inst.result_var] = :i64
        end

        len_value
      end

      # ========================================
      # NativeArray Enumerable Methods
      # ========================================

      # Generate NativeArray each: arr.each { |x| ... }
      def generate_native_array_each(inst, element_type)
        block = inst.block
        elem_param = block.params[0].name
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer and length (both already native!)
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Allocate index
        idx_alloca = @builder.alloca(LLVM::Int64, "na_each_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("na_each_cond")
        loop_body = func.basic_blocks.append("na_each_body")
        loop_end = func.basic_blocks.append("na_each_end")

        @builder.br(loop_cond)

        # Loop condition: idx < len
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Get element via GEP + load (no rb_ary_entry!)
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        # Set up block parameter (unboxed!)
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup
        @variables[elem_param] = elem_value
        @variable_types[elem_param] = type_tag
        @variable_allocas.delete(elem_param)

        # Generate block body
        block.body.each do |basic_block|
          basic_block.instructions.each { |i| generate_instruction(i) }
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Increment index and loop
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: return self (the array as VALUE - need to wrap)
        @builder.position_at_end(loop_end)
        @qnil  # NativeArray doesn't have a VALUE representation, return nil
      end

      # Generate NativeArray reduce: arr.reduce(init) { |acc, x| ... }
      def generate_native_array_reduce(inst, element_type)
        block = inst.block
        acc_param = block.params[0].name
        elem_param = block.params[1].name
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer and length
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Get initial value and convert to unboxed
        initial_value = if inst.args.any?
          val, val_type = get_value_with_type(inst.args.first)
          convert_value(val, val_type, type_tag)
        else
          # Use first element as initial, start from index 1
          elem_ptr = @builder.gep(array_ptr, [LLVM::Int64.from_i(0)], "first_ptr")
          @builder.load2(llvm_elem_type, elem_ptr, "first_elem")
        end

        # Allocate accumulator (unboxed)
        acc_alloca = @builder.alloca(llvm_elem_type, "na_reduce_acc")
        @builder.store(initial_value, acc_alloca)

        # Allocate index
        start_idx = inst.args.any? ? 0 : 1
        idx_alloca = @builder.alloca(LLVM::Int64, "na_reduce_idx")
        @builder.store(LLVM::Int64.from_i(start_idx), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("na_reduce_cond")
        loop_body = func.basic_blocks.append("na_reduce_body")
        loop_end = func.basic_blocks.append("na_reduce_end")

        @builder.br(loop_cond)

        # Loop condition
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Load accumulator and element (both unboxed)
        acc_value = @builder.load2(llvm_elem_type, acc_alloca, "acc")
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        # Set up block parameters
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup
        @variables[acc_param] = acc_value
        @variables[elem_param] = elem_value
        @variable_types[acc_param] = type_tag
        @variable_types[elem_param] = type_tag
        @variable_allocas.delete(acc_param)
        @variable_allocas.delete(elem_param)

        # Generate block body
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each { |i| body_result = generate_instruction(i) }
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Store result back to accumulator (keeping unboxed)
        new_acc = body_result || (element_type == :Int64 ? LLVM::Int64.from_i(0) : LLVM::Double.from_f(0.0))
        if new_acc.type == llvm_elem_type
          @builder.store(new_acc, acc_alloca)
        elsif new_acc.type == value_type
          # Need to unbox
          unboxed = element_type == :Int64 ? @builder.call(@rb_num2long, new_acc) : @builder.call(@rb_num2dbl, new_acc)
          @builder.store(unboxed, acc_alloca)
        else
          @builder.store(new_acc, acc_alloca)
        end

        # Increment index
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: box final result
        @builder.position_at_end(loop_end)
        final = @builder.load2(llvm_elem_type, acc_alloca, "reduce_result")
        boxed = if element_type == :Int64
          @builder.call(@rb_int2inum, final)
        else
          @builder.call(@rb_float_new, final)
        end

        if inst.result_var
          @variables[inst.result_var] = boxed
          @variable_types[inst.result_var] = :value
        end

        boxed
      end

      # Generate NativeArray map: arr.map { |x| ... }
      def generate_native_array_map(inst, element_type)
        block = inst.block
        elem_param = block.params[0].name
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer and length
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Create result Ruby array and store on stack via alloca to protect from GC.
        # rb_float_new/rb_int2inum in the loop can trigger GC; without an alloca,
        # result_array would only live in an LLVM register that GC may not scan.
        result_alloca = @builder.alloca(value_type, "na_map_result")
        result_array = @builder.call(@rb_ary_new)
        @builder.store(result_array, result_alloca)

        # Allocate index
        idx_alloca = @builder.alloca(LLVM::Int64, "na_map_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("na_map_cond")
        loop_body = func.basic_blocks.append("na_map_body")
        loop_end = func.basic_blocks.append("na_map_end")

        @builder.br(loop_cond)

        # Loop condition
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Load element (unboxed)
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        # Set up block parameter
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup
        @variables[elem_param] = elem_value
        @variable_types[elem_param] = type_tag
        @variable_allocas.delete(elem_param)

        # Generate block body
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each { |i| body_result = generate_instruction(i) }
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Box result and push to array (reload result_array from alloca for GC safety)
        boxed_result = box_value_if_needed(body_result)
        result_val = @builder.load2(value_type, result_alloca, "result_arr")
        @builder.call(@rb_ary_push, result_val, boxed_result)

        # Increment index
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end
        @builder.position_at_end(loop_end)
        final_result = @builder.load2(value_type, result_alloca, "result_arr_final")

        if inst.result_var
          @variables[inst.result_var] = final_result
          @variable_types[inst.result_var] = :value
        end

        final_result
      end

      # Generate NativeArray select/reject: arr.select { |x| ... }
      def generate_native_array_select(inst, element_type, reject_mode)
        block = inst.block
        elem_param = block.params[0].name
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer and length
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Create result Ruby array
        result_array = @builder.call(@rb_ary_new)

        # Allocate index
        idx_alloca = @builder.alloca(LLVM::Int64, "na_select_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("na_select_cond")
        loop_body = func.basic_blocks.append("na_select_body")
        push_block = func.basic_blocks.append("na_select_push")
        loop_continue = func.basic_blocks.append("na_select_continue")
        loop_end = func.basic_blocks.append("na_select_end")

        @builder.br(loop_cond)

        # Loop condition
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Load element (unboxed)
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        # Set up block parameter
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup
        @variables[elem_param] = elem_value
        @variable_types[elem_param] = type_tag
        @variable_allocas.delete(elem_param)

        # Generate block body
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each { |i| body_result = generate_instruction(i) }
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Check if result is truthy
        is_truthy = generate_truthy_check(body_result)
        if reject_mode
          # reject: push if NOT truthy
          @builder.cond(is_truthy, loop_continue, push_block)
        else
          # select: push if truthy
          @builder.cond(is_truthy, push_block, loop_continue)
        end

        # Push block: box element and push to result
        @builder.position_at_end(push_block)
        boxed_elem = if element_type == :Int64
          @builder.call(@rb_int2inum, elem_value)
        else
          @builder.call(@rb_float_new, elem_value)
        end
        @builder.call(@rb_ary_push, result_array, boxed_elem)
        @builder.br(loop_continue)

        # Continue: increment index
        @builder.position_at_end(loop_continue)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end
        @builder.position_at_end(loop_end)

        if inst.result_var
          @variables[inst.result_var] = result_array
          @variable_types[inst.result_var] = :value
        end

        result_array
      end

      # Generate NativeArray find: arr.find { |x| ... }
      def generate_native_array_find(inst, element_type)
        block = inst.block
        elem_param = block.params[0].name
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer and length
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Allocate index, element storage, and result
        idx_alloca = @builder.alloca(LLVM::Int64, "na_find_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)
        elem_alloca = @builder.alloca(llvm_elem_type, "na_find_elem")
        result_alloca = @builder.alloca(value_type, "na_find_result")
        @builder.store(@qnil, result_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("na_find_cond")
        loop_body = func.basic_blocks.append("na_find_body")
        found_block = func.basic_blocks.append("na_find_found")
        loop_continue = func.basic_blocks.append("na_find_continue")
        loop_end = func.basic_blocks.append("na_find_end")

        @builder.br(loop_cond)

        # Loop condition
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Load element and store to alloca for later use
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")
        @builder.store(elem_value, elem_alloca)

        # Set up block parameter
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup
        @variables[elem_param] = elem_value
        @variable_types[elem_param] = type_tag
        @variable_allocas.delete(elem_param)

        # Generate block body
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each { |i| body_result = generate_instruction(i) }
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Check if result is truthy
        is_truthy = generate_truthy_check(body_result)
        @builder.cond(is_truthy, found_block, loop_continue)

        # Found: reload element from alloca, box and store, then exit loop
        @builder.position_at_end(found_block)
        found_elem = @builder.load2(llvm_elem_type, elem_alloca, "found_elem")
        boxed_elem = if element_type == :Int64
          @builder.call(@rb_int2inum, found_elem)
        else
          @builder.call(@rb_float_new, found_elem)
        end
        @builder.store(boxed_elem, result_alloca)
        @builder.br(loop_end)

        # Continue: increment index
        @builder.position_at_end(loop_continue)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end
        @builder.position_at_end(loop_end)
        result = @builder.load2(value_type, result_alloca, "find_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate NativeArray any?/all?/none?: arr.any? { |x| ... }
      def generate_native_array_predicate(inst, element_type, predicate_type)
        block = inst.block
        elem_param = block.params[0].name
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer and length
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Allocate index and result
        idx_alloca = @builder.alloca(LLVM::Int64, "na_pred_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("na_pred_cond")
        loop_body = func.basic_blocks.append("na_pred_body")
        early_exit = func.basic_blocks.append("na_pred_early")
        loop_continue = func.basic_blocks.append("na_pred_continue")
        loop_end = func.basic_blocks.append("na_pred_end")

        @builder.br(loop_cond)

        # Loop condition
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Load element
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        # Set up block parameter
        saved_vars = @variables.dup
        saved_types = @variable_types.dup
        saved_allocas = @variable_allocas.dup
        @variables[elem_param] = elem_value
        @variable_types[elem_param] = type_tag
        @variable_allocas.delete(elem_param)

        # Generate block body
        body_result = nil
        block.body.each do |basic_block|
          basic_block.instructions.each { |i| body_result = generate_instruction(i) }
        end

        # Restore variables
        @variables = saved_vars
        @variable_types = saved_types
        @variable_allocas = saved_allocas

        # Check if result is truthy
        is_truthy = generate_truthy_check(body_result)

        # Branch based on predicate type
        case predicate_type
        when :any
          # any?: early exit with true if truthy
          @builder.cond(is_truthy, early_exit, loop_continue)
        when :all
          # all?: early exit with false if NOT truthy
          @builder.cond(is_truthy, loop_continue, early_exit)
        when :none
          # none?: early exit with false if truthy
          @builder.cond(is_truthy, early_exit, loop_continue)
        end

        # Early exit block
        @builder.position_at_end(early_exit)
        early_result = case predicate_type
        when :any then @qtrue
        when :all then @qfalse
        when :none then @qfalse
        end
        @builder.br(loop_end)

        # Continue: increment index
        @builder.position_at_end(loop_continue)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: phi node for result
        @builder.position_at_end(loop_end)
        default_result = case predicate_type
        when :any then @qfalse   # any? returns false if none match
        when :all then @qtrue    # all? returns true if all match
        when :none then @qtrue   # none? returns true if none match
        end
        result = @builder.phi(value_type, { early_exit => early_result, loop_cond => default_result }, "pred_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Generate NativeArray sum: arr.sum
      def generate_native_array_sum(inst, element_type)
        llvm_elem_type = native_array_element_llvm_type(element_type)
        type_tag = element_type == :Int64 ? :i64 : :double

        # Get array pointer and length
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Allocate accumulator (unboxed)
        initial = element_type == :Int64 ? LLVM::Int64.from_i(0) : LLVM::Double.from_f(0.0)
        acc_alloca = @builder.alloca(llvm_elem_type, "na_sum_acc")
        @builder.store(initial, acc_alloca)

        # Allocate index
        idx_alloca = @builder.alloca(LLVM::Int64, "na_sum_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)

        # Create loop blocks
        func = @builder.insert_block.parent
        loop_cond = func.basic_blocks.append("na_sum_cond")
        loop_body = func.basic_blocks.append("na_sum_body")
        loop_end = func.basic_blocks.append("na_sum_end")

        @builder.br(loop_cond)

        # Loop condition
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Load accumulator and element
        acc_value = @builder.load2(llvm_elem_type, acc_alloca, "acc")
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        # Add (unboxed)
        new_acc = if element_type == :Int64
          @builder.add(acc_value, elem_value, "sum")
        else
          @builder.fadd(acc_value, elem_value, "sum")
        end
        @builder.store(new_acc, acc_alloca)

        # Increment index
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: box final result
        @builder.position_at_end(loop_end)
        final = @builder.load2(llvm_elem_type, acc_alloca, "sum_result")
        boxed = if element_type == :Int64
          @builder.call(@rb_int2inum, final)
        else
          @builder.call(@rb_float_new, final)
        end

        if inst.result_var
          @variables[inst.result_var] = boxed
          @variable_types[inst.result_var] = :value
        end

        boxed
      end

      # Generate NativeArray min/max: arr.min, arr.max
      def generate_native_array_minmax(inst, element_type, minmax_type)
        llvm_elem_type = native_array_element_llvm_type(element_type)

        # Get array pointer and length
        array_ptr = get_native_array_ptr(inst.receiver)
        receiver_var = get_receiver_var_name(inst.receiver)
        arr_len = @variables["#{receiver_var}_len"]

        # Allocate VALUE result (will hold nil or boxed value)
        final_result_alloca = @builder.alloca(value_type, "na_minmax_final")
        @builder.store(@qnil, final_result_alloca)

        # Create blocks
        func = @builder.insert_block.parent
        non_empty_block = func.basic_blocks.append("na_minmax_non_empty")
        loop_cond = func.basic_blocks.append("na_minmax_cond")
        loop_body = func.basic_blocks.append("na_minmax_body")
        loop_end = func.basic_blocks.append("na_minmax_end")
        final_block = func.basic_blocks.append("na_minmax_final")

        # Check if array is empty
        is_empty = @builder.icmp(:eq, arr_len, LLVM::Int64.from_i(0))
        @builder.cond(is_empty, final_block, non_empty_block)

        # Non-empty: initialize with first element
        @builder.position_at_end(non_empty_block)
        result_alloca = @builder.alloca(llvm_elem_type, "na_minmax_result")
        first_ptr = @builder.gep(array_ptr, [LLVM::Int64.from_i(0)], "first_ptr")
        first_elem = @builder.load2(llvm_elem_type, first_ptr, "first")
        @builder.store(first_elem, result_alloca)

        # Allocate index (start from 1)
        idx_alloca = @builder.alloca(LLVM::Int64, "na_minmax_idx")
        @builder.store(LLVM::Int64.from_i(1), idx_alloca)
        @builder.br(loop_cond)

        # Loop condition
        @builder.position_at_end(loop_cond)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:slt, current_idx, arr_len)
        @builder.cond(cond, loop_body, loop_end)

        # Loop body
        @builder.position_at_end(loop_body)

        # Load current result and element
        current_result = @builder.load2(llvm_elem_type, result_alloca, "current")
        elem_ptr = @builder.gep(array_ptr, [current_idx], "elem_ptr")
        elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

        # Compare and select
        comparison = if element_type == :Int64
          if minmax_type == :min
            @builder.icmp(:slt, elem_value, current_result)
          else
            @builder.icmp(:sgt, elem_value, current_result)
          end
        else
          if minmax_type == :min
            @builder.fcmp(:olt, elem_value, current_result)
          else
            @builder.fcmp(:ogt, elem_value, current_result)
          end
        end

        new_result = @builder.select(comparison, elem_value, current_result, "selected")
        @builder.store(new_result, result_alloca)

        # Increment index
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1))
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_cond)

        # Loop end: box final result
        @builder.position_at_end(loop_end)
        final = @builder.load2(llvm_elem_type, result_alloca, "minmax_result")
        boxed = if element_type == :Int64
          @builder.call(@rb_int2inum, final)
        else
          @builder.call(@rb_float_new, final)
        end
        @builder.store(boxed, final_result_alloca)
        @builder.br(final_block)

        # Final block: load and return result
        @builder.position_at_end(final_block)
        result = @builder.load2(value_type, final_result_alloca, "final_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Helper: box value if needed
      def box_value_if_needed(val)
        return val if val.nil?
        return val if val.type == value_type

        if val.type == LLVM::Int64
          @builder.call(@rb_int2inum, val)
        elsif val.type == LLVM::Double
          @builder.call(@rb_float_new, val)
        elsif val.type == LLVM::Int1
          # Boolean
          @builder.select(val, @qtrue, @qfalse)
        else
          val
        end
      end


      # Get the array pointer from a receiver HIR value
      def get_native_array_ptr(receiver)
        case receiver
        when HIR::Instruction
          if receiver.result_var
            @variables[receiver.result_var]
          else
            raise "NativeArray receiver has no result_var"
          end
        when String
          @variables[receiver]
        else
          raise "Unknown NativeArray receiver type: #{receiver.class}"
        end
      end

      # Get the variable name from a receiver for length lookup
      def get_receiver_var_name(receiver)
        case receiver
        when HIR::Instruction
          receiver.result_var
        when String
          receiver
        else
          nil
        end
      end

      # Allocate a NativeArray on the stack
      # Returns a pointer to contiguous memory + stores length
      def generate_native_array_alloc(inst)
        element_type = inst.element_type
        llvm_elem_type = native_array_element_llvm_type(element_type)

        # Get size value (should be i64)
        size_value, size_type = get_value_with_type(inst.size)
        size_i64 = size_type == :i64 ? size_value : @builder.call(@rb_num2long, size_value)

        # Allocate array on stack: alloca [size x element_type]
        # For variable-size arrays, we use alloca with dynamic size
        array_ptr = @builder.array_alloca(llvm_elem_type, size_i64, "native_arr")

        # Zero-initialize the array
        # This is important for NativeClass elements to ensure all fields start as 0
        elem_size = calculate_llvm_type_size(llvm_elem_type)
        total_size = @builder.mul(size_i64, LLVM::Int64.from_i(elem_size), "total_size")
        array_ptr_i8 = @builder.bit_cast(array_ptr, LLVM::Pointer(LLVM::Int8), "arr_i8")
        @builder.call(@memset, array_ptr_i8, LLVM::Int32.from_i(0), total_size)

        # Store the result (pointer + length info)
        if inst.result_var
          @variables[inst.result_var] = array_ptr
          @variable_types[inst.result_var] = :native_array
          @variables["#{inst.result_var}_len"] = size_i64

          # For NativeClass arrays, also store the element class type
          if native_array_has_class_element?(element_type)
            @native_array_class_types ||= {}
            @native_array_class_types[inst.result_var] = element_type
          end
        end

        array_ptr
      end

      # Get element from NativeArray (unboxed access)
      def generate_native_array_get(inst)
        element_type = inst.element_type
        llvm_elem_type = native_array_element_llvm_type(element_type)

        # Get array pointer
        array_ptr = get_value(inst.array)

        # Get index value (convert to i64 if needed)
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # GEP to get element pointer
        elem_ptr = @builder.gep(array_ptr, [index_i64], "elem_ptr")

        if native_array_has_class_element?(element_type)
          # For NativeClass elements, return pointer to struct (for field access)
          if inst.result_var
            @variables[inst.result_var] = elem_ptr
            @variable_types[inst.result_var] = :native_class
            @native_class_types ||= {}
            @native_class_types[inst.result_var] = element_type
          end
          elem_ptr
        else
          # For primitive elements, load the value
          type_tag = element_type == :Int64 ? :i64 : :double
          elem_value = @builder.load2(llvm_elem_type, elem_ptr, "elem")

          if inst.result_var
            @variables[inst.result_var] = elem_value
            @variable_types[inst.result_var] = type_tag
          end

          elem_value
        end
      end

      # Set element in NativeArray
      def generate_native_array_set(inst)
        element_type = inst.element_type

        # Get array pointer
        array_ptr = get_value(inst.array)

        # Get index value
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Get value to store (convert to correct type if needed)
        store_value, value_type = get_value_with_type(inst.value)
        target_type = element_type == :Int64 ? :i64 : :double
        converted_value = convert_value(store_value, value_type, target_type)

        # GEP to get element pointer
        elem_ptr = @builder.gep(array_ptr, [index_i64], "elem_ptr")

        # Store element
        @builder.store(converted_value, elem_ptr)
      end

      # Get length of NativeArray
      def generate_native_array_length(inst)
        # Length was stored when array was allocated
        array_var = inst.array.result_var
        len_value = @variables["#{array_var}_len"]

        if inst.result_var
          @variables[inst.result_var] = len_value
          @variable_types[inst.result_var] = :i64
        end

        len_value
      end

      # Helper: Get LLVM type for NativeArray element
      def native_array_element_llvm_type(element_type)
        case element_type
        when :Int64 then LLVM::Int64
        when :Float64 then LLVM::Double
        when TypeChecker::Types::NativeClassType
          get_or_create_native_class_struct(element_type)
        else raise "Unknown NativeArray element type: #{element_type}"
        end
      end

      # Check if element type is a NativeClass
      def native_array_has_class_element?(element_type)
        element_type.is_a?(TypeChecker::Types::NativeClassType)
      end

      # Calculate size of an LLVM type in bytes
      def calculate_llvm_type_size(llvm_type)
        case llvm_type
        when LLVM::Int8.type then 1
        when LLVM::Int32.type then 4
        when LLVM::Int64.type then 8
        when LLVM::Float.type then 4
        when LLVM::Double.type then 8
        else
          # For struct types, sum up field sizes (approximation, ignoring padding)
          if llvm_type.kind == :struct
            # Assume 8-byte alignment for simplicity
            llvm_type.element_types.sum { |t| calculate_llvm_type_size(t) }
          else
            8  # Default to 8 bytes (pointer size on 64-bit)
          end
        end
      end

      # ========================================
      # StaticArray code generation
      # Fixed-size stack-allocated arrays
      # ========================================

      # Allocate a StaticArray on stack
      def generate_static_array_alloc(inst)
        elem_type = inst.element_type == :Int64 ? LLVM::Int64 : LLVM::Double
        array_type = LLVM::Array(elem_type, inst.size)

        # Stack allocation (no heap, no GC pressure)
        array_ptr = @builder.alloca(array_type, "static_arr")

        # Initialize with value or zero
        if inst.initial_value
          # Fill with initial value
          fill_value, fill_type = get_value_with_type(inst.initial_value)

          # Convert to appropriate type if needed
          fill_native = if inst.element_type == :Float64
            fill_type == :double ? fill_value : @builder.si_to_fp(fill_value, LLVM::Double, "fill_f")
          else
            fill_type == :i64 ? fill_value : @builder.fp_to_si(fill_value, LLVM::Int64, "fill_i")
          end

          # Store to each element
          inst.size.times do |i|
            idx = LLVM::Int64.from_i(i)
            elem_ptr = @builder.gep2(array_type, array_ptr, [LLVM::Int32.from_i(0), idx], "elem_ptr_#{i}")
            @builder.store(fill_native, elem_ptr)
          end
        else
          # Zero-initialize using memset
          byte_size = LLVM::Int64.from_i(inst.size * 8)
          declare_memset unless @memset
          @builder.call(@memset, array_ptr, LLVM::Int8.from_i(0), byte_size, LLVM::FALSE)
        end

        if inst.result_var
          @variables[inst.result_var] = array_ptr
          @variable_types[inst.result_var] = :static_array
          # Store type metadata
          @static_array_types ||= {}
          @static_array_types[inst.result_var] = {
            element_type: inst.element_type,
            size: inst.size
          }
        end

        array_ptr
      end

      # Get element from StaticArray (unboxed)
      def generate_static_array_get(inst)
        elem_type = inst.element_type == :Int64 ? LLVM::Int64 : LLVM::Double
        array_type = LLVM::Array(elem_type, inst.size)
        array_ptr = get_value(inst.array)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Normalize negative indices
        index_i64 = normalize_static_index(index_i64, inst.size)

        # GEP to element
        elem_ptr = @builder.gep2(array_type, array_ptr, [LLVM::Int32.from_i(0), index_i64], "elem_ptr")
        value = @builder.load2(elem_type, elem_ptr, "elem")

        type_tag = inst.element_type == :Int64 ? :i64 : :double
        if inst.result_var
          @variables[inst.result_var] = value
          @variable_types[inst.result_var] = type_tag
        end

        value
      end

      # Set element in StaticArray
      def generate_static_array_set(inst)
        elem_type = inst.element_type == :Int64 ? LLVM::Int64 : LLVM::Double
        array_type = LLVM::Array(elem_type, inst.size)
        array_ptr = get_value(inst.array)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Normalize negative indices
        index_i64 = normalize_static_index(index_i64, inst.size)

        # Get value to store
        value, value_type = get_value_with_type(inst.value)

        # Convert to appropriate type if needed
        store_value = if inst.element_type == :Float64
          value_type == :double ? value : @builder.si_to_fp(value, LLVM::Double, "store_f")
        else
          value_type == :i64 ? value : @builder.fp_to_si(value, LLVM::Int64, "store_i")
        end

        # GEP and store
        elem_ptr = @builder.gep2(array_type, array_ptr, [LLVM::Int32.from_i(0), index_i64], "elem_ptr")
        @builder.store(store_value, elem_ptr)

        store_value
      end

      # Get size of StaticArray (compile-time constant)
      def generate_static_array_size(inst)
        # Size is known at compile time
        size_val = LLVM::Int64.from_i(inst.size)

        if inst.result_var
          @variables[inst.result_var] = size_val
          @variable_types[inst.result_var] = :i64
        end

        size_val
      end

      # ========================================
      # ByteBuffer code generation
      # ========================================

      # ByteBuffer struct layout:
      # { i64 capacity, i64 length, ptr data }
      def get_byte_buffer_struct
        @byte_buffer_struct ||= LLVM::Struct(LLVM::Int64, LLVM::Int64, LLVM::Pointer(LLVM::Int8), "ByteBuffer")
      end

      # ByteSlice struct layout (fat pointer):
      # { ptr data, i64 length }
      def get_byte_slice_struct
        @byte_slice_struct ||= LLVM::Struct(LLVM::Pointer(LLVM::Int8), LLVM::Int64, "ByteSlice")
      end

      # Declare memchr if not already declared
      def declare_memchr
        @memchr ||= @mod.functions["memchr"] || @mod.functions.add(
          "memchr",
          [LLVM::Pointer(LLVM::Int8), LLVM::Int32, LLVM::Int64],
          LLVM::Pointer(LLVM::Int8)
        )
      end

      # Declare memmem if not already declared (for sequence search)
      def declare_memmem
        @memmem ||= @mod.functions["memmem"] || @mod.functions.add(
          "memmem",
          [LLVM::Pointer(LLVM::Int8), LLVM::Int64, LLVM::Pointer(LLVM::Int8), LLVM::Int64],
          LLVM::Pointer(LLVM::Int8)
        )
      end

      # Declare malloc if not already declared
      def declare_malloc
        @malloc ||= @mod.functions["malloc"] || @mod.functions.add(
          "malloc",
          [LLVM::Int64],
          LLVM::Pointer(LLVM::Int8)
        )
      end

      # Declare memset if not already declared
      def declare_memset
        @memset ||= @mod.functions["memset"] || @mod.functions.add(
          "memset",
          [LLVM::Pointer(LLVM::Int8), LLVM::Int32, LLVM::Int64],
          LLVM::Pointer(LLVM::Int8)
        )
      end

      # Declare memcpy if not already declared
      def declare_memcpy
        @memcpy ||= @mod.functions["memcpy"] || @mod.functions.add(
          "memcpy",
          [LLVM::Pointer(LLVM::Int8), LLVM::Pointer(LLVM::Int8), LLVM::Int64],
          LLVM::Pointer(LLVM::Int8)
        )
      end

      # Allocate a ByteBuffer
      def generate_byte_buffer_alloc(inst)
        struct_type = get_byte_buffer_struct

        # Declare required external functions
        declare_malloc
        declare_memset

        # Get capacity value
        capacity_value, capacity_type = get_value_with_type(inst.capacity)
        capacity_i64 = capacity_type == :i64 ? capacity_value : @builder.call(@rb_num2long, capacity_value)

        # Allocate the struct on stack
        buffer_ptr = @builder.alloca(struct_type, "bytebuffer")

        # Allocate data array on heap using malloc
        data_ptr = @builder.call(@malloc, capacity_i64, "buffer_data")

        # Zero-initialize the data
        @builder.call(@memset, data_ptr, LLVM::Int32.from_i(0), capacity_i64)

        # Store capacity, length (0), and data pointer
        cap_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "cap_ptr")
        @builder.store(capacity_i64, cap_ptr)

        len_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_ptr")
        @builder.store(LLVM::Int64.from_i(0), len_ptr)

        data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field_ptr")
        @builder.store(data_ptr, data_field_ptr)

        if inst.result_var
          @variables[inst.result_var] = buffer_ptr
          @variable_types[inst.result_var] = :byte_buffer
        end

        buffer_ptr
      end

      # Get byte from ByteBuffer
      def generate_byte_buffer_get(inst)
        struct_type = get_byte_buffer_struct
        buffer_ptr = get_value(inst.buffer)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Load data pointer
        data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        # GEP to byte (use gep2 with i8 element type)
        byte_ptr = @builder.gep2(LLVM::Int8, data_ptr, [index_i64], "byte_ptr")
        byte_val = @builder.load2(LLVM::Int8, byte_ptr, "byte")

        # Zero-extend to i64
        byte_i64 = @builder.zext(byte_val, LLVM::Int64, "byte_i64")

        if inst.result_var
          @variables[inst.result_var] = byte_i64
          @variable_types[inst.result_var] = :i64
        end

        byte_i64
      end

      # Set byte in ByteBuffer
      def generate_byte_buffer_set(inst)
        struct_type = get_byte_buffer_struct
        buffer_ptr = get_value(inst.buffer)

        # Get index and byte value
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        byte_value, byte_type = get_value_with_type(inst.byte)
        byte_i64 = byte_type == :i64 ? byte_value : @builder.call(@rb_num2long, byte_value)

        # Truncate to i8
        byte_i8 = @builder.trunc(byte_i64, LLVM::Int8, "byte_i8")

        # Load data pointer
        data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        # Store byte (use gep2 with i8 element type)
        byte_ptr = @builder.gep2(LLVM::Int8, data_ptr, [index_i64], "byte_ptr")
        @builder.store(byte_i8, byte_ptr)

        byte_i64
      end

      # Get ByteBuffer length
      def generate_byte_buffer_length(inst)
        struct_type = get_byte_buffer_struct
        buffer_ptr = get_value(inst.buffer)

        # Load length
        len_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_ptr")
        len_val = @builder.load2(LLVM::Int64, len_ptr, "len")

        if inst.result_var
          @variables[inst.result_var] = len_val
          @variable_types[inst.result_var] = :i64
        end

        len_val
      end

      # Append to ByteBuffer
      def generate_byte_buffer_append(inst)
        struct_type = get_byte_buffer_struct
        buffer_ptr = get_value(inst.buffer)

        # Declare memcpy for string/buffer append
        declare_memcpy

        case inst.append_type
        when :byte
          # Append single byte
          byte_value, byte_type = get_value_with_type(inst.value)
          byte_i64 = byte_type == :i64 ? byte_value : @builder.call(@rb_num2long, byte_value)
          byte_i8 = @builder.trunc(byte_i64, LLVM::Int8, "byte")

          # Load current length
          len_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_ptr")
          len_val = @builder.load2(LLVM::Int64, len_ptr, "len")

          # Load data pointer
          data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
          data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data")

          # Store byte at current length position (use gep2 with i8 element type)
          byte_ptr = @builder.gep2(LLVM::Int8, data_ptr, [len_val], "append_ptr")
          @builder.store(byte_i8, byte_ptr)

          # Increment length
          new_len = @builder.add(len_val, LLVM::Int64.from_i(1), "new_len")
          @builder.store(new_len, len_ptr)

        when :string
          # Append string
          str_value = get_value(inst.value)

          # rb_string_value_cstr requires a pointer to VALUE, so we need an alloca
          str_alloca = @builder.alloca(LLVM::Int64, "str_value_ptr")
          @builder.store(str_value, str_alloca)
          str_ptr = @builder.call(@rb_string_value_cstr, str_alloca, "str_cstr")

          # rb_str_length returns a Fixnum VALUE, convert to integer
          str_len_val = @builder.call(@rb_str_length, str_value, "str_len_val")
          str_len = @builder.call(@rb_num2long, str_len_val, "str_len")

          # Load current buffer state
          len_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_ptr")
          len_val = @builder.load2(LLVM::Int64, len_ptr, "len")

          data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
          data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data")

          # Copy string to buffer (use gep2 with i8 element type)
          dest_ptr = @builder.gep2(LLVM::Int8, data_ptr, [len_val], "dest_ptr")
          @builder.call(@memcpy, dest_ptr, str_ptr, str_len)

          # Update length
          new_len = @builder.add(len_val, str_len, "new_len")
          @builder.store(new_len, len_ptr)

        when :buffer
          # Append another buffer's contents
          other_ptr = get_value(inst.value)

          # Load other buffer's data and length
          other_len_ptr = @builder.gep2(struct_type, other_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "other_len_ptr")
          other_len = @builder.load2(LLVM::Int64, other_len_ptr, "other_len")

          other_data_field = @builder.gep2(struct_type, other_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "other_data_field")
          other_data = @builder.load2(LLVM::Pointer(LLVM::Int8), other_data_field, "other_data")

          # Load current buffer state
          len_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_ptr")
          len_val = @builder.load2(LLVM::Int64, len_ptr, "len")

          data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
          data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data")

          # Copy bytes (use gep2 with i8 element type)
          dest_ptr = @builder.gep2(LLVM::Int8, data_ptr, [len_val], "dest_ptr")
          @builder.call(@memcpy, dest_ptr, other_data, other_len)

          # Update length
          new_len = @builder.add(len_val, other_len, "new_len")
          @builder.store(new_len, len_ptr)
        end

        if inst.result_var
          @variables[inst.result_var] = buffer_ptr
          @variable_types[inst.result_var] = :byte_buffer
        end

        buffer_ptr
      end

      # Search for byte or sequence in ByteBuffer
      def generate_byte_buffer_index_of(inst)
        struct_type = get_byte_buffer_struct
        buffer_ptr = get_value(inst.buffer)

        # Load buffer data and length
        len_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_ptr")
        len_val = @builder.load2(LLVM::Int64, len_ptr, "len")

        data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data")

        # Handle start offset if provided
        search_start = data_ptr
        search_len = len_val
        if inst.start_offset
          offset_val, offset_type = get_value_with_type(inst.start_offset)
          offset_i64 = offset_type == :i64 ? offset_val : @builder.call(@rb_num2long, offset_val)
          search_start = @builder.gep2(LLVM::Int8, data_ptr, [offset_i64], "search_start")
          search_len = @builder.sub(len_val, offset_i64, "search_len")
        end

        result = case inst.search_type
        when :byte
          # Use memchr
          declare_memchr
          byte_value, byte_type = get_value_with_type(inst.pattern)
          byte_i64 = byte_type == :i64 ? byte_value : @builder.call(@rb_num2long, byte_value)
          byte_i32 = @builder.trunc(byte_i64, LLVM::Int32, "byte_i32")
          @builder.call(@memchr, search_start, byte_i32, search_len, "found_ptr")

        when :sequence
          # Use memmem
          declare_memmem
          str_value = get_value(inst.pattern)

          # rb_string_value_cstr requires a pointer to VALUE
          str_alloca = @builder.alloca(LLVM::Int64, "needle_ptr")
          @builder.store(str_value, str_alloca)
          str_ptr = @builder.call(@rb_string_value_cstr, str_alloca, "needle_cstr")

          # rb_str_length returns a Fixnum VALUE, convert to integer
          str_len_val = @builder.call(@rb_str_length, str_value, "needle_len_val")
          str_len = @builder.call(@rb_num2long, str_len_val, "needle_len")

          @builder.call(@memmem, search_start, search_len, str_ptr, str_len, "found_ptr")
        end

        # Convert pointer to index (or nil if not found)
        # Check if result is null
        is_null = @builder.icmp(:eq, result, LLVM::Pointer(LLVM::Int8).null, "is_null")

        # Calculate index = found_ptr - data_ptr
        result_int = @builder.ptr2int(result, LLVM::Int64, "result_int")
        data_int = @builder.ptr2int(data_ptr, LLVM::Int64, "data_int")
        index = @builder.sub(result_int, data_int, "index")

        # Select nil or boxed index
        boxed_index = @builder.call(@rb_int2inum, index, "boxed_index")
        final_result = @builder.select(is_null, @qnil, boxed_index, "result")

        if inst.result_var
          @variables[inst.result_var] = final_result
          @variable_types[inst.result_var] = :value
        end

        final_result
      end

      # Convert ByteBuffer to String
      def generate_byte_buffer_to_string(inst)
        struct_type = get_byte_buffer_struct
        buffer_ptr = get_value(inst.buffer)

        # Load buffer data and length
        len_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_ptr")
        len_val = @builder.load2(LLVM::Int64, len_ptr, "len")

        data_field_ptr = @builder.gep2(struct_type, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data")

        # Create Ruby string from buffer
        str = @builder.call(@rb_str_new, data_ptr, len_val, "str")

        if inst.result_var
          @variables[inst.result_var] = str
          @variable_types[inst.result_var] = :value
        end

        str
      end

      # Create ByteSlice from ByteBuffer
      def generate_byte_buffer_slice(inst)
        buffer_struct = get_byte_buffer_struct
        slice_struct = get_byte_slice_struct
        buffer_ptr = get_value(inst.buffer)

        # Get start and length
        start_value, start_type = get_value_with_type(inst.start)
        start_i64 = start_type == :i64 ? start_value : @builder.call(@rb_num2long, start_value)

        length_value, length_type = get_value_with_type(inst.length)
        length_i64 = length_type == :i64 ? length_value : @builder.call(@rb_num2long, length_value)

        # Load buffer data pointer
        data_field_ptr = @builder.gep2(buffer_struct, buffer_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data")

        # Calculate slice data pointer (use gep2 with i8 element type)
        slice_data = @builder.gep2(LLVM::Int8, data_ptr, [start_i64], "slice_data")

        # Allocate slice struct on stack
        slice_ptr = @builder.alloca(slice_struct, "byteslice")

        # Store data pointer and length
        slice_data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "slice_data_field")
        @builder.store(slice_data, slice_data_field)

        slice_len_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "slice_len_field")
        @builder.store(length_i64, slice_len_field)

        if inst.result_var
          @variables[inst.result_var] = slice_ptr
          @variable_types[inst.result_var] = :byte_slice
        end

        slice_ptr
      end

      # ========================================
      # ByteSlice code generation
      # ========================================

      # Get byte from ByteSlice
      def generate_byte_slice_get(inst)
        slice_struct = get_byte_slice_struct
        slice_ptr = get_value(inst.slice)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Load data pointer
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field, "data")

        # Get byte (use gep2 with i8 element type)
        byte_ptr = @builder.gep2(LLVM::Int8, data_ptr, [index_i64], "byte_ptr")
        byte_val = @builder.load2(LLVM::Int8, byte_ptr, "byte")
        byte_i64 = @builder.zext(byte_val, LLVM::Int64, "byte_i64")

        if inst.result_var
          @variables[inst.result_var] = byte_i64
          @variable_types[inst.result_var] = :i64
        end

        byte_i64
      end

      # Get ByteSlice length
      def generate_byte_slice_length(inst)
        slice_struct = get_byte_slice_struct
        slice_ptr = get_value(inst.slice)

        # Load length
        len_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_field")
        len_val = @builder.load2(LLVM::Int64, len_field, "len")

        if inst.result_var
          @variables[inst.result_var] = len_val
          @variable_types[inst.result_var] = :i64
        end

        len_val
      end

      # Convert ByteSlice to String
      def generate_byte_slice_to_string(inst)
        slice_struct = get_byte_slice_struct
        slice_ptr = get_value(inst.slice)

        # Load data and length
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field, "data")

        len_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len_field")
        len_val = @builder.load2(LLVM::Int64, len_field, "len")

        # Create Ruby string
        str = @builder.call(@rb_str_new, data_ptr, len_val, "str")

        if inst.result_var
          @variables[inst.result_var] = str
          @variable_types[inst.result_var] = :value
        end

        str
      end

      # ========================================
      # Slice[T] code generation
      # Generic bounds-checked pointer view
      # ========================================

      # Get Slice struct type for given element type
      # Struct: { ptr, size }
      def get_slice_struct(element_type)
        @slice_structs ||= {}
        key = element_type
        @slice_structs[key] ||= begin
          # Element LLVM type
          elem_llvm = element_type == :Int64 ? LLVM::Int64 : LLVM::Double
          LLVM::Struct(LLVM::Pointer(elem_llvm), LLVM::Int64)
        end
      end

      # Get element LLVM type
      def slice_element_llvm_type(element_type)
        element_type == :Int64 ? LLVM::Int64 : LLVM::Double
      end

      # Allocate a new Slice with given size
      def generate_slice_alloc(inst)
        # Declare required external functions
        declare_malloc
        declare_memset

        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        # Get size
        size_value, size_type = get_value_with_type(inst.size)
        size_i64 = size_type == :i64 ? size_value : @builder.call(@rb_num2long, size_value)

        # Calculate byte size (size * 8 for both i64 and double)
        elem_size = LLVM::Int64.from_i(8)
        byte_size = @builder.mul(size_i64, elem_size, "byte_size")

        # Allocate memory
        data_ptr = @builder.call(@malloc, byte_size, "slice_data")

        # Cast to element pointer type
        typed_ptr = @builder.bit_cast(data_ptr, LLVM::Pointer(elem_llvm), "typed_ptr")

        # Zero-initialize the memory
        @builder.call(@memset, data_ptr, LLVM::Int32.from_i(0), byte_size)

        # Allocate slice struct on stack
        slice_ptr = @builder.alloca(slice_struct, "slice")

        # Store data pointer
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        @builder.store(typed_ptr, data_field)

        # Store size
        size_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        @builder.store(size_i64, size_field)

        if inst.result_var
          @variables[inst.result_var] = slice_ptr
          @variable_types[inst.result_var] = element_type == :Int64 ? :slice_int64 : :slice_float64
        end

        slice_ptr
      end

      # Get empty Slice singleton
      def generate_slice_empty(inst)
        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        # Allocate slice struct on stack
        slice_ptr = @builder.alloca(slice_struct, "empty_slice")

        # Store null pointer
        null_ptr = LLVM::Pointer(elem_llvm).null
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        @builder.store(null_ptr, data_field)

        # Store size 0
        size_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        @builder.store(LLVM::Int64.from_i(0), size_field)

        if inst.result_var
          @variables[inst.result_var] = slice_ptr
          @variable_types[inst.result_var] = element_type == :Int64 ? :slice_int64 : :slice_float64
        end

        slice_ptr
      end

      # Get element from Slice (bounds-checked)
      def generate_slice_get(inst)
        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        slice_ptr = get_value(inst.slice)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Load size for bounds check
        size_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        size_val = @builder.load2(LLVM::Int64, size_field, "size")

        # Normalize negative indices
        is_negative = @builder.icmp(:slt, index_i64, LLVM::Int64.from_i(0))
        normalized = @builder.add(size_val, index_i64, "neg_slice_idx")
        index_i64 = @builder.select(is_negative, normalized, index_i64, "slice_idx")

        # Bounds check: index < size (signed comparison since we normalized negatives)
        in_bounds = @builder.icmp(:ult, index_i64, size_val, "in_bounds")

        func = @builder.insert_block.parent
        ok_block = func.basic_blocks.append("slice_get_ok")
        err_block = func.basic_blocks.append("slice_get_err")
        cont_block = func.basic_blocks.append("slice_get_cont")

        @builder.cond(in_bounds, ok_block, err_block)

        # Error block - raise IndexError
        @builder.position_at_end(err_block)
        raise_index_error("Slice index out of bounds")
        @builder.unreachable

        # OK block - load element
        @builder.position_at_end(ok_block)
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(elem_llvm), data_field, "data")
        elem_ptr = @builder.gep2(elem_llvm, data_ptr, [index_i64], "elem_ptr")
        elem_val = @builder.load2(elem_llvm, elem_ptr, "elem")
        @builder.br(cont_block)

        # Continue block
        @builder.position_at_end(cont_block)
        result_phi = @builder.phi(elem_llvm, {ok_block => elem_val}, "result")

        if inst.result_var
          @variables[inst.result_var] = result_phi
          @variable_types[inst.result_var] = element_type == :Int64 ? :i64 : :double
        end

        result_phi
      end

      # Set element in Slice (bounds-checked)
      def generate_slice_set(inst)
        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        slice_ptr = get_value(inst.slice)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Get value
        val_value, val_type = get_value_with_type(inst.value)
        typed_val = if element_type == :Int64
          val_type == :i64 ? val_value : @builder.call(@rb_num2long, val_value)
        else
          val_type == :double ? val_value : @builder.call(@rb_num2dbl, val_value)
        end

        # Load size for bounds check
        size_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        size_val = @builder.load2(LLVM::Int64, size_field, "size")

        # Bounds check
        in_bounds = @builder.icmp(:ult, index_i64, size_val, "in_bounds")

        func = @builder.insert_block.parent
        ok_block = func.basic_blocks.append("slice_set_ok")
        err_block = func.basic_blocks.append("slice_set_err")
        cont_block = func.basic_blocks.append("slice_set_cont")

        @builder.cond(in_bounds, ok_block, err_block)

        # Error block - raise IndexError
        @builder.position_at_end(err_block)
        raise_index_error("Slice index out of bounds")
        @builder.unreachable

        # OK block - store element
        @builder.position_at_end(ok_block)
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(elem_llvm), data_field, "data")
        elem_ptr = @builder.gep2(elem_llvm, data_ptr, [index_i64], "elem_ptr")
        @builder.store(typed_val, elem_ptr)
        @builder.br(cont_block)

        # Continue block
        @builder.position_at_end(cont_block)

        if inst.result_var
          @variables[inst.result_var] = typed_val
          @variable_types[inst.result_var] = element_type == :Int64 ? :i64 : :double
        end

        typed_val
      end

      # Get Slice size
      def generate_slice_size(inst)
        # Determine element type from slice variable type
        slice_ptr = get_value(inst.slice)
        var_type = @variable_types[inst.slice.result_var] if inst.slice.respond_to?(:result_var)
        element_type = case var_type
                       when :slice_int64 then :Int64
                       when :slice_float64 then :Float64
                       else :Int64  # Default
                       end
        slice_struct = get_slice_struct(element_type)

        # Load size
        size_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        size_val = @builder.load2(LLVM::Int64, size_field, "size")

        if inst.result_var
          @variables[inst.result_var] = size_val
          @variable_types[inst.result_var] = :i64
        end

        size_val
      end

      # Create subslice (view, no copy)
      def generate_slice_subslice(inst)
        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        slice_ptr = get_value(inst.slice)

        # Get start and count
        start_value, start_type = get_value_with_type(inst.start)
        start_i64 = start_type == :i64 ? start_value : @builder.call(@rb_num2long, start_value)

        count_value, count_type = get_value_with_type(inst.count)
        count_i64 = count_type == :i64 ? count_value : @builder.call(@rb_num2long, count_value)

        # Load original data pointer
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(elem_llvm), data_field, "data")

        # Calculate new data pointer (data + start)
        new_data_ptr = @builder.gep2(elem_llvm, data_ptr, [start_i64], "subslice_data")

        # Allocate new slice struct on stack
        new_slice_ptr = @builder.alloca(slice_struct, "subslice")

        # Store new data pointer
        new_data_field = @builder.gep2(slice_struct, new_slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "new_data_field")
        @builder.store(new_data_ptr, new_data_field)

        # Store count as size
        new_size_field = @builder.gep2(slice_struct, new_slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "new_size_field")
        @builder.store(count_i64, new_size_field)

        if inst.result_var
          @variables[inst.result_var] = new_slice_ptr
          @variable_types[inst.result_var] = element_type == :Int64 ? :slice_int64 : :slice_float64
        end

        new_slice_ptr
      end

      # Copy elements from another Slice
      def generate_slice_copy_from(inst)
        # Declare required external function
        declare_memcpy

        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        dest_ptr = get_value(inst.dest)
        source_ptr = get_value(inst.source)

        # Load source data and size
        src_data_field = @builder.gep2(slice_struct, source_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "src_data_field")
        src_data = @builder.load2(LLVM::Pointer(elem_llvm), src_data_field, "src_data")
        src_size_field = @builder.gep2(slice_struct, source_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "src_size_field")
        src_size = @builder.load2(LLVM::Int64, src_size_field, "src_size")

        # Load dest data
        dest_data_field = @builder.gep2(slice_struct, dest_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "dest_data_field")
        dest_data = @builder.load2(LLVM::Pointer(elem_llvm), dest_data_field, "dest_data")

        # Calculate byte size
        elem_size = LLVM::Int64.from_i(8)
        byte_size = @builder.mul(src_size, elem_size, "byte_size")

        # memcpy
        dest_i8 = @builder.bit_cast(dest_data, LLVM::Pointer(LLVM::Int8), "dest_i8")
        src_i8 = @builder.bit_cast(src_data, LLVM::Pointer(LLVM::Int8), "src_i8")
        @builder.call(@memcpy, dest_i8, src_i8, byte_size)

        if inst.result_var
          @variables[inst.result_var] = dest_ptr
          @variable_types[inst.result_var] = element_type == :Int64 ? :slice_int64 : :slice_float64
        end

        dest_ptr
      end

      # Fill Slice with a value
      def generate_slice_fill(inst)
        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        slice_ptr = get_value(inst.slice)

        # Get fill value
        fill_value, fill_type = get_value_with_type(inst.value)
        typed_fill = if element_type == :Int64
          fill_type == :i64 ? fill_value : @builder.call(@rb_num2long, fill_value)
        else
          fill_type == :double ? fill_value : @builder.call(@rb_num2dbl, fill_value)
        end

        # Load data and size
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(elem_llvm), data_field, "data")
        size_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        size_val = @builder.load2(LLVM::Int64, size_field, "size")

        func = @builder.insert_block.parent

        # Create loop blocks
        loop_header = func.basic_blocks.append("fill_header")
        loop_body = func.basic_blocks.append("fill_body")
        loop_end = func.basic_blocks.append("fill_end")

        # Initialize index
        index_alloca = @builder.alloca(LLVM::Int64, "fill_idx")
        @builder.store(LLVM::Int64.from_i(0), index_alloca)
        @builder.br(loop_header)

        # Loop header: check index < size
        @builder.position_at_end(loop_header)
        current_idx = @builder.load2(LLVM::Int64, index_alloca, "idx")
        cond = @builder.icmp(:ult, current_idx, size_val, "cond")
        @builder.cond(cond, loop_body, loop_end)

        # Loop body: store value, increment index
        @builder.position_at_end(loop_body)
        elem_ptr = @builder.gep2(elem_llvm, data_ptr, [current_idx], "elem_ptr")
        @builder.store(typed_fill, elem_ptr)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1), "next_idx")
        @builder.store(next_idx, index_alloca)
        @builder.br(loop_header)

        # Loop end
        @builder.position_at_end(loop_end)

        if inst.result_var
          @variables[inst.result_var] = slice_ptr
          @variable_types[inst.result_var] = element_type == :Int64 ? :slice_int64 : :slice_float64
        end

        slice_ptr
      end

      # Convert NativeArray or StaticArray to Slice
      def generate_to_slice(inst)
        element_type = inst.element_type
        slice_struct = get_slice_struct(element_type)
        elem_llvm = slice_element_llvm_type(element_type)

        source = get_value(inst.source)

        data_ptr = nil
        size_val = nil

        case inst.source_kind
        when :native_array
          # NativeArray is a pointer to contiguous memory
          # Load size from first element (stored separately or computed)
          # For NativeArray, we need the length - use rb_funcallv with "length"
          len_result = @builder.call(@rb_funcallv, source, intern_symbol("length"), LLVM::Int32.from_i(0), LLVM::Pointer(LLVM::Int64).null, "len")
          size_val = @builder.call(@rb_num2long, len_result, "size")

          # Get data pointer from NativeArray
          # NativeArray stores data as VALUE* internally, need to get native pointer
          # Since NativeArray elements are unboxed, the array itself is the data
          data_ptr = @builder.bit_cast(source, LLVM::Pointer(elem_llvm), "data")

        when :static_array
          # StaticArray is stack-allocated [N x T]
          # The source is already a pointer to the first element
          data_ptr = @builder.bit_cast(source, LLVM::Pointer(elem_llvm), "data")

          # Size is compile-time known - need to get from type
          # For now, use rb_funcallv to call "size" method
          size_result = @builder.call(@rb_funcallv, source, intern_symbol("size"), LLVM::Int32.from_i(0), LLVM::Pointer(LLVM::Int64).null, "size_result")
          size_val = @builder.call(@rb_num2long, size_result, "size")
        end

        # Allocate slice struct on stack
        slice_ptr = @builder.alloca(slice_struct, "slice_from_array")

        # Store data pointer
        data_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        @builder.store(data_ptr, data_field)

        # Store size
        size_field = @builder.gep2(slice_struct, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        @builder.store(size_val, size_field)

        if inst.result_var
          @variables[inst.result_var] = slice_ptr
          @variable_types[inst.result_var] = element_type == :Int64 ? :slice_int64 : :slice_float64
        end

        slice_ptr
      end

      # Helper to raise IndexError
      def raise_index_error(message)
        # Get or declare rb_eIndexError
        @rb_e_index_error ||= @mod.globals["rb_eIndexError"] || begin
          g = @mod.globals.add(LLVM::Int64, "rb_eIndexError")
          g.linkage = :external
          g
        end

        # Create error message
        msg_str = @builder.global_string_pointer(message)

        # Call rb_raise(rb_eIndexError, message)
        @rb_raise_func ||= @mod.functions["rb_raise"] || begin
          param_types = [LLVM::Int64, LLVM::Pointer(LLVM::Int8)]
          ret_type = LLVM::Type.void
          @mod.functions.add("rb_raise", param_types, ret_type)
        end

        exc = @builder.load2(LLVM::Int64, @rb_e_index_error, "exc")
        @builder.call(@rb_raise_func, exc, msg_str)
      end

      # ========================================
      # StringBuffer code generation
      # ========================================

      # Allocate a StringBuffer (uses rb_str_buf_new internally)
      def generate_string_buffer_alloc(inst)
        capacity = if inst.capacity
          cap_value, cap_type = get_value_with_type(inst.capacity)
          cap_type == :i64 ? cap_value : @builder.call(@rb_num2long, cap_value)
        else
          LLVM::Int64.from_i(256)  # Default capacity
        end

        # Create string buffer using rb_str_buf_new
        str_buf = @builder.call(@rb_str_buf_new, capacity, "strbuf")

        if inst.result_var
          @variables[inst.result_var] = str_buf
          @variable_types[inst.result_var] = :string_buffer
        end

        str_buf
      end

      # Append to StringBuffer
      def generate_string_buffer_append(inst)
        buffer = get_value(inst.buffer)
        value = get_value(inst.value)

        # Use rb_str_buf_append (already declared in declare_cruby_functions)
        @builder.call(@rb_str_buf_append, buffer, value)

        if inst.result_var
          @variables[inst.result_var] = buffer
          @variable_types[inst.result_var] = :string_buffer
        end

        buffer
      end

      # Get StringBuffer length
      def generate_string_buffer_length(inst)
        buffer = get_value(inst.buffer)

        # rb_str_length returns a Ruby Fixnum VALUE, convert to i64
        len_val = @builder.call(@rb_str_length, buffer, "len_val")
        len = @builder.call(@rb_num2long, len_val, "len")

        if inst.result_var
          @variables[inst.result_var] = len
          @variable_types[inst.result_var] = :i64
        end

        len
      end

      # Convert StringBuffer to String (just returns the internal string)
      def generate_string_buffer_to_string(inst)
        buffer = get_value(inst.buffer)

        # StringBuffer is already a Ruby String VALUE, just return it
        if inst.result_var
          @variables[inst.result_var] = buffer
          @variable_types[inst.result_var] = :value
        end

        buffer
      end

      # ========================================
      # NativeString code generation
      # UTF-8 native string with byte and character level operations
      # ========================================

      # NativeString struct layout:
      # { ptr data, i64 byte_len, i64 char_len, i64 flags }
      # flags: bit 0 = ASCII_ONLY
      def get_native_string_struct
        @native_string_struct ||= LLVM::Struct(
          LLVM::Pointer(LLVM::Int8),  # data pointer
          LLVM::Int64,                 # byte length
          LLVM::Int64,                 # char length (-1 if not computed)
          LLVM::Int64,                 # flags (bit 0 = ASCII_ONLY)
          "NativeString"
        )
      end

      # Declare memcmp if not already declared
      def declare_memcmp
        @memcmp ||= @mod.functions["memcmp"] || @mod.functions.add(
          "memcmp",
          [LLVM::Pointer(LLVM::Int8), LLVM::Pointer(LLVM::Int8), LLVM::Int64],
          LLVM::Int32
        )
      end

      # Create NativeString from Ruby String
      def generate_native_string_from_ruby(inst)
        struct_type = get_native_string_struct
        string_value = get_value(inst.string)

        # Declare rb_string_value_cstr if not already declared
        unless @rb_string_value_cstr
          @rb_string_value_cstr = @mod.functions["rb_string_value_cstr"] || @mod.functions.add(
            "rb_string_value_cstr",
            [LLVM::Pointer(LLVM::Int64)],  # volatile VALUE*
            LLVM::Pointer(LLVM::Int8)
          )
        end

        # Allocate stack space for the VALUE (rb_string_value_cstr expects a pointer)
        value_ptr = @builder.alloca(LLVM::Int64, "str_ptr")
        @builder.store(string_value, value_ptr)

        # Get C string pointer
        data_ptr = @builder.call(@rb_string_value_cstr, value_ptr, "data_ptr")

        # Get byte length using rb_str_length (returns Fixnum)
        len_value = @builder.call(@rb_str_length, string_value, "str_len")
        byte_len = @builder.call(@rb_num2long, len_value, "byte_len")

        # Check ASCII-only using Ruby's ascii_only? method
        ascii_only_id = @builder.call(@rb_intern, @builder.global_string_pointer("ascii_only?"))
        ascii_result = @builder.call(@rb_funcallv, string_value, ascii_only_id,
          LLVM::Int32.from_i(0), LLVM::Pointer(LLVM::Int64).null_pointer, "ascii_result")

        # Convert Ruby boolean to flags (Qtrue = 20, Qfalse = 0)
        # flags bit 0 = ASCII_ONLY
        is_ascii_true = @builder.icmp(:eq, ascii_result, @qtrue, "is_ascii_true")
        flags_val = @builder.select(is_ascii_true, LLVM::Int64.from_i(1), LLVM::Int64.from_i(0), "flags_val")

        # For ASCII strings, char_len = byte_len; otherwise -1 (not computed)
        char_len = @builder.select(is_ascii_true, byte_len, LLVM::Int64.from_i(-1), "char_len")

        # Allocate struct on stack
        ns_ptr = @builder.alloca(struct_type, "native_string")

        # Store fields
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        @builder.store(data_ptr, data_field_ptr)

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_field")
        @builder.store(byte_len, byte_len_ptr)

        char_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "char_len_field")
        @builder.store(char_len, char_len_ptr)

        flags_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "flags_field")
        @builder.store(flags_val, flags_field_ptr)

        if inst.result_var
          @variables[inst.result_var] = ns_ptr
          @variable_types[inst.result_var] = :native_string
        end

        ns_ptr
      end

      # Get byte at index (O(1))
      def generate_native_string_byte_at(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        index_i64 = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Load data pointer
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        # GEP to byte
        byte_ptr = @builder.gep2(LLVM::Int8, data_ptr, [index_i64], "byte_ptr")
        byte_val = @builder.load2(LLVM::Int8, byte_ptr, "byte")

        # Zero-extend to i64
        byte_i64 = @builder.zext(byte_val, LLVM::Int64, "byte_i64")

        if inst.result_var
          @variables[inst.result_var] = byte_i64
          @variable_types[inst.result_var] = :i64
        end

        byte_i64
      end

      # Get byte length (O(1))
      def generate_native_string_byte_length(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Load byte_len field
        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        if inst.result_var
          @variables[inst.result_var] = byte_len
          @variable_types[inst.result_var] = :i64
        end

        byte_len
      end

      # Search for byte in NativeString using memchr
      def generate_native_string_byte_index_of(inst)
        struct_type = get_native_string_struct
        declare_memchr
        ns_ptr = get_value(inst.native_string)

        # Get byte to search for
        byte_value, byte_type = get_value_with_type(inst.byte)
        byte_i32 = if byte_type == :i64
          @builder.trunc(byte_value, LLVM::Int32)
        else
          # If it's a VALUE, convert to i64 first then truncate
          byte_i64 = @builder.call(@rb_num2long, byte_value)
          @builder.trunc(byte_i64, LLVM::Int32)
        end

        # Load data pointer and length
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        # Handle start offset if provided
        search_ptr = data_ptr
        search_len = byte_len
        offset = LLVM::Int64.from_i(0)

        if inst.start_offset
          offset_value, offset_type = get_value_with_type(inst.start_offset)
          offset = offset_type == :i64 ? offset_value : @builder.call(@rb_num2long, offset_value)
          search_ptr = @builder.gep2(LLVM::Int8, data_ptr, [offset], "search_ptr")
          search_len = @builder.sub(byte_len, offset, "search_len")
        end

        # Call memchr
        result_ptr = @builder.call(@memchr, search_ptr, byte_i32, search_len, "memchr_result")

        # Check if found (result != null)
        null_ptr = LLVM::Pointer(LLVM::Int8).null_pointer
        is_found = @builder.icmp(:ne, result_ptr, null_ptr, "is_found")

        # Calculate index or return nil
        found_bb = @current_function.basic_blocks.append("byte_found")
        not_found_bb = @current_function.basic_blocks.append("byte_not_found")
        done_bb = @current_function.basic_blocks.append("byte_index_done")

        @builder.cond(is_found, found_bb, not_found_bb)

        # Found: calculate index
        @builder.position_at_end(found_bb)
        result_int = @builder.ptr2int(result_ptr, LLVM::Int64, "result_int")
        data_int = @builder.ptr2int(data_ptr, LLVM::Int64, "data_int")
        index = @builder.sub(result_int, data_int, "found_index")
        boxed_index = @builder.call(@rb_int2inum, index, "boxed_index")
        @builder.br(done_bb)

        # Not found: return nil
        @builder.position_at_end(not_found_bb)
        @builder.br(done_bb)

        # Done: phi node for result
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Int64, { found_bb => boxed_index, not_found_bb => @qnil }, "index_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Create byte-level slice of NativeString
      def generate_native_string_byte_slice(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Get start and length
        start_value, start_type = get_value_with_type(inst.start)
        start_i64 = start_type == :i64 ? start_value : @builder.call(@rb_num2long, start_value)

        length_value, length_type = get_value_with_type(inst.length)
        length_i64 = length_type == :i64 ? length_value : @builder.call(@rb_num2long, length_value)

        # Load data pointer
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        # Calculate new data pointer
        new_data_ptr = @builder.gep2(LLVM::Int8, data_ptr, [start_i64], "slice_data")

        # Allocate new NativeString struct
        slice_ptr = @builder.alloca(struct_type, "byte_slice")

        # Store fields
        slice_data_ptr = @builder.gep2(struct_type, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "slice_data_field")
        @builder.store(new_data_ptr, slice_data_ptr)

        slice_byte_len_ptr = @builder.gep2(struct_type, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "slice_byte_len_field")
        @builder.store(length_i64, slice_byte_len_ptr)

        # For byte slice, char_len = -1 (unknown without scanning)
        slice_char_len_ptr = @builder.gep2(struct_type, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "slice_char_len_field")
        @builder.store(LLVM::Int64.from_i(-1), slice_char_len_ptr)

        # Copy flags (ASCII status may still be valid)
        flags_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "flags_field")
        flags = @builder.load2(LLVM::Int64, flags_field_ptr, "flags")
        slice_flags_ptr = @builder.gep2(struct_type, slice_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "slice_flags_field")
        @builder.store(flags, slice_flags_ptr)

        if inst.result_var
          @variables[inst.result_var] = slice_ptr
          @variable_types[inst.result_var] = :native_string
        end

        slice_ptr
      end

      # Get character at index (UTF-8 aware)
      def generate_native_string_char_at(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Get index
        index_value, index_type = get_value_with_type(inst.index)
        char_index = index_type == :i64 ? index_value : @builder.call(@rb_num2long, index_value)

        # Load data pointer and byte length
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        flags_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "flags_ptr")
        flags = @builder.load2(LLVM::Int64, flags_ptr, "flags")

        # Check if ASCII-only (fast path)
        is_ascii = @builder.and(flags, LLVM::Int64.from_i(1), "ascii_flag")
        is_ascii_only = @builder.icmp(:ne, is_ascii, LLVM::Int64.from_i(0), "is_ascii_only")

        ascii_bb = @current_function.basic_blocks.append("char_at_ascii")
        utf8_bb = @current_function.basic_blocks.append("char_at_utf8")
        done_bb = @current_function.basic_blocks.append("char_at_done")

        @builder.cond(is_ascii_only, ascii_bb, utf8_bb)

        # ASCII path: direct byte access
        @builder.position_at_end(ascii_bb)
        byte_ptr = @builder.gep2(LLVM::Int8, data_ptr, [char_index], "ascii_byte_ptr")
        ascii_char = @builder.call(@rb_str_new, byte_ptr, LLVM::Int64.from_i(1), "ascii_char")
        @builder.br(done_bb)

        # UTF-8 path: scan to find character boundary
        # For simplicity, use rb_str_substr on the original string
        # This is a fallback - a full UTF-8 scanner would be more efficient
        @builder.position_at_end(utf8_bb)
        # Create Ruby String from data, then use [] on it
        temp_str = @builder.call(@rb_utf8_str_new, data_ptr, byte_len, "temp_str")
        # Call String#[] with index
        index_boxed = @builder.call(@rb_int2inum, char_index, "index_boxed")
        args_arr = @builder.alloca(LLVM::Array(LLVM::Int64, 1), "args")
        arg0_ptr = @builder.gep2(LLVM::Array(LLVM::Int64, 1), args_arr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "arg0")
        @builder.store(index_boxed, arg0_ptr)
        utf8_char = @builder.call(@rb_funcallv, temp_str, @builder.call(@rb_intern, @builder.global_string_pointer("\[\]")), LLVM::Int32.from_i(1), args_arr, "utf8_char")
        @builder.br(done_bb)

        # Done
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Int64, { ascii_bb => ascii_char, utf8_bb => utf8_char }, "char_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Get character length (UTF-8 aware, cached)
      def generate_native_string_char_length(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Load char_len field (may be -1 if not computed)
        char_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "char_len_ptr")
        cached_char_len = @builder.load2(LLVM::Int64, char_len_ptr, "cached_char_len")

        # Check if already computed (>= 0)
        is_computed = @builder.icmp(:sge, cached_char_len, LLVM::Int64.from_i(0), "is_computed")

        cached_bb = @current_function.basic_blocks.append("char_len_cached")
        compute_bb = @current_function.basic_blocks.append("char_len_compute")
        done_bb = @current_function.basic_blocks.append("char_len_done")

        @builder.cond(is_computed, cached_bb, compute_bb)

        # Cached path
        @builder.position_at_end(cached_bb)
        @builder.br(done_bb)

        # Compute path: scan UTF-8 bytes
        @builder.position_at_end(compute_bb)
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        # Create temp Ruby string and call length on it
        temp_str = @builder.call(@rb_utf8_str_new, data_ptr, byte_len, "temp_str")
        len_value = @builder.call(@rb_str_length, temp_str, "len_value")
        computed_len = @builder.call(@rb_num2long, len_value, "computed_len")

        # Cache the result
        @builder.store(computed_len, char_len_ptr)
        @builder.br(done_bb)

        # Done
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Int64, { cached_bb => cached_char_len, compute_bb => computed_len }, "char_len_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :i64
        end

        result
      end

      # Search for substring in NativeString
      def generate_native_string_char_index_of(inst)
        struct_type = get_native_string_struct
        declare_memmem
        ns_ptr = get_value(inst.native_string)

        # Get needle (Ruby String)
        needle_value = get_value(inst.needle)

        # Load haystack data and length
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        # Get needle C string and length
        needle_ptr_alloca = @builder.alloca(LLVM::Int64, "needle_ptr")
        @builder.store(needle_value, needle_ptr_alloca)
        needle_cstr = @builder.call(@rb_string_value_cstr, needle_ptr_alloca, "needle_cstr")
        needle_len_val = @builder.call(@rb_str_length, needle_value, "needle_len_val")
        needle_len = @builder.call(@rb_num2long, needle_len_val, "needle_len")

        # Call memmem
        result_ptr = @builder.call(@memmem, data_ptr, byte_len, needle_cstr, needle_len, "memmem_result")

        # Check if found
        null_ptr = LLVM::Pointer(LLVM::Int8).null_pointer
        is_found = @builder.icmp(:ne, result_ptr, null_ptr, "is_found")

        found_bb = @current_function.basic_blocks.append("needle_found")
        not_found_bb = @current_function.basic_blocks.append("needle_not_found")
        done_bb = @current_function.basic_blocks.append("char_index_done")

        @builder.cond(is_found, found_bb, not_found_bb)

        # Found: calculate byte index, then convert to char index if needed
        @builder.position_at_end(found_bb)
        result_int = @builder.ptr2int(result_ptr, LLVM::Int64, "result_int")
        data_int = @builder.ptr2int(data_ptr, LLVM::Int64, "data_int")
        byte_index = @builder.sub(result_int, data_int, "byte_index")

        # For now, return byte index boxed (char index would require UTF-8 scanning)
        boxed_index = @builder.call(@rb_int2inum, byte_index, "boxed_index")
        @builder.br(done_bb)

        # Not found
        @builder.position_at_end(not_found_bb)
        @builder.br(done_bb)

        # Done
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Int64, { found_bb => boxed_index, not_found_bb => @qnil }, "char_index_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Create character-level slice of NativeString (UTF-8 aware)
      def generate_native_string_char_slice(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Get start and length (character indices)
        start_value, start_type = get_value_with_type(inst.start)
        char_start = start_type == :i64 ? start_value : @builder.call(@rb_num2long, start_value)

        length_value, length_type = get_value_with_type(inst.length)
        char_length = length_type == :i64 ? length_value : @builder.call(@rb_num2long, length_value)

        # Load data and flags
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        flags_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "flags_ptr")
        flags = @builder.load2(LLVM::Int64, flags_ptr, "flags")

        # Check ASCII
        is_ascii = @builder.and(flags, LLVM::Int64.from_i(1), "ascii_flag")
        is_ascii_only = @builder.icmp(:ne, is_ascii, LLVM::Int64.from_i(0), "is_ascii_only")

        ascii_bb = @current_function.basic_blocks.append("char_slice_ascii")
        utf8_bb = @current_function.basic_blocks.append("char_slice_utf8")
        done_bb = @current_function.basic_blocks.append("char_slice_done")

        @builder.cond(is_ascii_only, ascii_bb, utf8_bb)

        # ASCII path: char index = byte index
        @builder.position_at_end(ascii_bb)
        ascii_new_ptr = @builder.gep2(LLVM::Int8, data_ptr, [char_start], "ascii_slice_ptr")
        ascii_slice = @builder.alloca(struct_type, "ascii_slice")

        ascii_data_ptr = @builder.gep2(struct_type, ascii_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "ascii_data_ptr")
        @builder.store(ascii_new_ptr, ascii_data_ptr)

        ascii_byte_len_ptr = @builder.gep2(struct_type, ascii_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "ascii_byte_len")
        @builder.store(char_length, ascii_byte_len_ptr)

        ascii_char_len_ptr = @builder.gep2(struct_type, ascii_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "ascii_char_len")
        @builder.store(char_length, ascii_char_len_ptr)  # For ASCII, byte_len = char_len

        ascii_flags_ptr = @builder.gep2(struct_type, ascii_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "ascii_flags")
        @builder.store(LLVM::Int64.from_i(1), ascii_flags_ptr)  # Still ASCII

        @builder.br(done_bb)

        # UTF-8 path: use Ruby's String#[] to get correct slice
        @builder.position_at_end(utf8_bb)
        temp_str = @builder.call(@rb_utf8_str_new, data_ptr, byte_len, "temp_str")

        # Call String#[start, length]
        start_boxed = @builder.call(@rb_int2inum, char_start, "start_boxed")
        len_boxed = @builder.call(@rb_int2inum, char_length, "len_boxed")
        args_arr = @builder.alloca(LLVM::Array(LLVM::Int64, 2), "slice_args")
        arg0_ptr = @builder.gep2(LLVM::Array(LLVM::Int64, 2), args_arr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "arg0")
        @builder.store(start_boxed, arg0_ptr)
        arg1_ptr = @builder.gep2(LLVM::Array(LLVM::Int64, 2), args_arr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "arg1")
        @builder.store(len_boxed, arg1_ptr)

        slice_str = @builder.call(@rb_funcallv, temp_str, @builder.call(@rb_intern, @builder.global_string_pointer("\[\]")), LLVM::Int32.from_i(2), args_arr, "slice_str")

        # Create NativeString from the sliced Ruby String
        utf8_slice = @builder.alloca(struct_type, "utf8_slice")

        # Get C string from sliced result
        slice_val_ptr = @builder.alloca(LLVM::Int64, "slice_val_ptr")
        @builder.store(slice_str, slice_val_ptr)
        utf8_data_ptr_val = @builder.call(@rb_string_value_cstr, slice_val_ptr, "utf8_data")

        utf8_len_val = @builder.call(@rb_str_length, slice_str, "utf8_len_val")
        utf8_byte_len_val = @builder.call(@rb_num2long, utf8_len_val, "utf8_byte_len")

        utf8_data_field = @builder.gep2(struct_type, utf8_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "utf8_data_field")
        @builder.store(utf8_data_ptr_val, utf8_data_field)

        utf8_blen_field = @builder.gep2(struct_type, utf8_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "utf8_blen_field")
        @builder.store(utf8_byte_len_val, utf8_blen_field)

        utf8_clen_field = @builder.gep2(struct_type, utf8_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "utf8_clen_field")
        @builder.store(char_length, utf8_clen_field)  # We know the char length

        utf8_flags_field = @builder.gep2(struct_type, utf8_slice, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "utf8_flags_field")
        @builder.store(LLVM::Int64.from_i(0), utf8_flags_field)  # Not ASCII

        @builder.br(done_bb)

        # Done
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Pointer(struct_type), { ascii_bb => ascii_slice, utf8_bb => utf8_slice }, "slice_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :native_string
        end

        result
      end

      # Check if NativeString is ASCII-only
      def generate_native_string_ascii_only(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Load flags
        flags_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "flags_ptr")
        flags = @builder.load2(LLVM::Int64, flags_ptr, "flags")

        # Check bit 0
        is_ascii = @builder.and(flags, LLVM::Int64.from_i(1), "ascii_flag")
        is_ascii_bool = @builder.icmp(:ne, is_ascii, LLVM::Int64.from_i(0), "is_ascii")

        # Convert to Ruby boolean
        result = @builder.select(is_ascii_bool, @qtrue, @qfalse, "ascii_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Check if NativeString starts with prefix
      def generate_native_string_starts_with(inst)
        struct_type = get_native_string_struct
        declare_memcmp
        ns_ptr = get_value(inst.native_string)
        prefix_value = get_value(inst.prefix)

        # Load data and length
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        # Get prefix C string and length
        prefix_ptr_alloca = @builder.alloca(LLVM::Int64, "prefix_ptr")
        @builder.store(prefix_value, prefix_ptr_alloca)
        prefix_cstr = @builder.call(@rb_string_value_cstr, prefix_ptr_alloca, "prefix_cstr")
        prefix_len_val = @builder.call(@rb_str_length, prefix_value, "prefix_len_val")
        prefix_len = @builder.call(@rb_num2long, prefix_len_val, "prefix_len")

        # Check if string is long enough
        is_long_enough = @builder.icmp(:uge, byte_len, prefix_len, "is_long_enough")

        check_bb = @current_function.basic_blocks.append("starts_with_check")
        too_short_bb = @current_function.basic_blocks.append("starts_with_short")
        done_bb = @current_function.basic_blocks.append("starts_with_done")

        @builder.cond(is_long_enough, check_bb, too_short_bb)

        # Check with memcmp
        @builder.position_at_end(check_bb)
        cmp_result = @builder.call(@memcmp, data_ptr, prefix_cstr, prefix_len, "cmp_result")
        is_match = @builder.icmp(:eq, cmp_result, LLVM::Int32.from_i(0), "is_match")
        match_result = @builder.select(is_match, @qtrue, @qfalse, "match_result")
        @builder.br(done_bb)

        # Too short
        @builder.position_at_end(too_short_bb)
        @builder.br(done_bb)

        # Done
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Int64, { check_bb => match_result, too_short_bb => @qfalse }, "starts_with_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Check if NativeString ends with suffix
      def generate_native_string_ends_with(inst)
        struct_type = get_native_string_struct
        declare_memcmp
        ns_ptr = get_value(inst.native_string)
        suffix_value = get_value(inst.suffix)

        # Load data and length
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        # Get suffix C string and length
        suffix_ptr_alloca = @builder.alloca(LLVM::Int64, "suffix_ptr")
        @builder.store(suffix_value, suffix_ptr_alloca)
        suffix_cstr = @builder.call(@rb_string_value_cstr, suffix_ptr_alloca, "suffix_cstr")
        suffix_len_val = @builder.call(@rb_str_length, suffix_value, "suffix_len_val")
        suffix_len = @builder.call(@rb_num2long, suffix_len_val, "suffix_len")

        # Check if string is long enough
        is_long_enough = @builder.icmp(:uge, byte_len, suffix_len, "is_long_enough")

        check_bb = @current_function.basic_blocks.append("ends_with_check")
        too_short_bb = @current_function.basic_blocks.append("ends_with_short")
        done_bb = @current_function.basic_blocks.append("ends_with_done")

        @builder.cond(is_long_enough, check_bb, too_short_bb)

        # Check with memcmp at end of string
        @builder.position_at_end(check_bb)
        offset = @builder.sub(byte_len, suffix_len, "end_offset")
        end_ptr = @builder.gep2(LLVM::Int8, data_ptr, [offset], "end_ptr")
        cmp_result = @builder.call(@memcmp, end_ptr, suffix_cstr, suffix_len, "cmp_result")
        is_match = @builder.icmp(:eq, cmp_result, LLVM::Int32.from_i(0), "is_match")
        match_result = @builder.select(is_match, @qtrue, @qfalse, "match_result")
        @builder.br(done_bb)

        # Too short
        @builder.position_at_end(too_short_bb)
        @builder.br(done_bb)

        # Done
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Int64, { check_bb => match_result, too_short_bb => @qfalse }, "ends_with_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Check if NativeString has valid UTF-8 encoding
      def generate_native_string_valid_encoding(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Load data and length
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        # Create temp Ruby string and call valid_encoding? on it
        temp_str = @builder.call(@rb_utf8_str_new, data_ptr, byte_len, "temp_str")
        result = @builder.call(@rb_funcallv, temp_str, @builder.call(@rb_intern, @builder.global_string_pointer("valid_encoding?")), LLVM::Int32.from_i(0),
          LLVM::Pointer(LLVM::Int64).null_pointer, "valid_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Convert NativeString to Ruby String
      def generate_native_string_to_ruby(inst)
        struct_type = get_native_string_struct
        ns_ptr = get_value(inst.native_string)

        # Load data and length
        data_field_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data_field")
        data_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), data_field_ptr, "data_ptr")

        byte_len_ptr = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "byte_len_ptr")
        byte_len = @builder.load2(LLVM::Int64, byte_len_ptr, "byte_len")

        # Create Ruby String
        result = @builder.call(@rb_str_new, data_ptr, byte_len, "ruby_string")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Compare two NativeStrings
      def generate_native_string_compare(inst)
        struct_type = get_native_string_struct
        declare_memcmp
        ns_ptr = get_value(inst.native_string)
        other_ptr = get_value(inst.other)

        # Load data and length for both
        data1_field = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data1_field")
        data1 = @builder.load2(LLVM::Pointer(LLVM::Int8), data1_field, "data1")

        len1_field = @builder.gep2(struct_type, ns_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len1_field")
        len1 = @builder.load2(LLVM::Int64, len1_field, "len1")

        data2_field = @builder.gep2(struct_type, other_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "data2_field")
        data2 = @builder.load2(LLVM::Pointer(LLVM::Int8), data2_field, "data2")

        len2_field = @builder.gep2(struct_type, other_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "len2_field")
        len2 = @builder.load2(LLVM::Int64, len2_field, "len2")

        # First check lengths
        same_len = @builder.icmp(:eq, len1, len2, "same_len")

        compare_bb = @current_function.basic_blocks.append("compare_content")
        diff_len_bb = @current_function.basic_blocks.append("diff_len")
        done_bb = @current_function.basic_blocks.append("compare_done")

        @builder.cond(same_len, compare_bb, diff_len_bb)

        # Compare content
        @builder.position_at_end(compare_bb)
        cmp_result = @builder.call(@memcmp, data1, data2, len1, "cmp_result")
        is_equal = @builder.icmp(:eq, cmp_result, LLVM::Int32.from_i(0), "is_equal")
        equal_result = @builder.select(is_equal, @qtrue, @qfalse, "equal_result")
        @builder.br(done_bb)

        # Different lengths
        @builder.position_at_end(diff_len_bb)
        @builder.br(done_bb)

        # Done
        @builder.position_at_end(done_bb)
        result = @builder.phi(LLVM::Int64, { compare_bb => equal_result, diff_len_bb => @qfalse }, "compare_result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # ========================================
      # JSON parsing
      # Direct JSON to NativeClass conversion
      # ========================================

      # Parse JSON string directly into a NativeClass
      # Avoids Ruby VALUE conversion for unboxed fields
      def generate_json_parse_as(inst)
        target_class = inst.target_class
        llvm_struct = get_or_create_native_class_struct(target_class)

        # Get JSON string VALUE
        json_value = get_value(inst.json_expr)

        # Get C string pointer and length from Ruby String
        # We need to use rb_string_value_cstr which requires a pointer to VALUE
        json_ptr_alloca = @builder.alloca(value_type, "json_ptr")
        @builder.store(json_value, json_ptr_alloca)
        str_ptr = @builder.call(@rb_string_value_cstr, json_ptr_alloca, "json_cstr")

        # Get string length
        str_len_value = @builder.call(@rb_str_length, json_value, "json_len_val")
        str_len = @builder.call(@rb_num2long, str_len_value, "json_len")

        # Parse JSON with yyjson
        doc = @builder.call(@yyjson_read, str_ptr, str_len, LLVM::Int32.from_i(0), "json_doc")
        root = @builder.call(@yyjson_doc_get_root, doc, "json_root")

        # Allocate NativeClass struct
        struct_ptr = @builder.alloca(llvm_struct, "native_#{target_class.name}")

        # Zero-initialize the struct
        struct_size = calculate_native_class_size(target_class)
        struct_ptr_i8 = @builder.bit_cast(struct_ptr, LLVM::Pointer(LLVM::Int8), "struct_i8")
        @builder.call(@memset, struct_ptr_i8, LLVM::Int32.from_i(0), LLVM::Int64.from_i(struct_size))

        # Get field information
        fields = target_class.fields
        field_offset = 0  # Adjust if vtable is used

        # Process each field
        fields.each_with_index do |(field_name, field_type), idx|
          # Get JSON value for this field
          field_key = @builder.global_string_pointer(field_name.to_s)
          field_val = @builder.call(@yyjson_obj_get, root, field_key, "field_#{field_name}")

          # Get struct field pointer
          field_ptr = @builder.gep2(llvm_struct, struct_ptr,
                                    [LLVM::Int32.from_i(0), LLVM::Int32.from_i(field_offset + idx)],
                                    "#{field_name}_ptr")

          # Check if field value is not null
          is_null = @builder.icmp(:eq, field_val, LLVM::Pointer(LLVM::Int8).null, "#{field_name}_is_null")

          # Create blocks for conditional
          store_bb = @current_function.basic_blocks.append("store_#{field_name}")
          skip_bb = @current_function.basic_blocks.append("skip_#{field_name}")
          cont_bb = @current_function.basic_blocks.append("cont_#{field_name}")

          @builder.cond(is_null, skip_bb, store_bb)

          # Store value if not null
          @builder.position_at_end(store_bb)
          case field_type
          when :Int64, :Integer
            # Unboxed integer: direct copy
            i64_val = @builder.call(@yyjson_get_sint, field_val, "#{field_name}_i64")
            @builder.store(i64_val, field_ptr)
          when :Float64, :Float
            # Unboxed float: direct copy
            f64_val = @builder.call(@yyjson_get_real, field_val, "#{field_name}_f64")
            @builder.store(f64_val, field_ptr)
          when :Bool
            # Unboxed bool: convert to i8
            bool_val = @builder.call(@yyjson_get_bool, field_val, "#{field_name}_bool")
            i8_val = @builder.zext(bool_val, LLVM::Int8, "#{field_name}_i8")
            @builder.store(i8_val, field_ptr)
          when :String
            # Ruby String: convert from C string
            cstr = @builder.call(@yyjson_get_str, field_val, "#{field_name}_cstr")
            len = @builder.call(@yyjson_get_len, field_val, "#{field_name}_len")
            ruby_str = @builder.call(@rb_utf8_str_new, cstr, len, "#{field_name}_str")
            @builder.store(ruby_str, field_ptr)
          else
            # Other VALUE types: need more complex handling
            # For now, store Qnil
            @builder.store(@qnil, field_ptr)
          end
          @builder.br(cont_bb)

          # Skip (value stays zero-initialized)
          @builder.position_at_end(skip_bb)
          @builder.br(cont_bb)

          # Continue
          @builder.position_at_end(cont_bb)
        end

        # Free JSON document
        @builder.call(@yyjson_doc_free, doc)

        # Store result
        if inst.result_var
          @variables[inst.result_var] = struct_ptr
          @variable_types[inst.result_var] = :native_class
          # Also track the class type for field access
          @native_class_types ||= {}
          @native_class_types[inst.result_var] = target_class
        end

        struct_ptr
      end

      # Parse JSON array directly into NativeArray[NativeClass]
      def generate_json_parse_array_as(inst)
        element_class = inst.element_class
        llvm_struct = get_or_create_native_class_struct(element_class)

        # Get JSON string VALUE
        json_value = get_value(inst.json_expr)

        # Get C string pointer and length from Ruby String
        json_ptr_alloca = @builder.alloca(value_type, "json_arr_ptr")
        @builder.store(json_value, json_ptr_alloca)
        str_ptr = @builder.call(@rb_string_value_cstr, json_ptr_alloca, "json_arr_cstr")
        str_len_value = @builder.call(@rb_str_length, json_value, "json_arr_len_val")
        str_len = @builder.call(@rb_num2long, str_len_value, "json_arr_len")

        # Parse JSON with yyjson
        doc = @builder.call(@yyjson_read, str_ptr, str_len, LLVM::Int32.from_i(0), "json_arr_doc")
        root = @builder.call(@yyjson_doc_get_root, doc, "json_arr_root")

        # Get array size
        arr_size = @builder.call(@yyjson_arr_size, root, "json_arr_size")

        # Allocate NativeArray on stack
        llvm_elem_type = llvm_struct
        array_ptr = @builder.array_alloca(llvm_elem_type, arr_size, "json_native_arr")

        # Zero-initialize the array
        elem_size = calculate_native_class_size(element_class)
        total_size = @builder.mul(arr_size, LLVM::Int64.from_i(elem_size), "json_arr_total")
        array_ptr_i8 = @builder.bit_cast(array_ptr, LLVM::Pointer(LLVM::Int8), "json_arr_i8")
        @builder.call(@memset, array_ptr_i8, LLVM::Int32.from_i(0), total_size)

        # Loop over array elements
        loop_bb = @current_function.basic_blocks.append("json_arr_loop")
        body_bb = @current_function.basic_blocks.append("json_arr_body")
        done_bb = @current_function.basic_blocks.append("json_arr_done")

        # Initialize loop counter
        idx_alloca = @builder.alloca(LLVM::Int64, "json_arr_idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)
        @builder.br(loop_bb)

        # Loop condition
        @builder.position_at_end(loop_bb)
        idx = @builder.load2(LLVM::Int64, idx_alloca, "idx")
        cond = @builder.icmp(:ult, idx, arr_size, "json_arr_cond")
        @builder.cond(cond, body_bb, done_bb)

        # Loop body: parse each element
        @builder.position_at_end(body_bb)

        # Get JSON element at index
        elem_val = @builder.call(@yyjson_arr_get, root, idx, "json_elem")

        # Get pointer to NativeClass struct in the array
        struct_ptr = @builder.gep(array_ptr, [idx], "elem_struct_ptr")

        # Parse fields from JSON object into struct
        fields = element_class.fields
        field_offset = 0

        fields.each_with_index do |(field_name, field_type), fidx|
          field_key = @builder.global_string_pointer(field_name.to_s)
          field_val = @builder.call(@yyjson_obj_get, elem_val, field_key, "arr_field_#{field_name}")

          field_ptr = @builder.gep2(llvm_struct, struct_ptr,
                                    [LLVM::Int32.from_i(0), LLVM::Int32.from_i(field_offset + fidx)],
                                    "arr_#{field_name}_ptr")

          is_null = @builder.icmp(:eq, field_val, LLVM::Pointer(LLVM::Int8).null, "arr_#{field_name}_null")

          store_bb_f = @current_function.basic_blocks.append("arr_store_#{field_name}")
          skip_bb_f = @current_function.basic_blocks.append("arr_skip_#{field_name}")
          cont_bb_f = @current_function.basic_blocks.append("arr_cont_#{field_name}")

          @builder.cond(is_null, skip_bb_f, store_bb_f)

          @builder.position_at_end(store_bb_f)
          case field_type
          when :Int64, :Integer
            i64_val = @builder.call(@yyjson_get_sint, field_val, "arr_#{field_name}_i64")
            @builder.store(i64_val, field_ptr)
          when :Float64, :Float
            f64_val = @builder.call(@yyjson_get_real, field_val, "arr_#{field_name}_f64")
            @builder.store(f64_val, field_ptr)
          when :Bool
            bool_val = @builder.call(@yyjson_get_bool, field_val, "arr_#{field_name}_bool")
            i8_val = @builder.zext(bool_val, LLVM::Int8, "arr_#{field_name}_i8")
            @builder.store(i8_val, field_ptr)
          when :String
            cstr = @builder.call(@yyjson_get_str, field_val, "arr_#{field_name}_cstr")
            len = @builder.call(@yyjson_get_len, field_val, "arr_#{field_name}_len")
            ruby_str = @builder.call(@rb_utf8_str_new, cstr, len, "arr_#{field_name}_str")
            @builder.store(ruby_str, field_ptr)
          else
            @builder.store(@qnil, field_ptr)
          end
          @builder.br(cont_bb_f)

          @builder.position_at_end(skip_bb_f)
          @builder.br(cont_bb_f)

          @builder.position_at_end(cont_bb_f)
        end

        # Increment counter
        next_idx = @builder.add(idx, LLVM::Int64.from_i(1), "next_idx")
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_bb)

        # Done
        @builder.position_at_end(done_bb)

        # Free JSON document
        @builder.call(@yyjson_doc_free, doc)

        # Store result
        if inst.result_var
          @variables[inst.result_var] = array_ptr
          @variable_types[inst.result_var] = :native_array
          @variables["#{inst.result_var}_len"] = arr_size
          @native_array_class_types ||= {}
          @native_array_class_types[inst.result_var] = element_class
        end

        array_ptr
      end

      # Calculate size of NativeClass struct in bytes
      def calculate_native_class_size(class_type)
        size = 0
        class_type.fields.each do |_name, field_type|
          case field_type
          when :Int64, :Integer, :Float64, :Float, :String, :Object, :Array, :Hash
            size += 8
          when :Bool
            size += 1
          else
            size += 8  # Pointer or VALUE
          end
        end
        # Align to 8 bytes
        (size + 7) / 8 * 8
      end

      # ========================================
      # NativeClass code generation
      # ========================================

      # Allocate a NativeClass instance on the stack
      # Returns a pointer to the struct (or struct value for value types)
      def generate_native_new(inst)
        class_type = inst.class_type
        llvm_struct = get_or_create_native_class_struct(class_type)
        uses_vtable = class_uses_vtable?(class_type)
        is_value_type = is_value_type_class?(class_type)

        # Value types use insertvalue chain instead of alloca + store
        if is_value_type && !uses_vtable
          return generate_value_struct_new(inst, class_type, llvm_struct)
        end

        # Allocate struct on stack (reference type)
        struct_ptr = @builder.alloca(llvm_struct, "native_#{class_type.name}")

        # Field index offset (1 if vtable, 0 otherwise)
        field_offset = uses_vtable ? 1 : 0

        # Initialize vptr if using vtable
        if uses_vtable
          vtable_info = get_vtable_for_class(class_type)
          if vtable_info
            vptr_ptr = @builder.struct_gep(struct_ptr, 0, "vptr_ptr")
            vtable_ptr = @builder.bit_cast(vtable_info[:global], LLVM::Pointer(LLVM::Int8))
            @builder.store(vtable_ptr, vptr_ptr)
          end
        end

        # Initialize all fields to zero/Qnil
        class_type.fields.each_with_index do |(field_name, field_type), idx|
          field_ptr = @builder.struct_gep(struct_ptr, idx + field_offset, "#{field_name}_ptr")
          case field_type
          when :Int64
            @builder.store(LLVM::Int64.from_i(0), field_ptr)
          when :Float64
            @builder.store(LLVM::Double.from_f(0.0), field_ptr)
          when :Bool
            @builder.store(LLVM::Int8.from_i(0), field_ptr)
          when :String, :Object, :Array, :Hash
            # Initialize VALUE fields to Qnil for GC safety
            @builder.store(@qnil, field_ptr)
          else
            # Embedded NativeClass - initialize each sub-field to zero
            embedded_class = @native_class_type_registry[field_type]
            if embedded_class
              embedded_class.fields.each_with_index do |(sub_field_name, sub_field_type), sub_idx|
                sub_field_ptr = @builder.struct_gep(field_ptr, sub_idx, "#{field_name}_#{sub_field_name}_ptr")
                zero_val = case sub_field_type
                when :Int64 then LLVM::Int64.from_i(0)
                when :Float64 then LLVM::Double.from_f(0.0)
                when :Bool then LLVM::Int8.from_i(0)
                else LLVM::Double.from_f(0.0)
                end
                @builder.store(zero_val, sub_field_ptr)
              end
            end
          end
        end

        if inst.result_var
          @variables[inst.result_var] = struct_ptr
          @variable_types[inst.result_var] = :native_class
          @native_class_types ||= {}
          @native_class_types[inst.result_var] = class_type
        end

        struct_ptr
      end

      # Generate value struct creation
      # Uses alloca + zero initialization, but tracks as value type for method calls
      def generate_value_struct_new(inst, class_type, llvm_struct)
        # Allocate on stack and zero-initialize
        struct_ptr = @builder.alloca(llvm_struct, "value_#{class_type.name}")

        # Initialize each field to zero
        class_type.fields.each_with_index do |(field_name, field_type), idx|
          field_ptr = @builder.struct_gep(struct_ptr, idx, "#{field_name}_ptr")
          zero_val = case field_type
          when :Int64 then LLVM::Int64.from_i(0)
          when :Float64 then LLVM::Double.from_f(0.0)
          when :Bool then LLVM::Int8.from_i(0)
          else
            # Embedded NativeClass - not supported in value types for now
            raise "Value types cannot have embedded NativeClass fields: #{field_name}"
          end
          @builder.store(zero_val, field_ptr)
        end

        if inst.result_var
          # Store pointer but track as value struct (will load for method calls)
          @variables[inst.result_var] = struct_ptr
          @variable_types[inst.result_var] = :value_struct
          @native_class_types ||= {}
          @native_class_types[inst.result_var] = class_type
        end

        struct_ptr
      end

      # Get field from NativeClass (unboxed)
      def generate_native_field_get(inst)
        class_type = inst.class_type
        field_name = inst.field_name
        field_type_tag = class_type.llvm_field_type_tag(field_name)

        # Check if receiver is a value struct (uses non-vtable field index)
        receiver_var_name = inst.object.is_a?(HIR::LoadLocal) ? inst.object.var.name : nil
        is_value_struct = receiver_var_name && is_value_struct_var?(receiver_var_name)

        # Value structs use simple field index (no vtable), reference types use adjusted index
        field_index = if is_value_struct
          class_type.field_index(field_name)
        else
          adjusted_field_index(class_type, field_name)
        end

        # Get object pointer (value struct vars also store pointers to allocas)
        object_ptr = if is_value_struct
          @variables[receiver_var_name]
        else
          get_native_class_ptr(inst.object)
        end

        llvm_struct = get_or_create_native_class_struct(class_type)

        # Determine LLVM type for the field
        llvm_field_type = case field_type_tag
        when :i64 then LLVM::Int64
        when :double then LLVM::Double
        when :i8 then LLVM::Int8
        else value_type
        end

        # GEP to get field pointer - use struct_gep2 with explicit type
        field_ptr = @builder.struct_gep2(llvm_struct, object_ptr, field_index, "#{field_name}_ptr")

        # Load field value with explicit type
        field_value = @builder.load2(llvm_field_type, field_ptr, "#{field_name}_val")

        if inst.result_var
          @variables[inst.result_var] = field_value
          @variable_types[inst.result_var] = field_type_tag
        end

        field_value
      end

      # Set field in NativeClass
      def generate_native_field_set(inst)
        class_type = inst.class_type
        field_name = inst.field_name
        field_type_tag = class_type.llvm_field_type_tag(field_name)

        # Get value to store
        store_value, value_type = get_value_with_type(inst.value)
        converted_value = convert_value(store_value, value_type, field_type_tag)

        # Check if receiver is a value struct (uses non-vtable field index)
        receiver_var_name = inst.object.is_a?(HIR::LoadLocal) ? inst.object.var.name : nil
        is_value_struct = receiver_var_name && is_value_struct_var?(receiver_var_name)

        # Value structs use simple field index (no vtable), reference types use adjusted index
        field_index = if is_value_struct
          class_type.field_index(field_name)
        else
          adjusted_field_index(class_type, field_name)
        end

        # Get object pointer (value struct vars also store pointers to allocas)
        object_ptr = if is_value_struct
          @variables[receiver_var_name]
        else
          get_native_class_ptr(inst.object)
        end

        llvm_struct = get_or_create_native_class_struct(class_type)

        # GEP to get field pointer - use struct_gep2 with explicit type
        field_ptr = @builder.struct_gep2(llvm_struct, object_ptr, field_index, "#{field_name}_ptr")

        # Store value
        @builder.store(converted_value, field_ptr)

        converted_value
      end

      # Call a method on a NativeClass instance
      # Uses vtable dispatch if the class uses vtable, static dispatch otherwise
      def generate_native_method_call(inst)
        class_type = inst.class_type
        method_name = inst.method_name
        method_sig = inst.method_sig
        owner_class = inst.owner_class
        is_value_type = is_value_type_class?(class_type)

        # Check if receiver is a value struct variable
        receiver_var_name = inst.receiver.is_a?(HIR::LoadLocal) ? inst.receiver.var.name : nil
        is_value_struct_receiver = receiver_var_name && is_value_struct_var?(receiver_var_name)

        # Get receiver (pointer for ref types, load struct value for value types)
        receiver = if is_value_struct_receiver && is_value_type
          # Value type: load the struct value from alloca and pass by value
          struct_ptr = @variables[receiver_var_name]
          llvm_struct = get_or_create_native_class_struct(class_type)
          @builder.load2(llvm_struct, struct_ptr, "value_struct_load")
        else
          get_native_class_ptr(inst.receiver)  # Get pointer for reference types
        end

        # Build argument list: [self, arg1, arg2, ...]
        call_args = [receiver]

        inst.args.each_with_index do |arg, i|
          param_type = method_sig.param_types[i]
          arg_value, arg_type_tag = get_value_with_type(arg)

          # Convert to expected native type
          converted_arg = case param_type
          when :Int64
            convert_value(arg_value, arg_type_tag, :i64)
          when :Float64
            convert_value(arg_value, arg_type_tag, :double)
          else
            # Could be another NativeClass type
            # Check if it's a value struct argument
            if arg.is_a?(HIR::LoadLocal) && is_value_struct_var?(arg.var.name)
              @variables[arg.var.name]  # Pass value struct by value
            else
              arg_value  # Pass pointer for reference types
            end
          end

          call_args << converted_arg
        end

        # Choose dispatch method based on whether class uses vtable
        result = if class_uses_vtable?(class_type)
          generate_vtable_call(class_type, method_name, method_sig, receiver, call_args)
        else
          # Static dispatch - get or create the native method function
          native_func = get_or_create_native_method_func(owner_class, method_name, method_sig)
          @builder.call(native_func, *call_args, "#{method_name}_result")
        end

        # Store result with appropriate type tag
        if inst.result_var
          # Determine result type - check if it's a value type
          return_class = method_sig.return_type == :Self ? class_type : (owner_class || class_type)
          returns_value_type = method_sig.return_type == :Self && is_value_type

          result_type_tag = case method_sig.return_type
          when :Int64 then :i64
          when :Float64 then :double
          when :Void then :value  # Will be nil
          when :Self then returns_value_type ? :value_struct : :native_class
          else :native_class  # Assume other types are NativeClass
          end

          if result_type_tag == :value_struct
            # Value type returned - store struct value directly
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :value_struct
            @native_class_types ||= {}
            @native_class_types[inst.result_var] = return_class
          elsif result_type_tag == :native_class
            # Reference type: Struct returned by value - allocate space and store
            struct_type = get_or_create_native_class_struct(return_class)

            # Allocate space for the struct in the caller's stack
            result_alloca = @builder.alloca(struct_type, "#{method_name}_retval")

            # Store the returned struct value
            @builder.store(result, result_alloca)

            # Use the pointer to the stored struct
            @variables[inst.result_var] = result_alloca
            @variable_types[inst.result_var] = result_type_tag

            @native_class_types ||= {}
            @native_class_types[inst.result_var] = return_class

            result = result_alloca
          else
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = result_type_tag
          end
        end

        result
      end

      # Generate code for CFuncCall instruction - direct C function call
      # Bypasses Ruby method dispatch entirely for @cfunc annotated methods
      def generate_cfunc_call(inst)
        cfunc_type = inst.cfunc_type
        func = declare_cfunc(cfunc_type)

        # Convert arguments with type coercion
        call_args = inst.args.each_with_index.map do |arg, i|
          arg_value, arg_type_tag = get_value_with_type(arg)
          expected_type = cfunc_type.param_types[i]
          convert_to_cfunc_arg(arg_value, arg_type_tag, expected_type)
        end

        # Call the C function
        result = if cfunc_type.return_type == :void
          @builder.call(func, *call_args)
          @qnil
        else
          raw_result = @builder.call(func, *call_args, "cfunc_result")
          convert_from_cfunc_result(raw_result, cfunc_type.return_type)
        end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Declare an external C function for @cfunc calls
      def declare_cfunc(cfunc_type)
        @declared_cfuncs ||= {}
        return @declared_cfuncs[cfunc_type.c_func_name] if @declared_cfuncs[cfunc_type.c_func_name]

        # Convert types to LLVM types
        param_types = cfunc_type.param_types.map { |t| cfunc_type_to_llvm(t) }
        return_type = cfunc_type_to_llvm(cfunc_type.return_type)

        func = @mod.functions.add(cfunc_type.c_func_name, param_types, return_type)
        func.linkage = :external
        @declared_cfuncs[cfunc_type.c_func_name] = func
        func
      end

      # Convert CFuncType type symbol to LLVM type
      def cfunc_type_to_llvm(type_sym)
        case type_sym
        when :Float then LLVM::Double
        when :Integer then LLVM::Int64
        when :String then LLVM::Int64  # VALUE
        when :Bool then LLVM::Int1
        when :void then LLVM.Void
        else LLVM::Int64  # Default to VALUE for unknown types
        end
      end

      # Convert Ruby VALUE to C type for cfunc argument
      def convert_to_cfunc_arg(value, current_type_tag, target_type)
        case target_type
        when :Float
          # VALUE or double -> double
          if current_type_tag == :double
            value
          else
            # Box if it's unboxed i64 first
            boxed = if current_type_tag == :i64
              @builder.call(@rb_int2inum, value)
            else
              value
            end
            @builder.call(@rb_num2dbl, boxed)
          end
        when :Integer
          # VALUE or i64 -> int64_t
          if current_type_tag == :i64
            value
          else
            # Box if it's unboxed double first
            boxed = if current_type_tag == :double
              @builder.call(@rb_float_new, value)
            else
              value
            end
            @builder.call(@rb_num2long, boxed)
          end
        when :String
          # Keep as VALUE
          if current_type_tag == :i64
            @builder.call(@rb_int2inum, value)
          elsif current_type_tag == :double
            @builder.call(@rb_float_new, value)
          else
            value
          end
        when :Bool
          # VALUE -> i1 (truthy check)
          boxed = if current_type_tag == :i64
            @builder.call(@rb_int2inum, value)
          elsif current_type_tag == :double
            @builder.call(@rb_float_new, value)
          else
            value
          end
          is_truthy = @builder.icmp(:ne, boxed, @qfalse)
          is_not_nil = @builder.icmp(:ne, boxed, @qnil)
          @builder.and(is_truthy, is_not_nil)
        else
          # Pass as-is (ensure it's boxed)
          if current_type_tag == :i64
            @builder.call(@rb_int2inum, value)
          elsif current_type_tag == :double
            @builder.call(@rb_float_new, value)
          else
            value
          end
        end
      end

      # Convert C result to Ruby VALUE
      def convert_from_cfunc_result(value, source_type)
        case source_type
        when :Float
          # double -> VALUE
          @builder.call(@rb_float_new, value)
        when :Integer
          # int64_t -> VALUE
          @builder.call(@rb_int2inum, value)
        when :String
          # Assume VALUE string returned
          value
        when :Bool
          # i1 -> VALUE (Qtrue/Qfalse)
          @builder.select(value, @qtrue, @qfalse)
        else
          value
        end
      end

      # ========================================
      # ExternClass code generation
      # ========================================

      # Generate code for ExternConstructorCall
      # Creates a wrapper struct and calls the C constructor
      def generate_extern_constructor_call(inst)
        extern_type = inst.extern_type
        method_sig = inst.method_sig

        # Get or declare the C function
        func = declare_extern_cfunc(inst.c_func_name, method_sig, constructor: true)

        # Convert arguments
        call_args = inst.args.each_with_index.map do |arg, i|
          arg_value, arg_type_tag = get_value_with_type(arg)
          expected_type = method_sig.param_types[i]
          convert_to_cfunc_arg(arg_value, arg_type_tag, expected_type)
        end

        # Call the C constructor - returns opaque pointer
        raw_ptr = @builder.call(func, *call_args, "extern_ptr")

        # Allocate wrapper struct and store pointer
        wrapper_struct = get_or_create_extern_struct(extern_type)
        wrapper_ptr = @builder.alloca(wrapper_struct, "extern_wrapper_#{extern_type.name}")
        ptr_field = @builder.struct_gep2(wrapper_struct, wrapper_ptr, 0, "ptr_field")
        @builder.store(raw_ptr, ptr_field)

        if inst.result_var
          @variables[inst.result_var] = wrapper_ptr
          @variable_types[inst.result_var] = :extern_ptr
          @extern_class_type_registry ||= {}
          @extern_class_type_registry[inst.result_var] = extern_type
        end

        wrapper_ptr
      end

      # Generate code for ExternMethodCall
      # Extracts opaque pointer and calls C function with it
      def generate_extern_method_call(inst)
        extern_type = inst.extern_type
        method_sig = inst.method_sig

        # Get or declare the C function
        func = declare_extern_cfunc(inst.c_func_name, method_sig, constructor: false)

        # Get receiver and extract opaque pointer
        receiver_ptr = get_extern_ptr(inst.receiver)
        wrapper_struct = get_or_create_extern_struct(extern_type)
        ptr_field = @builder.struct_gep2(wrapper_struct, receiver_ptr, 0, "ptr_field")
        opaque_ptr = @builder.load2(ptr_type, ptr_field, "opaque_ptr")

        # Build call args: [opaque_ptr, ...user_args...]
        call_args = [opaque_ptr]

        # Skip the first param type (opaque pointer) when converting user args
        user_param_types = method_sig.param_types[1..]
        inst.args.each_with_index do |arg, i|
          arg_value, arg_type_tag = get_value_with_type(arg)
          expected_type = user_param_types[i]
          call_args << convert_to_cfunc_arg(arg_value, arg_type_tag, expected_type)
        end

        # Call the C function
        result = if method_sig.return_type == :void
          @builder.call(func, *call_args)
          @qnil
        else
          raw_result = @builder.call(func, *call_args, "extern_result")
          convert_from_cfunc_result(raw_result, method_sig.return_type)
        end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :value
        end

        result
      end

      # Get or create wrapper struct for extern class
      # Extern classes use a simple struct with a single void* field
      def get_or_create_extern_struct(extern_type)
        @extern_class_structs ||= {}
        return @extern_class_structs[extern_type.name] if @extern_class_structs[extern_type.name]

        struct_type = LLVM::Type.struct([ptr_type], false, "Extern_#{extern_type.name}")
        @extern_class_structs[extern_type.name] = struct_type
        struct_type
      end

      # Declare external C function for extern class
      def declare_extern_cfunc(c_func_name, method_sig, constructor: false)
        @declared_extern_cfuncs ||= {}
        return @declared_extern_cfuncs[c_func_name] if @declared_extern_cfuncs[c_func_name]

        # Build parameter types
        param_types = if constructor
          # Constructor: just user params, returns ptr
          method_sig.param_types.map { |t| extern_type_to_llvm(t) }
        else
          # Instance method: first param is opaque ptr
          method_sig.param_types.map { |t| extern_type_to_llvm(t) }
        end

        return_type = extern_type_to_llvm(method_sig.return_type)

        func = @mod.functions.add(c_func_name, param_types, return_type)
        func.linkage = :external
        @declared_extern_cfuncs[c_func_name] = func
        func
      end

      # Convert extern type symbol to LLVM type
      def extern_type_to_llvm(type_sym)
        case type_sym
        when :Float then LLVM::Double
        when :Integer then LLVM::Int64
        when :String then LLVM::Int64  # VALUE
        when :Bool then LLVM::Int1
        when :ptr then ptr_type
        when :void then LLVM.Void
        when :Array, :Hash then LLVM::Int64  # VALUE
        else LLVM::Int64  # Default to VALUE
        end
      end

      # Get extern class pointer from variable reference
      def get_extern_ptr(ref)
        case ref
        when HIR::LoadLocal, HIR::Instruction
          var_name = ref.result_var || ref.var&.name
          @variables[var_name]
        when String
          @variables[ref]
        else
          ref
        end
      end

      # ========================================
      # SIMDClass code generation
      # ========================================

      # Generate code for SIMDNew - allocate and zero-initialize vector
      def generate_simd_new(inst)
        simd_type = inst.simd_type
        vec_type = get_or_create_simd_vector_type(simd_type)

        # Allocate aligned vector on stack
        vec_alloca = @builder.alloca(vec_type, "simd_#{simd_type.name}")

        # Zero-initialize
        zero = LLVM::Double.from_f(0.0)
        zero_vec = LLVM::ConstantVector.const([zero] * simd_type.llvm_vector_width)
        @builder.store(zero_vec, vec_alloca)

        if inst.result_var
          @variables[inst.result_var] = vec_alloca
          @variable_types[inst.result_var] = :simd_ptr
          @simd_class_type_registry ||= {}
          @simd_class_type_registry[inst.result_var] = simd_type
        end

        vec_alloca
      end

      # Generate code for SIMDFieldGet - extract element from vector
      def generate_simd_field_get(inst)
        simd_type = inst.simd_type
        vec_type = get_or_create_simd_vector_type(simd_type)

        # Get vector pointer
        vec_ptr = get_simd_ptr(inst.object)

        # Load vector
        vec = @builder.load2(vec_type, vec_ptr, "simd_vec")

        # Extract element
        idx = simd_type.field_index(inst.field_name)
        result = @builder.extract_element(vec, LLVM::Int32.from_i(idx), "simd_elem_#{inst.field_name}")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :double
        end

        result
      end

      # Generate code for SIMDFieldSet - insert element into vector
      def generate_simd_field_set(inst)
        simd_type = inst.simd_type
        vec_type = get_or_create_simd_vector_type(simd_type)

        # Get vector pointer
        vec_ptr = get_simd_ptr(inst.object)

        # Load current vector
        vec = @builder.load2(vec_type, vec_ptr, "simd_vec")

        # Get value (convert to double if needed)
        value, value_type = get_value_with_type(inst.value)
        double_val = if value_type == :double
          value
        elsif value_type == :i64
          @builder.si2fp(value, LLVM::Double, "i64_to_double")
        else
          # VALUE -> double
          @builder.call(@rb_num2dbl, ensure_boxed(value, value_type), "value_to_double")
        end

        # Insert element
        idx = simd_type.field_index(inst.field_name)
        new_vec = @builder.insert_element(vec, double_val, LLVM::Int32.from_i(idx), "simd_insert_#{inst.field_name}")

        # Store back
        @builder.store(new_vec, vec_ptr)

        double_val
      end

      # Generate code for SIMDMethodCall - vector arithmetic operations
      def generate_simd_method_call(inst)
        simd_type = inst.simd_type
        vec_type = get_or_create_simd_vector_type(simd_type)

        # Get receiver vector
        self_ptr = get_simd_ptr(inst.receiver)
        self_vec = @builder.load2(vec_type, self_ptr, "simd_self")

        result = case inst.method_name
        when :add
          other_ptr = get_simd_ptr(inst.args[0])
          other_vec = @builder.load2(vec_type, other_ptr, "simd_other")
          generate_simd_vector_result(@builder.fadd(self_vec, other_vec, "simd_add"), simd_type, inst)

        when :sub
          other_ptr = get_simd_ptr(inst.args[0])
          other_vec = @builder.load2(vec_type, other_ptr, "simd_other")
          generate_simd_vector_result(@builder.fsub(self_vec, other_vec, "simd_sub"), simd_type, inst)

        when :mul
          other_ptr = get_simd_ptr(inst.args[0])
          other_vec = @builder.load2(vec_type, other_ptr, "simd_other")
          generate_simd_vector_result(@builder.fmul(self_vec, other_vec, "simd_mul"), simd_type, inst)

        when :div
          other_ptr = get_simd_ptr(inst.args[0])
          other_vec = @builder.load2(vec_type, other_ptr, "simd_other")
          generate_simd_vector_result(@builder.fdiv(self_vec, other_vec, "simd_div"), simd_type, inst)

        when :scale
          # Scale by scalar: splat scalar to vector, then multiply
          scalar_val, scalar_type = get_value_with_type(inst.args[0])
          double_val = if scalar_type == :double
            scalar_val
          elsif scalar_type == :i64
            @builder.si2fp(scalar_val, LLVM::Double, "i64_to_double")
          else
            @builder.call(@rb_num2dbl, ensure_boxed(scalar_val, scalar_type), "value_to_double")
          end
          splat_vec = create_simd_splat(double_val, simd_type)
          generate_simd_vector_result(@builder.fmul(self_vec, splat_vec, "simd_scale"), simd_type, inst)

        when :dot
          # Dot product: multiply elements, then sum
          other_ptr = get_simd_ptr(inst.args[0])
          other_vec = @builder.load2(vec_type, other_ptr, "simd_other")
          mul_vec = @builder.fmul(self_vec, other_vec, "simd_dot_mul")
          sum = generate_simd_horizontal_sum(mul_vec, simd_type)

          if inst.result_var
            @variables[inst.result_var] = sum
            @variable_types[inst.result_var] = :double
          end
          sum

        when :length, :magnitude
          # Length: sqrt(dot(self, self))
          mul_vec = @builder.fmul(self_vec, self_vec, "simd_len_sq_vec")
          sum = generate_simd_horizontal_sum(mul_vec, simd_type)
          sqrt_func = @mod.functions["llvm.sqrt.f64"] || @mod.functions.add("llvm.sqrt.f64", [LLVM::Double], LLVM::Double)
          result = @builder.call(sqrt_func, sum, "simd_len")

          if inst.result_var
            @variables[inst.result_var] = result
            @variable_types[inst.result_var] = :double
          end
          result

        when :normalize
          # Normalize: self / length
          mul_vec = @builder.fmul(self_vec, self_vec, "simd_len_sq_vec")
          sum = generate_simd_horizontal_sum(mul_vec, simd_type)
          sqrt_func = @mod.functions["llvm.sqrt.f64"] || @mod.functions.add("llvm.sqrt.f64", [LLVM::Double], LLVM::Double)
          len = @builder.call(sqrt_func, sum, "simd_len")
          len_splat = create_simd_splat(len, simd_type)
          generate_simd_vector_result(@builder.fdiv(self_vec, len_splat, "simd_normalize"), simd_type, inst)

        else
          # Unknown method, return nil
          @qnil
        end

        result
      end

      # Get or create LLVM vector type for SIMD class
      def get_or_create_simd_vector_type(simd_type)
        @simd_vector_types ||= {}
        return @simd_vector_types[simd_type.name] if @simd_vector_types[simd_type.name]

        width = simd_type.llvm_vector_width
        vec_type = LLVM::Type.vector(LLVM::Double, width)
        @simd_vector_types[simd_type.name] = vec_type
        vec_type
      end

      # Get SIMD pointer from variable reference
      def get_simd_ptr(ref)
        case ref
        when HIR::LoadLocal, HIR::Instruction
          var_name = ref.result_var || ref.var&.name
          @variables[var_name]
        when String
          @variables[ref]
        else
          ref
        end
      end

      # Store vector result and allocate new SIMD instance if needed
      def generate_simd_vector_result(vec, simd_type, inst)
        vec_type = get_or_create_simd_vector_type(simd_type)
        result_ptr = @builder.alloca(vec_type, "simd_result")
        @builder.store(vec, result_ptr)

        if inst.result_var
          @variables[inst.result_var] = result_ptr
          @variable_types[inst.result_var] = :simd_ptr
          @simd_class_type_registry ||= {}
          @simd_class_type_registry[inst.result_var] = simd_type
        end

        result_ptr
      end

      # Create splat vector (broadcast scalar to all elements)
      def create_simd_splat(scalar, simd_type)
        width = simd_type.llvm_vector_width
        undef_vec = LLVM::Undef(LLVM::Type.vector(LLVM::Double, width))
        # Insert scalar at index 0
        vec0 = @builder.insert_element(undef_vec, scalar, LLVM::Int32.from_i(0), "splat_insert")
        # Shuffle to broadcast to all lanes
        mask = LLVM::ConstantVector.const([LLVM::Int32.from_i(0)] * width)
        @builder.shuffle_vector(vec0, undef_vec, mask, "splat_shuffle")
      end

      # Generate horizontal sum (reduce add) of vector elements
      def generate_simd_horizontal_sum(vec, simd_type)
        # Extract each element and sum them
        sum = @builder.extract_element(vec, LLVM::Int32.from_i(0), "sum_init")
        (1...simd_type.vector_width).each do |i|
          elem = @builder.extract_element(vec, LLVM::Int32.from_i(i), "elem_#{i}")
          sum = @builder.fadd(sum, elem, "sum_#{i}")
        end
        sum
      end

      # Get or create an LLVM function for a NativeClass method
      # Native method signature: return_type method(Self* self, param1, param2, ...)
      # For value types: return_type method(Self self, param1, param2, ...) - pass by value
      def get_or_create_native_method_func(owner_class, method_name, method_sig)
        @native_method_funcs ||= {}
        is_value_type = is_value_type_class?(owner_class)
        sanitized_owner = owner_class.name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
        sanitized_method = sanitize_c_name(method_name.to_s)
        func_name = "rn_#{sanitized_owner}_#{sanitized_method}"

        return @native_method_funcs[func_name] if @native_method_funcs[func_name]

        # Build parameter types: first is self (pointer for ref types, struct for value types)
        struct_type = get_or_create_native_class_struct(owner_class)
        param_types = if is_value_type
          [struct_type]  # Value type: pass struct by value (LLVM handles register passing)
        else
          [LLVM::Pointer(struct_type)]  # Reference type: pass pointer
        end

        method_sig.param_types.each do |param_type|
          llvm_type = case param_type
          when :Int64 then LLVM::Int64
          when :Float64 then LLVM::Double
          else
            # Another NativeClass - check if it's a value type
            other_class = @native_class_type_registry[param_type]
            if other_class && is_value_type_class?(other_class)
              get_or_create_native_class_struct(other_class)  # Pass value type by value
            else
              LLVM::Pointer(LLVM::Int8)  # Pass reference type by pointer
            end
          end
          param_types << llvm_type
        end

        # Return type - return struct by value for :Self to avoid use-after-free
        return_type = case method_sig.return_type
        when :Int64 then LLVM::Int64
        when :Float64 then LLVM::Double
        when :Void then LLVM.Void
        when :Self then struct_type  # Return struct by value, not pointer
        else
          # Another NativeClass - return struct by value
          other_struct = get_or_create_native_class_struct(
            @native_class_type_registry[method_sig.return_type] || owner_class
          )
          other_struct
        end

        func = @mod.functions.add(func_name, param_types, return_type)
        @native_method_funcs[func_name] = func

        func
      end

      # Helper: Get or create LLVM struct type for NativeClass
      def get_or_create_native_class_struct(class_type)
        @native_class_structs ||= {}

        return @native_class_structs[class_type.name] if @native_class_structs[class_type.name]

        # Build struct with field types
        field_types = []

        # For vtable classes, add vptr as first field (pointer to vtable)
        uses_vtable = class_type.uses_vtable?(@native_class_type_registry)
        if uses_vtable
          field_types << LLVM::Pointer(LLVM::Int8)  # vptr
        end

        # Add regular fields
        class_type.fields.each_value do |field_type|
          llvm_type = case field_type
          when :Int64 then LLVM::Int64
          when :Float64 then LLVM::Double
          when :Bool then LLVM::Int8
          when :String, :Object, :Array, :Hash then value_type  # VALUE (i64) for GC-managed objects
          else
            # Could be an embedded NativeClass
            if field_type.is_a?(Symbol)
              embedded_class = @native_class_type_registry[field_type]
              if embedded_class
                # Recursively get/create the embedded struct type
                get_or_create_native_class_struct(embedded_class)
              else
                # Unknown type, use pointer
                ptr_type
              end
            else
              ptr_type
            end
          end
          field_types << llvm_type
        end

        struct_type = LLVM::Type.struct(field_types, false, "Native_#{class_type.name}")
        @native_class_structs[class_type.name] = struct_type
        struct_type
      end

      # Check if a class uses vtable (for field index adjustment)
      def class_uses_vtable?(class_type)
        class_type.uses_vtable?(@native_class_type_registry)
      end

      # Check if a class is a value type (@struct annotation)
      def is_value_type_class?(class_type)
        class_type.respond_to?(:is_value_type?) && class_type.is_value_type?
      end

      # Check if a variable holds a value struct
      def is_value_struct_var?(var_name)
        @variable_types[var_name] == :value_struct
      end

      # Get field index adjusted for vtable (if class uses vtable, add 1 for vptr)
      def adjusted_field_index(class_type, field_name)
        base_index = class_type.field_index(field_name)
        return nil unless base_index

        if class_uses_vtable?(class_type)
          base_index + 1  # Skip vptr field
        else
          base_index
        end
      end

      # Helper: Get pointer to NativeClass instance
      # For variables that have allocas (loop-safe), load from alloca
      def get_native_class_ptr(hir_value)
        if hir_value.is_a?(HIR::LoadLocal)
          var_name = hir_value.var.name

          # Check if we have an alloca for this variable (needed for loop safety)
          alloca = @variable_allocas[var_name]
          if alloca && @variable_types[var_name] == :native_class
            # Load from alloca to get proper phi-merged value after loops
            @builder.load2(ptr_type, alloca, "#{var_name}_ptr")
          else
            @variables[var_name]
          end
        elsif hir_value.result_var
          @variables[hir_value.result_var]
        else
          raise "Cannot get NativeClass pointer from: #{hir_value.class}"
        end
      end

      # Profiling helper methods

      # Get the display name for the current function being generated
      def format_function_display_name(hir_func)
        if hir_func.owner_class
          "#{hir_func.owner_class}##{hir_func.name}"
        elsif hir_func.owner_module
          "#{hir_func.owner_module}.#{hir_func.name}"
        else
          hir_func.name.to_s
        end
      end

      # ========================================
      # NativeHash code generation
      # Robin Hood hashing with open addressing
      # ========================================

      # Default initial capacity for NativeHash
      NATIVE_HASH_DEFAULT_CAPACITY = 16
      NATIVE_HASH_LOAD_FACTOR = 0.75

      # Entry states
      HASH_ENTRY_EMPTY = 0
      HASH_ENTRY_OCCUPIED = 1
      HASH_ENTRY_TOMBSTONE = 2

      # Get or create NativeHash struct type: { buckets_ptr, size, capacity }
      def get_native_hash_struct(key_type, value_type)
        key_str = key_type.to_s
        val_str = value_type.is_a?(TypeChecker::Types::NativeClassType) ? value_type.name.to_s : value_type.to_s
        struct_name = "NativeHash_#{key_str}_#{val_str}"
        @native_hash_structs ||= {}
        @native_hash_structs[struct_name] ||= LLVM::Struct(
          LLVM::Pointer(LLVM::Int8),  # buckets pointer (opaque)
          LLVM::Int64,                 # size (number of elements)
          LLVM::Int64,                 # capacity (number of buckets)
          struct_name
        )
      end

      # Get or create NativeHash entry struct: { hash_value, key, value, state }
      def get_native_hash_entry_struct(key_type, value_type)
        key_str = key_type.to_s
        val_str = value_type.is_a?(TypeChecker::Types::NativeClassType) ? value_type.name.to_s : value_type.to_s
        struct_name = "NativeHashEntry_#{key_str}_#{val_str}"
        @native_hash_entry_structs ||= {}
        @native_hash_entry_structs[struct_name] ||= begin
          key_llvm = native_hash_key_llvm_type(key_type)
          value_llvm = native_hash_value_llvm_type(value_type)
          LLVM::Struct(
            LLVM::Int64,   # hash value
            key_llvm,      # key
            value_llvm,    # value
            LLVM::Int8,    # state (0=empty, 1=occupied, 2=tombstone)
            struct_name
          )
        end
      end

      # Get LLVM type for hash key
      def native_hash_key_llvm_type(key_type)
        case key_type
        when :String then LLVM::Int64  # Ruby VALUE
        when :Symbol then LLVM::Int64  # Ruby VALUE (symbol ID)
        when :Integer then LLVM::Int64 # Unboxed integer
        else LLVM::Int64
        end
      end

      # Get LLVM type for hash value
      def native_hash_value_llvm_type(value_type)
        case value_type
        when :Integer then LLVM::Int64
        when :Float then LLVM::Double
        when :Bool then LLVM::Int8
        when :String, :Object, :Array, :Hash then LLVM::Int64  # Ruby VALUE
        else
          # NativeClass - use pointer to struct
          if value_type.is_a?(TypeChecker::Types::NativeClassType)
            LLVM::Pointer(get_or_create_native_class_struct(value_type))
          else
            LLVM::Int64
          end
        end
      end

      # Allocate a new NativeHash
      def generate_native_hash_alloc(inst)
        declare_malloc
        declare_memset

        key_type = inst.key_type
        value_type = inst.value_type
        hash_struct = get_native_hash_struct(key_type, value_type)
        entry_struct = get_native_hash_entry_struct(key_type, value_type)

        # Get capacity
        capacity = if inst.capacity
          cap_val, cap_type = get_value_with_type(inst.capacity)
          cap_type == :i64 ? cap_val : @builder.call(@rb_num2long, cap_val)
        else
          LLVM::Int64.from_i(NATIVE_HASH_DEFAULT_CAPACITY)
        end

        # Calculate bucket array size
        entry_size = LLVM::Int64.from_i(32)  # Each entry is 32 bytes (aligned)
        bucket_bytes = @builder.mul(capacity, entry_size, "bucket_bytes")

        # Allocate bucket array
        buckets_ptr = @builder.call(@malloc, bucket_bytes, "buckets")

        # Zero-initialize buckets (sets all states to EMPTY)
        @builder.call(@memset, buckets_ptr, LLVM::Int32.from_i(0), bucket_bytes)

        # Allocate hash struct on stack
        hash_ptr = @builder.alloca(hash_struct, "native_hash")

        # Store buckets pointer
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        @builder.store(buckets_ptr, buckets_field)

        # Store size (0)
        size_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        @builder.store(LLVM::Int64.from_i(0), size_field)

        # Store capacity
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field")
        @builder.store(capacity, cap_field)

        if inst.result_var
          @variables[inst.result_var] = hash_ptr
          @variable_types[inst.result_var] = :native_hash
          @native_hash_types ||= {}
          @native_hash_types[inst.result_var] = { key_type: key_type, value_type: value_type }
        end

        hash_ptr
      end

      # Generate hash function for key
      def generate_hash_key(key_value, key_type)
        declare_rb_str_hash if key_type == :String

        case key_type
        when :String
          # Use Ruby's string hash
          @rb_str_hash ||= @mod.functions["rb_str_hash"] || @mod.functions.add("rb_str_hash", [LLVM::Int64], LLVM::Int64)
          @builder.call(@rb_str_hash, key_value, "str_hash")
        when :Symbol
          # Symbol ID is already a good hash
          key_value
        when :Integer
          # FNV-1a style hash for integers
          # hash = (key ^ 0x811c9dc5) * 0x01000193
          xor_val = @builder.xor(key_value, LLVM::Int64.from_i(0x811c9dc5), "xor")
          @builder.mul(xor_val, LLVM::Int64.from_i(0x01000193), "int_hash")
        else
          key_value
        end
      end

      # Declare rb_str_hash if needed
      def declare_rb_str_hash
        @rb_str_hash ||= @mod.functions["rb_str_hash"] || @mod.functions.add("rb_str_hash", [LLVM::Int64], LLVM::Int64)
      end

      # Generate key comparison
      def generate_key_equals(key1, key2, key_type)
        declare_rb_str_equal if key_type == :String

        case key_type
        when :String
          @rb_str_equal ||= @mod.functions["rb_str_equal"] || @mod.functions.add("rb_str_equal", [LLVM::Int64, LLVM::Int64], LLVM::Int64)
          eq_result = @builder.call(@rb_str_equal, key1, key2, "str_eq")
          # rb_str_equal returns Qtrue/Qfalse, compare with Qtrue
          @builder.icmp(:eq, eq_result, @qtrue, "key_eq")
        when :Symbol, :Integer
          @builder.icmp(:eq, key1, key2, "key_eq")
        else
          @builder.icmp(:eq, key1, key2, "key_eq")
        end
      end

      # Declare rb_str_equal if needed
      def declare_rb_str_equal
        @rb_str_equal ||= @mod.functions["rb_str_equal"] || @mod.functions.add("rb_str_equal", [LLVM::Int64, LLVM::Int64], LLVM::Int64)
      end

      # Get value from NativeHash with linear probing
      def generate_native_hash_get(inst)
        key_type = inst.key_type
        value_type = inst.value_type
        hash_struct = get_native_hash_struct(key_type, value_type)
        entry_struct = get_native_hash_entry_struct(key_type, value_type)
        key_llvm = native_hash_key_llvm_type(key_type)
        value_llvm = native_hash_value_llvm_type(value_type)

        hash_ptr = get_value(inst.hash_var)
        key_value, key_llvm_type = get_value_with_type(inst.key)

        # Convert key to appropriate type if needed
        key_val = if key_type == :Integer && key_llvm_type != :i64
          @builder.call(@rb_num2long, key_value)
        else
          key_value
        end

        # Calculate hash
        hash_val = generate_hash_key(key_val, key_type)

        # Get capacity
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field")
        capacity = @builder.load2(LLVM::Int64, cap_field, "capacity")

        # Get buckets pointer
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        buckets_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), buckets_field, "buckets")
        buckets_typed = @builder.bit_cast(buckets_ptr, LLVM::Pointer(entry_struct), "buckets_typed")

        # Calculate initial index: hash % capacity
        initial_idx = @builder.urem(hash_val, capacity, "initial_idx")

        # Create basic blocks for probing loop
        current_func = @builder.insert_block.parent
        probe_bb = current_func.basic_blocks.append("hash_get_probe")
        check_key_bb = current_func.basic_blocks.append("hash_get_check_key")
        found_bb = current_func.basic_blocks.append("hash_get_found")
        next_slot_bb = current_func.basic_blocks.append("hash_get_next")
        not_found_bb = current_func.basic_blocks.append("hash_get_not_found")
        done_bb = current_func.basic_blocks.append("hash_get_done")

        # Allocate probe index
        idx_alloca = @builder.alloca(LLVM::Int64, "probe_idx")
        @builder.store(initial_idx, idx_alloca)

        # Allocate result
        result_alloca = @builder.alloca(value_llvm, "result")
        default_val = case value_type
                      when :Integer then LLVM::Int64.from_i(0)
                      when :Float then LLVM::Double.from_f(0.0)
                      when :Bool then LLVM::Int8.from_i(0)
                      else @qnil
                      end
        @builder.store(default_val, result_alloca)

        @builder.br(probe_bb)

        # Probe loop
        @builder.position_at_end(probe_bb)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "current_idx")

        # Get entry at current index
        entry_ptr = @builder.gep2(entry_struct, buckets_typed, [current_idx], "entry_ptr")

        # Load state
        state_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "state_ptr")
        state = @builder.load2(LLVM::Int8, state_ptr, "state")

        # Check if empty -> not found
        is_empty = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_EMPTY), "is_empty")
        @builder.cond(is_empty, not_found_bb, check_key_bb)

        # Check if occupied and key matches
        @builder.position_at_end(check_key_bb)
        is_occupied = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), "is_occupied")
        @builder.cond(is_occupied, found_bb, next_slot_bb)

        # Found - check if key matches
        @builder.position_at_end(found_bb)
        stored_key_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "stored_key_ptr")
        stored_key = @builder.load2(key_llvm, stored_key_ptr, "stored_key")

        key_matches = generate_key_equals(key_val, stored_key, key_type)

        # Create block for matched key
        matched_bb = current_func.basic_blocks.append("hash_get_matched")

        @builder.cond(key_matches, matched_bb, next_slot_bb)

        # Key matched - load value
        @builder.position_at_end(matched_bb)
        value_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "value_ptr")
        found_value = @builder.load2(value_llvm, value_ptr, "found_value")
        @builder.store(found_value, result_alloca)
        @builder.br(done_bb)

        # Next slot
        @builder.position_at_end(next_slot_bb)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1), "next_idx")
        wrapped_idx = @builder.urem(next_idx, capacity, "wrapped_idx")
        @builder.store(wrapped_idx, idx_alloca)

        # Check if we've wrapped around
        wrapped_around = @builder.icmp(:eq, wrapped_idx, initial_idx, "wrapped_around")
        @builder.cond(wrapped_around, not_found_bb, probe_bb)

        # Not found
        @builder.position_at_end(not_found_bb)
        @builder.br(done_bb)

        # Done - load result
        @builder.position_at_end(done_bb)
        result = @builder.load2(value_llvm, result_alloca, "result")

        result_type = case value_type
                      when :Integer then :i64
                      when :Float then :double
                      when :Bool then :i8
                      else :value
                      end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = result_type
        end

        result
      end

      # Set value in NativeHash with linear probing
      # Includes automatic resizing when load factor exceeds 0.75
      def generate_native_hash_set(inst)
        declare_malloc
        declare_memset
        declare_free

        key_type = inst.key_type
        value_type = inst.value_type
        hash_struct = get_native_hash_struct(key_type, value_type)
        entry_struct = get_native_hash_entry_struct(key_type, value_type)
        key_llvm = native_hash_key_llvm_type(key_type)
        value_llvm = native_hash_value_llvm_type(value_type)

        hash_ptr = get_value(inst.hash_var)
        key_value, key_llvm_type = get_value_with_type(inst.key)
        set_value, set_value_type = get_value_with_type(inst.value)

        # Convert key to appropriate type if needed
        key_val = if key_type == :Integer && key_llvm_type != :i64
          @builder.call(@rb_num2long, key_value)
        else
          key_value
        end

        # Convert value to appropriate type if needed
        val_to_store = case value_type
                       when :Integer
                         set_value_type == :i64 ? set_value : @builder.call(@rb_num2long, set_value)
                       when :Float
                         set_value_type == :double ? set_value : @builder.call(@rb_float_value, set_value)
                       else
                         set_value
                       end

        # Calculate hash for the key (do this early as we need it for resize too)
        hash_val = generate_hash_key(key_val, key_type)

        current_func = @builder.insert_block.parent

        # === Load factor check and resize ===
        # Check if (size + 1) * 4 > capacity * 3 (i.e., load factor > 0.75 after insert)
        size_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field_check")
        current_size = @builder.load2(LLVM::Int64, size_field, "current_size_check")
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field_check")
        current_cap = @builder.load2(LLVM::Int64, cap_field, "current_cap_check")

        # (size + 1) * 4
        size_plus_1 = @builder.add(current_size, LLVM::Int64.from_i(1), "size_plus_1")
        size_scaled = @builder.mul(size_plus_1, LLVM::Int64.from_i(4), "size_scaled")
        # capacity * 3
        cap_scaled = @builder.mul(current_cap, LLVM::Int64.from_i(3), "cap_scaled")

        needs_resize = @builder.icmp(:ugt, size_scaled, cap_scaled, "needs_resize")

        resize_bb = current_func.basic_blocks.append("hash_resize")
        after_resize_bb = current_func.basic_blocks.append("hash_after_resize")
        @builder.cond(needs_resize, resize_bb, after_resize_bb)

        # === Resize block ===
        @builder.position_at_end(resize_bb)

        # Double the capacity
        new_cap = @builder.mul(current_cap, LLVM::Int64.from_i(2), "new_cap")

        # Allocate new bucket array
        entry_size = LLVM::Int64.from_i(32)  # Each entry is 32 bytes (aligned)
        new_bucket_bytes = @builder.mul(new_cap, entry_size, "new_bucket_bytes")
        new_buckets = @builder.call(@malloc, new_bucket_bytes, "new_buckets")

        # Zero-initialize new buckets
        @builder.call(@memset, new_buckets, LLVM::Int32.from_i(0), new_bucket_bytes)

        # Get old buckets
        old_buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "old_buckets_field")
        old_buckets = @builder.load2(LLVM::Pointer(LLVM::Int8), old_buckets_field, "old_buckets")
        old_buckets_typed = @builder.bit_cast(old_buckets, LLVM::Pointer(entry_struct), "old_buckets_typed")
        new_buckets_typed = @builder.bit_cast(new_buckets, LLVM::Pointer(entry_struct), "new_buckets_typed")

        # Rehash all entries from old to new
        rehash_idx_alloca = @builder.alloca(LLVM::Int64, "rehash_idx")
        @builder.store(LLVM::Int64.from_i(0), rehash_idx_alloca)

        rehash_loop_bb = current_func.basic_blocks.append("rehash_loop")
        rehash_check_bb = current_func.basic_blocks.append("rehash_check")
        rehash_copy_bb = current_func.basic_blocks.append("rehash_copy")
        rehash_insert_loop_bb = current_func.basic_blocks.append("rehash_insert_loop")
        rehash_insert_bb = current_func.basic_blocks.append("rehash_insert")
        rehash_next_slot_bb = current_func.basic_blocks.append("rehash_next_slot")
        rehash_next_bb = current_func.basic_blocks.append("rehash_next")
        rehash_done_bb = current_func.basic_blocks.append("rehash_done")

        @builder.br(rehash_loop_bb)

        # Rehash loop - iterate through all old buckets
        @builder.position_at_end(rehash_loop_bb)
        rehash_idx = @builder.load2(LLVM::Int64, rehash_idx_alloca, "rehash_idx")
        rehash_done_cond = @builder.icmp(:uge, rehash_idx, current_cap, "rehash_done_cond")
        @builder.cond(rehash_done_cond, rehash_done_bb, rehash_check_bb)

        # Check if entry is occupied
        @builder.position_at_end(rehash_check_bb)
        old_entry = @builder.gep2(entry_struct, old_buckets_typed, [rehash_idx], "old_entry")
        old_state_ptr = @builder.gep2(entry_struct, old_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "old_state_ptr")
        old_state = @builder.load2(LLVM::Int8, old_state_ptr, "old_state")
        is_occupied = @builder.icmp(:eq, old_state, LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), "is_occupied")
        @builder.cond(is_occupied, rehash_copy_bb, rehash_next_bb)

        # Copy entry to new location
        @builder.position_at_end(rehash_copy_bb)

        # Load old entry data
        old_hash_ptr = @builder.gep2(entry_struct, old_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "old_hash_ptr")
        old_hash = @builder.load2(LLVM::Int64, old_hash_ptr, "old_hash")
        old_key_ptr = @builder.gep2(entry_struct, old_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "old_key_ptr")
        old_key = @builder.load2(key_llvm, old_key_ptr, "old_key")
        old_val_ptr = @builder.gep2(entry_struct, old_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "old_val_ptr")
        old_val = @builder.load2(value_llvm, old_val_ptr, "old_val")

        # Calculate new index
        new_idx_alloca = @builder.alloca(LLVM::Int64, "new_idx_alloca")
        new_initial_idx = @builder.urem(old_hash, new_cap, "new_initial_idx")
        @builder.store(new_initial_idx, new_idx_alloca)
        @builder.br(rehash_insert_loop_bb)

        # Linear probe to find empty slot in new array
        @builder.position_at_end(rehash_insert_loop_bb)
        new_idx = @builder.load2(LLVM::Int64, new_idx_alloca, "new_idx")
        new_entry = @builder.gep2(entry_struct, new_buckets_typed, [new_idx], "new_entry")
        new_state_ptr = @builder.gep2(entry_struct, new_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "new_state_ptr")
        new_state = @builder.load2(LLVM::Int8, new_state_ptr, "new_state")
        new_is_empty = @builder.icmp(:eq, new_state, LLVM::Int8.from_i(HASH_ENTRY_EMPTY), "new_is_empty")
        @builder.cond(new_is_empty, rehash_insert_bb, rehash_next_slot_bb)

        # Insert into new slot
        @builder.position_at_end(rehash_insert_bb)
        new_hash_ptr = @builder.gep2(entry_struct, new_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "new_hash_ptr")
        @builder.store(old_hash, new_hash_ptr)
        new_key_ptr = @builder.gep2(entry_struct, new_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "new_key_ptr")
        @builder.store(old_key, new_key_ptr)
        new_val_ptr = @builder.gep2(entry_struct, new_entry, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "new_val_ptr")
        @builder.store(old_val, new_val_ptr)
        @builder.store(LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), new_state_ptr)
        @builder.br(rehash_next_bb)

        # Try next slot in new array
        @builder.position_at_end(rehash_next_slot_bb)
        next_new_idx = @builder.add(new_idx, LLVM::Int64.from_i(1), "next_new_idx")
        wrapped_new_idx = @builder.urem(next_new_idx, new_cap, "wrapped_new_idx")
        @builder.store(wrapped_new_idx, new_idx_alloca)
        @builder.br(rehash_insert_loop_bb)

        # Move to next old entry
        @builder.position_at_end(rehash_next_bb)
        next_rehash_idx = @builder.add(rehash_idx, LLVM::Int64.from_i(1), "next_rehash_idx")
        @builder.store(next_rehash_idx, rehash_idx_alloca)
        @builder.br(rehash_loop_bb)

        # Done rehashing
        @builder.position_at_end(rehash_done_bb)

        # Free old buckets
        @builder.call(@free, old_buckets)

        # Update hash struct with new buckets and capacity
        @builder.store(new_buckets, old_buckets_field)
        @builder.store(new_cap, cap_field)

        @builder.br(after_resize_bb)

        # === After resize - proceed with insertion ===
        @builder.position_at_end(after_resize_bb)

        # Re-load capacity and buckets (may have changed after resize)
        capacity = @builder.load2(LLVM::Int64, cap_field, "capacity")
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        buckets_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), buckets_field, "buckets")
        buckets_typed = @builder.bit_cast(buckets_ptr, LLVM::Pointer(entry_struct), "buckets_typed")

        # Calculate initial index: hash % capacity
        initial_idx = @builder.urem(hash_val, capacity, "initial_idx")

        # Create basic blocks for probing loop
        probe_bb = current_func.basic_blocks.append("hash_set_probe")
        check_occupied_bb = current_func.basic_blocks.append("hash_set_check_occupied")
        check_key_bb = current_func.basic_blocks.append("hash_set_check_key")
        update_bb = current_func.basic_blocks.append("hash_set_update")
        insert_bb = current_func.basic_blocks.append("hash_set_insert")
        next_slot_bb = current_func.basic_blocks.append("hash_set_next")
        done_bb = current_func.basic_blocks.append("hash_set_done")

        # Allocate probe index and count (for safety check)
        idx_alloca = @builder.alloca(LLVM::Int64, "probe_idx")
        @builder.store(initial_idx, idx_alloca)
        probe_count_alloca = @builder.alloca(LLVM::Int64, "probe_count")
        @builder.store(LLVM::Int64.from_i(0), probe_count_alloca)

        # Track if we need to increment size (new insertion vs update)
        is_new_alloca = @builder.alloca(LLVM::Int8, "is_new")
        @builder.store(LLVM::Int8.from_i(1), is_new_alloca)  # Assume new until we find existing key

        # Allocate for entry_ptr to use in insert_bb
        entry_ptr_alloca = @builder.alloca(LLVM::Pointer(entry_struct), "entry_ptr_alloca")

        @builder.br(probe_bb)

        # Probe loop
        @builder.position_at_end(probe_bb)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "current_idx")

        # Safety check: don't probe more than capacity times
        probe_count = @builder.load2(LLVM::Int64, probe_count_alloca, "probe_count")
        too_many_probes = @builder.icmp(:uge, probe_count, capacity, "too_many_probes")
        emergency_bb = current_func.basic_blocks.append("hash_set_emergency")
        continue_probe_bb = current_func.basic_blocks.append("hash_set_continue_probe")
        @builder.cond(too_many_probes, emergency_bb, continue_probe_bb)

        # Emergency: table is full (shouldn't happen with resize, but safety net)
        @builder.position_at_end(emergency_bb)
        @builder.br(done_bb)

        @builder.position_at_end(continue_probe_bb)

        # Get entry at current index
        entry_ptr = @builder.gep2(entry_struct, buckets_typed, [current_idx], "entry_ptr")
        @builder.store(entry_ptr, entry_ptr_alloca)

        # Load state
        state_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "state_ptr")
        state = @builder.load2(LLVM::Int8, state_ptr, "state")

        # Check if empty or tombstone -> insert here
        is_empty = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_EMPTY), "is_empty")
        is_tombstone = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_TOMBSTONE), "is_tombstone")
        can_insert = @builder.or(is_empty, is_tombstone, "can_insert")
        @builder.cond(can_insert, insert_bb, check_occupied_bb)

        # Check if occupied
        @builder.position_at_end(check_occupied_bb)
        is_occupied = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), "is_occupied")
        @builder.cond(is_occupied, check_key_bb, next_slot_bb)

        # Check if key matches
        @builder.position_at_end(check_key_bb)
        stored_key_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "stored_key_ptr")
        stored_key = @builder.load2(key_llvm, stored_key_ptr, "stored_key")
        key_matches = generate_key_equals(key_val, stored_key, key_type)
        @builder.cond(key_matches, update_bb, next_slot_bb)

        # Update existing entry (don't increment size)
        @builder.position_at_end(update_bb)
        @builder.store(LLVM::Int8.from_i(0), is_new_alloca)  # Not new, just update
        @builder.br(insert_bb)

        # Insert/update value at current entry
        @builder.position_at_end(insert_bb)
        entry_ptr_final = @builder.load2(LLVM::Pointer(entry_struct), entry_ptr_alloca, "entry_ptr_final")

        # Store hash value
        hash_ptr_field = @builder.gep2(entry_struct, entry_ptr_final, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "hash_field")
        @builder.store(hash_val, hash_ptr_field)

        # Store key
        key_ptr = @builder.gep2(entry_struct, entry_ptr_final, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "key_ptr")
        @builder.store(key_val, key_ptr)

        # Store value
        value_ptr = @builder.gep2(entry_struct, entry_ptr_final, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "value_ptr")
        @builder.store(val_to_store, value_ptr)

        # Set state to occupied
        state_ptr_final = @builder.gep2(entry_struct, entry_ptr_final, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "state_ptr_final")
        @builder.store(LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), state_ptr_final)

        # Increment size only if new insertion
        is_new = @builder.load2(LLVM::Int8, is_new_alloca, "is_new")
        is_new_bool = @builder.icmp(:ne, is_new, LLVM::Int8.from_i(0), "is_new_bool")

        inc_size_bb = current_func.basic_blocks.append("hash_set_inc_size")
        @builder.cond(is_new_bool, inc_size_bb, done_bb)

        @builder.position_at_end(inc_size_bb)
        size_field_inc = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field_inc")
        current_size_inc = @builder.load2(LLVM::Int64, size_field_inc, "current_size_inc")
        new_size = @builder.add(current_size_inc, LLVM::Int64.from_i(1), "new_size")
        @builder.store(new_size, size_field_inc)
        @builder.br(done_bb)

        # Next slot
        @builder.position_at_end(next_slot_bb)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1), "next_idx")
        wrapped_idx = @builder.urem(next_idx, capacity, "wrapped_idx")
        @builder.store(wrapped_idx, idx_alloca)
        # Increment probe count
        new_probe_count = @builder.add(probe_count, LLVM::Int64.from_i(1), "new_probe_count")
        @builder.store(new_probe_count, probe_count_alloca)
        @builder.br(probe_bb)

        # Done
        @builder.position_at_end(done_bb)

        if inst.result_var
          @variables[inst.result_var] = set_value
          @variable_types[inst.result_var] = set_value_type
        end

        set_value
      end

      # Declare free function
      def declare_free
        @free ||= @mod.functions["free"] || @mod.functions.add("free", [LLVM::Pointer(LLVM::Int8)], LLVM.Void)
      end

      # Get size of NativeHash
      def generate_native_hash_size(inst)
        hash_ptr = get_value(inst.hash_var)
        hash_info = @native_hash_types&.dig(inst.hash_var.to_s) || { key_type: :String, value_type: :Integer }
        hash_struct = get_native_hash_struct(hash_info[:key_type], hash_info[:value_type])

        size_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        size_val = @builder.load2(LLVM::Int64, size_field, "size")

        if inst.result_var
          @variables[inst.result_var] = size_val
          @variable_types[inst.result_var] = :i64
        end

        size_val
      end

      # Check if key exists in NativeHash with linear probing
      def generate_native_hash_has_key(inst)
        key_type = inst.key_type
        hash_info = @native_hash_types&.dig(get_source_var_name(inst.hash_var)) || { key_type: key_type, value_type: :Integer }
        value_type = hash_info[:value_type] || :Integer
        hash_struct = get_native_hash_struct(key_type, value_type)
        entry_struct = get_native_hash_entry_struct(key_type, value_type)
        key_llvm = native_hash_key_llvm_type(key_type)

        hash_ptr = get_value(inst.hash_var)
        key_value, key_llvm_type = get_value_with_type(inst.key)

        # Convert key to appropriate type if needed
        key_val = if key_type == :Integer && key_llvm_type != :i64
          @builder.call(@rb_num2long, key_value)
        else
          key_value
        end

        # Calculate hash
        hash_val = generate_hash_key(key_val, key_type)

        # Get capacity
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field")
        capacity = @builder.load2(LLVM::Int64, cap_field, "capacity")

        # Get buckets pointer
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        buckets_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), buckets_field, "buckets")
        buckets_typed = @builder.bit_cast(buckets_ptr, LLVM::Pointer(entry_struct), "buckets_typed")

        # Calculate initial index
        initial_idx = @builder.urem(hash_val, capacity, "initial_idx")

        # Create basic blocks
        current_func = @builder.insert_block.parent
        probe_bb = current_func.basic_blocks.append("has_key_probe")
        check_key_bb = current_func.basic_blocks.append("has_key_check")
        found_bb = current_func.basic_blocks.append("has_key_found")
        next_slot_bb = current_func.basic_blocks.append("has_key_next")
        not_found_bb = current_func.basic_blocks.append("has_key_not_found")
        done_bb = current_func.basic_blocks.append("has_key_done")

        # Allocate probe index and result
        idx_alloca = @builder.alloca(LLVM::Int64, "probe_idx")
        @builder.store(initial_idx, idx_alloca)
        result_alloca = @builder.alloca(LLVM::Int8, "result")
        @builder.store(LLVM::Int8.from_i(0), result_alloca)

        @builder.br(probe_bb)

        # Probe loop
        @builder.position_at_end(probe_bb)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "current_idx")
        entry_ptr = @builder.gep2(entry_struct, buckets_typed, [current_idx], "entry_ptr")
        state_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "state_ptr")
        state = @builder.load2(LLVM::Int8, state_ptr, "state")

        is_empty = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_EMPTY), "is_empty")
        @builder.cond(is_empty, not_found_bb, check_key_bb)

        # Check if occupied and key matches
        @builder.position_at_end(check_key_bb)
        is_occupied = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), "is_occupied")
        @builder.cond(is_occupied, found_bb, next_slot_bb)

        @builder.position_at_end(found_bb)
        stored_key_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "stored_key_ptr")
        stored_key = @builder.load2(key_llvm, stored_key_ptr, "stored_key")
        key_matches = generate_key_equals(key_val, stored_key, key_type)

        matched_bb = current_func.basic_blocks.append("has_key_matched")
        @builder.cond(key_matches, matched_bb, next_slot_bb)

        @builder.position_at_end(matched_bb)
        @builder.store(LLVM::Int8.from_i(1), result_alloca)
        @builder.br(done_bb)

        # Next slot
        @builder.position_at_end(next_slot_bb)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1), "next_idx")
        wrapped_idx = @builder.urem(next_idx, capacity, "wrapped_idx")
        @builder.store(wrapped_idx, idx_alloca)
        wrapped_around = @builder.icmp(:eq, wrapped_idx, initial_idx, "wrapped_around")
        @builder.cond(wrapped_around, not_found_bb, probe_bb)

        @builder.position_at_end(not_found_bb)
        @builder.br(done_bb)

        @builder.position_at_end(done_bb)
        result = @builder.load2(LLVM::Int8, result_alloca, "result")

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = :i8
        end

        result
      end

      # Delete key from NativeHash with linear probing
      def generate_native_hash_delete(inst)
        key_type = inst.key_type
        value_type = inst.value_type
        hash_struct = get_native_hash_struct(key_type, value_type)
        entry_struct = get_native_hash_entry_struct(key_type, value_type)
        key_llvm = native_hash_key_llvm_type(key_type)
        value_llvm = native_hash_value_llvm_type(value_type)

        hash_ptr = get_value(inst.hash_var)
        key_value, key_llvm_type = get_value_with_type(inst.key)

        # Convert key to appropriate type if needed
        key_val = if key_type == :Integer && key_llvm_type != :i64
          @builder.call(@rb_num2long, key_value)
        else
          key_value
        end

        # Calculate hash
        hash_val = generate_hash_key(key_val, key_type)

        # Get capacity
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field")
        capacity = @builder.load2(LLVM::Int64, cap_field, "capacity")

        # Get buckets pointer
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        buckets_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), buckets_field, "buckets")
        buckets_typed = @builder.bit_cast(buckets_ptr, LLVM::Pointer(entry_struct), "buckets_typed")

        # Calculate initial index
        initial_idx = @builder.urem(hash_val, capacity, "initial_idx")

        # Create basic blocks
        current_func = @builder.insert_block.parent
        probe_bb = current_func.basic_blocks.append("delete_probe")
        check_key_bb = current_func.basic_blocks.append("delete_check")
        found_bb = current_func.basic_blocks.append("delete_found")
        do_delete_bb = current_func.basic_blocks.append("delete_do")
        next_slot_bb = current_func.basic_blocks.append("delete_next")
        not_found_bb = current_func.basic_blocks.append("delete_not_found")
        done_bb = current_func.basic_blocks.append("delete_done")

        # Allocate probe index and result
        idx_alloca = @builder.alloca(LLVM::Int64, "probe_idx")
        @builder.store(initial_idx, idx_alloca)
        result_alloca = @builder.alloca(value_llvm, "result")
        default_val = case value_type
                      when :Integer then LLVM::Int64.from_i(0)
                      when :Float then LLVM::Double.from_f(0.0)
                      when :Bool then LLVM::Int8.from_i(0)
                      else @qnil
                      end
        @builder.store(default_val, result_alloca)

        @builder.br(probe_bb)

        # Probe loop
        @builder.position_at_end(probe_bb)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "current_idx")
        entry_ptr = @builder.gep2(entry_struct, buckets_typed, [current_idx], "entry_ptr")
        state_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "state_ptr")
        state = @builder.load2(LLVM::Int8, state_ptr, "state")

        is_empty = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_EMPTY), "is_empty")
        @builder.cond(is_empty, not_found_bb, check_key_bb)

        @builder.position_at_end(check_key_bb)
        is_occupied = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), "is_occupied")
        @builder.cond(is_occupied, found_bb, next_slot_bb)

        @builder.position_at_end(found_bb)
        stored_key_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "stored_key_ptr")
        stored_key = @builder.load2(key_llvm, stored_key_ptr, "stored_key")
        key_matches = generate_key_equals(key_val, stored_key, key_type)
        @builder.cond(key_matches, do_delete_bb, next_slot_bb)

        # Delete entry
        @builder.position_at_end(do_delete_bb)
        # Save value before deleting
        value_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "value_ptr")
        deleted_value = @builder.load2(value_llvm, value_ptr, "deleted_value")
        @builder.store(deleted_value, result_alloca)

        # Set state to tombstone
        @builder.store(LLVM::Int8.from_i(HASH_ENTRY_TOMBSTONE), state_ptr)

        # Decrement size
        size_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        current_size = @builder.load2(LLVM::Int64, size_field, "current_size")
        new_size = @builder.sub(current_size, LLVM::Int64.from_i(1), "new_size")
        @builder.store(new_size, size_field)
        @builder.br(done_bb)

        # Next slot
        @builder.position_at_end(next_slot_bb)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1), "next_idx")
        wrapped_idx = @builder.urem(next_idx, capacity, "wrapped_idx")
        @builder.store(wrapped_idx, idx_alloca)
        wrapped_around = @builder.icmp(:eq, wrapped_idx, initial_idx, "wrapped_around")
        @builder.cond(wrapped_around, not_found_bb, probe_bb)

        @builder.position_at_end(not_found_bb)
        @builder.br(done_bb)

        @builder.position_at_end(done_bb)
        result = @builder.load2(value_llvm, result_alloca, "result")

        result_type = case value_type
                      when :Integer then :i64
                      when :Float then :double
                      when :Bool then :i8
                      else :value
                      end

        if inst.result_var
          @variables[inst.result_var] = result
          @variable_types[inst.result_var] = result_type
        end

        result
      end

      # Clear all entries from NativeHash
      def generate_native_hash_clear(inst)
        declare_memset

        key_type = inst.key_type
        value_type = inst.value_type
        hash_struct = get_native_hash_struct(key_type, value_type)

        hash_ptr = get_value(inst.hash_var)

        # Get capacity
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field")
        capacity = @builder.load2(LLVM::Int64, cap_field, "capacity")

        # Get buckets pointer
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        buckets_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), buckets_field, "buckets")

        # Calculate bucket array size
        entry_size = LLVM::Int64.from_i(32)
        bucket_bytes = @builder.mul(capacity, entry_size, "bucket_bytes")

        # Zero all buckets
        @builder.call(@memset, buckets_ptr, LLVM::Int32.from_i(0), bucket_bytes)

        # Set size to 0
        size_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "size_field")
        @builder.store(LLVM::Int64.from_i(0), size_field)

        if inst.result_var
          @variables[inst.result_var] = hash_ptr
          @variable_types[inst.result_var] = :native_hash
        end

        hash_ptr
      end

      # Get all keys from NativeHash
      def generate_native_hash_keys(inst)
        key_type = inst.key_type
        hash_info = @native_hash_types&.dig(get_source_var_name(inst.hash_var)) || { key_type: key_type, value_type: :Integer }
        value_type = hash_info[:value_type] || :Integer
        hash_struct = get_native_hash_struct(key_type, value_type)
        entry_struct = get_native_hash_entry_struct(key_type, value_type)
        key_llvm = native_hash_key_llvm_type(key_type)

        hash_ptr = get_value(inst.hash_var)

        # Create result array
        result_array = @builder.call(@rb_ary_new, "keys_array")

        # Get capacity
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field")
        capacity = @builder.load2(LLVM::Int64, cap_field, "capacity")

        # Get buckets pointer
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        buckets_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), buckets_field, "buckets")
        buckets_typed = @builder.bit_cast(buckets_ptr, LLVM::Pointer(entry_struct), "buckets_typed")

        # Loop through all buckets
        current_func = @builder.insert_block.parent
        loop_bb = current_func.basic_blocks.append("keys_loop")
        body_bb = current_func.basic_blocks.append("keys_body")
        next_bb = current_func.basic_blocks.append("keys_next")
        done_bb = current_func.basic_blocks.append("keys_done")

        idx_alloca = @builder.alloca(LLVM::Int64, "idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)
        @builder.br(loop_bb)

        @builder.position_at_end(loop_bb)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "current_idx")
        done_cond = @builder.icmp(:uge, current_idx, capacity, "done")
        @builder.cond(done_cond, done_bb, body_bb)

        @builder.position_at_end(body_bb)
        entry_ptr = @builder.gep2(entry_struct, buckets_typed, [current_idx], "entry_ptr")
        state_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "state_ptr")
        state = @builder.load2(LLVM::Int8, state_ptr, "state")

        is_occupied = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), "is_occupied")
        push_bb = current_func.basic_blocks.append("keys_push")
        @builder.cond(is_occupied, push_bb, next_bb)

        @builder.position_at_end(push_bb)
        key_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(1)], "key_ptr")
        key_val = @builder.load2(key_llvm, key_ptr, "key_val")
        # Box key if needed
        boxed_key = case key_type
                    when :Integer then @builder.call(@rb_int2inum, key_val)
                    else key_val  # String/Symbol are already VALUE
                    end
        @builder.call(@rb_ary_push, result_array, boxed_key)
        @builder.br(next_bb)

        @builder.position_at_end(next_bb)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1), "next_idx")
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_bb)

        @builder.position_at_end(done_bb)

        if inst.result_var
          @variables[inst.result_var] = result_array
          @variable_types[inst.result_var] = :value
        end

        result_array
      end

      # Get all values from NativeHash
      def generate_native_hash_values(inst)
        key_type = inst.key_type
        value_type = inst.value_type
        hash_struct = get_native_hash_struct(key_type, value_type)
        entry_struct = get_native_hash_entry_struct(key_type, value_type)
        value_llvm = native_hash_value_llvm_type(value_type)

        hash_ptr = get_value(inst.hash_var)

        # Create result array
        result_array = @builder.call(@rb_ary_new, "values_array")

        # Get capacity
        cap_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "cap_field")
        capacity = @builder.load2(LLVM::Int64, cap_field, "capacity")

        # Get buckets pointer
        buckets_field = @builder.gep2(hash_struct, hash_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(0)], "buckets_field")
        buckets_ptr = @builder.load2(LLVM::Pointer(LLVM::Int8), buckets_field, "buckets")
        buckets_typed = @builder.bit_cast(buckets_ptr, LLVM::Pointer(entry_struct), "buckets_typed")

        # Loop through all buckets
        current_func = @builder.insert_block.parent
        loop_bb = current_func.basic_blocks.append("values_loop")
        body_bb = current_func.basic_blocks.append("values_body")
        next_bb = current_func.basic_blocks.append("values_next")
        done_bb = current_func.basic_blocks.append("values_done")

        idx_alloca = @builder.alloca(LLVM::Int64, "idx")
        @builder.store(LLVM::Int64.from_i(0), idx_alloca)
        @builder.br(loop_bb)

        @builder.position_at_end(loop_bb)
        current_idx = @builder.load2(LLVM::Int64, idx_alloca, "current_idx")
        done_cond = @builder.icmp(:uge, current_idx, capacity, "done")
        @builder.cond(done_cond, done_bb, body_bb)

        @builder.position_at_end(body_bb)
        entry_ptr = @builder.gep2(entry_struct, buckets_typed, [current_idx], "entry_ptr")
        state_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(3)], "state_ptr")
        state = @builder.load2(LLVM::Int8, state_ptr, "state")

        is_occupied = @builder.icmp(:eq, state, LLVM::Int8.from_i(HASH_ENTRY_OCCUPIED), "is_occupied")
        push_bb = current_func.basic_blocks.append("values_push")
        @builder.cond(is_occupied, push_bb, next_bb)

        @builder.position_at_end(push_bb)
        value_ptr = @builder.gep2(entry_struct, entry_ptr, [LLVM::Int32.from_i(0), LLVM::Int32.from_i(2)], "value_ptr")
        val = @builder.load2(value_llvm, value_ptr, "val")
        # Box value if needed
        boxed_val = case value_type
                    when :Integer then @builder.call(@rb_int2inum, val)
                    when :Float then @builder.call(@rb_float_new, val)
                    when :Bool
                      true_bb = current_func.basic_blocks.append("val_true")
                      false_bb = current_func.basic_blocks.append("val_false")
                      join_bb = current_func.basic_blocks.append("val_join")
                      is_true = @builder.icmp(:ne, val, LLVM::Int8.from_i(0), "is_true")
                      @builder.cond(is_true, true_bb, false_bb)
                      @builder.position_at_end(true_bb)
                      @builder.br(join_bb)
                      @builder.position_at_end(false_bb)
                      @builder.br(join_bb)
                      @builder.position_at_end(join_bb)
                      @builder.phi(LLVM::Int64, { true_bb => @qtrue, false_bb => @qfalse })
                    else val  # String/Object are already VALUE
                    end
        @builder.call(@rb_ary_push, result_array, boxed_val)
        @builder.br(next_bb)

        @builder.position_at_end(next_bb)
        next_idx = @builder.add(current_idx, LLVM::Int64.from_i(1), "next_idx")
        @builder.store(next_idx, idx_alloca)
        @builder.br(loop_bb)

        @builder.position_at_end(done_bb)

        if inst.result_var
          @variables[inst.result_var] = result_array
          @variable_types[inst.result_var] = :value
        end

        result_array
      end

      # Iterate over NativeHash entries (each)
      def generate_native_hash_each(inst)
        # For now, return the hash itself
        # Full implementation would need block execution which is complex
        hash_ptr = get_value(inst.hash_var)

        if inst.result_var
          @variables[inst.result_var] = hash_ptr
          @variable_types[inst.result_var] = :native_hash
        end

        hash_ptr
      end

      # Insert profiling entry probe at function start
      def insert_profile_entry_probe(hir_func)
        return unless @profiler
        return if hir_func.name.to_s == "__main__"  # Skip main entry point

        display_name = format_function_display_name(hir_func)
        @profiler.insert_entry_probe(display_name)
      end

      # Insert profiling exit probe before function return
      def insert_profile_exit_probe
        return unless @profiler
        return unless @current_hir_func
        return if @current_hir_func.name.to_s == "__main__"  # Skip main entry point

        display_name = format_function_display_name(@current_hir_func)
        @profiler.insert_exit_probe(display_name)
      end
    end
  end
end
