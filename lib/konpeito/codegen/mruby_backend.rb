# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "set"

module Konpeito
  module Codegen
    # Generates standalone executable from LLVM module using mruby runtime
    class MRubyBackend
      # Stdlib modules that should be auto-defined in mruby init code
      # even when no ModuleDef exists in HIR (cfunc-only modules).
      STDLIB_MODULES = %w[Raylib Clay ClayTUI KonpeitoShell].freeze

      attr_reader :llvm_generator, :output_file, :module_name, :rbs_loader, :debug

      def initialize(llvm_generator, output_file:, module_name: nil, rbs_loader: nil, debug: false, extra_c_files: [],
                     cross_target: nil, cross_mruby_dir: nil, cross_libs_dir: nil)
        @llvm_generator = llvm_generator
        @output_file = output_file
        @module_name = module_name || derive_module_name(output_file)
        @rbs_loader = rbs_loader
        @debug = debug
        @extra_c_files = extra_c_files
        @cross_target = cross_target
        @cross_mruby_dir = cross_mruby_dir
        @cross_libs_dir = cross_libs_dir
      end

      def cross_compiling?
        !!@cross_target
      end

      def generate
        ir_file = "#{output_base}.ll"
        obj_file = "#{output_base}.o"
        init_c_file = "#{output_base}_mruby_init.c"
        init_obj_file = "#{output_base}_mruby_init.o"
        helpers_obj_file = "#{output_base}_mruby_helpers.o"
        extra_obj_files = []

        begin
          # Write LLVM IR to file
          File.write(ir_file, llvm_generator.to_ir)

          # Generate C wrapper with main() function
          File.write(init_c_file, generate_init_c_code)

          # Compile IR to object file (static relocation for executable)
          compile_ir_to_object(ir_file, obj_file)

          # Compile C init wrapper with mruby headers
          compile_c_to_object(init_c_file, init_obj_file)

          # Compile mruby_helpers.c
          compile_helpers_to_object(helpers_obj_file)

          # Compile extra C source files
          @extra_c_files.each do |c_file|
            extra_obj = "#{output_base}_extra_#{File.basename(c_file, '.c')}.o"
            compile_extra_c_to_object(c_file, extra_obj)
            extra_obj_files << extra_obj
          end

          # Compile vendored Clay library if used
          clay_objs = ensure_clay_compiled
          extra_obj_files.concat(clay_objs)

          # Compile vendored termbox2 library if ClayTUI is used
          tb2_objs = ensure_termbox_compiled
          extra_obj_files.concat(tb2_objs)

          obj_files = [obj_file, init_obj_file, helpers_obj_file] + extra_obj_files

          # Link into standalone executable
          link_to_executable(obj_files, output_file)

          # Generate license file alongside the executable
          generate_license_file
        ensure
          # Clean up intermediate files (keep .ll for debugging if ENV['KONPEITO_KEEP_IR'] is set)
          keep_ir = ENV['KONPEITO_KEEP_IR']
          all_temps = [ir_file, obj_file, init_c_file, init_obj_file, helpers_obj_file] + extra_obj_files
          all_temps.each do |f|
            next if keep_ir && f&.end_with?('.ll')
            FileUtils.rm_f(f) if f && File.exist?(f)
          end
          # Also clean optimized IR if it was generated
          unless keep_ir
            FileUtils.rm_f("#{ir_file}.opt.ll") if File.exist?("#{ir_file}.opt.ll")
          end
        end
      end

      private

      def output_base
        output_file.sub(/(\.[^.]+)?$/, "")
      end

      def derive_module_name(path)
        File.basename(path).sub(/\.[^.]*$/, "").gsub(/[^a-zA-Z0-9_]/, "_")
      end

      def generate_init_c_code
        hir = llvm_generator.hir_program
        lines = []

        lines << "#include <mruby.h>"
        lines << "#include <mruby/class.h>"
        lines << "#include <mruby/data.h>"
        lines << "#include <mruby/string.h>"
        lines << "#include <mruby/array.h>"
        lines << "#include <mruby/hash.h>"
        lines << "#include <mruby/error.h>"
        lines << "#include <mruby/proc.h>"
        lines << "#include <mruby/variable.h>"
        lines << "#include <mruby/numeric.h>"
        lines << "#include <stddef.h>"
        lines << "#include <stdlib.h>"
        lines << "#include <string.h>"
        lines << "#include <stdio.h>"
        lines << ""

        # Global mrb_state pointer (LLVM-generated code references this)
        lines << "/* Global mrb_state pointer (referenced by LLVM-generated code) */"
        lines << "extern mrb_state *konpeito_mrb_state;"
        lines << ""
        lines << "/* Block stack for rb_yield/rb_block_given_p support */"
        lines << "extern void konpeito_push_block(mrb_value block);"
        lines << "extern void konpeito_pop_block(void);"
        lines << ""

        # Collect NativeClasses from RBS loader
        native_classes = @rbs_loader&.native_classes || {}

        # Sort native classes by dependency order
        sorted_classes = topological_sort_native_classes(native_classes)

        # Forward declare structs
        sorted_classes.each do |class_name|
          lines << "typedef struct Native_#{class_name}_s Native_#{class_name};"
        end
        lines << ""

        # Generate struct definitions and mrb_data_type for NativeClasses
        sorted_classes.each do |class_name|
          class_type = native_classes[class_name]
          lines.concat(generate_native_class_struct(class_name, class_type))
        end

        # Declare external native functions from LLVM module (NativeClass methods)
        native_classes.each do |class_name, class_type|
          class_type.methods.each do |method_name, method_sig|
            lines.concat(generate_native_func_declaration(class_name, class_type, method_name, method_sig))
          end
        end

        lines << ""

        # Generate wrapper functions for NativeClass methods (mrb_get_args style)
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

            if llvm_generator.variadic_functions[mangled_name]
              lines << "extern mrb_value #{mangled_name}(mrb_state *mrb, mrb_value self);"
            else
              param_count = func.params.size
              param_types = (["mrb_value"] * param_count).join(", ")
              lines << "extern mrb_value #{mangled_name}(#{param_types});"
            end
          end
        end

        # Declare external functions from LLVM module (modules)
        hir.modules.each do |module_def|
          (module_def.methods + module_def.singleton_methods).each do |method_name|
            mangled_name = mangle_method_name(module_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            if llvm_generator.variadic_functions[mangled_name]
              lines << "extern mrb_value #{mangled_name}(mrb_state *mrb, mrb_value self);"
            else
              param_count = func.params.size
              param_types = (["mrb_value"] * param_count).join(", ")
              lines << "extern mrb_value #{mangled_name}(#{param_types});"
            end
          end
        end

        # Declare top-level functions
        hir.functions.each do |func_def|
          next if func_def.owner_class

          mangled_name = "rn_#{func_def.name}".gsub(/[^a-zA-Z0-9_]/, "_")
          func = llvm_generator.mod.functions[mangled_name]
          next unless func

          if llvm_generator.variadic_functions[mangled_name]
            lines << "extern mrb_value #{mangled_name}(mrb_state *mrb, mrb_value self);"
          else
            param_count = func.params.size
            param_types = (["mrb_value"] * param_count).join(", ")
            lines << "extern mrb_value #{mangled_name}(#{param_types});"
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

        lines << ""

        # Generate mrb_value wrapper functions for non-native methods
        # These adapt the mrb_func_t signature (mrb_state*, mrb_value self) to
        # the LLVM-generated VALUE-style signatures
        hir.classes.each do |class_def|
          next if native_classes.key?(class_def.name.to_sym)

          (class_def.method_names + class_def.singleton_methods).each do |method_name|
            mangled_name = mangle_method_name(class_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            lines.concat(generate_mruby_method_wrapper(mangled_name, func))
          end
        end

        hir.modules.each do |module_def|
          (module_def.methods + module_def.singleton_methods).each do |method_name|
            mangled_name = mangle_method_name(module_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            lines.concat(generate_mruby_method_wrapper(mangled_name, func))
          end
        end

        hir.functions.each do |func_def|
          next if func_def.owner_class
          next if func_def.owner_module
          next if func_def.name == "__main__"

          mangled_name = "rn_#{func_def.name}".gsub(/[^a-zA-Z0-9_]/, "_")
          func = llvm_generator.mod.functions[mangled_name]
          next unless func

          lines.concat(generate_mruby_method_wrapper(mangled_name, func))
        end

        lines << ""
        lines << "int main(int argc, char **argv) {"
        lines << "    mrb_state *mrb = mrb_open();"
        lines << "    if (!mrb) {"
        lines << '        fprintf(stderr, "mruby initialization failed\\n");'
        lines << "        return 1;"
        lines << "    }"
        lines << "    konpeito_mrb_state = mrb;"
        lines << ""
        lines << "    /* Initialize CRuby-compatible global variables (rb_cObject, rb_eStandardError, etc.) */"
        lines << "    extern void konpeito_mruby_init_globals(void);"
        lines << "    konpeito_mruby_init_globals();"
        lines << ""
        lines << "    /* Initialize mruby constant values (Qnil, Qtrue, etc.) */"
        lines << "    extern void konpeito_mruby_init_constants(void);"
        lines << "    konpeito_mruby_init_constants();"
        lines << ""

        # Define modules
        defined_module_names = []
        hir.modules.each do |module_def|
          defined_module_names << module_def.name.to_s
          module_var = "m#{module_def.name}"
          lines << "    struct RClass *#{module_var} = mrb_define_module(mrb, \"#{module_def.name}\");"

          # Register instance methods
          module_def.methods.each do |method_name|
            next if @rbs_loader&.cfunc_method?(module_def.name, method_name, singleton: false)

            mangled_name = mangle_method_name(module_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            wrapper = "mrb_wrap_#{mangled_name}"
            mrb_args = arity_to_mrb_args(arity)
            lines << "    mrb_define_method(mrb, #{module_var}, \"#{method_name}\", #{wrapper}, #{mrb_args});"
          end

          # Register singleton methods
          module_def.singleton_methods.each do |method_name|
            next if @rbs_loader&.cfunc_method?(module_def.name, method_name, singleton: true)

            mangled_name = mangle_method_name(module_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            wrapper = "mrb_wrap_#{mangled_name}"
            mrb_args = arity_to_mrb_args(arity)
            lines << "    mrb_define_class_method(mrb, #{module_var}, \"#{method_name}\", #{wrapper}, #{mrb_args});"
          end

          # Register module constants
          module_def.constants.each do |const_name, value_node|
            c_value = hir_literal_to_mrb_value(value_node)
            next unless c_value

            lines << "    mrb_define_const(mrb, #{module_var}, \"#{const_name}\", #{c_value});"
          end
        end

        # Auto-define stdlib modules that have cfunc methods but no ModuleDef in HIR.
        # This ensures that even if a dynamic dispatch fallback occurs (e.g., due to
        # a method name mismatch), the module constant exists at runtime.
        if @rbs_loader
          STDLIB_MODULES.each do |mod_name|
            next if defined_module_names.include?(mod_name)
            next unless @rbs_loader.has_cfunc_methods?(mod_name.to_sym)

            lines << "    mrb_define_module(mrb, \"#{mod_name}\");"
          end
        end

        # Define NativeClasses with mrb_data_type
        native_classes.each do |class_name, class_type|
          lines.concat(generate_native_class_init(class_name, class_type))
        end

        # Define non-native classes
        non_native_classes = hir.classes.reject { |cd| native_classes.key?(cd.name.to_sym) }
        sorted_non_native = topological_sort_non_native_classes(non_native_classes)

        sorted_non_native.each do |class_def|
          class_var = "c#{class_def.name}"
          if class_def.reopened
            lines << "    struct RClass *#{class_var} = mrb_class_get(mrb, \"#{class_def.name}\");"
          else
            superclass_expr = resolve_superclass_mrb_expr(class_def.superclass, non_native_classes)
            lines << "    struct RClass *#{class_var} = mrb_define_class(mrb, \"#{class_def.name}\", #{superclass_expr});"
          end

          # Include modules
          class_def.included_modules.each do |mod_name|
            mod_expr = resolve_module_mrb_expr(mod_name)
            lines << "    mrb_include_module(mrb, #{class_var}, #{mod_expr});"
          end

          class_def.method_names.each do |method_name|
            mangled_name = mangle_method_name(class_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            wrapper = "mrb_wrap_#{mangled_name}"
            mrb_args = arity_to_mrb_args(arity)
            lines << "    mrb_define_method(mrb, #{class_var}, \"#{method_name}\", #{wrapper}, #{mrb_args});"
          end

          # Register singleton methods
          class_def.singleton_methods.each do |method_name|
            next if @rbs_loader&.cfunc_method?(class_def.name, method_name, singleton: true)

            mangled_name = mangle_method_name(class_def.name, method_name)
            func = llvm_generator.mod.functions[mangled_name]
            next unless func

            arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
            wrapper = "mrb_wrap_#{mangled_name}"
            mrb_args = arity_to_mrb_args(arity)
            lines << "    mrb_define_class_method(mrb, #{class_var}, \"#{method_name}\", #{wrapper}, #{mrb_args});"
          end

          # Register aliases
          class_def.aliases.each do |new_name, old_name|
            lines << "    mrb_define_alias(mrb, #{class_var}, \"#{new_name}\", \"#{old_name}\");"
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

          arity = llvm_generator.variadic_functions[mangled_name] ? -1 : func.params.size - 1
          wrapper = "mrb_wrap_#{mangled_name}"
          mrb_args = arity_to_mrb_args(arity)
          lines << "    mrb_define_method(mrb, mrb->object_class, \"#{func_def.name}\", #{wrapper}, #{mrb_args});"
        end

        # Call top-level entry point
        has_main = hir.functions.any? { |f| f.name == "__main__" && !f.owner_class && !f.owner_module }
        if has_main
          lines << ""
          lines << "    /* Run top-level code */"
          lines << "    rn___main__(mrb_top_self(mrb));"
        end

        lines << ""
        lines << "    if (mrb->exc) {"
        lines << "        mrb_print_error(mrb);"
        lines << "        mrb_close(mrb);"
        lines << "        return 1;"
        lines << "    }"
        lines << ""
        lines << "    mrb_close(mrb);"
        lines << "    return 0;"
        lines << "}"
        lines << ""

        lines.join("\n")
      end

      # Generate mrb_func_t wrapper that calls the LLVM-generated function.
      # All wrappers capture the block argument so rb_yield/rb_block_given_p
      # work correctly via the konpeito_push_block/konpeito_pop_block mechanism.
      def generate_mruby_method_wrapper(mangled_name, llvm_func)
        lines = []
        wrapper_name = "mrb_wrap_#{mangled_name}"

        if llvm_generator.variadic_functions[mangled_name]
          # Variadic function: already has (mrb_state*, mrb_value self) signature.
          # Capture block before delegating.
          lines << "static mrb_value #{wrapper_name}(mrb_state *mrb, mrb_value self) {"
          lines << "    mrb_value _block = mrb_nil_value();"
          lines << "    mrb_get_args(mrb, \"|&\", &_block);"
          lines << "    konpeito_push_block(_block);"
          lines << "    mrb_value _result = #{mangled_name}(mrb, self);"
          lines << "    konpeito_pop_block();"
          lines << "    return _result;"
          lines << "}"
        else
          arity = llvm_func.params.size - 1  # Subtract self

          # Check if this function has only keyword args (no positional params).
          # If so, the kwargs hash arg is optional — caller may pass 0 args
          # when no keywords are specified (e.g., `footer do ... end`).
          func_base_name = mangled_name.sub(/\Arn_/, "")
          kw_info = llvm_generator.keyword_param_functions[func_base_name] ||
                    llvm_generator.keyword_param_functions[func_base_name.to_sym]
          kwargs_only = kw_info && kw_info[:regular_count] == 0 && arity == 1

          lines << "static mrb_value #{wrapper_name}(mrb_state *mrb, mrb_value self) {"
          if kwargs_only
            # Single optional kwargs hash arg — default to empty hash
            lines << "    mrb_value a0 = mrb_nil_value(), _block = mrb_nil_value();"
            lines << "    mrb_get_args(mrb, \"|o&\", &a0, &_block);"
            lines << "    if (mrb_nil_p(a0)) a0 = mrb_hash_new(mrb);"
          elsif arity > 0
            lines << "    mrb_value #{(0...arity).map { |i| "a#{i}" }.join(', ')}, _block;"
            format_str = "o" * arity + "&"
            args_list = (0...arity).map { |i| "&a#{i}" }.join(", ") + ", &_block"
            lines << "    mrb_get_args(mrb, \"#{format_str}\", #{args_list});"
          else
            lines << "    mrb_value _block;"
            lines << "    mrb_get_args(mrb, \"&\", &_block);"
          end
          lines << "    konpeito_push_block(_block);"
          if arity > 0
            call_args = (["self"] + (0...arity).map { |i| "a#{i}" }).join(", ")
          else
            call_args = "self"
          end
          lines << "    mrb_value _result = #{mangled_name}(#{call_args});"
          lines << "    konpeito_pop_block();"
          lines << "    return _result;"
          lines << "}"
        end

        lines << ""
        lines
      end

      # Generate C struct and mrb_data_type for NativeClass
      def generate_native_class_struct(class_name, class_type)
        lines = []
        struct_name = "Native_#{class_name}"

        # Struct definition
        lines << "struct Native_#{class_name}_s {"
        class_type.fields.each do |field_name, field_type|
          c_type = case field_type
          when :Int64 then "int64_t"
          when :Float64 then "double"
          when :Bool then "int8_t"
          when :String, :Object, :Array, :Hash then "mrb_value"
          when Hash then "mrb_value"
          else
            if @rbs_loader&.native_class?(field_type)
              "Native_#{field_type}"
            else
              "mrb_value"
            end
          end
          lines << "    #{c_type} #{field_name};"
        end
        lines << "};"
        lines << ""

        # mrb_data_type (replaces CRuby's rb_data_type_t)
        lines << "static const mrb_data_type #{class_name}_type = {"
        lines << "    \"#{class_name}\", mrb_free"
        lines << "};"
        lines << ""

        # Allocator function
        lines << "static mrb_value #{class_name}_alloc(mrb_state *mrb, mrb_value klass) {"
        lines << "    #{struct_name} *ptr = (#{struct_name} *)mrb_malloc(mrb, sizeof(#{struct_name}));"
        lines << "    memset(ptr, 0, sizeof(#{struct_name}));"

        # Initialize VALUE fields to nil
        class_type.fields.each do |field_name, field_type|
          case field_type
          when :String, :Object, :Array, :Hash
            lines << "    ptr->#{field_name} = mrb_nil_value();"
          when Hash
            lines << "    ptr->#{field_name} = mrb_nil_value();"
          end
        end

        lines << "    struct RClass *cls = mrb_class_ptr(klass);"
        lines << "    struct RData *data = mrb_data_object_alloc(mrb, cls, ptr, &#{class_name}_type);"
        lines << "    return mrb_obj_value(data);"
        lines << "}"
        lines << ""

        # Field accessors (getter)
        class_type.fields.each do |field_name, _field_type|
          lines << "static mrb_value #{class_name}_get_#{field_name}(mrb_state *mrb, mrb_value self) {"
          lines << "    #{struct_name} *ptr = (#{struct_name} *)DATA_PTR(self);"
          case _field_type
          when :Int64
            lines << "    return mrb_fixnum_value(ptr->#{field_name});"
          when :Float64
            lines << "    return mrb_float_value(mrb, ptr->#{field_name});"
          when :Bool
            lines << "    return ptr->#{field_name} ? mrb_true_value() : mrb_false_value();"
          else
            lines << "    return ptr->#{field_name};"
          end
          lines << "}"
          lines << ""
        end

        # Field accessors (setter)
        class_type.fields.each do |field_name, _field_type|
          lines << "static mrb_value #{class_name}_set_#{field_name}(mrb_state *mrb, mrb_value self) {"
          lines << "    mrb_value val;"
          lines << "    mrb_get_args(mrb, \"o\", &val);"
          lines << "    #{struct_name} *ptr = (#{struct_name} *)DATA_PTR(self);"
          case _field_type
          when :Int64
            lines << "    ptr->#{field_name} = mrb_integer(val);"
          when :Float64
            lines << "    ptr->#{field_name} = mrb_as_float(mrb, val);"
          when :Bool
            lines << "    ptr->#{field_name} = mrb_test(val) ? 1 : 0;"
          else
            lines << "    ptr->#{field_name} = val;"
          end
          lines << "    return val;"
          lines << "}"
          lines << ""
        end

        lines
      end

      # Generate Init code for a NativeClass in mruby
      def generate_native_class_init(class_name, class_type)
        lines = []
        class_var = "c#{class_name}"

        superclass = class_type.superclass
        if superclass && @rbs_loader&.native_class?(superclass)
          lines << "    struct RClass *#{class_var} = mrb_define_class(mrb, \"#{class_name}\", c#{superclass});"
        else
          lines << "    struct RClass *#{class_var} = mrb_define_class(mrb, \"#{class_name}\", mrb->object_class);"
        end

        lines << "    MRB_SET_INSTANCE_TT(#{class_var}, MRB_TT_CDATA);"

        # Register allocator as class method "new"
        lines << "    mrb_define_class_method(mrb, #{class_var}, \"new\", #{class_name}_alloc, MRB_ARGS_NONE());"

        # Register field accessors
        class_type.fields.each do |field_name, _field_type|
          lines << "    mrb_define_method(mrb, #{class_var}, \"#{field_name}\", #{class_name}_get_#{field_name}, MRB_ARGS_NONE());"
          lines << "    mrb_define_method(mrb, #{class_var}, \"#{field_name}=\", #{class_name}_set_#{field_name}, MRB_ARGS_REQ(1));"
        end

        # Register native methods
        class_type.methods.each do |method_name, method_sig|
          sanitized_method = sanitize_c_name(method_name.to_s)
          wrapper_name = "rn_wrap_#{class_name}_#{sanitized_method}"
          arity = method_sig.param_types.size
          mrb_args = arity_to_mrb_args(arity)
          lines << "    mrb_define_method(mrb, #{class_var}, \"#{method_name}\", #{wrapper_name}, #{mrb_args});"
        end

        lines
      end

      # Generate extern declaration for a native function
      def generate_native_func_declaration(class_name, class_type, method_name, method_sig)
        lines = []
        struct_name = "Native_#{class_name}"
        func_name = mangle_method_name(class_name, method_name)

        params = ["#{struct_name}* self"]
        method_sig.param_types.each_with_index do |param_type, i|
          param_name = method_sig.param_names[i] || "arg#{i}"
          c_type = native_type_to_c(param_type, class_name)
          params << "#{c_type} #{param_name}"
        end

        return_c_type = native_return_type_to_c(method_sig.return_type, class_name)
        lines << "extern #{return_c_type} #{func_name}(#{params.join(', ')});"
        lines
      end

      # Generate wrapper function for a NativeClass method (mruby style)
      def generate_native_method_wrapper(class_name, class_type, method_name, method_sig)
        lines = []
        struct_name = "Native_#{class_name}"
        native_func = mangle_method_name(class_name, method_name)
        sanitized_method = sanitize_c_name(method_name.to_s)
        wrapper_name = "rn_wrap_#{class_name}_#{sanitized_method}"

        arity = method_sig.param_types.size

        lines << "static mrb_value #{wrapper_name}(mrb_state *mrb, mrb_value self) {"
        lines << "    #{struct_name} *ptr = (#{struct_name} *)DATA_PTR(self);"

        # Get arguments with mrb_get_args
        if arity > 0
          lines << "    mrb_value #{(0...arity).map { |i| "arg#{i}" }.join(', ')};"
          format_str = "o" * arity
          args_list = (0...arity).map { |i| "&arg#{i}" }.join(", ")
          lines << "    mrb_get_args(mrb, \"#{format_str}\", #{args_list});"
        end

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
          lines << "    return mrb_nil_value();"
        elsif return_type == :Self || @rbs_loader&.native_class?(return_type)
          result_class = return_type == :Self ? class_name : return_type
          result_struct = "Native_#{result_class}"
          lines << "    #{result_struct} result = #{native_func}(#{call_args.join(', ')});"
          lines << "    struct RClass *result_cls = mrb_class_get(mrb, \"#{result_class}\");"
          lines << "    mrb_value result_obj = #{result_class}_alloc(mrb, mrb_obj_value(result_cls));"
          lines << "    #{result_struct} *result_ptr = (#{result_struct} *)DATA_PTR(result_obj);"
          lines << "    *result_ptr = result;"
          lines << "    return result_obj;"
        elsif return_type == :Int64
          lines << "    int64_t result = #{native_func}(#{call_args.join(', ')});"
          lines << "    return mrb_fixnum_value(result);"
        elsif return_type == :Float64
          lines << "    double result = #{native_func}(#{call_args.join(', ')});"
          lines << "    return mrb_float_value(mrb, result);"
        else
          lines << "    double result = #{native_func}(#{call_args.join(', ')});"
          lines << "    return mrb_float_value(mrb, result);"
        end

        lines << "}"
        lines << ""
        lines
      end

      # Convert native type symbol to C type string
      def native_type_to_c(type_sym, current_class)
        case type_sym
        when :Int64 then "int64_t"
        when :Float64 then "double"
        when :Self then "Native_#{current_class}*"
        else
          "Native_#{type_sym}*"
        end
      end

      def native_return_type_to_c(type_sym, current_class)
        case type_sym
        when :Int64 then "int64_t"
        when :Float64 then "double"
        when :Void then "void"
        when :Self then "Native_#{current_class}"
        else
          "Native_#{type_sym}"
        end
      end

      # Generate code to convert mruby mrb_value to native type
      def convert_ruby_to_native(ruby_var, native_var, type_sym, current_class, class_type)
        lines = []
        case type_sym
        when :Int64
          lines << "    int64_t #{native_var} = mrb_integer(#{ruby_var});"
        when :Float64
          lines << "    double #{native_var} = mrb_as_float(mrb, #{ruby_var});"
        when :Self
          struct_name = "Native_#{current_class}"
          lines << "    #{struct_name} *#{native_var} = (#{struct_name} *)DATA_PTR(#{ruby_var});"
        else
          struct_name = "Native_#{type_sym}"
          lines << "    #{struct_name} *#{native_var} = (#{struct_name} *)DATA_PTR(#{ruby_var});"
        end
        lines
      end

      def generate_cfunc_extern_declaration(cfunc_type)
        lines = []
        # Generate extern declaration for C function
        return_c = case cfunc_type.return_type
        when :Float64, :float, :double then "double"
        when :Int64, :int, :long then "long"
        when :Void, :void then "void"
        when :String, :string then "const char*"
        when :Pointer, :ptr then "void*"
        else "double"
        end

        params_c = cfunc_type.param_types.map do |pt|
          case pt
          when :Float64, :float, :double then "double"
          when :Int64, :int, :long then "long"
          when :String, :string then "const char*"
          when :Pointer, :ptr then "void*"
          else "double"
          end
        end

        lines << "extern #{return_c} #{cfunc_type.c_func_name}(#{params_c.join(', ')});"
        lines
      end

      # Convert HIR literal node to mruby C expression
      def hir_literal_to_mrb_value(node)
        case node
        when HIR::IntLit
          "mrb_fixnum_value(#{node.value})"
        when HIR::FloatLit
          "mrb_float_value(mrb, #{node.value})"
        when HIR::StringLit
          "mrb_str_new_cstr(mrb, \"#{escape_c_string(node.value)}\")"
        when HIR::SymbolLit
          "mrb_symbol_value(mrb_intern_cstr(mrb, \"#{node.value}\"))"
        when HIR::BoolLit
          node.value ? "mrb_true_value()" : "mrb_false_value()"
        when HIR::NilLit
          "mrb_nil_value()"
        end
      end

      def escape_c_string(str)
        str.gsub("\\", "\\\\\\\\")
           .gsub("\"", "\\\"")
           .gsub("\n", "\\n")
           .gsub("\t", "\\t")
           .gsub("\r", "\\r")
      end

      def arity_to_mrb_args(arity)
        if arity == -1
          "MRB_ARGS_ANY()"
        elsif arity == 0
          "MRB_ARGS_NONE()"
        else
          "MRB_ARGS_REQ(#{arity})"
        end
      end

      def resolve_superclass_mrb_expr(superclass, non_native_classes)
        return "mrb->object_class" unless superclass

        known_core = {
          "StandardError" => "E_STANDARD_ERROR",
          "RuntimeError" => "E_RUNTIME_ERROR",
          "ArgumentError" => "E_ARGUMENT_ERROR",
          "TypeError" => "E_TYPE_ERROR",
          "NameError" => "E_NAME_ERROR",
          "IndexError" => "E_INDEX_ERROR",
          "RangeError" => "E_RANGE_ERROR",
        }

        if known_core[superclass.to_s]
          known_core[superclass.to_s]
        elsif non_native_classes.any? { |cd| cd.name.to_s == superclass.to_s }
          "c#{superclass}"
        else
          "mrb_class_get(mrb, \"#{superclass}\")"
        end
      end

      def resolve_module_mrb_expr(module_name)
        "mrb_module_get(mrb, \"#{module_name}\")"
      end

      def mangle_method_name(class_name, method_name)
        owner = class_name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
        name = sanitize_c_name(method_name.to_s)
        "rn_#{owner}_#{name}"
      end

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

      # === License file generation ===

      def generate_license_file
        license_path = "#{output_file}.LICENSES.txt"
        sections = []

        # Always include Konpeito itself
        sections << license_section(
          "Konpeito",
          "MIT",
          "Copyright (c) Konpeito contributors",
          "https://github.com/i2y/konpeito",
          <<~MIT
            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            SOFTWARE.
          MIT
        )

        # Always include mruby (statically linked)
        sections << license_section(
          "mruby",
          "MIT",
          "Copyright (c) mruby developers",
          "https://github.com/mruby/mruby",
          <<~MIT
            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            SOFTWARE.
          MIT
        )

        # Include yyjson if JSON stdlib is used
        json_used = @extra_c_files.any? { |f| File.basename(f).include?("json") }
        if json_used
          sections << license_section(
            "yyjson",
            "MIT",
            "Copyright (c) 2020 YaoYuan <ibireme@gmail.com>",
            "https://github.com/ibireme/yyjson",
            <<~MIT
              Permission is hereby granted, free of charge, to any person obtaining a copy
              of this software and associated documentation files (the "Software"), to deal
              in the Software without restriction, including without limitation the rights
              to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
              copies of the Software, and to permit persons to whom the Software is
              furnished to do so, subject to the following conditions:

              The above copyright notice and this permission notice shall be included in all
              copies or substantial portions of the Software.

              THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
              IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
              FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
              AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
              LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
              OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
              SOFTWARE.
            MIT
          )
        end

        # Include Clay if used
        clay_used = @extra_c_files.any? { |f| File.basename(f).include?("clay") }
        if clay_used
          sections << license_section(
            "Clay",
            "zlib/libpng",
            "Copyright (c) 2024 Nic Barker",
            "https://github.com/nicbarker/clay",
            <<~ZLIB
              This software is provided 'as-is', without any express or implied warranty.
              In no event will the authors be held liable for any damages arising from the
              use of this software.

              Permission is granted to anyone to use this software for any purpose,
              including commercial applications, and to alter it and redistribute it freely,
              subject to the following restrictions:

              1. The origin of this software must not be misrepresented; you must not claim
                 that you wrote the original software. If you use this software in a product,
                 an acknowledgment in the product documentation would be appreciated but is
                 not required.
              2. Altered source versions must be plainly marked as such, and must not be
                 misrepresented as being the original software.
              3. This notice may not be removed or altered from any source distribution.
            ZLIB
          )
        end

        # Include termbox2 if ClayTUI is used
        clay_tui_used = @extra_c_files.any? { |f| File.basename(f).include?("clay_tui") }
        if clay_tui_used
          sections << license_section(
            "termbox2",
            "MIT",
            "Copyright (c) 2021 termbox developers",
            "https://github.com/termbox/termbox2",
            <<~MIT
              Permission is hereby granted, free of charge, to any person obtaining a copy
              of this software and associated documentation files (the "Software"), to deal
              in the Software without restriction, including without limitation the rights
              to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
              copies of the Software, and to permit persons to whom the Software is
              furnished to do so, subject to the following conditions:

              The above copyright notice and this permission notice shall be included in all
              copies or substantial portions of the Software.

              THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
              IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
              FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
              AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
              LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
              OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
              SOFTWARE.
            MIT
          )
        end

        # Include raylib if linked
        ffi_libs = @rbs_loader&.all_ffi_libraries || []
        if ffi_libs.any? { |lib| lib.to_s.include?("raylib") }
          sections << license_section(
            "raylib",
            "zlib/libpng",
            "Copyright (c) 2013-2024 Ramon Santamaria (@raysan5)",
            "https://github.com/raysan5/raylib",
            <<~ZLIB
              This software is provided 'as-is', without any express or implied warranty.
              In no event will the authors be held liable for any damages arising from the
              use of this software.

              Permission is granted to anyone to use this software for any purpose,
              including commercial applications, and to alter it and redistribute it freely,
              subject to the following restrictions:

              1. The origin of this software must not be misrepresented; you must not claim
                 that you wrote the original software. If you use this software in a product,
                 an acknowledgment in the product documentation would be appreciated but is
                 not required.
              2. Altered source versions must be plainly marked as such, and must not be
                 misrepresented as being the original software.
              3. This notice may not be removed or altered from any source distribution.
            ZLIB
          )
        end

        File.write(license_path, sections.join("\n"))
      end

      def license_section(name, license_type, copyright, url, license_text)
        <<~SECTION
          ================================================================================
          #{name}
          License: #{license_type}
          #{copyright}
          #{url}
          ================================================================================

          #{license_text.strip}

        SECTION
      end

      # === Compilation pipeline ===

      def compile_ir_to_object(ir_file, obj_file)
        llc = find_llvm_tool("llc")
        optimized_ir = nil

        unless @debug
          opt = find_llvm_tool("opt")
          if opt
            optimized_ir = "#{ir_file}.opt.ll"
            opt_cmd = [opt, "--passes=default<O2>", "-S", "-o", optimized_ir, ir_file]
            if system(*opt_cmd)
              ir_file = optimized_ir
            else
              optimized_ir = nil
            end
          end
        end

        opt_level = @debug ? "-O0" : "-O2"
        cmd = [
          llc, opt_level,
          "-filetype=obj",
          "-relocation-model=static",  # Static for standalone executable (not PIC)
        ]

        # Add target triple for cross-compilation
        if cross_compiling?
          triple = Platform.llvm_triple(@cross_target)
          cmd += ["--mtriple=#{triple}"]
        end

        cmd += ["-o", obj_file, ir_file]

        system(*cmd) or raise CodegenError, "Failed to compile LLVM IR to object file"
      ensure
        FileUtils.rm_f(optimized_ir) if optimized_ir
      end

      def compile_c_to_object(c_file, obj_file)
        cc, cc_flags = cross_cc_with_flags
        cflags = cross_compiling? ? Platform.cross_mruby_cflags(@cross_mruby_dir) : Platform.mruby_cflags

        cmd = [*cc, "-c"]
        cmd.concat(cc_flags)
        cmd.concat(cflags.split)
        cmd += ["-o", obj_file, c_file]

        system(*cmd) or raise CodegenError, "Failed to compile mruby init wrapper"
      end

      def compile_helpers_to_object(obj_file)
        cc, cc_flags = cross_cc_with_flags
        helpers_c = File.expand_path("mruby_helpers.c", __dir__)
        cflags = cross_compiling? ? Platform.cross_mruby_cflags(@cross_mruby_dir) : Platform.mruby_cflags

        cmd = [*cc, "-c"]
        cmd.concat(cc_flags)
        cmd.concat(cflags.split)
        cmd += ["-o", obj_file, helpers_c]

        system(*cmd) or raise CodegenError, "Failed to compile mruby helpers"
      end

      def compile_extra_c_to_object(c_file, obj_file)
        cc, cc_flags = cross_cc_with_flags
        cflags = cross_compiling? ? Platform.cross_mruby_cflags(@cross_mruby_dir) : Platform.mruby_cflags

        # Add include paths for FFI libraries (e.g., raylib)
        extra_includes = ffi_include_flags

        cmd = [*cc, "-c"]
        cmd.concat(cc_flags)
        cmd.concat(cflags.split)
        cmd.concat(extra_includes)
        cmd += ["-o", obj_file, c_file]

        system(*cmd) or raise CodegenError, "Failed to compile #{File.basename(c_file)}"
      end

      def link_to_executable(obj_files, output_file)
        if cross_compiling?
          link_cross(obj_files, output_file)
        else
          link_native(obj_files, output_file)
        end
      end

      def link_native(obj_files, output_file)
        cc = find_llvm_tool("clang") || "cc"
        ldflags = Platform.mruby_ldflags
        ffi_libs = ffi_link_flags

        cmd = [cc, "-o", output_file, *obj_files]
        cmd.concat(ldflags.split)

        # Add library search paths for homebrew
        if Dir.exist?("/opt/homebrew/lib")
          cmd << "-L/opt/homebrew/lib"
        end

        cmd.concat(ffi_libs)

        if @debug
          cmd << "-g"
        end

        # Platform-specific flags
        case RbConfig::CONFIG["host_os"]
        when /darwin/
          # macOS may need frameworks for certain libs
        when /linux/
          cmd << "-lpthread" unless ldflags.include?("-lpthread")
          cmd << "-ldl" unless ldflags.include?("-ldl")
        end

        system(*cmd) or raise CodegenError, "Failed to link standalone executable"
      end

      def link_cross(obj_files, output_file)
        cc, cc_flags = cross_cc_with_flags
        ldflags = Platform.cross_mruby_ldflags(@cross_mruby_dir)
        ffi_libs = ffi_link_flags

        cmd = [*cc, "-o", output_file, *obj_files]
        cmd.concat(cc_flags)
        cmd.concat(ldflags.split)

        # Add cross library search path if specified
        if @cross_libs_dir && Dir.exist?(@cross_libs_dir)
          cmd << "-L#{@cross_libs_dir}"
        end

        cmd.concat(ffi_libs)

        if @debug
          cmd << "-g"
        end

        # Platform-specific flags for target
        if @cross_target =~ /linux/
          cmd << "-lpthread" unless ldflags.include?("-lpthread")
          cmd << "-ldl" unless ldflags.include?("-ldl")
        end

        # Static linking preferred for cross-compiled executables
        cmd << "-static" if @cross_target =~ /linux/

        system(*cmd) or raise CodegenError, "Failed to cross-link standalone executable for #{@cross_target}"
      end

      def ffi_link_flags
        flags = []
        if @rbs_loader
          @rbs_loader.all_ffi_libraries.each do |lib_name|
            link_name = lib_name.sub(/^lib/, "")
            # Prefer static library (.a) for standalone executables
            static_lib = find_static_library(link_name)
            if static_lib
              flags << static_lib
              # Add macOS framework dependencies for known libraries
              flags.concat(macos_framework_flags(link_name)) if darwin?
            else
              flags << "-l#{link_name}"
            end
          end
        end
        flags
      end

      def find_static_library(lib_name)
        search_paths = []

        if cross_compiling?
          # When cross-compiling, search cross paths first
          search_paths << @cross_libs_dir if @cross_libs_dir && Dir.exist?(@cross_libs_dir)
          search_paths << File.join(@cross_mruby_dir, "lib") if @cross_mruby_dir
        else
          search_paths << "/opt/homebrew/lib" if Dir.exist?("/opt/homebrew/lib")
          search_paths << "/usr/local/lib" if Dir.exist?("/usr/local/lib")
        end

        search_paths.each do |dir|
          path = File.join(dir, "lib#{lib_name}.a")
          return path if File.exist?(path)
        end
        nil
      end

      def macos_framework_flags(lib_name)
        # Known framework dependencies for popular libraries
        case lib_name
        when "raylib"
          ["-framework", "IOKit", "-framework", "Cocoa", "-framework", "OpenGL",
           "-framework", "CoreAudio", "-framework", "AudioToolbox",
           "-framework", "CoreFoundation"]
        when "SDL2", "sdl2"
          ["-framework", "IOKit", "-framework", "Cocoa", "-framework", "Carbon",
           "-framework", "CoreAudio", "-framework", "AudioToolbox",
           "-framework", "ForceFeedback", "-framework", "CoreVideo",
           "-framework", "Metal", "-framework", "GameController"]
        when "glfw3", "glfw"
          ["-framework", "IOKit", "-framework", "Cocoa", "-framework", "OpenGL"]
        else
          []
        end
      end

      def darwin?
        if cross_compiling?
          @cross_target =~ /darwin|macos/
        else
          RbConfig::CONFIG["host_os"] =~ /darwin/
        end
      end

      # Compile vendored clay.h implementation if Clay stdlib is used
      # Returns array of object file paths
      def ensure_clay_compiled
        clay_used = @extra_c_files.any? { |f| File.basename(f).include?("clay") }
        return [] unless clay_used

        clay_dir = File.expand_path("../../../vendor/clay", __dir__)
        clay_impl_c = File.join(clay_dir, "clay_impl.c")
        clay_impl_obj = File.join(clay_dir, "clay_impl.o")

        return [] unless File.exist?(clay_impl_c)

        cc, cc_flags = cross_cc_with_flags
        cflags = cross_compiling? ? Platform.cross_mruby_cflags(@cross_mruby_dir) : (Platform.mruby_cflags rescue "-O2")

        # Compile clay_impl.c (only if stale)
        unless File.exist?(clay_impl_obj) && File.mtime(clay_impl_obj) > File.mtime(clay_impl_c)
          cmd = [*cc, "-c", "-O2"]
          cmd.concat(cc_flags)
          cmd += ["-o", clay_impl_obj, clay_impl_c]
          system(*cmd) or return []
        end

        [clay_impl_obj]
      end

      # Compile vendored termbox2 implementation if ClayTUI stdlib is used
      # Returns array of object file paths
      def ensure_termbox_compiled
        clay_tui_used = @extra_c_files.any? { |f| File.basename(f).include?("clay_tui") }
        return [] unless clay_tui_used

        tb2_dir = File.expand_path("../../../vendor/termbox2", __dir__)
        tb2_impl_c = File.join(tb2_dir, "termbox2_impl.c")
        tb2_impl_obj = File.join(tb2_dir, "termbox2_impl.o")

        return [] unless File.exist?(tb2_impl_c)

        cc, cc_flags = cross_cc_with_flags

        # Compile termbox2_impl.c (only if stale)
        unless File.exist?(tb2_impl_obj) && File.mtime(tb2_impl_obj) > File.mtime(tb2_impl_c)
          cmd = [*cc, "-c", "-O2"]
          cmd.concat(cc_flags)
          cmd += ["-o", tb2_impl_obj, tb2_impl_c]
          system(*cmd) or return []
        end

        [tb2_impl_obj]
      end

      def ffi_include_flags
        flags = []

        # Always add vendored Clay include path if Clay/ClayTUI stdlib is used
        clay_dir = File.expand_path("../../../vendor/clay", __dir__)
        if @extra_c_files.any? { |f| File.basename(f).include?("clay") } && Dir.exist?(clay_dir)
          flags << "-I#{clay_dir}"
        end

        # Add vendored termbox2 include path if ClayTUI stdlib is used
        tb2_dir = File.expand_path("../../../vendor/termbox2", __dir__)
        if @extra_c_files.any? { |f| File.basename(f).include?("clay_tui") } && Dir.exist?(tb2_dir)
          flags << "-I#{tb2_dir}"
        end

        if cross_compiling?
          # When cross-compiling, use cross library include paths
          flags << "-I#{@cross_libs_dir}/../include" if @cross_libs_dir && Dir.exist?("#{@cross_libs_dir}/../include")
        else
          # Add homebrew include paths for common libraries
          if Dir.exist?("/opt/homebrew/include")
            flags << "-I/opt/homebrew/include"
          end
        end
        flags
      end

      # Returns [cc_command_array, extra_flags_array] for compilation
      # When cross-compiling, uses `zig cc` with target; otherwise uses clang/cc
      def cross_cc_with_flags
        if cross_compiling?
          zig = Platform.find_zig
          raise CodegenError, "zig not found. Install zig for cross-compilation: https://ziglang.org/download/" unless zig

          zig_target = Platform.zig_target(@cross_target)
          [[zig, "cc"], ["-target", zig_target]]
        else
          cc = find_llvm_tool("clang") || "cc"
          [[cc], []]
        end
      end

      def find_llvm_tool(name)
        Platform.find_llvm_tool(name)
      end

      # Sort native classes in dependency order
      def topological_sort_native_classes(native_classes)
        sorted = []
        visited = {}

        visit = lambda do |name|
          return if visited[name]
          visited[name] = true
          class_type = native_classes[name]
          if class_type
            class_type.fields.each_value do |field_type|
              next if TypeChecker::Types::NativeClassType::ALLOWED_PRIMITIVE_TYPES.include?(field_type)
              next if TypeChecker::Types::NativeClassType::RUBY_OBJECT_TYPES.include?(field_type)
              next if field_type.is_a?(Hash)
              dep_name = field_type.to_sym
              visit.call(dep_name) if native_classes.key?(dep_name)
            end
          end
          sorted << name.to_s
        end

        native_classes.each_key { |name| visit.call(name) }
        sorted
      end

      def topological_sort_non_native_classes(classes)
        class_map = classes.map { |c| [c.name.to_s, c] }.to_h
        sorted = []
        visited = {}

        visit = lambda do |cls|
          return if visited[cls.name.to_s]
          visited[cls.name.to_s] = true
          if cls.superclass && class_map[cls.superclass.to_s]
            visit.call(class_map[cls.superclass.to_s])
          end
          sorted << cls
        end

        classes.each { |c| visit.call(c) }
        sorted
      end
    end
  end
end
