# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "set"

module Konpeito
  module Codegen
    # Generates CRuby extension (.so/.bundle) from LLVM module
    class CRubyBackend
      attr_reader :llvm_generator, :output_file, :module_name, :rbs_loader, :stdlib_requires, :debug, :profile

      def initialize(llvm_generator, output_file:, module_name: nil, rbs_loader: nil, stdlib_requires: [], runtime_native_extensions: [], debug: false, profile: false, uses_json_parse_as: false)
        @llvm_generator = llvm_generator
        @output_file = output_file
        @module_name = module_name || derive_module_name(output_file)
        @rbs_loader = rbs_loader
        @stdlib_requires = stdlib_requires
        @runtime_native_extensions = runtime_native_extensions
        @debug = debug
        @profile = profile
        @uses_json_parse_as = uses_json_parse_as
      end

      def generate
        ir_file = "#{output_base}.ll"
        obj_file = "#{output_base}.o"
        init_c_file = "#{output_base}_init.c"
        init_obj_file = "#{output_base}_init.o"
        profile_c_file = nil
        profile_obj_file = nil

        begin
          # Write LLVM IR to file
          File.write(ir_file, llvm_generator.to_ir)

          # Generate C wrapper for Init function
          File.write(init_c_file, generate_init_c_code)

          # Compile IR to object file
          compile_ir_to_object(ir_file, obj_file)

          # Compile C init wrapper
          compile_c_to_object(init_c_file, init_obj_file)

          obj_files = [obj_file, init_obj_file]

          # Compile profile runtime if profiling enabled
          if @profile
            profile_c_file = "#{output_base}_profile_runtime.c"
            profile_obj_file = "#{output_base}_profile_runtime.o"

            # Write embedded C runtime
            File.write(profile_c_file, profile_runtime_c_code)
            compile_c_to_object(profile_c_file, profile_obj_file)

            obj_files << profile_obj_file
          end

          # Link all object files to shared library
          link_to_shared_library(obj_files, output_file)
        ensure
          # Cleanup temporary files (keep .ll for debugging)
          # FileUtils.rm_f(ir_file)
          unless @debug
            FileUtils.rm_f(obj_file)
          end
          FileUtils.rm_f(init_c_file)
          FileUtils.rm_f(init_obj_file)
          FileUtils.rm_f(profile_c_file) if profile_c_file
          FileUtils.rm_f(profile_obj_file) if profile_obj_file
        end

        output_file
      end

      private

      def output_base
        output_file.sub(/\.(so|bundle|dll)$/, "")
      end

      def derive_module_name(path)
        File.basename(path).sub(/\.(so|bundle|dll)$/, "").gsub(/[^a-zA-Z0-9_]/, "_")
      end

      def generate_init_c_code
        hir = llvm_generator.hir_program
        lines = []

        lines << "#include <ruby.h>"
        lines << "#include <stddef.h>"
        lines << "#include <string.h>"
        lines << ""

        # Collect NativeClasses from RBS loader
        native_classes = @rbs_loader&.native_classes || {}

        # Sort native classes by dependency order (embedded types first)
        sorted_classes = topological_sort_native_classes(native_classes)

        # Forward declare structs for vtable function signatures
        sorted_classes.each do |class_name|
          lines << "typedef struct Native_#{class_name}_s Native_#{class_name};"
        end
        lines << ""

        # Generate struct definitions and TypedData for NativeClasses
        sorted_classes.each do |class_name|
          class_type = native_classes[class_name]
          lines.concat(generate_native_class_struct_body(class_name, class_type))
        end

        # Declare external native functions from LLVM module (for NativeClass methods)
        native_classes.each do |class_name, class_type|
          class_type.methods.each do |method_name, method_sig|
            lines.concat(generate_native_func_declaration(class_name, class_type, method_name, method_sig))
          end
        end

        # Generate vtables for vtable classes (after function declarations)
        sorted_classes.each do |class_name|
          class_type = native_classes[class_name]
          if class_type.uses_vtable?(native_classes)
            lines.concat(generate_vtable(class_name, class_type, native_classes))
          end
        end

        lines << ""

        # Generate wrapper functions for NativeClass methods
        native_classes.each do |class_name, class_type|
          class_type.methods.each do |method_name, method_sig|
            lines.concat(generate_native_method_wrapper(class_name, class_type, method_name, method_sig))
          end
        end

        # Declare external functions from LLVM module (non-native classes)
        hir.classes.each do |class_def|
          next if native_classes.key?(class_def.name.to_sym)

          (class_def.method_names + class_def.singleton_methods).each do |method_name|
            mangled_name = mangle_method_name(class_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            # Use variadic signature for functions with **kwargs or *args
            if llvm_generator.variadic_functions[mangled_name]
              lines << "extern VALUE #{mangled_name}(int argc, VALUE *argv, VALUE self);"
            else
              arity = func.params.size - 1
              lines << "extern VALUE #{mangled_name}(#{(['VALUE'] * (arity + 1)).join(', ')});"
            end
          end

          # Declare extern for alias-renamed functions
          (llvm_generator.alias_renamed_methods || {}).each do |key, renamed|
            class_name, _method_name = key.split("#", 2)
            next unless class_name == class_def.name.to_s

            owner = class_name.gsub(/[^a-zA-Z0-9_]/, "_")
            sanitized = renamed.gsub(/[^a-zA-Z0-9_]/, "_")
            mangled = "rn_#{owner}_#{sanitized}"
            func = llvm_generator.mod.functions[mangled]
            next unless func

            if llvm_generator.variadic_functions[mangled]
              lines << "extern VALUE #{mangled}(int argc, VALUE *argv, VALUE self);"
            else
              arity = func.params.size - 1
              lines << "extern VALUE #{mangled}(#{(['VALUE'] * (arity + 1)).join(', ')});"
            end
          end
        end

        # Declare external functions from LLVM module (modules)
        hir.modules.each do |module_def|
          (module_def.methods + module_def.singleton_methods).each do |method_name|
            mangled_name = mangle_method_name(module_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            # Use variadic signature for functions with **kwargs or *args
            if llvm_generator.variadic_functions[mangled_name]
              lines << "extern VALUE #{mangled_name}(int argc, VALUE *argv, VALUE self);"
            else
              arity = func.params.size - 1
              lines << "extern VALUE #{mangled_name}(#{(['VALUE'] * (arity + 1)).join(', ')});"
            end
          end
        end

        # Declare top-level functions
        hir.functions.each do |func_def|
          next if func_def.owner_class

          mangled_name = "rn_#{func_def.name}".gsub(/[^a-zA-Z0-9_]/, "_")
          func = llvm_generator.mod.functions[mangled_name]
          next unless func

          # Use variadic signature for functions with **kwargs or *args
          if llvm_generator.variadic_functions[mangled_name]
            lines << "extern VALUE #{mangled_name}(int argc, VALUE *argv, VALUE self);"
          else
            arity = func.params.size - 1
            lines << "extern VALUE #{mangled_name}(#{(['VALUE'] * (arity + 1)).join(', ')});"
          end
        end

        # Declare external C functions used by @cfunc annotations
        cfunc_methods = @rbs_loader&.cfunc_methods || {}
        unless cfunc_methods.empty?
          lines << ""
          lines << "/* External C functions (@cfunc) */"
          declared_cfuncs = Set.new
          cfunc_methods.each_value do |cfunc_type|
            next if declared_cfuncs.include?(cfunc_type.c_func_name)

            declared_cfuncs << cfunc_type.c_func_name
            lines.concat(generate_cfunc_extern_declaration(cfunc_type))
          end
        end

        # Profile runtime function declarations
        if @profile
          lines << "/* Profiling runtime functions */"
          lines << "extern void konpeito_profile_init(int num_functions, const char* output_path);"
          lines << "extern void konpeito_profile_finalize(void);"
          lines << ""
        end

        lines << ""
        lines << "void Init_#{module_name}(void) {"

        # Initialize profiling if enabled
        if @profile
          num_funcs = llvm_generator.profiler&.num_functions || 0
          profile_output = "#{module_name}_profile.json"
          lines << "    /* Initialize profiling */"
          lines << "    konpeito_profile_init(#{num_funcs}, \"#{profile_output}\");"
          lines << ""
        end

        # Load stdlib dependencies first
        unless @stdlib_requires.empty?
          lines << "    /* Load stdlib dependencies */"
          @stdlib_requires.each do |lib_name|
            lines << "    rb_require(\"#{lib_name}\");"
          end
          lines << ""
        end

        # Define modules first (before classes that may include them)
        hir.modules.each do |module_def|
          module_var = "m#{module_def.name}"
          lines << "    VALUE #{module_var} = rb_define_module(\"#{module_def.name}\");"

          # Register instance methods (for include/extend)
          module_def.methods.each do |method_name|
            # Skip @cfunc methods - they are direct C calls, not Ruby methods
            next if @rbs_loader&.cfunc_method?(module_def.name, method_name, singleton: false)

            mangled_name = mangle_method_name(module_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            # Use -1 arity for variadic functions
            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            lines << "    rb_define_method(#{module_var}, \"#{method_name}\", #{mangled_name}, #{arity});"
          end

          # Register singleton methods (def self.method)
          module_def.singleton_methods.each do |method_name|
            # Skip @cfunc methods - they are direct C calls, not Ruby methods
            next if @rbs_loader&.cfunc_method?(module_def.name, method_name, singleton: true)

            mangled_name = mangle_method_name(module_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            # Use -1 arity for variadic functions
            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            lines << "    rb_define_singleton_method(#{module_var}, \"#{method_name}\", #{mangled_name}, #{arity});"
          end

          # Register module constants (e.g., VERSION = "2.0")
          module_def.constants.each do |const_name, value_node|
            c_value = hir_literal_to_c_value(value_node)
            next unless c_value

            lines << "    rb_const_set(#{module_var}, rb_intern(\"#{const_name}\"), #{c_value});"
          end
        end

        # Define NativeClasses with TypedData allocator
        native_classes.each do |class_name, class_type|
          lines.concat(generate_native_class_init(class_name, class_type))
        end

        # Define non-native classes (including @boxed classes)
        # Native-first: Classes without field definitions or marked @boxed
        # use standard VALUE-based class definition
        # Sort classes topologically so superclasses are defined first
        non_native_classes = hir.classes.reject { |cd| native_classes.key?(cd.name.to_sym) }
        sorted_non_native = topological_sort_non_native_classes(non_native_classes)

        sorted_non_native.each do |class_def|
          class_var = "c#{class_def.name}"
          if class_def.reopened
            # Reopened class - get existing class instead of defining new one
            lines << "    VALUE #{class_var} = rb_const_get(rb_cObject, rb_intern(\"#{class_def.name}\"));"
          else
            superclass_expr = resolve_superclass_c_expr(class_def.superclass, non_native_classes)
            lines << "    VALUE #{class_var} = rb_define_class(\"#{class_def.name}\", #{superclass_expr});"
          end

          # Prepend modules (must come before include to maintain proper method resolution order)
          class_def.prepended_modules.each do |module_name|
            module_expr = resolve_module_c_expr(module_name)
            lines << "    rb_prepend_module(#{class_var}, #{module_expr});"
          end

          # Include modules
          class_def.included_modules.each do |module_name|
            module_expr = resolve_module_c_expr(module_name)
            lines << "    rb_include_module(#{class_var}, #{module_expr});"
          end

          # Extend modules (adds module methods as singleton methods on the class)
          class_def.extended_modules.each do |module_name|
            module_expr = resolve_module_c_expr(module_name)
            lines << "    rb_extend_object(#{class_var}, #{module_expr});"
          end

          class_def.method_names.each do |method_name|
            mangled_name = mangle_method_name(class_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            # Use -1 arity for variadic functions
            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            # Method visibility
            define_func = if class_def.private_methods.include?(method_name)
                           "rb_define_private_method"
                         elsif class_def.protected_methods.include?(method_name)
                           "rb_define_protected_method"
                         else
                           "rb_define_method"
                         end
            lines << "    #{define_func}(#{class_var}, \"#{method_name}\", #{mangled_name}, #{arity});"
          end

          # Register singleton methods (class << self / def self.xxx)
          class_def.singleton_methods.each do |method_name|
            # Skip @cfunc methods - they are direct C calls, not Ruby methods
            next if @rbs_loader&.cfunc_method?(class_def.name, method_name, singleton: true)

            mangled_name = mangle_method_name(class_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            lines << "    rb_define_singleton_method(#{class_var}, \"#{method_name}\", #{mangled_name}, #{arity});"
          end

          # Register aliases
          class_def.aliases.each do |new_name, old_name|
            renamed_key = "#{class_def.name}##{old_name}"
            if llvm_generator.alias_renamed_methods&.key?(renamed_key)
              # Method was redefined after alias — point alias to renamed original
              renamed = llvm_generator.alias_renamed_methods[renamed_key]
              owner = class_def.name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
              sanitized = renamed.gsub(/[^a-zA-Z0-9_]/, "_")
              mangled = "rn_#{owner}_#{sanitized}"
              llvm_func = llvm_generator.mod.functions[mangled]
              if llvm_generator.variadic_functions[mangled]
                arity = -1
              elsif llvm_func
                arity = llvm_func.params.size - 1
              else
                arity = 0
              end
              lines << "    rb_define_method(#{class_var}, \"#{new_name}\", #{mangled}, #{arity});"
            else
              lines << "    rb_define_alias(#{class_var}, \"#{new_name}\", \"#{old_name}\");"
            end
          end

          # Register class body constants (e.g., PI = 3, VERSION = "1.0")
          class_def.body_constants.each do |const_name, value_node|
            c_value = hir_literal_to_c_value(value_node)
            next unless c_value

            lines << "    rb_const_set(#{class_var}, rb_intern(\"#{const_name}\"), #{c_value});"
          end

          # Register class body class variables (e.g., @@count = 0)
          class_def.body_class_vars.each do |cvar_name, value_node|
            c_value = hir_literal_to_c_value(value_node)
            next unless c_value

            lines << "    rb_cvar_set(#{class_var}, rb_intern(\"#{cvar_name}\"), #{c_value});"
          end
        end

        # Define top-level methods on Object
        hir.functions.each do |func_def|
          next if func_def.owner_class
          next if func_def.owner_module
          next if func_def.name == "__main__"

          mangled_name = "rn_#{func_def.name}".gsub(/[^a-zA-Z0-9_]/, "_")
          func = llvm_generator.mod.functions[mangled_name]
          next unless func

          # Use -1 arity for variadic functions (**kwargs, *args)
          if llvm_generator.variadic_functions[mangled_name]
            arity = -1
          else
            arity = func.params.size - 1
          end
          lines << "    rb_define_private_method(rb_cObject, \"#{func_def.name}\", #{mangled_name}, #{arity});"
        end

        lines << "}"
        lines << ""

        lines.join("\n")
      end

      # Generate C struct definition body and TypedData for a NativeClass
      # Uses forward-declared struct name (Native_ClassName_s) to allow self-referential types
      def generate_native_class_struct_body(class_name, class_type)
        lines = []
        struct_name = "Native_#{class_name}"
        native_classes = @rbs_loader&.native_classes || {}
        uses_vtable = class_type.uses_vtable?(native_classes)

        # Struct definition with tag (for forward declaration)
        lines << "struct Native_#{class_name}_s {"

        # For vtable classes, add vptr as first field
        if uses_vtable
          lines << "    void **vptr;  /* Pointer to vtable */"
        end

        class_type.fields.each do |field_name, field_type|
          c_type = case field_type
          when :Int64 then "int64_t"
          when :Float64 then "double"
          when :Bool then "int8_t"
          when :String, :Object, :Array, :Hash then "VALUE"
          when Hash
            # Reference to NativeClass - stored as VALUE (can be nil)
            "VALUE"
          else
            # Embedded NativeClass - use the struct type
            if @rbs_loader&.native_class?(field_type)
              "Native_#{field_type}"
            else
              "VALUE"
            end
          end
          lines << "    #{c_type} #{field_name};"
        end
        lines << "};"
        lines << ""

        # GC mark function (if class has Ruby object fields)
        ruby_fields = class_type.ruby_object_field_names(@rbs_loader&.native_classes || {})
        unless ruby_fields.empty?
          lines << "static void #{class_name}_mark(void *ptr) {"
          lines << "    #{struct_name} *obj = (#{struct_name} *)ptr;"
          ruby_fields.each do |field_name|
            lines << "    rb_gc_mark(obj->#{field_name});"
          end
          lines << "}"
          lines << ""
        end

        # TypedData type definition
        ruby_fields = class_type.ruby_object_field_names(@rbs_loader&.native_classes || {})
        dmark_func = ruby_fields.empty? ? "NULL" : "#{class_name}_mark"

        lines << "static const rb_data_type_t #{class_name}_type = {"
        lines << "    .wrap_struct_name = \"#{class_name}\","
        lines << "    .function = {"
        lines << "        .dmark = #{dmark_func},"
        lines << "        .dfree = RUBY_DEFAULT_FREE,"
        lines << "        .dsize = NULL,"
        lines << "    },"
        lines << "    .flags = RUBY_TYPED_FREE_IMMEDIATELY,"
        lines << "};"
        lines << ""

        # Allocator function
        lines << "static VALUE #{class_name}_alloc(VALUE klass) {"
        lines << "    #{struct_name} *ptr;"
        lines << "    VALUE obj = TypedData_Make_Struct(klass, #{struct_name}, &#{class_name}_type, ptr);"

        # Initialize vptr if using vtable
        if uses_vtable
          lines << "    ptr->vptr = vtable_#{class_name};"
        end

        class_type.fields.each do |field_name, field_type|
          case field_type
          when :Int64
            lines << "    ptr->#{field_name} = 0;"
          when :Float64
            lines << "    ptr->#{field_name} = 0.0;"
          when :Bool
            lines << "    ptr->#{field_name} = 0;"
          when :String, :Object, :Array, :Hash
            lines << "    ptr->#{field_name} = Qnil;"
          when ::Hash
            # Reference to NativeClass - initialize to nil
            lines << "    ptr->#{field_name} = Qnil;"
          else
            # Embedded NativeClass - initialize with memset or field-by-field
            if @rbs_loader&.native_class?(field_type)
              lines << "    memset(&ptr->#{field_name}, 0, sizeof(Native_#{field_type}));"
            else
              lines << "    ptr->#{field_name} = Qnil;"
            end
          end
        end
        lines << "    return obj;"
        lines << "}"
        lines << ""

        # Field accessor wrappers (getter)
        class_type.fields.each do |field_name, field_type|
          lines << "static VALUE #{class_name}_get_#{field_name}(VALUE self) {"
          lines << "    #{struct_name} *ptr;"
          lines << "    TypedData_Get_Struct(self, #{struct_name}, &#{class_name}_type, ptr);"
          case field_type
          when :Int64
            lines << "    return rb_int2inum(ptr->#{field_name});"
          when :Float64
            lines << "    return rb_float_new(ptr->#{field_name});"
          when :Bool
            lines << "    return ptr->#{field_name} ? Qtrue : Qfalse;"
          when :String, :Object, :Array, :Hash
            lines << "    return ptr->#{field_name};"
          when ::Hash
            # Reference to NativeClass - return VALUE directly (can be nil)
            lines << "    return ptr->#{field_name};"
          else
            # Embedded NativeClass - return a new Ruby object with a copy
            if @rbs_loader&.native_class?(field_type)
              embedded_struct = "Native_#{field_type}"
              lines << "    VALUE klass = rb_const_get(rb_cObject, rb_intern(\"#{field_type}\"));"
              lines << "    VALUE result = #{field_type}_alloc(klass);"
              lines << "    #{embedded_struct} *result_ptr;"
              lines << "    TypedData_Get_Struct(result, #{embedded_struct}, &#{field_type}_type, result_ptr);"
              lines << "    *result_ptr = ptr->#{field_name};"
              lines << "    return result;"
            else
              lines << "    return ptr->#{field_name};"
            end
          end
          lines << "}"
          lines << ""
        end

        # Field accessor wrappers (setter)
        class_type.fields.each do |field_name, field_type|
          lines << "static VALUE #{class_name}_set_#{field_name}(VALUE self, VALUE val) {"
          lines << "    #{struct_name} *ptr;"
          lines << "    TypedData_Get_Struct(self, #{struct_name}, &#{class_name}_type, ptr);"
          case field_type
          when :Int64
            lines << "    ptr->#{field_name} = NUM2LONG(val);"
          when :Float64
            lines << "    ptr->#{field_name} = NUM2DBL(val);"
          when :Bool
            lines << "    ptr->#{field_name} = RTEST(val) ? 1 : 0;"
          when :String, :Object, :Array, :Hash
            lines << "    ptr->#{field_name} = val;"
          when ::Hash
            # Reference to NativeClass - store VALUE directly
            lines << "    ptr->#{field_name} = val;"
          else
            # Embedded NativeClass - copy from the passed object
            if @rbs_loader&.native_class?(field_type)
              embedded_struct = "Native_#{field_type}"
              lines << "    #{embedded_struct} *val_ptr;"
              lines << "    TypedData_Get_Struct(val, #{embedded_struct}, &#{field_type}_type, val_ptr);"
              lines << "    ptr->#{field_name} = *val_ptr;"
            else
              lines << "    ptr->#{field_name} = val;"
            end
          end
          lines << "    return val;"
          lines << "}"
          lines << ""
        end

        lines
      end

      # Generate extern declaration for a native function
      def generate_native_func_declaration(class_name, class_type, method_name, method_sig)
        lines = []
        struct_name = "Native_#{class_name}"
        func_name = mangle_method_name(class_name, method_name)

        # Build parameter list: first is struct pointer for self
        params = ["#{struct_name}* self"]

        method_sig.param_types.each_with_index do |param_type, i|
          param_name = method_sig.param_names[i] || "arg#{i}"
          c_type = native_type_to_c(param_type, class_name)
          params << "#{c_type} #{param_name}"
        end

        # Return type
        return_c_type = native_return_type_to_c(method_sig.return_type, class_name)

        lines << "extern #{return_c_type} #{func_name}(#{params.join(', ')});"
        lines
      end

      # Generate wrapper function for a NativeClass method
      def generate_native_method_wrapper(class_name, class_type, method_name, method_sig)
        lines = []
        struct_name = "Native_#{class_name}"
        native_func = mangle_method_name(class_name, method_name)
        sanitized_method = sanitize_c_name(method_name.to_s)
        wrapper_name = "rn_wrap_#{class_name}_#{sanitized_method}"

        arity = method_sig.param_types.size

        # Build parameter list for wrapper
        params = ["VALUE self"]
        arity.times { |i| params << "VALUE arg#{i}" }

        lines << "static VALUE #{wrapper_name}(#{params.join(', ')}) {"
        lines << "    #{struct_name} *ptr;"
        lines << "    TypedData_Get_Struct(self, #{struct_name}, &#{class_name}_type, ptr);"

        # Convert Ruby arguments to native types
        call_args = ["ptr"]
        method_sig.param_types.each_with_index do |param_type, i|
          arg_name = "native_arg#{i}"
          lines.concat(convert_ruby_to_native("arg#{i}", arg_name, param_type, class_name, class_type))
          call_args << arg_name
        end

        # Call native function
        return_type = method_sig.return_type
        if return_type == :Void
          lines << "    #{native_func}(#{call_args.join(', ')});"
          lines << "    return Qnil;"
        elsif return_type == :Self || @rbs_loader&.native_class?(return_type)
          # Struct returned by value - allocate Ruby object and copy into it
          result_class = return_type == :Self ? class_name : return_type
          result_struct = "Native_#{result_class}"
          lines << "    #{result_struct} result = #{native_func}(#{call_args.join(', ')});"
          lines << "    VALUE result_klass = rb_const_get(rb_cObject, rb_intern(\"#{result_class}\"));"
          lines << "    VALUE result_obj = #{result_class}_alloc(result_klass);"
          lines << "    #{result_struct} *result_ptr;"
          lines << "    TypedData_Get_Struct(result_obj, #{result_struct}, &#{result_class}_type, result_ptr);"
          lines << "    *result_ptr = result;"
          lines << "    return result_obj;"
        elsif return_type == :Int64
          lines << "    int64_t result = #{native_func}(#{call_args.join(', ')});"
          lines << "    return rb_int2inum(result);"
        elsif return_type == :Float64
          lines << "    double result = #{native_func}(#{call_args.join(', ')});"
          lines << "    return rb_float_new(result);"
        else
          lines << "    double result = #{native_func}(#{call_args.join(', ')});"
          lines << "    return rb_float_new(result);"
        end

        lines << "}"
        lines << ""
        lines
      end

      # Generate vtable for a NativeClass
      def generate_vtable(class_name, class_type, native_classes)
        lines = []

        vtable_methods = class_type.vtable_methods(native_classes)
        return lines if vtable_methods.empty?

        # Generate vtable as array of function pointers
        lines << "/* Vtable for #{class_name} */"
        lines << "static void *vtable_#{class_name}[] = {"

        vtable_methods.each_with_index do |(method_name, _method_sig, owner_name), idx|
          # Each entry points to the implementing class's function
          func_name = mangle_method_name(owner_name, method_name)
          comma = idx < vtable_methods.size - 1 ? "," : ""
          lines << "    (void *)#{func_name}#{comma}  /* #{idx}: #{method_name} */"
        end

        lines << "};"
        lines << ""
        lines
      end

      # Generate Init code for a NativeClass
      def generate_native_class_init(class_name, class_type)
        lines = []
        class_var = "c#{class_name}"

        # Define class with superclass
        superclass = class_type.superclass
        if superclass && @rbs_loader&.native_class?(superclass)
          lines << "    VALUE #{class_var} = rb_define_class(\"#{class_name}\", c#{superclass});"
        else
          lines << "    VALUE #{class_var} = rb_define_class(\"#{class_name}\", rb_cObject);"
        end

        # Register allocator
        lines << "    rb_define_alloc_func(#{class_var}, #{class_name}_alloc);"

        # Register field accessors
        class_type.fields.each do |field_name, _field_type|
          lines << "    rb_define_method(#{class_var}, \"#{field_name}\", #{class_name}_get_#{field_name}, 0);"
          lines << "    rb_define_method(#{class_var}, \"#{field_name}=\", #{class_name}_set_#{field_name}, 1);"
        end

        # Register native methods
        class_type.methods.each do |method_name, method_sig|
          sanitized_method = sanitize_c_name(method_name.to_s)
          wrapper_name = "rn_wrap_#{class_name}_#{sanitized_method}"
          arity = method_sig.param_types.size
          lines << "    rb_define_method(#{class_var}, \"#{method_name}\", #{wrapper_name}, #{arity});"
        end

        lines
      end

      # Convert native type symbol to C type string
      def native_type_to_c(type_sym, current_class)
        case type_sym
        when :Int64 then "int64_t"
        when :Float64 then "double"
        when :Self then "Native_#{current_class}*"
        else
          # Another NativeClass - use pointer
          "Native_#{type_sym}*"
        end
      end

      # Convert native return type to C type (structs are returned by value)
      def native_return_type_to_c(type_sym, current_class)
        case type_sym
        when :Int64 then "int64_t"
        when :Float64 then "double"
        when :Void then "void"
        when :Self then "Native_#{current_class}"  # Return by value
        else
          # Another NativeClass - return by value
          "Native_#{type_sym}"
        end
      end

      # Generate code to convert Ruby VALUE to native type
      def convert_ruby_to_native(ruby_var, native_var, type_sym, current_class, class_type)
        lines = []
        case type_sym
        when :Int64
          lines << "    int64_t #{native_var} = NUM2LONG(#{ruby_var});"
        when :Float64
          lines << "    double #{native_var} = NUM2DBL(#{ruby_var});"
        when :Self
          struct_name = "Native_#{current_class}"
          lines << "    #{struct_name} *#{native_var};"
          lines << "    TypedData_Get_Struct(#{ruby_var}, #{struct_name}, &#{current_class}_type, #{native_var});"
        else
          # Another NativeClass
          struct_name = "Native_#{type_sym}"
          lines << "    #{struct_name} *#{native_var};"
          lines << "    TypedData_Get_Struct(#{ruby_var}, #{struct_name}, &#{type_sym}_type, #{native_var});"
        end
        lines
      end

      def mangle_method_name(class_name, method_name)
        owner = class_name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
        name = sanitize_c_name(method_name.to_s)
        "rn_#{owner}_#{name}"
      end

      # Sanitize a Ruby method name to a valid C identifier
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

      def compile_ir_to_object(ir_file, obj_file)
        llc = find_llvm_tool("llc")
        optimized_ir = nil

        # Run opt passes before llc for better optimization
        # In debug mode, skip opt to preserve debug info
        unless @debug
          opt = find_llvm_tool("opt")
          if opt
            optimized_ir = "#{ir_file}.opt.ll"
            opt_cmd = [
              opt,
              "--passes=default<O2>",
              "-S",  # Output as text IR (not bitcode)
              "-o", optimized_ir,
              ir_file
            ]
            if system(*opt_cmd)
              ir_file = optimized_ir
            else
              optimized_ir = nil  # Don't clean up if opt failed
            end
          end
        end

        # Use llc to compile IR to object file
        # -O2 enables optimization passes including mem2reg which converts
        # allocas to proper SSA form with Phi nodes for loop variables
        # In debug mode, use -O0 to preserve debug info
        opt_level = @debug ? "-O0" : "-O2"

        cmd = [
          llc,
          opt_level,
          "-filetype=obj",
          "-relocation-model=pic"  # Required for shared libraries
        ]

        # Add debug-specific options
        if @debug
          cmd << "--debugger-tune=#{Platform.debugger_tune}"
        end

        cmd += ["-o", obj_file, ir_file]

        system(*cmd) or raise CodegenError, "Failed to compile LLVM IR to object file"
      ensure
        FileUtils.rm_f(optimized_ir) if optimized_ir
      end

      def compile_c_to_object(c_file, obj_file)
        cc = find_llvm_tool("clang") || "cc"

        cmd = [
          cc,
          "-c",
          "-fPIC",
          "-I#{RbConfig::CONFIG['rubyhdrdir']}",
          "-I#{RbConfig::CONFIG['rubyarchhdrdir']}",
          "-o", obj_file,
          c_file
        ]

        system(*cmd) or raise CodegenError, "Failed to compile C init wrapper"
      end

      def link_to_shared_library(obj_files, output_file)
        obj_files = Array(obj_files)

        # Use clang or system linker
        clang = find_llvm_tool("clang") || "cc"

        # Get Ruby's library flags
        ruby_libs = ruby_link_flags

        # Get FFI library flags from RBS annotations
        ffi_libs = ffi_link_flags

        cmd = [
          clang,
          "-shared",
          "-fPIC"
        ]

        # Add debug flag to preserve debug info during linking
        if @debug
          cmd << "-g"
        end

        cmd += [
          "-o", output_file,
          *obj_files,
          *ruby_libs,
          *ffi_libs
        ]

        # Add platform-specific flags
        case RbConfig::CONFIG["host_os"]
        when /darwin/
          cmd << "-undefined"
          cmd << "dynamic_lookup"
        when /mingw|mswin|cygwin/
          cmd << "-Wl,--export-all-symbols"
        when /linux/
          # Don't use --no-undefined for extensions
        end

        system(*cmd) or raise CodegenError, "Failed to link shared library"

        # On macOS, generate dSYM bundle for debug info
        if @debug && RbConfig::CONFIG["host_os"] =~ /darwin/
          dsymutil = "dsymutil"
          dsym_cmd = [dsymutil, output_file]
          system(*dsym_cmd) # Don't fail if dsymutil is not available
        end
      end

      # Get link flags for @ffi annotated libraries
      def ffi_link_flags
        flags = []

        # Add yyjson object files if JSON parse_as is used
        if @uses_json_parse_as
          yyjson_objs = ensure_yyjson_compiled
          flags.concat(yyjson_objs)
        end

        if @rbs_loader
          @rbs_loader.all_ffi_libraries.each do |lib_name|
            # Convert library name to linker flag
            # "libm" -> "-lm", "libfoo" -> "-lfoo", "foo" -> "-lfoo"
            link_name = lib_name.sub(/^lib/, "")
            flags << "-l#{link_name}"
          end
        end

        flags
      end

      # Compile yyjson.c and wrapper to object files if needed
      # Returns array of object file paths
      def ensure_yyjson_compiled
        yyjson_dir = File.expand_path("../../../vendor/yyjson", __dir__)
        yyjson_c = File.join(yyjson_dir, "yyjson.c")
        yyjson_obj = File.join(yyjson_dir, "yyjson.o")

        # Wrapper source is tracked in repo alongside JSON stdlib
        json_stdlib_dir = File.expand_path("../stdlib/json", __dir__)
        wrapper_c = File.join(json_stdlib_dir, "yyjson_wrapper.c")
        wrapper_obj = File.join(yyjson_dir, "yyjson_wrapper.o")

        return [] unless File.exist?(yyjson_c) && File.exist?(wrapper_c)

        cc = find_llvm_tool("clang") || "cc"

        # Compile yyjson.c
        unless File.exist?(yyjson_obj) && File.mtime(yyjson_obj) > File.mtime(yyjson_c)
          cmd = [cc, "-c", "-O3", "-fPIC", "-o", yyjson_obj, yyjson_c]
          system(*cmd) or return []
        end

        # Compile wrapper (needs yyjson.h from vendor dir)
        unless File.exist?(wrapper_obj) && File.mtime(wrapper_obj) > File.mtime(wrapper_c)
          cmd = [cc, "-c", "-O3", "-fPIC", "-I#{yyjson_dir}", "-o", wrapper_obj, wrapper_c]
          system(*cmd) or return []
        end

        [yyjson_obj, wrapper_obj]
      end

      def ruby_link_flags
        # Get Ruby's linker flags for extensions
        [
          "-L#{RbConfig::CONFIG['libdir']}",
          # Don't link against libruby for extensions - they're loaded by Ruby
        ]
      end

      # Sort native classes in dependency order (embedded types first)
      def topological_sort_native_classes(native_classes)
        sorted = []
        visited = {}
        temp_mark = {}

        visit = lambda do |name|
          return if visited[name]
          raise "Circular dependency detected in NativeClass #{name}" if temp_mark[name]

          temp_mark[name] = true

          class_type = native_classes[name]
          if class_type
            # Visit dependencies (embedded NativeClass fields only, not references)
            class_type.fields.each_value do |field_type|
              next if TypeChecker::Types::NativeClassType::ALLOWED_PRIMITIVE_TYPES.include?(field_type)
              next if TypeChecker::Types::NativeClassType::RUBY_OBJECT_TYPES.include?(field_type)
              next if field_type.is_a?(Hash)  # Skip references (stored as VALUE)
              visit.call(field_type) if native_classes.key?(field_type)
            end

            # Also visit superclass
            visit.call(class_type.superclass) if class_type.superclass && native_classes.key?(class_type.superclass)
          end

          temp_mark.delete(name)
          visited[name] = true
          sorted << name
        end

        native_classes.each_key { |name| visit.call(name) }
        sorted
      end

      # Topological sort for non-native classes (superclass before subclass)
      def topological_sort_non_native_classes(class_defs)
        by_name = class_defs.each_with_object({}) { |cd, h| h[cd.name] = cd }
        sorted = []
        visited = {}

        visit = lambda do |cd|
          return if visited[cd.name]

          visited[cd.name] = true
          if cd.superclass && by_name[cd.superclass]
            visit.call(by_name[cd.superclass])
          end
          sorted << cd
        end

        class_defs.each { |cd| visit.call(cd) }
        sorted
      end

      # Resolve superclass to C expression for rb_define_class
      EXCEPTION_CLASS_MAP = {
        "StandardError" => "rb_eStandardError",
        "RuntimeError" => "rb_eRuntimeError",
        "TypeError" => "rb_eTypeError",
        "ArgumentError" => "rb_eArgError",
        "NameError" => "rb_eNameError",
        "NoMethodError" => "rb_eNoMethodError",
        "RangeError" => "rb_eRangeError",
        "IOError" => "rb_eIOError",
        "EOFError" => "rb_eEOFError",
        "IndexError" => "rb_eIndexError",
        "KeyError" => "rb_eKeyError",
        "StopIteration" => "rb_eStopIteration",
        "ZeroDivisionError" => "rb_eZeroDivError",
        "NotImplementedError" => "rb_eNotImpError",
        "LoadError" => "rb_eLoadError",
        "ScriptError" => "rb_eScriptError",
        "SyntaxError" => "rb_eSyntaxError",
        "SecurityError" => "rb_eSecurityError",
        "RegexpError" => "rb_eRegexpError",
        "EncodingError" => "rb_eEncError",
        "Errno::ENOENT" => "rb_eSystemCallError",
        "Exception" => "rb_eException",
      }.freeze

      KNOWN_SUPERCLASS_MAP = {
        "Numeric" => "rb_cNumeric",
        "Integer" => "rb_cInteger",
        "Float" => "rb_cFloat",
        "String" => "rb_cString",
        "Array" => "rb_cArray",
        "Hash" => "rb_cHash",
        "IO" => "rb_cIO",
        "Struct" => "rb_cStruct",
        "Comparable" => "rb_mComparable",
      }.freeze

      # Known Ruby stdlib modules that can be included/extended/prepended
      KNOWN_MODULE_MAP = {
        "Comparable" => "rb_mComparable",
        "Enumerable" => "rb_mEnumerable",
        "Kernel" => "rb_mKernel",
        "Math" => "rb_mMath",
      }.freeze

      # Resolve a module name to its C expression for include/extend/prepend
      def resolve_module_c_expr(module_name)
        # Check known stdlib modules first
        if KNOWN_MODULE_MAP[module_name]
          return KNOWN_MODULE_MAP[module_name]
        end

        # User-defined module (defined earlier in Init function as mModuleName)
        "m#{module_name}"
      end

      def resolve_superclass_c_expr(superclass_name, non_native_classes)
        return "rb_cObject" unless superclass_name

        # Check known exception classes
        if EXCEPTION_CLASS_MAP[superclass_name]
          return EXCEPTION_CLASS_MAP[superclass_name]
        end

        # Check known standard classes
        if KNOWN_SUPERCLASS_MAP[superclass_name]
          return KNOWN_SUPERCLASS_MAP[superclass_name]
        end

        # Check if it's a user-defined class in the same compilation unit
        if non_native_classes.any? { |cd| cd.name == superclass_name }
          return "c#{superclass_name}"
        end

        # Fallback: runtime constant lookup
        "rb_const_get(rb_cObject, rb_intern(\"#{superclass_name}\"))"
      end

      # Convert an HIR literal node to a C VALUE expression for use in Init function.
      # Returns nil for non-literal nodes that cannot be statically initialized.
      def hir_literal_to_c_value(node)
        case node
        when HIR::IntegerLit
          "INT2FIX(#{node.value})"
        when HIR::FloatLit
          "DBL2NUM(#{node.value})"
        when HIR::StringLit
          escaped = node.value.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"').gsub("\n", "\\n").gsub("\t", "\\t")
          "rb_str_new_cstr(\"#{escaped}\")"
        when HIR::SymbolLit
          "ID2SYM(rb_intern(\"#{node.value}\"))"
        when HIR::BoolLit
          node.value ? "Qtrue" : "Qfalse"
        when HIR::NilLit
          "Qnil"
        when HIR::Literal
          # Generic literal fallback
          case node.type
          when TypeChecker::Types::INTEGER
            "INT2FIX(#{node.value})"
          when TypeChecker::Types::FLOAT
            "DBL2NUM(#{node.value})"
          when TypeChecker::Types::STRING
            escaped = node.value.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"').gsub("\n", "\\n").gsub("\t", "\\t")
            "rb_str_new_cstr(\"#{escaped}\")"
          when TypeChecker::Types::BOOL
            node.value ? "Qtrue" : "Qfalse"
          else
            nil
          end
        else
          nil
        end
      end

      # Generate extern declaration for a @cfunc C function
      def generate_cfunc_extern_declaration(cfunc_type)
        lines = []

        c_params = cfunc_type.param_types.map do |type|
          cfunc_type_to_c(type)
        end.join(", ")
        c_params = "void" if c_params.empty?

        c_return = cfunc_type_to_c(cfunc_type.return_type)

        lines << "extern #{c_return} #{cfunc_type.c_func_name}(#{c_params});"
        lines
      end

      # Convert CFuncType type symbol to C type string
      def cfunc_type_to_c(type_sym)
        case type_sym
        when :Float then "double"
        when :Integer then "int64_t"
        when :String then "VALUE"
        when :Bool then "int"
        when :void then "void"
        else "VALUE"
        end
      end

      def find_llvm_tool(name)
        path = Platform.find_llvm_tool(name)
        return path if path

        raise CodegenError, "Could not find LLVM tool: #{name}. #{Platform.llvm_install_hint}"
      end

      def ptr_type
        LLVM::Pointer(LLVM::Int8)
      end

      def profile_runtime_c_code
        # Read the profile runtime C code from the installed location
        runtime_path = File.join(__dir__, "profile_runtime.c")
        if File.exist?(runtime_path)
          File.read(runtime_path)
        else
          raise CodegenError, "Profile runtime not found at #{runtime_path}"
        end
      end
    end
  end
end
