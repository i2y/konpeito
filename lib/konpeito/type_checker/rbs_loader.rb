# frozen_string_literal: true

require "rbs"
require "tmpdir"
require_relative "annotation_parser"

module Konpeito
  module TypeChecker
    # Loads and manages RBS type definitions
    class RBSLoader
      attr_reader :environment, :native_classes, :native_modules, :boxed_classes, :cfunc_methods, :ffi_libraries,
                  :extern_classes, :simd_classes, :jvm_classes

      def initialize
        @environment = nil
        @loaded = false
        @native_classes = {}  # class_name -> NativeClassType
        @native_modules = {}  # module_name -> NativeModuleType
        @boxed_classes = {}   # class_name -> true (explicitly boxed classes)
        @cfunc_methods = {}   # "ClassName.method_name" -> CFuncType
        @ffi_libraries = {}   # class/module_name -> library_name (e.g., :LibM -> "libm")
        @extern_classes = {}  # class_name -> ExternClassType (external C struct wrappers)
        @simd_classes = {}    # class_name -> SIMDClassType (SIMD vector classes)
        @jvm_classes = {}     # "Java::Util::ArrayList" -> { jvm_internal_name:, methods:, static_methods: }
        @rbs_file_contents = {}  # path -> content
        @temp_dirs = []  # Temp directories for single RBS files
        @definition_builder = nil  # Cached DefinitionBuilder
        @definition_cache = {}  # [type_name, singleton?] -> Definition
      end

      # Cleanup temp directories created for single RBS file loading
      def cleanup
        @temp_dirs.each do |dir|
          FileUtils.remove_entry(dir) if File.exist?(dir)
        rescue StandardError
          # Ignore cleanup errors
        end
        @temp_dirs.clear
      end

      # Load RBS definitions from standard library and optional paths
      # @param rbs_paths [Array<String>] User-specified RBS file paths
      # @param stdlib_libraries [Array<String>] Stdlib library names to load (e.g., ["json", "fileutils"])
      # @param inline_rbs_content [String, nil] RBS content generated from inline annotations
      def load(rbs_paths: [], stdlib_libraries: [], inline_rbs_content: nil)
        cleanup  # Clean up any temp dirs from previous load
        loader = RBS::EnvironmentLoader.new

        # Load stdlib libraries first (only if RBS definitions exist)
        stdlib_libraries.each do |lib_name|
          if stdlib_rbs_available?(lib_name)
            loader.add(library: lib_name)
          else
            warn "Warning: No RBS types available for stdlib '#{lib_name}'"
          end
        end

        # Add user-specified paths and store file contents for annotation parsing
        rbs_paths.each do |path|
          if File.directory?(path)
            loader.add(path: Pathname(path))
            Dir.glob(File.join(path, "**/*.rbs")).each do |file|
              @rbs_file_contents[file] = File.read(file)
            end
          elsif File.file?(path)
            # For single files, create a unique temp directory to avoid loading
            # other RBS files from the same directory (which could cause
            # DuplicatedMethodDefinitionError)
            content = File.read(path)
            @rbs_file_contents[path] = content

            temp_dir = Dir.mktmpdir("konpeito_rbs_")
            @temp_dirs << temp_dir
            temp_file = File.join(temp_dir, File.basename(path))
            File.write(temp_file, content)
            loader.add(path: Pathname(temp_dir))
          end
        end

        # Add inline RBS content if provided
        if inline_rbs_content && !inline_rbs_content.strip.empty?
          @rbs_file_contents["(inline)"] = inline_rbs_content

          temp_dir = Dir.mktmpdir("konpeito_inline_rbs_")
          @temp_dirs << temp_dir
          temp_file = File.join(temp_dir, "inline.rbs")
          File.write(temp_file, inline_rbs_content)
          loader.add(path: Pathname(temp_dir))
        end

        begin
          @environment = RBS::Environment.from_loader(loader).resolve_type_names
        rescue RBS::EnvironmentLoader::UnknownLibraryError => e
          # If stdlib loading fails, retry without it and emit warning
          warn "Warning: #{e.message}"
          # Create a fresh loader without the problematic stdlib libraries
          loader = RBS::EnvironmentLoader.new
          rbs_paths.each do |path|
            if File.directory?(path)
              loader.add(path: Pathname(path))
            elsif File.file?(path)
              # Re-add temp directory
              temp_dir = @temp_dirs.find { |d| File.exist?(File.join(d, File.basename(path))) }
              loader.add(path: Pathname(temp_dir)) if temp_dir
            end
          end
          @environment = RBS::Environment.from_loader(loader).resolve_type_names
        end
        invalidate_definition_cache!
        @loaded = true

        # Parse declarations from RBS AST (unified parsing)
        parse_declarations

        self
      end

      def loaded?
        @loaded
      end

      # Check if a class is a NativeClass
      def native_class?(class_name)
        @native_classes.key?(class_name.to_sym)
      end

      # Get NativeClassType for a class (returns nil if not native)
      def native_class_type(class_name)
        @native_classes[class_name.to_sym]
      end

      # Check if a module is a NativeModule
      def native_module?(module_name)
        @native_modules.key?(module_name.to_sym)
      end

      # Get NativeModuleType for a module (returns nil if not native)
      def native_module_type(module_name)
        @native_modules[module_name.to_sym]
      end

      # Check if a class is explicitly boxed (VALUE-based, for CRuby interop)
      def boxed_class?(class_name)
        @boxed_classes.key?(class_name.to_sym)
      end

      # Get CFuncType for a method (returns nil if not a cfunc)
      # @param class_name [Symbol, String] The class/module name
      # @param method_name [Symbol, String] The method name
      # @param singleton [Boolean] Whether this is a singleton (class) method
      # @return [Types::CFuncType, nil] The cfunc type if found
      def cfunc_method(class_name, method_name, singleton: false)
        key = singleton ? :"#{class_name}.#{method_name}" : :"#{class_name}##{method_name}"
        @cfunc_methods[key]
      end

      # Check if a method is a cfunc
      def cfunc_method?(class_name, method_name, singleton: false)
        !cfunc_method(class_name, method_name, singleton: singleton).nil?
      end

      # Get the FFI library name for a class/module
      # @param name [Symbol, String] The class or module name
      # @return [String, nil] The library name (e.g., "libm") or nil
      def ffi_library(name)
        @ffi_libraries[name.to_sym]
      end

      # Check if a class/module has an %a{ffi} annotation
      def ffi_library?(name)
        !ffi_library(name).nil?
      end

      # Get all FFI libraries used (for linking)
      # @return [Array<String>] Unique list of library names
      def all_ffi_libraries
        # Combine FFI libraries from cfunc modules and extern classes
        libs = @ffi_libraries.values.dup
        @extern_classes.each_value { |ext| libs << ext.ffi_library }
        libs.uniq
      end

      # Check if a class is an extern class (wrapping external C struct)
      def extern_class?(class_name)
        @extern_classes.key?(class_name.to_sym)
      end

      # Get ExternClassType for a class (returns nil if not extern)
      def extern_class_type(class_name)
        @extern_classes[class_name.to_sym]
      end

      # Check if a class is a SIMD class (vector operations)
      def simd_class?(class_name)
        @simd_classes.key?(class_name.to_sym)
      end

      # Get SIMDClassType for a class (returns nil if not simd)
      def simd_class_type(class_name)
        @simd_classes[class_name.to_sym]
      end

      # Get class definition by name
      def class_definition(name)
        ensure_loaded!
        type_name = parse_type_name(name)
        environment.class_decls[type_name]
      end

      # Check if a type exists in the environment
      def type_exists?(name)
        ensure_loaded!
        type_name = parse_type_name(name)
        environment.class_decls.key?(type_name)
      end

      # Parse a type string into an RBS type
      def parse_type(type_string)
        ensure_loaded!
        RBS::Parser.parse_type(type_string)
      end

      # Get instance methods for a class
      def instance_methods(class_name)
        ensure_loaded!

        type_name = parse_type_name(class_name)
        decl = environment.class_decls[type_name]
        return [] unless decl

        definition = build_definition(type_name, singleton: false)
        return [] unless definition

        definition.methods.keys
      end

      # Get method type for a class method
      def method_type(class_name, method_name, singleton: false)
        ensure_loaded!

        type_name = parse_type_name(class_name)
        decl = environment.class_decls[type_name]
        return nil unless decl

        definition = build_definition(type_name, singleton: singleton)
        return nil unless definition

        method = definition.methods[method_name.to_sym]
        return nil unless method

        method.defs.map(&:type)
      end

      # Directly look up method type from module/class declaration without building full definition.
      # This avoids expensive DefinitionBuilder and is faster for simple lookups.
      # Falls back to the full method_type if not found (to handle inheritance, mix-ins, etc.)
      def method_type_direct(class_name, method_name, singleton: false)
        ensure_loaded!

        type_name = parse_type_name(class_name)
        decl_entry = environment.class_decls[type_name]
        return method_type(class_name, method_name, singleton: singleton) unless decl_entry

        # Search in all declarations (handles reopened classes)
        decl_entry.decls.each do |d|
          decl = d.decl
          next unless decl.respond_to?(:members)

          decl.members.each do |member|
            case member
            when RBS::AST::Members::MethodDefinition
              # Check if this is the method we're looking for
              is_singleton = member.kind == :singleton
              next unless is_singleton == singleton && member.name == method_name.to_sym

              # Return the method types
              return member.overloads.map(&:method_type)
            end
          end
        end

        # Fall back to full definition builder (handles inheritance)
        method_type(class_name, method_name, singleton: singleton)
      end

      # Alias for backward compatibility
      alias direct_method_type method_type_direct

      # Look up a constant's type
      def constant_type(constant_name)
        ensure_loaded!

        type_name = parse_type_name(constant_name)
        environment.constant_decls[type_name]&.decl&.type
      end

      # Look up a global variable's type
      def global_variable_type(name)
        ensure_loaded!

        environment.global_decls[name.to_sym]&.decl&.type
      end

      # Get superclass of a class
      def superclass(class_name)
        ensure_loaded!

        type_name = parse_type_name(class_name)
        decl_entry = environment.class_decls[type_name]
        return nil unless decl_entry

        # Get the first declaration that has a superclass
        decl_entry.decls.each do |d|
          decl = d.decl
          return decl.super_class.name.name.to_s if decl.respond_to?(:super_class) && decl.super_class
        end

        nil
      end

      # Get all instance variables (with types) for a class
      def instance_variables(class_name)
        ensure_loaded!

        type_name = parse_type_name(class_name)
        decl_entry = environment.class_decls[type_name]
        return {} unless decl_entry

        ivars = {}

        decl_entry.decls.each do |d|
          decl = d.decl
          next unless decl.respond_to?(:members)

          decl.members.each do |member|
            case member
            when RBS::AST::Members::InstanceVariable
              ivars[member.name] = member.type
            end
          end
        end

        ivars
      end

      # Get all methods (with types) for a class or module
      def all_methods(class_name, singleton: false)
        ensure_loaded!

        type_name = parse_type_name(class_name)
        decl = environment.class_decls[type_name]
        return {} unless decl

        builder = RBS::DefinitionBuilder.new(env: environment)

        definition = if singleton
          builder.build_singleton(type_name)
        else
          builder.build_instance(type_name)
        end

        definition.methods.transform_values do |method|
          method.defs.map(&:type)
        end
      end

      # Get methods defined directly on a class (not inherited)
      def own_methods(class_name, singleton: false)
        ensure_loaded!

        type_name = parse_type_name(class_name)
        decl_entry = environment.class_decls[type_name]
        return {} unless decl_entry

        methods = {}

        decl_entry.decls.each do |d|
          decl = d.decl
          next unless decl.respond_to?(:members)

          decl.members.each do |member|
            case member
            when RBS::AST::Members::MethodDefinition
              is_singleton = member.kind == :singleton
              next unless is_singleton == singleton

              methods[member.name] = member.overloads.map(&:method_type)
            end
          end
        end

        methods
      end

      # Convert a type to its string representation
      def type_to_string(type)
        type.to_s
      end

      # Check if one RBS type is a subtype of another
      # @param sub_type [RBS::Types::t] The potential subtype
      # @param super_type [RBS::Types::t] The potential supertype
      # @return [Boolean] true if sub_type is a subtype of super_type
      def subtype?(sub_type, super_type)
        ensure_loaded!

        # Any (untyped) accepts all types
        return true if super_type.is_a?(RBS::Types::Bases::Any)

        # Same type
        return true if sub_type == super_type

        # ClassInstance comparison
        if sub_type.is_a?(RBS::Types::ClassInstance) && super_type.is_a?(RBS::Types::ClassInstance)
          return check_class_subtype(sub_type.name, super_type.name)
        end

        false
      end

      private

      # Check if one class is a subtype of another (based on inheritance)
      def check_class_subtype(sub_name, super_name)
        return true if sub_name == super_name

        # Get the class declaration
        decl_entry = environment.class_decls[sub_name]
        return false unless decl_entry

        # Check superclass chain
        decl_entry.decls.each do |d|
          decl = d.decl
          if decl.respond_to?(:super_class) && decl.super_class
            parent_name = decl.super_class.name
            return true if parent_name == super_name
            return true if check_class_subtype(parent_name, super_name)
          end
        end

        false
      end

      public

      # Check if stdlib RBS types are available for a library
      def stdlib_rbs_available?(lib_name)
        # Try to find the library in RBS's built-in paths
        begin
          test_loader = RBS::EnvironmentLoader.new
          test_loader.add(library: lib_name)
          true
        rescue RBS::EnvironmentLoader::UnknownLibraryError
          false
        end
      end

      def ensure_loaded!
        raise Error, "RBS environment not loaded. Call #load first." unless @loaded
      end

      # Cached DefinitionBuilder (one per environment)
      def definition_builder
        @definition_builder ||= RBS::DefinitionBuilder.new(env: environment)
      end

      # Build and cache a class/module definition
      def build_definition(type_name, singleton: false)
        cache_key = [type_name, singleton]
        return @definition_cache[cache_key] if @definition_cache.key?(cache_key)

        definition = begin
          if singleton
            definition_builder.build_singleton(type_name)
          else
            definition_builder.build_instance(type_name)
          end
        rescue RBS::NoTypeFoundError
          nil
        end

        @definition_cache[cache_key] = definition
        definition
      end

      # Invalidate definition caches (call when environment changes)
      def invalidate_definition_cache!
        @definition_builder = nil
        @definition_cache = {}
      end

      def parse_type_name(name)
        name_str = name.to_s
        if name_str.include?("::")
          # Nested class: "Ractor::Port" → name: :Port, namespace: ::Ractor::
          parts = name_str.split("::")
          short_name = parts.pop.to_sym
          namespace = RBS::Namespace.new(path: parts.map(&:to_sym), absolute: true)
          RBS::TypeName.new(namespace: namespace, name: short_name)
        else
          RBS::TypeName.new(namespace: RBS::Namespace.root, name: name.to_sym)
        end
      end

      # ============================================================
      # Unified Declaration Parsing (using RBS AST with %a{} annotations)
      # ============================================================

      # Parse all declarations from RBS file contents
      def parse_declarations
        @rbs_file_contents.each_value do |content|
          parse_declarations_from_content(content)
        end

        # Validate inheritance (superclasses must exist)
        validate_native_inheritance
      end

      # Parse declarations from RBS content using RBS AST
      # Recognizes %a{} annotations for:
      #   - %a{native}       - Native struct class
      #   - %a{native: vtable} - Native with dynamic dispatch
      #   - %a{extern}       - External C struct wrapper (requires %a{ffi})
      #   - %a{boxed}        - VALUE-based class
      #   - %a{struct}       - Value type (pass-by-value)
      #   - %a{simd}         - SIMD vector class
      #   - %a{ffi: "lib"}   - FFI library for class/module
      #   - %a{cfunc: "name"} - C function binding for method
      #   - %a{cfunc}        - C function (use method name)
      def parse_declarations_from_content(content)
        buffer = RBS::Buffer.new(name: "(inline)", content: content)
        _, _, declarations = RBS::Parser.parse_signature(buffer)

        declarations.each do |decl|
          case decl
          when RBS::AST::Declarations::Class
            parse_class_declaration(decl)
          when RBS::AST::Declarations::Module
            parse_module_declaration(decl)
          end
        end
      rescue RBS::ParsingError => e
        warn "Warning: RBS parsing error: #{e.message}"
      end

      # Parse a class declaration
      def parse_class_declaration(decl)
        class_name = decl.name.name

        # Check for Java:: namespace prefix (JVM interop class)
        full_name = decl.name.to_s.delete_prefix("::")
        if full_name.start_with?("Java::")
          parse_jvm_class(decl, full_name)
          return
        end

        annotations = AnnotationParser.parse_all(decl.annotations)

        # Skip built-in types
        if builtin_type?(class_name)
          return
        end

        # Check for %a{ffi: "lib"} at class level
        ffi_ann = AnnotationParser.find(annotations, :ffi)
        @ffi_libraries[class_name] = ffi_ann[:library] if ffi_ann

        # Check for %a{boxed}
        if AnnotationParser.has?(annotations, :boxed)
          @boxed_classes[class_name] = true
          return
        end

        # Check for %a{extern} (requires ffi)
        if AnnotationParser.has?(annotations, :extern)
          parse_extern_class(decl, ffi_ann)
          return
        end

        # Check for %a{simd}
        if AnnotationParser.has?(annotations, :simd)
          parse_simd_class(decl)
          return
        end

        # Check for %a{struct} (value type)
        is_struct = AnnotationParser.has?(annotations, :struct)

        # Check for %a{native} with options
        native_ann = AnnotationParser.find(annotations, :native)
        use_vtable = native_ann&.dig(:vtable) || false

        # Parse fields and methods
        fields = {}
        methods = {}
        superclass_name = decl.super_class&.name&.name

        decl.members.each do |member|
          case member
          when RBS::AST::Members::InstanceVariable
            # Strip @ prefix from instance variable name (e.g., :@x -> :x)
            field_name = member.name.to_s.delete_prefix("@").to_sym
            native_type = convert_rbs_type_to_native_field(member.type)
            fields[field_name] = native_type if native_type
          when RBS::AST::Members::MethodDefinition
            # Parse method annotations for cfunc
            method_annotations = AnnotationParser.parse_all(member.annotations)
            cfunc_ann = AnnotationParser.find(method_annotations, :cfunc)

            if cfunc_ann
              parse_cfunc_method(class_name, member, cfunc_ann)
            else
              # Skip field accessors
              field_base = member.name.to_s.chomp("=").to_sym
              is_accessor = fields.key?(field_base) ||
                            (superclass_name && will_inherit_field?(superclass_name, field_base))
              next if is_accessor
              next if member.kind == :singleton  # Skip constructors

              method_type = parse_native_method(member, class_name)
              methods[member.name] = method_type if method_type
            end
          end
        end

        # Create NativeClassType if has fields or methods
        return if fields.empty? && methods.empty?

        native_type = Types::NativeClassType.new(
          class_name,
          fields,
          methods,
          superclass: superclass_name,
          vtable: use_vtable,
          is_value_type: is_struct
        )

        # Validate value type constraints
        if is_struct
          valid, error_msg = native_type.valid_value_type?
          unless valid
            warn "Warning: %a{struct} #{class_name} is invalid: #{error_msg}"
            native_type.is_value_type = false
          end
        end

        @native_classes[class_name] = native_type
      end

      # Parse a module declaration
      def parse_module_declaration(decl)
        module_name = decl.name.name
        annotations = AnnotationParser.parse_all(decl.annotations)

        # Check for %a{ffi: "lib"}
        ffi_ann = AnnotationParser.find(annotations, :ffi)
        @ffi_libraries[module_name] = ffi_ann[:library] if ffi_ann

        # Check for %a{jvm_static: "..."} module (maps to external Java class)
        jvm_static_ann = AnnotationParser.find(annotations, :jvm_static)
        if jvm_static_ann
          parse_jvm_static_module(decl, jvm_static_ann[:java_class])
          return
        end

        # Check for %a{native} module
        if AnnotationParser.has?(annotations, :native)
          parse_native_module(decl)
          return
        end

        # Parse methods for cfunc annotations
        decl.members.each do |member|
          next unless member.is_a?(RBS::AST::Members::MethodDefinition)

          method_annotations = AnnotationParser.parse_all(member.annotations)
          cfunc_ann = AnnotationParser.find(method_annotations, :cfunc)
          parse_cfunc_method(module_name, member, cfunc_ann) if cfunc_ann
        end
      end

      # Parse a native module (with %a{native})
      def parse_native_module(decl)
        module_name = decl.name.name
        methods = {}

        decl.members.each do |member|
          next unless member.is_a?(RBS::AST::Members::MethodDefinition)

          method_type = parse_native_method(member, module_name)
          methods[member.name] = method_type if method_type
        end

        return if methods.empty?

        @native_modules[module_name] = Types::NativeModuleType.new(module_name, methods)
      end

      # Parse an extern class (with %a{extern})
      def parse_extern_class(decl, ffi_ann)
        class_name = decl.name.name

        unless ffi_ann
          warn "Warning: %a{extern} class #{class_name} requires %a{ffi} annotation, skipping"
          return
        end

        extern_methods = {}

        decl.members.each do |member|
          next unless member.is_a?(RBS::AST::Members::MethodDefinition)

          overload = member.overloads.first
          next unless overload

          func_type = overload.method_type.type
          return_type_str = rbs_type_to_string(func_type.return_type)
          param_types = parse_extern_params(func_type)
          return_type = parse_extern_return_type(return_type_str, class_name)

          is_singleton = member.kind == :singleton
          is_constructor = is_singleton && (return_type == :ptr || return_type_str == class_name.to_s)

          # Instance methods receive opaque pointer as first param
          unless is_singleton
            param_types = [:ptr] + param_types
          end

          extern_methods[member.name] = Types::ExternMethodType.new(
            member.name.to_s,
            param_types,
            is_constructor ? :ptr : return_type,
            is_constructor: is_constructor
          )
        end

        @extern_classes[class_name] = Types::ExternClassType.new(
          class_name,
          ffi_ann[:library],
          extern_methods
        )
      end

      # Parse a SIMD class (with %a{simd})
      def parse_simd_class(decl)
        class_name = decl.name.name
        field_names = []
        simd_methods = {}

        decl.members.each do |member|
          case member
          when RBS::AST::Members::InstanceVariable
            # Strip @ prefix from instance variable name
            field_name = member.name.to_s.delete_prefix("@").to_sym
            type_str = rbs_type_to_string(member.type)
            unless type_str == "Float"
              warn "Warning: %a{simd} class #{class_name} field '#{field_name}' must be Float, got #{type_str}"
              next
            end
            field_names << field_name
          when RBS::AST::Members::MethodDefinition
            # Skip field accessors
            field_base = member.name.to_s.chomp("=").to_sym
            next if field_names.include?(field_base)
            next if member.kind == :singleton

            method_type = parse_simd_method(member, class_name)
            simd_methods[member.name] = method_type if method_type
          end
        end

        # Validate SIMD field count
        unless Types::SIMDClassType::ALLOWED_WIDTHS.include?(field_names.size)
          warn "Warning: %a{simd} class #{class_name} must have #{Types::SIMDClassType::ALLOWED_WIDTHS.join('/')} Float fields, got #{field_names.size}"
          return
        end

        @simd_classes[class_name] = Types::SIMDClassType.new(class_name, field_names, simd_methods)
      end

      # Parse a JVM interop class (Java:: namespace prefix)
      # e.g., class Java::Util::ArrayList → java/util/ArrayList
      def parse_jvm_class(decl, full_name)
        # Convert Java::Util::ArrayList → java/util/ArrayList
        # All segments form the Java class path; package segments are lowercased
        segments = full_name.split("::")
        jvm_segments = segments.each_with_index.map do |seg, i|
          i < segments.size - 1 ? seg[0].downcase + seg[1..] : seg
        end
        jvm_internal_name = jvm_segments.join("/")

        methods = {}
        static_methods = {}
        constructor_params = nil

        decl.members.each do |member|
          next unless member.is_a?(RBS::AST::Members::MethodDefinition)

          overload = member.overloads.first
          next unless overload

          func_type = overload.method_type.type
          param_types = func_type.required_positionals.map { |p| jvm_rbs_type_to_tag(p.type) }
          return_type = jvm_rbs_type_to_tag(func_type.return_type)

          method_name = member.name.to_s

          if member.kind == :singleton
            if method_name == "new"
              # Constructor: store param types for <init> descriptor
              constructor_params = param_types
              # Return type of constructor is the class itself
              return_type = :value
            else
              static_methods[method_name] = { params: param_types, return: return_type }
            end
          else
            # Check if return type is the same class (for method chaining)
            # Use full qualified name from RBS type for Java:: classes
            ret_type_obj = func_type.return_type
            if ret_type_obj.is_a?(RBS::Types::ClassInstance)
              ret_full_name = ret_type_obj.name.to_s
            else
              ret_full_name = rbs_type_to_string(ret_type_obj)
            end
            return_class = (ret_full_name == full_name) ? full_name : nil

            methods[method_name] = {
              params: param_types,
              return: return_type,
              return_class: return_class
            }
          end
        end

        @jvm_classes[full_name] = {
          jvm_internal_name: jvm_internal_name,
          methods: methods,
          static_methods: static_methods,
          constructor_params: constructor_params
        }
      end

      # Parse a module with %a{jvm_static: "java/class/Name"} annotation.
      # Maps a Ruby module to an external Java class's static methods.
      def parse_jvm_static_module(decl, java_class)
        module_name = decl.name.to_s.delete_prefix("::")
        static_methods = {}

        decl.members.each do |member|
          next unless member.is_a?(RBS::AST::Members::MethodDefinition)
          next unless member.kind == :singleton # def self.xxx only

          overload = member.overloads.first
          next unless overload

          func_type = overload.method_type.type
          param_types = func_type.required_positionals.map { |p| jvm_rbs_type_to_tag(p.type) }
          return_type = jvm_rbs_type_to_tag(func_type.return_type)

          method_name = member.name.to_s
          java_method_name = snake_to_camel(method_name)

          method_info = { params: param_types, return: return_type, java_name: java_method_name }

          # Check for %a{callback: "..." descriptor: "..."} annotation on method
          method_annotations = AnnotationParser.parse_all(member.annotations)
          callback_ann = AnnotationParser.find(method_annotations, :callback)
          if callback_ann
            cb_info = { interface: callback_ann[:interface] }
            if callback_ann[:descriptor]
              cb_info[:descriptor] = callback_ann[:descriptor]
              cb_info[:param_types] = parse_callback_descriptor_params(callback_ann[:descriptor])
              cb_info[:return_type] = parse_callback_descriptor_return(callback_ann[:descriptor])
            end
            method_info[:block_callback] = cb_info
          end

          static_methods[method_name] = method_info
        end

        @jvm_classes[module_name] = {
          jvm_internal_name: java_class,
          methods: {},
          static_methods: static_methods,
          constructor_params: nil,
          jvm_static_module: true
        }
      end

      # Convert snake_case to camelCase (e.g., "set_background" -> "setBackground")
      def snake_to_camel(name)
        parts = name.split("_")
        parts[0] + parts[1..].map(&:capitalize).join
      end

      # Convert camelCase to snake_case (e.g., "setBackground" -> "set_background")
      def camel_to_snake(name)
        name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      # Register Java:: references found by AST pre-scan.
      # Introspects the classpath for the referenced classes and auto-registers them
      # in @jvm_classes so that load_classpath_types can supplement their methods.
      def register_java_references(java_refs, classpath)
        refs = java_refs[:refs]
        aliases = java_refs[:aliases]

        # Skip classes already registered via RBS
        new_refs = refs.reject { |ruby_name, _| @jvm_classes.key?(ruby_name) }
        return if new_refs.empty?

        # Introspect the classpath for referenced classes
        target_classes = new_refs.values
        introspect_json = run_introspector(classpath, target_classes)
        return unless introspect_json

        # Build SAM interface map from all introspected classes
        sam_interfaces = build_sam_interface_map(introspect_json)

        # Register each class in @jvm_classes
        new_refs.each do |ruby_name, jvm_internal|
          class_data = introspect_json.dig("classes", jvm_internal)
          next unless class_data

          register_introspected_class(ruby_name, jvm_internal, class_data, sam_interfaces)
        end

        # Register aliases: KCanvas → same data as Java::Konpeito::Canvas::Canvas
        aliases.each do |alias_name, java_path|
          next if @jvm_classes.key?(alias_name)

          source = @jvm_classes[java_path]
          @jvm_classes[alias_name] = source.dup if source
        end
      end

      # Load type information from classpath JAR/class files.
      # Supplements @jvm_classes entries that were registered from RBS but may lack
      # method signatures. RBS-defined methods take priority; missing ones are filled
      # from classpath introspection.
      def load_classpath_types(classpath)
        return unless classpath

        target_classes = @jvm_classes.values.map { |info| info[:jvm_internal_name] }.compact
        return if target_classes.empty?

        introspect_json = run_introspector(classpath, target_classes)
        return unless introspect_json

        merge_introspected_types(introspect_json)
      end

      # Parse param types from a JVM method descriptor (e.g., "(DD)V" -> [:double, :double])
      def parse_callback_descriptor_params(descriptor)
        return [] unless descriptor =~ /\A\(([^)]*)\)/

        params_str = ::Regexp.last_match(1)
        types = []
        i = 0
        while i < params_str.length
          case params_str[i]
          when "I" then types << :i64; i += 1
          when "J" then types << :i64; i += 1
          when "D" then types << :double; i += 1
          when "F" then types << :double; i += 1
          when "Z" then types << :i8; i += 1
          when "L"
            # Object type: skip to ;
            semi = params_str.index(";", i)
            class_name = params_str[(i + 1)...semi]
            types << if class_name == "java/lang/String"
                       :string
                     else
                       :value
                     end
            i = semi + 1
          else
            types << :value; i += 1
          end
        end
        types
      end

      # Parse return type from a JVM method descriptor (e.g., "(DD)V" -> :void)
      def parse_callback_descriptor_return(descriptor)
        return :void unless descriptor =~ /\)(.+)\z/

        ret = ::Regexp.last_match(1)
        case ret
        when "V" then :void
        when "I", "J" then :i64
        when "D", "F" then :double
        when "Z" then :i8
        when "Ljava/lang/String;" then :string
        else :value
        end
      end

      # Convert RBS type to JVM interop type tag
      # Returns a symbol tag or a string for Java class references (e.g., "java/util/ArrayList")
      def jvm_rbs_type_to_tag(type)
        # For ClassInstance types, check full qualified name for Java:: prefix
        if type.is_a?(RBS::Types::ClassInstance)
          full_name = type.name.to_s
          if full_name.start_with?("Java::")
            # Return the JVM internal name as a string tag (e.g., "java/lang/StringBuilder")
            segments = full_name.split("::")
            jvm_segs = segments.each_with_index.map { |s, i| i < segments.size - 1 ? s[0].downcase + s[1..] : s }
            return jvm_segs.join("/")
          end
        end

        type_str = rbs_type_to_string(type)
        case type_str
        when "Integer" then :i64
        when "Float" then :double
        when "String" then :string
        when "Bool", "bool" then :i8
        when "void" then :void
        else :value  # Object, untyped, etc.
        end
      end

      # Check if a class name is a JVM interop class
      def jvm_class?(name)
        @jvm_classes.key?(name.to_s)
      end

      # Run the KonpeitoAssembler --introspect subprocess to extract type info from classpath.
      # Returns parsed JSON hash or nil on failure.
      def run_introspector(classpath, target_classes)
        asm_jar = File.expand_path("../../../tools/konpeito-asm/konpeito-asm.jar", __dir__)
        return nil unless File.exist?(asm_jar)

        java_home = ENV["JAVA_HOME"] || Platform.default_java_home
        java_cmd = File.join(java_home, "bin", "java")
        unless File.exist?(java_cmd)
          java_cmd = Platform.find_executable("java") || "java"
        end

        request = { "classpath" => classpath, "classes" => target_classes }
        request_json = JSON.generate(request)

        cmd = [java_cmd, "-jar", asm_jar, "--introspect"]
        output = nil
        IO.popen(cmd, "r+", err: File::NULL) do |io|
          io.write(request_json)
          io.close_write
          output = io.read
        end

        return nil unless $?.success? && output && !output.strip.empty?

        JSON.parse(output)
      rescue StandardError => e
        $stderr.puts "[DEBUG] run_introspector error: #{e.class}: #{e.message}" if ENV["KONPEITO_DEBUG"]
        nil
      end

      # Merge introspected class info into @jvm_classes.
      # RBS-defined methods take priority; classpath fills in missing ones.
      def merge_introspected_types(introspect_data)
        classes_data = introspect_data["classes"]
        return unless classes_data

        # Build SAM interface map from inner classes:
        # { "konpeito/canvas/KCanvas$MouseCallback" => { method: "call", descriptor: "(DD)V" } }
        sam_interfaces = {}
        classes_data.each_value do |class_info|
          inner_classes = class_info["inner_classes"] || {}
          inner_classes.each do |inner_name, inner_info|
            next unless inner_info["is_interface"]

            abstract_methods = inner_info["abstract_methods"] || {}
            if abstract_methods.size == 1
              method_name, method_info = abstract_methods.first
              sam_interfaces[inner_name] = {
                method: method_name,
                descriptor: method_info["descriptor"]
              }
            end
          end
        end

        # Merge into each @jvm_classes entry
        @jvm_classes.each do |ruby_name, jvm_info|
          jvm_internal = jvm_info[:jvm_internal_name]
          class_data = classes_data[jvm_internal]
          next unless class_data

          existing_static = jvm_info[:static_methods] || {}
          introspected_static = class_data["static_methods"] || {}

          introspected_static.each do |java_method_name, method_data|
            ruby_method_name = camel_to_snake(java_method_name)

            # Skip if already defined in RBS
            next if existing_static.key?(ruby_method_name)

            descriptor = method_data["descriptor"]
            param_types = parse_callback_descriptor_params(descriptor)
            return_type = parse_callback_descriptor_return(descriptor)

            method_info = {
              params: param_types,
              return: return_type,
              java_name: java_method_name
            }

            # Auto-detect SAM callback parameters:
            # If a parameter type is a SAM interface, convert to block_callback
            # and remove the SAM parameter from the param list
            raw_param_types = parse_descriptor_raw_params(descriptor)
            sam_param_idx = nil
            raw_param_types.each_with_index do |raw_type, idx|
              if raw_type.is_a?(String) && sam_interfaces.key?(raw_type)
                sam_param_idx = idx
                break
              end
            end

            if sam_param_idx
              sam_info = sam_interfaces[raw_param_types[sam_param_idx]]
              method_info[:block_callback] = {
                interface: raw_param_types[sam_param_idx],
                descriptor: sam_info[:descriptor],
                param_types: parse_callback_descriptor_params(sam_info[:descriptor]),
                return_type: parse_callback_descriptor_return(sam_info[:descriptor])
              }
              # Remove the SAM parameter from the param list
              method_info[:params].delete_at(sam_param_idx)
            end

            existing_static[ruby_method_name] = method_info
          end

          jvm_info[:static_methods] = existing_static

          # Also merge instance methods
          existing_methods = jvm_info[:methods] || {}
          introspected_methods = class_data["methods"] || {}

          introspected_methods.each do |java_method_name, method_data|
            ruby_method_name = camel_to_snake(java_method_name)
            next if existing_methods.key?(ruby_method_name)

            descriptor = method_data["descriptor"]
            param_types = parse_callback_descriptor_params(descriptor)
            return_type = parse_callback_descriptor_return(descriptor)

            existing_methods[ruby_method_name] = {
              params: param_types,
              return: return_type
            }
          end

          jvm_info[:methods] = existing_methods

          # Merge constructor if not already defined
          if jvm_info[:constructor_params].nil? && class_data["constructor"]
            ctor_desc = class_data["constructor"]["descriptor"]
            jvm_info[:constructor_params] = parse_callback_descriptor_params(ctor_desc) if ctor_desc
          end
        end
      end

      # Build SAM (Single Abstract Method) interface map from introspection data.
      # Returns { "pkg/Class$Interface" => { method: "call", descriptor: "(DD)V" } }
      def build_sam_interface_map(introspect_data)
        sam_interfaces = {}
        classes_data = introspect_data["classes"] || {}
        classes_data.each_value do |class_info|
          inner_classes = class_info["inner_classes"] || {}
          inner_classes.each do |inner_name, inner_info|
            next unless inner_info["is_interface"]

            abstract_methods = inner_info["abstract_methods"] || {}
            if abstract_methods.size == 1
              method_name, method_info = abstract_methods.first
              sam_interfaces[inner_name] = {
                method: method_name,
                descriptor: method_info["descriptor"]
              }
            end
          end
        end
        sam_interfaces
      end

      # Register one introspected class in @jvm_classes (auto-registered without RBS).
      def register_introspected_class(ruby_name, jvm_internal, class_data, sam_interfaces)
        static_methods = {}
        (class_data["static_methods"] || {}).each do |java_name, info|
          ruby_method = camel_to_snake(java_name)
          descriptor = info["descriptor"]
          method_info = {
            params: parse_callback_descriptor_params(descriptor),
            return: parse_callback_descriptor_return(descriptor),
            java_name: java_name
          }
          # Auto-detect SAM callback parameters
          detect_sam_callback!(method_info, descriptor, sam_interfaces)
          static_methods[ruby_method] = method_info
        end

        methods = {}
        (class_data["methods"] || {}).each do |java_name, info|
          ruby_method = camel_to_snake(java_name)
          descriptor = info["descriptor"]
          method_info = {
            params: parse_callback_descriptor_params(descriptor),
            return: parse_callback_descriptor_return(descriptor),
            java_name: java_name
          }
          # Auto-detect SAM callback on instance methods too
          detect_sam_callback!(method_info, descriptor, sam_interfaces)
          methods[ruby_method] = method_info
        end

        constructor_params = nil
        if class_data["constructor"]
          ctor_desc = class_data["constructor"]["descriptor"]
          constructor_params = parse_callback_descriptor_params(ctor_desc) if ctor_desc
        end

        @jvm_classes[ruby_name] = {
          jvm_internal_name: jvm_internal,
          methods: methods,
          static_methods: static_methods,
          constructor_params: constructor_params,
          auto_registered: true
        }
      end

      # Detect SAM callback parameters in a method and update method_info in-place.
      def detect_sam_callback!(method_info, descriptor, sam_interfaces)
        raw_param_types = parse_descriptor_raw_params(descriptor)
        sam_param_idx = nil
        raw_param_types.each_with_index do |raw_type, idx|
          if raw_type.is_a?(String) && sam_interfaces.key?(raw_type)
            sam_param_idx = idx
            break
          end
        end

        return unless sam_param_idx

        sam_info = sam_interfaces[raw_param_types[sam_param_idx]]
        method_info[:block_callback] = {
          interface: raw_param_types[sam_param_idx],
          descriptor: sam_info[:descriptor],
          param_types: parse_callback_descriptor_params(sam_info[:descriptor]),
          return_type: parse_callback_descriptor_return(sam_info[:descriptor])
        }
        # Remove the SAM parameter from the param list
        method_info[:params].delete_at(sam_param_idx)
      end

      # Parse raw parameter types from descriptor, returning class names as strings
      # for L...;  types (needed for SAM interface detection).
      # e.g., "(Lkonpeito/canvas/KCanvas$MouseCallback;)V" -> ["konpeito/canvas/KCanvas$MouseCallback"]
      def parse_descriptor_raw_params(descriptor)
        return [] unless descriptor =~ /\A\(([^)]*)\)/

        params_str = ::Regexp.last_match(1)
        types = []
        i = 0
        while i < params_str.length
          case params_str[i]
          when "I", "J", "D", "F", "Z", "B", "C", "S"
            types << params_str[i]
            i += 1
          when "L"
            semi = params_str.index(";", i)
            class_name = params_str[(i + 1)...semi]
            types << class_name
            i = semi + 1
          when "["
            # Array type: skip dimension prefix
            types << :array
            i += 1
            # Skip element type
            if params_str[i] == "L"
              semi = params_str.index(";", i)
              i = semi + 1
            else
              i += 1
            end
          else
            types << :unknown
            i += 1
          end
        end
        types
      end

      # Parse a cfunc method (with %a{cfunc} or %a{cfunc: "name"})
      def parse_cfunc_method(context_name, member, cfunc_ann)
        overload = member.overloads.first
        return unless overload

        func_type = overload.method_type.type
        c_func_name = cfunc_ann[:c_name] || member.name.to_s

        param_types = func_type.required_positionals.map do |param|
          parse_cfunc_type(rbs_type_to_string(param.type))
        end

        return_type = parse_cfunc_type(rbs_type_to_string(func_type.return_type))

        cfunc_type = Types::CFuncType.new(c_func_name, param_types, return_type)
        singleton = member.kind == :singleton
        key = singleton ? :"#{context_name}.#{member.name}" : :"#{context_name}##{member.name}"
        @cfunc_methods[key] = cfunc_type
      end

      # Parse a native method from RBS AST
      def parse_native_method(member, class_name)
        overload = member.overloads.first
        return nil unless overload

        func_type = overload.method_type.type
        param_types = []
        param_names = []

        func_type.required_positionals.each do |param|
          param_types << convert_to_native_return_type(rbs_type_to_string(param.type), class_name)
          param_names << (param.name || :"arg#{param_names.size}")
        end

        return_type = convert_to_native_return_type(rbs_type_to_string(func_type.return_type), class_name)

        Types::NativeMethodType.new(param_types, return_type, param_names: param_names)
      end

      # Parse a SIMD method from RBS AST
      def parse_simd_method(member, class_name)
        overload = member.overloads.first
        return nil unless overload

        func_type = overload.method_type.type
        param_types = []
        param_names = []

        func_type.required_positionals.each do |param|
          type_str = rbs_type_to_string(param.type)
          param_types << parse_simd_type(type_str, class_name)
          param_names << (param.name || :"arg#{param_names.size}")
        end

        return_type = parse_simd_type(rbs_type_to_string(func_type.return_type), class_name)

        Types::NativeMethodType.new(param_types, return_type, param_names: param_names)
      end

      # Parse extern method parameters
      def parse_extern_params(func_type)
        func_type.required_positionals.map do |param|
          parse_extern_type(rbs_type_to_string(param.type))
        end
      end

      # ============================================================
      # Type Conversion Helpers
      # ============================================================

      # Convert RBS type to string representation
      def rbs_type_to_string(type)
        case type
        when RBS::Types::ClassInstance
          base_name = type.name.name.to_s
          if type.args.empty?
            base_name
          else
            # Handle generic types: NativeHash[String, Integer] -> "NativeHash[String, Integer]"
            args_str = type.args.map { |a| rbs_type_to_string(a) }.join(", ")
            "#{base_name}[#{args_str}]"
          end
        when RBS::Types::Bases::Bool
          "Bool"
        when RBS::Types::Bases::Void
          "void"
        when RBS::Types::Bases::Nil
          "nil"
        when RBS::Types::Optional
          rbs_type_to_string(type.type) + "?"
        when RBS::Types::Literal
          # Handle literal types (e.g., 4 in StaticArray[Float, 4])
          type.literal.to_s
        else
          type.to_s
        end
      end

      # Convert RBS type to native field type
      def convert_rbs_type_to_native_field(type)
        type_str = rbs_type_to_string(type)
        is_optional = type.is_a?(RBS::Types::Optional)
        base_type_str = type_str.chomp("?")

        convert_to_native_field_type(base_type_str, is_optional)
      end

      # Convert RBS type string to native field type
      def convert_to_native_field_type(type_str, is_optional = false)
        case type_str
        when "Float", "Float64" then :Float64
        when "Integer", "Int64" then :Int64
        when "Bool", "bool" then :Bool
        when "String" then :String
        when "Array" then :Array
        when "Hash" then :Hash
        when "Object", "untyped" then :Object
        else
          # Could be a NativeClass type
          if is_optional
            # Optional NativeClass = reference (stored as VALUE), can be nil
            { ref: type_str.to_sym }
          else
            # Non-optional = embedded (stored as struct)
            type_str.to_sym
          end
        end
      end

      # Convert RBS type string to native method return/param type
      def convert_to_native_return_type(type_str, class_name)
        case type_str
        when "Float", "Float64" then :Float64
        when "Integer", "Int64" then :Int64
        when "void", "Void", "nil" then :Void
        when class_name.to_s then :Self
        else
          type_str.to_sym
        end
      end

      # Convert type string to cfunc type symbol
      def parse_cfunc_type(type_str)
        case type_str.strip
        when "Float" then :Float
        when "Integer" then :Integer
        when "String" then :String
        when "Bool", "bool" then :Bool
        when "void", "nil" then :void
        else type_str.to_sym
        end
      end

      # Convert type string to extern type symbol
      def parse_extern_type(type_str)
        case type_str.strip
        when "Float" then :Float
        when "Integer" then :Integer
        when "String" then :String
        when "Bool", "bool" then :Bool
        when "Array" then :Array
        when "Hash" then :Hash
        when "void", "nil" then :void
        else :ptr  # Unknown types are treated as opaque pointers
        end
      end

      # Parse extern class return type
      def parse_extern_return_type(type_str, class_name)
        case type_str
        when class_name.to_s then :ptr  # Return Self = return opaque pointer
        when "void", "nil" then :void
        else parse_extern_type(type_str)
        end
      end

      # Convert type string to SIMD type symbol
      def parse_simd_type(type_str, class_name)
        case type_str
        when class_name.to_s then :Self
        when "Float", "Float64" then :Float64
        when "void", "nil" then :Void
        else type_str.to_sym
        end
      end

      # Check if class is a built-in type that should be skipped
      def builtin_type?(class_name)
        name_str = class_name.to_s
        # Extract base name (before '[' if generic)
        base_name = name_str.split("[").first

        # Check for generic built-in types
        %w[NativeArray NativeHash StaticArray Slice ByteBuffer ByteSlice StringBuffer NativeString].include?(base_name) ||
          # Legacy class name encoding patterns (backward compatibility)
          name_str.match?(/\AStaticArray\d+(Float|Int)\z/) ||
          name_str.match?(/\ASlice(Int64|Float64)\z/) ||
          name_str.match?(/\ANativeHash(String|Symbol|Integer)(Integer|Float|Bool|String|Object|Array|Hash|\w+)\z/)
      end

      # Parse generic native type from RBS ClassInstance
      # Returns hash with type info, or nil if not a generic native type
      def parse_generic_native_type(type)
        return nil unless type.is_a?(RBS::Types::ClassInstance)
        return nil if type.args.empty?

        base_name = type.name.name.to_s
        args = type.args

        case base_name
        when "NativeHash"
          return nil unless args.size == 2
          {
            type: :native_hash,
            key_type: resolve_generic_type_arg(args[0]),
            value_type: resolve_generic_type_arg(args[1])
          }
        when "NativeArray"
          return nil unless args.size == 1
          {
            type: :native_array,
            element_type: resolve_generic_type_arg(args[0])
          }
        when "StaticArray"
          return nil unless args.size == 2
          {
            type: :static_array,
            element_type: resolve_generic_type_arg(args[0]),
            size: resolve_literal_arg(args[1])
          }
        when "Slice"
          return nil unless args.size == 1
          {
            type: :slice,
            element_type: resolve_generic_type_arg(args[0])
          }
        else
          nil
        end
      end

      # Resolve a generic type argument to internal type symbol
      def resolve_generic_type_arg(arg)
        case arg
        when RBS::Types::ClassInstance
          name = arg.name.name.to_s
          case name
          when "Integer", "Int64" then :Integer
          when "Float", "Float64" then :Float
          when "Bool", "bool" then :Bool
          when "String" then :String
          when "Symbol" then :Symbol
          when "Array" then :Array
          when "Hash" then :Hash
          when "Object" then :Object
          else
            # Could be a NativeClass type
            name.to_sym
          end
        when RBS::Types::Bases::Bool
          :Bool
        else
          arg.to_s.to_sym
        end
      end

      # Resolve a literal argument (for StaticArray size)
      def resolve_literal_arg(arg)
        case arg
        when RBS::Types::Literal
          arg.literal
        when RBS::Types::ClassInstance
          # Might be a constant reference, try to parse as integer
          arg.name.name.to_s.to_i
        else
          arg.to_s.to_i
        end
      end

      # Check if a superclass has a field (for accessor detection)
      def will_inherit_field?(superclass_name, field_name)
        parent = @native_classes[superclass_name]
        return false unless parent
        return true if parent.fields.key?(field_name)
        return false unless parent.superclass

        will_inherit_field?(parent.superclass, field_name)
      end

      # Validate that all superclasses and embedded types exist
      def validate_native_inheritance
        @native_classes.each do |class_name, class_type|
          # Set registry for embedded type resolution
          class_type.native_class_registry = @native_classes

          # Validate superclass
          if class_type.superclass && !@native_classes.key?(class_type.superclass)
            raise Error, "NativeClass #{class_name} inherits from unknown class #{class_type.superclass}"
          end

          # Validate embedded and reference NativeClass field types
          class_type.fields.each do |field_name, field_type|
            next if Types::NativeClassType::ALLOWED_PRIMITIVE_TYPES.include?(field_type)
            next if Types::NativeClassType::RUBY_OBJECT_TYPES.include?(field_type)

            # Check for reference types (Hash with :ref key)
            if field_type.is_a?(Hash) && field_type[:ref]
              ref_class = field_type[:ref]
              unless @native_classes.key?(ref_class)
                raise Error, "NativeClass #{class_name} has field '#{field_name}' referencing unknown type #{ref_class}"
              end
              next
            end

            # Embedded NativeClass
            unless @native_classes.key?(field_type)
              raise Error, "NativeClass #{class_name} has field '#{field_name}' with unknown type #{field_type}"
            end
          end
        end
      end
    end
  end
end
