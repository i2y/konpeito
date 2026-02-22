# frozen_string_literal: true

require "json"
require "set"

module Konpeito
  module Codegen
    # Generates JVM bytecode IR (JSON format) from HIR.
    # The JSON IR is consumed by the ASM wrapper tool to produce .class files.
    class JVMGenerator
      attr_reader :hir_program, :class_defs

      JAVA_PACKAGE = "konpeito/generated"

      # Standard Library module registry
      # Maps Ruby module names to Java runtime class + method descriptors
      STDLIB_MODULES = {
        "KonpeitoJSON" => {
          runtime_class: "konpeito/runtime/KJSON",
          methods: {
            "parse" => { java_name: "parse", descriptor: "(Ljava/lang/String;)Ljava/lang/Object;", return_type: :value },
            "generate" => { java_name: "generate", descriptor: "(Ljava/lang/Object;)Ljava/lang/String;", return_type: :value },
            "generate_pretty" => { java_name: "generatePretty", descriptor: "(Ljava/lang/Object;J)Ljava/lang/String;", return_type: :value }
          }
        },
        "KonpeitoCrypto" => {
          runtime_class: "konpeito/runtime/KCrypto",
          methods: {
            "sha256" => { java_name: "sha256", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "sha512" => { java_name: "sha512", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "sha256_binary" => { java_name: "sha256Binary", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "sha512_binary" => { java_name: "sha512Binary", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "hmac_sha256" => { java_name: "hmacSha256", descriptor: "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "hmac_sha512" => { java_name: "hmacSha512", descriptor: "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "hmac_sha256_binary" => { java_name: "hmacSha256Binary", descriptor: "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "random_bytes" => { java_name: "randomBytes", descriptor: "(J)Ljava/lang/String;", return_type: :value },
            "random_hex" => { java_name: "randomHex", descriptor: "(J)Ljava/lang/String;", return_type: :value },
            "secure_compare" => { java_name: "secureCompare", descriptor: "(Ljava/lang/String;Ljava/lang/String;)Z", return_type: :i8 }
          }
        },
        "KonpeitoCompression" => {
          runtime_class: "konpeito/runtime/KCompression",
          methods: {
            "gzip" => { java_name: "gzip", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "gunzip" => { java_name: "gunzip", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "deflate" => { java_name: "deflate", descriptor: "(Ljava/lang/String;Ljava/lang/Object;)Ljava/lang/String;", return_type: :value },
            "inflate" => { java_name: "inflate", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "zlib_compress" => { java_name: "zlibCompress", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "zlib_decompress" => { java_name: "zlibDecompress", descriptor: "(Ljava/lang/String;Ljava/lang/Object;)Ljava/lang/String;", return_type: :value }
          }
        },
        "KonpeitoHTTP" => {
          runtime_class: "konpeito/runtime/KHTTP",
          methods: {
            "get" => { java_name: "get", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "post" => { java_name: "post", descriptor: "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "get_response" => { java_name: "getResponse", descriptor: "(Ljava/lang/String;)Lkonpeito/runtime/KHash;", return_type: :value },
            "request" => { java_name: "request", descriptor: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Lkonpeito/runtime/KHash;)Lkonpeito/runtime/KHash;", return_type: :value }
          }
        },
        "KonpeitoTime" => {
          runtime_class: "konpeito/runtime/KTime",
          methods: {
            "now" => { java_name: "now", descriptor: "()Ljava/lang/String;", return_type: :value },
            "epoch_millis" => { java_name: "epochMillis", descriptor: "()J", return_type: :i64 },
            "epoch_nanos" => { java_name: "epochNanos", descriptor: "()J", return_type: :i64 },
            "format" => { java_name: "format", descriptor: "(JLjava/lang/String;)Ljava/lang/String;", return_type: :value },
            "parse" => { java_name: "parse", descriptor: "(Ljava/lang/String;Ljava/lang/String;)J", return_type: :i64 }
          }
        },
        "KonpeitoFile" => {
          runtime_class: "konpeito/runtime/KFile",
          methods: {
            "read" => { java_name: "read", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "write" => { java_name: "write", descriptor: "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "exist?" => { java_name: "exists", descriptor: "(Ljava/lang/String;)Z", return_type: :i8 },
            "delete" => { java_name: "delete", descriptor: "(Ljava/lang/String;)Z", return_type: :i8 },
            "size" => { java_name: "size", descriptor: "(Ljava/lang/String;)J", return_type: :i64 },
            "readlines" => { java_name: "readlines", descriptor: "(Ljava/lang/String;)Lkonpeito/runtime/KArray;", return_type: :value },
            "basename" => { java_name: "basename", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "dirname" => { java_name: "dirname", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "extname" => { java_name: "extname", descriptor: "(Ljava/lang/String;)Ljava/lang/String;", return_type: :value },
            "mkdir" => { java_name: "mkdir", descriptor: "(Ljava/lang/String;)Z", return_type: :i8 }
          }
        },
        "KonpeitoMath" => {
          runtime_class: "konpeito/runtime/KMath",
          methods: {
            "sqrt" => { java_name: "sqrt", descriptor: "(D)D", return_type: :double },
            "sin" => { java_name: "sin", descriptor: "(D)D", return_type: :double },
            "cos" => { java_name: "cos", descriptor: "(D)D", return_type: :double },
            "tan" => { java_name: "tan", descriptor: "(D)D", return_type: :double },
            "log" => { java_name: "log", descriptor: "(D)D", return_type: :double },
            "log10" => { java_name: "log10", descriptor: "(D)D", return_type: :double },
            "pow" => { java_name: "pow", descriptor: "(DD)D", return_type: :double },
            "pi" => { java_name: "pi", descriptor: "()D", return_type: :double },
            "e" => { java_name: "e", descriptor: "()D", return_type: :double },
            "abs" => { java_name: "abs", descriptor: "(D)D", return_type: :double },
            "floor" => { java_name: "floor", descriptor: "(D)D", return_type: :double },
            "ceil" => { java_name: "ceil", descriptor: "(D)D", return_type: :double },
            "round" => { java_name: "round", descriptor: "(D)J", return_type: :i64 },
            "min" => { java_name: "min", descriptor: "(DD)D", return_type: :double },
            "max" => { java_name: "max", descriptor: "(DD)D", return_type: :double }
          }
        },
      }.freeze

      def initialize(module_name: "konpeito", monomorphizer: nil, rbs_loader: nil, verbose: false)
        @module_name = module_name
        @monomorphizer = monomorphizer
        @rbs_loader = rbs_loader
        @verbose = verbose
        @hir_program = nil
        @class_defs = []  # Generated JVM class definitions (JSON-ready hashes)

        # Class registry: class_name -> { fields: {name => type_tag}, jvm_name:, super_name: }
        @class_info = {}

        # Per-function state
        @variable_slots = {}   # variable_name -> slot_index
        @variable_types = {}   # variable_name -> :i64, :double, :i8, :value
        @variable_class_types = {}  # variable_name -> class_name (for method dispatch)
        @variable_is_class_ref = {}  # variable_name -> true (for ConstantLookup, i.e. class reference)
        @next_slot = 0
        @current_instructions = []
        @label_counter = 0

        # Instance method generation state
        @generating_instance_method = false
        @current_class_name = nil
        @current_class_fields = nil
        @current_method_name = nil

        # Block/closure state
        @block_counter = 0
        @block_methods = []  # Accumulated block static methods for current class
        @kblock_registry = {}  # signature_key -> jvm_interface_name (deduplication)
        @yield_functions = Set.new  # function names that contain yield
        @current_enclosing_class = nil  # JVM class name for block method generation
        @block_param_slot = nil  # slot for __block__ parameter in yield-containing functions
        @current_kblock_iface = nil  # KBlock interface for current yield-containing function
        @variable_kblock_iface = {}  # variable_name -> kblock_iface_name (for lambda/proc .call())
        @method_descriptors = {}  # "ClassName#method_name" -> descriptor (populated during class gen)
        @static_method_renames = {}  # "ClassName.method_name" -> renamed JVM name (conflict avoidance)
        @constructor_param_types = {}  # "ClassName" -> [param_type_tags] (for call-site arg loading)
        @global_fields = Set.new  # Global variable field names (for main class static fields)
        @constant_fields = Set.new  # Top-level constant field names (for main class static fields)

        # Module registry: module_name -> { jvm_name:, methods: [], singleton_methods: [] }
        @module_info = {}

        # Kotlin-style validation counters: track how many TypeVars/RBS fallbacks occur
        @typevar_fallback_count = 0
        @rbs_fallback_count = 0

        # Current function being generated (for polymorphism tracking)
        @current_generating_func_name = nil
      end

      attr_reader :typevar_fallback_count, :rbs_fallback_count

      def generate(hir_program)
        @hir_program = hir_program

        # First pass: register all class info for cross-referencing
        hir_program.classes.each { |cd| register_class_info(cd) }

        # Second pass: dedup inherited fields now that all classes are registered
        # (First pass may register child before parent, so dedup in register_class_info
        #  can't always find parent fields)
        dedup_inherited_fields

        # Register module info
        hir_program.modules.each { |md| register_module_info(md) }

        # Register JVM interop classes (Java:: namespace)
        register_jvm_interop_classes

        # Register RBS-only native classes (@struct, NativeClass without Ruby source)
        register_rbs_only_native_classes

        # Pre-scan: identify functions that contain Yield instructions
        prescan_yield_functions(hir_program)

        # Pre-scan: identify top-level constants (FIXED=0, EXPANDING=1, etc.)
        # so that generate_constant_lookup in class methods can find them.
        # Classes are generated before main class, so we need this early.
        prescan_top_level_constants(hir_program)

        # Pre-scan: register global variable static fields early so that
        # global variables referenced inside blocks have fields available.
        prescan_global_variables(hir_program)

        # Pre-scan: detect functions called with inconsistent argument types
        # across call sites, and widen those params to :value (Object).
        # This prevents JVM VerifyError when e.g. assert_equal is called with
        # both Integer and String arguments at different sites.
        prescan_call_site_arg_types(hir_program)

        # Generate module interfaces FIRST (before classes that may implement them)
        hir_program.modules.each do |module_def|
          @block_methods = []
          @current_enclosing_class = module_jvm_name(module_def.name.to_s)
          mod_iface = generate_module_interface(module_def)
          mod_iface["methods"].concat(@block_methods)
          @class_defs << mod_iface
        end

        # Pre-register ALL class method descriptors before generating any class code.
        # This ensures cross-class calls always find the correct descriptor regardless
        # of class generation order (e.g., EventSource calling MyHandler.handle).
        sorted_classes = topological_sort_classes(hir_program.classes)
        sorted_classes.each do |class_def|
          next if @class_info[class_def.name.to_s]&.dig(:jvm_interop)
          fields_info = resolve_class_fields(class_def)
          pre_register_class_method_descriptors(class_def, fields_info)
        end

        # Generate user-defined classes (topologically sorted: parent before child)
        sorted_classes.each do |class_def|
          # Skip JVM interop classes (Java:: namespace — no code generation needed)
          next if @class_info[class_def.name.to_s]&.dig(:jvm_interop)

          @block_methods = []
          @current_enclosing_class = user_class_jvm_name(class_def.name.to_s)
          user_class = generate_user_class(class_def)
          user_class["methods"].concat(@block_methods)
          @class_defs << user_class
        end

        # Generate RBS-only native classes (@struct, etc.)
        @class_info.each do |class_name, info|
          next unless info[:rbs_only]
          @block_methods = []
          @current_enclosing_class = info[:jvm_name]
          rbs_class = generate_rbs_only_class(class_name, info)
          rbs_class["methods"].concat(@block_methods)
          @class_defs << rbs_class
        end

        # Generate main class containing all top-level functions
        @block_methods = []
        @current_enclosing_class = main_class_name
        main_class = generate_main_class
        # Append any block methods generated during main class processing
        main_class["methods"].concat(@block_methods)
        @class_defs << main_class

        # Generate KBlock functional interfaces
        @kblock_registry.each_value do |iface_name|
          @class_defs << @kblock_interfaces[iface_name]
        end

        # Report unresolved method calls as info (using invokedynamic for runtime resolution).
        # Only shown with --verbose since these are informational, not errors.
        if @verbose && @unresolved_calls && !@unresolved_calls.empty?
          STDERR.puts "Info: #{@unresolved_calls.size} dynamically dispatched method call(s):"
          @unresolved_calls.each { |msg| STDERR.puts msg }
          STDERR.puts ""
          STDERR.puts "  Type inference could not determine the receiver type."
          STDERR.puts "  These calls use invokedynamic for runtime method resolution."
          # Collect unique class#method suggestions for RBS
          rbs_suggestions = @unresolved_calls.map { |msg|
            if msg =~ /(\w+#\w+):/
              $1
            end
          }.compact.uniq
          unless rbs_suggestions.empty?
            STDERR.puts ""
            STDERR.puts "  Consider adding RBS type annotations to help resolve these calls statically."
            STDERR.puts "  For example, add type annotations for the receiver's class/method:"
            rbs_suggestions.first(5).each { |s| STDERR.puts "    Add RBS type annotations for #{s}" }
            STDERR.puts "    ... (#{rbs_suggestions.size - 5} more)" if rbs_suggestions.size > 5
          end
        end
      end

      # Pre-scan all functions to find those containing Yield instructions
      # NOTE: yield may appear inside nested blocks (e.g., `w.on_click { yield }`).
      # In Ruby, yield always refers to the enclosing method's block, so we must
      # recursively check nested BlockDefs to detect yield functions correctly.
      def prescan_yield_functions(hir_program)
        @kblock_interfaces = {}  # iface_name -> class def hash

        hir_program.functions.each do |func|
          has_yield = body_contains_yield?(func.body)
          has_block_given = body_contains_block_given?(func.body)
          @yield_functions.add(func.name.to_s) if has_yield || has_block_given
        end
      end

      # Check if basic blocks contain block_given? calls
      def body_contains_block_given?(basic_blocks)
        basic_blocks.any? { |bb|
          bb.instructions.any? { |inst|
            inst.is_a?(HIR::Call) && inst.method_name.to_s == "block_given?" &&
              (inst.receiver.nil? || inst.receiver.is_a?(HIR::SelfRef))
          }
        }
      end

      # Check if an array of basic blocks contains Yield instructions,
      # recursing into nested block bodies.
      def body_contains_yield?(basic_blocks)
        basic_blocks.any? { |bb|
          bb.instructions.any? { |inst|
            if inst.is_a?(HIR::Yield)
              true
            elsif inst.is_a?(HIR::Call) && inst.block
              block_contains_yield?(inst.block)
            else
              false
            end
          }
        }
      end

      # Yield every instruction in basic_blocks, recursing into block bodies
      # attached to HIR::Call nodes.
      def each_instruction_recursive(basic_blocks, &blk)
        basic_blocks.each do |bb|
          bb.instructions.each do |inst|
            blk.call(inst)
            if inst.is_a?(HIR::Call) && inst.block
              each_instruction_recursive(inst.block.body, &blk)
            end
          end
        end
      end

      # Pre-scan top-level StoreConstant instructions to populate @constant_fields early.
      # This is needed because user classes are generated before the main class, and
      # class constructors may reference top-level constants (e.g. EXPANDING = 1).
      # Recurses into block bodies so constants defined inside lambdas are also found.
      def prescan_top_level_constants(hir_program)
        hir_program.functions.each do |func|
          next if func.owner_class || func.owner_module
          each_instruction_recursive(func.body) do |inst|
            if inst.is_a?(HIR::StoreConstant) && inst.scope.nil?
              @constant_fields << inst.name.to_s
            end
          end
        end
      end

      # Pre-scan all functions for global variable access (LoadGlobalVar/StoreGlobalVar)
      # and register the corresponding static fields early. This ensures global variables
      # referenced inside blocks have their fields available during code generation.
      def prescan_global_variables(hir_program)
        hir_program.functions.each do |func|
          each_instruction_recursive(func.body) do |inst|
            if inst.is_a?(HIR::LoadGlobalVar) || inst.is_a?(HIR::StoreGlobalVar)
              field_name = inst.name.sub(/^\$/, "GLOBAL_")
              register_global_field(field_name)
            end
          end
        end
      end

      # Pre-scan: detect functions called with inconsistent argument types.
      # When a function like assert_equal(expected, actual, desc) is called with
      # Integer args at one site and String args at another, the JVM needs a single
      # method descriptor. If HM inference resolves params to a concrete type (e.g. :i64)
      # based on the first call site, later call sites with different types cause VerifyError.
      # This pre-scan detects such cases and marks params for widening to :value (Object).
      def prescan_call_site_arg_types(hir_program)
        # Collect argument types at each call site per function
        call_arg_types = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = Set.new } }

        # Scan all functions (top-level + class methods are both in functions list)
        # Note: top-level method calls may have SelfRef receiver (implicit self),
        # so we check for both nil and SelfRef receivers.
        hir_program.functions.each do |func|
          each_instruction_recursive(func.body) do |inst|
            next unless inst.is_a?(HIR::Call)
            if inst.receiver.nil? || inst.receiver.is_a?(HIR::SelfRef)
              # Top-level or self method call
              target = inst.method_name.to_s
              inst.args.each_with_index do |arg, i|
                call_arg_types[target][i] << static_arg_type(arg)
              end
            elsif inst.receiver
              # Instance method call — also collect arg types keyed by "ClassName#method"
              recv_class = static_receiver_class(inst.receiver, func)
              if recv_class
                target = "#{recv_class}##{inst.method_name}"
                inst.args.each_with_index do |arg, i|
                  call_arg_types[target][i] << static_arg_type(arg)
                end
              end
            end
          end
        end

        # Build widened params map: func_name => Set of param indices that need widening
        @widened_params = {}
        hir_program.functions.each do |func|
          func_name = func.name.to_s
          sites = call_arg_types[func_name]
          next if sites.empty?

          widened = Set.new
          func.params.each_with_index do |param, i|
            site_types = sites[i]
            next if site_types.nil? || site_types.empty?

            # Multiple different types at call sites — widen to :value
            if site_types.size > 1
              widened << i
            elsif site_types.size == 1
              # Even with a single call-site type, widen if it conflicts with HM-inferred param type.
              # E.g., HM infers param as :i8 (bool) but call site passes :value (Object from invokedynamic).
              site_type = site_types.first
              hm_type = param_type(param)
              if site_type != hm_type && (site_type == :value || hm_type == :value)
                widened << i
              end
            end
          end

          @widened_params[func_name] = widened unless widened.empty?
        end

        # Also build widened params for class instance methods
        hir_program.classes.each do |class_def|
          (class_def.method_names || []).each do |method_name|
            next if method_name.to_s == "initialize"
            key = "#{class_def.name}##{method_name}"
            sites = call_arg_types[key]
            next if sites.empty?

            func = find_class_instance_method(class_def.name.to_s, method_name.to_s)
            next unless func

            widened = Set.new
            func.params.each_with_index do |param, i|
              site_types = sites[i]
              next if site_types.nil? || site_types.empty?

              if site_types.size > 1
                widened << i
              elsif site_types.size == 1
                site_type = site_types.first
                hm_type = param_type(param)
                if site_type != hm_type && (site_type == :value || hm_type == :value)
                  widened << i
                end
              end
            end

            @widened_params[func.name.to_s] = widened unless widened.empty?
          end
        end
      end

      # Resolve the class name of a receiver node statically (during prescan).
      # Traces through variable assignments to find constructor calls (ClassName.new).
      def static_receiver_class(receiver, func)
        return nil unless receiver

        # Direct: ClassName.new stored in variable
        if receiver.respond_to?(:type) && receiver.type
          hir_type = receiver.type
          hir_type = hir_type.prune if hir_type.respond_to?(:prune)
          if hir_type.is_a?(TypeChecker::Types::ClassInstance)
            name = hir_type.name.to_s
            # Only return user-defined class names (not builtins like Integer, String)
            return name if @hir_program.classes.any? { |cd| cd.name.to_s == name }
          end
        end

        nil
      end

      # Infer the JVM type tag of an HIR node statically (without @variable_types).
      # Used by prescan_call_site_arg_types.
      def static_arg_type(node)
        case node
        when HIR::IntegerLit then :i64
        when HIR::FloatLit then :double
        when HIR::StringLit then :string
        when HIR::BoolLit then :i8
        when HIR::NilLit then :value
        when HIR::Call
          # Call results that go through invokedynamic always return Object on JVM,
          # regardless of what HM inference says. Treat as :value.
          :value
        else
          if node.respond_to?(:type) && node.type
            konpeito_type_to_tag(node.type)
          else
            :value
          end
        end
      end

      # Get the effective param type for a function, applying widening if needed.
      # Widening occurs when different call sites pass different types for the same param.
      def widened_param_type(func, param, index)
        widened = @widened_params && @widened_params[func.name.to_s]
        if widened && widened.include?(index)
          :value
        else
          param_type(param)
        end
      end


      # Returns the complete JSON IR as a Hash
      def to_json_ir
        { "classes" => @class_defs }
      end

      # Returns the JSON IR as a string
      def to_json
        JSON.generate(to_json_ir)
      end

      private

      def main_class_name
        "#{JAVA_PACKAGE}/#{sanitize_name(@module_name).capitalize}Main"
      end

      def sanitize_name(name)
        name.gsub(/[^a-zA-Z0-9_]/, "_")
      end

      # ========================================================================
      # Main Class Generation (top-level functions)
      # ========================================================================

      def generate_main_class
        methods = []

        # Default constructor
        methods << generate_default_constructor

        # Generate only top-level functions (skip class instance/class methods and module methods)
        @hir_program.functions.each do |func|
          next if func.owner_class
          next if func.owner_module  # Skip module-owned methods
          methods << generate_function(func)
        end

        # Generate main method that calls the top-level entry function
        methods << generate_main_method

        # Add global variable fields (static)
        fields = []
        (@global_fields || Set.new).each do |field_name|
          fields << {
            "name" => field_name,
            "descriptor" => "Ljava/lang/Object;",
            "access" => ["public", "static"]
          }
        end

        # Add top-level constant fields (static)
        (@constant_fields || Set.new).each do |field_name|
          fields << {
            "name" => field_name,
            "descriptor" => "Ljava/lang/Object;",
            "access" => ["public", "static"]
          }
        end

        {
          "name" => main_class_name,
          "access" => ["public", "super"],
          "superName" => "java/lang/Object",
          "interfaces" => [],
          "fields" => fields,
          "methods" => methods
        }
      end

      def generate_default_constructor
        {
          "name" => "<init>",
          "descriptor" => "()V",
          "access" => ["public"],
          "instructions" => [
            { "op" => "aload", "var" => 0 },
            { "op" => "invokespecial", "owner" => "java/lang/Object",
              "name" => "<init>", "descriptor" => "()V" },
            { "op" => "return" }
          ]
        }
      end

      def generate_main_method
        # Find a top-level expression function to call
        entry_func = @hir_program.functions.find { |f| f.name == "__main__" } ||
                     @hir_program.functions.find { |f| f.name == "__top_level__" }

        instructions = []

        if entry_func
          # Call the entry function
          desc = method_descriptor(entry_func)

          if entry_func.params.empty?
            instructions << { "op" => "invokestatic", "owner" => main_class_name,
                              "name" => jvm_method_name(entry_func.name),
                              "descriptor" => desc }

            # Discard return value if any (main returns void)
            ret_type = function_return_type(entry_func)
            case ret_type
            when :i64, :double
              instructions << { "op" => "pop2" }
            when :i8, :value
              instructions << { "op" => "pop" }
            end
          end
        end

        instructions << { "op" => "return" }

        {
          "name" => "main",
          "descriptor" => "([Ljava/lang/String;)V",
          "access" => ["public", "static"],
          "instructions" => instructions
        }
      end

      # ========================================================================
      # Function Generation
      # ========================================================================

      def generate_function(func)
        @current_generating_func_name = func.name.to_s
        reset_function_state(func)

        # Pre-scan for shared mutable captures (variables captured by blocks AND modified inside blocks)
        @shared_mutable_captures = scan_shared_mutable_captures(func)
        @shared_capture_fields = {}
        @shared_mutable_capture_types = {}  # Populated during codegen when type becomes known
        @shared_mutable_captures.each do |var_name|
          field_name = "SHARED_#{sanitize_name(var_name)}"
          @shared_capture_fields[var_name] = field_name
          register_global_field(field_name)
        end

        ret_type = function_return_type(func)
        @current_function_return_type = ret_type

        # Allocate parameter slots (use widened types for functions called with mixed arg types)
        func.params.each_with_index do |param, i|
          type = widened_param_type(func, param, i)
          # :void (NilClass) is not a valid JVM parameter type — nil is null, which is Object reference
          type = :value if type == :void
          allocate_slot(param.name, type)
          # *args (rest param) is a Ruby Array, **kwargs (keyword_rest) is a Hash
          if param.rest || param.keyword_rest
            @variable_collection_types[param.name.to_s] = param.rest ? :array : :hash
          end
        end

        # If this function contains yield, add a __block__ parameter
        @block_param_slot = nil
        @current_kblock_iface = nil
        func_has_yield = @yield_functions.include?(func.name.to_s)
        if func_has_yield
          @current_kblock_iface = yield_function_kblock_interface(func)
          @block_param_slot = @next_slot
          allocate_slot("__block__", :value)  # KBlock interface reference (Object slot)
        end

        prescan_phi_nodes(func)

        # After phi prescan, verify return type is compatible with variable assignments.
        # When a variable is assigned different types on different paths (e.g., x = nil
        # then x ||= 42), the return type must be :value to avoid JVM type mismatches.
        if ret_type != :value && ret_type != :void
          ret_type = verify_return_type_with_phi(func, ret_type)
          @current_function_return_type = ret_type
        end

        instructions = generate_function_body(func)

        # Sanitize returns for void methods: replace non-void returns with void return
        if ret_type == :void
          instructions = sanitize_void_returns(instructions)
        end

        # Box primitive returns when method descriptor expects Object
        if ret_type == :value
          instructions = convert_primitive_return_to_object(instructions)
        end

        # Insert checkcast before areturn when return type is more specific than Object
        if ret_type == :string
          areturn_count = instructions.count { |i| i["op"] == "areturn" }
          instructions = insert_return_checkcast(instructions, "java/lang/String")
        elsif ret_type.to_s.start_with?("class:")
          cast_type = user_class_jvm_name(ret_type.to_s.sub("class:", ""))
          instructions = insert_return_checkcast(instructions, cast_type)
        end

        # Ensure method has a return instruction
        unless instructions.last && return_instruction?(instructions.last)
          instructions << default_return(ret_type)
        end

        # Post-process: insert checkcast before invokevirtual/getfield/putfield on user classes
        instructions = insert_missing_checkcasts(instructions)

        @current_function_return_type = nil

        # Build descriptor: add KBlock parameter if yield-containing
        desc = if func_has_yield
                 method_descriptor_with_block(func, @current_kblock_iface)
               else
                 method_descriptor(func)
               end

        method_hash = {
          "name" => jvm_method_name(func.name),
          "descriptor" => desc,
          "access" => ["public", "static"],
          "instructions" => instructions
        }
        method_hash["exceptionTable"] = @pending_exception_table unless @pending_exception_table.empty?
        method_hash
      end

      # ========================================================================
      # Basic Block Generation
      # ========================================================================

      def generate_basic_block(bb)
        instructions = []

        # Emit label for this block
        instructions << { "op" => "label", "name" => bb.label.to_s }

        # Check if this block contains a BeginRescue
        begin_rescue_idx = bb.instructions.index { |i| i.is_a?(HIR::BeginRescue) }

        if begin_rescue_idx
          begin_rescue_inst = bb.instructions[begin_rescue_idx]

          # Collect all owned instruction IDs (Call blocks + BeginRescue non-try instructions)
          owned = collect_block_owned_instructions(bb.instructions)

          # The try body is everything before BeginRescue that's NOT owned
          inlined_try_body = bb.instructions[0...begin_rescue_idx].reject { |i| owned.include?(i.object_id) }

          # Generate BeginRescue with the inlined try body
          instructions.concat(generate_begin_rescue(begin_rescue_inst, inlined_try_body: inlined_try_body, bb_instructions: bb.instructions))

          # Process any remaining instructions after BeginRescue
          bb.instructions[(begin_rescue_idx + 1)..]&.each do |inst|
            next if owned.include?(inst.object_id)
            instructions.concat(generate_instruction(inst))
          end
        else
          # Normal block processing
          owned = collect_block_owned_instructions(bb.instructions)
          bb.instructions.each do |inst|
            next if owned.include?(inst.object_id)
            instructions.concat(generate_instruction(inst))
          end
        end

        # Generate terminator
        if bb.terminator
          instructions.concat(generate_terminator(bb.terminator))
        end

        instructions
      end

      # Collect instructions that should be skipped during normal block iteration.
      # This includes: Call block bodies, and all rescue/else/ensure instructions
      # (including sub-expressions like StringLit for literal arguments).
      def collect_block_owned_instructions(instructions)
        owned = Set.new
        instructions.each do |inst|
          if inst.is_a?(HIR::Call) && inst.block
            inst.block.body.each do |bb|
              bb.instructions.each { |i| owned << i.object_id }
            end
          end

          if inst.is_a?(HIR::BeginRescue)
            if inst.non_try_instruction_ids
              owned.merge(inst.non_try_instruction_ids)
            else
              inst.try_blocks&.each { |i| owned << i.object_id }
              inst.rescue_clauses&.each do |clause|
                clause.body_blocks&.each { |i| owned << i.object_id }
              end
              inst.else_blocks&.each { |i| owned << i.object_id }
              inst.ensure_blocks&.each { |i| owned << i.object_id }
            end
          end

          if inst.is_a?(HIR::CaseStatement)
            # Collect result_vars from CaseStatement sub-instructions.
            # We match by result_var name (not object_id) because the monomorphizer
            # dup's instructions, changing object_ids but preserving result_var names.
            sub_result_vars = Set.new
            inst.when_clauses&.each do |clause|
              clause.conditions&.each do |c|
                sub_result_vars << c.result_var if c.respond_to?(:result_var) && c.result_var
              end
              clause.body&.each do |b|
                sub_result_vars << b.result_var if b.respond_to?(:result_var) && b.result_var
              end
            end
            inst.else_body&.each do |e|
              sub_result_vars << e.result_var if e.respond_to?(:result_var) && e.result_var
            end
            instructions.each do |block_inst|
              next if block_inst.equal?(inst)
              if block_inst.respond_to?(:result_var) && block_inst.result_var && sub_result_vars.include?(block_inst.result_var)
                owned << block_inst.object_id
              end
            end
          end

          if inst.is_a?(HIR::CaseMatchStatement)
            sub_result_vars = Set.new
            inst.in_clauses&.each do |clause|
              collect_pattern_result_vars(clause.pattern, sub_result_vars) if clause.pattern
            end
            instructions.each do |block_inst|
              next if block_inst.equal?(inst)
              if block_inst.respond_to?(:result_var) && block_inst.result_var && sub_result_vars.include?(block_inst.result_var)
                owned << block_inst.object_id
              end
            end
          end
        end
        owned
      end

      # Recursively collect result_vars from pattern nodes
      def collect_pattern_result_vars(pattern, vars)
        case pattern
        when HIR::LiteralPattern
          vars << pattern.value.result_var if pattern.value.respond_to?(:result_var) && pattern.value.result_var
        when HIR::AlternationPattern
          pattern.alternatives&.each { |alt| collect_pattern_result_vars(alt, vars) }
        when HIR::CapturePattern
          collect_pattern_result_vars(pattern.value_pattern, vars) if pattern.value_pattern
        when HIR::ArrayPattern
          pattern.requireds&.each { |r| collect_pattern_result_vars(r, vars) }
          pattern.posts&.each { |p| collect_pattern_result_vars(p, vars) }
        when HIR::HashPattern
          pattern.elements&.each { |e| collect_pattern_result_vars(e.value_pattern, vars) if e.value_pattern }
        end
      end

      # ========================================================================
      # Instruction Dispatch
      # ========================================================================

      def generate_instruction(inst)
        case inst
        when HIR::IntegerLit
          generate_integer_lit(inst)
        when HIR::FloatLit
          generate_float_lit(inst)
        when HIR::BoolLit
          generate_bool_lit(inst)
        when HIR::NilLit
          generate_nil_lit(inst)
        when HIR::StringLit
          generate_string_lit(inst)
        when HIR::LoadLocal
          generate_load_local(inst)
        when HIR::StoreLocal
          generate_store_local(inst)
        when HIR::Call
          generate_call(inst)
        when HIR::Phi
          generate_phi(inst)
        when HIR::StringConcat
          generate_string_concat(inst)
        when HIR::SelfRef
          generate_self_ref(inst)
        when HIR::LoadInstanceVar
          generate_load_instance_var(inst)
        when HIR::StoreInstanceVar
          generate_store_instance_var(inst)
        when HIR::NativeNew
          generate_native_new(inst)
        when HIR::NativeMethodCall
          generate_native_method_call(inst)
        when HIR::SuperCall
          generate_super_call(inst)
        when HIR::ConstantLookup
          generate_constant_lookup(inst)
        when HIR::NativeFieldGet
          generate_native_field_get(inst)
        when HIR::NativeFieldSet
          generate_native_field_set(inst)
        when HIR::NativeMethodCall
          generate_native_method_call(inst)
        when HIR::Yield
          generate_yield(inst)
        when HIR::ProcNew
          generate_proc_new(inst)
        when HIR::ProcCall
          generate_proc_call(inst)
        when HIR::ArrayLit
          generate_array_lit(inst)
        when HIR::SymbolLit
          generate_symbol_lit(inst)
        when HIR::HashLit
          generate_hash_lit(inst)
        when HIR::BeginRescue
          generate_begin_rescue(inst)
        when HIR::CaseStatement
          generate_case_statement(inst)
        when HIR::CaseMatchStatement
          generate_case_match_statement(inst)
        when HIR::LoadGlobalVar
          generate_load_global_var(inst)
        when HIR::StoreGlobalVar
          generate_store_global_var(inst)
        when HIR::LoadClassVar
          generate_load_class_var(inst)
        when HIR::StoreClassVar
          generate_store_class_var(inst)
        when HIR::MultiWriteExtract
          generate_multi_write_extract(inst)
        when HIR::RangeLit
          generate_range_lit(inst)
        when HIR::RegexpLit
          generate_regexp_lit(inst)
        when HIR::StoreConstant
          generate_store_constant(inst)
        when HIR::IncludeStatement
          # Include/extend/prepend are handled at class generation time
          []
        when HIR::DefinedCheck
          generate_defined_check(inst)
        # Concurrency — Fiber
        when HIR::FiberNew     then generate_fiber_new(inst)
        when HIR::FiberResume  then generate_fiber_resume(inst)
        when HIR::FiberYield   then generate_fiber_yield(inst)
        when HIR::FiberAlive   then generate_fiber_alive(inst)
        when HIR::FiberCurrent then generate_fiber_current(inst)
        # Concurrency — Thread, Mutex, etc.
        when HIR::ThreadNew     then generate_thread_new(inst)
        when HIR::ThreadJoin    then generate_thread_join(inst)
        when HIR::ThreadValue   then generate_thread_value(inst)
        when HIR::ThreadCurrent then generate_thread_current(inst)
        when HIR::MutexNew          then generate_mutex_new(inst)
        when HIR::MutexLock         then generate_mutex_lock(inst)
        when HIR::MutexUnlock       then generate_mutex_unlock(inst)
        when HIR::MutexSynchronize  then generate_mutex_synchronize(inst)
        when HIR::ConditionVariableNew       then generate_cv_new(inst)
        when HIR::ConditionVariableWait      then generate_cv_wait(inst)
        when HIR::ConditionVariableSignal    then generate_cv_signal(inst)
        when HIR::ConditionVariableBroadcast then generate_cv_broadcast(inst)
        when HIR::SizedQueueNew  then generate_sized_queue_new(inst)
        when HIR::SizedQueuePush then generate_sized_queue_push(inst)
        when HIR::SizedQueuePop  then generate_sized_queue_pop(inst)
        # Ractor operations
        when HIR::RactorNew          then generate_ractor_new(inst)
        when HIR::RactorSend         then generate_ractor_send(inst)
        when HIR::RactorReceive      then generate_ractor_receive(inst)
        when HIR::RactorJoin         then generate_ractor_join(inst)
        when HIR::RactorValue        then generate_ractor_value(inst)
        when HIR::RactorClose        then generate_ractor_close(inst)
        when HIR::RactorCurrent      then generate_ractor_current(inst)
        when HIR::RactorMain         then generate_ractor_main(inst)
        when HIR::RactorName         then generate_ractor_name(inst)
        when HIR::RactorLocalGet     then generate_ractor_local_get(inst)
        when HIR::RactorLocalSet     then generate_ractor_local_set(inst)
        when HIR::RactorMakeSharable then generate_ractor_make_sharable(inst)
        when HIR::RactorSharable     then generate_ractor_sharable(inst)
        when HIR::RactorMonitor      then generate_ractor_monitor(inst)
        when HIR::RactorUnmonitor    then generate_ractor_unmonitor(inst)
        when HIR::RactorPortNew      then generate_ractor_port_new(inst)
        when HIR::RactorPortSend     then generate_ractor_port_send(inst)
        when HIR::RactorPortReceive  then generate_ractor_port_receive(inst)
        when HIR::RactorPortClose    then generate_ractor_port_close(inst)
        when HIR::RactorSelect       then generate_ractor_select(inst)
        # NativeArray (primitive arrays)
        when HIR::NativeArrayAlloc  then generate_jvm_native_array_alloc(inst)
        when HIR::NativeArrayGet    then generate_jvm_native_array_get(inst)
        when HIR::NativeArraySet    then generate_jvm_native_array_set(inst)
        when HIR::NativeArrayLength then generate_jvm_native_array_length(inst)
        # StaticArray (compile-time sized primitive arrays)
        when HIR::StaticArrayAlloc then generate_jvm_static_array_alloc(inst)
        when HIR::StaticArrayGet   then generate_jvm_native_array_get(inst)
        when HIR::StaticArraySet   then generate_jvm_native_array_set(inst)
        when HIR::StaticArraySize  then generate_jvm_static_array_size(inst)
        when HIR::SplatArg
          # SplatArg is handled by generate_call/generate_static_call — just store the expression
          insts = load_value(inst.expression, :value)
          if inst.result_var
            ensure_slot(inst.result_var, :value)
            insts << store_instruction(inst.result_var, :value)
            @variable_types[inst.result_var] = :value
          end
          insts
        else
          # Unsupported instruction - emit warning comment
          warn "JVM: unsupported HIR instruction: #{inst.class.name}"
          []
        end
      end

      # ========================================================================
      # Terminator Generation
      # ========================================================================

      def generate_terminator(term)
        case term
        when HIR::Return
          generate_return(term)
        when HIR::Branch
          generate_branch(term)
        when HIR::Jump
          generate_jump(term)
        when HIR::RaiseException
          generate_raise_exception(term)
        else
          warn "JVM: unsupported terminator: #{term.class.name}"
          []
        end
      end

      # ========================================================================
      # Literal Instructions
      # ========================================================================

      def generate_integer_lit(inst)
        result_var = inst.result_var
        type = :i64
        ensure_slot(result_var, type)

        instructions = []
        val = inst.value

        if val == 0
          instructions << { "op" => "lconst_0" }
        elsif val == 1
          instructions << { "op" => "lconst_1" }
        else
          instructions << { "op" => "ldc2_w", "value" => val, "type" => "long" }
        end

        instructions << store_instruction(result_var, type)
        @variable_types[result_var] = type
        instructions
      end

      def generate_float_lit(inst)
        result_var = inst.result_var
        type = :double
        ensure_slot(result_var, type)

        instructions = []
        val = inst.value

        if val == 0.0
          instructions << { "op" => "dconst_0" }
        elsif val == 1.0
          instructions << { "op" => "dconst_1" }
        else
          instructions << { "op" => "ldc2_w", "value" => val, "type" => "double" }
        end

        instructions << store_instruction(result_var, type)
        @variable_types[result_var] = type
        instructions
      end

      def generate_bool_lit(inst)
        result_var = inst.result_var
        ensure_slot(result_var, :i8)

        instructions = []
        val = inst.value ? 1 : 0
        instructions << { "op" => "iconst", "value" => val }
        instructions << store_instruction(result_var, :i8)
        @variable_types[result_var] = :i8
        instructions
      end

      def generate_nil_lit(inst)
        result_var = inst.result_var
        type = :value
        ensure_slot(result_var, type)

        [
          { "op" => "aconst_null" },
          store_instruction(result_var, type)
        ].tap { @variable_types[result_var] = type }
      end

      def generate_string_lit(inst)
        result_var = inst.result_var
        type = :string
        ensure_slot(result_var, type)

        # Use new String(ldc) instead of bare ldc to avoid JVM string interning.
        # This ensures Object#equal? (identity check) returns false for different
        # string literals with the same value, matching Ruby semantics.
        [
          { "op" => "new", "type" => "java/lang/String" },
          { "op" => "dup" },
          { "op" => "ldc", "value" => inst.value },
          { "op" => "invokespecial", "owner" => "java/lang/String",
            "name" => "<init>", "descriptor" => "(Ljava/lang/String;)V" },
          store_instruction(result_var, type)
        ].tap { @variable_types[result_var] = type }
      end

      # ========================================================================
      # Variable Instructions
      # ========================================================================

      def generate_load_local(inst)
        result_var = inst.result_var
        source_var = inst.var.is_a?(HIR::LocalVar) ? inst.var.name.to_s : inst.var.to_s

        # Shared mutable capture inside a block: no local slot, use getstatic
        if @shared_mutable_captures&.include?(source_var) && !@variable_slots.key?(source_var)
          return generate_load_shared_capture(source_var, result_var)
        end

        type = @variable_types[source_var] || :value
        ensure_slot(result_var, type) if result_var

        if result_var
          [
            load_instruction(source_var, type),
            store_instruction(result_var, type)
          ].tap do
            @variable_types[result_var] = type
            # Propagate class type info for method dispatch
            if @variable_class_types[source_var]
              @variable_class_types[result_var] = @variable_class_types[source_var]
            end
            # Propagate KBlock interface info for lambda/proc .call()
            if @variable_kblock_iface[source_var]
              @variable_kblock_iface[result_var] = @variable_kblock_iface[source_var]
            end
            # Propagate collection type info for array/hash dispatch
            if @variable_collection_types[source_var]
              @variable_collection_types[result_var] = @variable_collection_types[source_var]
            end
            # Propagate concurrency type info for Thread/Mutex/CV/SizedQueue dispatch
            if @variable_concurrency_types[source_var]
              @variable_concurrency_types[result_var] = @variable_concurrency_types[source_var]
            end
            # Propagate native array element type for primitive array dispatch
            if @variable_native_array_element_type[source_var]
              @variable_native_array_element_type[result_var] = @variable_native_array_element_type[source_var]
            end
            # Propagate array element type for typed array access (Array[String] etc.)
            if @variable_array_element_types[source_var]
              @variable_array_element_types[result_var] = @variable_array_element_types[source_var]
            end
          end
        else
          # LoadLocal without result_var - just load to stack
          [load_instruction(source_var, type)]
        end
      end

      # Load a shared mutable capture from static field (inside block)
      def generate_load_shared_capture(source_var, result_var)
        field_name = @shared_capture_fields[source_var]
        # Determine expected type: check @shared_mutable_capture_types or default to :value
        # (previously defaulted to :i64, which broke Proc/KBlock values)
        type = @shared_mutable_capture_types&.dig(source_var) || :value

        instructions = []
        instructions << { "op" => "getstatic", "owner" => main_class_name,
                          "name" => field_name, "descriptor" => "Ljava/lang/Object;" }
        instructions.concat(unbox_from_object_field(type))

        if result_var
          ensure_slot(result_var, type)
          instructions << store_instruction(result_var, type)
          @variable_types[result_var] = type
          # Propagate KBlock interface info for lambda/proc .call()
          if @variable_kblock_iface[source_var]
            @variable_kblock_iface[result_var] = @variable_kblock_iface[source_var]
          end
          # Propagate class type info for method dispatch
          if @variable_class_types[source_var]
            @variable_class_types[result_var] = @variable_class_types[source_var]
          end
          # Propagate collection type info for array/hash dispatch
          if @variable_collection_types[source_var]
            @variable_collection_types[result_var] = @variable_collection_types[source_var]
          end
        end

        instructions
      end

      def generate_store_local(inst)
        target_var = inst.var.is_a?(HIR::LocalVar) ? inst.var.name.to_s : inst.var.to_s
        value = inst.value

        # Shared mutable capture inside a block: no local slot, use putstatic only
        if @shared_mutable_captures&.include?(target_var) && !@variable_slots.key?(target_var)
          return generate_store_shared_capture(target_var, value)
        end

        instructions = []

        if value.is_a?(HIR::LocalVar) || value.is_a?(HIR::Param)
          source_var = value.name.to_s
          type = @variable_types[source_var] || :value
          type = reconcile_store_type(target_var, type)
          ensure_slot(target_var, type)
          instructions << load_instruction(source_var, @variable_types[source_var] || :value)
          instructions.concat(convert_for_store(type, @variable_types[source_var] || :value))
          instructions << store_instruction(target_var, type)
          @variable_types[target_var] = type
          @variable_class_types[target_var] = @variable_class_types[source_var] if @variable_class_types[source_var]
          @variable_kblock_iface[target_var] = @variable_kblock_iface[source_var] if @variable_kblock_iface[source_var]
          @variable_collection_types[target_var] = @variable_collection_types[source_var] if @variable_collection_types[source_var]
          @variable_concurrency_types[target_var] = @variable_concurrency_types[source_var] if @variable_concurrency_types[source_var]
          @variable_native_array_element_type[target_var] = @variable_native_array_element_type[source_var] if @variable_native_array_element_type[source_var]
          @variable_array_element_types[target_var] = @variable_array_element_types[source_var] if @variable_array_element_types[source_var]
          @variable_is_class_ref[target_var] = @variable_is_class_ref[source_var] if @variable_is_class_ref[source_var]
          @variable_is_symbol[target_var] = @variable_is_symbol[source_var] if @variable_is_symbol[source_var]
        elsif value.is_a?(HIR::LoadLocal)
          # LoadLocal - load from its source variable
          source_var = value.var.is_a?(HIR::LocalVar) ? value.var.name.to_s : value.var.to_s
          type = @variable_types[source_var] || infer_type_from_hir(value) || :value
          type = reconcile_store_type(target_var, type)
          ensure_slot(target_var, type)
          instructions << load_instruction(source_var, @variable_types[source_var] || :value)
          instructions.concat(convert_for_store(type, @variable_types[source_var] || :value))
          instructions << store_instruction(target_var, type)
          @variable_types[target_var] = type
          @variable_class_types[target_var] = @variable_class_types[source_var] if @variable_class_types[source_var]
          @variable_kblock_iface[target_var] = @variable_kblock_iface[source_var] if @variable_kblock_iface[source_var]
          @variable_collection_types[target_var] = @variable_collection_types[source_var] if @variable_collection_types[source_var]
          @variable_concurrency_types[target_var] = @variable_concurrency_types[source_var] if @variable_concurrency_types[source_var]
          @variable_native_array_element_type[target_var] = @variable_native_array_element_type[source_var] if @variable_native_array_element_type[source_var]
          @variable_array_element_types[target_var] = @variable_array_element_types[source_var] if @variable_array_element_types[source_var]
          @variable_is_class_ref[target_var] = @variable_is_class_ref[source_var] if @variable_is_class_ref[source_var]
          @variable_is_symbol[target_var] = @variable_is_symbol[source_var] if @variable_is_symbol[source_var]
        elsif value.is_a?(HIR::IntegerLit) || value.is_a?(HIR::FloatLit) ||
              value.is_a?(HIR::StringLit) || value.is_a?(HIR::BoolLit) ||
              value.is_a?(HIR::NilLit) || value.is_a?(HIR::SymbolLit)
          # Literal value (e.g. from inlined default parameter) — generate inline
          loaded_type = infer_type_from_hir(value) || :value
          # NilLit is a null Object reference on JVM, not void
          loaded_type = :value if loaded_type == :void || value.is_a?(HIR::NilLit)
          # If this variable has mixed-type assignments, force :value
          loaded_type = :value if @_nil_assigned_vars&.include?(target_var)
          type = reconcile_store_type(target_var, loaded_type)
          ensure_slot(target_var, type)
          instructions.concat(load_value(value, type))
          instructions << store_instruction(target_var, type)
          @variable_types[target_var] = type
          @variable_is_symbol[target_var] = true if value.is_a?(HIR::SymbolLit)
        else
          # Value should already be on the stack or in a temp var
          source_var = value.respond_to?(:result_var) ? value.result_var : nil
          if source_var
            type = @variable_types[source_var] || infer_type_from_hir(value) || :value
            type = reconcile_store_type(target_var, type)
            ensure_slot(target_var, type)
            instructions << load_instruction(source_var, @variable_types[source_var] || :value)
            instructions.concat(convert_for_store(type, @variable_types[source_var] || :value))
            instructions << store_instruction(target_var, type)
            @variable_types[target_var] = type
            @variable_class_types[target_var] = @variable_class_types[source_var] if @variable_class_types[source_var]
            @variable_kblock_iface[target_var] = @variable_kblock_iface[source_var] if @variable_kblock_iface[source_var]
            @variable_collection_types[target_var] = @variable_collection_types[source_var] if @variable_collection_types[source_var]
            @variable_concurrency_types[target_var] = @variable_concurrency_types[source_var] if @variable_concurrency_types[source_var]
            @variable_native_array_element_type[target_var] = @variable_native_array_element_type[source_var] if @variable_native_array_element_type[source_var]
            @variable_is_class_ref[target_var] = @variable_is_class_ref[source_var] if @variable_is_class_ref[source_var]
          end
        end

        # Sync to static field for shared mutable captures (outer function has local slot)
        if @shared_mutable_captures&.include?(target_var) && @shared_capture_fields&.key?(target_var)
          instructions.concat(sync_to_shared_capture_field(target_var))
        end

        instructions
      end

      # When storing to a variable that already has a slot with a known type,
      # keep the existing type to avoid JVM verifier conflicts at merge points.
      # E.g., parameter `completely` is :value (Object), and `completely = true` (:i8)
      # must box to Object, not change the slot type to :i8.
      def reconcile_store_type(target_var, source_type)
        # Variables with mixed-type assignments must always be :value
        return :value if @_nil_assigned_vars&.include?(target_var)
        existing_type = @variable_types[target_var]
        return source_type unless existing_type && @variable_slots.key?(target_var)
        return source_type if existing_type == source_type
        # If slot already has a type, keep it (widen to :value if incompatible)
        existing_type
      end

      # Convert stack top from source_type to target_type for store
      def convert_for_store(target_type, source_type)
        return [] if target_type == source_type
        if target_type == :value && (source_type == :i8 || source_type == :i64 || source_type == :double)
          box_primitive_if_needed(source_type, :value)
        elsif (target_type == :i64) && (source_type == :value || source_type == :string || source_type == :array || source_type == :hash || source_type == :regexp)
          # Reference type → long: cast to Number and unbox.
          # This handles mixed-type arrays where element type tracking may be inaccurate.
          [{ "op" => "checkcast", "type" => "java/lang/Number" },
           { "op" => "invokevirtual", "owner" => "java/lang/Number", "name" => "longValue", "descriptor" => "()J" }]
        elsif (target_type == :double) && (source_type == :value || source_type == :string || source_type == :array || source_type == :hash || source_type == :regexp)
          # Reference type → double: cast to Number and unbox.
          [{ "op" => "checkcast", "type" => "java/lang/Number" },
           { "op" => "invokevirtual", "owner" => "java/lang/Number", "name" => "doubleValue", "descriptor" => "()D" }]
        elsif (target_type == :i8) && (source_type == :value || source_type == :string)
          # Unbox Boolean → int
          [{ "op" => "checkcast", "type" => "java/lang/Boolean" },
           { "op" => "invokevirtual", "owner" => "java/lang/Boolean", "name" => "booleanValue", "descriptor" => "()Z" }]
        elsif target_type == :double && source_type == :i64
          # long → double conversion
          [{ "op" => "l2d" }]
        elsif target_type == :i64 && source_type == :double
          # double → long conversion
          [{ "op" => "d2l" }]
        elsif target_type == :string && (source_type == :value || source_type == :array || source_type == :hash)
          # Reference type → String: checkcast
          [{ "op" => "checkcast", "type" => "java/lang/String" }]
        elsif (target_type == :value) && (source_type == :string || source_type == :array || source_type == :hash || source_type == :regexp)
          # String/Array/Hash/Regexp are already Object references — no conversion needed
          []
        else
          []
        end
      end

      # Store to a shared mutable capture field (inside block, no local slot)
      def generate_store_shared_capture(target_var, value)
        instructions = []
        field_name = @shared_capture_fields[target_var]

        # Load the source value
        source_var = if value.is_a?(HIR::LocalVar) || value.is_a?(HIR::Param)
                       value.name.to_s
                     elsif value.is_a?(HIR::LoadLocal)
                       value.var.is_a?(HIR::LocalVar) ? value.var.name.to_s : value.var.to_s
                     elsif value.respond_to?(:result_var) && value.result_var
                       value.result_var
                     end

        if source_var
          type = @variable_types[source_var] || :value
          # Record type so that subsequent loads from this shared field use the correct type
          # (without this, the default :i64 is assumed, which breaks Proc/KBlock values)
          @shared_mutable_capture_types[target_var] = type
          # Propagate KBlock interface info so .call() works on shared capture variables
          if @variable_kblock_iface[source_var]
            @variable_kblock_iface[target_var] = @variable_kblock_iface[source_var]
          end
          instructions << load_instruction(source_var, type)
          # Box primitive for Object field
          instructions.concat(box_for_object_field(type))
          instructions << { "op" => "putstatic", "owner" => main_class_name,
                            "name" => field_name, "descriptor" => "Ljava/lang/Object;" }
        end

        instructions
      end

      # After local store, sync value to shared capture static field
      def sync_to_shared_capture_field(target_var)
        field_name = @shared_capture_fields[target_var]
        type = @variable_types[target_var] || :value
        # Record type for use inside block methods
        @shared_mutable_capture_types[target_var] = type
        instructions = []
        instructions << load_instruction(target_var, type)
        instructions.concat(box_for_object_field(type))
        instructions << { "op" => "putstatic", "owner" => main_class_name,
                          "name" => field_name, "descriptor" => "Ljava/lang/Object;" }
        instructions
      end

      # Box a primitive value to Object for storing in an Object field
      def box_for_object_field(type)
        case type
        when :i64
          [{ "op" => "invokestatic", "owner" => "java/lang/Long",
             "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }]
        when :double
          [{ "op" => "invokestatic", "owner" => "java/lang/Double",
             "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }]
        when :i8
          [{ "op" => "invokestatic", "owner" => "java/lang/Boolean",
             "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }]
        else
          []
        end
      end

      # Unbox an Object from a shared capture field to the expected type
      def unbox_from_object_field(expected_type)
        case expected_type
        when :i64
          # Null-safe: RubyDispatch.unboxLong returns 0L for null
          [{ "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
             "name" => "unboxLong", "descriptor" => "(Ljava/lang/Object;)J" }]
        when :double
          # Null-safe: RubyDispatch.unboxDouble returns 0.0 for null
          [{ "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
             "name" => "unboxDouble", "descriptor" => "(Ljava/lang/Object;)D" }]
        when :i8
          # Null-safe: RubyDispatch.unboxBoolean returns false for null
          [{ "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
             "name" => "unboxBoolean", "descriptor" => "(Ljava/lang/Object;)Z" }]
        else
          []
        end
      end

      # ========================================================================
      # Call (Arithmetic Operations)
      # ========================================================================

      def generate_call(inst)
        method_name = inst.method_name.to_s
        receiver = inst.receiver
        args = inst.args || []
        result_var = inst.result_var
        block_def = inst.block

        # Safe navigation: x&.method → if x == nil then nil else x.method end
        if inst.safe_navigation && receiver
          return generate_safe_navigation_call(inst)
        end

        # Symbol#class → "Symbol" (symbols are represented as strings on JVM)
        if method_name == "class" && receiver && args.empty?
          recv_var = extract_var_name(receiver)
          if recv_var && @variable_is_symbol[recv_var]
            instructions = [{ "op" => "ldc", "value" => "Symbol" }]
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          end
        end

        # block_given? → null check on __block__ parameter
        if method_name == "block_given?" && (receiver.nil? || receiver.is_a?(HIR::SelfRef))
          return generate_block_given(result_var)
        end

        # Boolean negation: !expr
        if method_name == "!" && receiver && args.empty?
          return generate_not_operator(receiver, result_var)
        end

        # Integer#times with block → inline loop
        if method_name == "times" && block_def && receiver
          return generate_times_inline(inst, receiver, block_def, result_var)
        end

        # Integer#upto(limit) / Integer#downto(limit) with block → inline loop
        if method_name == "upto" && block_def && receiver && args.length == 1
          return generate_upto_inline(inst, receiver, args[0], block_def, result_var)
        end
        if method_name == "downto" && block_def && receiver && args.length == 1
          return generate_downto_inline(inst, receiver, args[0], block_def, result_var)
        end

        # Range#each/map/select/reduce/any?/all?/none?/sum/min/max with block → inline loop
        if block_def && receiver && can_jvm_inline_range_loop?(inst)
          case method_name
          when "each"
            return generate_range_each_inline(inst, receiver, block_def, result_var)
          when "map", "collect"
            return generate_range_map_inline(inst, receiver, block_def, result_var)
          when "select", "filter"
            return generate_range_select_inline(inst, receiver, block_def, result_var)
          when "reduce", "inject"
            return generate_range_reduce_inline(inst, receiver, block_def, result_var)
          when "any?"
            return generate_range_any_inline(inst, receiver, block_def, result_var)
          when "all?"
            return generate_range_all_inline(inst, receiver, block_def, result_var)
          when "none?"
            return generate_range_none_inline(inst, receiver, block_def, result_var)
          end
        end

        # Range#min/max/sum without block
        if receiver && can_jvm_inline_range_loop?(inst)
          case method_name
          when "min"
            return generate_range_min_inline(inst, receiver, result_var)
          when "max"
            return generate_range_max_inline(inst, receiver, result_var)
          when "sum"
            return generate_range_sum_inline(inst, receiver, result_var)
          end
        end

        # Call with block to yield-containing function
        if block_def && (receiver.nil? || receiver.is_a?(HIR::SelfRef)) &&
           @yield_functions.include?(method_name)
          return generate_call_with_block(inst, method_name, args, block_def, result_var)
        end

        # Lambda/Proc .call() → invokeinterface on KBlock
        if method_name == "call" && receiver
          recv_var = extract_var_name(receiver)
          if recv_var && @variable_kblock_iface[recv_var]
            return generate_kblock_call(recv_var, args, result_var)
          end
          # Fallback: stored block/proc without tracked interface
          # Generate a generic KBlock0 (no-arg) or KBlockN (N-arg) call
          if recv_var
            return generate_generic_block_call(recv_var, args, result_var)
          end
        end

        # Check for constructor call: ClassName.new(args)
        if method_name == "new" && receiver_is_class?(receiver)
          return generate_constructor_call(inst, receiver, args, result_var)
        end
        # Check for class method call: ClassName.method(args) (not "new")
        if receiver_is_class?(receiver) && method_name != "new"
          return generate_class_method_call(inst, receiver, method_name, args, result_var)
        end

        # Check for stdlib module call (KonpeitoJSON, KonpeitoCrypto, etc.)
        if receiver.is_a?(HIR::ConstantLookup)
          stdlib_info = STDLIB_MODULES[receiver.name.to_s]
          if stdlib_info
            return generate_stdlib_call(stdlib_info, method_name, args, result_var)
          end
        end

        # Check for module singleton method call: ModuleName.method(args)
        if receiver_is_module?(receiver)
          return generate_module_method_call(inst, receiver, method_name, args, result_var)
        end

        # Check for instance method call on user class object
        # Exclude comparison operators — they must go through generate_comparison_call
        # which handles == nil (ifnull), Objects.equals, etc. correctly.
        # User-defined comparison operators (==, != etc.) are handled inside generate_comparison_call.
        if receiver && !receiver.is_a?(HIR::SelfRef) && is_user_class_receiver?(receiver) && !comparison_operator?(method_name.to_s)
          result = generate_instance_call(inst, method_name, receiver, args, result_var)
          # If generate_instance_call returns empty (method not found in user class hierarchy),
          # fall through to invokedynamic for Ruby built-in methods (is_a?, respond_to?, etc.)
          return result unless result.empty?
        end

        # Check for self.method() call within instance method (explicit or implicit self)
        if (receiver.is_a?(HIR::SelfRef) || receiver.nil?) && @generating_instance_method && has_class_instance_method?(method_name)
          return generate_self_method_call(inst, method_name, args, result_var)
        end

        # Check for concurrency method calls (Thread/Mutex/CV/SizedQueue)
        if receiver
          recv_var = extract_var_name(receiver)
          conc_type = recv_var ? @variable_concurrency_types[recv_var] : nil
          if conc_type
            result = generate_concurrency_method_call(conc_type, method_name, receiver, args, result_var)
            return result if result
          end
        end

        # Check for collection method calls (Array)
        if receiver && is_array_receiver?(receiver)
          # Extract element type from HM inference on the call result (inst.type)
          call_elem_type = resolve_array_element_type_from_inst(inst)
          result = generate_array_method_call(method_name, receiver, args, result_var, block_def, element_type: call_elem_type)
          return result if result
        end

        # Check for collection method calls (Hash)
        if receiver && is_hash_receiver?(receiver)
          result = generate_hash_method_call(method_name, receiver, args, result_var, block_def)
          return result if result
        end

        # Check for String method calls
        if receiver && is_string_receiver?(receiver) && string_method?(method_name)
          result = generate_string_method_call(method_name, receiver, args, result_var)
          return result if result
        end

        # Check for NativeArray primitive array method calls ([], []=, length)
        if receiver
          recv_var = extract_var_name(receiver)
          if recv_var && @variable_native_array_element_type[recv_var]
            result = generate_native_array_method_call(method_name, receiver, args, result_var)
            return result if result
          end
        end

        # Check for numeric method calls (abs, even?, odd?, to_f, gcd, etc.)
        if receiver && numeric_instance_method?(method_name) && args.size <= 1
          result = generate_numeric_method_call(method_name, receiver, args, result_var)
          return result if result
        end

        # Check for unboxed arithmetic
        if arithmetic_operator?(method_name) && args.size == 1
          result = generate_arithmetic_call(inst, method_name, receiver, args.first, result_var)
          return result if result
        end

        # Check for comparison operators
        if comparison_operator?(method_name) && args.size == 1
          return generate_comparison_call(inst, method_name, receiver, args.first, result_var)
        end

        # raise → new RuntimeException + athrow
        if method_name == "raise" && (receiver.nil? || receiver.is_a?(HIR::SelfRef))
          return generate_raise_call(args, result_var)
        end

        # Check for puts/print (receiver can be nil or self)
        if method_name == "puts" && (receiver.nil? || receiver.is_a?(HIR::SelfRef))
          return generate_puts_call(args, result_var)
        end

        if method_name == "print" && (receiver.nil? || receiver.is_a?(HIR::SelfRef))
          return generate_print_call(args, result_var)
        end

        # Symbol#inspect → ":" + value (symbols are strings in JVM backend)
        if method_name == "inspect" && receiver && args.empty?
          recv_var = extract_var_name(receiver)
          is_sym = receiver.is_a?(HIR::SymbolLit) || (recv_var && @variable_is_symbol[recv_var])
          if is_sym
            return generate_symbol_inspect(receiver, result_var)
          end
        end

        # Check for type conversion methods
        if %w[to_s to_i to_f].include?(method_name) && receiver
          return generate_conversion_call(method_name, receiver, result_var)
        end

        # Check for user-defined static method calls (top-level)
        if receiver.nil? || (receiver.is_a?(HIR::SelfRef))
          return generate_static_call(inst, method_name, args, result_var)
        end

        # Resolve receiver class from HIR type annotation (HM inferrer result) ONLY.
        # No heuristic guessing — if HM inference didn't resolve the type, it's an error.
        if receiver
          resolved_class = nil
          recv_var = extract_var_name(receiver)

          recv_hir_type = receiver.type if receiver.respond_to?(:type)
          # Resolve TypeVars to their bound types (HM inference uses mutable TypeVars)
          recv_hir_type = recv_hir_type.prune if recv_hir_type.respond_to?(:prune)
          if recv_hir_type.is_a?(TypeChecker::Types::ClassInstance)
            cls_name = recv_hir_type.name.to_s

            # HM inferred Array type → dispatch through array methods
            if cls_name == "Array"
              @variable_collection_types[recv_var] = :array if recv_var
              # Record element type from receiver's type_args (e.g., Array[String] → :string)
              if recv_var && recv_hir_type.type_args&.any?
                et = konpeito_type_to_tag(recv_hir_type.type_args.first)
                @variable_array_element_types[recv_var] = et if et != :value
              end
              call_elem_type = resolve_array_element_type_from_inst(inst)
              result = generate_array_method_call(method_name, receiver, args, result_var, block_def, element_type: call_elem_type)
              return result if result
            end

            # HM inferred Hash type → dispatch through hash methods
            if cls_name == "Hash"
              @variable_collection_types[recv_var] = :hash if recv_var
              result = generate_hash_method_call(method_name, receiver, args, result_var, block_def)
              return result if result
            end

            # HM inferred String type → dispatch through string methods
            if cls_name == "String"
              @variable_types[recv_var] = :string if recv_var
              if string_method?(method_name)
                result = generate_string_method_call(method_name, receiver, args, result_var)
                return result if result
              end
            end

            # HM inferred user class type — do NOT dispatch directly.
            # HM inference can be wrong without RBS. Fall through to invokedynamic
            # for safe runtime method resolution. Constructor-tracked variables are
            # already handled by is_user_class_receiver? above (line 1145).
          end
        end

        # If we reach here, the type was not resolved by HM inference or the
        # pre-codegen TypeResolver pass. Collect error for reporting.
        recv_hir_type = nil
        if receiver
          recv_hir_type = receiver.type if receiver.respond_to?(:type)
          recv_hir_type = recv_hir_type.prune if recv_hir_type.respond_to?(:prune)
        end
        location = @current_class_name ? "#{@current_class_name}##{@current_method_name}" : @current_method_name.to_s

        @unresolved_calls ||= []
        @unresolved_calls << "  #{location}: .#{method_name}(#{args.size} args) — receiver type: #{recv_hir_type || 'unknown'} [invokedynamic]"

        # Generate invokedynamic call for runtime method resolution
        instructions = []

        # If there's a block, compile it as a KBlock and include as extra argument
        kblock_var = nil
        if block_def
          all_captures = block_def.captures || []
          captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
          capture_types = captures.map { |c| @variable_types[c.name.to_s] || :value }

          # If inside instance method and block accesses instance vars, add self as implicit capture
          needs_self = @generating_instance_method && block_needs_self?(block_def)
          if needs_self
            self_capture = HIR::Capture.new(name: "__block_self__", type: TypeChecker::Types::UNTYPED)
            captures = [self_capture] + captures
            capture_types = [:value] + capture_types
          end

          # If block contains yield and outer function has a __block__ param, capture it
          if @block_param_slot && block_contains_yield?(block_def)
            block_capture = HIR::Capture.new(name: "__block__", type: TypeChecker::Types::UNTYPED)
            captures = captures + [block_capture]
            capture_types = capture_types + [:value]
          end

          # Compile block as static method with all-Object param/return types
          block_param_types = block_def.params.map { :value }
          block_ret_type = :value
          block_method_name = compile_block_as_method_with_types(
            block_def, capture_types, block_param_types, block_ret_type,
            filtered_captures: captures, self_capture: needs_self
          )

          # Create KBlock interface for this arity
          kblock_iface = get_or_create_kblock(block_param_types, block_ret_type)
          call_desc = kblock_call_descriptor(block_param_types, block_ret_type)

          # Load captures
          captures.each_with_index do |cap, i|
            if cap.name.to_s == "__block_self__"
              # Load self — use @block_self_slot for nested block contexts
              self_slot = @block_self_slot || 0
              instructions << { "op" => "aload", "var" => self_slot }
            else
              ct = capture_types[i]
              instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), ct))
            end
          end

          # invokedynamic LambdaMetafactory to create KBlock
          capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
          indy_desc = "(#{capture_desc})L#{kblock_iface};"
          block_method_params_desc = (capture_types + block_param_types).map { |t| type_to_descriptor(t) }.join
          block_method_full_desc = "(#{block_method_params_desc})#{type_to_descriptor(block_ret_type)}"

          instructions << {
            "op" => "invokedynamic",
            "name" => "call",
            "descriptor" => indy_desc,
            "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
            "bootstrapName" => "metafactory",
            "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
            "bootstrapArgs" => [
              { "type" => "methodType", "descriptor" => call_desc },
              { "type" => "handle", "tag" => "H_INVOKESTATIC",
                "owner" => @current_enclosing_class,
                "name" => block_method_name,
                "descriptor" => block_method_full_desc },
              { "type" => "methodType", "descriptor" => call_desc }
            ]
          }

          # Store KBlock in temp
          kblock_var = "__indy_kblock_#{@block_counter}"
          ensure_slot(kblock_var, :value)
          instructions << store_instruction(kblock_var, :value)
          @variable_types[kblock_var] = :value
        end

        # Load receiver (as Object)
        if receiver && !receiver.is_a?(HIR::SelfRef)
          instructions.concat(load_value(receiver, :value))
        elsif @generating_instance_method
          instructions << { "op" => "aload", "var" => 0 }  # self
        else
          instructions << { "op" => "aconst_null" }
        end

        # Load all args as Object
        args.each do |arg|
          instructions.concat(load_value(arg, :value))
        end

        # Build and load keyword arguments hash if present
        has_kwargs = inst.respond_to?(:keyword_args) && inst.has_keyword_args?
        if has_kwargs
          instructions.concat(build_kwargs_hash(inst.keyword_args))
        end

        # Load KBlock as additional argument if present
        if kblock_var
          instructions << load_instruction(kblock_var, :value)
        end

        # Build invokedynamic descriptor: (Object receiver, Object arg1, ..., [Object kwargs_hash], [Object block]) -> Object
        param_count = 1 + args.size + (has_kwargs ? 1 : 0) + (kblock_var ? 1 : 0)
        params_desc = "Ljava/lang/Object;" * param_count
        indy_desc = "(#{params_desc})Ljava/lang/Object;"

        instructions << {
          "op" => "invokedynamic",
          "name" => jvm_method_name(method_name),
          "descriptor" => indy_desc,
          "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
          "bootstrapName" => "bootstrap",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => []
        }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end

        return instructions
      end

      def generate_arithmetic_call(inst, op, receiver, arg, result_var)
        instructions = []

        # Determine types (check variable types AND literal types from HIR nodes)
        recv_var = extract_var_name(receiver)
        arg_var = extract_var_name(arg)
        recv_type = recv_var ? (@variable_types[recv_var] || :value) : (literal_type_tag(receiver) || :value)
        arg_type = arg_var ? (@variable_types[arg_var] || :value) : (literal_type_tag(arg) || :value)

        # Determine result type
        # Only do inline arithmetic when both operands are numeric, or it's string concat
        is_string_concat = (recv_type == :string || arg_type == :string) && op == "+"
        numeric_types = [:i64, :double]
        recv_numeric = numeric_types.include?(recv_type)
        arg_numeric = numeric_types.include?(arg_type)

        result_type = if is_string_concat
                        :string
                      elsif recv_numeric && arg_numeric
                        # Both numeric — inline arithmetic
                        (recv_type == :double || arg_type == :double) ? :double : :i64
                      elsif recv_numeric && arg_type == :value
                        # One numeric, one boxed — unbox and do inline arithmetic
                        recv_type == :double ? :double : :i64
                      elsif arg_numeric && recv_type == :value
                        # One boxed, one numeric — unbox and do inline arithmetic
                        arg_type == :double ? :double : :i64
                      else
                        # Can't determine concrete numeric type — use dynamic dispatch
                        return nil
                      end

        # No rebox needed — the only case that needed it (both :value) now uses dynamic dispatch
        needs_rebox = false

        ensure_slot(result_var, needs_rebox ? :value : result_type)

        # Load receiver (in its actual type)
        recv_loaded_type = recv_var ? (@variable_types[recv_var] || :value) : result_type
        instructions.concat(load_value(receiver, recv_loaded_type))

        # Unbox/cast if needed: Object → primitive or String
        # For string concat, always checkcast — JVM verifier may widen to Object at phi merge points
        if is_string_concat
          instructions << { "op" => "checkcast", "type" => "java/lang/String" }
        elsif recv_loaded_type == :value && result_type == :i64
          instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
          instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                            "name" => "longValue", "descriptor" => "()J" }
        elsif recv_loaded_type == :value && result_type == :double
          instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
          instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                            "name" => "doubleValue", "descriptor" => "()D" }
        elsif recv_type == :i64 && result_type == :double
          instructions << { "op" => "l2d" }
        end

        # Load argument (in its actual type)
        arg_loaded_type = arg_var ? (@variable_types[arg_var] || :value) : result_type
        instructions.concat(load_value(arg, arg_loaded_type))

        # Unbox/cast if needed
        if is_string_concat
          instructions << { "op" => "checkcast", "type" => "java/lang/String" }
        elsif arg_loaded_type == :value && result_type == :i64
          instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
          instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                            "name" => "longValue", "descriptor" => "()J" }
        elsif arg_loaded_type == :value && result_type == :double
          instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
          instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                            "name" => "doubleValue", "descriptor" => "()D" }
        elsif arg_type == :i64 && result_type == :double
          instructions << { "op" => "l2d" }
        end

        # Emit arithmetic operation
        if is_string_concat
          # String concatenation: call String.concat
          instructions << { "op" => "invokevirtual",
                            "owner" => "java/lang/String", "name" => "concat",
                            "descriptor" => "(Ljava/lang/String;)Ljava/lang/String;" }
        else
          instructions << arithmetic_instruction(op, result_type)
        end

        # Re-box if we unboxed for arithmetic on Object operands
        if needs_rebox
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                            "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          result_type = :value
        end

        # Store result
        instructions << store_instruction(result_var, result_type)
        @variable_types[result_var] = result_type

        instructions
      end

      def generate_comparison_call(inst, op, receiver, arg, result_var)
        instructions = []

        recv_var = extract_var_name(receiver)
        arg_var = extract_var_name(arg)
        recv_type = recv_var ? (@variable_types[recv_var] || :value) : (literal_type_tag(receiver) || :value)
        arg_type = arg_var ? (@variable_types[arg_var] || :value) : (literal_type_tag(arg) || :value)

        # :void (NilClass) should be treated as :value (Object) for comparison purposes
        recv_type = :value if recv_type == :void
        arg_type = :value if arg_type == :void

        # Check for user-defined comparison operator (e.g., class OpVec has def ==(other))
        # If the user class defines the operator, dispatch to it via invokevirtual
        # and convert the returned Object (Boolean) to an i8 boolean result.
        if receiver && !receiver.is_a?(HIR::SelfRef) && user_class_has_method?(receiver, op)
          return generate_user_defined_comparison(inst, op, receiver, arg, result_var)
        end

        # For ordering operators (<, >, <=, >=): if receiver's class defines <=>,
        # delegate to it: `a < b` becomes `(a <=> b) < 0`
        if %w[< > <= >=].include?(op) && receiver && !receiver.is_a?(HIR::SelfRef) &&
           user_class_has_method?(receiver, "<=>")
          return generate_comparable_via_spaceship(inst, op, receiver, arg, result_var)
        end

        # Determine comparison type
        # If either side is nil (literal or :value variable), always use null-safe object comparison
        has_nil = receiver.is_a?(HIR::NilLit) || arg.is_a?(HIR::NilLit)

        # For == and !=: if one side is :value (potentially null) and the other is numeric,
        # use object comparison to avoid NPE when unboxing null to primitive.
        # This handles inlined nil comparisons where nil becomes a LoadLocal with :value type.
        mixed_value_numeric = (op == "==" || op == "!=") &&
                              ((recv_type == :value && (arg_type == :i64 || arg_type == :double || arg_type == :i8)) ||
                               (arg_type == :value && (recv_type == :i64 || recv_type == :double || recv_type == :i8)))

        is_object_type = has_nil || mixed_value_numeric ||
                         recv_type == :string || arg_type == :string ||
                         (recv_type == :value && arg_type == :value &&
                          recv_type != :i64 && arg_type != :i64 &&
                          recv_type != :double && arg_type != :double)

        cmp_type = if is_object_type && (op == "==" || op == "!=")
                     :object
                   elsif recv_type == :double || arg_type == :double
                     :double
                   elsif recv_type == :i64 || arg_type == :i64
                     :i64
                   else
                     :object # default to Object.equals for unknown types
                   end

        ensure_slot(result_var, :i8)

        true_label = new_label("cmp_true")
        end_label = new_label("cmp_end")

        if cmp_type == :object
          # Nil comparison: use ifnull/ifnonnull (null-safe, avoids NPE)
          arg_is_nil = arg.is_a?(HIR::NilLit)
          recv_is_nil = receiver.is_a?(HIR::NilLit)

          if (op == "==" || op == "!=") && (arg_is_nil || recv_is_nil)
            # Load the non-nil side
            non_nil = arg_is_nil ? receiver : arg
            instructions.concat(load_value(non_nil, :value))
            if op == "=="
              instructions << { "op" => "ifnull", "target" => true_label }
            else
              instructions << { "op" => "ifnonnull", "target" => true_label }
            end
          elsif op == "==" || op == "!="
            instructions.concat(load_value(receiver, :value))
            instructions.concat(load_value(arg, :value))
            # Null-safe Object equality: use Objects.equals (handles null receiver)
            instructions << { "op" => "invokestatic", "owner" => "java/util/Objects",
                              "name" => "equals", "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Z" }
            instructions << { "op" => (op == "==" ? "ifne" : "ifeq"), "target" => true_label }
          else
            # Ordering comparison (>, <, >=, <=): unbox to Long and use lcmp
            instructions.concat(load_value(receiver, :value))
            instructions.concat(load_value(arg, :value))
            # Stack: [receiver_obj, arg_obj]
            # Unbox arg (top of stack), store temporarily
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "longValue", "descriptor" => "()J" }
            cmp_tmp = ensure_slot("__cmp_tmp__", :i64)
            instructions << { "op" => "lstore", "var" => cmp_tmp }
            # Stack: [receiver_obj] — unbox receiver
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "longValue", "descriptor" => "()J" }
            # Stack: [receiver_long] — reload arg
            instructions << { "op" => "lload", "var" => cmp_tmp }
            # Stack: [receiver_long, arg_long] — lcmp = sign(receiver - arg)
            instructions << { "op" => "lcmp" }
            jump_op = case op
                      when "<" then "iflt"
                      when ">" then "ifgt"
                      when "<=" then "ifle"
                      when ">=" then "ifge"
                      end
            instructions << { "op" => jump_op, "target" => true_label }
          end
        else
          # Load values (in their actual types, then convert if needed)
          recv_loaded_type = recv_var ? (@variable_types[recv_var] || :value) : cmp_type
          instructions.concat(load_value(receiver, recv_loaded_type))
          if recv_loaded_type == :value && cmp_type == :i64
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "longValue", "descriptor" => "()J" }
          elsif recv_loaded_type == :value && cmp_type == :double
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "doubleValue", "descriptor" => "()D" }
          elsif recv_type == :i64 && cmp_type == :double
            instructions << { "op" => "l2d" }
          end

          arg_loaded_type = arg_var ? (@variable_types[arg_var] || :value) : cmp_type
          instructions.concat(load_value(arg, arg_loaded_type))
          if arg_loaded_type == :value && cmp_type == :i64
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "longValue", "descriptor" => "()J" }
          elsif arg_loaded_type == :value && cmp_type == :double
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "doubleValue", "descriptor" => "()D" }
          elsif arg_type == :i64 && cmp_type == :double
            instructions << { "op" => "l2d" }
          end

          # Compare
          if cmp_type == :i64
            instructions << { "op" => "lcmp" }
            jump_op = case op
                      when "<" then "iflt"
                      when ">" then "ifgt"
                      when "<=" then "ifle"
                      when ">=" then "ifge"
                      when "==" then "ifeq"
                      when "!=" then "ifne"
                      end
            instructions << { "op" => jump_op, "target" => true_label }
          else
            instructions << { "op" => "dcmpg" }
            jump_op = case op
                      when "<" then "iflt"
                      when ">" then "ifgt"
                      when "<=" then "ifle"
                      when ">=" then "ifge"
                      when "==" then "ifeq"
                      when "!=" then "ifne"
                      end
            instructions << { "op" => jump_op, "target" => true_label }
          end
        end

        # False path
        instructions << { "op" => "iconst", "value" => 0 }
        instructions << { "op" => "goto", "target" => end_label }

        # True path
        instructions << { "op" => "label", "name" => true_label }
        instructions << { "op" => "iconst", "value" => 1 }

        # End
        instructions << { "op" => "label", "name" => end_label }
        instructions << store_instruction(result_var, :i8)
        @variable_types[result_var] = :i8

        instructions
      end

      # Dispatch a comparison operator to a user-defined method (e.g., OpVec#==)
      # and convert the returned Object to an i8 boolean result.
      def generate_user_defined_comparison(inst, op, receiver, arg, result_var)
        instructions = []
        recv_class_name = resolve_receiver_class(receiver)
        info = @class_info[recv_class_name]
        jvm_class = info[:jvm_name]
        jvm_name = jvm_method_name(op)

        # Look up the method descriptor
        target_func = find_class_instance_method(recv_class_name, op)
        descriptor_key = "#{jvm_class}.#{jvm_name}"
        desc = @method_descriptors[descriptor_key]

        unless desc
          # Build descriptor from the target function
          param_desc = target_func ? target_func.params.each_with_index.map { |p, i|
            t = widened_param_type(target_func, p, i)
            type_to_descriptor(t)
          }.join : "Ljava/lang/Object;"
          ret_desc = "Ljava/lang/Object;"
          desc = "(#{param_desc})#{ret_desc}"
        end

        # Load receiver + checkcast
        instructions.concat(load_value(receiver, :value))
        instructions << { "op" => "checkcast", "type" => jvm_class }

        # Load argument
        if target_func && target_func.params.size == 1
          param = target_func.params.first
          param_t = widened_param_type(target_func, param, 0)
          instructions.concat(load_value(arg, param_t))
          loaded_t = infer_loaded_type(arg)
          instructions.concat(unbox_if_needed(loaded_t, param_t))
        else
          instructions.concat(load_value(arg, :value))
        end

        # Call the user-defined operator method
        instructions << { "op" => "invokevirtual", "owner" => jvm_class,
                          "name" => jvm_name, "descriptor" => desc }

        # Convert the returned Object (Boolean) to i8 boolean
        # Ruby truthiness: null → false, Boolean.FALSE → false, else → true
        ensure_slot(result_var, :i8)
        truthy_label = new_label("udc_truthy")
        falsy_label = new_label("udc_falsy")
        end_label = new_label("udc_end")

        instructions << { "op" => "dup" }
        instructions << { "op" => "ifnull", "target" => falsy_label }
        # Not null — check for Boolean.FALSE
        instructions << { "op" => "instanceof", "type" => "java/lang/Boolean" }
        instructions << { "op" => "ifeq", "target" => truthy_label } # not a Boolean → truthy
        # Reload and unbox Boolean
        # Actually we popped the original during instanceof; we need a different approach
        # Let's use a simpler approach: call isTruthy-style logic
        instructions.pop(4) # remove the dup/ifnull/instanceof/ifeq

        # Simpler: check if the result is Boolean.FALSE or null
        result_tmp = "__udc_result_#{@label_counter}"
        @label_counter += 1
        ensure_slot(result_tmp, :value)
        instructions << store_instruction(result_tmp, :value)

        instructions << load_instruction(result_tmp, :value)
        instructions << { "op" => "ifnull", "target" => falsy_label }

        instructions << load_instruction(result_tmp, :value)
        instructions << { "op" => "instanceof", "type" => "java/lang/Boolean" }
        instructions << { "op" => "ifeq", "target" => truthy_label }

        # It's a Boolean — unbox and check
        instructions << load_instruction(result_tmp, :value)
        instructions << { "op" => "checkcast", "type" => "java/lang/Boolean" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/Boolean",
                          "name" => "booleanValue", "descriptor" => "()Z" }
        instructions << { "op" => "ifeq", "target" => falsy_label }
        # Boolean.TRUE → true
        instructions << { "op" => "goto", "target" => truthy_label }

        instructions << { "op" => "label", "name" => falsy_label }
        if op == "!="
          instructions << { "op" => "iconst", "value" => 1 }
        else
          instructions << { "op" => "iconst", "value" => 0 }
        end
        instructions << { "op" => "goto", "target" => end_label }

        instructions << { "op" => "label", "name" => truthy_label }
        if op == "!="
          instructions << { "op" => "iconst", "value" => 0 }
        else
          instructions << { "op" => "iconst", "value" => 1 }
        end

        instructions << { "op" => "label", "name" => end_label }
        instructions << store_instruction(result_var, :i8)
        @variable_types[result_var] = :i8

        instructions
      end

      # Generate comparison via <=> (Comparable pattern):
      # `a < b` → `(a <=> b) < 0`, `a > b` → `(a <=> b) > 0`, etc.
      def generate_comparable_via_spaceship(inst, op, receiver, arg, result_var)
        instructions = []
        recv_class_name = resolve_receiver_class(receiver)
        info = @class_info[recv_class_name]
        jvm_class = info[:jvm_name]

        # Look up <=> method
        target_func = find_class_instance_method(recv_class_name, "<=>")
        spaceship_jvm = jvm_method_name("<=>")
        descriptor_key = "#{jvm_class}.#{spaceship_jvm}"
        desc = @method_descriptors[descriptor_key]

        unless desc
          param_desc = target_func ? target_func.params.each_with_index.map { |p, i|
            t = widened_param_type(target_func, p, i)
            type_to_descriptor(t)
          }.join : "Ljava/lang/Object;"
          ret_desc = "Ljava/lang/Object;"
          desc = "(#{param_desc})#{ret_desc}"
        end

        # Load receiver + checkcast
        instructions.concat(load_value(receiver, :value))
        instructions << { "op" => "checkcast", "type" => jvm_class }

        # Load argument
        if target_func && target_func.params.size == 1
          param = target_func.params.first
          param_t = widened_param_type(target_func, param, 0)
          instructions.concat(load_value(arg, param_t))
          loaded_t = infer_loaded_type(arg)
          instructions.concat(unbox_if_needed(loaded_t, param_t))
        else
          instructions.concat(load_value(arg, :value))
        end

        # Call <=> — returns Long (Integer result: -1, 0, 1)
        instructions << { "op" => "invokevirtual", "owner" => jvm_class,
                          "name" => spaceship_jvm, "descriptor" => desc }

        # Unbox the result (Object → long)
        instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                          "name" => "longValue", "descriptor" => "()J" }

        # Compare with 0: lcmp result is already -1/0/1 as long; convert to int for ifXX
        instructions << { "op" => "lconst_0" }
        instructions << { "op" => "lcmp" }

        true_label = new_label("cmp_spaceship_true")
        end_label = new_label("cmp_spaceship_end")

        jump_op = case op
                  when "<" then "iflt"
                  when ">" then "ifgt"
                  when "<=" then "ifle"
                  when ">=" then "ifge"
                  end
        instructions << { "op" => jump_op, "target" => true_label }

        # False path
        ensure_slot(result_var, :i8)
        instructions << { "op" => "iconst", "value" => 0 }
        instructions << { "op" => "goto", "target" => end_label }

        # True path
        instructions << { "op" => "label", "name" => true_label }
        instructions << { "op" => "iconst", "value" => 1 }

        instructions << { "op" => "label", "name" => end_label }
        instructions << store_instruction(result_var, :i8)
        @variable_types[result_var] = :i8

        instructions
      end

      # ---- raise → new RuntimeException(message) + athrow ----

      def generate_raise_call(args, result_var)
        instructions = []

        instructions << { "op" => "new", "type" => "java/lang/RuntimeException" }
        instructions << { "op" => "dup" }

        if args.empty?
          # raise with no args → RuntimeException()
          instructions << { "op" => "invokespecial",
                            "owner" => "java/lang/RuntimeException", "name" => "<init>",
                            "descriptor" => "()V" }
        else
          # raise "message" or raise ExceptionClass, "message"
          # For now, use last string arg as message
          msg_arg = args.size == 1 ? args.first : args.last
          instructions.concat(load_value(msg_arg, :string))

          # Ensure we have a String on stack (convert if needed)
          msg_var = extract_var_name(msg_arg)
          msg_type = msg_var ? (@variable_types[msg_var] || :value) : :value
          if msg_type == :i64
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                              "name" => "toString", "descriptor" => "(J)Ljava/lang/String;" }
          elsif msg_type == :double
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                              "name" => "toString", "descriptor" => "(D)Ljava/lang/String;" }
          elsif msg_type == :value
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Object",
                              "name" => "toString", "descriptor" => "()Ljava/lang/String;" }
          end

          instructions << { "op" => "invokespecial",
                            "owner" => "java/lang/RuntimeException", "name" => "<init>",
                            "descriptor" => "(Ljava/lang/String;)V" }
        end

        instructions << { "op" => "athrow" }

        instructions
      end

      # ---- begin/rescue/else/ensure ----

      def generate_begin_rescue(inst, inlined_try_body: nil, bb_instructions: nil)
        instructions = []

        try_start = new_label("try_start")
        try_end = new_label("try_end")
        after_all = new_label("after_all")

        has_rescue = inst.rescue_clauses && !inst.rescue_clauses.empty?
        has_else = inst.else_blocks && !inst.else_blocks.empty?
        has_ensure = inst.ensure_blocks && !inst.ensure_blocks.empty?

        # Build a map from body_blocks/ensure_blocks/else_blocks expression IDs to their
        # wrapping StoreLocal instructions from the main BB. The HIR builder extracts
        # StoreLocal wrappers into the main BB and only puts the value expression in
        # body_blocks. We need to re-associate them for correct code generation.
        orphaned_stores = {}  # expression_object_id => StoreLocal instruction
        if bb_instructions && inst.non_try_instruction_ids
          non_try_ids = inst.non_try_instruction_ids
          # Collect all body expression IDs
          body_expr_ids = Set.new
          inst.rescue_clauses&.each do |clause|
            clause.body_blocks&.each { |bi| body_expr_ids << bi.object_id }
          end
          inst.ensure_blocks&.each { |bi| body_expr_ids << bi.object_id }
          inst.else_blocks&.each { |bi| body_expr_ids << bi.object_id }

          bb_instructions.each do |bi|
            next unless bi.is_a?(HIR::StoreLocal) && non_try_ids.include?(bi.object_id)
            # This StoreLocal wraps one of the body expressions
            val_id = bi.value.object_id
            orphaned_stores[val_id] = bi if body_expr_ids.include?(val_id)
          end
        end

        # Use inlined try body if provided (from block's pre-BeginRescue instructions),
        # otherwise fall back to BeginRescue's stored try_blocks
        try_body = inlined_try_body || inst.try_blocks || []

        # If the begin/rescue has a result variable, pre-initialize it with null
        result_var = inst.result_var
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          @variable_types[result_var.to_s] = :value
        end

        # Labels for rescue handlers
        handler_labels = []
        if has_rescue
          inst.rescue_clauses.each_with_index do |_clause, i|
            handler_labels << new_label("handler_#{i}")
          end
        end

        # Label for else block
        else_label = new_label("rescue_else") if has_else

        # Label for normal ensure path
        ensure_normal_label = new_label("ensure_normal") if has_ensure

        # Label for exception ensure path (catch-all)
        finally_handler_label = new_label("finally_handler") if has_ensure

        # 1. Try block (generate BEFORE registering outer exception handlers,
        # so that inner/nested BeginRescue handlers appear first in the table.
        # JVM checks exception table entries in order; first match wins.)
        instructions << { "op" => "label", "name" => try_start }
        last_try_result = nil
        try_body.each do |try_inst|
          instructions.concat(generate_instruction(try_inst))
          last_try_result = try_inst.result_var if try_inst.respond_to?(:result_var) && try_inst.result_var
        end
        instructions << { "op" => "label", "name" => try_end }

        # Register exception table entries AFTER try body is generated
        # (so nested handlers from inner BeginRescue appear before outer ones)
        if has_rescue
          inst.rescue_clauses.each_with_index do |clause, i|
            clause.exception_classes.each do |exc_class|
              jvm_exc = ruby_exception_to_jvm(exc_class)
              @pending_exception_table << {
                "start" => try_start,
                "end" => try_end,
                "handler" => handler_labels[i],
                "type" => jvm_exc
              }
            end
          end
        end

        # Register catch-all for ensure (must be AFTER specific handlers)
        if has_ensure
          @pending_exception_table << {
            "start" => try_start,
            "end" => try_end,
            "handler" => finally_handler_label,
            "type" => nil  # catch all
          }
        end

        # Store try block result to result_var if present
        if result_var && last_try_result
          last_type = @variable_types[last_try_result.to_s] || :value
          instructions.concat(load_value_from_var(last_try_result.to_s, last_type))
          instructions.concat(box_primitive_if_needed(last_type, :value))
          instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
        end

        # After try: jump to else or ensure_normal or after_all
        if has_else
          instructions << { "op" => "goto", "target" => else_label }
        elsif has_ensure
          instructions << { "op" => "goto", "target" => ensure_normal_label }
        else
          instructions << { "op" => "goto", "target" => after_all }
        end

        # 2. Rescue handlers
        if has_rescue
          inst.rescue_clauses.each_with_index do |clause, i|
            instructions << { "op" => "label", "name" => handler_labels[i] }

            # Exception object is on top of stack
            if clause.exception_var
              exc_slot = allocate_slot(clause.exception_var, :value)
              instructions << { "op" => "astore", "var" => exc_slot }
              @variable_types[clause.exception_var] = :value
            else
              instructions << { "op" => "pop" }  # discard exception
            end

            # Generate rescue body
            last_rescue_result = nil
            clause.body_blocks&.each do |body_inst|
              instructions.concat(generate_instruction(body_inst))
              last_rescue_result = body_inst.result_var if body_inst.respond_to?(:result_var) && body_inst.result_var
              # Generate orphaned StoreLocal that wraps this body expression
              if (store_inst = orphaned_stores[body_inst.object_id])
                instructions.concat(generate_instruction(store_inst))
              end
            end

            # Store rescue body result to result_var
            if result_var && last_rescue_result
              last_type = @variable_types[last_rescue_result.to_s] || :value
              instructions.concat(load_value_from_var(last_rescue_result.to_s, last_type))
              instructions.concat(box_primitive_if_needed(last_type, :value))
              instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
            end

            # Jump to ensure or after_all
            if has_ensure
              instructions << { "op" => "goto", "target" => ensure_normal_label }
            else
              instructions << { "op" => "goto", "target" => after_all }
            end
          end
        end

        # 3. Finally handler (catch-all for ensure with exception)
        if has_ensure
          instructions << { "op" => "label", "name" => finally_handler_label }
          exc_temp_slot = @next_slot
          @next_slot += 1  # allocate temp slot for exception
          instructions << { "op" => "astore", "var" => exc_temp_slot }

          # Run ensure body
          inst.ensure_blocks.each do |ensure_inst|
            instructions.concat(generate_instruction(ensure_inst))
            # Generate orphaned StoreLocal that wraps this ensure expression
            if (store_inst = orphaned_stores[ensure_inst.object_id])
              instructions.concat(generate_instruction(store_inst))
            end
          end

          # Re-throw
          instructions << { "op" => "aload", "var" => exc_temp_slot }
          instructions << { "op" => "athrow" }
        end

        # 4. Else block
        if has_else
          instructions << { "op" => "label", "name" => else_label }
          last_else_result = nil
          inst.else_blocks.each do |else_inst|
            instructions.concat(generate_instruction(else_inst))
            last_else_result = else_inst.result_var if else_inst.respond_to?(:result_var) && else_inst.result_var
            # Generate orphaned StoreLocal that wraps this else expression
            if (store_inst = orphaned_stores[else_inst.object_id])
              instructions.concat(generate_instruction(store_inst))
            end
          end
          # Else block result overrides the try block result
          if result_var && last_else_result
            last_type = @variable_types[last_else_result.to_s] || :value
            instructions.concat(load_value_from_var(last_else_result.to_s, last_type))
            instructions.concat(box_primitive_if_needed(last_type, :value))
            instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          end
          if has_ensure
            instructions << { "op" => "goto", "target" => ensure_normal_label }
          else
            instructions << { "op" => "goto", "target" => after_all }
          end
        end

        # 5. Normal ensure path
        if has_ensure
          instructions << { "op" => "label", "name" => ensure_normal_label }
          inst.ensure_blocks.each do |ensure_inst|
            instructions.concat(generate_instruction(ensure_inst))
            # Generate orphaned StoreLocal that wraps this ensure expression
            if (store_inst = orphaned_stores[ensure_inst.object_id])
              instructions.concat(generate_instruction(store_inst))
            end
          end
        end

        instructions << { "op" => "label", "name" => after_all }
        instructions
      end

      # ========================================================================
      # case/when Statement
      # ========================================================================

      def generate_case_statement(inst)
        instructions = []
        after_all = new_label("case_end")
        result_var = inst.result_var

        # Pre-initialize result variable
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          @variable_types[result_var.to_s] = :value
        end

        # Load predicate once and store in temp slot
        pred_slot = nil
        if inst.predicate
          # load_value(:value) handles all boxing via box_primitive_if_needed
          instructions.concat(load_value(inst.predicate, :value))
          pred_slot = @next_slot
          @next_slot += 1
          instructions << { "op" => "astore", "var" => pred_slot }
        end

        # Generate when clauses
        inst.when_clauses.each_with_index do |when_clause, i|
          body_label = new_label("when_body_#{i}")
          next_label = new_label("when_next_#{i}")

          # Evaluate conditions (OR them together)
          when_clause.conditions.each_with_index do |cond, ci|
            match_label = (ci == when_clause.conditions.size - 1) ? nil : new_label("when_cond_#{i}_#{ci + 1}")

            if pred_slot
              # Load predicate
              instructions << { "op" => "aload", "var" => pred_slot }

              # Load condition value (load_value(:value) handles all boxing)
              instructions.concat(load_value(cond, :value))

              # Compare using Object.equals()
              instructions << { "op" => "invokevirtual", "owner" => "java/lang/Object",
                                "name" => "equals", "descriptor" => "(Ljava/lang/Object;)Z" }
            else
              # No predicate - evaluate condition as truthy
              instructions.concat(load_value(cond, :value))
              # Convert to boolean (non-null = true)
              instructions << { "op" => "ifnonnull", "target" => body_label }
              if match_label
                instructions << { "op" => "goto", "target" => match_label }
              else
                instructions << { "op" => "goto", "target" => next_label }
              end
              if match_label
                instructions << { "op" => "label", "name" => match_label }
              end
              next
            end

            # Branch on comparison result
            if ci < when_clause.conditions.size - 1
              # More conditions to check - if true, go to body
              instructions << { "op" => "ifne", "target" => body_label }
              if match_label
                instructions << { "op" => "label", "name" => match_label }
              end
            else
              # Last condition - if false, go to next when
              instructions << { "op" => "ifeq", "target" => next_label }
            end
          end

          # When body
          instructions << { "op" => "label", "name" => body_label }
          last_body_result = nil
          when_clause.body.each do |body_inst|
            instructions.concat(generate_instruction(body_inst))
            last_body_result = body_inst.result_var if body_inst.respond_to?(:result_var) && body_inst.result_var
          end

          # Store body result
          if result_var && last_body_result
            last_type = @variable_types[last_body_result.to_s] || :value
            instructions.concat(load_value_from_var(last_body_result.to_s, last_type))
            if last_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif last_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            end
            instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          end
          instructions << { "op" => "goto", "target" => after_all }

          instructions << { "op" => "label", "name" => next_label }
        end

        # Else body
        if inst.else_body && !inst.else_body.empty?
          last_else_result = nil
          inst.else_body.each do |else_inst|
            instructions.concat(generate_instruction(else_inst))
            last_else_result = else_inst.result_var if else_inst.respond_to?(:result_var) && else_inst.result_var
          end

          if result_var && last_else_result
            last_type = @variable_types[last_else_result.to_s] || :value
            instructions.concat(load_value_from_var(last_else_result.to_s, last_type))
            if last_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif last_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            end
            instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          end
        end

        instructions << { "op" => "label", "name" => after_all }
        instructions
      end

      def load_value_from_var(var_name, type)
        slot = @variable_slots[var_name.to_s]
        return [] unless slot
        case type
        when :i64 then [{ "op" => "lload", "var" => slot }]
        when :double then [{ "op" => "dload", "var" => slot }]
        when :i8 then [{ "op" => "iload", "var" => slot }]
        else [{ "op" => "aload", "var" => slot }]
        end
      end

      # ========================================================================
      # J8.5: case/in Pattern Matching
      # ========================================================================

      # Ruby type → JVM instanceof class mapping
      RUBY_TYPE_TO_JVM_CLASS = {
        "Integer" => "java/lang/Long",
        "Float" => "java/lang/Double",
        "String" => "java/lang/String",
      }.freeze

      def generate_case_match_statement(inst)
        instructions = []
        after_all = new_label("match_end")
        result_var = inst.result_var

        # Pre-initialize result variable with null
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          @variable_types[result_var.to_s] = :value
        end

        # Load predicate once, box to Object, store in temp slot
        pred_slot = nil
        if inst.predicate
          # load_value(:value) handles all boxing via box_primitive_if_needed
          instructions.concat(load_value(inst.predicate, :value))
          pred_slot = @next_slot
          @next_slot += 1
          instructions << { "op" => "astore", "var" => pred_slot }
        end

        # Generate each in clause
        inst.in_clauses.each_with_index do |in_clause, i|
          body_label = new_label("in_body_#{i}")
          next_label = new_label("in_next_#{i}")

          # Compile pattern match
          match_insts, bound_vars = compile_jvm_pattern(in_clause.pattern, pred_slot)
          instructions.concat(match_insts)
          # Stack now has int 0/1 from pattern match

          # Check guard if present
          if in_clause.guard
            guard_label = new_label("guard_#{i}")
            instructions << { "op" => "ifeq", "target" => next_label }

            # Bind pattern variables before evaluating guard
            instructions << { "op" => "label", "name" => guard_label }
            instructions.concat(bind_pattern_vars(bound_vars, pred_slot))

            # Evaluate guard
            guard_insts = generate_instruction(in_clause.guard)
            instructions.concat(guard_insts)
            # Guard result is on stack or in result_var
            guard_result_var = in_clause.guard.result_var if in_clause.guard.respond_to?(:result_var)
            guard_type = :value
            if guard_result_var
              guard_type = @variable_types[guard_result_var.to_s] || :value
              instructions.concat(load_value_from_var(guard_result_var.to_s, guard_type))
            end
            # Check truthiness based on guard result type
            if guard_type == :i8
              # Boolean/int result: 0 = false, non-zero = true
              instructions << { "op" => "ifeq", "target" => next_label }
            else
              # Object result: null = false, non-null = truthy
              instructions << { "op" => "ifnull", "target" => next_label }
            end
            instructions << { "op" => "goto", "target" => body_label }
          else
            instructions << { "op" => "ifeq", "target" => next_label }
          end

          # In clause body
          instructions << { "op" => "label", "name" => body_label }

          # Bind pattern variables (if not already done for guard)
          unless in_clause.guard
            instructions.concat(bind_pattern_vars(bound_vars, pred_slot))
          end

          # Execute body
          last_body_result = nil
          in_clause.body.each do |body_inst|
            instructions.concat(generate_instruction(body_inst))
            last_body_result = body_inst.result_var if body_inst.respond_to?(:result_var) && body_inst.result_var
          end

          # Store body result
          if result_var && last_body_result
            last_type = @variable_types[last_body_result.to_s] || :value
            instructions.concat(load_value_from_var(last_body_result.to_s, last_type))
            if last_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif last_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            end
            instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          end
          instructions << { "op" => "goto", "target" => after_all }

          instructions << { "op" => "label", "name" => next_label }
        end

        # Else body or no-matching-pattern error
        if inst.else_body && !inst.else_body.empty?
          last_else_result = nil
          inst.else_body.each do |else_inst|
            instructions.concat(generate_instruction(else_inst))
            last_else_result = else_inst.result_var if else_inst.respond_to?(:result_var) && else_inst.result_var
          end

          if result_var && last_else_result
            last_type = @variable_types[last_else_result.to_s] || :value
            instructions.concat(load_value_from_var(last_else_result.to_s, last_type))
            if last_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif last_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            end
            instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          end
        else
          # No else clause → throw RuntimeException("no matching pattern")
          instructions << { "op" => "new", "type" => "java/lang/RuntimeException" }
          instructions << { "op" => "dup" }
          instructions << { "op" => "ldc", "value" => "no matching pattern" }
          instructions << { "op" => "invokespecial", "owner" => "java/lang/RuntimeException",
                            "name" => "<init>", "descriptor" => "(Ljava/lang/String;)V" }
          instructions << { "op" => "athrow" }
        end

        instructions << { "op" => "label", "name" => after_all }
        instructions
      end

      # Compile a pattern into JVM bytecode.
      # Returns [instructions, bound_vars] where:
      #   - instructions leave an int (0/1) on the stack indicating match
      #   - bound_vars is a Hash { var_name => :predicate | :literal_value }
      def compile_jvm_pattern(pattern, pred_slot)
        case pattern
        when HIR::LiteralPattern
          compile_jvm_literal_pattern(pattern, pred_slot)
        when HIR::ConstantPattern
          compile_jvm_constant_pattern(pattern, pred_slot)
        when HIR::VariablePattern
          compile_jvm_variable_pattern(pattern, pred_slot)
        when HIR::AlternationPattern
          compile_jvm_alternation_pattern(pattern, pred_slot)
        when HIR::CapturePattern
          compile_jvm_capture_pattern(pattern, pred_slot)
        when HIR::PinnedPattern
          compile_jvm_pinned_pattern(pattern, pred_slot)
        when HIR::RestPattern
          compile_jvm_rest_pattern(pattern, pred_slot)
        when HIR::ArrayPattern
          compile_jvm_array_pattern(pattern, pred_slot)
        when HIR::HashPattern
          compile_jvm_hash_pattern(pattern, pred_slot)
        else
          # Unknown pattern - always match
          [[{ "op" => "iconst", "value" => 1 }], {}]
        end
      end

      # Literal pattern: box and use Object.equals()
      def compile_jvm_literal_pattern(pattern, pred_slot)
        instructions = []
        bound_vars = {}

        # Load predicate
        instructions << { "op" => "aload", "var" => pred_slot }

        # Load literal value as boxed Object
        instructions.concat(load_value(pattern.value, :value))

        # Compare using Object.equals()
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/Object",
                          "name" => "equals", "descriptor" => "(Ljava/lang/Object;)Z" }

        [instructions, bound_vars]
      end

      # Constant/Type pattern: instanceof check
      def compile_jvm_constant_pattern(pattern, pred_slot)
        instructions = []
        bound_vars = {}

        jvm_class = RUBY_TYPE_TO_JVM_CLASS[pattern.constant_name]
        if jvm_class
          # Load predicate and check instanceof
          instructions << { "op" => "aload", "var" => pred_slot }
          instructions << { "op" => "instanceof", "type" => jvm_class }
        else
          # Unknown constant type - always false
          instructions << { "op" => "iconst", "value" => 0 }
        end

        [instructions, bound_vars]
      end

      # Variable pattern: always matches, binds value to variable
      def compile_jvm_variable_pattern(pattern, pred_slot)
        instructions = []
        bound_vars = { pattern.name => :predicate }

        # Always matches
        instructions << { "op" => "iconst", "value" => 1 }

        [instructions, bound_vars]
      end

      # Alternation pattern: early-exit branching
      # If any alternative matches, jump to match_ok label and push 1.
      # Otherwise push 0.
      def compile_jvm_alternation_pattern(pattern, pred_slot)
        instructions = []
        bound_vars = {}
        match_ok = new_label("alt_match")
        match_done = new_label("alt_done")

        pattern.alternatives.each_with_index do |alt, i|
          alt_insts, alt_vars = compile_jvm_pattern(alt, pred_slot)
          instructions.concat(alt_insts)
          bound_vars.merge!(alt_vars)
          # If this alternative matched, short-circuit to match_ok
          instructions << { "op" => "ifne", "target" => match_ok }
        end

        # No alternative matched
        instructions << { "op" => "iconst", "value" => 0 }
        instructions << { "op" => "goto", "target" => match_done }

        # At least one matched
        instructions << { "op" => "label", "name" => match_ok }
        instructions << { "op" => "iconst", "value" => 1 }

        instructions << { "op" => "label", "name" => match_done }

        [instructions, bound_vars]
      end

      # Capture pattern: match inner pattern and bind value to variable
      # Example: `in Integer => n`
      def compile_jvm_capture_pattern(pattern, pred_slot)
        # Match the inner pattern
        inner_insts, inner_vars = compile_jvm_pattern(pattern.value_pattern, pred_slot)
        bound_vars = inner_vars.dup
        # Bind the predicate value to the capture target variable
        bound_vars[pattern.target] = :predicate
        [inner_insts, bound_vars]
      end

      # Pinned pattern: match against existing variable value using Object.equals()
      # Example: `in ^expected`
      def compile_jvm_pinned_pattern(pattern, pred_slot)
        instructions = []
        var_name = pattern.variable_name.to_s

        # Load the pinned variable's value (box to Object if primitive)
        var_type = @variable_types[var_name] || :value
        instructions << load_instruction(var_name, var_type)
        instructions.concat(box_primitive_if_needed(var_type, :value))

        # Load predicate
        instructions << { "op" => "aload", "var" => pred_slot }

        # Compare using Object.equals()
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/Object",
                          "name" => "equals", "descriptor" => "(Ljava/lang/Object;)Z" }

        [instructions, {}]
      end

      # Rest pattern: always matches, optionally binds remaining elements
      # Example: `*rest` or `*`
      def compile_jvm_rest_pattern(pattern, pred_slot)
        bound_vars = {}
        bound_vars[pattern.name] = :predicate if pattern.name
        [[{ "op" => "iconst", "value" => 1 }], bound_vars]
      end

      # Array pattern: call deconstruct, check size, match elements
      # Example: `in [a, b]`, `in [first, *rest]`, `in [first, *mid, last]`
      def compile_jvm_array_pattern(pattern, pred_slot)
        instructions = []
        bound_vars = {}
        match_fail = new_label("arr_pat_fail")
        match_done = new_label("arr_pat_done")

        # Pre-allocate and null-initialize all element slots to satisfy JVM verifier.
        # The verifier requires all slots to be initialized on all code paths.
        pre_slots = []
        total_elements = pattern.requireds.size + pattern.posts.size
        total_elements.times do
          s = @next_slot
          @next_slot += 1
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => s }
          pre_slots << s
        end

        # Pre-allocate rest slot if needed
        rest_slot = nil
        if pattern.rest && pattern.rest.name
          rest_slot = @next_slot
          @next_slot += 1
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => rest_slot }
        end

        # Step 1: Call deconstruct on the predicate via invokedynamic
        deconstructed_slot = @next_slot
        @next_slot += 1
        instructions << { "op" => "aload", "var" => pred_slot }
        # deconstruct() takes no args: (Object receiver) -> Object
        instructions << {
          "op" => "invokedynamic",
          "name" => "deconstruct",
          "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;",
          "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
          "bootstrapName" => "bootstrap",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => []
        }
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << { "op" => "astore", "var" => deconstructed_slot }

        # Step 2: Check array size
        required_count = pattern.requireds.size + pattern.posts.size
        instructions << { "op" => "aload", "var" => deconstructed_slot }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << { "op" => "l2i" }
        instructions << { "op" => "iconst", "value" => required_count }
        if pattern.rest
          # size < required → fail
          instructions << { "op" => "if_icmplt", "target" => match_fail }
        else
          # size != required → fail
          instructions << { "op" => "if_icmpne", "target" => match_fail }
        end

        # Step 3: Match each required element (using pre-allocated slots)
        pattern.requireds.each_with_index do |elem_pattern, i|
          elem_slot = pre_slots[i]
          instructions << { "op" => "aload", "var" => deconstructed_slot }
          instructions << { "op" => "iconst", "value" => i }
          instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                            "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
          instructions << { "op" => "astore", "var" => elem_slot }

          elem_insts, elem_vars = compile_jvm_pattern(elem_pattern, elem_slot)
          instructions.concat(elem_insts)
          instructions << { "op" => "ifeq", "target" => match_fail }
          # Rewrite :predicate to elem_slot so bind_pattern_vars uses element, not outer predicate
          elem_vars.each { |k, v| bound_vars[k] = (v == :predicate ? elem_slot : v) }
        end

        # Step 4: Handle rest pattern (bind remaining elements as KArray)
        if pattern.rest && pattern.rest.name
          rest_start = pattern.requireds.size
          # Create sublist: deconstructed.subList(start, size - posts.size)
          instructions << { "op" => "aload", "var" => deconstructed_slot }
          instructions << { "op" => "iconst", "value" => rest_start }
          # end index = size - posts.size
          instructions << { "op" => "aload", "var" => deconstructed_slot }
          instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                            "name" => "length", "descriptor" => "()J" }
          instructions << { "op" => "l2i" }
          instructions << { "op" => "iconst", "value" => pattern.posts.size }
          instructions << { "op" => "isub" }
          instructions << { "op" => "invokeinterface", "owner" => "java/util/List",
                            "name" => "subList", "descriptor" => "(II)Ljava/util/List;" }
          # Wrap in a new KArray
          instructions << { "op" => "new", "type" => KARRAY_CLASS }
          instructions << { "op" => "dup_x1" }
          instructions << { "op" => "swap" }
          instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                            "name" => "<init>", "descriptor" => "(Ljava/util/Collection;)V" }
          instructions << { "op" => "astore", "var" => rest_slot }
          bound_vars[pattern.rest.name] = rest_slot
        end

        # Step 5: Match post elements (from the end, using pre-allocated slots)
        pattern.posts.each_with_index do |post_pattern, i|
          post_slot = pre_slots[pattern.requireds.size + i]
          # index = size - posts.size + i
          instructions << { "op" => "aload", "var" => deconstructed_slot }
          instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                            "name" => "length", "descriptor" => "()J" }
          instructions << { "op" => "l2i" }
          instructions << { "op" => "iconst", "value" => pattern.posts.size - i }
          instructions << { "op" => "isub" }
          # Store index in temp, then get(index)
          post_idx_slot = @next_slot
          @next_slot += 1
          instructions << { "op" => "istore", "var" => post_idx_slot }
          instructions << { "op" => "aload", "var" => deconstructed_slot }
          instructions << { "op" => "iload", "var" => post_idx_slot }
          instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                            "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
          instructions << { "op" => "astore", "var" => post_slot }

          post_insts, post_vars = compile_jvm_pattern(post_pattern, post_slot)
          instructions.concat(post_insts)
          instructions << { "op" => "ifeq", "target" => match_fail }
          # Rewrite :predicate to post_slot
          post_vars.each { |k, v| bound_vars[k] = (v == :predicate ? post_slot : v) }
        end

        # All matched
        instructions << { "op" => "iconst", "value" => 1 }
        instructions << { "op" => "goto", "target" => match_done }

        # Match failure
        instructions << { "op" => "label", "name" => match_fail }
        instructions << { "op" => "iconst", "value" => 0 }

        instructions << { "op" => "label", "name" => match_done }

        [instructions, bound_vars]
      end

      # Hash pattern: call deconstruct_keys, check keys, match values
      # Example: `in {x:, y:}`, `in {name: String}`
      def compile_jvm_hash_pattern(pattern, pred_slot)
        instructions = []
        bound_vars = {}
        match_fail = new_label("hash_pat_fail")
        match_done = new_label("hash_pat_done")

        # Pre-allocate and null-initialize all value slots for JVM verifier
        val_slots = []
        pattern.elements.size.times do
          s = @next_slot
          @next_slot += 1
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => s }
          val_slots << s
        end

        # Step 1: Build keys array for deconstruct_keys
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "iconst", "value" => pattern.elements.size }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "(I)V" }
        pattern.elements.each do |elem|
          instructions << { "op" => "dup" }
          instructions << { "op" => "ldc", "value" => elem.key.to_s }
          instructions << { "op" => "invokeinterface", "owner" => "java/util/List",
                            "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "pop" }  # discard boolean
        end
        keys_slot = @next_slot
        @next_slot += 1
        instructions << { "op" => "astore", "var" => keys_slot }

        # Step 2: Call deconstruct_keys(keys) via invokedynamic
        deconstructed_slot = @next_slot
        @next_slot += 1
        instructions << { "op" => "aload", "var" => pred_slot }
        instructions << { "op" => "aload", "var" => keys_slot }
        # deconstruct_keys(keys): (Object receiver, Object keys) -> Object
        instructions << {
          "op" => "invokedynamic",
          "name" => "deconstruct_keys",
          "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
          "bootstrapName" => "bootstrap",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => []
        }
        instructions << { "op" => "astore", "var" => deconstructed_slot }

        # Step 3: For each element, get value by key and match
        pattern.elements.each_with_index do |elem, idx|
          val_slot = val_slots[idx]

          # Load the deconstructed hash and get the value for this key
          instructions << { "op" => "aload", "var" => deconstructed_slot }
          instructions << { "op" => "checkcast", "type" => "java/util/Map" }
          instructions << { "op" => "ldc", "value" => elem.key.to_s }
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map",
                            "name" => "get",
                            "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;" }
          # Store first, then check null (avoids stack issues with dup+ifnull)
          instructions << { "op" => "astore", "var" => val_slot }
          instructions << { "op" => "aload", "var" => val_slot }
          instructions << { "op" => "ifnull", "target" => match_fail }

          if elem.value_pattern
            # Match value against nested pattern
            val_insts, val_vars = compile_jvm_pattern(elem.value_pattern, val_slot)
            instructions.concat(val_insts)
            instructions << { "op" => "ifeq", "target" => match_fail }
            # Rewrite :predicate to val_slot
            val_vars.each { |k, v| bound_vars[k] = (v == :predicate ? val_slot : v) }
          else
            # Shorthand: {x:} → bind x to the value
            bound_vars[elem.key] = val_slot
          end
        end

        # All matched
        instructions << { "op" => "iconst", "value" => 1 }
        instructions << { "op" => "goto", "target" => match_done }

        # Match failure
        instructions << { "op" => "label", "name" => match_fail }
        instructions << { "op" => "iconst", "value" => 0 }

        instructions << { "op" => "label", "name" => match_done }

        [instructions, bound_vars]
      end

      # Bind pattern variables after a successful match
      def bind_pattern_vars(bound_vars, pred_slot)
        instructions = []
        bound_vars.each do |var_name, source|
          ensure_slot(var_name, :value)
          if source == :predicate
            # Bind the matched value (predicate) to the variable
            instructions << { "op" => "aload", "var" => pred_slot }
            instructions << { "op" => "astore", "var" => @variable_slots[var_name.to_s] }
            @variable_types[var_name.to_s] = :value
          elsif source.is_a?(Integer)
            # Bind from a specific slot (used by Hash/Array pattern element slots)
            instructions << { "op" => "aload", "var" => source }
            instructions << { "op" => "astore", "var" => @variable_slots[var_name.to_s] }
            @variable_types[var_name.to_s] = :value
          end
        end
        instructions
      end

      # ========================================================================
      # J8.6: Small Features
      # ========================================================================

      # Global variables: implemented as static fields on the main class
      def generate_load_global_var(inst)
        instructions = []
        field_name = inst.name.sub(/^\$/, "GLOBAL_")
        register_global_field(field_name)

        instructions << { "op" => "getstatic", "owner" => main_class_name,
                          "name" => field_name, "descriptor" => "Ljava/lang/Object;" }

        if inst.result_var
          ensure_slot(inst.result_var, :value)
          instructions << { "op" => "astore", "var" => @variable_slots[inst.result_var.to_s] }
          @variable_types[inst.result_var.to_s] = :value

          # Propagate class type from HM-inferred global variable type
          gv_type = inst.type
          gv_type = gv_type.prune if gv_type.respond_to?(:prune)
          if gv_type.is_a?(TypeChecker::Types::ClassInstance)
            cls_name = gv_type.name.to_s
            if @class_info.key?(cls_name)
              @variable_class_types[inst.result_var.to_s] = cls_name
            end
          end
        end
        instructions
      end

      def generate_store_global_var(inst)
        instructions = []
        field_name = inst.name.sub(/^\$/, "GLOBAL_")
        register_global_field(field_name)

        # Load value as boxed Object (load_value(:value) handles all boxing)
        instructions.concat(load_value(inst.value, :value))

        instructions << { "op" => "putstatic", "owner" => main_class_name,
                          "name" => field_name, "descriptor" => "Ljava/lang/Object;" }
        instructions
      end

      def register_global_field(field_name)
        @global_fields ||= Set.new
        @global_fields << field_name
      end

      # Class variable read (@@var) - stored as static field on main class
      def generate_load_class_var(inst)
        instructions = []
        field_name = inst.name.sub(/^@@/, "CLASSVAR_")
        register_global_field(field_name)

        instructions << { "op" => "getstatic", "owner" => main_class_name,
                          "name" => field_name, "descriptor" => "Ljava/lang/Object;" }

        if inst.result_var
          ensure_slot(inst.result_var, :value)
          instructions << { "op" => "astore", "var" => @variable_slots[inst.result_var.to_s] }
          @variable_types[inst.result_var.to_s] = :value
        end
        instructions
      end

      # Class variable write (@@var) - stored as static field on main class
      def generate_store_class_var(inst)
        instructions = []
        field_name = inst.name.sub(/^@@/, "CLASSVAR_")
        register_global_field(field_name)

        # Load value as boxed Object (load_value(:value) handles all boxing)
        instructions.concat(load_value(inst.value, :value))

        instructions << { "op" => "putstatic", "owner" => main_class_name,
                          "name" => field_name, "descriptor" => "Ljava/lang/Object;" }
        instructions
      end

      # Store constant to module/class static field
      def generate_store_constant(inst)
        instructions = []

        # Java:: class reference aliases (e.g., KUIRuntime = Java::Konpeito::Ui::KUIRuntime)
        # Store the alias name as a string in the static field so that getstatic in class
        # constructors gets a valid class reference (not null).
        if inst.value.is_a?(HIR::ConstantLookup) && inst.value.name.to_s.start_with?("Java::")
          alias_name = inst.name.to_s
          @variable_class_types[alias_name] = inst.value.name.to_s

          # Determine owner for the static field
          scope = inst.respond_to?(:scope) ? inst.scope&.to_s : nil
          owner = if scope && @module_info.key?(scope)
                    module_jvm_name(scope)
                  elsif scope && @class_info.key?(scope)
                    @class_info[scope][:jvm_name]
                  else
                    main_class_name
                  end
          if owner == main_class_name
            @constant_fields << alias_name
          end

          return [
            { "op" => "ldc", "value" => alias_name },
            { "op" => "putstatic", "owner" => owner,
              "name" => alias_name, "descriptor" => "Ljava/lang/Object;" }
          ]
        end

        # Determine the owner (module or class)
        scope = inst.respond_to?(:scope) ? inst.scope&.to_s : nil
        owner = if scope && @module_info.key?(scope)
                  module_jvm_name(scope)
                elsif scope && @class_info.key?(scope)
                  @class_info[scope][:jvm_name]
                else
                  main_class_name
                end

        # Register top-level constants as main class fields
        if owner == main_class_name
          @constant_fields << inst.name.to_s
        end

        # Load value as boxed Object (load_value(:value) handles all boxing)
        instructions.concat(load_value(inst.value, :value))

        instructions << { "op" => "putstatic", "owner" => owner,
                          "name" => inst.name.to_s, "descriptor" => "Ljava/lang/Object;" }
        instructions
      end

      # defined? operator: returns a string describing the type of the expression
      def generate_defined_check(inst)
        instructions = []
        result_var = inst.result_var

        case inst.check_type
        when :local_variable
          # In AOT compilation, local variables are always known at compile time
          instructions << { "op" => "ldc", "value" => "local-variable" }
        when :constant
          # For well-known constants, just return "constant"
          # In a more complete implementation, we'd use Class.forName to check
          instructions << { "op" => "ldc", "value" => "constant" }
        when :expression
          # For nil/true/false literals etc., return the name directly
          instructions << { "op" => "ldc", "value" => inst.name.to_s }
        when :method
          instructions << { "op" => "ldc", "value" => "method" }
        when :global_variable
          instructions << { "op" => "ldc", "value" => "global-variable" }
        when :instance_variable
          instructions << { "op" => "ldc", "value" => "instance-variable" }
        when :class_variable
          instructions << { "op" => "ldc", "value" => "class-variable" }
        else
          instructions << { "op" => "ldc", "value" => "expression" }
        end

        if result_var
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end

        instructions
      end

      # Multi-assignment extraction: a, b = [1, 2]
      def generate_multi_write_extract(inst)
        instructions = []

        # Load the array
        instructions.concat(load_value(inst.array, :value))
        # Cast to KArray
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KArray" }
        # Load index
        instructions << { "op" => "ldc", "value" => inst.index }
        # Call KArray.get(int)
        instructions << { "op" => "invokevirtual", "owner" => "konpeito/runtime/KArray",
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }

        if inst.result_var
          ensure_slot(inst.result_var, :value)
          instructions << { "op" => "astore", "var" => @variable_slots[inst.result_var.to_s] }
          @variable_types[inst.result_var.to_s] = :value
        end
        instructions
      end

      # Range literal: 1..5 or 1...5
      # Represented as a string "start..end" or "start...end" for simple usage
      def generate_range_lit(inst)
        instructions = []

        # Load left value as boxed Object, convert to String
        instructions.concat(load_boxed_value(inst.left))
        instructions << { "op" => "invokestatic", "owner" => "java/lang/String",
                          "name" => "valueOf", "descriptor" => "(Ljava/lang/Object;)Ljava/lang/String;" }

        # Add ".." or "..."
        separator = inst.exclusive ? "..." : ".."
        instructions << { "op" => "ldc", "value" => separator }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "concat", "descriptor" => "(Ljava/lang/String;)Ljava/lang/String;" }

        # Load right value as boxed Object, convert to String
        instructions.concat(load_boxed_value(inst.right))
        instructions << { "op" => "invokestatic", "owner" => "java/lang/String",
                          "name" => "valueOf", "descriptor" => "(Ljava/lang/Object;)Ljava/lang/String;" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "concat", "descriptor" => "(Ljava/lang/String;)Ljava/lang/String;" }

        if inst.result_var
          ensure_slot(inst.result_var, :value)
          instructions << { "op" => "astore", "var" => @variable_slots[inst.result_var.to_s] }
          @variable_types[inst.result_var.to_s] = :value
        end
        instructions
      end

      # Regexp literal: /pattern/flags
      # Store as pattern string for now (full java.util.regex.Pattern can be added later)
      def generate_regexp_lit(inst)
        instructions = []

        # Compile regexp literal to java.util.regex.Pattern for proper regex support
        instructions << { "op" => "ldc", "value" => inst.pattern }
        flags = inst.respond_to?(:options) ? ruby_regexp_flags_to_jvm(inst.options || 0) : 0
        if flags != 0
          instructions << { "op" => "iconst", "value" => flags }
          instructions << { "op" => "invokestatic", "owner" => "java/util/regex/Pattern",
                            "name" => "compile",
                            "descriptor" => "(Ljava/lang/String;I)Ljava/util/regex/Pattern;" }
        else
          instructions << { "op" => "invokestatic", "owner" => "java/util/regex/Pattern",
                            "name" => "compile",
                            "descriptor" => "(Ljava/lang/String;)Ljava/util/regex/Pattern;" }
        end

        if inst.result_var
          ensure_slot(inst.result_var, :value)
          instructions << { "op" => "astore", "var" => @variable_slots[inst.result_var.to_s] }
          @variable_types[inst.result_var.to_s] = :value
        end
        instructions
      end

      # Load an HIR value as a boxed Object on the stack.
      # load_value(:value) handles all boxing via box_primitive_if_needed.
      def load_boxed_value(hir_value)
        load_value(hir_value, :value)
      end

      def ruby_regexp_flags_to_jvm(options)
        flags = 0
        # Ruby Regexp::IGNORECASE = 1, EXTENDED = 2, MULTILINE = 4
        flags |= 2 if options & 1 != 0   # CASE_INSENSITIVE
        flags |= 4 if options & 2 != 0   # COMMENTS (EXTENDED)
        flags |= 32 if options & 4 != 0  # DOTALL (Ruby MULTILINE)
        flags
      end

      RUBY_EXCEPTION_TO_JVM = {
        "RuntimeError" => "java/lang/RuntimeException",
        "StandardError" => "java/lang/Exception",
        "ArgumentError" => "java/lang/IllegalArgumentException",
        "TypeError" => "java/lang/ClassCastException",
        "ZeroDivisionError" => "java/lang/ArithmeticException",
        "RangeError" => "java/lang/IndexOutOfBoundsException",
        "NameError" => "java/lang/RuntimeException",
        "NoMethodError" => "java/lang/RuntimeException",
        "IOError" => "java/io/IOException",
        "Errno::ENOENT" => "java/io/FileNotFoundException",
      }.freeze

      def ruby_exception_to_jvm(ruby_class_name)
        RUBY_EXCEPTION_TO_JVM[ruby_class_name.to_s] || "java/lang/Exception"
      end

      def generate_puts_call(args, result_var)
        instructions = []

        # Get System.out
        instructions << { "op" => "getstatic",
                          "owner" => "java/lang/System", "name" => "out",
                          "descriptor" => "Ljava/io/PrintStream;" }

        if args.empty?
          # puts with no args → println()
          instructions << { "op" => "invokevirtual",
                            "owner" => "java/io/PrintStream", "name" => "println",
                            "descriptor" => "()V" }
        else
          arg = args.first
          arg_var = extract_var_name(arg)
          arg_type = arg_var ? (@variable_types[arg_var] || :value) : :value

          instructions.concat(load_value(arg, arg_type))

          # Choose appropriate println overload
          desc = case arg_type
                 when :i64 then "(J)V"
                 when :double then "(D)V"
                 when :i8 then "(Z)V"
                 when :string then "(Ljava/lang/String;)V"
                 else "(Ljava/lang/Object;)V"
                 end

          instructions << { "op" => "invokevirtual",
                            "owner" => "java/io/PrintStream", "name" => "println",
                            "descriptor" => desc }
        end

        # puts returns nil
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end

        instructions
      end

      def generate_print_call(args, result_var)
        instructions = []

        # Get System.out
        instructions << { "op" => "getstatic",
                          "owner" => "java/lang/System", "name" => "out",
                          "descriptor" => "Ljava/io/PrintStream;" }

        if args.empty?
          # print with no args → nothing
        else
          arg = args.first
          arg_var = extract_var_name(arg)
          arg_type = arg_var ? (@variable_types[arg_var] || :value) : :value

          instructions.concat(load_value(arg, arg_type))

          desc = case arg_type
                 when :i64 then "(J)V"
                 when :double then "(D)V"
                 when :i8 then "(Z)V"
                 else "(Ljava/lang/Object;)V"
                 end

          instructions << { "op" => "invokevirtual",
                            "owner" => "java/io/PrintStream", "name" => "print",
                            "descriptor" => desc }
        end

        # print returns nil
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end

        instructions
      end

      def generate_conversion_call(method_name, receiver, result_var)
        instructions = []
        recv_var = extract_var_name(receiver)
        recv_type = recv_var ? (@variable_types[recv_var] || :value) : :value

        case method_name
        when "to_s"
          ensure_slot(result_var, :value) if result_var
          case recv_type
          when :i64
            instructions.concat(load_value(receiver, :i64))
            instructions << { "op" => "invokestatic",
                              "owner" => "java/lang/Long", "name" => "toString",
                              "descriptor" => "(J)Ljava/lang/String;" }
          when :double
            instructions.concat(load_value(receiver, :double))
            instructions << { "op" => "invokestatic",
                              "owner" => "java/lang/Double", "name" => "toString",
                              "descriptor" => "(D)Ljava/lang/String;" }
          when :i8
            instructions.concat(load_value(receiver, :i8))
            instructions << { "op" => "invokestatic",
                              "owner" => "java/lang/Boolean", "name" => "toString",
                              "descriptor" => "(Z)Ljava/lang/String;" }
          else
            # Object.toString() — null-safe: return "" for nil (Ruby semantics)
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "ldc", "value" => "" }
            instructions << { "op" => "invokestatic",
                              "owner" => "java/util/Objects", "name" => "toString",
                              "descriptor" => "(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/String;" }
          end
          if result_var
            instructions << store_instruction(result_var, :value)
            @variable_types[result_var] = :value
          end

        when "to_i"
          ensure_slot(result_var, :i64) if result_var
          case recv_type
          when :i64
            instructions.concat(load_value(receiver, :i64))
          when :double
            instructions.concat(load_value(receiver, :double))
            instructions << { "op" => "d2l" }
          else
            # Fallback: use invokedynamic for null-safe, Ruby-compatible to_i
            # (handles non-numeric strings by returning 0, partial numeric parsing, etc.)
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "invokedynamic",
                              "name" => "to_i",
                              "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;",
                              "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
                              "bootstrapName" => "bootstrap",
                              "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;" }
            # Unbox the result (Object → Long → long)
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "longValue", "descriptor" => "()J" }
          end
          if result_var
            instructions << store_instruction(result_var, :i64)
            @variable_types[result_var] = :i64
          end

        when "to_f"
          ensure_slot(result_var, :double) if result_var
          case recv_type
          when :double
            instructions.concat(load_value(receiver, :double))
          when :i64
            instructions.concat(load_value(receiver, :i64))
            instructions << { "op" => "l2d" }
          else
            # Fallback: use invokedynamic for null-safe, Ruby-compatible to_f
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "invokedynamic",
                              "name" => "to_f",
                              "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;",
                              "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
                              "bootstrapName" => "bootstrap",
                              "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;" }
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "doubleValue", "descriptor" => "()D" }
          end
          if result_var
            instructions << store_instruction(result_var, :double)
            @variable_types[result_var] = :double
          end
        end

        instructions
      end

      def generate_static_call(inst, method_name, args, result_var)
        instructions = []

        # Check for monomorphized target (e.g., identity → identity_Integer)
        actual_target = inst.instance_variable_get(:@specialized_target) || method_name
        # Prefer top-level functions (owner_class nil) over class instance methods
        # to avoid name collisions (e.g., MouseEvent#button vs DSL button(label))
        target_func = @hir_program.functions.find { |f| f.name == actual_target && f.owner_class.nil? } ||
                      @hir_program.functions.find { |f| f.name == method_name && f.owner_class.nil? } ||
                      @hir_program.functions.find { |f| f.name == actual_target } ||
                      @hir_program.functions.find { |f| f.name == method_name }
        return [] unless target_func

        # Check if call has splat args — needs special expansion
        has_splat = args.any? { |a| a.is_a?(HIR::SplatArg) }

        if has_splat
          # Splat expansion: extract elements from the array for each target param
          # For now handles the common case: regular args before splat, then *array expands to fill remaining params
          splat_index = args.index { |a| a.is_a?(HIR::SplatArg) }

          # Load regular args before the splat
          splat_index.times do |i|
            if i < target_func.params.size
              param = target_func.params[i]
              param_t = widened_param_type(target_func, param, i)
              instructions.concat(load_value(args[i], param_t))
              loaded_t = infer_loaded_type(args[i])
              instructions.concat(unbox_if_needed(loaded_t, param_t))
            end
          end

          # Load the splat array into a temp
          splat_arg = args[splat_index]
          splat_temp = "__splat_arr_#{@label_counter}"
          @label_counter += 1
          instructions.concat(load_value(splat_arg.expression, :value))
          instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KArray" }
          ensure_slot(splat_temp, :value)
          instructions << store_instruction(splat_temp, :value)
          @variable_types[splat_temp] = :value

          # Extract elements for remaining params
          remaining_params = target_func.params[splat_index..]
          remaining_params.each_with_index do |param, j|
            next if param.rest || param.keyword_rest
            param_t = widened_param_type(target_func, param, splat_index + j)
            # Load array, push index, call get(int)
            instructions << load_instruction(splat_temp, :value)
            instructions << { "op" => "iconst", "value" => j }
            instructions << { "op" => "invokevirtual", "owner" => "konpeito/runtime/KArray",
                              "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
            # Unbox if needed (array elements are boxed Objects)
            instructions.concat(unbox_if_needed(:value, param_t))
          end
        else
          # Normal argument loading (no splat)
          # Load arguments
          target_func.params.each_with_index do |param, i|
            if param.rest
              # Rest parameter (*args): collect remaining arguments into a KArray
              rest_args = args[i..]
              instructions << { "op" => "new", "type" => "konpeito/runtime/KArray" }
              instructions << { "op" => "dup" }
              instructions << { "op" => "invokespecial", "owner" => "konpeito/runtime/KArray",
                                "name" => "<init>", "descriptor" => "()V" }
              rest_args.each do |arg|
                instructions.concat(load_value(arg, :value))
                instructions << { "op" => "invokevirtual", "owner" => "konpeito/runtime/KArray",
                                  "name" => "push", "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
              end
              break  # rest param consumes all remaining args
            elsif param.keyword_rest
              # Keyword rest parameter (**kwargs): build a KHash from keyword_args
              if inst.respond_to?(:keyword_args) && inst.has_keyword_args?
                instructions.concat(build_kwargs_hash(inst.keyword_args))
              else
                # No keyword args provided — pass empty KHash
                instructions << { "op" => "new", "type" => KHASH_CLASS }
                instructions << { "op" => "dup" }
                instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                                  "name" => "<init>", "descriptor" => "()V" }
              end
            elsif i < args.size
              param_t = widened_param_type(target_func, param, i)
              instructions.concat(load_value(args[i], param_t))
              # Unbox if loaded type is :value but function expects primitive
              loaded_t = infer_loaded_type(args[i])
              instructions.concat(unbox_if_needed(loaded_t, param_t))
            else
              # Optional parameter not provided at call site — push default value
              param_t = widened_param_type(target_func, param, i)
              if param.default_value
                instructions.concat(prism_default_to_jvm(param.default_value, param_t))
              else
                instructions.concat(default_value_instructions(param_t))
              end
            end
          end
        end

        # If target is a yield-containing function, determine descriptor and pass null block
        target_has_yield = @yield_functions.include?(actual_target) || @yield_functions.include?(method_name)
        if target_has_yield
          kblock_iface = yield_function_kblock_interface(target_func)
          desc = method_descriptor_with_block(target_func, kblock_iface)
          # Pass null as block argument (no block provided)
          instructions << { "op" => "aconst_null" }
        else
          desc = method_descriptor(target_func)
        end

        # Call the function (use actual_target for monomorphized name)
        instructions << { "op" => "invokestatic",
                          "owner" => main_class_name,
                          "name" => jvm_method_name(actual_target),
                          "descriptor" => desc }

        # Store result
        if result_var
          ret_type = function_return_type(target_func)
          if ret_type != :void
            ensure_slot(result_var, ret_type)
            instructions << store_instruction(result_var, ret_type)
            @variable_types[result_var] = ret_type

            # Propagate class type so subsequent method chains resolve the receiver.
            # Without this, `Button("Animate!").kind(1)` fails because the receiver
            # class of `.kind(1)` is unknown after the static call to `Button()`.
            if ret_type.is_a?(Symbol) && ret_type.to_s.start_with?("class:")
              cls = ret_type.to_s.sub("class:", "")
              @variable_class_types[result_var] = cls if @class_info.key?(cls)
            end
            # Also check HM-inferred type from the call instruction
            if !@variable_class_types[result_var] && inst.respond_to?(:type) && inst.type
              call_type = inst.type
              call_type = call_type.prune if call_type.respond_to?(:prune)
              if call_type.is_a?(TypeChecker::Types::ClassInstance) && @class_info.key?(call_type.name.to_s)
                @variable_class_types[result_var] = call_type.name.to_s
              end
            end
          end
        end

        instructions
      end

      # ========================================================================
      # Phi Node
      # ========================================================================

      def generate_phi(inst)
        # Phi nodes are handled by generate_phi_stores in Jump/Branch terminators.
        # The slot is pre-allocated in generate_function. Nothing to emit here.
        []
      end

      # ========================================================================
      # String Concat
      # ========================================================================

      def generate_string_concat(inst)
        result_var = inst.result_var
        ensure_slot(result_var, :value)

        instructions = []

        # Create StringBuilder
        instructions << { "op" => "new", "type" => "java/lang/StringBuilder" }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => "java/lang/StringBuilder",
                          "name" => "<init>", "descriptor" => "()V" }

        # Append each part
        inst.parts.each do |part|
          part_var = extract_var_name(part)
          part_type = part_var ? (@variable_types[part_var] || :value) : :value

          instructions.concat(load_value(part, part_type))

          append_desc = case part_type
                        when :i64 then "(J)Ljava/lang/StringBuilder;"
                        when :double then "(D)Ljava/lang/StringBuilder;"
                        when :i8 then "(Z)Ljava/lang/StringBuilder;"
                        else "(Ljava/lang/Object;)Ljava/lang/StringBuilder;"
                        end

          instructions << { "op" => "invokevirtual",
                            "owner" => "java/lang/StringBuilder", "name" => "append",
                            "descriptor" => append_desc }
        end

        # toString
        instructions << { "op" => "invokevirtual",
                          "owner" => "java/lang/StringBuilder", "name" => "toString",
                          "descriptor" => "()Ljava/lang/String;" }

        instructions << store_instruction(result_var, :value)
        @variable_types[result_var] = :value

        instructions
      end

      # ========================================================================
      # Terminators
      # ========================================================================

      def generate_return(term)
        if term.value
          # If value is NilLit, return null for Object-returning methods, void for void methods
          if term.value.is_a?(HIR::NilLit)
            if @current_function_return_type && @current_function_return_type != :void
              return [{ "op" => "aconst_null" }, { "op" => "areturn" }]
            else
              return [{ "op" => "return" }]
            end
          end

          var = extract_var_name(term.value)
          type = var ? (@variable_types[var] || :value) : :value

          # If the variable was never allocated (e.g., void-returning JVM interop call),
          # return null for Object-returning methods or void return
          if var && !@variable_slots.key?(var)
            if @current_function_return_type && @current_function_return_type != :void
              return [{ "op" => "aconst_null" }, { "op" => "areturn" }]
            else
              return [{ "op" => "return" }]
            end
          end

          # If the value type is nil/void, return null if method expects Object, else void return
          if type == :void
            if @current_function_return_type && @current_function_return_type != :void
              return [{ "op" => "aconst_null" }, { "op" => "areturn" }]
            else
              return [{ "op" => "return" }]
            end
          end

          instructions = load_value(term.value, type).dup

          # Box primitives if method/block returns Object
          if @current_function_return_type == :value && type == :i64
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                              "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            type = :value
          elsif @current_function_return_type == :value && type == :double
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            type = :value
          elsif @current_function_return_type == :value && type == :i8
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                              "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
            type = :value
          # Unbox Object to match expected primitive return type (static methods only).
          # Instance method descriptors are always normalized to Object return, so
          # unboxing would be incorrect — the value might not be the expected wrapper type.
          elsif !@generating_instance_method && @current_function_return_type == :double && type == :value
            instructions << { "op" => "checkcast", "type" => "java/lang/Double" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Double",
                              "name" => "doubleValue", "descriptor" => "()D" }
            type = :double
          elsif !@generating_instance_method && @current_function_return_type == :i64 && type == :value
            instructions << { "op" => "checkcast", "type" => "java/lang/Long" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Long",
                              "name" => "longValue", "descriptor" => "()J" }
            type = :i64
          elsif !@generating_instance_method && @current_function_return_type == :i8 && type == :value
            instructions << { "op" => "checkcast", "type" => "java/lang/Boolean" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Boolean",
                              "name" => "booleanValue", "descriptor" => "()Z" }
            type = :i8
          end

          instructions << case type
                          when :i64 then { "op" => "lreturn" }
                          when :double then { "op" => "dreturn" }
                          when :i8 then { "op" => "ireturn" }
                          when :value then { "op" => "areturn" }
                          else { "op" => "areturn" }
                          end
          instructions
        else
          # No return value — void return for void methods, null for Object-returning methods
          if @current_function_return_type && @current_function_return_type != :void
            [{ "op" => "aconst_null" }, { "op" => "areturn" }]
          else
            [{ "op" => "return" }]
          end
        end
      end

      def generate_branch(term)
        instructions = []

        cond_var = extract_var_name(term.condition)
        cond_type = cond_var ? (@variable_types[cond_var] || :value) : :value

        then_label = term.then_block.to_s
        else_label = term.else_block.to_s

        # Generate phi stores for the else path BEFORE loading condition,
        # so they execute before the conditional jump takes us to else_label.
        else_phi_stores = generate_phi_stores(else_label)
        instructions.concat(else_phi_stores)

        # Load condition
        instructions.concat(load_value(term.condition, cond_type))

        # Branch based on type
        case cond_type
        when :i8
          # boolean: ifeq jumps to else (false = 0)
          instructions << { "op" => "ifeq", "target" => else_label }
        when :i64
          # Ruby: all integers (including 0) are truthy.
          # Pop the loaded long value and always fall through to then.
          instructions << { "op" => "pop2" }
        when :value
          # Ruby truthiness: null (nil) and Boolean.FALSE (false) are falsy.
          # Use RubyDispatch.isTruthy() to avoid complex dup/pop/label patterns
          # that confuse ASM's COMPUTE_FRAMES in methods with many merge points.
          instructions << { "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
                            "name" => "isTruthy", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "ifeq", "target" => else_label }
        else
          instructions << { "op" => "ifnull", "target" => else_label }
        end

        # Generate phi stores for the then path (fall-through side)
        then_phi_stores = generate_phi_stores(then_label)
        instructions.concat(then_phi_stores)

        # Fall through to then block (no explicit jump needed if then block follows)
        # But we need to handle non-sequential blocks
        instructions << { "op" => "goto", "target" => then_label }

        instructions
      end

      # Safe navigation: x&.method → if x == nil then nil else x.method end
      def generate_safe_navigation_call(inst)
        instructions = []
        receiver = inst.receiver
        result_var = inst.result_var

        # Force result_var to :value type (safe nav can return nil)
        # This ensures both branches (null and non-null) use the same JVM type
        if result_var
          @variable_types[result_var] = :value
          @_nil_assigned_vars ||= Set.new
          @_nil_assigned_vars << result_var
          slot_for(result_var) # ensure slot is allocated as Object
        end

        # Load receiver onto stack for null check
        instructions.concat(load_value(receiver, :value))

        # If null, jump to nil_label
        nil_label = new_label("safe_nav_nil")
        end_label = new_label("safe_nav_end")
        instructions << { "op" => "ifnull", "target" => nil_label }

        # Non-null path: do the actual call (with safe_navigation disabled to avoid recursion)
        original_safe_nav = inst.instance_variable_get(:@safe_navigation)
        inst.instance_variable_set(:@safe_navigation, false)
        instructions.concat(generate_call(inst))
        inst.instance_variable_set(:@safe_navigation, original_safe_nav)

        # If the call stored the result as a primitive type, we need to convert it to Object
        # since safe navigation result must be Object (can be null)
        if result_var
          actual_type = @variable_types[result_var]
          if actual_type && actual_type != :value
            # Re-read as current type, box, and store as :value
            slot = slot_for(result_var)
            case actual_type
            when :i64
              instructions << { "op" => "lload", "var" => slot }
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                               "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
              instructions << { "op" => "astore", "var" => slot }
            when :double
              instructions << { "op" => "dload", "var" => slot }
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                               "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
              instructions << { "op" => "astore", "var" => slot }
            when :i8
              instructions << { "op" => "iload", "var" => slot }
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                               "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
              instructions << { "op" => "astore", "var" => slot }
            end
            @variable_types[result_var] = :value
          end
        end

        instructions << { "op" => "goto", "target" => end_label }

        # Null path: store null as result
        instructions << { "op" => "label", "name" => nil_label }
        if result_var
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
        end

        instructions << { "op" => "label", "name" => end_label }
        instructions
      end

      # Boolean negation: !expr → invert truthiness
      def generate_not_operator(receiver, result_var)
        instructions = []
        recv_var = extract_var_name(receiver)
        recv_type = recv_var ? (@variable_types[recv_var] || :value) : :value

        true_label = "not_true_#{@label_counter}"
        end_label = "not_end_#{@label_counter}"
        @label_counter += 1

        instructions.concat(load_value(receiver, recv_type))

        case recv_type
        when :i8
          # boolean: 0 → 1, non-0 → 0
          instructions << { "op" => "ifeq", "target" => true_label }
          # value was truthy → result is false (0)
          instructions << { "op" => "iconst", "value" => 0 }
          instructions << { "op" => "goto", "target" => end_label }
          instructions << { "op" => "label", "name" => true_label }
          # value was falsy → result is true (1)
          instructions << { "op" => "iconst", "value" => 1 }
          instructions << { "op" => "label", "name" => end_label }
        when :i64
          # long: 0 → 1, non-0 → 0
          instructions << { "op" => "lconst_0" }
          instructions << { "op" => "lcmp" }
          instructions << { "op" => "ifeq", "target" => true_label }
          instructions << { "op" => "iconst", "value" => 0 }
          instructions << { "op" => "goto", "target" => end_label }
          instructions << { "op" => "label", "name" => true_label }
          instructions << { "op" => "iconst", "value" => 1 }
          instructions << { "op" => "label", "name" => end_label }
        else
          # Object: Ruby truthiness — nil (null) and false (Boolean.FALSE) are falsy
          # !nil → true, !false → true, !anything_else → false
          # Use RubyDispatch.isTruthy() to simplify frame computation.
          instructions << { "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
                            "name" => "isTruthy", "descriptor" => "(Ljava/lang/Object;)Z" }
          # isTruthy returns 1 for truthy, 0 for falsy. NOT inverts.
          instructions << { "op" => "ifeq", "target" => true_label }
          # truthy → !truthy = false (0)
          instructions << { "op" => "iconst", "value" => 0 }
          instructions << { "op" => "goto", "target" => end_label }
          # falsy → !falsy = true (1)
          instructions << { "op" => "label", "name" => true_label }
          instructions << { "op" => "iconst", "value" => 1 }
          instructions << { "op" => "label", "name" => end_label }
        end

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end

        instructions
      end

      def generate_jump(term)
        instructions = []
        target = term.target.to_s

        # Insert Phi stores: before jumping, store values for any Phi nodes in the target block
        instructions.concat(generate_phi_stores(target))

        instructions << { "op" => "goto", "target" => target }
        instructions
      end

      def generate_raise_exception(term)
        instructions = []
        instructions << { "op" => "new", "type" => "java/lang/RuntimeException" }
        instructions << { "op" => "dup" }

        if term.exception
          instructions.concat(load_value(term.exception, :value))
          instructions << { "op" => "invokevirtual", "owner" => "java/lang/Object",
                            "name" => "toString", "descriptor" => "()Ljava/lang/String;" }
          instructions << { "op" => "invokespecial",
                            "owner" => "java/lang/RuntimeException", "name" => "<init>",
                            "descriptor" => "(Ljava/lang/String;)V" }
        else
          instructions << { "op" => "invokespecial",
                            "owner" => "java/lang/RuntimeException", "name" => "<init>",
                            "descriptor" => "()V" }
        end

        instructions << { "op" => "athrow" }
        instructions
      end

      # ========================================================================
      # Module Generation
      # ========================================================================

      def module_jvm_name(module_name)
        "#{JAVA_PACKAGE}/#{sanitize_name(module_name)}"
      end

      def register_module_info(module_def)
        mod_name = module_def.name.to_s
        @module_info[mod_name] = {
          jvm_name: module_jvm_name(mod_name),
          methods: (module_def.methods || []).map(&:to_s),
          singleton_methods: (module_def.singleton_methods || []).map(&:to_s),
          constants: module_def.constants || {}
        }
      end

      def find_module_instance_method(module_name, method_name)
        mod_def = @hir_program.modules.find { |m| m.name.to_s == module_name.to_s }
        return nil unless mod_def
        return nil unless (mod_def.methods || []).any? { |m| m.to_s == method_name.to_s }

        @hir_program.functions.find { |f|
          f.owner_module.to_s == module_name.to_s &&
          f.name.to_s == method_name.to_s &&
          !(mod_def.singleton_methods || []).any? { |sm| sm.to_s == method_name.to_s }
        }
      end

      def find_module_singleton_method(module_name, method_name)
        mod_def = @hir_program.modules.find { |m| m.name.to_s == module_name.to_s }
        return nil unless mod_def
        return nil unless (mod_def.singleton_methods || []).any? { |m| m.to_s == method_name.to_s }

        @hir_program.functions.find { |f|
          f.owner_module.to_s == module_name.to_s &&
          f.name.to_s == method_name.to_s
        }
      end

      def generate_module_interface(module_def)
        mod_name = module_def.name.to_s
        jvm_name = module_jvm_name(mod_name)

        jvm_fields = []
        jvm_methods = []

        # Generate constants as static final fields
        (module_def.constants || {}).each do |const_name, _value_inst|
          jvm_fields << {
            "name" => const_name.to_s,
            "descriptor" => "Ljava/lang/Object;",
            "access" => ["public", "static", "final"]
          }
        end

        # Generate instance methods as default methods (Java 8+)
        (module_def.methods || []).each do |method_name|
          func = find_module_instance_method(mod_name, method_name.to_s)
          next unless func
          jvm_methods << generate_module_default_method(func, module_def)
        end

        # Generate singleton methods as static methods
        (module_def.singleton_methods || []).each do |method_name|
          func = find_module_singleton_method(mod_name, method_name.to_s)
          next unless func
          jvm_methods << generate_module_static_method(func, module_def)
        end

        # Generate <clinit> for constant initialization if needed
        clinit = generate_module_clinit(module_def)
        jvm_methods << clinit if clinit

        {
          "name" => jvm_name,
          "access" => ["public", "interface", "abstract"],
          "superName" => "java/lang/Object",
          "interfaces" => [],
          "fields" => jvm_fields,
          "methods" => jvm_methods
        }
      end

      def generate_module_default_method(func, module_def)
        @current_generating_func_name = func.name.to_s
        reset_function_state(func)

        @current_class_name = module_def.name.to_s
        @current_class_fields = {}  # Modules don't have instance fields
        @generating_instance_method = true
        @current_method_name = func.name.to_s

        # Slot 0 is 'this' (the implementing class instance)
        allocate_slot("__self__", :value)

        # Allocate parameter slots
        func.params.each do |param|
          type = param_type(param)
          allocate_slot(param.name, type)
          if param.rest || param.keyword_rest
            @variable_collection_types[param.name.to_s] = param.rest ? :array : :hash
          end
        end

        prescan_phi_nodes(func)
        instructions = generate_function_body(func)

        ret_type = detect_return_type_from_instructions(instructions)

        # Sanitize returns for void methods
        if ret_type == :void
          instructions = sanitize_void_returns(instructions)
        end

        if ret_type == :string
          instructions = insert_return_checkcast(instructions, "java/lang/String")
        end

        if ret_type == :i64 || ret_type == :double || ret_type == :i8
          instructions = convert_object_return_to_primitive(instructions, ret_type)
        end

        if ret_type == :value
          instructions = convert_primitive_return_to_object(instructions)
        end

        unless instructions.last && return_instruction?(instructions.last)
          instructions << default_return(ret_type)
        end

        params_desc = func.params.map { |p| type_to_descriptor(param_type(p)) }.join
        descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"

        # Register for call-site lookup (instance method pattern: ClassName#method)
        @method_descriptors["#{module_def.name}##{func.name}"] = descriptor

        @generating_instance_method = false
        @current_class_name = nil
        @current_class_fields = nil
        @current_method_name = nil

        {
          "name" => jvm_method_name(func.name),
          "descriptor" => descriptor,
          "access" => ["public"],  # default method (not abstract — has body)
          "instructions" => instructions
        }
      end

      def generate_module_static_method(func, module_def)
        @current_generating_func_name = func.name.to_s
        reset_function_state(func)

        func.params.each do |param|
          type = param_type(param)
          allocate_slot(param.name, type)
        end

        prescan_phi_nodes(func)
        instructions = generate_function_body(func)

        ret_type = detect_return_type_from_instructions(instructions)

        unless instructions.last && return_instruction?(instructions.last)
          instructions << default_return(ret_type)
        end

        params_desc = func.params.map { |p| type_to_descriptor(@variable_types[p.name.to_s] || :value) }.join
        descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"

        # Register for call-site lookup (singleton method pattern: ClassName.method)
        @method_descriptors["#{module_def.name}.#{func.name}"] = descriptor

        {
          "name" => jvm_method_name(func.name),
          "descriptor" => descriptor,
          "access" => ["public", "static"],
          "instructions" => instructions
        }
      end

      def generate_module_clinit(module_def)
        constants = module_def.constants || {}
        return nil if constants.empty?

        jvm_name = module_jvm_name(module_def.name.to_s)
        instructions = []

        constants.each do |const_name, value_insts|
          # value_insts may be an Array of HIR instructions or a single HIR node
          insts = value_insts.is_a?(Array) ? value_insts : [value_insts]
          insts.each do |inst|
            instructions.concat(clinit_push_value(inst))
          end
          # The last instruction should have produced a value — store it to the static field
          instructions << { "op" => "putstatic", "owner" => jvm_name,
                            "name" => const_name.to_s,
                            "descriptor" => "Ljava/lang/Object;" }
        end

        instructions << { "op" => "return" }

        return nil if instructions.size <= 1  # Only "return" — no actual constants to init

        {
          "name" => "<clinit>",
          "descriptor" => "()V",
          "access" => ["public", "static"],
          "instructions" => instructions
        }
      end

      # Generate <clinit> for class body constants and class variables
      def generate_class_clinit(class_def, jvm_class_name)
        body_constants = class_def.body_constants || []
        body_class_vars = class_def.body_class_vars || []
        return nil if body_constants.empty? && body_class_vars.empty?

        instructions = []

        body_constants.each do |const_name, value_node|
          instructions.concat(clinit_push_value(value_node))
          instructions << { "op" => "putstatic", "owner" => jvm_class_name,
                            "name" => const_name.to_s,
                            "descriptor" => "Ljava/lang/Object;" }
        end

        body_class_vars.each do |cvar_name, value_node|
          # Store to main class with CLASSVAR_ prefix (matching LoadClassVar/StoreClassVar)
          field_name = cvar_name.to_s.sub(/^@@/, "CLASSVAR_")
          register_global_field(field_name)
          instructions.concat(clinit_push_value(value_node))
          instructions << { "op" => "putstatic", "owner" => main_class_name,
                            "name" => field_name,
                            "descriptor" => "Ljava/lang/Object;" }
        end

        instructions << { "op" => "return" }

        {
          "name" => "<clinit>",
          "descriptor" => "()V",
          "access" => ["public", "static"],
          "instructions" => instructions
        }
      end

      # Push a literal value onto the JVM operand stack (for use in <clinit>).
      # Does not store to local variable slots.
      def clinit_push_value(node)
        case node
        when HIR::IntegerLit
          insts = []
          val = node.value
          if val == 0
            insts << { "op" => "lconst_0" }
          elsif val == 1
            insts << { "op" => "lconst_1" }
          else
            insts << { "op" => "ldc2_w", "value" => val, "type" => "long" }
          end
          # Box to Long
          insts << { "op" => "invokestatic", "owner" => "java/lang/Long",
                     "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          insts
        when HIR::FloatLit
          insts = []
          val = node.value
          if val == 0.0
            insts << { "op" => "dconst_0" }
          elsif val == 1.0
            insts << { "op" => "dconst_1" }
          else
            insts << { "op" => "ldc2_w", "value" => val, "type" => "double" }
          end
          # Box to Double
          insts << { "op" => "invokestatic", "owner" => "java/lang/Double",
                     "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          insts
        when HIR::StringLit
          [{ "op" => "ldc", "value" => node.value.to_s }]
        when HIR::SymbolLit
          [{ "op" => "ldc", "value" => ":#{node.value}" }]
        when HIR::BoolLit
          val = node.value ? 1 : 0
          insts = [{ "op" => "iconst", "value" => val }]
          insts << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                     "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
          insts
        when HIR::NilLit
          [{ "op" => "aconst_null" }]
        else
          [{ "op" => "aconst_null" }]
        end
      end

      # Generate a static method on a class from an extended module's instance method
      def generate_extended_static_method(func, module_name, class_def)
        @current_generating_func_name = func.name.to_s
        reset_function_state(func)

        # Static method — no 'self' slot
        func.params.each do |param|
          type = param_type(param)
          allocate_slot(param.name, type)
        end

        prescan_phi_nodes(func)
        instructions = generate_function_body(func)

        ret_type = detect_return_type_from_instructions(instructions)

        unless instructions.last && return_instruction?(instructions.last)
          instructions << default_return(ret_type)
        end

        params_desc = func.params.map { |p| type_to_descriptor(@variable_types[p.name.to_s] || :value) }.join
        descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"

        # Register as class-level static method
        @method_descriptors["#{class_def.name}.#{func.name}"] = descriptor

        {
          "name" => jvm_method_name(func.name),
          "descriptor" => descriptor,
          "access" => ["public", "static"],
          "instructions" => instructions
        }
      end

      # ========================================================================
      # User Class Generation
      # ========================================================================

      def register_class_info(class_def)
        class_name = class_def.name.to_s
        jvm_class_name = user_class_jvm_name(class_name)
        super_name = if class_def.superclass && @hir_program.classes.any? { |cd| cd.name.to_s == class_def.superclass.to_s }
                       user_class_jvm_name(class_def.superclass.to_s)
                     else
                       "java/lang/Object"
                     end

        fields_info = resolve_class_fields(class_def)

        @class_info[class_name] = { fields: fields_info, jvm_name: jvm_class_name, super_name: super_name }
      end

      # Remove fields from child classes that are already declared on a parent class.
      # Must run AFTER all classes are registered (register_class_info) since the
      # HIR class order may register children before parents.
      #
      # Type conflict detection: when a child class assigns a concrete but different type
      # to a field that the parent typed narrowly (e.g. parent :i64, child :string), widen
      # the parent's field to :value (Object) to prevent runtime NPE.
      # If the child type is :value (unresolved/unknown), keep the parent's concrete type.
      def dedup_inherited_fields
        @class_info.each do |class_name, info|
          parent = info[:super_name]
          while parent
            parent_name = parent.split("/").last
            parent_info = @class_info[parent_name]
            break unless parent_info
            if parent_info[:fields]
              parent_info[:fields].each_key do |fname|
                if info[:fields].key?(fname)
                  child_type = info[:fields][fname]
                  parent_type = parent_info[:fields][fname]
                  # Only widen when both types are concrete but different.
                  # If child is :value (unknown), trust the parent's type.
                  # If parent is :value, trust it (already wide enough).
                  if child_type != parent_type && child_type != :value && parent_type != :value
                    warn "[konpeito] JVM field type conflict: #{parent_name}##{fname} is :#{parent_type}, " \
                         "but subclass #{class_name} uses :#{child_type}. Widening to :value (Object)."
                    parent_info[:fields][fname] = :value
                  end
                  info[:fields].delete(fname)
                end
              end
            end
            parent = parent_info[:super_name]
          end
        end
      end

      # Register native classes from RBS that have no Ruby source class definition
      # (e.g., @struct types, NativeClass types used only via RBS annotations)
      def register_rbs_only_native_classes
        return unless @rbs_loader

        # Built-in native types handled by dedicated generators — skip them
        skip_prefixes = %w[NativeArray NativeHash StaticArray ByteBuffer StringBuffer Slice NativeString]

        @rbs_loader.native_classes.each do |class_name_sym, native_type|
          class_name = class_name_sym.to_s
          next if @class_info.key?(class_name)  # Already registered from HIR ClassDef
          next if skip_prefixes.any? { |prefix| class_name.start_with?(prefix) }

          jvm_class_name = user_class_jvm_name(class_name)
          fields_info = {}
          if native_type.respond_to?(:fields) && native_type.fields
            native_type.fields.each do |fname, ftype|
              fields_info[fname.to_s] = native_field_to_jvm_type(ftype)
            end
          end

          is_struct = native_type.respond_to?(:is_value_type?) && native_type.is_value_type?

          @class_info[class_name] = {
            fields: fields_info,
            jvm_name: jvm_class_name,
            super_name: "java/lang/Object",
            rbs_only: true,
            is_value_type: is_struct
          }
        end
      end

      # Generate a JVM class for an RBS-only native type
      # @struct types use regular mutable classes (matching LLVM mutable field semantics)
      def generate_rbs_only_class(class_name, info)
        jvm_class_name = info[:jvm_name]
        super_name = info[:super_name]
        fields_info = info[:fields]

        # Generate JVM fields
        jvm_fields = fields_info.map do |fname, ftype|
          {
            "name" => sanitize_field_name(fname),
            "descriptor" => type_to_descriptor(ftype),
            "access" => ["public"]
          }
        end

        # Generate default constructor: super() + zero-initialize all fields
        ctor_instructions = []
        ctor_instructions << { "op" => "aload", "var" => 0 }
        ctor_instructions << { "op" => "invokespecial", "owner" => super_name,
                               "name" => "<init>", "descriptor" => "()V" }

        fields_info.each do |fname, ftype|
          ctor_instructions << { "op" => "aload", "var" => 0 }
          ctor_instructions.concat(default_value_instructions(ftype))
          ctor_instructions << { "op" => "putfield", "owner" => jvm_class_name,
                                 "name" => sanitize_field_name(fname),
                                 "descriptor" => type_to_descriptor(ftype) }
        end
        ctor_instructions << { "op" => "return" }

        jvm_methods = [
          { "name" => "<init>", "descriptor" => "()V",
            "access" => ["public"], "instructions" => ctor_instructions }
        ]

        {
          "name" => jvm_class_name,
          "access" => ["public", "super"],
          "superName" => super_name,
          "interfaces" => [],
          "fields" => jvm_fields,
          "methods" => jvm_methods
        }
      end

      def topological_sort_classes(classes)
        sorted = []
        visited = Set.new
        class_map = classes.map { |cd| [cd.name.to_s, cd] }.to_h

        visit_topo = lambda do |cd|
          name = cd.name.to_s
          return if visited.include?(name)
          visited.add(name)
          if cd.superclass && class_map.key?(cd.superclass.to_s)
            visit_topo.call(class_map[cd.superclass.to_s])
          end
          sorted << cd
        end

        classes.each { |cd| visit_topo.call(cd) }
        sorted
      end

      def generate_user_class(class_def)
        class_name = class_def.name.to_s
        info = @class_info[class_name]
        jvm_class_name = info[:jvm_name]
        super_name = info[:super_name]
        fields_info = info[:fields]

        # Generate JVM fields
        jvm_fields = fields_info.map do |fname, ftype|
          {
            "name" => sanitize_field_name(fname),
            "descriptor" => type_to_descriptor(ftype),
            "access" => ["public"]
          }
        end

        # Generate methods
        jvm_methods = []

        # Pre-register method descriptors so intra-class calls always find
        # the correct descriptor regardless of generation order.
        pre_register_class_method_descriptors(class_def, fields_info)

        # Constructor(s)
        jvm_methods.concat(generate_class_constructor(class_def, fields_info, super_name))

        # Build set of methods overridden by prepended modules (Ruby MRO: prepend > class)
        prepended_method_funcs = {}
        (class_def.prepended_modules || []).each do |mod_name|
          mod_func_list = @hir_program.functions.select { |f|
            (f.owner_module.to_s == mod_name.to_s || f.owner_class.to_s == mod_name.to_s) && f.is_instance_method
          }
          mod_func_list.each do |mf|
            prepended_method_funcs[mf.name.to_s] ||= mf
          end
        end

        # Instance methods (skip initialize — already handled as <init> constructor above)
        # Deduplicate method_names to avoid JVM ClassFormatError on method override
        seen_methods = {}
        (class_def.method_names || []).each do |method_name|
          next if method_name.to_s == "initialize"
          next if seen_methods[method_name.to_s]
          seen_methods[method_name.to_s] = true
          # If a prepended module overrides this method, use the module's version
          func = prepended_method_funcs[method_name.to_s] || find_class_instance_method(class_name, method_name.to_s)
          next unless func
          jvm_methods << generate_instance_method(func, class_def, fields_info)
        end

        # Add methods from prepended modules that are NOT already in the class
        prepended_method_funcs.each do |method_name, func|
          next if seen_methods[method_name]
          seen_methods[method_name] = true
          jvm_methods << generate_instance_method(func, class_def, fields_info)
        end

        # Class methods (static)
        # Detect name conflicts: JVM forbids two methods with same name+descriptor,
        # even if one is static and the other virtual. Rename conflicting static methods.
        instance_method_set = (class_def.method_names || []).map(&:to_s).to_set
        (class_def.singleton_methods || []).each do |method_name|
          func = find_class_singleton_method(class_name, method_name.to_s)
          next unless func
          # Rename if conflicting with instance method of same name
          if instance_method_set.include?(method_name.to_s)
            jvm_methods << generate_class_static_method(func, class_def, rename_prefix: "$s_")
          else
            jvm_methods << generate_class_static_method(func, class_def)
          end
        end

        # Aliases — generate forwarding or full methods
        (class_def.aliases || []).each do |new_name, old_name|
          jvm_new = jvm_method_name(new_name)
          jvm_old = jvm_method_name(old_name)
          # Skip if alias name collides with an already-generated method
          next if seen_methods[new_name.to_s]
          seen_methods[new_name.to_s] = true

          # Check if method was redefined after aliasing — if so, compile original body
          all_matching = @hir_program.functions.select { |f|
            f.owner_class.to_s == class_name && f.name.to_s == old_name.to_s && f.is_instance_method
          }
          if all_matching.size > 1
            # Method was redefined — compile the first (original) definition as the alias
            orig_func = all_matching.first
            # Temporarily rename the function to generate it with the alias name
            orig_name_backup = orig_func.name
            orig_func.instance_variable_set(:@name, new_name.to_sym)
            alias_method = generate_instance_method(orig_func, class_def, fields_info)
            orig_func.instance_variable_set(:@name, orig_name_backup)
            jvm_methods << alias_method
            next
          end

          # Simple forwarding for non-redefined methods
          orig_key = "#{class_name}##{old_name}"
          orig_desc = @method_descriptors[orig_key]
          next unless orig_desc
          # Build forwarding method: load this + params, invokevirtual original, return
          fwd_instructions = []
          fwd_instructions << { "op" => "aload", "var" => 0 }  # this
          # Parse param types and load them
          param_types = parse_descriptor_param_types(orig_desc)
          slot = 1
          param_types.each do |pt|
            case pt
            when :i64
              fwd_instructions << { "op" => "lload", "var" => slot }
              slot += 2
            when :double
              fwd_instructions << { "op" => "dload", "var" => slot }
              slot += 2
            when :i8
              fwd_instructions << { "op" => "iload", "var" => slot }
              slot += 1
            else
              fwd_instructions << { "op" => "aload", "var" => slot }
              slot += 1
            end
          end
          jvm_class = user_class_jvm_name(class_name)
          fwd_instructions << { "op" => "invokevirtual", "owner" => jvm_class,
                                "name" => jvm_old, "descriptor" => orig_desc }
          # Return based on return type
          ret_desc = orig_desc[orig_desc.index(")") + 1..]
          case ret_desc
          when "J" then fwd_instructions << { "op" => "lreturn" }
          when "D" then fwd_instructions << { "op" => "dreturn" }
          when "I" then fwd_instructions << { "op" => "ireturn" }
          when "V" then fwd_instructions << { "op" => "return" }
          else fwd_instructions << { "op" => "areturn" }
          end
          # Register descriptor for the alias
          @method_descriptors["#{class_name}##{new_name}"] = orig_desc
          jvm_methods << {
            "name" => jvm_new,
            "descriptor" => orig_desc,
            "access" => ["public"],
            "instructions" => fwd_instructions
          }
        end

        # Extend — generate static wrapper methods from extended modules
        (class_def.extended_modules || []).each do |mod_name|
          mod_info = @module_info[mod_name.to_s]
          next unless mod_info
          mod_info[:methods].each do |method_name|
            func = find_module_instance_method(mod_name.to_s, method_name)
            next unless func
            jvm_methods << generate_extended_static_method(func, mod_name.to_s, class_def)
          end
        end

        # Collect interfaces from included and prepended modules
        interfaces = []
        all_mixed_modules = (class_def.included_modules || []) + (class_def.prepended_modules || [])
        all_mixed_modules.each do |mod_name|
          mod_name_s = mod_name.to_s
          if @module_info.key?(mod_name_s)
            interfaces << module_jvm_name(mod_name_s)
            # Register module method descriptors so invokevirtual on class instances works
            @module_info[mod_name_s][:methods].each do |meth_name|
              key = "#{class_name}##{meth_name}"
              unless @method_descriptors.key?(key)
                mod_key = "#{mod_name_s}##{meth_name}"
                @method_descriptors[key] = @method_descriptors[mod_key] if @method_descriptors[mod_key]
              end
            end
          end
        end

        # Add static fields for class body constants
        (class_def.body_constants || []).each do |const_name, _value_node|
          jvm_fields << {
            "name" => const_name.to_s,
            "descriptor" => "Ljava/lang/Object;",
            "access" => ["public", "static", "final"]
          }
        end

        # Class body class variables are stored on main class (via register_global_field
        # in generate_class_clinit), no separate fields needed on the class itself.

        # Generate <clinit> for class body constants and class variables
        clinit = generate_class_clinit(class_def, jvm_class_name)
        jvm_methods << clinit if clinit

        {
          "name" => jvm_class_name,
          "access" => ["public", "super"],
          "superName" => super_name,
          "interfaces" => interfaces,
          "fields" => jvm_fields,
          "methods" => jvm_methods
        }
      end

      # Pre-register method descriptors for all instance methods of a class
      # so that intra-class method calls always find the correct descriptor
      # regardless of method generation order.
      def pre_register_class_method_descriptors(class_def, fields_info)
        class_name = class_def.name.to_s
        (class_def.method_names || []).each do |method_name|
          next if method_name.to_s == "initialize"
          key = "#{class_name}##{method_name}"
          next if @method_descriptors.key?(key)

          func = find_class_instance_method(class_name, method_name.to_s)
          next unless func

          # Compute param types
          rbs_param_types = resolve_rbs_param_types(class_name, method_name.to_s, false)
          params_desc = func.params.each_with_index.map do |p, i|
            rbs_t = rbs_param_types && i < rbs_param_types.size ? rbs_param_types[i] : nil
            t = (rbs_t && rbs_t != :value) ? rbs_t : widened_param_type(func, p, i)
            t = :value if t == :void
            type_to_descriptor(t)
          end.join

          # Compute return type from RBS or HIR analysis
          rbs_ret = resolve_rbs_return_type(class_name, method_name.to_s, false)
          if rbs_ret && rbs_ret != :value
            ret_type = rbs_ret
          else
            frt = function_return_type(func)
            # When RBS says :value (untyped) but function_return_type says :void,
            # prefer :value — the method returns Object (possibly null)
            if frt == :void && rbs_ret == :value
              ret_type = :value
            else
              ret_type = frt
            end
          end
          # Ruby has no void methods — any method can be overridden by subclasses
          # to return a value. In JVM, void and Object are different return types,
          # so a void base method and an Object-returning override are different methods.
          # Always use :value (Object) for instance methods to ensure descriptor consistency.
          ret_type = :value if ret_type == :void
          # Without RBS, normalize all non-void types to :value for safety.
          # The method body may produce Object-typed values that don't match
          # specific descriptors (e.g. hash lookup returns Object, not String).
          if ret_type != :void && ret_type != :value
            ret_type = :value
          end

          @method_descriptors[key] = "(#{params_desc})#{type_to_descriptor(ret_type)}"
        end

        # Pre-register singleton (class) method descriptors
        (class_def.singleton_methods || []).each do |method_name|
          key = "#{class_name}.#{method_name}"
          next if @method_descriptors.key?(key)

          func = find_class_singleton_method(class_name, method_name.to_s)
          next unless func

          rbs_param_types = resolve_rbs_param_types(class_name, method_name.to_s, true)
          params_desc = func.params.each_with_index.map do |p, i|
            rbs_t = rbs_param_types && i < rbs_param_types.size ? rbs_param_types[i] : nil
            t = (rbs_t && rbs_t != :value) ? rbs_t : param_type(p)
            t = :value if t == :void
            type_to_descriptor(t)
          end.join

          rbs_ret = resolve_rbs_return_type(class_name, method_name.to_s, true)
          if rbs_ret && rbs_ret != :value
            ret_type = rbs_ret
          else
            frt = function_return_type(func)
            ret_type = (frt == :void) ? :value : frt
          end

          @method_descriptors[key] = "(#{params_desc})#{type_to_descriptor(ret_type)}"
        end
      end

      def resolve_class_fields(class_def)
        fields = {}

        # Try NativeClassType from RBS loader first (provides typed fields)
        if @rbs_loader
          begin
            native_type = @rbs_loader.native_class_type(class_def.name.to_s)
            if native_type && native_type.respond_to?(:fields) && native_type.fields
              native_type.fields.each do |fname, ftype|
                fields[fname.to_s] = native_field_to_jvm_type(ftype)
              end
            end
          rescue
            # RBS loader may not have this class
          end
        end

        # Also add instance_vars not already covered by RBS (provides untyped fields)
        (class_def.instance_vars || []).each do |ivar|
          clean_name = ivar.to_s.sub(/^@/, "")
          next if fields.key?(clean_name)  # RBS takes priority
          inferred = class_def.instance_var_types[clean_name]
          fields[clean_name] = inferred ? native_field_to_jvm_type(inferred) : :value
        end

        # Enhanced fallback: scan initialize body for literal assignments to detect types
        # This handles the case where HM inference doesn't provide ivar_types (e.g., no RBS)
        init_func = @hir_program&.functions&.find { |f|
          f.owner_class.to_s == class_def.name.to_s && f.name.to_s == "initialize"
        }
        if init_func
          init_func.body.each do |bb|
            bb.instructions.each do |inst|
              next unless inst.is_a?(HIR::StoreInstanceVar)
              clean_name = inst.name.to_s.sub(/^@/, "")
              if inst.value.is_a?(HIR::NilLit)
                # nil assignment: primitive types (:i64, :double, :i8) cannot hold null,
                # so downgrade to :value (Object) to allow nil storage.
                current = fields[clean_name]
                if current == :i64 || current == :double || current == :i8
                  fields[clean_name] = :value
                end
              elsif fields[clean_name] == :value
                # Only override unresolved types with detected literal types
                detected = detect_ivar_type_from_value(inst.value)
                fields[clean_name] = detected if detected
              end
            end
          end
        end

        fields
      end

      # Detect field type from the value being assigned in an initializer
      def detect_ivar_type_from_value(value)
        case value
        when HIR::ArrayLit then :array
        when HIR::HashLit then :hash
        when HIR::BoolLit then :i8
        when HIR::IntegerLit then :i64
        when HIR::FloatLit then :double
        when HIR::StringLit then :string
        when HIR::NilLit then nil  # nil doesn't tell us the type
        else
          # Check if value has a known type from HM inference
          if value.respond_to?(:type) && value.type
            tag = nil
            case value.type
            when TypeChecker::Types::INTEGER then tag = :i64
            when TypeChecker::Types::FLOAT then tag = :double
            when TypeChecker::Types::BOOL then tag = :i8
            when TypeChecker::Types::STRING then tag = :string
            end
            return tag if tag
            if value.type.is_a?(TypeChecker::Types::ClassInstance)
              case value.type.name
              when :Array then return :array
              when :Hash then return :hash
              end
            end
          end
          nil
        end
      end

      def native_field_to_jvm_type(field_type)
        case field_type.to_s.to_sym
        when :Int64, :Integer then :i64
        when :Float64, :Float then :double
        when :Bool then :i8
        when :String then :string
        when :Array then :array
        when :Hash then :hash
        else
          # Check if it's a user-defined class name
          class_name = field_type.to_s
          if @class_info && @class_info.key?(class_name)
            :"class:#{class_name}"
          else
            :value
          end
        end
      end

      # ========================================================================
      # Constructor Generation
      # ========================================================================

      def generate_class_constructor(class_def, fields_info, super_name)
        class_name = class_def.name.to_s
        init_func = find_class_instance_method(class_name, "initialize")
        constructors = []

        if init_func
          if init_func.params.any?
            # Generate both: no-arg default + parameterized with body
            constructors << generate_default_class_constructor(class_def, fields_info, super_name)
            constructors << generate_init_constructor(init_func, class_def, fields_info, super_name)
          else
            # No params but has body (e.g. @items = []) — run body in no-arg constructor
            constructors << generate_init_constructor(init_func, class_def, fields_info, super_name)
          end
        else
          # No initialize method at all — just default field initialization
          constructors << generate_default_class_constructor(class_def, fields_info, super_name)
        end

        constructors
      end

      def generate_default_class_constructor(class_def, fields_info, super_name)
        jvm_class_name = user_class_jvm_name(class_def.name.to_s)
        instructions = []

        # Call super()
        instructions << { "op" => "aload", "var" => 0 }
        instructions << { "op" => "invokespecial", "owner" => super_name,
                           "name" => "<init>", "descriptor" => "()V" }

        # Initialize fields to defaults
        fields_info.each do |fname, ftype|
          instructions << { "op" => "aload", "var" => 0 }
          instructions.concat(default_value_instructions(ftype))
          instructions << { "op" => "putfield", "owner" => jvm_class_name,
                             "name" => sanitize_field_name(fname),
                             "descriptor" => type_to_descriptor(ftype) }
        end

        instructions << { "op" => "return" }

        { "name" => "<init>", "descriptor" => "()V",
          "access" => ["public"], "instructions" => instructions }
      end

      def generate_init_constructor(init_func, class_def, fields_info, super_name)
        jvm_class_name = user_class_jvm_name(class_def.name.to_s)

        @current_generating_func_name = init_func.name.to_s
        reset_function_state(init_func)
        @current_class_name = class_def.name.to_s
        @current_class_fields = fields_info
        @generating_instance_method = true
        @current_method_name = "initialize"

        # Slot 0 = self
        allocate_slot("__self__", :value)

        # Allocate params
        init_func.params.each do |param|
          type = param_type(param)
          allocate_slot(param.name, type)
        end

        prescan_phi_nodes(init_func)

        instructions = []

        # JVM requires invokespecial <init> before field access.
        # Check if there's an explicit super(args) call in the initialize body.
        # If so, call the parent's parameterized <init> with the arguments.
        super_call = find_super_call_in_body(init_func.body)
        if super_call && super_call.args && !super_call.args.empty?
          # Find the parent's initialize method to get its descriptor
          parent_class_name = find_parent_class_name(class_def.name.to_s)
          parent_init_func = parent_class_name ? find_class_instance_method(parent_class_name, "initialize") : nil

          instructions << { "op" => "aload", "var" => 0 }
          if parent_init_func
            # Load super call arguments matching parent init's parameter types.
            # load_value handles boxing/unboxing based on expected type.
            super_call.args.each_with_index do |arg, i|
              parent_param_type = i < parent_init_func.params.size ? param_type(parent_init_func.params[i]) : :value
              instructions.concat(load_value(arg, parent_param_type))
            end
            params_desc = parent_init_func.params.map { |p| type_to_descriptor(param_type(p)) }.join
            instructions << { "op" => "invokespecial", "owner" => super_name,
                               "name" => "<init>", "descriptor" => "(#{params_desc})V" }
          else
            instructions << { "op" => "invokespecial", "owner" => super_name,
                               "name" => "<init>", "descriptor" => "()V" }
          end
        else
          instructions << { "op" => "aload", "var" => 0 }
          instructions << { "op" => "invokespecial", "owner" => super_name,
                             "name" => "<init>", "descriptor" => "()V" }
        end

        # Initialize all fields to defaults before running initialize body
        fields_info.each do |fname, ftype|
          instructions << { "op" => "aload", "var" => 0 }
          instructions.concat(default_value_instructions(ftype))
          instructions << { "op" => "putfield", "owner" => jvm_class_name,
                             "name" => sanitize_field_name(fname),
                             "descriptor" => type_to_descriptor(ftype) }
        end

        # Generate initialize body
        instructions.concat(generate_function_body(init_func))

        # Remove any non-void returns AND their preceding value-load instructions
        # (void constructors must have an empty stack before 'return')
        clean = []
        instructions.each do |inst|
          if return_instruction?(inst)
            # Pop any value-load instruction that was meant for this return
            clean.pop if !clean.empty? && value_load_instruction?(clean.last)
            next
          end
          clean << inst
        end
        instructions = clean
        instructions << { "op" => "return" }

        @generating_instance_method = false
        @current_class_name = nil
        @current_class_fields = nil
        @current_method_name = nil

        # Build descriptor from initialize params
        # Map :void to :value — nil/void is not valid as JVM parameter type
        init_param_types = init_func.params.map { |p| t = param_type(p); t == :void ? :value : t }
        params_desc = init_param_types.map { |t| type_to_descriptor(t) }.join
        init_desc = "(#{params_desc})V"

        # Register constructor descriptor and param types for call-site lookup
        @method_descriptors["#{class_def.name}<init>"] = init_desc
        @constructor_param_types[class_def.name.to_s] = init_param_types

        { "name" => "<init>", "descriptor" => init_desc,
          "access" => ["public"], "instructions" => instructions }
      end

      # ========================================================================
      # Instance Method Generation
      # ========================================================================

      def generate_instance_method(func, class_def, fields_info)
        @current_generating_func_name = func.name.to_s
        reset_function_state(func)

        @current_class_name = class_def.name.to_s
        @current_class_fields = fields_info
        @generating_instance_method = true
        @current_method_name = func.name.to_s

        # Pre-determine return type so generate_return knows if method returns Object.
        # For instance methods, default to :value (Object) — bare returns emit aconst_null+areturn.
        # The actual descriptor is determined after body generation via detect_return_type_from_instructions.
        rbs_ret_pre = resolve_rbs_return_type(class_def.name.to_s, func.name.to_s, false)
        pre_ret = if rbs_ret_pre && rbs_ret_pre != :value
                    rbs_ret_pre
                  else
                    frt = function_return_type(func)
                    # When RBS says :value but function_return_type says :void, use :value
                    (frt == :void && rbs_ret_pre == :value) ? :value : frt
                  end
        # :void from NilLit → treat as :value for instance methods (return null, not void)
        @current_function_return_type = (pre_ret == :void) ? :value : pre_ret

        # Slot 0 is 'self' - reserve it
        allocate_slot("__self__", :value)

        # Allocate parameter slots starting from slot 1
        # Prefer RBS-declared param types for consistent slot/descriptor types
        rbs_ptypes_pre = resolve_rbs_param_types(class_def.name.to_s, func.name.to_s, false)
        func.params.each_with_index do |param, i|
          rbs_t = rbs_ptypes_pre && i < rbs_ptypes_pre.size ? rbs_ptypes_pre[i] : nil
          type = (rbs_t && rbs_t != :value && rbs_t != :void) ? rbs_t : widened_param_type(func, param, i)
          allocate_slot(param.name, type)
          if param.rest || param.keyword_rest
            @variable_collection_types[param.name.to_s] = param.rest ? :array : :hash
          end
        end

        prescan_phi_nodes(func)
        instructions = generate_function_body(func)

        # Determine return type: prefer RBS-declared type, fallback to instruction analysis
        rbs_ret = resolve_rbs_return_type(class_def.name.to_s, func.name.to_s, false)
        ret_type = if rbs_ret && rbs_ret != :value
                     rbs_ret
                   else
                     detected = detect_return_type_from_instructions(instructions)
                     # When RBS says :value (untyped) but detection says :void,
                     # prefer :value — the method should return Object (possibly null)
                     (detected == :void && rbs_ret == :value) ? :value : detected
                   end

        # Ruby has no void methods — any method can be overridden by subclasses
        # to return a value. In JVM, void and Object are different return types,
        # causing descriptor mismatches between base and overriding methods.
        # Always use :value (Object) for instance methods.
        ret_type = :value if ret_type == :void

        # Sanitize returns for void methods (no longer reached for instance methods,
        # but kept for safety)
        if ret_type == :void
          instructions = sanitize_void_returns(instructions)
        end

        # Insert checkcast before areturn when return type is more specific than Object
        if ret_type == :string
          instructions = insert_return_checkcast(instructions, "java/lang/String")
        elsif ret_type.to_s.start_with?("class:")
          cast_type = user_class_jvm_name(ret_type.to_s.sub("class:", ""))
          instructions = insert_return_checkcast(instructions, cast_type)
        end

        # Convert areturn to unbox+lreturn/dreturn/ireturn when method returns a primitive type
        if ret_type == :i64 || ret_type == :double || ret_type == :i8
          instructions = convert_object_return_to_primitive(instructions, ret_type)
        end

        # Box primitive returns when method descriptor expects Object
        if ret_type == :value
          instructions = convert_primitive_return_to_object(instructions)
        end

        # Ensure method has a return instruction
        unless instructions.last && return_instruction?(instructions.last)
          instructions << default_return(ret_type)
        end

        # Post-process: insert checkcast before invokevirtual/getfield/putfield on user classes
        instructions = insert_missing_checkcasts(instructions)

        # Use pre-registered descriptor if available (ensures call-site consistency).
        # Otherwise compute descriptor from param types and detected return type.
        pre_key = "#{class_def.name}##{func.name}"
        pre_registered = @method_descriptors[pre_key]
        if pre_registered
          descriptor = pre_registered
          # Ensure ret_type matches the pre-registered descriptor's return type
          pre_ret = parse_descriptor_return_type(pre_registered)
          if pre_ret != ret_type
            # Adjust: e.g., pre_registered says :void but detect says :value
            ret_type = pre_ret
            if ret_type == :void
              instructions = sanitize_void_returns(instructions)
            elsif ret_type == :value
              instructions = convert_primitive_return_to_object(instructions)
            elsif ret_type == :i64 || ret_type == :double
              # Pre-registered expects primitive but body returns Object → unbox
              instructions = convert_object_return_to_primitive(instructions, ret_type)
            end
          end
        else
          rbs_param_types = resolve_rbs_param_types(class_def.name.to_s, func.name.to_s, false)
          params_desc = func.params.each_with_index.map do |p, i|
            rbs_t = rbs_param_types && i < rbs_param_types.size ? rbs_param_types[i] : nil
            t = (rbs_t && rbs_t != :value) ? rbs_t : param_type(p)
            t = :value if t == :void
            type_to_descriptor(t)
          end.join
          descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"
          @method_descriptors[pre_key] = descriptor
        end

        @generating_instance_method = false
        @current_class_name = nil
        @current_class_fields = nil
        @current_method_name = nil
        @current_function_return_type = nil

        {
          "name" => jvm_method_name(func.name),
          "descriptor" => descriptor,
          "access" => ["public"],
          "instructions" => instructions
        }
      end

      # ========================================================================
      # Class Static Method Generation
      # ========================================================================

      def generate_class_static_method(func, class_def, rename_prefix: nil)
        @current_generating_func_name = func.name.to_s
        reset_function_state(func)

        # Pre-determine return type so generate_return knows if method returns Object.
        # If a descriptor was pre-registered (from RBS), use its return type to ensure
        # the generated return instruction matches the pre-registered descriptor.
        pre_registered = @method_descriptors["#{class_def.name}.#{func.name}"]
        if pre_registered
          pre_ret = parse_descriptor_return_type(pre_registered)
        else
          pre_ret = function_return_type(func)
          pre_ret = :value if pre_ret == :void
        end
        @current_function_return_type = pre_ret

        # Try to resolve param types from RBS if HIR types are unresolved
        rbs_param_types = resolve_rbs_param_types(class_def.name.to_s, func.name.to_s, true)

        func.params.each_with_index do |param, i|
          type = param_type(param)
          # Fallback to RBS-resolved type if param type is :value (unresolved TypeVar)
          if type == :value && rbs_param_types && i < rbs_param_types.size && rbs_param_types[i] != :value
            @rbs_fallback_count += 1
            # RBS resolved what HM couldn't — undo typevar fallback (not a genuine failure)
            @typevar_fallback_count -= 1 if @typevar_fallback_count > 0
            type = rbs_param_types[i]
          end
          allocate_slot(param.name, type)
        end

        prescan_phi_nodes(func)
        instructions = generate_function_body(func)

        ret_type = detect_return_type_from_instructions(instructions)

        unless instructions.last && return_instruction?(instructions.last)
          instructions << default_return(ret_type)
        end

        # Build descriptor: if pre-registered, use that descriptor directly for consistency.
        # The pre-registered descriptor was computed from param_type/RBS before code gen,
        # matching what the call site will use. The code-gen-derived descriptor may differ
        # because detect_return_type_from_instructions can miss returns in branching code.
        if pre_registered
          descriptor = pre_registered
          # Ensure final return instruction matches the pre-registered return type
          pre_ret_type = parse_descriptor_return_type(pre_registered)
          if pre_ret_type != :void && pre_ret_type != :value
            # Replace trailing void return with typed default return if needed
            if instructions.last && instructions.last["op"] == "return"
              instructions.pop
              case pre_ret_type
              when :i64
                instructions << { "op" => "lconst_0" }
                instructions << { "op" => "lreturn" }
              when :double
                instructions << { "op" => "dconst_0" }
                instructions << { "op" => "dreturn" }
              when :i8
                instructions << { "op" => "iconst_0" }
                instructions << { "op" => "ireturn" }
              end
            end
          end
        else
          # Build descriptor from actual param types (which may have been corrected from RBS)
          params_desc = func.params.map { |p| type_to_descriptor(@variable_types[p.name.to_s] || :value) }.join
          descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"
        end

        # When renaming for conflict avoidance, use prefixed JVM name
        jvm_name = if rename_prefix
                     "#{rename_prefix}#{jvm_method_name(func.name)}"
                   else
                     jvm_method_name(func.name)
                   end

        # Register for call-site lookup (always under original name for call resolution)
        @method_descriptors["#{class_def.name}.#{func.name}"] = descriptor
        # Track rename so call sites can find the actual JVM method name
        if rename_prefix
          @static_method_renames["#{class_def.name}.#{func.name}"] = jvm_name
        end

        @current_function_return_type = nil

        {
          "name" => jvm_name,
          "descriptor" => descriptor,
          "access" => ["public", "static"],
          "instructions" => instructions
        }
      end

      # ========================================================================
      # Self Reference
      # ========================================================================

      def generate_self_ref(inst)
        result_var = inst.result_var
        return [] unless result_var

        ensure_slot(result_var, :value)
        instructions = [
          { "op" => "aload", "var" => 0 },
          store_instruction(result_var, :value)
        ]
        @variable_types[result_var] = :value
        if @current_class_name
          @variable_class_types[result_var] = @current_class_name
        end
        instructions
      end

      # ========================================================================
      # Instance Variable Access
      # ========================================================================

      def generate_load_instance_var(inst)
        result_var = inst.result_var
        field_name = inst.name.to_s.sub(/^@/, "")
        ivar_info = resolve_ivar_info(field_name)
        field_type = ivar_info ? ivar_info[:type] : :value
        field_owner = ivar_info ? ivar_info[:owner] : @current_class_name

        ensure_slot(result_var, field_type) if result_var

        instructions = []
        # aload self — use @block_self_slot if inside a block that captured self
        self_slot = @block_self_slot || 0
        instructions << { "op" => "aload", "var" => self_slot }
        # If self was captured as Object, checkcast to the expected class
        if @block_self_slot && field_owner
          instructions << { "op" => "checkcast", "type" => user_class_jvm_name(field_owner) }
        end
        # getfield — use the owning class (field may be inherited)
        instructions << {
          "op" => "getfield",
          "owner" => user_class_jvm_name(field_owner),
          "name" => sanitize_field_name(field_name),
          "descriptor" => type_to_descriptor(field_type)
        }

        if result_var
          instructions << store_instruction(result_var, field_type)
          @variable_types[result_var] = field_type
          # Detect collection type from field type or class field info
          if field_type == :array
            @variable_collection_types[result_var] = :array
          elsif field_type == :hash
            @variable_collection_types[result_var] = :hash
          elsif @ivar_collection_types&.dig(field_name)
            @variable_collection_types[result_var] = @ivar_collection_types[field_name]
          elsif @current_class_name
            collection = resolve_field_collection_type(@current_class_name, field_name)
            @variable_collection_types[result_var] = collection if collection
          end
          # Propagate user-defined class type for method dispatch
          field_type_s = field_type.to_s
          if field_type_s.start_with?("class:")
            @variable_class_types[result_var] = field_type_s.sub("class:", "")
          elsif field_type == :value && @current_class_name
            # Fallback: check HM-inferred ivar types for a user class type
            cls = resolve_ivar_class_type(@current_class_name, field_name)
            @variable_class_types[result_var] = cls if cls
          end
        end

        instructions
      end

      def generate_store_instance_var(inst)
        field_name = inst.name.to_s.sub(/^@/, "")
        ivar_info = resolve_ivar_info(field_name)
        field_type = ivar_info ? ivar_info[:type] : :value
        field_owner = ivar_info ? ivar_info[:owner] : @current_class_name

        instructions = []
        # aload self — use @block_self_slot if inside a block that captured self
        self_slot = @block_self_slot || 0
        instructions << { "op" => "aload", "var" => self_slot }
        # If self was captured as Object, checkcast to the expected class
        if @block_self_slot && field_owner
          instructions << { "op" => "checkcast", "type" => user_class_jvm_name(field_owner) }
        end
        # Load value to store
        instructions.concat(load_value(inst.value, field_type))
        # Add unboxing/checkcast if loaded value is Object but field expects a specific type
        loaded_type = infer_loaded_type(inst.value)
        if loaded_type == :value && field_type != :value
          case field_type
          when :i64, :double, :i8
            instructions.concat(unbox_from_object_field(field_type))
          when :string
            instructions << { "op" => "checkcast", "type" => "java/lang/String" }
          when :array
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KArray" }
          when :hash
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KHash" }
          else
            # User class field type (e.g., :"class:JWMFrame") — checkcast needed
            field_type_s = field_type.to_s
            if field_type_s.start_with?("class:")
              target_class = field_type_s.sub("class:", "")
              instructions << { "op" => "checkcast", "type" => user_class_jvm_name(target_class) }
            elsif field_type_s.include?("/")
              instructions << { "op" => "checkcast", "type" => field_type_s }
            end
          end
        elsif loaded_type == :i64 && field_type == :double
          # Integer param stored to Float field — long → double
          instructions << { "op" => "l2d" }
        elsif loaded_type == :double && field_type == :i64
          # Float param stored to Integer field — double → long
          instructions << { "op" => "d2l" }
        end
        # putfield — use the owning class (field may be inherited)
        instructions << {
          "op" => "putfield",
          "owner" => user_class_jvm_name(field_owner),
          "name" => sanitize_field_name(field_name),
          "descriptor" => type_to_descriptor(field_type)
        }

        # Track runtime collection type for ivar within current method scope
        # (e.g., @sorted_children = [] makes subsequent @sorted_children loads know it's an array)
        @ivar_collection_types ||= {}
        val = inst.value
        if val.is_a?(HIR::ArrayLit) || (val.respond_to?(:result_var) && val.result_var && @variable_collection_types[val.result_var] == :array)
          @ivar_collection_types[field_name] = :array
        elsif val.is_a?(HIR::HashLit) || (val.respond_to?(:result_var) && val.result_var && @variable_collection_types[val.result_var] == :hash)
          @ivar_collection_types[field_name] = :hash
        end

        instructions
      end

      def infer_loaded_type(hir_value)
        case hir_value
        when HIR::Param, HIR::LocalVar
          @variable_types[hir_value.name.to_s] || :value
        when HIR::LoadLocal
          var = hir_value.result_var || (hir_value.var.is_a?(HIR::LocalVar) ? hir_value.var.name.to_s : hir_value.var.to_s)
          @variable_types[var] || :value
        when HIR::StringLit then :string
        when HIR::IntegerLit then :i64
        when HIR::FloatLit then :double
        when HIR::BoolLit then :i8
        when HIR::NilLit then :value
        else
          # Check result_var in @variable_types (e.g. Phi nodes, Call results)
          if hir_value.respond_to?(:result_var) && hir_value.result_var
            @variable_types[hir_value.result_var] || :value
          else
            :value
          end
        end
      end

      # Load an HIR value as a JVM int (for array/string indexing).
      # Handles the case where the value is stored as :value (Object)
      # but needs to be unboxed to long before l2i.
      def load_value_as_int(hir_value)
        instructions = []
        loaded_type = infer_loaded_type(hir_value)
        if loaded_type == :value
          instructions.concat(load_value(hir_value, :value))
          instructions.concat(unbox_if_needed(:value, :i64))
        else
          instructions.concat(load_value(hir_value, :i64))
        end
        instructions << { "op" => "l2i" }
        instructions
      end

      def resolve_ivar_type(field_name)
        result = resolve_ivar_info(field_name)
        result ? result[:type] : :value
      end

      # Resolve field type and owning class by walking the inheritance chain
      # Returns { type: JVM_type, owner: "ClassName" } or nil
      def resolve_ivar_info(field_name)
        fname = field_name.to_s
        # Check current class fields first
        if @current_class_fields
          result = @current_class_fields[fname] || @current_class_fields[field_name]
          if result
            return { type: result, owner: @current_class_name }
          end
        end
        # Walk up inheritance chain to find inherited fields
        if @current_class_name
          class_name = @current_class_name
          while class_name
            info = @class_info[class_name]
            break unless info
            if info[:fields] && info[:fields][fname]
              return { type: info[:fields][fname], owner: class_name }
            end
            # Move to parent class
            super_name = info[:super_name]
            break unless super_name
            class_name = super_name.split("/").last
          end
        end
        nil
      end

      # ========================================================================
      # Constructor Call: ClassName.new(args)
      # ========================================================================

      def generate_constructor_call(inst, receiver, args, result_var)
        class_name = extract_class_name(receiver)
        return [] unless class_name
        info = @class_info[class_name]
        return [] unless info

        # Java interop class: delegate to JVM interop constructor
        if info[:jvm_interop]
          return generate_jvm_constructor(class_name, args, result_var, info)
        end

        jvm_class = info[:jvm_name]
        instructions = []

        # new + dup
        instructions << { "op" => "new", "type" => jvm_class }
        instructions << { "op" => "dup" }

        # Use registered constructor descriptor and param types for consistency
        registered_desc = @method_descriptors["#{class_name}<init>"]
        stored_param_types = @constructor_param_types[class_name]

        # Check if constructor has rest params — need to pack excess args into KArray
        init_func = find_class_instance_method(class_name, "initialize")
        has_rest = init_func&.params&.any? { |p| p.rest }

        if registered_desc && registered_desc != "()V" && stored_param_types
          if has_rest
            # Rest param constructor: pack excess args into KArray
            init_func.params.each_with_index do |param, i|
              if param.rest
                rest_args = args[i..]
                instructions << { "op" => "new", "type" => "konpeito/runtime/KArray" }
                instructions << { "op" => "dup" }
                instructions << { "op" => "invokespecial", "owner" => "konpeito/runtime/KArray",
                                  "name" => "<init>", "descriptor" => "()V" }
                rest_args.each do |arg|
                  instructions.concat(load_value(arg, :value))
                  instructions << { "op" => "invokevirtual", "owner" => "konpeito/runtime/KArray",
                                    "name" => "push", "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
                end
                break
              elsif i < args.size
                instructions.concat(load_value(args[i], stored_param_types[i]))
                loaded_t = infer_loaded_type(args[i])
                instructions.concat(unbox_if_needed(loaded_t, stored_param_types[i]))
              end
            end
          else
            # Load args using the same param types as the constructor definition
            stored_param_types.each_with_index do |param_t, i|
              if i < args.size
                instructions.concat(load_value(args[i], param_t))
                # Unbox if loaded type is :value but constructor expects primitive
                loaded_t = infer_loaded_type(args[i])
                instructions.concat(unbox_if_needed(loaded_t, param_t))
              else
                # Optional parameter not provided at call site — push default value
                init_param = init_func&.params&.[](i)
                if init_param&.default_value
                  instructions.concat(prism_default_to_jvm(init_param.default_value, param_t))
                else
                  instructions.concat(default_value_instructions(param_t))
                end
              end
            end
          end
          init_desc = registered_desc
        elsif args.any?
          # Fallback: no registered descriptor, compute from init_func
          if init_func && init_func.params.any?
            init_func.params.each_with_index do |param, i|
              if param.rest
                rest_args = args[i..]
                instructions << { "op" => "new", "type" => "konpeito/runtime/KArray" }
                instructions << { "op" => "dup" }
                instructions << { "op" => "invokespecial", "owner" => "konpeito/runtime/KArray",
                                  "name" => "<init>", "descriptor" => "()V" }
                rest_args.each do |arg|
                  instructions.concat(load_value(arg, :value))
                  instructions << { "op" => "invokevirtual", "owner" => "konpeito/runtime/KArray",
                                    "name" => "push", "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
                end
                break
              elsif i < args.size
                param_t = param_type(param)
                param_t = :value if param_t == :void
                instructions.concat(load_value(args[i], param_t))
                loaded_t = infer_loaded_type(args[i])
                instructions.concat(unbox_if_needed(loaded_t, param_t))
              end
            end
            params_desc = init_func.params.map { |p| t = param_type(p); t == :void ? :value : t }.map { |t| type_to_descriptor(t) }.join
            init_desc = "(#{params_desc})V"
          else
            init_desc = "()V"
          end
        else
          init_desc = "()V"
        end

        # invokespecial <init>
        instructions << { "op" => "invokespecial", "owner" => jvm_class,
                           "name" => "<init>", "descriptor" => init_desc }

        # Store result
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_class_types[result_var] = class_name
        end

        instructions
      end

      def generate_native_new(inst)
        # NativeNew is used by the LLVM backend for NativeClass allocation.
        # On JVM, we treat it similarly to a constructor call.
        result_var = inst.result_var
        class_type = inst.class_type
        class_name = class_type.respond_to?(:name) ? class_type.name.to_s : nil
        return [] unless class_name && @class_info.key?(class_name)

        info = @class_info[class_name]
        jvm_class = info[:jvm_name]

        instructions = []
        instructions << { "op" => "new", "type" => jvm_class }
        instructions << { "op" => "dup" }

        # Check if NativeNew carries constructor arguments
        if inst.args && inst.args.any?
          # Prefer registered constructor descriptor for consistency
          registered_desc = @method_descriptors["#{class_name}<init>"]
          stored_param_types = @constructor_param_types[class_name]

          if registered_desc && registered_desc != "()V" && stored_param_types
            stored_param_types.each_with_index do |param_t, i|
              if i < inst.args.size
                instructions.concat(load_value(inst.args[i], param_t))
                loaded_t = infer_loaded_type(inst.args[i])
                instructions.concat(unbox_if_needed(loaded_t, param_t))
              end
            end
            init_desc = registered_desc
          else
            # Fallback: find initialize method to determine param types
            init_func = find_class_instance_method(class_name, "initialize")
            if init_func && init_func.params.any?
              init_func.params.each_with_index do |param, i|
                if i < inst.args.size
                  param_t = param_type(param)
                  param_t = :value if param_t == :void
                  instructions.concat(load_value(inst.args[i], param_t))
                  loaded_t = infer_loaded_type(inst.args[i])
                  instructions.concat(unbox_if_needed(loaded_t, param_t))
                end
              end
              params_desc = init_func.params.map { |p| t = param_type(p); t == :void ? :value : t }.map { |t| type_to_descriptor(t) }.join
              init_desc = "(#{params_desc})V"
            else
              init_desc = "()V"
            end
          end
        else
          init_desc = "()V"
        end

        instructions << { "op" => "invokespecial", "owner" => jvm_class,
                           "name" => "<init>", "descriptor" => init_desc }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_class_types[result_var] = class_name
        end

        instructions
      end

      def generate_constant_lookup(inst)
        result_var = inst.result_var
        return [] unless result_var

        name = inst.name.to_s

        # Special Ruby constants: Float::INFINITY, Float::NAN, etc.
        if name == "Float::INFINITY"
          ensure_slot(result_var, :value)
          @variable_types[result_var] = :value
          return [
            { "op" => "getstatic", "owner" => "java/lang/Double",
              "name" => "POSITIVE_INFINITY", "descriptor" => "D" },
            { "op" => "invokestatic", "owner" => "java/lang/Double",
              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" },
            store_instruction(result_var, :value)
          ]
        end
        if name == "Float::NAN"
          ensure_slot(result_var, :value)
          @variable_types[result_var] = :value
          return [
            { "op" => "getstatic", "owner" => "java/lang/Double",
              "name" => "NaN", "descriptor" => "D" },
            { "op" => "invokestatic", "owner" => "java/lang/Double",
              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" },
            store_instruction(result_var, :value)
          ]
        end

        # Built-in Ruby class/module names (for ConstantLookup of Integer, String, etc.)
        builtin_classes = %w[
          Integer Float String Symbol Array Hash Regexp NilClass TrueClass FalseClass
          Numeric Comparable Object BasicObject Kernel Enumerable
          Range MatchData IO File Dir Time Proc Method
          StandardError RuntimeError ArgumentError TypeError NameError NoMethodError
          ZeroDivisionError RangeError IndexError KeyError IOError
          Fiber Thread Mutex ConditionVariable Queue SizedQueue
        ]

        # Check if this is a class/module reference or a value constant
        # Also check if this is a Java:: class alias (e.g., KUIRuntime = Java::Konpeito::Ui::KUIRuntime)
        java_class_alias = @variable_class_types[name]&.to_s&.start_with?("Java::")
        is_class = @class_info.key?(name) ||
                   @module_info.key?(name) ||
                   STDLIB_MODULES.key?(name) ||
                   builtin_classes.include?(name) ||
                   @variable_class_types.values.include?(name) ||
                   java_class_alias ||
                   (@rbs_loader && @rbs_loader.respond_to?(:native_class_type) &&
                    (begin; @rbs_loader.native_class_type(name); rescue; nil; end))

        if is_class
          # Class reference — used as receiver for ClassName.new / ClassName.method calls.
          # Store as the class name string so that comparisons like
          # `assert_equal(Integer, 1.class, ...)` work (k_class returns the name).
          ensure_slot(result_var, :value)
          @variable_types[result_var] = :value
          @variable_class_types[result_var] = name
          @variable_is_class_ref[result_var] = true

          [
            { "op" => "ldc", "value" => name },
            store_instruction(result_var, :value)
          ]
        else
          # Check if this constant was actually stored (has a field to load from)
          # Handle path-style constants like "CoMath::PI"
          const_name = name
          scope_name = nil
          if name.include?("::")
            parts = name.split("::")
            scope_name = parts[0..-2].join("::")
            const_name = parts.last
          end

          has_field = @constant_fields&.include?(const_name)
          found_owner = nil

          # If there's a scope, look up the constant in that specific class/module
          if scope_name && !has_field
            # Check class body_constants
            @hir_program&.classes&.each do |cls|
              if cls.name.to_s == scope_name && cls.respond_to?(:body_constants) &&
                 cls.body_constants&.any? { |cn, _| cn.to_s == const_name }
                has_field = true
                found_owner = user_class_jvm_name(scope_name)
                break
              end
            end
            # Check module constants
            unless has_field
              if @hir_program&.modules&.any? { |m|
                m.name.to_s == scope_name && m.respond_to?(:constants) && m.constants&.any? { |k, _| k.to_s == const_name }
              }
                has_field = true
                found_owner = module_jvm_name(scope_name)
              end
            end
            # Check module body_constants
            unless has_field
              @hir_program&.modules&.each do |m|
                if m.name.to_s == scope_name && m.respond_to?(:body_constants) &&
                   m.body_constants&.any? { |cn, _| cn.to_s == const_name }
                  has_field = true
                  found_owner = module_jvm_name(scope_name)
                  break
                end
              end
            end
          end

          unless has_field
            # Check modules for the constant (unscoped)
            @module_info.each do |mod_name, _|
              if @hir_program&.modules&.any? { |m|
                m.name.to_s == mod_name && m.respond_to?(:constants) && m.constants&.any? { |k, _| k.to_s == const_name }
              }
                has_field = true
                found_owner = module_jvm_name(mod_name)
                break
              end
            end
          end
          unless has_field
            # Check class body_constants (unscoped — for constants referenced within the same class)
            @hir_program&.classes&.each do |cls|
              if cls.respond_to?(:body_constants) && cls.body_constants&.any? { |cn, _| cn.to_s == const_name }
                has_field = true
                found_owner = user_class_jvm_name(cls.name.to_s)
                break
              end
            end
          end

          if has_field
            # Value constant (e.g., FIXED = 0, EXPANDING = 1) — load via getstatic
            ensure_slot(result_var, :value)
            @variable_types[result_var] = :value

            owner = if @constant_fields&.include?(const_name)
                      main_class_name
                    else
                      found_owner || main_class_name
                    end

            [
              { "op" => "getstatic", "owner" => owner,
                "name" => const_name, "descriptor" => "Ljava/lang/Object;" },
              store_instruction(result_var, :value)
            ]
          else
            # Unknown constant — treat as class/module reference (safe fallback)
            ensure_slot(result_var, :value)
            @variable_types[result_var] = :value
            @variable_class_types[result_var] = name
            @variable_is_class_ref[result_var] = true

            [
              { "op" => "aconst_null" },
              store_instruction(result_var, :value)
            ]
          end
        end
      end

      # ========================================================================
      # Instance Method Dispatch
      # ========================================================================

      def generate_instance_call(inst, method_name, receiver, args, result_var)
        recv_class_name = resolve_receiver_class(receiver)
        return [] unless recv_class_name
        info = @class_info[recv_class_name]
        return [] unless info

        # Java interop class: delegate to JVM interop instance call
        if info[:jvm_interop]
          return generate_jvm_instance_call(recv_class_name, method_name, receiver, args, result_var, info, inst.block)
        end

        jvm_class = info[:jvm_name]

        # Check prepended modules FIRST — they override class methods (Ruby MRO)
        included_module_name = nil
        target_func = nil
        class_def = @hir_program.classes.find { |cd| cd.name.to_s == recv_class_name }
        if class_def && (class_def.prepended_modules || []).any?
          (class_def.prepended_modules || []).each do |mod_name|
            func = find_module_instance_method(mod_name.to_s, method_name)
            if func
              target_func = func
              included_module_name = mod_name.to_s
              break
            end
          end
        end

        # Find the target method in class itself
        unless target_func
          target_func = find_class_instance_method(recv_class_name, method_name)
        end

        # Also check parent classes
        unless target_func
          target_func = find_inherited_method(recv_class_name, method_name)
        end

        # Check included modules for the method (not prepended — already checked above)
        unless target_func
          if class_def
            (class_def.included_modules || []).each do |mod_name|
              func = find_module_instance_method(mod_name.to_s, method_name)
              if func
                target_func = func
                included_module_name = mod_name.to_s
                break
              end
            end
          end
        end

        # Fallback: field setter (name=) or getter (name) when no method exists
        unless target_func
          return generate_field_accessor_call(recv_class_name, method_name, receiver, args, result_var)
        end

        instructions = []

        # Load receiver (objectref)
        instructions.concat(load_value(receiver, :value))

        owner_class = target_func.owner_class.to_s

        # checkcast receiver to owner class when receiver type is Object
        recv_var = extract_var_name(receiver)
        recv_type = recv_var ? (@variable_types[recv_var] || :value) : :value
        if recv_type == :value && @class_info[owner_class] && owner_class != recv_class_name.to_s
          instructions << { "op" => "checkcast", "type" => @class_info[owner_class][:jvm_name] }
        elsif recv_type == :value && @class_info[recv_class_name.to_s]
          instructions << { "op" => "checkcast", "type" => @class_info[recv_class_name.to_s][:jvm_name] }
        end

        # Resolve registered descriptor first so we can use its param types for loading
        descriptor_owner = included_module_name || owner_class
        registered = @method_descriptors["#{descriptor_owner}##{method_name}"]
        registered ||= @method_descriptors["#{recv_class_name}##{method_name}"]

        # Parse expected param types from the registered descriptor (authoritative)
        registered_param_types = registered ? parse_descriptor_param_types(registered) : nil

        # Load arguments
        target_func.params.each_with_index do |param, i|
          if param.block && inst.block
            # Compile block as KBlock lambda and pass as the &block argument
            instructions.concat(compile_block_arg_for_instance_call(inst.block))
          elsif param.keyword_rest
            # Keyword rest parameter (**kwargs): build a KHash from keyword_args
            if inst.respond_to?(:keyword_args) && inst.has_keyword_args?
              instructions.concat(build_kwargs_hash(inst.keyword_args))
            else
              # No keyword args provided — pass empty KHash
              instructions << { "op" => "new", "type" => KHASH_CLASS }
              instructions << { "op" => "dup" }
              instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                                "name" => "<init>", "descriptor" => "()V" }
            end
          elsif param.rest
            # Rest parameter (*args): collect remaining arguments into a KArray
            rest_args = args[i..]
            instructions << { "op" => "new", "type" => "konpeito/runtime/KArray" }
            instructions << { "op" => "dup" }
            instructions << { "op" => "invokespecial", "owner" => "konpeito/runtime/KArray",
                              "name" => "<init>", "descriptor" => "()V" }
            rest_args.each do |arg|
              instructions.concat(load_value(arg, :value))
              instructions << { "op" => "invokevirtual", "owner" => "konpeito/runtime/KArray",
                                "name" => "push", "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
            end
            break
          elsif i < args.size
            # Prefer registered descriptor's param type, fall back to HM inference
            param_t = (registered_param_types && i < registered_param_types.size) ? registered_param_types[i] : param_type(param)
            instructions.concat(load_value(args[i], param_t))
            # Unbox Object→primitive if variable holds Object but method expects primitive
            arg_var = extract_var_name(args[i])
            arg_actual = arg_var ? (@variable_types[arg_var] || :value) : (literal_type_tag(args[i]) || param_t)
            instructions.concat(unbox_if_needed(arg_actual, param_t))
            # Convert between primitive types (e.g., d2l when caller has double but method expects long)
            # Skip when:
            #   - arg_actual == :value: unbox_if_needed already handled Object→primitive
            #   - arg_actual == param_t: no conversion needed
            #   - param_t == :value: load_value already boxed primitives to Object
            if arg_actual != :value && arg_actual != param_t && param_t != :value
              instructions.concat(convert_for_store(param_t, arg_actual))
            end
            # Always checkcast for String params — @variable_types may track :string from HM inference
            # but JVM runtime may have Object (e.g., method returning Object descriptor with HM String type)
            if param_t == :string
              instructions << { "op" => "checkcast", "type" => "java/lang/String" }
            end
          else
            # Optional parameter not provided at call site — push default value
            param_t = param_type(param)
            if param.default_value
              instructions.concat(prism_default_to_jvm(param.default_value, param_t))
            else
              instructions.concat(default_value_instructions(param_t))
            end
          end
        end

        # Build method descriptor — use the registered descriptor if available
        # to ensure call-site matches the actual method definition
        inferred_return_class = nil
        if registered
          descriptor = registered
          # Parse return type from registered descriptor for result storage
          ret_type = parse_descriptor_return_type(registered)
          # Check if the method returns self (builder pattern) or a known class for class type tracking
          if ret_type == :value
            frt = function_return_type(target_func)
            if frt.is_a?(Symbol) && frt.to_s.start_with?("class:")
              # Use receiver class, not method owner, for self-returning methods.
              # When calling inherited methods (e.g., BaseChart#title on a BarChart),
              # `self` is the actual receiver type (BarChart), not the defining class.
              inferred_return_class = recv_class_name
            end
            # Also check HM-inferred return type from the call instruction
            if inferred_return_class.nil? && inst.respond_to?(:type) && inst.type
              call_type = inst.type
              call_type = call_type.prune if call_type.respond_to?(:prune)
              if call_type.is_a?(TypeChecker::Types::ClassInstance) && @class_info.key?(call_type.name.to_s)
                inferred_return_class = call_type.name.to_s
              end
            end
          end
        else
          params_desc = target_func.params.map { |p| type_to_descriptor(param_type(p)) }.join
          ret_type = function_return_type(target_func)

          # Prefer RBS-declared return type for accurate descriptor (HIR types may be unresolved)
          rbs_ret = resolve_rbs_return_type(owner_class, method_name, false)
          if rbs_ret && rbs_ret != :value
            ret_type = rbs_ret
          else
            # Without RBS, normalize return type to :value (Object) for safety.
            # This matches pre_register_class_method_descriptors normalization to avoid
            # descriptor mismatch between call site and method definition.
            # Preserve class type info for @variable_class_types.
            # Use receiver class (not method owner) for self-returning methods —
            # inherited self-returning methods return the actual receiver type.
            inferred_return_class = nil
            if ret_type.is_a?(Symbol) && ret_type.to_s.start_with?("class:")
              inferred_return_class = recv_class_name
            end
            ret_type = :value if ret_type == :void
            ret_type = :value if ret_type != :void && ret_type != :value
          end

          descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"
        end

        # Determine which class owns the method for invokevirtual
        # For included module methods, use the receiver class (invokevirtual resolves default methods)
        owner_jvm = if included_module_name
                      jvm_class  # invokevirtual on the class will resolve to the interface default method
                    elsif @class_info[owner_class]
                      @class_info[owner_class][:jvm_name]
                    else
                      jvm_class
                    end

        # invokevirtual
        instructions << { "op" => "invokevirtual", "owner" => owner_jvm,
                           "name" => jvm_method_name(method_name),
                           "descriptor" => descriptor }

        # Store result
        if result_var && ret_type != :void
          # checkcast when return type is a user class (descriptor returns Object but actual is specific class)
          if ret_type == :value
            rbs_class = resolve_rbs_return_class_name(owner_class, method_name)
            # When function returns self (SelfRef), preserve the receiver's actual class type.
            # RBS annotations declare the defining class (e.g., Widget#fixed_height → Widget)
            # but `self` at runtime is the receiver's class (e.g., Button). Without this,
            # method chains like Button(...).fixed_height(36.0).on_click { ... } break because
            # the receiver type narrows to Widget and on_click (defined on Button) is not found.
            if inferred_return_class
              rbs_class = inferred_return_class
            else
              rbs_class ||= inferred_return_class
            end
            if rbs_class && @class_info.key?(rbs_class)
              instructions << { "op" => "checkcast", "type" => @class_info[rbs_class][:jvm_name] }
              @variable_class_types[result_var] = rbs_class
            end

          end

          ensure_slot(result_var, ret_type)
          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        elsif result_var && ret_type == :void
          # Void method: store null so downstream code doesn't reference uninitialized vars
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          @variable_types[result_var] = :value
        end

        instructions
      end

      # Generate field getter/setter when no method exists
      # Handles: obj.name (getter) → getfield, obj.name=("val") → putfield
      def generate_field_accessor_call(class_name, method_name, receiver, args, result_var)
        # Check for setter: name= with 1 arg
        if method_name.end_with?("=") && args.size == 1
          field_name = method_name.chomp("=")
          field_info = find_field_in_class_hierarchy(class_name, field_name)
          return [] unless field_info

          owner_jvm, field_type = field_info
          instructions = []
          instructions.concat(load_value(receiver, :value))
          instructions.concat(load_value(args.first, field_type))
          instructions << { "op" => "putfield", "owner" => owner_jvm,
                             "name" => sanitize_field_name(field_name),
                             "descriptor" => type_to_descriptor(field_type) }
          if result_var
            ensure_slot(result_var, field_type)
            instructions.concat(load_value(args.first, field_type))
            instructions << store_instruction(result_var, field_type)
            @variable_types[result_var] = field_type
          end
          return instructions
        end

        # Check for getter: name with 0 args
        if args.empty?
          field_info = find_field_in_class_hierarchy(class_name, method_name)
          if field_info
            owner_jvm, field_type = field_info
            instructions = []
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "getfield", "owner" => owner_jvm,
                               "name" => sanitize_field_name(method_name),
                               "descriptor" => type_to_descriptor(field_type) }
            if result_var
              ensure_slot(result_var, field_type)
              instructions << store_instruction(result_var, field_type)
              @variable_types[result_var] = field_type
            end
            return instructions
          end
        end

        []
      end

      # Find a field in the class or its parents, returns [jvm_class_name, field_type] or nil
      # Resolve JVM field type from @class_info (includes :string), falling back to LLVM tag
      def resolve_jvm_field_type(class_name, field_name)
        field_info = find_field_in_class_hierarchy(class_name, field_name)
        field_info ? field_info[1] : :value
      end

      def find_field_in_class_hierarchy(class_name, field_name)
        current = class_name
        while current
          info = @class_info[current]
          if info && info[:fields] && info[:fields].key?(field_name)
            return [info[:jvm_name], info[:fields][field_name]]
          end
          current = find_parent_class_name(current)
        end
        nil
      end

      def generate_self_method_call(inst, method_name, args, result_var)
        target_func = find_class_instance_method(@current_class_name, method_name)
        # Also check parent class methods
        unless target_func
          target_func = find_inherited_method(@current_class_name, method_name)
        end
        # Also check module methods for self.method() within module default methods
        unless target_func
          if @module_info.key?(@current_class_name)
            target_func = find_module_instance_method(@current_class_name, method_name)
          end
        end
        if target_func.nil?
          # Store null for result var to avoid uninitialized variable references
          instructions = []
          if result_var
            ensure_slot(result_var, :value)
            instructions << { "op" => "aconst_null" }
            instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
            @variable_types[result_var] = :value
          end
          return instructions
        end

        jvm_class = if @module_info.key?(@current_class_name)
                      module_jvm_name(@current_class_name)
                    else
                      user_class_jvm_name(@current_class_name)
                    end
        instructions = []

        # Load self — use @block_self_slot if inside a block that captured self
        self_slot = @block_self_slot || 0
        instructions << { "op" => "aload", "var" => self_slot }
        # If self was captured as Object, checkcast to the expected class
        if @block_self_slot
          instructions << { "op" => "checkcast", "type" => jvm_class }
        end

        # Prefer registered descriptor for consistency with method definition
        registered = @method_descriptors["#{@current_class_name}##{method_name}"]
        # Also check parent class descriptors
        unless registered
          parent = @class_info[@current_class_name]&.dig(:super_name)
          while parent && !registered
            parent_name = parent.split("/").last
            registered = @method_descriptors["#{parent_name}##{method_name}"]
            parent = @class_info[parent_name]&.dig(:super_name)
          end
        end
        registered_param_types = registered ? parse_descriptor_param_types(registered) : nil

        # Load arguments
        target_func.params.each_with_index do |param, i|
          if param.keyword_rest
            # Keyword rest parameter (**kwargs): build a KHash from keyword_args
            if inst.respond_to?(:keyword_args) && inst.has_keyword_args?
              instructions.concat(build_kwargs_hash(inst.keyword_args))
            else
              # No keyword args provided — pass empty KHash
              instructions << { "op" => "new", "type" => KHASH_CLASS }
              instructions << { "op" => "dup" }
              instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                                "name" => "<init>", "descriptor" => "()V" }
            end
          elsif param.rest
            # Rest parameter (*args): collect remaining arguments into a KArray
            rest_args = args[i..]
            instructions << { "op" => "new", "type" => "konpeito/runtime/KArray" }
            instructions << { "op" => "dup" }
            instructions << { "op" => "invokespecial", "owner" => "konpeito/runtime/KArray",
                              "name" => "<init>", "descriptor" => "()V" }
            rest_args.each do |arg|
              instructions.concat(load_value(arg, :value))
              instructions << { "op" => "invokevirtual", "owner" => "konpeito/runtime/KArray",
                                "name" => "push", "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
            end
            break
          elsif i < args.size
            param_t = (registered_param_types && i < registered_param_types.size) ? registered_param_types[i] : param_type(param)
            instructions.concat(load_value(args[i], param_t))
            arg_var = extract_var_name(args[i])
            arg_actual = arg_var ? (@variable_types[arg_var] || :value) : (literal_type_tag(args[i]) || param_t)
            instructions.concat(unbox_if_needed(arg_actual, param_t))
            # Convert between primitive types (e.g., d2l when caller has double but method expects long)
            if arg_actual != :value && arg_actual != param_t && param_t != :value
              instructions.concat(convert_for_store(param_t, arg_actual))
            end
            # Always checkcast for String params — @variable_types may track :string from HM inference
            # but JVM runtime may have Object (e.g., method returning Object descriptor with HM String type)
            if param_t == :string
              instructions << { "op" => "checkcast", "type" => "java/lang/String" }
            end
          else
            # Optional parameter not provided at call site — push default value
            param_t = param_type(param)
            if param.default_value
              instructions.concat(prism_default_to_jvm(param.default_value, param_t))
            else
              instructions.concat(default_value_instructions(param_t))
            end
          end
        end

        if registered
          descriptor = registered
          ret_type = parse_descriptor_return_type(registered)
        else
          # No registered descriptor yet (method not generated).
          # Use :value (Object) for return type to ensure consistency —
          # method definitions use detect_return_type_from_instructions which
          # returns :value for areturn. Using function_return_type here could
          # produce a more specific type that mismatches the definition.
          params_desc = target_func.params.map { |p| type_to_descriptor(param_type(p)) }.join
          ret_type = :value
          descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"
        end

        instructions << { "op" => "invokevirtual", "owner" => jvm_class,
                           "name" => jvm_method_name(method_name),
                           "descriptor" => descriptor }

        if result_var && ret_type != :void
          ensure_slot(result_var, ret_type)
          # Track user class type for subsequent method dispatch
          ret_type_s = ret_type.to_s
          if ret_type_s.start_with?("class:")
            @variable_class_types[result_var] = ret_type_s.sub("class:", "")
          end

          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        elsif result_var && ret_type == :void
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          @variable_types[result_var] = :value
        end

        instructions
      end

      # ========================================================================
      # Class Method Call: ClassName.method(args)
      # ========================================================================

      def generate_class_method_call(inst, receiver, method_name, args, result_var)
        class_name = extract_class_name(receiver)
        return [] unless class_name

        info = @class_info[class_name]
        return [] unless info

        # Java interop class: delegate to JVM interop static call
        if info[:jvm_interop]
          return generate_jvm_static_call(class_name, method_name, args, result_var, info, inst.block)
        end

        target_func = find_class_singleton_method(class_name, method_name)

        # Check extended modules if no class singleton method found
        unless target_func
          class_def = @hir_program.classes.find { |cd| cd.name.to_s == class_name }
          if class_def
            (class_def.extended_modules || []).each do |mod_name|
              target_func = find_module_instance_method(mod_name.to_s, method_name)
              break if target_func
            end
          end
        end

        # Walk up inheritance chain for class methods (JVM static methods aren't inherited)
        owner_class = class_name
        unless target_func
          parent = @hir_program.classes.find { |cd| cd.name.to_s == class_name }&.superclass&.to_s
          while parent && !target_func
            target_func = find_class_singleton_method(parent, method_name)
            owner_class = parent if target_func
            parent = @hir_program.classes.find { |cd| cd.name.to_s == parent }&.superclass&.to_s
          end
        end

        return [] unless target_func

        # Look up the registered descriptor first to determine expected param types
        registered = @method_descriptors["#{owner_class}.#{method_name}"] ||
                     @method_descriptors["#{class_name}.#{method_name}"]
        registered_param_types = registered ? parse_descriptor_param_types(registered) : nil

        # Resolve param types: prefer RBS types over HIR types (which may be unresolved TypeVars)
        rbs_param_types = resolve_rbs_param_types(owner_class, method_name, true) ||
                          resolve_rbs_param_types(class_name, method_name, true)

        instructions = []

        # Load arguments using resolved types
        arg_types = []
        target_func.params.each_with_index do |param, i|
          if param.keyword_rest
            # Keyword rest parameter (**kwargs): build a KHash from keyword_args
            if inst.respond_to?(:keyword_args) && inst.has_keyword_args?
              instructions.concat(build_kwargs_hash(inst.keyword_args))
            else
              instructions << { "op" => "new", "type" => KHASH_CLASS }
              instructions << { "op" => "dup" }
              instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                                "name" => "<init>", "descriptor" => "()V" }
            end
            arg_types << :hash
          elsif i < args.size
            # Use registered descriptor's param type if available (most accurate)
            param_t = if registered_param_types && i < registered_param_types.size
                        registered_param_types[i]
                      else
                        pt = param_type(param)
                        if pt == :value && rbs_param_types && i < rbs_param_types.size && rbs_param_types[i] != :value
                          rbs_param_types[i]
                        else
                          pt
                        end
                      end
            instructions.concat(load_value(args[i], param_t))
            arg_types << param_t
          else
            # Optional parameter not provided at call site — push default value
            param_t = param_type(param)
            if param.default_value
              instructions.concat(prism_default_to_jvm(param.default_value, param_t))
            else
              instructions.concat(default_value_instructions(param_t))
            end
            arg_types << param_t
          end
        end

        # Build descriptor — prefer registered descriptor for consistency
        if registered
          descriptor = registered
          ret_type = parse_descriptor_return_type(registered)
        else
          rbs_ret_type = resolve_rbs_return_type(class_name, method_name, true)
          ret_type = rbs_ret_type || function_return_type(target_func)

          params_desc = arg_types.map { |t| type_to_descriptor(t) }.join
          descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"
        end

        # Use renamed static method name if it was renamed to avoid conflict with instance method
        static_jvm_name = @static_method_renames["#{owner_class}.#{method_name}"] ||
                          @static_method_renames["#{class_name}.#{method_name}"] ||
                          jvm_method_name(method_name)
        # Use the owner class's JVM name (may differ from class_name when inheriting)
        owner_jvm_name = owner_class == class_name ? info[:jvm_name] : user_class_jvm_name(owner_class)
        instructions << { "op" => "invokestatic", "owner" => owner_jvm_name,
                           "name" => static_jvm_name, "descriptor" => descriptor }

        if result_var && ret_type != :void
          # Propagate class type for static methods that return a class instance
          if ret_type == :value
            inferred_class = nil
            # Check function_return_type for self-returning (builder pattern) class methods
            frt = function_return_type(target_func)
            if frt.is_a?(Symbol) && frt.to_s.start_with?("class:")
              inferred_class = frt.to_s.sub("class:", "")
            end
            # Also check HM-inferred return type
            if inferred_class.nil? && inst.respond_to?(:type) && inst.type
              call_type = inst.type
              call_type = call_type.prune if call_type.respond_to?(:prune)
              if call_type.is_a?(TypeChecker::Types::ClassInstance) && @class_info.key?(call_type.name.to_s)
                inferred_class = call_type.name.to_s
              end
            end
            if inferred_class && @class_info.key?(inferred_class)
              instructions << { "op" => "checkcast", "type" => @class_info[inferred_class][:jvm_name] }
              @variable_class_types[result_var] = inferred_class
            end
          end
          ensure_slot(result_var, ret_type)
          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        end

        instructions
      end

      # ========================================================================
      # Module Singleton Method Call
      # ========================================================================

      def generate_module_method_call(inst, receiver, method_name, args, result_var)
        mod_name = if receiver.is_a?(HIR::ConstantLookup)
                     receiver.name.to_s
                   else
                     var_name = extract_var_name(receiver)
                     var_name ? @variable_class_types[var_name] : nil
                   end
        return [] unless mod_name

        mod_info = @module_info[mod_name]
        return [] unless mod_info

        target_func = find_module_singleton_method(mod_name, method_name)
        return [] unless target_func

        # Look up the registered descriptor first to determine expected param types
        registered = @method_descriptors["#{mod_name}.#{method_name}"]

        instructions = []

        # Load arguments using the descriptor-expected types
        arg_types = []
        registered_param_types = registered ? parse_descriptor_param_types(registered) : nil
        target_func.params.each_with_index do |param, i|
          if param.keyword_rest
            # Keyword rest parameter (**kwargs): build a KHash from keyword_args
            if inst.respond_to?(:keyword_args) && inst.has_keyword_args?
              instructions.concat(build_kwargs_hash(inst.keyword_args))
            else
              instructions << { "op" => "new", "type" => KHASH_CLASS }
              instructions << { "op" => "dup" }
              instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                                "name" => "<init>", "descriptor" => "()V" }
            end
            arg_types << :hash
          elsif i < args.size
            # Use registered descriptor's param type if available (most accurate)
            param_t = if registered_param_types && i < registered_param_types.size
                        registered_param_types[i]
                      else
                        param_type(param)
                      end
            instructions.concat(load_value(args[i], param_t))
            arg_types << param_t
          else
            # Optional parameter not provided at call site — push default value
            param_t = param_type(param)
            if param.default_value
              instructions.concat(prism_default_to_jvm(param.default_value, param_t))
            else
              instructions.concat(default_value_instructions(param_t))
            end
            arg_types << param_t
          end
        end

        # Build descriptor
        if registered
          descriptor = registered
          ret_type = parse_descriptor_return_type(registered)
        else
          ret_type = function_return_type(target_func)
          params_desc = arg_types.map { |t| type_to_descriptor(t) }.join
          descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"
        end

        instructions << { "op" => "invokestatic", "owner" => mod_info[:jvm_name],
                           "name" => jvm_method_name(method_name), "descriptor" => descriptor,
                           "isInterface" => true }

        if result_var && ret_type != :void
          ensure_slot(result_var, ret_type)
          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        end

        instructions
      end

      # ========================================================================
      # Standard Library Module Call
      # ========================================================================

      def generate_stdlib_call(stdlib_info, method_name, args, result_var)
        method_info = stdlib_info[:methods][method_name]
        unless method_info
          warn "[JVM] Unknown stdlib method: #{method_name}"
          return []
        end

        instructions = []

        # Parse descriptor to determine parameter types
        descriptor = method_info[:descriptor]
        param_types = parse_descriptor_param_types(descriptor)

        # Load arguments onto the stack
        args.each_with_index do |arg, i|
          break if i >= param_types.size
          expected_type = param_types[i]
          instructions.concat(load_value(arg, expected_type))
        end

        # Emit invokestatic
        instructions << {
          "op" => "invokestatic",
          "owner" => stdlib_info[:runtime_class],
          "name" => method_info[:java_name],
          "descriptor" => descriptor
        }

        # Store result
        ret_type = method_info[:return_type] || :value
        if result_var && ret_type != :void
          ensure_slot(result_var, ret_type)
          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        elsif result_var && ret_type == :void
          # Mark the result variable as void so generate_return knows not to load it
          @variable_types[result_var] = :void
        end

        instructions
      end

      # ========================================================================
      # JVM Interop: Java:: class support
      # ========================================================================

      def register_jvm_interop_classes
        return unless @rbs_loader&.respond_to?(:jvm_classes)

        @rbs_loader.jvm_classes.each do |ruby_name, jvm_info|
          @class_info[ruby_name] = {
            fields: {},
            jvm_name: jvm_info[:jvm_internal_name],
            super_name: "java/lang/Object",
            jvm_interop: true,
            jvm_methods: jvm_info[:methods],
            jvm_static_methods: jvm_info[:static_methods],
            jvm_constructor_params: jvm_info[:constructor_params],
            jvm_static_module: jvm_info[:jvm_static_module] || jvm_info[:auto_registered]
          }
        end
      end

      def generate_jvm_constructor(class_name, args, result_var, info)
        jvm_class = info[:jvm_name]
        instructions = []

        # new + dup
        instructions << { "op" => "new", "type" => jvm_class }
        instructions << { "op" => "dup" }

        # Load constructor arguments
        ctor_params = info[:jvm_constructor_params] || []
        ctor_params.each_with_index do |param_type, i|
          break if i >= args.size
          instructions.concat(load_jvm_interop_arg(args[i], param_type))
        end

        # Build <init> descriptor
        params_desc = ctor_params.map { |t| jvm_interop_descriptor(t) }.join
        init_desc = "(#{params_desc})V"

        # invokespecial <init>
        instructions << { "op" => "invokespecial", "owner" => jvm_class,
                           "name" => "<init>", "descriptor" => init_desc }

        # Store result
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_class_types[result_var] = class_name
        end

        instructions
      end

      def generate_jvm_instance_call(class_name, method_name, receiver, args, result_var, info, block_def = nil)
        jvm_class = info[:jvm_name]
        method_info = info[:jvm_methods]&.dig(method_name)
        # Also try snake_to_camel conversion for Ruby-style method names
        method_info ||= info[:jvm_methods]&.dig(snake_to_camel(method_name.to_s))
        return [] unless method_info

        param_types = method_info[:params]
        ret_type = method_info[:return]
        return_class = method_info[:return_class]
        java_name = method_info[:java_name] || method_name

        instructions = []

        # Load receiver + checkcast
        instructions.concat(load_value(receiver, :value))
        instructions << { "op" => "checkcast", "type" => jvm_class }

        # Load arguments with Java int conversion
        param_types.each_with_index do |param_type, i|
          break if i >= args.size
          instructions.concat(load_jvm_interop_arg(args[i], param_type))
        end

        # Handle block → SAM conversion via invokedynamic + LambdaMetafactory
        cb_interface_desc = nil
        if block_def && method_info[:block_callback]
          cb_info = method_info[:block_callback]
          cb_interface = cb_info[:interface]
          cb_param_types = cb_info[:param_types] || block_def.params.map { |p| param_type(p) }
          cb_ret_type = cb_info[:return_type] || :void

          all_captures = block_def.captures || []
          # Filter out shared mutable captures — they use static fields instead
          captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
          capture_types = captures.map { |c| @variable_types[c.name.to_s] || :value }
          # Pass all_captures to compile so block body can reference them, but only non-shared become params
          block_method_name = compile_block_as_method_with_types(
            block_def, capture_types, cb_param_types, cb_ret_type,
            filtered_captures: captures
          )

          captures.each do |cap|
            cap_type = @variable_types[cap.name.to_s] || :value
            instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), cap_type))
          end

          capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
          indy_desc = "(#{capture_desc})L#{cb_interface};"
          block_params_desc = (capture_types + cb_param_types).map { |t| type_to_descriptor(t) }.join
          block_full_desc = "(#{block_params_desc})#{type_to_descriptor(cb_ret_type)}"
          call_desc = "(#{cb_param_types.map { |t| type_to_descriptor(t) }.join})#{type_to_descriptor(cb_ret_type)}"

          instructions << {
            "op" => "invokedynamic",
            "name" => "call",
            "descriptor" => indy_desc,
            "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
            "bootstrapName" => "metafactory",
            "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
            "bootstrapArgs" => [
              { "type" => "methodType", "descriptor" => call_desc },
              { "type" => "handle", "tag" => "H_INVOKESTATIC",
                "owner" => @current_enclosing_class,
                "name" => block_method_name,
                "descriptor" => block_full_desc },
              { "type" => "methodType", "descriptor" => call_desc }
            ]
          }

          cb_interface_desc = "L#{cb_interface};"
        end

        # Build descriptor (append callback interface param if block was compiled)
        params_desc = param_types.map { |t| jvm_interop_descriptor(t) }.join
        params_desc += cb_interface_desc if cb_interface_desc
        ret_desc = jvm_interop_descriptor(ret_type)
        descriptor = "(#{params_desc})#{ret_desc}"

        # invokevirtual (use java_name for auto-registered classes)
        instructions << { "op" => "invokevirtual", "owner" => jvm_class,
                           "name" => java_name, "descriptor" => descriptor }

        # Handle return value
        if result_var && ret_type != :void
          # Convert Java int return to Konpeito long
          instructions.concat(jvm_interop_convert_return(ret_type))

          store_type = jvm_interop_store_type(ret_type)
          ensure_slot(result_var, store_type)
          instructions << store_instruction(result_var, store_type)
          @variable_types[result_var] = store_type

          # Track class type for method chaining
          if return_class
            @variable_class_types[result_var] = return_class
          end
        end

        instructions
      end

      def generate_jvm_static_call(class_name, method_name, args, result_var, info, block_def = nil)
        jvm_class = info[:jvm_name]
        method_info = info[:jvm_static_methods]&.dig(method_name)
        return [] unless method_info

        param_types = method_info[:params]
        ret_type = method_info[:return]

        # Use java_name for snake_case → camelCase mapping (from %a{jvm_static} modules)
        java_method_name = method_info[:java_name] || method_name

        instructions = []

        # Load arguments with Java int conversion
        param_types.each_with_index do |param_type, i|
          break if i >= args.size
          instructions.concat(load_jvm_interop_arg(args[i], param_type))
        end

        # Handle block → SAM conversion via invokedynamic + LambdaMetafactory
        cb_interface_desc = nil
        if block_def && method_info[:block_callback]
          cb_info = method_info[:block_callback]
          cb_interface = cb_info[:interface]
          # Use param types from annotation descriptor if available, otherwise infer from block
          cb_param_types = cb_info[:param_types] || block_def.params.map { |p| param_type(p) }
          cb_ret_type = cb_info[:return_type] || :void

          all_captures = block_def.captures || []
          # Filter out shared mutable captures — they use static fields instead
          captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
          capture_types = captures.map { |c| @variable_types[c.name.to_s] || :value }
          block_method_name = compile_block_as_method_with_types(
            block_def, capture_types, cb_param_types, cb_ret_type,
            filtered_captures: captures
          )

          # Load capture variables onto the stack
          captures.each do |cap|
            cap_type = @variable_types[cap.name.to_s] || :value
            instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), cap_type))
          end

          # Build descriptors for invokedynamic
          capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
          indy_desc = "(#{capture_desc})L#{cb_interface};"
          block_params_desc = (capture_types + cb_param_types).map { |t| type_to_descriptor(t) }.join
          block_full_desc = "(#{block_params_desc})#{type_to_descriptor(cb_ret_type)}"
          call_desc = "(#{cb_param_types.map { |t| type_to_descriptor(t) }.join})#{type_to_descriptor(cb_ret_type)}"

          instructions << {
            "op" => "invokedynamic",
            "name" => "call",
            "descriptor" => indy_desc,
            "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
            "bootstrapName" => "metafactory",
            "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
            "bootstrapArgs" => [
              { "type" => "methodType", "descriptor" => call_desc },
              { "type" => "handle", "tag" => "H_INVOKESTATIC",
                "owner" => @current_enclosing_class,
                "name" => block_method_name,
                "descriptor" => block_full_desc },
              { "type" => "methodType", "descriptor" => call_desc }
            ]
          }

          cb_interface_desc = "L#{cb_interface};"
        end

        # Build descriptor (append callback interface param if block was compiled)
        params_desc = param_types.map { |t| jvm_interop_descriptor(t) }.join
        params_desc += cb_interface_desc if cb_interface_desc
        ret_desc = jvm_interop_descriptor(ret_type)
        descriptor = "(#{params_desc})#{ret_desc}"

        # invokestatic (use java_name for camelCase method name)
        instructions << { "op" => "invokestatic", "owner" => jvm_class,
                           "name" => java_method_name, "descriptor" => descriptor }

        # Handle return value
        if result_var && ret_type == :void
          @variable_types[result_var] = :void
        elsif result_var && ret_type != :void
          instructions.concat(jvm_interop_convert_return(ret_type))

          store_type = jvm_interop_store_type(ret_type)
          ensure_slot(result_var, store_type)
          instructions << store_instruction(result_var, store_type)
          @variable_types[result_var] = store_type
        end

        instructions
      end

      # JVM interop: type tag → Java descriptor (Integer → int for Java APIs)
      def jvm_interop_descriptor(type)
        case type
        when :i64 then "I"           # Java int (most Java APIs use int, not long)
        when :double then "D"
        when :string then "Ljava/lang/String;"
        when :i8 then "Z"            # Java boolean
        when :void then "V"
        when :value then "Ljava/lang/Object;"
        when String then "L#{type};" # Java class reference (e.g., "java/lang/StringBuilder")
        else "Ljava/lang/Object;"
        end
      end

      # JVM interop: load an argument with Java int conversion
      def load_jvm_interop_arg(arg, target_type)
        instructions = []

        case target_type
        when :i64
          # Load as long, then convert to Java int
          arg_var = extract_var_name(arg)
          arg_type = arg_var ? (@variable_types[arg_var] || :value) : (infer_type_from_hir(arg) || :value)
          if arg_type == :value
            # Object → unbox to long first
            instructions.concat(load_value(arg, :value))
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                               "name" => "longValue", "descriptor" => "()J" }
          else
            instructions.concat(load_value(arg, :i64))
          end
          instructions << { "op" => "l2i" }
        when :value
          # May need boxing if the arg is a primitive
          arg_var = extract_var_name(arg)
          arg_type = arg_var ? (@variable_types[arg_var] || :value) : (infer_type_from_hir(arg) || :value)

          if arg_type == :i64
            instructions.concat(load_value(arg, :i64))
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                               "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          elsif arg_type == :double
            instructions.concat(load_value(arg, :double))
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                               "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          else
            instructions.concat(load_value(arg, :value))
          end
        when :double
          arg_var2 = extract_var_name(arg)
          arg_type2 = arg_var2 ? (@variable_types[arg_var2] || :value) : (infer_type_from_hir(arg) || :value)
          if arg_type2 == :value
            instructions.concat(load_value(arg, :value))
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                               "name" => "doubleValue", "descriptor" => "()D" }
          else
            instructions.concat(load_value(arg, :double))
          end
        when :string
          arg_var3 = extract_var_name(arg)
          arg_type3 = arg_var3 ? (@variable_types[arg_var3] || :value) : (infer_type_from_hir(arg) || :value)
          if arg_type3 == :value
            instructions.concat(load_value(arg, :value))
            instructions << { "op" => "checkcast", "type" => "java/lang/String" }
          else
            instructions.concat(load_value(arg, :string))
          end
        else
          instructions.concat(load_value(arg, target_type))
        end

        instructions
      end

      # JVM interop: convert Java return value to Konpeito type
      def jvm_interop_convert_return(ret_type)
        case ret_type
        when :i64
          # Java int return → convert to Konpeito long
          [{ "op" => "i2l" }]
        else
          []
        end
      end

      # JVM interop: determine store type for return values
      def jvm_interop_store_type(ret_type)
        case ret_type
        when :i64 then :i64     # After i2l conversion, it's a long
        when :double then :double
        when :i8 then :i8
        else :value             # Object, String, or Java class reference
        end
      end

      # ========================================================================
      # Super Call
      # ========================================================================

      def generate_super_call(inst)
        return [] unless @generating_instance_method && @current_class_name

        parent_info = @class_info[@current_class_name]
        return [] unless parent_info

        parent_name = parent_info[:super_name]

        # In constructor (initialize), super() was already called in <init> prologue.
        # Skip the explicit super call to avoid calling <init> twice.
        if @current_method_name == "initialize"
          if inst.result_var
            ensure_slot(inst.result_var, :value)
            instructions = []
            instructions << { "op" => "aconst_null" }
            instructions << store_instruction(inst.result_var, :value)
            return instructions
          end
          return []
        end

        instructions = []

        # Load self
        instructions << { "op" => "aload", "var" => 0 }

        # Load arguments
        (inst.args || []).each do |arg|
          arg_var = extract_var_name(arg)
          arg_type = arg_var ? (@variable_types[arg_var] || :value) : :value
          instructions.concat(load_value(arg, arg_type))
        end

        # Find parent method to determine descriptor — prefer pre-registered descriptor
        # to ensure consistency with the actual method definition.
        parent_class_name = find_parent_class_name(@current_class_name)
        if parent_class_name
          pre_key = "#{parent_class_name}##{@current_method_name}"
          descriptor = @method_descriptors[pre_key]
          unless descriptor
            parent_func = find_class_instance_method(parent_class_name, @current_method_name)
            if parent_func
              params_desc = parent_func.params.map { |p| type_to_descriptor(param_type(p)) }.join
              rbs_ret = resolve_rbs_return_type(parent_class_name, @current_method_name, false)
              ret_type = if rbs_ret && rbs_ret != :value
                           rbs_ret
                         else
                           detected = function_return_type(parent_func)
                           # Ruby has no void methods — nil return is Object (null)
                           detected = :value if detected == :void
                           (detected == :void && rbs_ret == :value) ? :value : detected
                         end
              descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"
            end
          end
        end
        descriptor ||= "()Ljava/lang/Object;"

        instructions << { "op" => "invokespecial", "owner" => parent_name,
                           "name" => jvm_method_name(@current_method_name),
                           "descriptor" => descriptor }

        # Only store result if super method returns non-void
        ret_desc = descriptor.split(")").last
        if inst.result_var && ret_desc != "V"
          ensure_slot(inst.result_var, :value)
          instructions << store_instruction(inst.result_var, :value)
          @variable_types[inst.result_var] = :value
        end

        instructions
      end

      # ========================================================================
      # NativeClass Field Access (NativeFieldGet/NativeFieldSet)
      # ========================================================================

      def generate_native_field_get(inst)
        result_var = inst.result_var
        field_name = inst.field_name.to_s
        class_type = inst.class_type
        class_name = class_type.name.to_s

        # Determine field type: prefer @class_info (has JVM-specific types like :string)
        jvm_type = resolve_jvm_field_type(class_name, field_name)

        ensure_slot(result_var, jvm_type) if result_var

        instructions = []

        # Load receiver object
        if inst.object.is_a?(HIR::SelfRef)
          instructions << { "op" => "aload", "var" => 0 }
        else
          instructions.concat(load_value(inst.object, :value))
          # checkcast when receiver is typed as Object but field owner expects specific class.
          # Always emit when recv_type is :value — JVM verifier needs it even if compiler tracks the type.
          if @class_info.key?(class_name)
            recv_var = extract_var_name(inst.object)
            recv_type = recv_var ? (@variable_types[recv_var] || :value) : :value
            if recv_type == :value
              instructions << { "op" => "checkcast", "type" => user_class_jvm_name(class_name) }
            end
          end
        end

        # getfield - find owner class in hierarchy
        field_info = find_field_in_class_hierarchy(class_name, field_name)
        owner_jvm = field_info ? field_info[0] : user_class_jvm_name(class_name)
        instructions << {
          "op" => "getfield",
          "owner" => owner_jvm,
          "name" => sanitize_field_name(field_name),
          "descriptor" => type_to_descriptor(jvm_type)
        }

        if result_var
          instructions << store_instruction(result_var, jvm_type)
          @variable_types[result_var] = jvm_type
          # Detect collection type from the field's original RBS/HM type
          collection = resolve_field_collection_type(class_name, field_name)
          @variable_collection_types[result_var] = collection if collection
        end

        instructions
      end

      def generate_native_field_set(inst)
        field_name = inst.field_name.to_s
        class_type = inst.class_type
        class_name = class_type.name.to_s

        # Determine field type: prefer @class_info (has JVM-specific types like :string)
        jvm_type = resolve_jvm_field_type(class_name, field_name)

        instructions = []

        # Load receiver object
        if inst.object.is_a?(HIR::SelfRef)
          instructions << { "op" => "aload", "var" => 0 }
        else
          instructions.concat(load_value(inst.object, :value))
          # checkcast when receiver is typed as Object but field owner expects specific class.
          # Always emit when recv_type is :value — JVM verifier needs it even if compiler tracks the type.
          if @class_info.key?(class_name)
            recv_var = extract_var_name(inst.object)
            recv_type = recv_var ? (@variable_types[recv_var] || :value) : :value
            if recv_type == :value
              instructions << { "op" => "checkcast", "type" => user_class_jvm_name(class_name) }
            end
          end
        end

        # Load value
        instructions.concat(load_value(inst.value, jvm_type))

        # checkcast when loaded value is Object but field expects a user class
        val_var = extract_var_name(inst.value)
        val_actual = val_var ? (@variable_types[val_var] || :value) : (literal_type_tag(inst.value) || :value)
        jvm_type_s = jvm_type.to_s
        if val_actual == :value && jvm_type_s.start_with?("class:")
          target_class = jvm_type_s.sub("class:", "")
          instructions << { "op" => "checkcast", "type" => user_class_jvm_name(target_class) }
        end

        # putfield - find owner class in hierarchy
        field_info = find_field_in_class_hierarchy(class_name, field_name)
        owner_jvm = field_info ? field_info[0] : user_class_jvm_name(class_name)
        instructions << {
          "op" => "putfield",
          "owner" => owner_jvm,
          "name" => sanitize_field_name(field_name),
          "descriptor" => type_to_descriptor(jvm_type)
        }

        instructions
      end

      # ========================================================================
      # NativeClass Method Call (NativeMethodCall)
      # ========================================================================

      def generate_native_method_call(inst)
        result_var = inst.result_var
        receiver = inst.receiver
        method_name = inst.method_name.to_s
        args = inst.args || []
        method_sig = inst.method_sig
        owner_class = inst.owner_class || inst.class_type
        class_name = owner_class.name.to_s
        jvm_class = user_class_jvm_name(class_name)
        instructions = []

        # Check if this is a puts/print call (method on Kernel, not user class)
        if method_name == "puts" && !@class_info.key?(class_name)
          return generate_puts_call(args, result_var)
        end

        # Load receiver
        if receiver.is_a?(HIR::SelfRef)
          instructions << { "op" => "aload", "var" => 0 }
        else
          instructions.concat(load_value(receiver, :value))
          # checkcast when receiver is typed as Object but method owner expects specific class.
          # Always emit checkcast when recv_type is :value — even if @variable_class_types
          # tracks the type, the JVM verifier only sees the declared parameter type (Object).
          if @class_info.key?(class_name)
            recv_var = extract_var_name(receiver)
            recv_type = recv_var ? (@variable_types[recv_var] || :value) : :value
            if recv_type == :value
              instructions << { "op" => "checkcast", "type" => jvm_class }
            end
          end
        end

        # Build descriptor FIRST — prefer registered descriptor (from actual method generation)
        # over RBS-derived descriptor, because RBS may declare void but actual method returns Object.
        # Walk the class hierarchy to find the registered descriptor.
        registered = @method_descriptors["#{class_name}##{method_name}"]
        unless registered
          parent = @class_info[class_name]&.dig(:super_name)
          while parent && !registered
            parent_name = parent.split("/").last
            registered = @method_descriptors["#{parent_name}##{method_name}"]
            parent = @class_info[parent_name]&.dig(:super_name)
          end
        end
        if registered
          descriptor = registered
          ret_type = parse_descriptor_return_type(registered)
        else
          descriptor = build_native_method_descriptor(method_sig)
          ret_type = native_sig_type_to_jvm(method_sig&.return_type || :Void)
        end

        # Parse registered descriptor param types for accurate argument loading
        registered_param_types = registered ? parse_descriptor_param_types(registered) : nil

        # Load arguments using registered descriptor param types (preferred) or method signature types
        if method_sig && method_sig.param_types
          method_sig.param_types.each_with_index do |ptype, i|
            if i < args.size
              # Use registered param type if available (has class-specific types like :class:MouseEvent)
              jvm_ptype = (registered_param_types && i < registered_param_types.size) ? registered_param_types[i] : native_sig_type_to_jvm(ptype)
              instructions.concat(load_value(args[i], jvm_ptype))
              # Unbox/checkcast Object→primitive or Object→class if variable holds Object
              arg_var = extract_var_name(args[i])
              arg_actual = arg_var ? (@variable_types[arg_var] || :value) : (literal_type_tag(args[i]) || jvm_ptype)
              instructions.concat(unbox_if_needed(arg_actual, jvm_ptype))
            end
          end
        else
          args.each_with_index do |arg, i|
            arg_var = extract_var_name(arg)
            arg_type = arg_var ? (@variable_types[arg_var] || :value) : :value
            jvm_ptype = (registered_param_types && i < registered_param_types.size) ? registered_param_types[i] : arg_type
            instructions.concat(load_value(arg, arg_type))
            instructions.concat(unbox_if_needed(arg_type, jvm_ptype))
          end
        end

        # invokevirtual
        instructions << { "op" => "invokevirtual", "owner" => jvm_class,
                           "name" => jvm_method_name(method_name),
                           "descriptor" => descriptor }

        # Store result
        if result_var && ret_type != :void
          # checkcast when return type is a user class (descriptor returns Object but actual type is specific)
          if ret_type == :value && method_sig&.return_type
            ret_class = method_sig.return_type.to_s
            # Handle :Self return type
            ret_class = class_name if ret_class == "Self"
            if @class_info.key?(ret_class)
              instructions << { "op" => "checkcast", "type" => @class_info[ret_class][:jvm_name] }
              @variable_class_types[result_var] = ret_class
            end
          end

          ensure_slot(result_var, ret_type)
          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        elsif result_var && ret_type == :void
          # Void method but result_var expected - store null
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end

        instructions
      end

      def native_type_tag_to_jvm(tag)
        case tag
        when :i64 then :i64
        when :double then :double
        when :i8 then :i8
        else :value
        end
      end

      def native_sig_type_to_jvm(sig_type)
        case sig_type
        when :Int64 then :i64
        when :Float64 then :double
        when :Bool then :i8
        when :Void then :void
        when :String then :string
        else :value
        end
      end

      def build_native_method_descriptor(method_sig)
        return "()Ljava/lang/Object;" unless method_sig

        params_desc = method_sig.param_types.map { |pt| type_to_descriptor(native_sig_type_to_jvm(pt)) }.join
        ret_desc = type_to_descriptor(native_sig_type_to_jvm(method_sig.return_type))
        "(#{params_desc})#{ret_desc}"
      end

      # ========================================================================
      # Block / Closure Support
      # ========================================================================

      # Generate a Yield instruction: invoke the block's call method
      def generate_yield(inst)
        return [] unless @block_param_slot

        result_var = inst.result_var
        instructions = []

        # Use the current function's declared KBlock interface (set in generate_function)
        kblock_iface = @current_kblock_iface
        unless kblock_iface
          # Fallback: determine from yield args
          arg_types = inst.args.map { |a|
            v = extract_var_name(a)
            v ? (@variable_types[v] || infer_type_from_hir(a) || :value) : (infer_type_from_hir(a) || :value)
          }
          ret_type = result_var ? (@current_function_return_type || :value) : :void
          kblock_iface = get_or_create_kblock(arg_types, ret_type)
        end

        # Parse the KBlock's call method descriptor to get expected types
        kblock_info = @kblock_interfaces[kblock_iface]
        call_desc = kblock_info["methods"].first["descriptor"]
        arg_types = parse_kblock_param_types(call_desc)
        ret_type = parse_kblock_return_type(call_desc)

        # Load block reference
        instructions << { "op" => "aload", "var" => @block_param_slot }

        # Load yield arguments (match KBlock's expected types)
        inst.args.each_with_index do |arg, i|
          expected_type = i < arg_types.size ? arg_types[i] : :value
          instructions.concat(load_value(arg, expected_type))
        end

        # invokeinterface KBlock.call(args)
        instructions << { "op" => "invokeinterface",
                          "owner" => kblock_iface,
                          "name" => "call",
                          "descriptor" => call_desc }

        # Store result
        if result_var && ret_type != :void
          ensure_slot(result_var, ret_type)
          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        end

        instructions
      end

      # Fallback for .call() on stored blocks without tracked KBlock interface
      # Uses get_or_create_kblock to ensure the interface exists and matches
      def generate_generic_block_call(recv_var, args, result_var)
        instructions = []

        # Determine the KBlock interface based on argument count (all Object types)
        arity = args.size
        arg_types = Array.new(arity, :value)
        ret_type = :value
        kblock_iface = get_or_create_kblock(arg_types, ret_type)

        # Build the call descriptor: all args are Object, returns Object
        call_desc = kblock_call_descriptor(arg_types, ret_type)

        # Load the block reference
        instructions << load_instruction(recv_var, :value)
        # Cast to KBlock interface
        instructions << { "op" => "checkcast", "type" => kblock_iface }

        # Load arguments (box primitives to Object)
        args.each do |arg|
          arg_var = extract_var_name(arg)
          arg_type = arg_var ? (@variable_types[arg_var] || :value) : (literal_type_tag(arg) || :value)
          instructions.concat(load_value(arg, arg_type))
          if arg_type == :i64
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                              "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          elsif arg_type == :double
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          elsif arg_type == :i8
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                              "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
          end
        end

        # invokeinterface call
        instructions << { "op" => "invokeinterface",
                          "owner" => kblock_iface,
                          "name" => "call",
                          "descriptor" => call_desc }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end

        instructions
      end

      # Generate block_given? → null check on __block__ parameter
      def generate_block_given(result_var)
        instructions = []
        ensure_slot(result_var, :i8) if result_var

        if @block_param_slot
          true_label = new_label("bg_true")
          end_label = new_label("bg_end")

          instructions << { "op" => "aload", "var" => @block_param_slot }
          instructions << { "op" => "ifnonnull", "target" => true_label }

          # Block is null → false
          instructions << { "op" => "iconst", "value" => 0 }
          instructions << { "op" => "goto", "target" => end_label }

          # Block is non-null → true
          instructions << { "op" => "label", "name" => true_label }
          instructions << { "op" => "iconst", "value" => 1 }

          instructions << { "op" => "label", "name" => end_label }
        else
          # Not in a yield function → always false
          instructions << { "op" => "iconst", "value" => 0 }
        end

        if result_var
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end

        instructions
      end

      # Generate a call on a KBlock variable (lambda/proc .call())
      def generate_kblock_call(recv_var, args, result_var)
        kblock_iface = @variable_kblock_iface[recv_var]
        kblock_info = @kblock_interfaces[kblock_iface]
        call_desc = kblock_info["methods"].first["descriptor"]
        arg_types = parse_kblock_param_types(call_desc)
        ret_type = parse_kblock_return_type(call_desc)

        instructions = []

        # Load KBlock reference
        instructions << load_instruction(recv_var, :value)
        # Cast to the specific KBlock interface
        instructions << { "op" => "checkcast", "type" => kblock_iface }

        # Load arguments (match KBlock's expected types, with boxing/unboxing)
        args.each_with_index do |arg, i|
          expected_type = i < arg_types.size ? arg_types[i] : :value
          actual_type = literal_type_tag(arg) || (extract_var_name(arg) ? (@variable_types[extract_var_name(arg)] || :value) : :value)
          instructions.concat(load_value(arg, actual_type))
          # Box primitives if KBlock expects Object
          if expected_type == :value && actual_type == :i64
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                              "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          elsif expected_type == :value && actual_type == :double
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          # Unbox Object if KBlock expects primitive
          elsif expected_type == :i64 && actual_type == :value
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "longValue", "descriptor" => "()J" }
          elsif expected_type == :double && actual_type == :value
            instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
            instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                              "name" => "doubleValue", "descriptor" => "()D" }
          end
        end

        # invokeinterface call
        instructions << { "op" => "invokeinterface",
                          "owner" => kblock_iface,
                          "name" => "call",
                          "descriptor" => call_desc }

        if result_var
          if ret_type == :void
            ensure_slot(result_var, :value)
            instructions << { "op" => "aconst_null" }
            instructions << store_instruction(result_var, :value)
            @variable_types[result_var] = :value
          else
            ensure_slot(result_var, ret_type)
            instructions << store_instruction(result_var, ret_type)
            @variable_types[result_var] = ret_type
          end
        end

        instructions
      end

      # Generate a ProcNew: compile block as static method + invokedynamic
      def generate_proc_new(inst)
        result_var = inst.result_var
        block_def = inst.block_def
        return [] unless result_var && block_def

        instructions = []

        # Determine block param types and return type
        block_param_types = block_def.params.map { |p| param_type(p) }
        block_ret_type = infer_block_return_type(block_def) || :value

        # Get or create KBlock interface
        kblock_iface = get_or_create_kblock(block_param_types, block_ret_type)

        # Compile block as static method
        all_captures = block_def.captures || []
        # Filter out shared mutable captures — they use static fields instead
        captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
        capture_types = captures.map { |c|
          @variable_types[c.name.to_s] || :value
        }
        block_method_name = compile_block_as_method_with_types(
          block_def, capture_types, block_param_types, block_ret_type,
          filtered_captures: captures
        )

        # Build invokedynamic to create KBlock instance
        # Capture variables become the invokedynamic site's arguments
        capture_types.each_with_index do |ct, i|
          instructions.concat(load_value(HIR::LocalVar.new(name: captures[i].name), ct))
        end

        capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        indy_desc = "(#{capture_desc})L#{kblock_iface};"

        # The static method's full descriptor: captures + block params -> return
        block_method_params_desc = (capture_types + block_param_types).map { |t| type_to_descriptor(t) }.join
        block_method_full_desc = "(#{block_method_params_desc})#{type_to_descriptor(block_ret_type)}"

        # The interface's call method descriptor
        call_desc = kblock_call_descriptor(block_param_types, block_ret_type)

        instructions << {
          "op" => "invokedynamic",
          "name" => "call",
          "descriptor" => indy_desc,
          "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
          "bootstrapName" => "metafactory",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => [
            { "type" => "methodType", "descriptor" => call_desc },
            { "type" => "handle", "tag" => "H_INVOKESTATIC",
              "owner" => @current_enclosing_class,
              "name" => block_method_name,
              "descriptor" => block_method_full_desc },
            { "type" => "methodType", "descriptor" => call_desc }
          ]
        }

        ensure_slot(result_var, :value)
        instructions << store_instruction(result_var, :value)
        @variable_types[result_var] = :value

        # Track that this variable holds a specific KBlock type
        @variable_kblock_iface[result_var] = kblock_iface
        instructions
      end

      # Check if a block body accesses instance variables or calls methods on
      # implicit self (receiver-less calls like `kpi_card(label, value)`).
      # Recursively checks nested blocks (e.g., on_click inside a yield block)
      # so that outer blocks capture self when inner blocks need it.
      def block_needs_self?(block_def)
        block_def.body.any? do |bb|
          bb.instructions.any? { |inst|
            if inst.is_a?(HIR::LoadInstanceVar) || inst.is_a?(HIR::StoreInstanceVar)
              true
            elsif inst.is_a?(HIR::Call) && (inst.receiver.nil? || inst.receiver.is_a?(HIR::SelfRef))
              true
            elsif inst.is_a?(HIR::Call) && inst.block
              block_needs_self?(inst.block)
            else
              false
            end
          }
        end
      end

      # Check if a block (or any nested block within it) contains Yield instructions
      def block_contains_yield?(block_def)
        block_def.body.any? do |bb|
          bb.instructions.any? { |inst|
            if inst.is_a?(HIR::Yield)
              true
            elsif inst.is_a?(HIR::Call) && inst.block
              block_contains_yield?(inst.block)
            else
              false
            end
          }
        end
      end

      # Compile a block argument for an instance method call that accepts &block.
      # Returns instructions that leave a KBlock object on the stack.
      def compile_block_arg_for_instance_call(block_def)
        instructions = []

        # Determine block param types and return type
        block_param_types = block_def.params.map { |p| param_type(p) }
        block_ret_type = infer_block_return_type(block_def) || :value

        # Get or create KBlock interface
        kblock_iface = get_or_create_kblock(block_param_types, block_ret_type)

        # Compile block as static method
        all_captures = block_def.captures || []
        captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
        capture_types = captures.map { |c| @variable_types[c.name.to_s] || :value }

        # If inside instance method and block accesses instance vars, add self as implicit capture
        needs_self = @generating_instance_method && block_needs_self?(block_def)
        if needs_self
          self_capture = HIR::Capture.new(name: "__block_self__", type: TypeChecker::Types::UNTYPED)
          captures = [self_capture] + captures
          capture_types = [:value] + capture_types
        end

        # If block contains yield and outer function has a __block__ param, capture it
        if @block_param_slot && block_contains_yield?(block_def)
          block_capture = HIR::Capture.new(name: "__block__", type: TypeChecker::Types::UNTYPED)
          captures = captures + [block_capture]
          capture_types = capture_types + [:value]
        end

        block_method_name = compile_block_as_method_with_types(
          block_def, capture_types, block_param_types, block_ret_type,
          filtered_captures: captures, self_capture: needs_self
        )

        # Load capture variables for invokedynamic
        captures.each_with_index do |cap, i|
          if cap.name.to_s == "__block_self__"
            # Load self — use @block_self_slot for nested block contexts
            self_slot = @block_self_slot || 0
            instructions << { "op" => "aload", "var" => self_slot }
          else
            ct = capture_types[i]
            instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), ct))
          end
        end

        # Generate invokedynamic to create KBlock
        capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        indy_desc = "(#{capture_desc})L#{kblock_iface};"
        block_method_params_desc = (capture_types + block_param_types).map { |t| type_to_descriptor(t) }.join
        block_method_full_desc = "(#{block_method_params_desc})#{type_to_descriptor(block_ret_type)}"
        call_desc = kblock_call_descriptor(block_param_types, block_ret_type)

        instructions << {
          "op" => "invokedynamic",
          "name" => "call",
          "descriptor" => indy_desc,
          "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
          "bootstrapName" => "metafactory",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => [
            { "type" => "methodType", "descriptor" => call_desc },
            { "type" => "handle", "tag" => "H_INVOKESTATIC",
              "owner" => @current_enclosing_class,
              "name" => block_method_name,
              "descriptor" => block_method_full_desc },
            { "type" => "methodType", "descriptor" => call_desc }
          ]
        }

        instructions
      end

      # Generate a ProcCall: invokeinterface on the KBlock object
      def generate_proc_call(inst)
        result_var = inst.result_var
        proc_value = inst.proc_value
        args = inst.args || []

        instructions = []

        # Determine arg types
        arg_types = args.map { |a|
          v = extract_var_name(a)
          v ? (@variable_types[v] || infer_type_from_hir(a) || :value) : (infer_type_from_hir(a) || :value)
        }
        ret_type = result_var ? :i64 : :void  # Default to i64 for now; refine later

        # Try to infer return type from HIR
        if inst.respond_to?(:type) && inst.type
          inferred = konpeito_type_to_tag(inst.type)
          ret_type = inferred if inferred != :value || ret_type == :void
        end

        kblock_iface = get_or_create_kblock(arg_types, ret_type)

        # Load proc object
        instructions.concat(load_value(proc_value, :value))
        # Cast to the specific KBlock interface
        instructions << { "op" => "checkcast", "type" => kblock_iface }

        # Load arguments
        args.each_with_index do |arg, i|
          instructions.concat(load_value(arg, arg_types[i]))
        end

        # invokeinterface call
        call_desc = kblock_call_descriptor(arg_types, ret_type)
        instructions << { "op" => "invokeinterface",
                          "owner" => kblock_iface,
                          "name" => "call",
                          "descriptor" => call_desc }

        if result_var && ret_type != :void
          ensure_slot(result_var, ret_type)
          instructions << store_instruction(result_var, ret_type)
          @variable_types[result_var] = ret_type
        end

        instructions
      end

      # Compile a BlockDef as a private static method and add to @block_methods
      def compile_block_as_method(block_def, capture_types)
        block_param_types = block_def.params.map { |p| param_type(p) }
        block_ret_type = infer_block_return_type(block_def) || :value
        compile_block_as_method_with_types(block_def, capture_types, block_param_types, block_ret_type)
      end

      # Compile a BlockDef as a private static method with explicit param/return types
      # filtered_captures: if provided, only these captures become method parameters
      #   (shared mutable captures are excluded — they use static fields)
      def compile_block_as_method_with_types(block_def, capture_types, block_param_types, block_ret_type, filtered_captures: nil, self_capture: false)
        @block_counter += 1
        method_name = "lambda$block$#{@block_counter}"

        # Use filtered captures if provided (excludes shared mutable captures)
        captures = filtered_captures || (block_def.captures || [])
        block_params = block_def.params || []

        # Save and reset function state
        saved_state = save_function_state
        @variable_slots = {}
        @variable_types = {}
        @variable_class_types = {}
        @variable_is_class_ref = {}
        @next_slot = 0
        @label_counter = 0
        @block_phi_nodes = {}
        @block_param_slot = nil
        @pending_exception_table = []

        # Allocate slots: captures first, then block params (using explicit types)
        # Note: shared mutable captures are NOT allocated slots — they use getstatic/putstatic
        @block_self_slot = nil
        captures.each_with_index do |cap, i|
          ct = capture_types[i]
          allocate_slot(cap.name.to_s, ct)
          # Track self-capture slot for instance var access within blocks
          if self_capture && cap.name.to_s == "__block_self__"
            @block_self_slot = @variable_slots["__block_self__"]
          end
          # Track __block__ capture slot so yield works inside block bodies
          if cap.name.to_s == "__block__"
            @block_param_slot = @variable_slots["__block__"]
          end
          # Propagate class types from outer scope for captured variables
          outer_class = saved_state[:variable_class_types][cap.name.to_s]
          @variable_class_types[cap.name.to_s] = outer_class if outer_class

          # Fallback: extract class from capture's HIR type (TypeResolver may have resolved TypeVars)
          unless @variable_class_types[cap.name.to_s]
            cap_type = cap.type
            cap_type = cap_type.prune if cap_type.respond_to?(:prune)
            if cap_type.is_a?(TypeChecker::Types::ClassInstance)
              cls_name = cap_type.name.to_s
              @variable_class_types[cap.name.to_s] = cls_name if @class_info.key?(cls_name)
            end
          end
        end

        block_params.each_with_index do |param, i|
          pt = i < block_param_types.size ? block_param_types[i] : param_type(param)
          allocate_slot(param.name.to_s, pt)
        end

        # Pre-scan phi nodes in block body
        block_def.body.each do |bb|
          phis = bb.instructions.select { |inst| inst.is_a?(HIR::Phi) }
          unless phis.empty?
            @block_phi_nodes[bb.label.to_s] = phis
            phis.each do |phi|
              type = infer_phi_type(phi)
              ensure_slot(phi.result_var, type)
              @variable_types[phi.result_var] = type
            end
          end
        end

        # Record which slots are parameters (captures + block params — should not be pre-initialized)
        param_slots = Set.new
        @variable_slots.each { |_name, slot| param_slots << slot }

        # Generate block body instructions
        body_instructions = []
        last_result_var = nil
        ordered_body = reorder_blocks_for_jvm(block_def.body)
        ordered_body.each do |bb|
          @current_block_label = bb.label.to_s
          body_instructions.concat(generate_basic_block(bb))
          # Track the last instruction's result_var for implicit return
          bb.instructions.reverse_each do |bi|
            if bi.respond_to?(:result_var) && bi.result_var
              last_result_var = bi.result_var
              break
            end
          end
        end

        # Pre-initialize ALL non-parameter local variable slots with default values.
        # JVM verifier requires all locals to be definitely assigned on ALL
        # control flow paths that reach a read. Without this, slots allocated
        # during body generation (KBlock temps, intermediate results, etc.)
        # may not exist in the JVM frame, causing VerifyError.
        instructions = []
        @variable_slots.each do |name, slot|
          next if param_slots.include?(slot)
          type = @variable_types[name] || :value
          case type
          when :i64
            instructions << { "op" => "lconst_0" }
            instructions << { "op" => "lstore", "var" => slot }
          when :double
            instructions << { "op" => "dconst_0" }
            instructions << { "op" => "dstore", "var" => slot }
          when :i8
            instructions << { "op" => "iconst", "value" => 0 }
            instructions << { "op" => "istore", "var" => slot }
          else
            instructions << { "op" => "aconst_null" }
            instructions << { "op" => "astore", "var" => slot }
          end
        end
        instructions.concat(body_instructions)

        # Use the explicit return type (from callee's yield or caller's inference)
        ret_type = block_ret_type

        # Fix up return instructions to match the declared return type
        instructions = fix_block_returns(instructions, ret_type)

        unless instructions.last && return_instruction?(instructions.last)
          if ret_type == :void
            # Void callback: just return, don't try to load a result value
            instructions << { "op" => "return" }
          elsif last_result_var && @variable_types[last_result_var] &&
                @variable_types[last_result_var] != :void
            # Block has no explicit return — generate implicit return of last expression
            result_type = @variable_types[last_result_var]
            instructions.concat(load_value(HIR::LocalVar.new(name: last_result_var), result_type))
            # Box if needed to match return type
            if ret_type == :value && result_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif ret_type == :value && result_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            elsif ret_type == :value && result_type == :i8
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                                "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
            end
            instructions << case (ret_type == :value ? :value : result_type)
                            when :i64 then { "op" => "lreturn" }
                            when :double then { "op" => "dreturn" }
                            when :i8 then { "op" => "ireturn" }
                            else { "op" => "areturn" }
                            end
          else
            # No result — return default
            case ret_type
            when :i64
              instructions << { "op" => "lconst_0" }
              instructions << { "op" => "lreturn" }
            when :double
              instructions << { "op" => "dconst_0" }
              instructions << { "op" => "dreturn" }
            when :i8
              instructions << { "op" => "iconst", "value" => 0 }
              instructions << { "op" => "ireturn" }
            else
              instructions << { "op" => "aconst_null" }
              instructions << { "op" => "areturn" }
            end
          end
        end

        # Build descriptor
        all_param_types = capture_types + block_param_types
        params_desc = all_param_types.map { |t| type_to_descriptor(t) }.join
        descriptor = "(#{params_desc})#{type_to_descriptor(ret_type)}"

        block_method = {
          "name" => method_name,
          "descriptor" => descriptor,
          "access" => ["private", "static", "synthetic"],
          "instructions" => instructions
        }
        # Attach exception table if the block body generated try/catch entries
        block_method["exceptionTable"] = @pending_exception_table unless @pending_exception_table.empty?
        @block_methods << block_method

        # Restore function state (including pending_exception_table)
        restore_function_state(saved_state)

        method_name
      end

      # Fix block return instructions: ensure they match the declared return type
      def fix_block_returns(instructions, ret_type)
        instructions.map do |inst|
          if inst["op"] == "return" && ret_type != :void
            # Void return in a non-void method: push null and areturn
            [{ "op" => "aconst_null" }, { "op" => "areturn" }]
          else
            [inst]
          end
        end.flatten
      end

      def save_function_state
        {
          variable_slots: @variable_slots.dup,
          variable_types: @variable_types.dup,
          variable_class_types: @variable_class_types.dup,
          variable_is_class_ref: @variable_is_class_ref.dup,
          next_slot: @next_slot,
          label_counter: @label_counter,
          block_phi_nodes: @block_phi_nodes.dup,
          current_block_label: @current_block_label,
          block_param_slot: @block_param_slot,
          current_kblock_iface: @current_kblock_iface,
          block_self_slot: @block_self_slot,
          pending_exception_table: @pending_exception_table.dup
        }
      end

      def restore_function_state(state)
        @variable_slots = state[:variable_slots]
        @variable_types = state[:variable_types]
        @variable_class_types = state[:variable_class_types]
        @variable_is_class_ref = state[:variable_is_class_ref]
        @next_slot = state[:next_slot]
        @label_counter = state[:label_counter]
        @block_phi_nodes = state[:block_phi_nodes]
        @current_block_label = state[:current_block_label]
        @block_param_slot = state[:block_param_slot]
        @current_kblock_iface = state[:current_kblock_iface]
        @block_self_slot = state[:block_self_slot]
        @pending_exception_table = state[:pending_exception_table]
      end

      # Get or create a typed KBlock interface for the given signature
      def get_or_create_kblock(arg_types, ret_type)
        key = "#{arg_types.map { |t| type_to_kblock_tag(t) }.join("_")}_ret_#{type_to_kblock_tag(ret_type)}"

        return @kblock_registry[key] if @kblock_registry[key]

        iface_name = "#{JAVA_PACKAGE}/KBlock_#{key}"
        call_desc = kblock_call_descriptor(arg_types, ret_type)

        iface_def = {
          "name" => iface_name,
          "access" => ["public", "interface", "abstract"],
          "superName" => "java/lang/Object",
          "interfaces" => [],
          "fields" => [],
          "methods" => [{
            "name" => "call",
            "descriptor" => call_desc,
            "access" => ["public", "abstract"]
          }]
        }

        @kblock_registry[key] = iface_name
        @kblock_interfaces[iface_name] = iface_def
        iface_name
      end

      def kblock_call_descriptor(arg_types, ret_type)
        params_desc = arg_types.map { |t| type_to_descriptor(t) }.join
        "(#{params_desc})#{type_to_descriptor(ret_type)}"
      end

      # Parse param types from a JVM method descriptor like "(JLjava/lang/String;)Ljava/lang/Object;"
      def parse_kblock_param_types(descriptor)
        return [] unless descriptor =~ /\A\(([^)]*)\)/
        params_str = $1
        types = []
        i = 0
        while i < params_str.length
          case params_str[i]
          when "J" then types << :i64; i += 1
          when "D" then types << :double; i += 1
          when "Z" then types << :i8; i += 1
          when "L"
            # Object type: consume until ";"
            semi = params_str.index(";", i)
            obj_type = params_str[(i + 1)...semi]
            types << (obj_type == "java/lang/String" ? :string : :value)
            i = semi + 1
          else
            types << :value; i += 1
          end
        end
        types
      end

      # Parse return type from a JVM method descriptor
      # Parse the return type tag from a JVM method descriptor like "(Ljava/lang/String;)Ljava/lang/Object;"
      def parse_descriptor_return_type(descriptor)
        parse_kblock_return_type(descriptor)
      end

      # Parse parameter types from a JVM descriptor like "(JLjava/lang/Object;D)V"
      def parse_descriptor_param_types(descriptor)
        return [] unless descriptor =~ /\(([^)]*)\)/
        params_str = $1
        types = []
        i = 0
        while i < params_str.length
          case params_str[i]
          when "J"
            types << :i64
            i += 1
          when "D"
            types << :double
            i += 1
          when "Z"
            types << :i8
            i += 1
          when "I"
            types << :i64  # treat int as long for simplicity
            i += 1
          when "L"
            # Object type: read until ";"
            semi = params_str.index(";", i)
            class_name = params_str[(i + 1)...semi]
            types << descriptor_class_to_tag(class_name)
            i = semi + 1
          when "["
            types << :value  # arrays as Object
            i += 1
            # Skip the array element type
            if params_str[i] == "L"
              semi = params_str.index(";", i)
              i = semi + 1
            else
              i += 1
            end
          else
            types << :value
            i += 1
          end
        end
        types
      end

      def parse_kblock_return_type(descriptor)
        return :void unless descriptor =~ /\)(.+)\z/
        ret_str = $1
        case ret_str
        when "J" then :i64
        when "D" then :double
        when "Z" then :i8
        when "V" then :void
        else
          if ret_str =~ /\AL([^;]+);\z/
            descriptor_class_to_tag($1)
          else
            :value
          end
        end
      end

      # Convert a JVM internal class name to a type tag
      def descriptor_class_to_tag(class_name)
        case class_name
        when "java/lang/String" then :string
        when "konpeito/runtime/KArray" then :array
        when "konpeito/runtime/KHash" then :hash
        else
          if class_name.start_with?("konpeito/generated/")
            short = class_name.sub("konpeito/generated/", "")
            (@class_info && @class_info.key?(short)) ? :"class:#{short}" : :value
          else
            :value
          end
        end
      end

      def type_to_kblock_tag(type)
        case type
        when :i64 then "J"
        when :double then "D"
        when :i8 then "Z"
        when :string then "Str"
        when :void then "V"
        when :value then "Obj"
        else "Obj"
        end
      end

      # Determine the KBlock interface for a yield-containing function
      def yield_function_kblock_interface(func)
        # Find yield instructions to determine block signature
        yield_inst = nil
        func.body.each do |bb|
          bb.instructions.each do |inst|
            if inst.is_a?(HIR::Yield)
              yield_inst = inst
              break
            end
          end
          break if yield_inst
        end

        return get_or_create_kblock([], :value) unless yield_inst

        # Build a map of function parameter names to their resolved types
        param_type_map = {}
        func.params.each do |p|
          param_type_map[p.name.to_s] = param_type(p)
        end

        arg_types = yield_inst.args.map { |a|
          # If yield arg is a local variable that matches a function parameter,
          # use the parameter's resolved type
          var_name = extract_var_name_from_hir(a)
          if var_name && param_type_map.key?(var_name)
            param_type_map[var_name]
          elsif a.respond_to?(:type) && a.type
            t = konpeito_type_to_tag(a.type)
            t == :value ? (infer_type_from_hir(a) || :value) : t
          else
            infer_type_from_hir(a) || :value
          end
        }

        # Determine return type: use the yield instruction's type (what the block returns),
        # NOT the function's own return type (which is what the function returns after the yield).
        # Default to :value (Object) for safety — blocks may return different types.
        ret_type = if yield_inst.respond_to?(:type) && yield_inst.type
                     t = konpeito_type_to_tag(yield_inst.type)
                     t == :value ? :value : t
                   else
                     :value
                   end

        get_or_create_kblock(arg_types, ret_type)
      end

      # Extract variable name from an HIR node (LoadLocal, LocalVar, etc.)
      def extract_var_name_from_hir(node)
        case node
        when HIR::LoadLocal
          node.var.respond_to?(:name) ? node.var.name.to_s : nil
        when HIR::LocalVar
          node.name.to_s
        else
          nil
        end
      end

      # Build method descriptor with KBlock parameter for yield-containing functions
      def method_descriptor_with_block(func, kblock_iface)
        params_desc = func.params.map { |p|
          t = param_type(p)
          t = :value if t == :void  # Nil/void is not valid as JVM param type
          type_to_descriptor(t)
        }.join
        params_desc += "L#{kblock_iface};"
        ret_type = function_return_type(func)
        "(#{params_desc})#{type_to_descriptor(ret_type)}"
      end

      # Infer block return type from its body
      def infer_block_return_type(block_def)
        block_def.body.each do |bb|
          if bb.terminator.is_a?(HIR::Return) && bb.terminator.value
            val = bb.terminator.value
            if val.respond_to?(:type) && val.type
              t = konpeito_type_to_tag(val.type)
              return t unless t == :value
            end
          end
        end
        nil
      end

      # Handle call with block: compile block + invokedynamic + pass to callee
      def generate_call_with_block(inst, method_name, args, block_def, result_var)
        instructions = []

        # Check for monomorphized target (e.g., apply → apply_Integer)
        actual_target = inst.instance_variable_get(:@specialized_target) || method_name
        # Prefer top-level functions (owner_class nil) over class instance methods
        target_func = @hir_program.functions.find { |f| f.name == actual_target && f.owner_class.nil? } ||
                      @hir_program.functions.find { |f| f.name == method_name && f.owner_class.nil? } ||
                      @hir_program.functions.find { |f| f.name == actual_target } ||
                      @hir_program.functions.find { |f| f.name == method_name }
        return [] unless target_func

        # Use the callee's yield-derived KBlock interface (canonical type)
        kblock_iface = yield_function_kblock_interface(target_func)

        # Parse the call descriptor to get the block param types from the KBlock interface
        kblock_info = @kblock_interfaces[kblock_iface]
        kblock_call_desc = kblock_info["methods"].first["descriptor"]
        block_param_types = parse_kblock_param_types(kblock_call_desc)
        block_ret_type = parse_kblock_return_type(kblock_call_desc)

        # Compile block body as static method (using the yield-derived param types)
        all_captures = block_def.captures || []
        # Filter out shared mutable captures — they use static fields instead
        captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
        capture_types = captures.map { |c|
          @variable_types[c.name.to_s] || :value
        }

        # If inside instance method and block (or nested blocks) access instance vars, add self as implicit capture
        needs_self = @generating_instance_method && block_needs_self?(block_def)
        if needs_self
          self_capture = HIR::Capture.new(name: "__block_self__", type: TypeChecker::Types::UNTYPED)
          captures = [self_capture] + captures
          capture_types = [:value] + capture_types
        end

        # If block contains yield and outer function has a __block__ param, capture it
        if @block_param_slot && block_contains_yield?(block_def)
          block_capture = HIR::Capture.new(name: "__block__", type: TypeChecker::Types::UNTYPED)
          captures = captures + [block_capture]
          capture_types = capture_types + [:value]
        end

        block_method_name = compile_block_as_method_with_types(
          block_def, capture_types, block_param_types, block_ret_type,
          filtered_captures: captures, self_capture: needs_self
        )

        # Load capture variables for invokedynamic
        captures.each_with_index do |cap, i|
          if cap.name.to_s == "__block_self__"
            # Load self — use @block_self_slot for nested block contexts,
            # or slot 0 (this/self) when in the enclosing instance method
            self_slot = @block_self_slot || 0
            instructions << { "op" => "aload", "var" => self_slot }
          else
            ct = capture_types[i]
            instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), ct))
          end
        end

        # Generate invokedynamic to create KBlock
        capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        indy_desc = "(#{capture_desc})L#{kblock_iface};"

        block_method_params_desc = (capture_types + block_param_types).map { |t| type_to_descriptor(t) }.join
        block_method_full_desc = "(#{block_method_params_desc})#{type_to_descriptor(block_ret_type)}"
        call_desc = kblock_call_descriptor(block_param_types, block_ret_type)

        instructions << {
          "op" => "invokedynamic",
          "name" => "call",
          "descriptor" => indy_desc,
          "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
          "bootstrapName" => "metafactory",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => [
            { "type" => "methodType", "descriptor" => call_desc },
            { "type" => "handle", "tag" => "H_INVOKESTATIC",
              "owner" => @current_enclosing_class,
              "name" => block_method_name,
              "descriptor" => block_method_full_desc },
            { "type" => "methodType", "descriptor" => call_desc }
          ]
        }

        # Store KBlock in a temp variable
        kblock_var = "__kblock_temp_#{@block_counter}"
        ensure_slot(kblock_var, :value)
        instructions << store_instruction(kblock_var, :value)
        @variable_types[kblock_var] = :value

        # Load regular arguments (using the target function's param types)
        target_func.params.each_with_index do |param, i|
          if param.keyword_rest
            # Keyword rest parameter (**kwargs): build a KHash from keyword_args
            if inst.respond_to?(:keyword_args) && inst.has_keyword_args?
              instructions.concat(build_kwargs_hash(inst.keyword_args))
            else
              # No keyword args provided — pass empty KHash
              instructions << { "op" => "new", "type" => KHASH_CLASS }
              instructions << { "op" => "dup" }
              instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                                "name" => "<init>", "descriptor" => "()V" }
            end
          elsif i < args.size
            param_t = param_type(param)
            instructions.concat(load_value(args[i], param_t))
          else
            # Optional parameter not provided at call site — push default value
            param_t = param_type(param)
            if param.default_value
              instructions.concat(prism_default_to_jvm(param.default_value, param_t))
            else
              instructions.concat(default_value_instructions(param_t))
            end
          end
        end

        # Load KBlock argument
        instructions << load_instruction(kblock_var, :value)

        # Call with block parameter
        desc = method_descriptor_with_block(target_func, kblock_iface)
        instructions << { "op" => "invokestatic",
                          "owner" => main_class_name,
                          "name" => jvm_method_name(actual_target),
                          "descriptor" => desc }

        if result_var
          ret_type = function_return_type(target_func)
          if ret_type != :void
            ensure_slot(result_var, ret_type)
            instructions << store_instruction(result_var, ret_type)
            @variable_types[result_var] = ret_type
          end
        end

        instructions
      end

      # ========================================================================
      # Integer#times Inline Optimization
      # ========================================================================

      # ========================================================================
      # Array/Hash/Symbol Literal Generation
      # ========================================================================

      KARRAY_CLASS = "konpeito/runtime/KArray"
      KHASH_CLASS = "konpeito/runtime/KHash"

      def generate_array_lit(inst)
        result_var = inst.result_var
        ensure_slot(result_var, :array)
        instructions = []

        # new KArray(capacity)
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "iconst", "value" => inst.elements.size }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "(I)V" }

        # Add each element: dup, load element, box, List.add(Object), pop
        inst.elements.each do |elem|
          instructions << { "op" => "dup" }
          instructions.concat(load_and_box_for_collection(elem))
          instructions << { "op" => "invokeinterface", "owner" => "java/util/List",
                            "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "pop" }  # discard boolean return
        end

        instructions << store_instruction(result_var, :array)
        @variable_types[result_var] = :array
        @variable_collection_types[result_var] = :array

        # Track element type from HM inference (e.g., Array[String] → :string)
        # Only track reference types (:string) — primitives are unsafe to unbox at access time.
        if inst.type.is_a?(TypeChecker::Types::ClassInstance) &&
           inst.type.name == :Array && inst.type.type_args&.any?
          elem_tag = konpeito_type_to_tag(inst.type.type_args.first)
          @variable_array_element_types[result_var] = elem_tag if elem_tag == :string
        end

        instructions
      end

      def generate_symbol_lit(inst)
        result_var = inst.result_var
        ensure_slot(result_var, :string)
        @variable_is_symbol[result_var.to_s] = true

        [
          { "op" => "ldc", "value" => inst.value.to_s },
          store_instruction(result_var, :string)
        ].tap { @variable_types[result_var] = :string }
      end

      # Symbol#inspect → ":" + symbol_name
      def generate_symbol_inspect(receiver, result_var)
        instructions = []
        instructions << { "op" => "ldc", "value" => ":" }
        instructions.concat(load_value(receiver, :string))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "concat", "descriptor" => "(Ljava/lang/String;)Ljava/lang/String;" }
        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var.to_s] = :string
        end
        instructions
      end

      def generate_hash_lit(inst)
        result_var = inst.result_var
        ensure_slot(result_var, :hash)
        instructions = []

        # new KHash()
        instructions << { "op" => "new", "type" => KHASH_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }

        # Add each pair: dup, load key, box, load value, box, Map.put(Object,Object), pop
        inst.pairs.each do |key, value|
          instructions << { "op" => "dup" }
          instructions.concat(load_and_box_for_collection(key))
          instructions.concat(load_and_box_for_collection(value))
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map",
                            "name" => "put",
                            "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" }
          instructions << { "op" => "pop" }  # discard previous value
        end

        instructions << store_instruction(result_var, :hash)
        @variable_types[result_var] = :hash
        @variable_collection_types[result_var] = :hash
        instructions
      end

      # Build a KHash from keyword arguments (inst.keyword_args).
      # Returns instructions that leave a KHash on the operand stack.
      def build_kwargs_hash(keyword_args)
        instructions = []
        # new KHash()
        instructions << { "op" => "new", "type" => KHASH_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }

        keyword_args.each do |key_name, value_inst|
          instructions << { "op" => "dup" }
          # Load key as String (symbol name)
          instructions << { "op" => "ldc", "value" => key_name.to_s }
          # Load value as Object
          instructions.concat(load_and_box_for_collection(value_inst))
          # KHash implements Map, use put(Object, Object)
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map",
                            "name" => "put",
                            "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" }
          instructions << { "op" => "pop" }  # discard previous value
        end

        instructions
      end

      # Load an HIR value and box it as Object for collection storage
      def load_and_box_for_collection(hir_value)
        instructions = []
        var_name = extract_var_name(hir_value)
        type = if var_name
                 @variable_types[var_name] || (literal_type_tag(hir_value) || :value)
               else
                 literal_type_tag(hir_value) || :value
               end

        instructions.concat(load_value(hir_value, type))

        # Box primitive types to Object
        case type
        when :i64
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                            "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        when :double
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                            "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
        when :i8
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                            "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
        end
        instructions
      end

      # ========================================================================
      # Collection Type Detection Helpers
      # ========================================================================

      def is_array_receiver?(receiver)
        var_name = extract_var_name(receiver)
        return false unless var_name
        @variable_collection_types[var_name] == :array
      end

      # Extract element type tag from a Call instruction's HM-inferred return type.
      # For array element access (e.g., arr[i] → String), inst.type holds the element type.
      # Only returns reference types (:string) — primitives (:i64, :double) are unsafe
      # to unbox here because the value may be returned from blocks expecting Object.
      def resolve_array_element_type_from_inst(inst)
        return nil unless inst.respond_to?(:type) && inst.type
        hir_type = inst.type
        hir_type = hir_type.prune if hir_type.respond_to?(:prune)
        tag = konpeito_type_to_tag(hir_type)
        tag == :string ? :string : nil
      end

      def is_hash_receiver?(receiver)
        var_name = extract_var_name(receiver)
        return false unless var_name
        @variable_collection_types[var_name] == :hash
      end

      def is_string_receiver?(receiver)
        var_name = extract_var_name(receiver)
        return false unless var_name
        @variable_types[var_name] == :string
      end

      def string_method?(name)
        # Note: count, tr, chomp (with arg), delete, squeeze, insert, center, ljust, rjust,
        # capitalize, swapcase, chop, hex, oct, scan, match, match?, each_line
        # are delegated to invokedynamic (RubyDispatch.java) for correct Ruby semantics.
        # Note: gsub and sub are delegated to invokedynamic (RubyDispatch.java)
        # because they may receive Regexp (Pattern) arguments that can't be handled inline.
        %w[length size upcase downcase include? start_with? end_with? strip
           reverse empty? split chars lines bytes
           replace freeze frozen? to_i to_f []].include?(name)
      end

      # Check if a method argument is a Regexp (Pattern) type
      def regexp_type_arg?(arg)
        return true if arg.is_a?(HIR::RegexpLit)
        if arg.is_a?(HIR::LocalVar)
          var_name = arg.name.to_s
          type = @variable_types[var_name]
          return type == :regexp || type == :pattern
        end
        false
      end

      def numeric_instance_method?(name)
        %w[abs even? odd? zero? positive? negative?
           round floor ceil to_i to_f gcd].include?(name)
      end

      # Load receiver and checkcast to KArray (skips checkcast if already typed as :array)
      def load_karray_receiver(receiver)
        var_name = extract_var_name(receiver)
        type = var_name ? (@variable_types[var_name] || :value) : :value
        insts = load_value(receiver, type)
        insts << { "op" => "checkcast", "type" => KARRAY_CLASS } unless type == :array
        insts
      end

      # Load receiver and checkcast to KHash (skips checkcast if already typed as :hash)
      def load_khash_receiver(receiver)
        var_name = extract_var_name(receiver)
        type = var_name ? (@variable_types[var_name] || :value) : :value
        insts = load_value(receiver, type)
        insts << { "op" => "checkcast", "type" => KHASH_CLASS } unless type == :hash
        insts
      end

      # ========================================================================
      # Array Method Calls
      # ========================================================================

      def generate_array_method_call(method_name, receiver, args, result_var, block_def, element_type: nil)
        case method_name
        when "[]"
          generate_array_get(receiver, args, result_var, element_type: element_type)
        when "[]="
          generate_array_set(receiver, args, result_var)
        when "length", "size"
          generate_array_length(receiver, result_var)
        when "push", "<<"
          generate_array_push(receiver, args, result_var)
        when "first"
          if args.empty?
            generate_array_ruby_method(receiver, "first", "()Ljava/lang/Object;", result_var, element_type: element_type)
          else
            generate_array_first_n(receiver, args, result_var)
          end
        when "last"
          if args.empty?
            generate_array_ruby_method(receiver, "last", "()Ljava/lang/Object;", result_var, element_type: element_type)
          else
            generate_array_last_n(receiver, args, result_var)
          end
        when "take"
          generate_array_take(receiver, args, result_var)
        when "drop"
          generate_array_drop(receiver, args, result_var)
        when "zip"
          generate_array_zip(receiver, args, result_var)
        when "pop"
          generate_array_ruby_method(receiver, "pop", "()Ljava/lang/Object;", result_var, element_type: element_type)
        when "empty?"
          generate_array_predicate(receiver, "isEmpty_", result_var)
        when "include?"
          generate_array_includes(receiver, args, result_var)
        when "join"
          generate_array_join(receiver, args, result_var)
        when "reverse"
          generate_array_collection_method(receiver, "reverse", result_var)
        when "sort"
          if block_def
            # sort with block: fall through to dynamic dispatch via invokedynamic
            nil
          else
            generate_array_collection_method(receiver, "sort", result_var)
          end
        when "compact"
          generate_array_collection_method(receiver, "compact", result_var)
        when "uniq"
          generate_array_collection_method(receiver, "uniq", result_var)
        when "flatten"
          if args.empty?
            generate_array_collection_method(receiver, "flatten", result_var)
          else
            generate_array_flatten_depth(receiver, args, result_var)
          end
        when "min"
          generate_array_ruby_method(receiver, "min", "()Ljava/lang/Object;", result_var, element_type: element_type)
        when "max"
          generate_array_ruby_method(receiver, "max", "()Ljava/lang/Object;", result_var, element_type: element_type)
        when "each"
          if block_def
            generate_array_each_inline(receiver, block_def, result_var)
          end
        when "map", "collect"
          if block_def
            generate_array_map_inline(receiver, block_def, result_var)
          end
        when "select", "filter"
          if block_def
            generate_array_select_inline(receiver, block_def, result_var)
          end
        when "reject"
          if block_def
            generate_array_reject_inline(receiver, block_def, result_var)
          end
        when "reduce", "inject"
          if block_def
            generate_array_reduce_inline(receiver, args, block_def, result_var)
          end
        when "any?"
          if block_def
            generate_array_any_inline(receiver, block_def, result_var)
          end
        when "all?"
          if block_def
            generate_array_all_inline(receiver, block_def, result_var)
          end
        when "none?"
          if block_def
            generate_array_none_inline(receiver, block_def, result_var)
          end
        when "shift"
          generate_array_ruby_method(receiver, "shift", "()Ljava/lang/Object;", result_var, element_type: element_type)
        when "unshift", "prepend"
          generate_array_unshift(receiver, args, result_var)
        when "delete_at"
          generate_array_delete_at(receiver, args, result_var)
        when "delete"
          generate_array_delete_value(receiver, args, result_var)
        when "count"
          if block_def
            generate_array_count_inline(receiver, block_def, result_var)
          elsif args.empty?
            generate_array_length(receiver, result_var)
          end
        when "sum"
          if block_def
            generate_array_sum_inline(receiver, block_def, result_var)
          else
            generate_array_sum(receiver, result_var)
          end
        when "find_index"
          generate_array_find_index(receiver, args, result_var)
        when "find", "detect"
          if block_def
            generate_array_find_inline(receiver, block_def, result_var)
          end
        when "sort_by"
          nil # Complex: requires Comparator, skip for now
        when "min_by", "max_by"
          nil # Complex: requires block-based comparison, skip for now
        else
          nil  # Fall through to other dispatch
        end
      end

      def generate_array_get(receiver, args, result_var, element_type: nil)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))

        # Load index, convert to int
        instructions.concat(load_value_as_int(args.first))

        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }

        if result_var
          # Always store as :value (Object) — array elements are heterogeneous in Ruby.
          # checkcast should NOT be applied here because the same array may contain
          # mixed types (e.g., [String, Integer, Integer]). The consumer of the value
          # will apply the appropriate cast/conversion via convert_for_store.
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_array_set(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))

        # Load index
        instructions.concat(load_value_as_int(args[0]))

        # Load value, box if needed
        instructions.concat(load_and_box_for_collection(args[1]))

        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "set",
                          "descriptor" => "(ILjava/lang/Object;)Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      def generate_array_length(receiver, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_array_push(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "push",
                          "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }

        if result_var
          ensure_slot(result_var, :array)
          instructions << store_instruction(result_var, :array)
          @variable_types[result_var] = :array
          @variable_collection_types[result_var] = :array
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      def generate_array_ruby_method(receiver, method_name, descriptor, result_var, element_type: nil)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => method_name, "descriptor" => descriptor }

        if result_var
          # Always store as :value (Object) — same reasoning as generate_array_get.
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_array_predicate(receiver, method_name, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => method_name, "descriptor" => "()Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_array_includes(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "includes",
                          "descriptor" => "(Ljava/lang/Object;)Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_array_join(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))

        if args.empty?
          instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                            "name" => "join", "descriptor" => "()Ljava/lang/String;" }
        else
          instructions.concat(load_as_string(args.first))
          instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                            "name" => "join",
                            "descriptor" => "(Ljava/lang/String;)Ljava/lang/String;" }
        end

        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_array_collection_method(receiver, method_name, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => method_name,
                          "descriptor" => "()Lkonpeito/runtime/KArray;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      # -- Array methods --

      def generate_array_unshift(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "unshift",
                          "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      def generate_array_delete_at(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_value_as_int(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "deleteAt",
                          "descriptor" => "(I)Ljava/lang/Object;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_array_delete_value(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "deleteValue",
                          "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_array_sum(receiver, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "sumLong", "descriptor" => "()J" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_array_find_index(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "findIndex",
                          "descriptor" => "(Ljava/lang/Object;)J" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_array_first_n(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_value(args.first, :i64))
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "first", "descriptor" => "(I)Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_last_n(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_value(args.first, :i64))
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "last", "descriptor" => "(I)Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_take(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_value(args.first, :i64))
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "take", "descriptor" => "(I)Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_drop(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_value(args.first, :i64))
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "drop", "descriptor" => "(I)Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_zip(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_value(args.first, :value))
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "zip", "descriptor" => "(Lkonpeito/runtime/KArray;)Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_flatten_depth(receiver, args, result_var)
        instructions = []
        instructions.concat(load_karray_receiver(receiver))
        instructions.concat(load_value(args.first, :i64))
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "flatten", "descriptor" => "(I)Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_find_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        # Store array reference
        arr_var = "__arr_find_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        # Get array length
        len_var = "__arr_find_len_#{@block_counter}"
        ensure_slot(len_var, :i64)
        instructions << load_instruction(arr_var, :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(len_var, :i64)
        @variable_types[len_var] = :i64

        # Counter
        i_var = "__arr_find_i_#{@block_counter}"
        ensure_slot(i_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(i_var, :i64)
        @variable_types[i_var] = :i64

        # Result placeholder (null = not found)
        found_var = "__arr_find_result_#{@block_counter}"
        ensure_slot(found_var, :value)
        instructions << { "op" => "aconst_null" }
        instructions << store_instruction(found_var, :value)
        @variable_types[found_var] = :value

        loop_start = new_label("find_loop")
        loop_end = new_label("find_end")
        found_label = new_label("find_found")

        instructions << { "op" => "label", "name" => loop_start }
        # i < len?
        instructions << load_instruction(i_var, :i64)
        instructions << load_instruction(len_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => loop_end }

        # Load element
        block_param = block_def.params.first
        elem_var = block_param ? block_param.name.to_s : "__arr_find_elem_#{@block_counter}"
        saved_outer = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << load_instruction(i_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        # Execute block body (basic blocks)
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Check if block returned truthy → found
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          case last_type
          when :i8 then instructions << { "op" => "ifne", "target" => found_label }
          when :i64
            instructions << { "op" => "lconst_0" }
            instructions << { "op" => "lcmp" }
            instructions << { "op" => "ifne", "target" => found_label }
          else
            instructions << { "op" => "ifnonnull", "target" => found_label }
          end
        end

        # i++
        instructions << load_instruction(i_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(i_var, :i64)
        instructions << { "op" => "goto", "target" => loop_start }

        # Found: store element, then jump to end
        instructions << { "op" => "label", "name" => found_label }
        instructions << load_instruction(elem_var, :value)
        instructions << store_instruction(found_var, :value)

        instructions << { "op" => "label", "name" => loop_end }

        # Restore outer variable state after block completes
        restore_outer_var_after_block(elem_var, saved_outer)

        if result_var
          instructions << load_instruction(found_var, :value)
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ========================================================================
      # Block Parameter Scoping Helpers
      # ========================================================================

      # Save the outer variable's slot and type info so a block parameter with the
      # same name can shadow it without corrupting the outer variable's state.
      # Returns a saved state hash, or nil if no shadowing is needed.
      def save_outer_var_for_block_param(param_name)
        return nil unless @variable_slots.key?(param_name)
        saved = {
          slot: @variable_slots[param_name],
          type: @variable_types[param_name],
          class_type: @variable_class_types[param_name],
          collection_type: @variable_collection_types[param_name],
          kblock_iface: @variable_kblock_iface[param_name],
          concurrency_type: @variable_concurrency_types[param_name],
          native_array_element_type: @variable_native_array_element_type[param_name],
          is_symbol: @variable_is_symbol[param_name],
        }
        # Remove the old slot mapping so a new slot will be allocated for the block param
        @variable_slots.delete(param_name)
        @variable_types.delete(param_name)
        saved
      end

      # Restore the outer variable's slot and type info after the block has finished.
      def restore_outer_var_after_block(param_name, saved_state)
        return unless saved_state
        @variable_slots[param_name] = saved_state[:slot]
        @variable_types[param_name] = saved_state[:type]
        @variable_class_types[param_name] = saved_state[:class_type] if saved_state[:class_type]
        @variable_collection_types[param_name] = saved_state[:collection_type] if saved_state[:collection_type]
        @variable_kblock_iface[param_name] = saved_state[:kblock_iface] if saved_state[:kblock_iface]
        @variable_concurrency_types[param_name] = saved_state[:concurrency_type] if saved_state[:concurrency_type]
        @variable_native_array_element_type[param_name] = saved_state[:native_array_element_type] if saved_state[:native_array_element_type]
        @variable_is_symbol[param_name] = saved_state[:is_symbol] if saved_state[:is_symbol]
      end

      # ========================================================================
      # Array Enumerable Inline Loops
      # ========================================================================

      def generate_array_each_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        # Store array reference
        arr_var = "__arr_each_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        # Get size
        limit_var = "__each_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        # Counter i = 0
        counter_var = "__each_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("each_loop")
        end_label = new_label("each_end")

        # Loop header
        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        # Load element: arr.get(i)
        block_param = block_def.params.first
        elem_var = block_param ? block_param.name.to_s : "__each_elem_#{@block_counter}"
        # Save outer variable state if block param shadows it (different type)
        saved_outer = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        # Inline block body
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
          end
        end

        # Increment counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # Restore outer variable state after block completes
        restore_outer_var_after_block(elem_var, saved_outer)

        # each returns the receiver
        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(arr_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_map_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        # Store array
        arr_var = "__arr_map_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        # Get size
        limit_var = "__map_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        # Create result array
        result_arr_var = "__map_result_#{@block_counter}"
        ensure_slot(result_arr_var, :array)
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }
        instructions << store_instruction(result_arr_var, :array)
        @variable_types[result_arr_var] = :array

        # Counter
        counter_var = "__map_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("map_loop")
        end_label = new_label("map_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        # Load element
        block_param = block_def.params.first
        elem_var = block_param ? block_param.name.to_s : "__map_elem_#{@block_counter}"
        saved_outer_map = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Restore outer variable state after block completes
        restore_outer_var_after_block(elem_var, saved_outer_map)

        # Push block result to result array
        instructions << load_instruction(result_arr_var, @variable_types[result_arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[result_arr_var] == :array
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          # Box if primitive
          case last_type
          when :i64
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                              "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          when :double
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          when :i8
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                              "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
          end
        else
          instructions << { "op" => "aconst_null" }
        end
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "push",
                          "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
        instructions << { "op" => "pop" }

        # Increment
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(result_arr_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_select_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        arr_var = "__arr_sel_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        limit_var = "__sel_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        result_arr_var = "__sel_result_#{@block_counter}"
        ensure_slot(result_arr_var, :array)
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }
        instructions << store_instruction(result_arr_var, :array)
        @variable_types[result_arr_var] = :array

        counter_var = "__sel_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("sel_loop")
        end_label = new_label("sel_end")
        skip_label = new_label("sel_skip")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        block_param = block_def.params.first
        elem_var = block_param ? block_param.name.to_s : "__sel_elem_#{@block_counter}"
        saved_outer_sel = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Check truthiness of block result
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          case last_type
          when :i8
            instructions << { "op" => "ifeq", "target" => skip_label }
          when :i64
            instructions << { "op" => "lconst_0" }
            instructions << { "op" => "lcmp" }
            instructions << { "op" => "ifeq", "target" => skip_label }
          else
            instructions << { "op" => "ifnull", "target" => skip_label }
          end
        else
          instructions << { "op" => "goto", "target" => skip_label }
        end

        # Add element to result
        instructions << load_instruction(result_arr_var, @variable_types[result_arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[result_arr_var] == :array
        instructions << load_instruction(elem_var, :value)
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "push",
                          "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
        instructions << { "op" => "pop" }

        instructions << { "op" => "label", "name" => skip_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # Restore outer variable state after block completes
        restore_outer_var_after_block(elem_var, saved_outer_sel)

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(result_arr_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_reject_inline(receiver, block_def, result_var)
        # Same as select but inverted condition — skip when truthy
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        arr_var = "__arr_rej_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        limit_var = "__rej_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        result_arr_var = "__rej_result_#{@block_counter}"
        ensure_slot(result_arr_var, :array)
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }
        instructions << store_instruction(result_arr_var, :array)
        @variable_types[result_arr_var] = :array

        counter_var = "__rej_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rej_loop")
        end_label = new_label("rej_end")
        skip_label = new_label("rej_skip")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        block_param = block_def.params.first
        elem_var = block_param ? block_param.name.to_s : "__rej_elem_#{@block_counter}"
        saved_outer_rej = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # If truthy, skip (reject = keep when falsy)
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          case last_type
          when :i8
            instructions << { "op" => "ifne", "target" => skip_label }
          when :i64
            instructions << { "op" => "lconst_0" }
            instructions << { "op" => "lcmp" }
            instructions << { "op" => "ifne", "target" => skip_label }
          else
            instructions << { "op" => "ifnonnull", "target" => skip_label }
          end
        end

        instructions << load_instruction(result_arr_var, @variable_types[result_arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[result_arr_var] == :array
        instructions << load_instruction(elem_var, :value)
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "push",
                          "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
        instructions << { "op" => "pop" }

        instructions << { "op" => "label", "name" => skip_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # Restore outer variable state after block completes
        restore_outer_var_after_block(elem_var, saved_outer_rej)

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(result_arr_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_array_reduce_inline(receiver, args, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        arr_var = "__arr_red_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        limit_var = "__red_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        # Accumulator = initial value (boxed as Object)
        acc_param = block_def.params[0]
        acc_var = acc_param ? acc_param.name.to_s : "__red_acc_#{@block_counter}"
        saved_outer_acc = save_outer_var_for_block_param(acc_var)
        ensure_slot(acc_var, :value)
        has_initial = !!args.first
        if has_initial
          instructions.concat(load_and_box_for_collection(args.first))
        else
          # No initial value: use first element as accumulator, start loop from index 1
          instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
          instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
          instructions << { "op" => "iconst", "value" => 0 }
          instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                            "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        end
        instructions << store_instruction(acc_var, :value)
        @variable_types[acc_var] = :value

        counter_var = "__red_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        if has_initial
          instructions << { "op" => "lconst_0" }
        else
          # Start from index 1 when no initial value (first element is used as accumulator)
          instructions << { "op" => "lconst_1" }
        end
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("red_loop")
        end_label = new_label("red_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        # Load element
        elem_param = block_def.params[1]
        elem_var = elem_param ? elem_param.name.to_s : "__red_elem_#{@block_counter}"
        saved_outer_elem_red = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Store block result back to accumulator
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          case last_type
          when :i64
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                              "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          when :double
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          end
          instructions << store_instruction(acc_var, :value)
        end

        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # Restore outer variable state after block completes
        restore_outer_var_after_block(acc_var, saved_outer_acc)
        restore_outer_var_after_block(elem_var, saved_outer_elem_red)

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(acc_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_array_any_inline(receiver, block_def, result_var)
        generate_array_short_circuit_inline(receiver, block_def, result_var, :any)
      end

      def generate_array_all_inline(receiver, block_def, result_var)
        generate_array_short_circuit_inline(receiver, block_def, result_var, :all)
      end

      def generate_array_none_inline(receiver, block_def, result_var)
        generate_array_short_circuit_inline(receiver, block_def, result_var, :none)
      end

      def generate_array_short_circuit_inline(receiver, block_def, result_var, mode)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        arr_var = "__arr_sc_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        limit_var = "__sc_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        sc_result_var = "__sc_result_#{@block_counter}"
        ensure_slot(sc_result_var, :i8)
        # Default: any?=false, all?=true, none?=true
        default_val = (mode == :any) ? 0 : 1
        instructions << { "op" => "iconst", "value" => default_val }
        instructions << store_instruction(sc_result_var, :i8)
        @variable_types[sc_result_var] = :i8

        counter_var = "__sc_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("sc_loop")
        end_label = new_label("sc_end")
        found_label = new_label("sc_found")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        block_param = block_def.params.first
        elem_var = block_param ? block_param.name.to_s : "__sc_elem_#{@block_counter}"
        saved_outer_sc = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, @variable_types[arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[arr_var] == :array
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Check condition and short-circuit
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          case mode
          when :any
            # any?: if truthy → found (true)
            case last_type
            when :i8 then instructions << { "op" => "ifne", "target" => found_label }
            when :i64
              instructions << { "op" => "lconst_0" }
              instructions << { "op" => "lcmp" }
              instructions << { "op" => "ifne", "target" => found_label }
            else
              instructions << { "op" => "ifnonnull", "target" => found_label }
            end
          when :all
            # all?: if falsy → found (false)
            case last_type
            when :i8 then instructions << { "op" => "ifeq", "target" => found_label }
            when :i64
              instructions << { "op" => "lconst_0" }
              instructions << { "op" => "lcmp" }
              instructions << { "op" => "ifeq", "target" => found_label }
            else
              instructions << { "op" => "ifnull", "target" => found_label }
            end
          when :none
            # none?: if truthy → found (false)
            case last_type
            when :i8 then instructions << { "op" => "ifne", "target" => found_label }
            when :i64
              instructions << { "op" => "lconst_0" }
              instructions << { "op" => "lcmp" }
              instructions << { "op" => "ifne", "target" => found_label }
            else
              instructions << { "op" => "ifnonnull", "target" => found_label }
            end
          end
        end

        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }

        instructions << { "op" => "label", "name" => found_label }
        found_val = (mode == :any) ? 1 : 0
        instructions << { "op" => "iconst", "value" => found_val }
        instructions << store_instruction(sc_result_var, :i8)
        instructions << { "op" => "goto", "target" => end_label }

        instructions << { "op" => "label", "name" => end_label }

        # Restore outer variable state after block completes
        restore_outer_var_after_block(elem_var, saved_outer_sc)

        if result_var
          ensure_slot(result_var, :i8)
          instructions << load_instruction(sc_result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_array_count_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        arr_var = "__arr_cnt_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        limit_var = "__cnt_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        count_var = "__cnt_result_#{@block_counter}"
        ensure_slot(count_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(count_var, :i64)
        @variable_types[count_var] = :i64

        counter_var = "__cnt_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("cnt_loop")
        end_label = new_label("cnt_end")
        incr_label = new_label("cnt_incr")
        skip_label = new_label("cnt_skip")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        # Load element
        elem_param = block_def.params[0]
        elem_var = elem_param ? elem_param.name.to_s : "__cnt_elem_#{@block_counter}"
        saved_outer_cnt = save_outer_var_for_block_param(elem_var)
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Check if block returned truthy
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          if last_type == :i8
            instructions << { "op" => "ifeq", "target" => skip_label }
          else
            instructions << { "op" => "ifnull", "target" => skip_label }
          end
        end

        # Increment count
        instructions << { "op" => "label", "name" => incr_label }
        instructions << load_instruction(count_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(count_var, :i64)

        instructions << { "op" => "label", "name" => skip_label }

        # Increment counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # Restore outer variable state after block completes
        restore_outer_var_after_block(elem_var, saved_outer_cnt)

        if result_var
          ensure_slot(result_var, :i64)
          instructions << load_instruction(count_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_array_sum_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        arr_var = "__arr_sum_#{@block_counter}"
        ensure_slot(arr_var, :value)
        instructions.concat(load_value(receiver, :value))
        instructions << store_instruction(arr_var, :value)
        @variable_types[arr_var] = :value

        limit_var = "__sum_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << load_instruction(arr_var, :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "length", "descriptor" => "()J" }
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        # Accumulator (boxed as Object to handle both int/float)
        acc_var = "__sum_acc_#{@block_counter}"
        ensure_slot(acc_var, :value)
        instructions << { "op" => "lconst_0" }
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                          "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        instructions << store_instruction(acc_var, :value)
        @variable_types[acc_var] = :value

        counter_var = "__sum_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("sum_loop")
        end_label = new_label("sum_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        # Load element into block param
        elem_param = block_def.params[0]
        elem_var = elem_param ? elem_param.name.to_s : "__sum_elem_#{@block_counter}"
        ensure_slot(elem_var, :value)
        instructions << load_instruction(arr_var, :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        instructions << store_instruction(elem_var, :value)
        @variable_types[elem_var] = :value

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Add block result to accumulator using invokedynamic (handles both int/float)
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(acc_var, :value)
          instructions << load_instruction(last_result_var, last_type)
          # Box if needed
          case last_type
          when :i64
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                              "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          when :double
            instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                              "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          end
          instructions << { "op" => "invokedynamic",
                            "name" => "op_plus",
                            "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
                            "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
                            "bootstrapName" => "bootstrap",
                            "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
                            "bootstrapArgs" => [] }
          instructions << store_instruction(acc_var, :value)
        end

        # Increment counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(acc_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ========================================================================
      # Hash Method Calls
      # ========================================================================

      def generate_hash_method_call(method_name, receiver, args, result_var, _block_def)
        case method_name
        when "[]"
          generate_hash_get(receiver, args, result_var)
        when "[]="
          generate_hash_set(receiver, args, result_var)
        when "length", "size"
          generate_hash_length(receiver, result_var)
        when "has_key?", "key?"
          generate_hash_has_key(receiver, args, result_var)
        when "keys"
          generate_hash_keys(receiver, result_var)
        when "values"
          generate_hash_ruby_values(receiver, result_var)
        when "delete"
          generate_hash_delete(receiver, args, result_var)
        when "empty?"
          generate_hash_predicate(receiver, "isEmpty_", result_var)
        when "has_value?", "value?"
          generate_hash_has_value(receiver, args, result_var)
        when "count"
          if _block_def
            nil  # Fall through to dispatch for count with block
          else
            generate_hash_length(receiver, result_var)
          end
        when "each"
          if _block_def
            generate_hash_each_inline(receiver, _block_def, result_var)
          end
        when "fetch"
          generate_hash_fetch(receiver, args, result_var)
        when "merge"
          generate_hash_merge(receiver, args, result_var)
        when "merge!", "update"
          generate_hash_merge_inplace(receiver, args, result_var)
        when "clear"
          generate_hash_clear(receiver, result_var)
        when "each_key", "each_value", "each_pair"
          nil # Handled via invokedynamic dispatch → RubyDispatch
        when "select", "filter"
          if _block_def
            generate_hash_select_inline(receiver, _block_def, result_var, false)
          end
        when "reject"
          if _block_def
            generate_hash_select_inline(receiver, _block_def, result_var, true)
          end
        when "any?"
          if _block_def
            generate_hash_any_inline(receiver, _block_def, result_var)
          end
        when "all?"
          if _block_def
            generate_hash_all_inline(receiver, _block_def, result_var)
          end
        when "none?"
          if _block_def
            generate_hash_none_inline(receiver, _block_def, result_var)
          end
        when "each_with_object"
          if _block_def
            generate_hash_each_with_object_inline(receiver, args, _block_def, result_var)
          end
        when "min_by", "max_by", "sort_by"
          nil # Fall through to invokedynamic dispatch (complex iteration)
        when "to_a"
          generate_hash_to_a(receiver, result_var)
        when "map", "collect", "flat_map", "collect_concat", "find", "detect"
          nil # Handled via invokedynamic dispatch → RubyDispatch (block-based methods)
        else
          nil
        end
      end

      def generate_hash_get(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "get",
                          "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_hash_set(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args[0]))
        instructions.concat(load_and_box_for_collection(args[1]))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "put",
                          "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      def generate_hash_length(receiver, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "length", "descriptor" => "()J" }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_hash_has_key(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "hasKey",
                          "descriptor" => "(Ljava/lang/Object;)Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_hash_keys(receiver, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "rubyKeys",
                          "descriptor" => "()Lkonpeito/runtime/KArray;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_hash_ruby_values(receiver, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "rubyValues",
                          "descriptor" => "()Lkonpeito/runtime/KArray;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_hash_delete(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "remove",
                          "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_hash_predicate(receiver, method_name, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => method_name, "descriptor" => "()Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_hash_has_value(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args.first))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "hasValue",
                          "descriptor" => "(Ljava/lang/Object;)Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      # -- Hash methods --

      def generate_hash_fetch(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_and_box_for_collection(args[0]))
        if args.size > 1
          instructions.concat(load_and_box_for_collection(args[1]))
        else
          instructions << { "op" => "aconst_null" }
        end
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "fetch",
                          "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      def generate_hash_merge(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_value(args.first, :value))
        instructions << { "op" => "checkcast", "type" => KHASH_CLASS }
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "merge",
                          "descriptor" => "(Lkonpeito/runtime/KHash;)Lkonpeito/runtime/KHash;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :hash
        end
        instructions
      end

      def generate_hash_merge_inplace(receiver, args, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions.concat(load_value(args.first, :value))
        instructions << { "op" => "checkcast", "type" => KHASH_CLASS }
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "mergeInPlace",
                          "descriptor" => "(Lkonpeito/runtime/KHash;)Lkonpeito/runtime/KHash;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :hash
        end
        instructions
      end

      def generate_hash_clear(receiver, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "clear", "descriptor" => "()V" }
        # Return self (the dup'd hash)
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :hash
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      def generate_hash_each_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        # Store hash
        hash_var = "__hash_each_#{@block_counter}"
        recv_type = extract_var_name(receiver) ? (@variable_types[extract_var_name(receiver)] || :value) : :value
        hash_type = recv_type == :hash ? :hash : :value
        ensure_slot(hash_var, hash_type)
        instructions.concat(load_value(receiver, hash_type))
        instructions << store_instruction(hash_var, hash_type)
        @variable_types[hash_var] = hash_type

        # Get iterator: hash.entrySet().iterator()
        iter_var = "__hash_iter_#{@block_counter}"
        ensure_slot(iter_var, :value)
        instructions << load_instruction(hash_var, hash_type)
        instructions << { "op" => "checkcast", "type" => KHASH_CLASS } unless hash_type == :hash
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "entrySet", "descriptor" => "()Ljava/util/Set;" }
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Set",
                          "name" => "iterator", "descriptor" => "()Ljava/util/Iterator;" }
        instructions << store_instruction(iter_var, :value)
        @variable_types[iter_var] = :value

        loop_label = new_label("hash_each_loop")
        end_label = new_label("hash_each_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(iter_var, :value)
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Iterator",
                          "name" => "hasNext", "descriptor" => "()Z" }
        instructions << { "op" => "ifeq", "target" => end_label }

        # Get entry, extract key and value
        instructions << load_instruction(iter_var, :value)
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Iterator",
                          "name" => "next", "descriptor" => "()Ljava/lang/Object;" }
        instructions << { "op" => "checkcast", "type" => "java/util/Map$Entry" }

        key_param = block_def.params[0]
        value_param = block_def.params[1]
        key_var = key_param ? key_param.name.to_s : "__hash_key_#{@block_counter}"
        value_var = value_param ? value_param.name.to_s : "__hash_val_#{@block_counter}"

        ensure_slot(key_var, :value)
        ensure_slot(value_var, :value)

        instructions << { "op" => "dup" }
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                          "name" => "getKey", "descriptor" => "()Ljava/lang/Object;" }
        instructions << store_instruction(key_var, :value)
        @variable_types[key_var] = :value

        instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                          "name" => "getValue", "descriptor" => "()Ljava/lang/Object;" }
        instructions << store_instruction(value_var, :value)
        @variable_types[value_var] = :value

        # Inline block body
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
          end
        end

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(hash_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :hash
        end
        instructions
      end

      # Helper: set up hash iteration loop preamble (store hash, get iterator, start loop).
      # Returns [instructions, hash_var, iter_var, loop_label, end_label, counter_suffix]
      # Block params are:
      #   1-param block: pair = [key, value] (KArray)
      #   2-param block: key, value separately
      def setup_hash_iteration(receiver, block_def)
        @block_counter = (@block_counter || 0) + 1
        counter = @block_counter
        instructions = []

        # Store hash
        hash_var = "__hash_iter_h_#{counter}"
        recv_type = extract_var_name(receiver) ? (@variable_types[extract_var_name(receiver)] || :value) : :value
        hash_type = recv_type == :hash ? :hash : :value
        ensure_slot(hash_var, hash_type)
        instructions.concat(load_value(receiver, hash_type))
        instructions << store_instruction(hash_var, hash_type)
        @variable_types[hash_var] = hash_type

        # Get iterator
        iter_var = "__hash_iter_it_#{counter}"
        ensure_slot(iter_var, :value)
        instructions << load_instruction(hash_var, hash_type)
        instructions << { "op" => "checkcast", "type" => KHASH_CLASS } unless hash_type == :hash
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "entrySet", "descriptor" => "()Ljava/util/Set;" }
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Set",
                          "name" => "iterator", "descriptor" => "()Ljava/util/Iterator;" }
        instructions << store_instruction(iter_var, :value)
        @variable_types[iter_var] = :value

        loop_label = new_label("hash_iter_loop")
        end_label = new_label("hash_iter_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(iter_var, :value)
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Iterator",
                          "name" => "hasNext", "descriptor" => "()Z" }
        instructions << { "op" => "ifeq", "target" => end_label }

        # Get entry
        instructions << load_instruction(iter_var, :value)
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Iterator",
                          "name" => "next", "descriptor" => "()Ljava/lang/Object;" }
        instructions << { "op" => "checkcast", "type" => "java/util/Map$Entry" }

        # Extract key and value based on block params count
        if block_def.params.size >= 2
          # 2-param block: key, value
          key_param = block_def.params[0]
          value_param = block_def.params[1]
          key_var = key_param.name.to_s
          value_var = value_param.name.to_s

          ensure_slot(key_var, :value)
          ensure_slot(value_var, :value)

          instructions << { "op" => "dup" }
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                            "name" => "getKey", "descriptor" => "()Ljava/lang/Object;" }
          instructions << store_instruction(key_var, :value)
          @variable_types[key_var] = :value
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                            "name" => "getValue", "descriptor" => "()Ljava/lang/Object;" }
          instructions << store_instruction(value_var, :value)
          @variable_types[value_var] = :value
        else
          # 1-param block: pair = [key, value] as KArray
          pair_param = block_def.params[0]
          pair_var = pair_param ? pair_param.name.to_s : "__hash_pair_#{counter}"
          ensure_slot(pair_var, :value)

          # Build pair KArray
          pair_tmp = "__hash_pair_tmp_#{counter}"
          ensure_slot(pair_tmp, :value)
          instructions << { "op" => "dup" }
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                            "name" => "getKey", "descriptor" => "()Ljava/lang/Object;" }
          instructions << store_instruction("__hpk_#{counter}", :value)
          ensure_slot("__hpk_#{counter}", :value)
          @variable_types["__hpk_#{counter}"] = :value
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                            "name" => "getValue", "descriptor" => "()Ljava/lang/Object;" }
          instructions << store_instruction("__hpv_#{counter}", :value)
          ensure_slot("__hpv_#{counter}", :value)
          @variable_types["__hpv_#{counter}"] = :value

          # Create KArray pair
          instructions << { "op" => "new", "type" => KARRAY_CLASS }
          instructions << { "op" => "dup" }
          instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                            "name" => "<init>", "descriptor" => "()V" }
          instructions << store_instruction(pair_var, :value)
          @variable_types[pair_var] = :value

          instructions << load_instruction(pair_var, :value)
          instructions << load_instruction("__hpk_#{counter}", :value)
          instructions << { "op" => "invokeinterface", "owner" => "java/util/List",
                            "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "pop" }

          instructions << load_instruction(pair_var, :value)
          instructions << load_instruction("__hpv_#{counter}", :value)
          instructions << { "op" => "invokeinterface", "owner" => "java/util/List",
                            "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "pop" }
        end

        [instructions, hash_var, iter_var, loop_label, end_label, counter]
      end

      # Hash#select / Hash#reject inline
      def generate_hash_select_inline(receiver, block_def, result_var, negate)
        insts, hash_var, _iter_var, loop_label, end_label, counter = setup_hash_iteration(receiver, block_def)

        # Result hash
        result_hash_var = "__hash_sel_res_#{counter}"
        ensure_slot(result_hash_var, :value)
        result_insts = []
        result_insts << { "op" => "new", "type" => KHASH_CLASS }
        result_insts << { "op" => "dup" }
        result_insts << { "op" => "invokespecial", "owner" => KHASH_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }
        result_insts << store_instruction(result_hash_var, :value)
        @variable_types[result_hash_var] = :value

        # Insert result hash creation before loop
        insts = result_insts + insts

        # Inline block body
        last_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            insts.concat(generate_instruction(block_inst))
            last_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Check truthiness of block result
        add_entry_label = new_label("hash_sel_add")
        skip_label = new_label("hash_sel_skip")
        if last_var
          if negate
            # reject: skip if truthy → add if falsy
            insts.concat(load_and_check_truthy(last_var, skip_label))
          else
            # select: add if truthy → skip if falsy
            insts.concat(load_and_check_truthy(last_var, add_entry_label))
            insts << { "op" => "goto", "target" => skip_label }
            insts << { "op" => "label", "name" => add_entry_label }
          end
        end

        # Add entry to result hash
        key_var = block_def.params.size >= 2 ? block_def.params[0].name.to_s : "__hpk_#{counter}"
        val_var = block_def.params.size >= 2 ? block_def.params[1].name.to_s : "__hpv_#{counter}"
        insts << load_instruction(result_hash_var, :value)
        insts << load_instruction(key_var, :value)
        insts << load_instruction(val_var, :value)
        insts << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                   "name" => "put",
                   "descriptor" => "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" }
        insts << { "op" => "pop" }

        insts << { "op" => "label", "name" => skip_label } if last_var
        insts << { "op" => "goto", "target" => loop_label }
        insts << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          insts << load_instruction(result_hash_var, :value)
          insts << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        insts
      end

      # Hash#any? inline
      def generate_hash_any_inline(receiver, block_def, result_var)
        insts, _hash_var, _iter_var, loop_label, end_label, counter = setup_hash_iteration(receiver, block_def)

        # Inline block body
        last_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            insts.concat(generate_instruction(block_inst))
            last_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        found_label = new_label("hash_any_found")
        if last_var
          insts.concat(load_and_check_truthy(last_var, found_label))
        end

        insts << { "op" => "goto", "target" => loop_label }
        insts << { "op" => "label", "name" => end_label }

        # Not found: false
        if result_var
          ensure_slot(result_var, :value)
          insts << box_boolean(false)
          insts << store_instruction(result_var, :value)
          @variable_types[result_var] = :value

          done_label = new_label("hash_any_done")
          insts << { "op" => "goto", "target" => done_label }
          insts << { "op" => "label", "name" => found_label }
          insts << box_boolean(true)
          insts << store_instruction(result_var, :value)
          insts << { "op" => "label", "name" => done_label }
        else
          insts << { "op" => "label", "name" => found_label }
        end
        insts
      end

      # Hash#all? inline
      def generate_hash_all_inline(receiver, block_def, result_var)
        insts, _hash_var, _iter_var, loop_label, end_label, counter = setup_hash_iteration(receiver, block_def)

        # Inline block body
        last_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            insts.concat(generate_instruction(block_inst))
            last_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        not_all_label = new_label("hash_all_fail")
        if last_var
          insts.concat(load_and_check_falsy(last_var, not_all_label))
        end

        insts << { "op" => "goto", "target" => loop_label }
        insts << { "op" => "label", "name" => end_label }

        # All matched: true
        if result_var
          ensure_slot(result_var, :value)
          insts << box_boolean(true)
          insts << store_instruction(result_var, :value)
          @variable_types[result_var] = :value

          done_label = new_label("hash_all_done")
          insts << { "op" => "goto", "target" => done_label }
          insts << { "op" => "label", "name" => not_all_label }
          insts << box_boolean(false)
          insts << store_instruction(result_var, :value)
          insts << { "op" => "label", "name" => done_label }
        else
          insts << { "op" => "label", "name" => not_all_label }
        end
        insts
      end

      # Hash#none? inline
      def generate_hash_none_inline(receiver, block_def, result_var)
        insts, _hash_var, _iter_var, loop_label, end_label, counter = setup_hash_iteration(receiver, block_def)

        # Inline block body
        last_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            insts.concat(generate_instruction(block_inst))
            last_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        found_label = new_label("hash_none_fail")
        if last_var
          insts.concat(load_and_check_truthy(last_var, found_label))
        end

        insts << { "op" => "goto", "target" => loop_label }
        insts << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          insts << box_boolean(true)
          insts << store_instruction(result_var, :value)
          @variable_types[result_var] = :value

          done_label = new_label("hash_none_done")
          insts << { "op" => "goto", "target" => done_label }
          insts << { "op" => "label", "name" => found_label }
          insts << box_boolean(false)
          insts << store_instruction(result_var, :value)
          insts << { "op" => "label", "name" => done_label }
        else
          insts << { "op" => "label", "name" => found_label }
        end
        insts
      end

      # Hash#each_with_object inline
      def generate_hash_each_with_object_inline(receiver, args, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        counter = @block_counter
        instructions = []

        # Initialize memo from first arg
        memo_var = "__hash_ewo_memo_#{counter}"
        ensure_slot(memo_var, :value)
        instructions.concat(load_value(args.first, :value))
        instructions << store_instruction(memo_var, :value)
        @variable_types[memo_var] = :value

        # Store hash
        hash_var = "__hash_ewo_h_#{counter}"
        recv_type = extract_var_name(receiver) ? (@variable_types[extract_var_name(receiver)] || :value) : :value
        hash_type = recv_type == :hash ? :hash : :value
        ensure_slot(hash_var, hash_type)
        instructions.concat(load_value(receiver, hash_type))
        instructions << store_instruction(hash_var, hash_type)
        @variable_types[hash_var] = hash_type

        # Get iterator
        iter_var = "__hash_ewo_it_#{counter}"
        ensure_slot(iter_var, :value)
        instructions << load_instruction(hash_var, hash_type)
        instructions << { "op" => "checkcast", "type" => KHASH_CLASS } unless hash_type == :hash
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "entrySet", "descriptor" => "()Ljava/util/Set;" }
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Set",
                          "name" => "iterator", "descriptor" => "()Ljava/util/Iterator;" }
        instructions << store_instruction(iter_var, :value)
        @variable_types[iter_var] = :value

        loop_label = new_label("hash_ewo_loop")
        end_label = new_label("hash_ewo_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(iter_var, :value)
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Iterator",
                          "name" => "hasNext", "descriptor" => "()Z" }
        instructions << { "op" => "ifeq", "target" => end_label }

        instructions << load_instruction(iter_var, :value)
        instructions << { "op" => "invokeinterface", "owner" => "java/util/Iterator",
                          "name" => "next", "descriptor" => "()Ljava/lang/Object;" }
        instructions << { "op" => "checkcast", "type" => "java/util/Map$Entry" }

        # Block params: each_with_object yields |pair, memo| — pair is [k,v] array
        # The block may have 1 or 2 params:
        # 2 params: pair, memo
        if block_def.params.size >= 2
          pair_param = block_def.params[0]
          memo_param = block_def.params[1]

          pair_var = pair_param.name.to_s
          memo_param_var = memo_param.name.to_s

          # Build pair as KArray [key, value]
          ensure_slot(pair_var, :value)
          entry_tmp_k = "__ewo_ek_#{counter}"
          entry_tmp_v = "__ewo_ev_#{counter}"
          ensure_slot(entry_tmp_k, :value)
          ensure_slot(entry_tmp_v, :value)

          # Stack: [Entry]. Dup to get key, then use original for value
          instructions << { "op" => "dup" }
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                            "name" => "getKey", "descriptor" => "()Ljava/lang/Object;" }
          instructions << store_instruction(entry_tmp_k, :value)
          @variable_types[entry_tmp_k] = :value
          # Stack: [Entry]. Use for value
          instructions << { "op" => "invokeinterface", "owner" => "java/util/Map$Entry",
                            "name" => "getValue", "descriptor" => "()Ljava/lang/Object;" }
          instructions << store_instruction(entry_tmp_v, :value)
          @variable_types[entry_tmp_v] = :value

          # Create pair KArray
          instructions << { "op" => "new", "type" => KARRAY_CLASS }
          instructions << { "op" => "dup" }
          instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                            "name" => "<init>", "descriptor" => "()V" }
          instructions << store_instruction(pair_var, :value)
          @variable_types[pair_var] = :value

          instructions << load_instruction(pair_var, :value)
          instructions << load_instruction(entry_tmp_k, :value)
          instructions << { "op" => "invokeinterface", "owner" => "java/util/List",
                            "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "pop" }
          instructions << load_instruction(pair_var, :value)
          instructions << load_instruction(entry_tmp_v, :value)
          instructions << { "op" => "invokeinterface", "owner" => "java/util/List",
                            "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "pop" }

          # Set memo param to current memo_var
          ensure_slot(memo_param_var, :value)
          instructions << load_instruction(memo_var, :value)
          instructions << store_instruction(memo_param_var, :value)
          @variable_types[memo_param_var] = :value
        else
          # 1-param block: pop the entry
          instructions << { "op" => "pop" }
        end

        # Inline block body
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
          end
        end

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(memo_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Hash#min_by / Hash#max_by inline
      def generate_hash_min_max_by_inline(receiver, block_def, result_var, mode)
        insts, _hash_var, _iter_var, loop_label, end_label, counter = setup_hash_iteration(receiver, block_def)

        # Best value and best pair tracking
        best_key_var = "__hash_mmb_bk_#{counter}"
        best_val_var = "__hash_mmb_bv_#{counter}"
        best_score_var = "__hash_mmb_bs_#{counter}"
        first_var = "__hash_mmb_first_#{counter}"
        ensure_slot(best_key_var, :value)
        ensure_slot(best_val_var, :value)
        ensure_slot(best_score_var, :value)
        ensure_slot(first_var, :value)
        @variable_types[best_key_var] = :value
        @variable_types[best_val_var] = :value
        @variable_types[best_score_var] = :value
        @variable_types[first_var] = :value

        # Initialize first=true
        pre_insts = []
        pre_insts << box_boolean(true)
        pre_insts << store_instruction(first_var, :value)
        pre_insts << { "op" => "aconst_null" }
        pre_insts << store_instruction(best_key_var, :value)
        pre_insts << { "op" => "aconst_null" }
        pre_insts << store_instruction(best_val_var, :value)
        pre_insts << { "op" => "aconst_null" }
        pre_insts << store_instruction(best_score_var, :value)
        insts = pre_insts + insts

        # Save current key/value for possible assignment
        curr_key_var = block_def.params.size >= 2 ? block_def.params[0].name.to_s : "__hpk_#{counter}"
        curr_val_var = block_def.params.size >= 2 ? block_def.params[1].name.to_s : "__hpv_#{counter}"

        # Inline block body
        last_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            insts.concat(generate_instruction(block_inst))
            last_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Compare with best
        skip_label = new_label("hash_mmb_skip")
        if last_var
          # if first || score <cmp> best_score
          update_label = new_label("hash_mmb_update")
          insts.concat(load_and_check_truthy(first_var, update_label))

          # Compare scores using Comparable
          insts << load_instruction(last_var, @variable_types[last_var] || :value)
          insts.concat(box_if_needed(last_var))
          insts << { "op" => "checkcast", "type" => "java/lang/Comparable" }
          insts << load_instruction(best_score_var, :value)
          insts << { "op" => "invokeinterface", "owner" => "java/lang/Comparable",
                     "name" => "compareTo", "descriptor" => "(Ljava/lang/Object;)I" }
          if mode == :min
            insts << { "op" => "ifge", "target" => skip_label }
          else
            insts << { "op" => "ifle", "target" => skip_label }
          end

          insts << { "op" => "label", "name" => update_label }
          # Update best
          insts << load_instruction(last_var, @variable_types[last_var] || :value)
          insts.concat(box_if_needed(last_var))
          insts << store_instruction(best_score_var, :value)
          insts << load_instruction(curr_key_var, :value)
          insts << store_instruction(best_key_var, :value)
          insts << load_instruction(curr_val_var, :value)
          insts << store_instruction(best_val_var, :value)
          insts << box_boolean(false)
          insts << store_instruction(first_var, :value)
        end

        insts << { "op" => "label", "name" => skip_label } if last_var
        insts << { "op" => "goto", "target" => loop_label }
        insts << { "op" => "label", "name" => end_label }

        # Build result pair [best_key, best_val]
        if result_var
          ensure_slot(result_var, :value)
          insts << { "op" => "new", "type" => KARRAY_CLASS }
          insts << { "op" => "dup" }
          insts << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                     "name" => "<init>", "descriptor" => "()V" }
          insts << store_instruction(result_var, :value)
          @variable_types[result_var] = :value

          insts << load_instruction(result_var, :value)
          insts << load_instruction(best_key_var, :value)
          insts << { "op" => "invokeinterface", "owner" => "java/util/List",
                     "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          insts << { "op" => "pop" }

          insts << load_instruction(result_var, :value)
          insts << load_instruction(best_val_var, :value)
          insts << { "op" => "invokeinterface", "owner" => "java/util/List",
                     "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          insts << { "op" => "pop" }
        end
        insts
      end

      # Hash#sort_by inline — convert to pairs, collect scores, sort via KHash.sortPairsByScores
      def generate_hash_sort_by_inline(receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        counter = @block_counter
        insts = []

        # Convert hash to array of pairs via toArray_
        pairs_var = "__hash_sb_pairs_#{counter}"
        ensure_slot(pairs_var, :value)
        @variable_types[pairs_var] = :value
        insts.concat(load_value(receiver, :value))
        insts << { "op" => "checkcast", "type" => KHASH_CLASS }
        insts << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                   "name" => "toArray_", "descriptor" => "()Lkonpeito/runtime/KArray;" }
        insts << store_instruction(pairs_var, :value)

        # Collect scores into a parallel KArray
        scores_var = "__hash_sb_scores_#{counter}"
        ensure_slot(scores_var, :value)
        @variable_types[scores_var] = :value
        insts << { "op" => "new", "type" => KARRAY_CLASS }
        insts << { "op" => "dup" }
        insts << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                   "name" => "<init>", "descriptor" => "()V" }
        insts << store_instruction(scores_var, :value)

        # Iterate over pairs to compute scores
        idx_var = "__hash_sb_idx_#{counter}"
        len_var = "__hash_sb_len_#{counter}"
        ensure_slot(idx_var, :long)
        ensure_slot(len_var, :long)
        @variable_types[idx_var] = :long
        @variable_types[len_var] = :long

        insts << { "op" => "lconst_0" }
        insts << store_instruction(idx_var, :long)
        insts << load_instruction(pairs_var, :value)
        insts << { "op" => "invokeinterface", "owner" => "java/util/List",
                   "name" => "size", "descriptor" => "()I" }
        insts << { "op" => "i2l" }
        insts << store_instruction(len_var, :long)

        loop_label = new_label("hash_sb_loop")
        end_label = new_label("hash_sb_end")

        insts << { "op" => "label", "name" => loop_label }
        insts << load_instruction(idx_var, :long)
        insts << load_instruction(len_var, :long)
        insts << { "op" => "lcmp" }
        insts << { "op" => "ifge", "target" => end_label }

        # Get pair at idx → block param
        pair_param = block_def.params[0]
        pair_var = pair_param ? pair_param.name.to_s : "__hash_sb_pair_#{counter}"
        ensure_slot(pair_var, :value)
        @variable_types[pair_var] = :value

        insts << load_instruction(pairs_var, :value)
        insts << load_instruction(idx_var, :long)
        insts << { "op" => "l2i" }
        insts << { "op" => "invokeinterface", "owner" => "java/util/List",
                   "name" => "get", "descriptor" => "(I)Ljava/lang/Object;" }
        insts << store_instruction(pair_var, :value)

        # Inline block body
        last_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            insts.concat(generate_instruction(block_inst))
            last_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Add score to scores array
        if last_var
          insts << load_instruction(scores_var, :value)
          insts << load_instruction(last_var, @variable_types[last_var] || :value)
          insts.concat(box_if_needed(last_var))
          insts << { "op" => "invokeinterface", "owner" => "java/util/List",
                     "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
          insts << { "op" => "pop" }
        end

        insts << load_instruction(idx_var, :long)
        insts << { "op" => "lconst_1" }
        insts << { "op" => "ladd" }
        insts << store_instruction(idx_var, :long)
        insts << { "op" => "goto", "target" => loop_label }
        insts << { "op" => "label", "name" => end_label }

        # Sort pairs by scores using Java-side helper
        insts << load_instruction(pairs_var, :value)
        insts << { "op" => "checkcast", "type" => KARRAY_CLASS }
        insts << load_instruction(scores_var, :value)
        insts << { "op" => "checkcast", "type" => KARRAY_CLASS }
        insts << { "op" => "invokestatic", "owner" => KHASH_CLASS,
                   "name" => "sortPairsByScores",
                   "descriptor" => "(Lkonpeito/runtime/KArray;Lkonpeito/runtime/KArray;)V" }

        if result_var
          ensure_slot(result_var, :value)
          insts << load_instruction(pairs_var, :value)
          insts << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        insts
      end

      # Hash#to_a — returns KArray of [key, value] pairs
      def generate_hash_to_a(receiver, result_var)
        instructions = []
        instructions.concat(load_khash_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => KHASH_CLASS,
                          "name" => "toArray_",
                          "descriptor" => "()Lkonpeito/runtime/KArray;" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ========================================================================
      # String Method Calls
      # ========================================================================

      # Load receiver and ensure it's typed as String on the JVM stack.
      # When HM inference knows the type is String but the variable slot holds Object
      # (e.g. from invokedynamic result), we need checkcast java/lang/String.
      def load_string_receiver(receiver)
        load_as_string(receiver)
      end

      # Load any HIR value and ensure it's typed as String on the JVM stack.
      # Always adds checkcast java/lang/String because HM inference may say :string
      # but the JVM slot may hold Object (e.g. from invokedynamic results).
      # Duplicate checkcast is harmless on JVM.
      def load_as_string(hir_value)
        insts = load_value(hir_value, :string)
        insts << { "op" => "checkcast", "type" => "java/lang/String" }
        insts
      end

      def generate_string_method_call(method_name, receiver, args, result_var)
        case method_name
        when "length", "size"
          generate_string_length(receiver, result_var)
        when "upcase"
          generate_string_transform(receiver, "toUpperCase", result_var)
        when "downcase"
          generate_string_transform(receiver, "toLowerCase", result_var)
        when "strip"
          generate_string_transform(receiver, "strip", result_var)
        when "reverse"
          generate_string_reverse(receiver, result_var)
        when "empty?"
          generate_string_predicate(receiver, "isEmpty", result_var)
        when "include?"
          generate_string_contains(receiver, args, result_var)
        when "start_with?"
          generate_string_predicate_with_arg(receiver, "startsWith", args, result_var)
        when "end_with?"
          generate_string_predicate_with_arg(receiver, "endsWith", args, result_var)
        when "split"
          generate_string_split(receiver, args, result_var)
        when "gsub"
          # If the pattern arg is a Regexp, fall through to dispatch (which handles Pattern)
          if args.size >= 1 && (args[0].is_a?(HIR::RegexpLit) || regexp_type_arg?(args[0]))
            nil
          else
            generate_string_gsub(receiver, args, result_var)
          end
        when "sub"
          if args.size >= 1 && (args[0].is_a?(HIR::RegexpLit) || regexp_type_arg?(args[0]))
            nil
          else
            generate_string_sub(receiver, args, result_var)
          end
        when "index"
          generate_string_index(receiver, args, result_var)
        when "rindex"
          generate_string_rindex(receiver, args, result_var)
        when "chars"
          generate_string_chars(receiver, result_var)
        when "lines"
          generate_string_lines(receiver, result_var)
        when "bytes"
          generate_string_bytes(receiver, result_var)
        when "replace"
          generate_string_replace(receiver, args, result_var)
        when "freeze"
          # No-op on JVM (strings are immutable), just return the receiver
          generate_string_passthrough(receiver, result_var)
        when "frozen?"
          # Always true on JVM (strings are immutable)
          generate_string_always_true(result_var)
        when "count"
          generate_string_count(receiver, args, result_var)
        when "tr"
          generate_string_tr(receiver, args, result_var)
        when "chomp"
          generate_string_chomp(receiver, result_var)
        when "to_i"
          generate_string_to_i(receiver, result_var)
        when "to_f"
          generate_string_to_f(receiver, result_var)
        when "[]"
          generate_string_subscript(receiver, args, result_var)
        else
          []
        end
      end

      # String#[](index) or String#[](start, length)
      def generate_string_subscript(receiver, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))

        if args.size == 2
          # String#[](start, length) → substring(start, start + length)
          # Load start twice (avoid dup which confuses ASM frame computation in nested ifs)
          instructions.concat(load_value_as_int(args[0]))
          # Stack: [string, start]
          instructions.concat(load_value_as_int(args[0]))
          instructions.concat(load_value_as_int(args[1]))
          instructions << { "op" => "iadd" }
          # Stack: [string, start, start+length]
          instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                            "name" => "substring", "descriptor" => "(II)Ljava/lang/String;" }
        elsif args.size == 1
          # String#[](index) → substring(idx, idx+1) for single char
          instructions.concat(load_value_as_int(args[0]))
          instructions.concat(load_value_as_int(args[0]))
          instructions << { "op" => "iconst", "value" => 1 }
          instructions << { "op" => "iadd" }
          # Stack: [string, idx, idx+1]
          instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                            "name" => "substring", "descriptor" => "(II)Ljava/lang/String;" }
        else
          return []
        end

        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      # String#+(other) — concatenation
      def generate_string_plus(receiver, args, result_var)
        return [] unless args.size == 1
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_value(args[0], :value))
        # Convert arg to String if needed
        instructions << { "op" => "invokestatic", "owner" => "java/lang/String",
                          "name" => "valueOf", "descriptor" => "(Ljava/lang/Object;)Ljava/lang/String;" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "concat", "descriptor" => "(Ljava/lang/String;)Ljava/lang/String;" }
        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_length(receiver, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "length", "descriptor" => "()I" }
        instructions << { "op" => "i2l" }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_string_transform(receiver, java_method, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => java_method,
                          "descriptor" => "()Ljava/lang/String;" }

        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_reverse(receiver, result_var)
        instructions = []
        instructions << { "op" => "new", "type" => "java/lang/StringBuilder" }
        instructions << { "op" => "dup" }
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokespecial", "owner" => "java/lang/StringBuilder",
                          "name" => "<init>",
                          "descriptor" => "(Ljava/lang/String;)V" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/StringBuilder",
                          "name" => "reverse",
                          "descriptor" => "()Ljava/lang/StringBuilder;" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/StringBuilder",
                          "name" => "toString",
                          "descriptor" => "()Ljava/lang/String;" }

        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_predicate(receiver, java_method, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => java_method, "descriptor" => "()Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_string_contains(receiver, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args.first))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "contains",
                          "descriptor" => "(Ljava/lang/CharSequence;)Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_string_predicate_with_arg(receiver, java_method, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args.first))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => java_method,
                          "descriptor" => "(Ljava/lang/String;)Z" }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_string_split(receiver, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args.first))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "split",
                          "descriptor" => "(Ljava/lang/String;)[Ljava/lang/String;" }
        # Convert String[] to KArray via Arrays.asList then KArray(Collection)
        instructions << { "op" => "invokestatic", "owner" => "java/util/Arrays",
                          "name" => "asList",
                          "descriptor" => "([Ljava/lang/Object;)Ljava/util/List;" }
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup_x1" }
        instructions << { "op" => "swap" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>",
                          "descriptor" => "(Ljava/util/Collection;)V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_string_gsub(receiver, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args[0]))
        instructions.concat(load_as_string(args[1]))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "replaceAll",
                          "descriptor" => "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;" }

        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      # -- String methods --

      def generate_string_sub(receiver, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args[0]))
        instructions.concat(load_as_string(args[1]))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "replaceFirst",
                          "descriptor" => "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;" }
        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_index(receiver, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args.first))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "indexOf",
                          "descriptor" => "(Ljava/lang/String;)I" }
        # indexOf returns -1 if not found → convert to nil or boxed Integer
        # For simplicity: return -1 as i64 (caller can check for -1)
        instructions << { "op" => "i2l" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_string_rindex(receiver, args, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args.first))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "lastIndexOf",
                          "descriptor" => "(Ljava/lang/String;)I" }
        instructions << { "op" => "i2l" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_string_chars(receiver, result_var)
        instructions = []
        # Split by empty string to get char array, then convert to KArray
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "ldc", "value" => "" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "split",
                          "descriptor" => "(Ljava/lang/String;)[Ljava/lang/String;" }
        instructions << { "op" => "invokestatic", "owner" => "java/util/Arrays",
                          "name" => "asList",
                          "descriptor" => "([Ljava/lang/Object;)Ljava/util/List;" }
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup_x1" }
        instructions << { "op" => "swap" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>",
                          "descriptor" => "(Ljava/util/Collection;)V" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_string_lines(receiver, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "ldc", "value" => "\\n" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "split",
                          "descriptor" => "(Ljava/lang/String;)[Ljava/lang/String;" }
        instructions << { "op" => "invokestatic", "owner" => "java/util/Arrays",
                          "name" => "asList",
                          "descriptor" => "([Ljava/lang/Object;)Ljava/util/List;" }
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup_x1" }
        instructions << { "op" => "swap" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>",
                          "descriptor" => "(Ljava/util/Collection;)V" }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_string_bytes(receiver, result_var)
        instructions = []
        # Create KArray, then loop over getBytes() to add each byte as Long
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }
        # Store KArray temporarily
        temp_arr = "__str_bytes_arr_#{@block_counter}"
        @block_counter += 1
        ensure_slot(temp_arr, :value)
        instructions << store_instruction(temp_arr, :value)

        # Get byte array
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "getBytes", "descriptor" => "()[B" }
        temp_bytes = "__str_bytes_raw_#{@block_counter}"
        @block_counter += 1
        ensure_slot(temp_bytes, :value)
        instructions << store_instruction(temp_bytes, :value)

        # Loop: i = 0; while i < bytes.length
        counter = "__str_bytes_i_#{@block_counter}"
        @block_counter += 1
        ensure_slot(counter, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter, :i64)

        loop_start = new_label("bytes_loop")
        loop_end = new_label("bytes_end")

        instructions << { "op" => "label", "name" => loop_start }
        instructions << load_instruction(counter, :i64)
        instructions << load_instruction(temp_bytes, :value)
        instructions << { "op" => "arraylength" }
        instructions << { "op" => "i2l" }
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => loop_end }

        # arr.add(Long.valueOf(bytes[i] & 0xFF))
        instructions << load_instruction(temp_arr, :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS }
        instructions << load_instruction(temp_bytes, :value)
        instructions << { "op" => "checkcast", "type" => "[B" }
        instructions << load_instruction(counter, :i64)
        instructions << { "op" => "l2i" }
        instructions << { "op" => "baload" }
        # Sign extend byte and mask to 0-255
        instructions << { "op" => "sipush", "value" => 255 }
        instructions << { "op" => "iand" }
        instructions << { "op" => "i2l" }
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                          "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "add", "descriptor" => "(Ljava/lang/Object;)Z" }
        instructions << { "op" => "pop" }

        # i += 1
        instructions << load_instruction(counter, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter, :i64)
        instructions << { "op" => "goto", "target" => loop_start }
        instructions << { "op" => "label", "name" => loop_end }

        # Load result
        if result_var
          instructions << load_instruction(temp_arr, :value)
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      def generate_string_replace(receiver, args, result_var)
        # In Ruby, replace mutates the string. On JVM strings are immutable,
        # so we just return the replacement string (reassign semantics).
        instructions = []
        instructions.concat(load_as_string(args.first))
        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_passthrough(receiver, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_always_true(result_var)
        instructions = []
        instructions << { "op" => "iconst", "value" => 1 }
        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_string_count(receiver, args, result_var)
        instructions = []
        # Use a loop: count how many times indexOf succeeds
        # Simple approach: use replaceAll to remove target, compare lengths
        # count = (original.length - original.replace(target, "").length) / target.length
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "length", "descriptor" => "()I" }
        # Save original length
        temp_orig = "__str_count_orig_#{@block_counter}"
        @block_counter += 1
        ensure_slot(temp_orig, :i64)
        instructions << { "op" => "i2l" }
        instructions << store_instruction(temp_orig, :i64)

        # receiver.replace(target, "")
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args.first))
        instructions << { "op" => "ldc", "value" => "" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "replace",
                          "descriptor" => "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "length", "descriptor" => "()I" }
        instructions << { "op" => "i2l" }
        temp_new = "__str_count_new_#{@block_counter}"
        @block_counter += 1
        ensure_slot(temp_new, :i64)
        instructions << store_instruction(temp_new, :i64)

        # target.length
        instructions.concat(load_as_string(args.first))
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "length", "descriptor" => "()I" }
        instructions << { "op" => "i2l" }
        temp_tlen = "__str_count_tlen_#{@block_counter}"
        @block_counter += 1
        ensure_slot(temp_tlen, :i64)
        instructions << store_instruction(temp_tlen, :i64)

        # result = (orig_len - new_len) / target_len
        instructions << load_instruction(temp_orig, :i64)
        instructions << load_instruction(temp_new, :i64)
        instructions << { "op" => "lsub" }
        instructions << load_instruction(temp_tlen, :i64)
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => "floorDiv", "descriptor" => "(JJ)J" }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_string_tr(receiver, args, result_var)
        instructions = []
        # For single-char tr, we can use String.replace(char, char)
        # General approach: iterate and replace characters
        # Simple approach: use a loop with StringBuilder
        # Actually Java doesn't have a direct tr equivalent, but for simple cases
        # we can chain replace calls. Use a loop-based approach via a helper.
        # Simplest: use replaceAll with character class if from/to are single chars
        # For now, implement simple single-char tr using replace(CharSequence, CharSequence)
        instructions.concat(load_string_receiver(receiver))
        instructions.concat(load_as_string(args[0]))
        instructions.concat(load_as_string(args[1]))
        # Use String.replace(CharSequence, CharSequence) for simple cases
        # For multi-char tr, this handles char-by-char replacement via loop
        # Simple implementation: replace each char in `from` with corresponding char in `to`
        # This works for the common case tr("abc", "xyz") by chaining replace calls
        # For now, use a simplified approach: if from.length == 1, use replace
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "replace",
                          "descriptor" => "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;" }
        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_chomp(receiver, result_var)
        instructions = []
        instructions.concat(load_string_receiver(receiver))
        # Remove trailing \n, \r\n, or \r
        instructions << { "op" => "ldc", "value" => "\\r?\\n$|\\r$" }
        instructions << { "op" => "ldc", "value" => "" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/String",
                          "name" => "replaceAll",
                          "descriptor" => "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;" }
        if result_var
          ensure_slot(result_var, :string)
          instructions << store_instruction(result_var, :string)
          @variable_types[result_var] = :string
        end
        instructions
      end

      def generate_string_to_i(receiver, result_var)
        instructions = []
        # Use invokedynamic for Ruby-compatible String#to_i
        # (handles non-numeric strings, partial parsing, etc.)
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokedynamic",
                          "name" => "to_i",
                          "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;",
                          "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
                          "bootstrapName" => "bootstrap",
                          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;" }
        instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                          "name" => "longValue", "descriptor" => "()J" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_string_to_f(receiver, result_var)
        instructions = []
        # Use invokedynamic for Ruby-compatible String#to_f
        instructions.concat(load_string_receiver(receiver))
        instructions << { "op" => "invokedynamic",
                          "name" => "to_f",
                          "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;",
                          "bootstrapOwner" => "konpeito/runtime/RubyDispatch",
                          "bootstrapName" => "bootstrap",
                          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;" }
        instructions << { "op" => "checkcast", "type" => "java/lang/Number" }
        instructions << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                          "name" => "doubleValue", "descriptor" => "()D" }
        if result_var
          ensure_slot(result_var, :double)
          instructions << store_instruction(result_var, :double)
          @variable_types[result_var] = :double
        end
        instructions
      end

      # ========================================================================
      # Numeric Method Calls
      # ========================================================================

      def generate_numeric_method_call(method_name, receiver, args, result_var)
        recv_var = extract_var_name(receiver)
        recv_type = recv_var ? (@variable_types[recv_var] || :value) : (literal_type_tag(receiver) || :value)
        return nil unless recv_type == :i64 || recv_type == :double

        case method_name
        when "abs"
          generate_numeric_abs(receiver, recv_type, result_var)
        when "even?"
          return nil unless recv_type == :i64
          generate_integer_predicate(receiver, :even, result_var)
        when "odd?"
          return nil unless recv_type == :i64
          generate_integer_predicate(receiver, :odd, result_var)
        when "zero?"
          generate_numeric_comparison(receiver, recv_type, :eq, result_var)
        when "positive?"
          generate_numeric_comparison(receiver, recv_type, :gt, result_var)
        when "negative?"
          generate_numeric_comparison(receiver, recv_type, :lt, result_var)
        when "round"
          return nil unless recv_type == :double
          # Ruby uses round-half-away-from-zero, not Java's round-half-to-even
          # So we need custom logic instead of Math.round
          generate_ruby_round(receiver, result_var)
        when "floor"
          return nil unless recv_type == :double
          generate_float_to_long_via_double(receiver, "floor", result_var)
        when "ceil"
          return nil unless recv_type == :double
          generate_float_to_long_via_double(receiver, "ceil", result_var)
        when "to_i"
          return nil unless recv_type == :double
          generate_double_to_long(receiver, result_var)
        when "to_f"
          return nil unless recv_type == :i64
          generate_long_to_double(receiver, result_var)
        when "gcd"
          return nil unless recv_type == :i64
          generate_integer_gcd(receiver, args, result_var)
        else
          nil
        end
      end

      def generate_numeric_abs(receiver, type, result_var)
        instructions = []
        instructions.concat(load_value(receiver, type))

        case type
        when :i64
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                            "name" => "abs", "descriptor" => "(J)J" }
        when :double
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                            "name" => "abs", "descriptor" => "(D)D" }
        end

        if result_var
          ensure_slot(result_var, type)
          instructions << store_instruction(result_var, type)
          @variable_types[result_var] = type
        end
        instructions
      end

      def generate_integer_predicate(receiver, mode, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :i64))

        true_label = new_label("pred_true")
        end_label = new_label("pred_end")

        # n & 1
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "land" }
        instructions << { "op" => "lconst_0" }
        instructions << { "op" => "lcmp" }

        if mode == :even
          instructions << { "op" => "ifeq", "target" => true_label }
        else  # :odd
          instructions << { "op" => "ifne", "target" => true_label }
        end

        instructions << { "op" => "iconst", "value" => 0 }
        instructions << { "op" => "goto", "target" => end_label }
        instructions << { "op" => "label", "name" => true_label }
        instructions << { "op" => "iconst", "value" => 1 }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      def generate_numeric_comparison(receiver, type, mode, result_var)
        instructions = []
        instructions.concat(load_value(receiver, type))

        true_label = new_label("cmp_true")
        end_label = new_label("cmp_end")

        case type
        when :i64
          instructions << { "op" => "lconst_0" }
          instructions << { "op" => "lcmp" }
        when :double
          instructions << { "op" => "dconst_0" }
          instructions << { "op" => "dcmpl" }
        end

        branch_op = case mode
                    when :eq then "ifeq"
                    when :gt then "ifgt"
                    when :lt then "iflt"
                    end
        instructions << { "op" => branch_op, "target" => true_label }
        instructions << { "op" => "iconst", "value" => 0 }
        instructions << { "op" => "goto", "target" => end_label }
        instructions << { "op" => "label", "name" => true_label }
        instructions << { "op" => "iconst", "value" => 1 }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :i8)
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        end
        instructions
      end

      # -- Numeric methods --

      def generate_float_math(receiver, java_method, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :double))
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => java_method, "descriptor" => "(D)D" }
        if result_var
          ensure_slot(result_var, :double)
          instructions << store_instruction(result_var, :double)
          @variable_types[result_var] = :double
        end
        instructions
      end

      def generate_float_to_long_math(receiver, java_method, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :double))
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => java_method, "descriptor" => "(D)J" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # Ruby round: round-half-away-from-zero
      # if (x >= 0) return (long)Math.floor(x + 0.5) else return (long)Math.ceil(x - 0.5)
      def generate_ruby_round(receiver, result_var)
        instructions = []
        pos_label = new_label("round_pos")
        end_label = new_label("round_end")

        # Load receiver
        instructions.concat(load_value(receiver, :double))
        instructions << { "op" => "dconst_0" }
        instructions << { "op" => "dcmpg" }
        instructions << { "op" => "ifge", "target" => pos_label }

        # Negative case: ceil(x - 0.5)
        instructions.concat(load_value(receiver, :double))
        instructions << { "op" => "ldc2_w", "value" => 0.5, "type" => "double" }
        instructions << { "op" => "dsub" }
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => "ceil", "descriptor" => "(D)D" }
        instructions << { "op" => "d2l" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
        end
        instructions << { "op" => "goto", "target" => end_label }

        # Positive case: floor(x + 0.5)
        instructions << { "op" => "label", "name" => pos_label }
        instructions.concat(load_value(receiver, :double))
        instructions << { "op" => "ldc2_w", "value" => 0.5, "type" => "double" }
        instructions << { "op" => "dadd" }
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => "floor", "descriptor" => "(D)D" }
        instructions << { "op" => "d2l" }
        if result_var
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end

        instructions << { "op" => "label", "name" => end_label }
        instructions
      end

      # Call Math.floor/ceil (returns double), then d2l to convert to long
      def generate_float_to_long_via_double(receiver, java_method, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :double))
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => java_method, "descriptor" => "(D)D" }
        instructions << { "op" => "d2l" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_double_to_long(receiver, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :double))
        instructions << { "op" => "d2l" }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      def generate_long_to_double(receiver, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :i64))
        instructions << { "op" => "l2d" }
        if result_var
          ensure_slot(result_var, :double)
          instructions << store_instruction(result_var, :double)
          @variable_types[result_var] = :double
        end
        instructions
      end

      def generate_integer_gcd(receiver, args, result_var)
        instructions = []
        # Euclidean algorithm using a loop
        # a = abs(receiver), b = abs(arg)
        instructions.concat(load_value(receiver, :i64))
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => "abs", "descriptor" => "(J)J" }
        a_var = "__gcd_a_#{@block_counter}"
        @block_counter += 1
        ensure_slot(a_var, :i64)
        instructions << store_instruction(a_var, :i64)

        instructions.concat(load_value(args.first, :i64))
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => "abs", "descriptor" => "(J)J" }
        b_var = "__gcd_b_#{@block_counter}"
        @block_counter += 1
        ensure_slot(b_var, :i64)
        instructions << store_instruction(b_var, :i64)

        loop_label = new_label("gcd_loop")
        end_label = new_label("gcd_end")

        instructions << { "op" => "label", "name" => loop_label }
        # while b != 0
        instructions << load_instruction(b_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifeq", "target" => end_label }

        # temp = b; b = a % b; a = temp
        temp_var = "__gcd_t_#{@block_counter}"
        @block_counter += 1
        ensure_slot(temp_var, :i64)
        instructions << load_instruction(b_var, :i64)
        instructions << store_instruction(temp_var, :i64)

        instructions << load_instruction(a_var, :i64)
        instructions << load_instruction(b_var, :i64)
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Math",
                          "name" => "floorMod", "descriptor" => "(JJ)J" }
        instructions << store_instruction(b_var, :i64)

        instructions << load_instruction(temp_var, :i64)
        instructions << store_instruction(a_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # Result is a
        instructions << load_instruction(a_var, :i64)
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # ========================================================================
      # Integer#times Inline Loop
      # ========================================================================

      def generate_times_inline(inst, receiver, block_def, result_var)
        instructions = []

        # Load the receiver (n) as i64 counter limit
        recv_var = extract_var_name(receiver)
        recv_type = recv_var ? (@variable_types[recv_var] || :i64) : :i64
        instructions.concat(load_value(receiver, recv_type))

        # Store limit in a temp
        limit_var = "__times_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        # Initialize counter i = 0
        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__times_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("times_loop")
        end_label = new_label("times_end")

        # Loop header: i < n ?
        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifge", "target" => end_label }

        # Inline block body
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
          end
          # Skip terminator (Return) - we continue the loop instead
        end

        # Increment counter: i = i + 1
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # times returns the receiver value
        if result_var
          ensure_slot(result_var, :i64)
          instructions << load_instruction(limit_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end

        instructions
      end

      # Integer#upto(limit) inline: n.upto(m) { |i| ... }
      def generate_upto_inline(inst, receiver, limit_arg, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        # Load start (receiver) as i64
        start_var = "__upto_start_#{@block_counter}"
        ensure_slot(start_var, :i64)
        recv_type = infer_loaded_type(receiver) || :i64
        instructions.concat(load_value(receiver, recv_type))
        instructions.concat(convert_for_store(:i64, recv_type)) if recv_type != :i64
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64

        # Load limit as i64
        limit_var = "__upto_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        limit_type = infer_loaded_type(limit_arg) || :i64
        instructions.concat(load_value(limit_arg, limit_type))
        instructions.concat(convert_for_store(:i64, limit_type)) if limit_type != :i64
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        # Counter = start
        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__upto_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("upto_loop")
        end_label = new_label("upto_end")

        # Loop condition: counter <= limit
        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "ifgt", "target" => end_label }

        # Inline block body
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each { |bi| instructions.concat(generate_instruction(bi)) }
        end

        # Increment counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # upto returns nil
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end

        instructions
      end

      # Integer#downto(limit) inline: n.downto(m) { |i| ... }
      def generate_downto_inline(inst, receiver, limit_arg, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []

        # Load start (receiver) as i64
        start_var = "__downto_start_#{@block_counter}"
        ensure_slot(start_var, :i64)
        recv_type = infer_loaded_type(receiver) || :i64
        instructions.concat(load_value(receiver, recv_type))
        instructions.concat(convert_for_store(:i64, recv_type)) if recv_type != :i64
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64

        # Load limit as i64
        limit_var = "__downto_limit_#{@block_counter}"
        ensure_slot(limit_var, :i64)
        limit_type = infer_loaded_type(limit_arg) || :i64
        instructions.concat(load_value(limit_arg, limit_type))
        instructions.concat(convert_for_store(:i64, limit_type)) if limit_type != :i64
        instructions << store_instruction(limit_var, :i64)
        @variable_types[limit_var] = :i64

        # Counter = start
        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__downto_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("downto_loop")
        end_label = new_label("downto_end")

        # Loop condition: counter >= limit
        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(limit_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => "iflt", "target" => end_label }

        # Inline block body
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each { |bi| instructions.concat(generate_instruction(bi)) }
        end

        # Decrement counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "lsub" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # downto returns nil
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end

        instructions
      end

      # ========================================================================
      # Range Inline Iteration (JVM)
      # ========================================================================

      # Check if a method call can be inlined as a Range loop
      def can_jvm_inline_range_loop?(inst)
        receiver = inst.receiver
        return false unless receiver.is_a?(HIR::RangeLit)
        # Block-less methods (min, max, sum) are allowed
        return true unless inst.block
        return inst.block.params.size >= 1
      end

      # Extract Range info: [left, right, exclusive] from a RangeLit receiver
      def get_jvm_range_info(inst)
        receiver = inst.receiver
        return nil unless receiver.is_a?(HIR::RangeLit)
        [receiver.left, receiver.right, receiver.exclusive]
      end

      # Range#each inline: (start..end).each { |i| ... }
      def generate_range_each_inline(inst, receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info

        left, right, exclusive = range_info

        # Load start value as i64
        start_var = "__range_start_#{@block_counter}"
        ensure_slot(start_var, :i64)
        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64

        # Load end value as i64
        end_var = "__range_end_#{@block_counter}"
        ensure_slot(end_var, :i64)
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        # Counter = start
        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__range_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("range_each_loop")
        end_label = new_label("range_each_end")

        # Loop condition
        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        if exclusive
          instructions << { "op" => "ifge", "target" => end_label }  # i >= end → done
        else
          instructions << { "op" => "ifgt", "target" => end_label }  # i > end → done
        end

        # Inline block body
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
          end
        end

        # Increment counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # each returns nil (null on JVM)
        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << { "op" => "astore", "var" => @variable_slots[result_var.to_s] }
          @variable_types[result_var] = :value
        end

        instructions
      end

      # Range#map inline: (start..end).map { |i| expr }
      def generate_range_map_inline(inst, receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info

        left, right, exclusive = range_info

        # Load start/end
        start_var = "__rmap_start_#{@block_counter}"
        ensure_slot(start_var, :i64)
        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64

        end_var = "__rmap_end_#{@block_counter}"
        ensure_slot(end_var, :i64)
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        # Create result KArray
        result_arr_var = "__rmap_result_#{@block_counter}"
        ensure_slot(result_arr_var, :array)
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }
        instructions << store_instruction(result_arr_var, :array)
        @variable_types[result_arr_var] = :array

        # Counter = start
        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__rmap_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rmap_loop")
        end_label = new_label("rmap_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        if exclusive
          instructions << { "op" => "ifge", "target" => end_label }
        else
          instructions << { "op" => "ifgt", "target" => end_label }
        end

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Push block result to result array
        instructions << load_instruction(result_arr_var, @variable_types[result_arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[result_arr_var] == :array
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          instructions.concat(box_primitive_if_needed(last_type, :value))
        else
          instructions << { "op" => "aconst_null" }
        end
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "push",
                          "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
        instructions << { "op" => "pop" }

        # Increment counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(result_arr_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      # Range#select inline: (start..end).select { |i| predicate }
      def generate_range_select_inline(inst, receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info

        left, right, exclusive = range_info

        # Load start/end
        start_var = "__rsel_start_#{@block_counter}"
        ensure_slot(start_var, :i64)
        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64

        end_var = "__rsel_end_#{@block_counter}"
        ensure_slot(end_var, :i64)
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        # Create result KArray
        result_arr_var = "__rsel_result_#{@block_counter}"
        ensure_slot(result_arr_var, :array)
        instructions << { "op" => "new", "type" => KARRAY_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial", "owner" => KARRAY_CLASS,
                          "name" => "<init>", "descriptor" => "()V" }
        instructions << store_instruction(result_arr_var, :array)
        @variable_types[result_arr_var] = :array

        # Counter = start
        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__rsel_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rsel_loop")
        end_label = new_label("rsel_end")
        skip_label = new_label("rsel_skip")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        if exclusive
          instructions << { "op" => "ifge", "target" => end_label }
        else
          instructions << { "op" => "ifgt", "target" => end_label }
        end

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Check truthiness of block result
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          case last_type
          when :i8
            instructions << { "op" => "ifeq", "target" => skip_label }
          when :i64
            instructions << { "op" => "lconst_0" }
            instructions << { "op" => "lcmp" }
            instructions << { "op" => "ifeq", "target" => skip_label }
          else
            instructions << { "op" => "ifnull", "target" => skip_label }
          end
        else
          instructions << { "op" => "goto", "target" => skip_label }
        end

        # Add counter value (boxed) to result array
        instructions << load_instruction(result_arr_var, @variable_types[result_arr_var] || :value)
        instructions << { "op" => "checkcast", "type" => KARRAY_CLASS } unless @variable_types[result_arr_var] == :array
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                          "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        instructions << { "op" => "invokevirtual", "owner" => KARRAY_CLASS,
                          "name" => "push",
                          "descriptor" => "(Ljava/lang/Object;)Lkonpeito/runtime/KArray;" }
        instructions << { "op" => "pop" }

        instructions << { "op" => "label", "name" => skip_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :value)
          instructions << load_instruction(result_arr_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_collection_types[result_var] = :array
        end
        instructions
      end

      # Range#reduce inline: (start..end).reduce(init) { |acc, i| expr }
      def generate_range_reduce_inline(inst, receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info

        left, right, exclusive = range_info
        args = inst.args || []

        # Load start/end
        start_var = "__rred_start_#{@block_counter}"
        ensure_slot(start_var, :i64)
        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64

        end_var = "__rred_end_#{@block_counter}"
        ensure_slot(end_var, :i64)
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        # Initialize accumulator
        acc_param = block_def.params[0]
        acc_var = acc_param ? acc_param.name.to_s : "__rred_acc_#{@block_counter}"
        if args.size > 0
          # reduce(init) — use provided initial value
          init_type = :i64
          # Try to determine init type from literal
          init_val = args.first
          if init_val.is_a?(HIR::FloatLit)
            init_type = :double
          end
          ensure_slot(acc_var, init_type)
          instructions.concat(load_value(init_val, init_type))
          instructions << store_instruction(acc_var, init_type)
          @variable_types[acc_var] = init_type
        else
          # No initial value — use first element as accumulator, start from second
          ensure_slot(acc_var, :i64)
          instructions << load_instruction(start_var, :i64)
          instructions << store_instruction(acc_var, :i64)
          @variable_types[acc_var] = :i64
          # Advance start by 1
          instructions << load_instruction(start_var, :i64)
          instructions << { "op" => "lconst_1" }
          instructions << { "op" => "ladd" }
          instructions << store_instruction(start_var, :i64)
        end

        # Counter = start
        elem_param = block_def.params[1]
        counter_var = elem_param ? elem_param.name.to_s : "__rred_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rred_loop")
        end_label = new_label("rred_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        if exclusive
          instructions << { "op" => "ifge", "target" => end_label }
        else
          instructions << { "op" => "ifgt", "target" => end_label }
        end

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |block_inst|
            instructions.concat(generate_instruction(block_inst))
            last_result_var = block_inst.result_var if block_inst.respond_to?(:result_var) && block_inst.result_var
          end
        end

        # Update accumulator with block result
        if last_result_var
          last_type = @variable_types[last_result_var] || :value
          acc_type = @variable_types[acc_var] || :value
          instructions << load_instruction(last_result_var, last_type)
          instructions.concat(convert_for_store(acc_type, last_type))
          instructions << store_instruction(acc_var, acc_type)
        end

        # Increment counter
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        # Return accumulator
        if result_var
          acc_type = @variable_types[acc_var] || :value
          ensure_slot(result_var, acc_type)
          instructions << load_instruction(acc_var, acc_type)
          instructions << store_instruction(result_var, acc_type)
          @variable_types[result_var] = acc_type
        end
        instructions
      end

      # Range#any? inline: (start..end).any? { |i| ... }
      def generate_range_any_inline(inst, receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info
        left, right, exclusive = range_info

        start_var = "__rany_start_#{@block_counter}"
        end_var = "__rany_end_#{@block_counter}"
        ensure_slot(start_var, :i64); ensure_slot(end_var, :i64)
        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__rany_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rany_loop")
        true_label = new_label("rany_true")
        end_label = new_label("rany_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => (exclusive ? "ifge" : "ifgt"), "target" => end_label }

        # Inline block body
        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |bi|
            instructions.concat(generate_instruction(bi))
            last_result_var = bi.result_var if bi.respond_to?(:result_var) && bi.result_var
          end
        end

        # Check truthiness — short-circuit on true
        if last_result_var
          instructions.concat(load_and_check_truthy(last_result_var, true_label))
        end

        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }

        # End: false (no element matched)
        instructions << { "op" => "label", "name" => end_label }
        ensure_slot(result_var, :i8) if result_var
        instructions << { "op" => "iconst", "value" => 0 }
        if result_var
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        else
          instructions << { "op" => "pop" }
        end
        done_label = new_label("rany_done")
        instructions << { "op" => "goto", "target" => done_label }

        # True: found a match
        instructions << { "op" => "label", "name" => true_label }
        instructions << { "op" => "iconst", "value" => 1 }
        if result_var
          instructions << store_instruction(result_var, :i8)
        else
          instructions << { "op" => "pop" }
        end
        instructions << { "op" => "label", "name" => done_label }
        instructions
      end

      # Range#all? inline: (start..end).all? { |i| ... }
      def generate_range_all_inline(inst, receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info
        left, right, exclusive = range_info

        start_var = "__rall_start_#{@block_counter}"
        end_var = "__rall_end_#{@block_counter}"
        ensure_slot(start_var, :i64); ensure_slot(end_var, :i64)
        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__rall_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rall_loop")
        false_label = new_label("rall_false")
        end_label = new_label("rall_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => (exclusive ? "ifge" : "ifgt"), "target" => end_label }

        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |bi|
            instructions.concat(generate_instruction(bi))
            last_result_var = bi.result_var if bi.respond_to?(:result_var) && bi.result_var
          end
        end

        # Check truthiness — short-circuit on false
        if last_result_var
          instructions.concat(load_and_check_falsy(last_result_var, false_label))
        end

        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }

        # End: true (all matched)
        instructions << { "op" => "label", "name" => end_label }
        ensure_slot(result_var, :i8) if result_var
        instructions << { "op" => "iconst", "value" => 1 }
        if result_var
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        else
          instructions << { "op" => "pop" }
        end
        done_label = new_label("rall_done")
        instructions << { "op" => "goto", "target" => done_label }

        # False: found a non-match
        instructions << { "op" => "label", "name" => false_label }
        instructions << { "op" => "iconst", "value" => 0 }
        if result_var
          instructions << store_instruction(result_var, :i8)
        else
          instructions << { "op" => "pop" }
        end
        instructions << { "op" => "label", "name" => done_label }
        instructions
      end

      # Range#none? inline: (start..end).none? { |i| ... }
      def generate_range_none_inline(inst, receiver, block_def, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info
        left, right, exclusive = range_info

        start_var = "__rnone_start_#{@block_counter}"
        end_var = "__rnone_end_#{@block_counter}"
        ensure_slot(start_var, :i64); ensure_slot(end_var, :i64)
        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        block_param = block_def.params.first
        counter_var = block_param ? block_param.name.to_s : "__rnone_i_#{@block_counter}"
        ensure_slot(counter_var, :i64)
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rnone_loop")
        false_label = new_label("rnone_false")
        end_label = new_label("rnone_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => (exclusive ? "ifge" : "ifgt"), "target" => end_label }

        last_result_var = nil
        block_def.body.each do |bb|
          @current_block_label = bb.label.to_s
          bb.instructions.each do |bi|
            instructions.concat(generate_instruction(bi))
            last_result_var = bi.result_var if bi.respond_to?(:result_var) && bi.result_var
          end
        end

        # Check truthiness — short-circuit on true (found a match → none? is false)
        if last_result_var
          instructions.concat(load_and_check_truthy(last_result_var, false_label))
        end

        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)
        instructions << { "op" => "goto", "target" => loop_label }

        # End: true (no match found)
        instructions << { "op" => "label", "name" => end_label }
        ensure_slot(result_var, :i8) if result_var
        instructions << { "op" => "iconst", "value" => 1 }
        if result_var
          instructions << store_instruction(result_var, :i8)
          @variable_types[result_var] = :i8
        else
          instructions << { "op" => "pop" }
        end
        done_label = new_label("rnone_done")
        instructions << { "op" => "goto", "target" => done_label }

        instructions << { "op" => "label", "name" => false_label }
        instructions << { "op" => "iconst", "value" => 0 }
        if result_var
          instructions << store_instruction(result_var, :i8)
        else
          instructions << { "op" => "pop" }
        end
        instructions << { "op" => "label", "name" => done_label }
        instructions
      end

      # Helper: load a result variable and jump to target if truthy
      def load_and_check_truthy(result_var, target_label)
        instructions = []
        rt = @variable_types[result_var] || :value
        if rt == :i8
          instructions << load_instruction(result_var, :i8)
          instructions << { "op" => "ifne", "target" => target_label }
        elsif rt == :i64
          instructions << load_instruction(result_var, :i64)
          instructions << { "op" => "lconst_0" }
          instructions << { "op" => "lcmp" }
          instructions << { "op" => "ifne", "target" => target_label }
        else
          instructions << load_instruction(result_var, :value)
          instructions << { "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
                            "name" => "isTruthy", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "ifne", "target" => target_label }
        end
        instructions
      end

      # Helper: load a result variable and jump to target if falsy
      def load_and_check_falsy(result_var, target_label)
        instructions = []
        rt = @variable_types[result_var] || :value
        if rt == :i8
          instructions << load_instruction(result_var, :i8)
          instructions << { "op" => "ifeq", "target" => target_label }
        elsif rt == :i64
          instructions << load_instruction(result_var, :i64)
          instructions << { "op" => "lconst_0" }
          instructions << { "op" => "lcmp" }
          instructions << { "op" => "ifeq", "target" => target_label }
        else
          instructions << load_instruction(result_var, :value)
          instructions << { "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
                            "name" => "isTruthy", "descriptor" => "(Ljava/lang/Object;)Z" }
          instructions << { "op" => "ifeq", "target" => target_label }
        end
        instructions
      end

      # Helper: emit instructions to push a boxed Boolean on the stack
      def box_boolean(value)
        if value
          { "op" => "getstatic", "owner" => "java/lang/Boolean", "name" => "TRUE",
            "descriptor" => "Ljava/lang/Boolean;" }
        else
          { "op" => "getstatic", "owner" => "java/lang/Boolean", "name" => "FALSE",
            "descriptor" => "Ljava/lang/Boolean;" }
        end
      end

      # Helper: box a variable value if it's a primitive type, leave Object as-is.
      # Returns an array of instructions (may be empty for already-boxed values).
      def box_if_needed(var_name)
        vt = @variable_types[var_name]
        case vt
        when :i64
          [{ "op" => "invokestatic", "owner" => "java/lang/Long",
             "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }]
        when :double
          [{ "op" => "invokestatic", "owner" => "java/lang/Double",
             "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }]
        when :i8
          [{ "op" => "invokestatic", "owner" => "java/lang/Boolean",
             "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }]
        else
          [] # Already Object — no boxing needed
        end
      end

      # Range#min inline (no block): (start..end).min → start
      def generate_range_min_inline(inst, receiver, result_var)
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info
        left, _right, _exclusive = range_info
        if result_var
          ensure_slot(result_var, :i64)
          instructions.concat(load_value(left, :i64))
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # Range#max inline (no block): (start..end).max → end (for inclusive)
      def generate_range_max_inline(inst, receiver, result_var)
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info
        _left, right, exclusive = range_info
        if result_var
          ensure_slot(result_var, :i64)
          instructions.concat(load_value(right, :i64))
          if exclusive
            # exclusive range: max = end - 1
            instructions << { "op" => "lconst_1" }
            instructions << { "op" => "lsub" }
          end
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # Range#sum inline (no block): (start..end).sum → arithmetic sum
      def generate_range_sum_inline(inst, receiver, result_var)
        @block_counter = (@block_counter || 0) + 1
        instructions = []
        range_info = get_jvm_range_info(inst)
        return generate_static_call(inst, inst.method_name.to_s, inst.args || [], result_var) unless range_info
        left, right, exclusive = range_info

        start_var = "__rsum_start_#{@block_counter}"
        end_var = "__rsum_end_#{@block_counter}"
        sum_var = "__rsum_acc_#{@block_counter}"
        counter_var = "__rsum_i_#{@block_counter}"

        ensure_slot(start_var, :i64); ensure_slot(end_var, :i64)
        ensure_slot(sum_var, :i64); ensure_slot(counter_var, :i64)

        instructions.concat(load_value(left, :i64))
        instructions << store_instruction(start_var, :i64)
        @variable_types[start_var] = :i64
        instructions.concat(load_value(right, :i64))
        instructions << store_instruction(end_var, :i64)
        @variable_types[end_var] = :i64

        # sum = 0
        instructions << { "op" => "lconst_0" }
        instructions << store_instruction(sum_var, :i64)
        @variable_types[sum_var] = :i64

        # counter = start
        instructions << load_instruction(start_var, :i64)
        instructions << store_instruction(counter_var, :i64)
        @variable_types[counter_var] = :i64

        loop_label = new_label("rsum_loop")
        end_label = new_label("rsum_end")

        instructions << { "op" => "label", "name" => loop_label }
        instructions << load_instruction(counter_var, :i64)
        instructions << load_instruction(end_var, :i64)
        instructions << { "op" => "lcmp" }
        instructions << { "op" => (exclusive ? "ifge" : "ifgt"), "target" => end_label }

        # sum += counter
        instructions << load_instruction(sum_var, :i64)
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "ladd" }
        instructions << store_instruction(sum_var, :i64)

        # counter++
        instructions << load_instruction(counter_var, :i64)
        instructions << { "op" => "lconst_1" }
        instructions << { "op" => "ladd" }
        instructions << store_instruction(counter_var, :i64)

        instructions << { "op" => "goto", "target" => loop_label }
        instructions << { "op" => "label", "name" => end_label }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << load_instruction(sum_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # ========================================================================
      # Shared Function Body Generation
      # ========================================================================

      def prescan_phi_nodes(func)
        # Pre-scan: identify variables that are assigned different types on different
        # paths (e.g., x = nil; x ||= 42 or x = false; x ||= 42).
        # These variables must be stored as :value (Object) on the JVM.
        @_nil_assigned_vars = Set.new
        var_assigned_types = Hash.new { |h, k| h[k] = Set.new }
        # Track variables stored inside exception handlers (rescue/ensure) — these need :value
        # because JVM verifier requires type consistency across normal and exception code paths.
        exception_block_vars = Set.new

        func.body.each do |bb|
          # Collect non_try_instruction_ids from all BeginRescue in this BB.
          # These are instruction object_ids of instructions that belong to rescue/ensure/else
          # bodies but are extracted into the main BB by the HIR builder.
          non_try_ids = Set.new
          bb.instructions.each do |inst|
            if inst.is_a?(HIR::BeginRescue) && inst.non_try_instruction_ids
              non_try_ids.merge(inst.non_try_instruction_ids)
            end
          end

          bb.instructions.each do |inst|
            next unless inst.is_a?(HIR::StoreLocal)
            target = inst.var.is_a?(HIR::LocalVar) ? inst.var.name.to_s : inst.var.to_s
            val = inst.value
            tag = if val.is_a?(HIR::NilLit)
                    :nil
                  elsif val.is_a?(HIR::BoolLit)
                    :i8
                  elsif val.is_a?(HIR::IntegerLit)
                    :i64
                  elsif val.is_a?(HIR::FloatLit)
                    :double
                  elsif val.is_a?(HIR::StringLit)
                    :string
                  else
                    # For non-literal values (LoadLocal, Call results, etc.),
                    # try to infer type from HM type annotation to avoid
                    # falsely flagging variables as mixed-type.
                    inferred_tag = nil
                    if val.is_a?(HIR::LoadLocal) || val.is_a?(HIR::LocalVar) || val.is_a?(HIR::Param)
                      src = if val.is_a?(HIR::LoadLocal)
                              val.var.is_a?(HIR::LocalVar) ? val.var.name.to_s : val.var.to_s
                            else
                              val.respond_to?(:name) ? val.name.to_s : val.to_s
                            end
                      src_tags = var_assigned_types[src]
                      if src_tags && src_tags.size == 1 && !src_tags.include?(:other)
                        inferred_tag = src_tags.first
                      end
                    end
                    if inferred_tag.nil? && val.respond_to?(:type) && val.type
                      t = konpeito_type_to_tag(val.type)
                      inferred_tag = t unless t == :value
                    end
                    inferred_tag || :other
                  end
            var_assigned_types[target] << tag
            # If this StoreLocal is owned by a BeginRescue (in rescue/ensure/else body),
            # mark it as an exception block variable
            exception_block_vars << target if non_try_ids.include?(inst.object_id)
          end
        end
        # Variables stored in exception blocks need :value for JVM verifier compatibility
        exception_block_vars.each { |v| @_nil_assigned_vars << v }
        # Mark variables with mixed-type assignments (nil + primitive, or different primitives)
        var_assigned_types.each do |var_name, tags|
          if tags.include?(:nil) || tags.size > 1
            # Multiple types or nil assignment — variable needs :value on JVM
            @_nil_assigned_vars << var_name if tags.size > 1 || tags.include?(:nil)
          end
        end

        @block_phi_nodes = {}
        func.body.each do |bb|
          phis = bb.instructions.select { |inst| inst.is_a?(HIR::Phi) }
          unless phis.empty?
            @block_phi_nodes[bb.label.to_s] = phis
            phis.each do |phi|
              type = infer_phi_type(phi)
              ensure_slot(phi.result_var, type)
              @variable_types[phi.result_var] = type
            end
          end
        end
      end

      def generate_function_body(func)
        @current_block_label = nil

        # Record which slots are parameters (should not be pre-initialized)
        param_slots = Set.new
        @variable_slots.each { |_name, slot| param_slots << slot }

        # Generate body instructions (this allocates slots for all locals)
        body_instructions = []
        ordered_blocks = reorder_blocks_for_jvm(func.body)
        ordered_blocks.each do |basic_block|
          @current_block_label = basic_block.label.to_s
          body_instructions.concat(generate_basic_block(basic_block))
        end

        # Pre-initialize ALL non-parameter local variable slots with default values.
        # JVM verifier requires all locals to be definitely assigned on ALL
        # control flow paths that reach a read. Complex control flow (||, &&,
        # nested if, short-circuit) can leave variables uninitialized on some paths.
        init_instructions = []
        @variable_slots.each do |name, slot|
          next if param_slots.include?(slot)
          type = @variable_types[name] || :value
          case type
          when :i64
            init_instructions << { "op" => "lconst_0" }
            init_instructions << { "op" => "lstore", "var" => slot }
          when :double
            init_instructions << { "op" => "dconst_0" }
            init_instructions << { "op" => "dstore", "var" => slot }
          when :i8
            init_instructions << { "op" => "iconst", "value" => 0 }
            init_instructions << { "op" => "istore", "var" => slot }
          else
            init_instructions << { "op" => "aconst_null" }
            init_instructions << { "op" => "astore", "var" => slot }
          end
        end

        init_instructions.concat(body_instructions)
        init_instructions
      end

      # Reorder basic blocks for correct JVM fall-through semantics.
      # HIR blocks are created in declaration order (then/else/merge created before
      # nested blocks). This means merge blocks (which have no terminator) can appear
      # in the middle of the list, causing wrong fall-through to unrelated blocks.
      # Fix: move unterminated blocks (except the entry block) to the end so they
      # fall through to the return code.
      def reorder_blocks_for_jvm(blocks)
        return blocks if blocks.size <= 1

        result = [blocks.first]
        unterminated = []

        blocks[1..].each do |bb|
          if bb.terminator
            result << bb
          else
            unterminated << bb
          end
        end

        result.concat(unterminated)
        result
      end

      # ========================================================================
      # Helpers
      # ========================================================================

      def reset_function_state(func)
        @variable_slots = {}
        @variable_types = {}
        @variable_class_types = {}
        @variable_is_class_ref = {}
        @variable_collection_types = {}  # Track :array or :hash for collection variables
        @ivar_collection_types = {}  # Track collection types for ivars within current method
        @variable_concurrency_types = {}  # Track :thread, :mutex, :cv, :sized_queue, :ractor, :ractor_port
        @variable_native_array_element_type = {}  # Track :i64, :double for primitive arrays
        @variable_array_element_types = {}  # Track element type tag for Array[T] (e.g., :string, :i64, :double)
        @variable_is_symbol = {}  # Track variables that hold symbol values (for inspect)
        @next_slot = 0
        @label_counter = 0
        @block_phi_nodes = {}
        @current_block_label = nil
        @pending_exception_table = []  # Exception table entries for current function

        # Pre-populate parameter types from HIR (no fallback counting here —
        # actual counting happens in generate_function/generate_*_method)
        func.params.each_with_index do |param, i|
          @variable_types[param.name.to_s] = param.type ? konpeito_type_to_tag(param.type) : :value
          # Detect Array/Hash collection types from HM inference
          collection = infer_collection_type_from_hir_type(param.type)
          # Fallback: check RBS parameter types if HM inference returned Untyped
          if collection.nil? && @rbs_loader && func.owner_class
            collection = resolve_rbs_param_collection_type(func.owner_class.to_s, func.name.to_s, i)
          end
          @variable_collection_types[param.name.to_s] = collection if collection
        end
      end

      # Scan a function for shared mutable captures: variables captured by blocks
      # AND modified inside those blocks OR in the outer scope (for lambdas/procs).
      # These need static field storage for sharing.
      def scan_shared_mutable_captures(func)
        mutable_capture_names = Set.new

        # Collect all variables stored in the outer function body (for lambda/proc capture-by-reference)
        outer_stored_vars = Set.new
        func.body.each do |bb|
          bb.instructions.each do |inst|
            if inst.is_a?(HIR::StoreLocal)
              var_name = inst.var.is_a?(HIR::LocalVar) ? inst.var.name.to_s : inst.var.to_s
              outer_stored_vars.add(var_name)
            end
          end
        end

        func.body.each do |bb|
          bb.instructions.each do |inst|
            block_def = extract_block_def_from_inst(inst)
            next unless block_def

            captured_names = Set.new((block_def.captures || []).map { |c| c.name.to_s })
            next if captured_names.empty?

            # For lambdas/procs (ProcNew), the captured variable may be modified in the
            # outer scope after lambda creation. In Ruby, lambdas capture by reference,
            # so mutations to outer variables must be visible when the lambda is called.
            if inst.is_a?(HIR::ProcNew)
              captured_names.each do |var_name|
                mutable_capture_names.add(var_name) if outer_stored_vars.include?(var_name)
              end
            end

            # Also check for stores inside the block body (for regular block captures)
            # Recursively scan nested blocks too (e.g., Thread.new { mutex.synchronize { counter = counter + 1 } })
            scan_block_stores(block_def, captured_names, mutable_capture_names)
          end
        end

        mutable_capture_names
      end

      # Recursively scan block body (and nested blocks) for StoreLocal to captured variables
      def scan_block_stores(block_def, captured_names, mutable_capture_names)
        block_def.body.each do |block_bb|
          block_bb.instructions.each do |block_inst|
            if block_inst.is_a?(HIR::StoreLocal)
              var_name = block_inst.var.is_a?(HIR::LocalVar) ? block_inst.var.name.to_s : block_inst.var.to_s
              mutable_capture_names.add(var_name) if captured_names.include?(var_name)
            end
            # Recurse into nested blocks
            nested_block = extract_block_def_from_inst(block_inst)
            if nested_block
              scan_block_stores(nested_block, captured_names, mutable_capture_names)
            end
          end
        end
      end

      def extract_block_def_from_inst(inst)
        if inst.respond_to?(:block) && inst.block
          inst.block
        elsif inst.respond_to?(:block_def) && inst.block_def
          inst.block_def
        else
          nil
        end
      end

      # ---- Class/Method Lookup Helpers ----

      def user_class_jvm_name(class_name)
        "#{JAVA_PACKAGE}/#{sanitize_name(class_name)}"
      end

      def sanitize_field_name(name)
        name.to_s.sub(/^@/, "").gsub(/[^a-zA-Z0-9_]/, "_")
      end

      def find_class_instance_method(class_name, method_name)
        # Prefer is_instance_method flag (set by HIR builder for def self.xxx)
        # Fall back to singleton_methods list for compatibility
        class_def = @hir_program.classes.find { |cd| cd.name.to_s == class_name.to_s }
        singleton_methods = class_def ? (class_def.singleton_methods || []).map(&:to_s) : []
        instance_method_names = class_def ? (class_def.method_names || []).map(&:to_s) : []

        # Use reverse_each to find the LAST definition (handles method redefinition)
        @hir_program.functions.reverse_each.find { |f|
          f.owner_class.to_s == class_name.to_s &&
          f.name.to_s == method_name.to_s &&
          f.is_instance_method &&
          # Exclude singleton-only methods (not in method_names)
          (!singleton_methods.include?(f.name.to_s) || instance_method_names.include?(f.name.to_s))
        }
      end

      def find_class_singleton_method(class_name, method_name)
        # Use ClassDef.singleton_methods as source of truth (HIR builder may set is_instance_method=true
        # for all methods in a class body, even def self.xxx)
        class_def = @hir_program.classes.find { |cd| cd.name.to_s == class_name.to_s }
        return nil unless class_def
        return nil unless (class_def.singleton_methods || []).any? { |m| m.to_s == method_name.to_s }

        @hir_program.functions.find { |f|
          f.owner_class.to_s == class_name.to_s &&
          f.name.to_s == method_name.to_s
        }
      end

      def find_inherited_method(class_name, method_name)
        parent = find_parent_class_name(class_name)
        while parent
          func = find_class_instance_method(parent, method_name)
          return func if func
          parent = find_parent_class_name(parent)
        end
        nil
      end

      def find_parent_class_name(class_name)
        class_def = @hir_program.classes.find { |cd| cd.name.to_s == class_name.to_s }
        return nil unless class_def&.superclass
        class_def.superclass.to_s
      end

      # Given multiple classes that define the same method, find the topmost ancestor
      # among them. Returns the ancestor if all classes share one, nil if disjoint.
      def find_topmost_defining_class(class_names)
        return class_names.first if class_names.size == 1

        # For each class, check if it's an ancestor of all others
        class_names.each do |candidate|
          if class_names.all? { |cn| cn == candidate || is_ancestor_of?(candidate, cn) }
            return candidate
          end
        end

        nil # Disjoint hierarchies — can't resolve
      end

      # Check if `ancestor` is a parent/grandparent of `descendant`
      def is_ancestor_of?(ancestor, descendant)
        current = find_parent_class_name(descendant)
        while current
          return true if current == ancestor
          current = find_parent_class_name(current)
        end
        false
      end

      # Find a JVM interop class that defines the given instance method
      def find_jvm_interop_class_for_method(method_name)
        method_str = method_name.to_s
        @class_info.each do |cls_name, info|
          next unless info[:jvm_interop]
          methods = info[:jvm_methods]
          next unless methods
          # Check both exact and snake_case/camelCase variants
          if methods.key?(method_str) || methods.key?(snake_to_camel(method_str))
            return cls_name
          end
        end
        nil
      end

      # Generate a JVM instance method call on a classpath-introspected class
      def generate_jvm_instance_call_fallback(inst, method_name, receiver, args, result_var, jvm_class_name)
        info = @class_info[jvm_class_name]
        return [] unless info && info[:jvm_methods]

        jvm_class = info[:jvm_name]
        method_str = method_name.to_s
        jvm_method_name = method_str
        method_info = info[:jvm_methods][method_str]
        unless method_info
          camel = snake_to_camel(method_str)
          method_info = info[:jvm_methods][camel]
          jvm_method_name = camel if method_info
        end
        return [] unless method_info

        # Use java_name if available (introspected methods store the original Java name)
        jvm_method_name = method_info[:java_name] if method_info[:java_name]

        # Build descriptor from method_info's :params and :return (introspected format)
        # or use :descriptor if already present (RBS format)
        descriptor = method_info[:descriptor]
        unless descriptor
          param_types = method_info[:params] || []
          ret_type = method_info[:return] || :void
          params_desc = param_types.map { |t| jvm_interop_descriptor(t) }.join
          ret_desc = ret_type == :void ? "V" : jvm_interop_descriptor(ret_type)
          descriptor = "(#{params_desc})#{ret_desc}"
        end

        instructions = []

        # Load receiver and checkcast
        instructions += load_value(receiver, expected_type: :value)
        instructions << { "op" => "checkcast", "type" => jvm_class }

        # Load arguments based on method_info param types
        m_param_types = method_info[:params] || parse_descriptor_param_types(descriptor)
        args.each_with_index do |arg, i|
          expected = m_param_types[i] || :value
          instructions += load_value(arg, expected_type: expected)
        end

        # Invoke
        instructions << {
          "op" => "invokevirtual",
          "owner" => jvm_class,
          "name" => jvm_method_name,
          "descriptor" => descriptor
        }

        # Handle return value
        ret_type = method_info[:return] || parse_descriptor_return_type(descriptor)
        if result_var
          if ret_type == :void
            instructions << { "op" => "aconst_null" }
            instructions << store_instruction(result_var, :value)
          else
            instructions << store_instruction(result_var, ret_type)
            @variable_types[result_var] = ret_type
          end
        elsif ret_type != :void
          # Discard return value
          instructions << { "op" => (ret_type == :i64 || ret_type == :double) ? "pop2" : "pop" }
        end

        instructions
      end

      def has_class_instance_method?(method_name)
        return false unless @current_class_name
        # Check class methods
        return true if find_class_instance_method(@current_class_name, method_name)
        # Check inherited methods from parent classes
        return true if find_inherited_method(@current_class_name, method_name)
        # Also check module methods (for self.method() within module default methods)
        return true if @module_info.key?(@current_class_name) &&
                       find_module_instance_method(@current_class_name, method_name)
        false
      end

      def receiver_is_class?(receiver)
        return false unless receiver
        if receiver.is_a?(HIR::ConstantLookup)
          return @class_info.key?(receiver.name.to_s)
        end
        # Check if the variable holds a class reference (not an instance)
        var_name = extract_var_name(receiver)
        if var_name && @variable_is_class_ref[var_name]
          return @class_info.key?(@variable_class_types[var_name])
        end
        false
      end

      # Check if receiver is a module reference (for singleton method calls)
      def receiver_is_module?(receiver)
        return false unless receiver
        if receiver.is_a?(HIR::ConstantLookup)
          return @module_info.key?(receiver.name.to_s)
        end
        # Check if the variable holds a module reference (not an instance)
        var_name = extract_var_name(receiver)
        if var_name && @variable_is_class_ref[var_name]
          return @module_info.key?(@variable_class_types[var_name])
        end
        false
      end

      def extract_class_name(receiver)
        if receiver.is_a?(HIR::ConstantLookup)
          receiver.name.to_s
        else
          var_name = extract_var_name(receiver)
          var_name ? @variable_class_types[var_name] : nil
        end
      end

      def is_user_class_receiver?(receiver)
        recv_class = resolve_receiver_class(receiver)
        recv_class && @class_info.key?(recv_class)
      end

      # Search all user-defined classes for a method by name.
      # Filters by arity when given, and prefers classes related to the current class hierarchy.
      # Also searches JVM interop classes as fallback.
      def find_class_with_method(method_name, arity: nil)
        candidates = []
        @class_info.each do |class_name, info|
          next if info[:jvm_interop]
          func = find_class_instance_method(class_name, method_name)
          next unless func
          # Filter by arity when given (exclude rest/keyword_rest/block params from count)
          if arity
            func_arity = func.params.count { |p| !p.rest && !p.keyword_rest && !p.block }
            next unless func_arity == arity
          end
          candidates << class_name
        end

        unless candidates.empty?
          return candidates.first if candidates.size == 1

          # Multiple candidates: disambiguate
          # 1. Prefer classes in the current class's inheritance chain
          if @current_class_name
            in_hierarchy = candidates.select { |c| is_ancestor_of?(c, @current_class_name) || is_ancestor_of?(@current_class_name, c) || c == @current_class_name }
            candidates = in_hierarchy unless in_hierarchy.empty?
          end

          return candidates.first if candidates.size == 1

          # 2. Among remaining candidates, prefer the most base class (for widest invokevirtual compatibility)
          best_class = candidates.first
          candidates[1..].each do |c|
            best_class = c if is_ancestor_of?(c, best_class)
          end
          return best_class if best_class
        end

        # Fallback: search JVM interop classes
        @class_info.each do |class_name, info|
          next unless info[:jvm_interop]
          methods = info[:jvm_methods] || {}
          if methods.key?(method_name.to_s) || methods.key?(method_name.to_sym)
            return class_name
          end
          # Also check snake_to_camel conversion
          camel = snake_to_camel(method_name.to_s)
          if methods.key?(camel) || methods.key?(camel.to_sym)
            return class_name
          end
        end

        nil
      end

      # Return ALL user classes that have a method with the given name and arity.
      def find_all_classes_with_method(method_name, arity: nil)
        candidates = []
        @class_info.each do |class_name, info|
          next if info[:jvm_interop]
          func = find_class_instance_method(class_name, method_name)
          next unless func
          if arity
            func_arity = func.params.count { |p| !p.rest && !p.keyword_rest && !p.block }
            next unless func_arity == arity
          end
          candidates << class_name
        end
        candidates
      end

      # Convert snake_case to camelCase (e.g., "set_background" -> "setBackground")
      def snake_to_camel(name)
        parts = name.split("_")
        parts[0] + parts[1..].map(&:capitalize).join
      end

      # Check if potential_ancestor is an ancestor of class_name
      def is_ancestor_of?(potential_ancestor, class_name)
        current = class_name
        while current
          return true if current == potential_ancestor
          class_def = @hir_program.classes.find { |cd| cd.name.to_s == current }
          break unless class_def && class_def.superclass
          current = class_def.superclass.to_s
        end
        false
      end

      def resolve_receiver_class(receiver)
        var_name = extract_var_name(receiver)
        if var_name && @variable_class_types[var_name]
          cls = @variable_class_types[var_name]
          return cls if @class_info.key?(cls)
        end

        # NOTE: Do NOT fall back to HIR type (HM inference) here.
        # HM inference can be wrong without RBS, leading to incorrect checkcast
        # and ClassCastException at runtime. Only use @variable_class_types which
        # are set from definitive sources (constructor calls, self refs, field loads).
        # Unresolved receiver types will fall through to invokedynamic for safe dispatch.

        nil
      end

      # Resolve RBS-declared parameter types for a method.
      # Returns an array of JVM type tags, or nil if not available.
      def resolve_rbs_param_types(class_name, method_name, is_singleton)
        return nil unless @rbs_loader

        begin
          method_types = @rbs_loader.method_type(class_name, method_name, singleton: is_singleton)
          return nil unless method_types

          mt = method_types.is_a?(Array) ? method_types.first : method_types
          return nil unless mt

          if mt.respond_to?(:type) && mt.type.respond_to?(:each_param)
            mt.type.each_param.map do |param|
              rbs_type_to_jvm_tag(param.type)
            end
          elsif mt.respond_to?(:type) && mt.type.respond_to?(:required_positionals)
            rp = mt.type.required_positionals || []
            op = mt.type.optional_positionals || []
            (rp + op).map { |p| rbs_type_to_jvm_tag(p.type) }
          end
        rescue
          nil
        end
      end

      def resolve_rbs_return_type(class_name, method_name, is_singleton)
        return nil unless @rbs_loader

        begin
          method_types = @rbs_loader.method_type(class_name, method_name, singleton: is_singleton)
          return nil unless method_types

          mt = method_types.is_a?(Array) ? method_types.first : method_types
          return nil unless mt

          if mt.respond_to?(:type) && mt.type.respond_to?(:return_type)
            rbs_type_to_jvm_tag(mt.type.return_type)
          end
        rescue
          nil
        end
      end

      # Resolve the class name of a method's return type from RBS
      # Returns the short class name (e.g., "Vector2") if the return type is a class, nil otherwise
      def resolve_rbs_return_class_name(class_name, method_name, is_singleton = false)
        return nil unless @rbs_loader

        begin
          method_types = @rbs_loader.method_type(class_name, method_name, singleton: is_singleton)
          return nil unless method_types

          mt = method_types.is_a?(Array) ? method_types.first : method_types
          return nil unless mt&.respond_to?(:type) && mt.type.respond_to?(:return_type)

          rbs_type = mt.type.return_type
          if rbs_type.respond_to?(:name) && rbs_type.name.respond_to?(:name)
            rbs_type.name.name.to_s
          end
        rescue
          nil
        end
      end

      # Convert RBS type to JVM type tag
      def rbs_type_to_jvm_tag(rbs_type)
        return :value unless rbs_type

        type_name = if rbs_type.respond_to?(:name) && rbs_type.name.respond_to?(:to_s)
                       rbs_type.name.to_s
                     elsif rbs_type.respond_to?(:to_s)
                       rbs_type.to_s
                     else
                       ""
                     end

        case type_name
        when /\bInteger\b/ then :i64
        when /\bFloat\b/ then :double
        when /\bbool\b/i then :i8
        when /\bvoid\b/i then :void
        when /\bString\b/ then :string
        else :value
        end
      end

      # Convert a Prism default value node to JVM bytecode instructions.
      # Used when optional parameters are missing at a call site.
      def prism_default_to_jvm(prism_node, expected_type)
        case prism_node
        when Prism::IntegerNode
          val = prism_node.value
          insts = if val == 0
            [{ "op" => "lconst_0" }]
          elsif val == 1
            [{ "op" => "lconst_1" }]
          else
            [{ "op" => "ldc2_w", "value" => val, "type" => "long" }]
          end
          if expected_type == :value
            insts << { "op" => "invokestatic", "owner" => "java/lang/Long",
                       "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          end
          insts
        when Prism::FloatNode
          val = prism_node.value
          insts = if val == 0.0
            [{ "op" => "dconst_0" }]
          elsif val == 1.0
            [{ "op" => "dconst_1" }]
          else
            [{ "op" => "ldc2_w", "value" => val, "type" => "double" }]
          end
          if expected_type == :value
            insts << { "op" => "invokestatic", "owner" => "java/lang/Double",
                       "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          end
          insts
        when Prism::StringNode
          [{ "op" => "ldc", "value" => prism_node.unescaped }]
        when Prism::SymbolNode
          [{ "op" => "ldc", "value" => prism_node.value }]
        when Prism::NilNode
          [{ "op" => "aconst_null" }]
        when Prism::TrueNode
          insts = [{ "op" => "iconst", "value" => 1 }]
          if expected_type == :value
            insts << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                       "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
          end
          insts
        when Prism::FalseNode
          insts = [{ "op" => "iconst", "value" => 0 }]
          if expected_type == :value
            insts << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                       "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
          end
          insts
        else
          default_value_instructions(expected_type)
        end
      end

      def default_value_instructions(type)
        case type
        when :i64 then [{ "op" => "lconst_0" }]
        when :double then [{ "op" => "dconst_0" }]
        when :i8 then [{ "op" => "iconst", "value" => 0 }]
        else [{ "op" => "aconst_null" }]
        end
      end

      # Box a primitive value on the stack when the expected type is :value (Object)
      def box_primitive_if_needed(actual_type, expected_type)
        return [] unless expected_type == :value
        case actual_type
        when :i64
          [{ "op" => "invokestatic", "owner" => "java/lang/Long",
             "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }]
        when :double
          [{ "op" => "invokestatic", "owner" => "java/lang/Double",
             "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }]
        when :i8
          # boolean → Boolean
          [{ "op" => "invokestatic", "owner" => "java/lang/Boolean",
             "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }]
        else
          []
        end
      end

      # Unbox Object to primitive when the variable holds Object but the call site expects a primitive
      def unbox_if_needed(actual_type, expected_type)
        return [] unless actual_type == :value
        case expected_type
        when :i64
          # Null-safe unboxing via RubyDispatch helper
          [{ "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
             "name" => "unboxLong", "descriptor" => "(Ljava/lang/Object;)J" }]
        when :double
          [{ "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
             "name" => "unboxDouble", "descriptor" => "(Ljava/lang/Object;)D" }]
        when :i8
          [{ "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
             "name" => "unboxBoolean", "descriptor" => "(Ljava/lang/Object;)Z" }]
        when :string
          [{ "op" => "checkcast", "type" => "java/lang/String" }]
        when :array
          [{ "op" => "checkcast", "type" => "konpeito/runtime/KArray" }]
        when :hash
          [{ "op" => "checkcast", "type" => "konpeito/runtime/KHash" }]
        else
          # User class: checkcast to narrow Object → specific class
          expected_s = expected_type.to_s
          if expected_s.start_with?("class:")
            class_name = expected_s.sub("class:", "")
            [{ "op" => "checkcast", "type" => user_class_jvm_name(class_name) }]
          else
            []
          end
        end
      end

      # Insert store instructions for Phi nodes when jumping to a target block
      def generate_phi_stores(target_label)
        instructions = []
        phis = @block_phi_nodes[target_label]
        return instructions unless phis

        phis.each do |phi|
          # Find the incoming value for the current block
          incoming_val = phi.incoming[@current_block_label] ||
                         phi.incoming[@current_block_label&.to_sym]

          # Try matching by label object
          unless incoming_val
            phi.incoming.each do |block_ref, val|
              if block_ref.to_s == @current_block_label
                incoming_val = val
                break
              end
            end
          end

          next unless incoming_val

          phi_type = @variable_types[phi.result_var] || :value

          # Check if incoming value type matches phi type;
          # if incoming is null/Object but phi expects primitive, provide default.
          incoming_var = extract_var_name(incoming_val)
          incoming_type = incoming_var ? (@variable_types[incoming_var] || :value) : nil
          incoming_type ||= infer_type_from_hir(incoming_val) || :value

          if phi_type == :i64 && incoming_type == :value
            # Incoming is Object/null but phi expects long — use 0L as default
            if incoming_val.is_a?(HIR::NilLit)
              instructions << { "op" => "lconst_0" }
            else
              # Null-safe unbox via RubyDispatch.unboxLong
              instructions.concat(load_value(incoming_val, :value))
              instructions << { "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
                               "name" => "unboxLong", "descriptor" => "(Ljava/lang/Object;)J" }
            end
            instructions << store_instruction(phi.result_var, :i64)
          elsif phi_type == :double && incoming_type == :value
            if incoming_val.is_a?(HIR::NilLit)
              instructions << { "op" => "dconst_0" }
            else
              # Null-safe unbox via RubyDispatch.unboxDouble
              instructions.concat(load_value(incoming_val, :value))
              instructions << { "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
                               "name" => "unboxDouble", "descriptor" => "(Ljava/lang/Object;)D" }
            end
            instructions << store_instruction(phi.result_var, :double)
          elsif phi_type == :i8 && incoming_type == :value
            # Null-safe unbox via RubyDispatch.unboxBoolean
            instructions.concat(load_value(incoming_val, :value))
            instructions << { "op" => "invokestatic", "owner" => "konpeito/runtime/RubyDispatch",
                             "name" => "unboxBoolean", "descriptor" => "(Ljava/lang/Object;)Z" }
            instructions << store_instruction(phi.result_var, :i8)
          elsif phi_type == :value && (incoming_type == :i64 || incoming_type == :double || incoming_type == :i8)
            # Incoming is primitive but phi expects Object — box it
            instructions.concat(load_value(incoming_val, incoming_type))
            instructions.concat(box_primitive_if_needed(incoming_type, :value))
            instructions << store_instruction(phi.result_var, :value)
          elsif phi_type == :double && incoming_type == :i64
            # Incoming is long but phi expects double — convert
            instructions.concat(load_value(incoming_val, :i64))
            instructions << { "op" => "l2d" }
            instructions << store_instruction(phi.result_var, :double)
          elsif phi_type == :i64 && incoming_type == :double
            # Incoming is double but phi expects long — convert
            instructions.concat(load_value(incoming_val, :double))
            instructions << { "op" => "d2l" }
            instructions << store_instruction(phi.result_var, :i64)
          else
            # Load the incoming value and store to the Phi's slot
            instructions.concat(load_value(incoming_val, phi_type))
            instructions << store_instruction(phi.result_var, phi_type)
          end
        end

        instructions
      end

      # Determine the type of a Phi node from its incoming values
      def infer_phi_type(phi)
        incoming_types = phi.incoming.values.map do |val|
          var = extract_var_name(val)
          type = var ? @variable_types[var] : nil
          type || infer_type_from_hir(val) || literal_type_tag(val) || :value
        end

        # Check if any incoming value is a LoadLocal of a variable that has nil
        # assignments. In such cases, the JVM variable will be stored as :value
        # (Object), not as a primitive, so the phi must also be :value.
        has_nil_source = phi.incoming.values.any? do |val|
          if val.is_a?(HIR::LoadLocal) && val.var.respond_to?(:name)
            var_name = val.var.name.to_s
            @_nil_assigned_vars&.include?(var_name)
          else
            false
          end
        end
        return :value if has_nil_source

        if incoming_types.all? { |t| t == :i8 }
          :i8
        elsif incoming_types.all? { |t| t == :i64 }
          :i64
        elsif incoming_types.all? { |t| t == :double }
          :double
        elsif incoming_types.all? { |t| t == :i64 || t == :double }
          :double
        else
          :value
        end
      end

      def allocate_slot(name, type)
        name = name.to_s
        return @variable_slots[name] if @variable_slots.key?(name)

        slot = @next_slot
        @variable_slots[name] = slot
        @variable_types[name] = type

        # long and double take 2 slots in JVM
        @next_slot += (type == :i64 || type == :double) ? 2 : 1

        slot
      end

      def ensure_slot(name, type)
        name = name.to_s
        allocate_slot(name, type) unless @variable_slots.key?(name)
        @variable_slots[name]
      end

      # Store null into result_var so downstream code doesn't reference uninitialized vars.
      # Returns instructions array. Returns [] if result_var is nil.
      def store_null_for_result(result_var)
        return [] unless result_var
        ensure_slot(result_var, :value)
        @variable_types[result_var] = :value
        [{ "op" => "aconst_null" }, { "op" => "astore", "var" => @variable_slots[result_var.to_s] }]
      end

      def slot_for(name)
        name = name.to_s
        @variable_slots[name] || allocate_slot(name, :value)
      end

      def load_instruction(var_name, type)
        slot = slot_for(var_name)
        case type
        when :i64 then { "op" => "lload", "var" => slot }
        when :double then { "op" => "dload", "var" => slot }
        when :i8 then { "op" => "iload", "var" => slot }
        else { "op" => "aload", "var" => slot }
        end
      end

      def store_instruction(var_name, type)
        slot = slot_for(var_name)
        case type
        when :i64 then { "op" => "lstore", "var" => slot }
        when :double then { "op" => "dstore", "var" => slot }
        when :i8 then { "op" => "istore", "var" => slot }
        else { "op" => "astore", "var" => slot }
        end
      end

      def load_value(hir_value, expected_type)
        case hir_value
        when HIR::IntegerLit
          val = hir_value.value
          insts = if val == 0
            [{ "op" => "lconst_0" }]
          elsif val == 1
            [{ "op" => "lconst_1" }]
          else
            [{ "op" => "ldc2_w", "value" => val, "type" => "long" }]
          end
          # Box to Long if expected type is Object
          if expected_type == :value
            insts << { "op" => "invokestatic", "owner" => "java/lang/Long",
                       "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
          end
          insts
        when HIR::FloatLit
          val = hir_value.value
          # Use dconst_0 only for positive zero; negative zero (-0.0) needs ldc2_w
          insts = if val == 0.0 && (1.0 / val) == Float::INFINITY  # positive zero: 1.0/+0.0 = +Inf
            [{ "op" => "dconst_0" }]
          elsif val == 1.0
            [{ "op" => "dconst_1" }]
          else
            [{ "op" => "ldc2_w", "value" => val, "type" => "double" }]
          end
          # Box to Double if expected type is Object
          if expected_type == :value
            insts << { "op" => "invokestatic", "owner" => "java/lang/Double",
                       "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
          end
          insts
        when HIR::BoolLit
          insts = [{ "op" => "iconst", "value" => hir_value.value ? 1 : 0 }]
          if expected_type == :value
            insts << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                       "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
          end
          insts
        when HIR::NilLit
          [{ "op" => "aconst_null" }]
        when HIR::StringLit
          # Use new String(ldc) to avoid JVM string interning.
          # This ensures Object#equal? (identity check) returns false for different
          # string literals with the same value, matching Ruby semantics.
          [
            { "op" => "new", "type" => "java/lang/String" },
            { "op" => "dup" },
            { "op" => "ldc", "value" => hir_value.value },
            { "op" => "invokespecial", "owner" => "java/lang/String",
              "name" => "<init>", "descriptor" => "(Ljava/lang/String;)V" }
          ]
        when HIR::LocalVar, HIR::Param
          var_name = hir_value.name.to_s
          # Shared mutable capture inside block: use getstatic
          if @shared_mutable_captures&.include?(var_name) && !@variable_slots.key?(var_name)
            field_name = @shared_capture_fields[var_name]
            type = @shared_mutable_capture_types&.dig(var_name) || :value
            insts = [{ "op" => "getstatic", "owner" => main_class_name,
                       "name" => field_name, "descriptor" => "Ljava/lang/Object;" }]
            insts.concat(unbox_from_object_field(type))
            insts.concat(box_primitive_if_needed(type, expected_type))
            insts
          else
            type = @variable_types[var_name] || expected_type
            insts = [load_instruction(var_name, type)]
            insts.concat(box_primitive_if_needed(type, expected_type))
            insts
          end
        when HIR::LoadLocal
          if hir_value.result_var && @variable_slots.key?(hir_value.result_var)
            var_name = hir_value.result_var
            type = @variable_types[var_name] || expected_type
            insts = [load_instruction(var_name, type)]
            insts.concat(box_primitive_if_needed(type, expected_type))
            insts
          else
            source = hir_value.var.is_a?(HIR::LocalVar) ? hir_value.var.name.to_s : hir_value.var.to_s
            # Shared mutable capture inside block: use getstatic
            if @shared_mutable_captures&.include?(source) && !@variable_slots.key?(source)
              field_name = @shared_capture_fields[source]
              type = @shared_mutable_capture_types&.dig(source) || :value
              insts = [{ "op" => "getstatic", "owner" => main_class_name,
                         "name" => field_name, "descriptor" => "Ljava/lang/Object;" }]
              insts.concat(unbox_from_object_field(type))
              insts.concat(box_primitive_if_needed(type, expected_type))
              insts
            else
              type = @variable_types[source] || expected_type
              insts = [load_instruction(source, type)]
              insts.concat(box_primitive_if_needed(type, expected_type))
              insts
            end
          end
        else
          # For embedded HIR nodes (e.g., Call used as receiver of another Call
          # inside CaseMatchStatement bodies), generate the instruction first,
          # then load from its result variable.
          if hir_value.respond_to?(:result_var) && hir_value.result_var
            var_name = hir_value.result_var
            # If the result_var hasn't been generated yet (no slot allocated),
            # generate the instruction first
            if !@variable_slots.key?(var_name)
              insts = generate_instruction(hir_value)
              type = @variable_types[var_name] || expected_type
              insts << load_instruction(var_name, type)
              insts.concat(box_primitive_if_needed(type, expected_type))
              insts
            else
              type = @variable_types[var_name] || expected_type
              insts = [load_instruction(var_name, type)]
              insts.concat(box_primitive_if_needed(type, expected_type))
              insts
            end
          else
            [{ "op" => "aconst_null" }]
          end
        end
      end

      def extract_var_name(hir_value)
        case hir_value
        when HIR::LocalVar, HIR::Param
          hir_value.name.to_s
        when HIR::LoadLocal
          if hir_value.result_var
            hir_value.result_var
          else
            hir_value.var.is_a?(HIR::LocalVar) ? hir_value.var.name.to_s : hir_value.var.to_s
          end
        else
          hir_value.respond_to?(:result_var) ? hir_value.result_var : nil
        end
      end

      def param_type(param)
        type = param.type
        unless type
          # Only count as genuine fallback if function is NOT polymorphic (no monomorphized specializations)
          unless function_is_polymorphic?(@current_generating_func_name)
            @typevar_fallback_count += 1
          end
          return :value
        end
        tag = konpeito_type_to_tag(type)
        if tag == :value && type.is_a?(TypeChecker::TypeVar)
          # TypeVar → :value is expected for polymorphic functions (type erasure, Kotlin-style)
          # Only count as genuine fallback for non-polymorphic functions
          unless function_is_polymorphic?(@current_generating_func_name)
            @typevar_fallback_count += 1
          end
        end
        tag
      end

      # Check if a function is polymorphic (generalized with TypeVar params).
      # Polymorphic functions are expected to have TypeVar params — this is type erasure, not an error.
      # Detection: (1) monomorphizer has specializations for it, OR
      #            (2) HIR function params have unresolved TypeVars (generalized by HM inference)
      def function_is_polymorphic?(func_name)
        # Check monomorphizer specializations
        if @monomorphizer && func_name
          return true if @monomorphizer.specializations.any? { |key, _| key[0] == func_name }
          return true if @monomorphizer.specializations.any? { |_, name| name == func_name }
        end
        # Check HIR function params for TypeVars (generalized top-level functions)
        if @hir_program && func_name
          func = @hir_program.functions.find { |f| f.name.to_s == func_name }
          if func && func.params.any? { |p| p.type.is_a?(TypeChecker::TypeVar) && p.type.prune.is_a?(TypeChecker::TypeVar) }
            return true
          end
        end
        false
      end

      def function_return_type(func)
        # Try to determine return type from the Return terminator
        func.body.each do |bb|
          if bb.terminator.is_a?(HIR::Return) && bb.terminator.value
            val = bb.terminator.value

            # SelfRef → return the owning class type (builder pattern)
            # Use func.owner_class (not @current_class_name) so we return the
            # correct class when inspecting a method from a different class
            self_class = func.respond_to?(:owner_class) && func.owner_class ? func.owner_class.to_s : @current_class_name
            if val.is_a?(HIR::SelfRef) && self_class
              return :"class:#{self_class}"
            end

            val_type = val.respond_to?(:type) ? val.type : nil
            if val_type
              result = konpeito_type_to_tag(val_type)
              # Before returning a primitive type, check if the return variable
              # can be nil on some paths (e.g., x = nil; x ||= 42).
              # JVM needs Object return type in such cases.
              if result != :value && val.is_a?(HIR::LoadLocal) && val.var.respond_to?(:name)
                var_name = val.var.name.to_s
                if variable_has_nil_assignment?(func, var_name)
                  result = :value
                end
              end
              return result if result != :value
            end

            # If the return value is a LoadLocal matching a parameter, use param's type
            # (handles monomorphized generics where TypeVar isn't resolved in LoadLocal)
            if val.is_a?(HIR::LoadLocal) && val.var.respond_to?(:name)
              param = func.params.find { |p| p.name == val.var.name }
              if param
                result = param_type(param)
                return result if result != :value
              end
            end
          end
        end

        # Fallback to function's declared return type
        return_type = func.return_type
        return :value unless return_type
        konpeito_type_to_tag(return_type)
      end

      # Check if a variable has a NilLit assignment anywhere in the function.
      # Used to detect cases like `x = nil; x ||= 42` where the variable's JVM
      # type must be :value (Object) even though HM inference says Integer.
      def variable_has_nil_assignment?(func, var_name)
        func.body.each do |bb|
          bb.instructions.each do |inst|
            next unless inst.is_a?(HIR::StoreLocal)
            target = inst.var.is_a?(HIR::LocalVar) ? inst.var.name.to_s : inst.var.to_s
            next unless target == var_name
            return true if inst.value.is_a?(HIR::NilLit)
          end
        end
        false
      end

      # Check if the return type needs to be widened to :value due to phi nodes
      # or mixed-type variable assignments (e.g., x = nil; x ||= 42).
      def verify_return_type_with_phi(func, ret_type)
        # Collect return variable names
        ret_var_names = []
        func.body.each do |bb|
          next unless bb.terminator.is_a?(HIR::Return) && bb.terminator.value
          var_name = extract_var_name(bb.terminator.value)
          ret_var_names << var_name if var_name
        end
        return ret_type if ret_var_names.empty?

        # Check if phi result vars feed into the return
        phi_result_vars = {}
        @block_phi_nodes&.each_value do |phis|
          phis.each { |phi| phi_result_vars[phi.result_var] = @variable_types[phi.result_var] }
        end

        ret_var_names.each do |rv|
          # If the return var is a phi result that resolved to :value, widen
          if phi_result_vars[rv] == :value
            return :value
          end
        end

        # Also check if any return variable is assigned both nil and a primitive
        # (e.g., x = nil on one path and x = 42 on another path via ||=)
        ret_var_names.each do |rv|
          assigned_types = Set.new
          func.body.each do |bb|
            bb.instructions.each do |inst|
              next unless inst.is_a?(HIR::StoreLocal)
              target = inst.var.is_a?(HIR::LocalVar) ? inst.var.name.to_s : inst.var.to_s
              next unless target == rv
              val = inst.value
              if val.is_a?(HIR::NilLit)
                assigned_types << :nil
              elsif val.is_a?(HIR::IntegerLit)
                assigned_types << :i64
              elsif val.is_a?(HIR::FloatLit)
                assigned_types << :double
              elsif val.is_a?(HIR::BoolLit)
                assigned_types << :i8
              elsif val.is_a?(HIR::StringLit) || val.is_a?(HIR::SymbolLit)
                assigned_types << :string
              else
                assigned_types << :other
              end
            end
          end
          # If variable has nil assignment + primitive assignment, widen to :value
          if assigned_types.include?(:nil) && (assigned_types.include?(:i64) || assigned_types.include?(:double) || assigned_types.include?(:i8))
            return :value
          end
        end

        ret_type
      end

      def infer_type_from_hir(hir_value)
        return nil unless hir_value.respond_to?(:type) && hir_value.type
        tag = konpeito_type_to_tag(hir_value.type)
        tag == :value ? nil : tag
      end

      # Get type tag directly from HIR literal nodes (without relying on HM type annotation)
      def literal_type_tag(node)
        case node
        when HIR::IntegerLit then :i64
        when HIR::FloatLit then :double
        when HIR::BoolLit then :i8
        else nil
        end
      end

      # Resolve user class type from HM-inferred ivar types (walks up class hierarchy)
      def resolve_ivar_class_type(class_name, field_name)
        current = class_name
        while current
          class_def = @hir_program.classes.find { |cd| cd.name.to_s == current }
          if class_def && class_def.respond_to?(:instance_var_types) && class_def.instance_var_types
            clean = field_name.to_s.sub(/^@/, "")
            ivar_type = class_def.instance_var_types[clean] || class_def.instance_var_types["@#{clean}"]
            if ivar_type
              # Check if it's a ClassInstance pointing to a registered user class
              if ivar_type.is_a?(TypeChecker::Types::ClassInstance)
                cls_name = ivar_type.name.to_s
                return cls_name if @class_info.key?(cls_name)
              elsif ivar_type.is_a?(String) && @class_info.key?(ivar_type)
                # HIR builder converts ClassInstance to string via hm_type_to_field_tag
                return ivar_type
              end
            end
          end
          if class_def && class_def.superclass
            current = class_def.superclass.to_s
          else
            current = nil
          end
        end
        nil
      end

      def resolve_field_collection_type(class_name, field_name)
        # Walk up the class hierarchy to find the field
        current = class_name
        while current
          if @rbs_loader
            begin
              native_type = @rbs_loader.native_class_type(current)
              if native_type && native_type.respond_to?(:fields) && native_type.fields
                ftype = native_type.fields[field_name.to_s] || native_type.fields[field_name.to_sym]
                return infer_collection_type_from_hir_type(ftype) if ftype
              end
            rescue
              # RBS loader may not have this class
            end
          end
          # Fallback: check HM-inferred ivar types from class def
          class_def = @hir_program.classes.find { |cd| cd.name.to_s == current }
          if class_def && class_def.respond_to?(:instance_var_types) && class_def.instance_var_types
            clean = field_name.to_s.sub(/^@/, "")
            ivar_type = class_def.instance_var_types[clean] || class_def.instance_var_types["@#{clean}"]
            return infer_collection_type_from_hir_type(ivar_type) if ivar_type
          end
          # Move to parent class
          if class_def && class_def.superclass
            current = class_def.superclass.to_s
          else
            current = nil
          end
        end
        nil
      end

      def infer_collection_type_from_hir_type(type)
        return nil unless type
        type_str = type.to_s
        if type_str =~ /\bArray\b/
          :array
        elsif type_str =~ /\bHash\b/
          :hash
        else
          nil
        end
      end

      def resolve_rbs_param_collection_type(class_name, method_name, param_index)
        return nil unless @rbs_loader
        begin
          native_type = @rbs_loader.native_class_type(class_name)
          if native_type && native_type.respond_to?(:methods) && native_type.methods
            method_info = native_type.methods[method_name.to_s] || native_type.methods[method_name.to_sym]
            if method_info && method_info.respond_to?(:param_types) && method_info.param_types
              param_type_sym = method_info.param_types[param_index]
              return infer_collection_type_from_hir_type(param_type_sym) if param_type_sym
            end
          end
        rescue
          # RBS loader may not have this method
        end
        nil
      end

      def konpeito_type_to_tag(type)
        # Resolve TypeVars to their unified concrete types
        if type.is_a?(TypeChecker::TypeVar)
          resolved = type.prune
          return konpeito_type_to_tag(resolved) unless resolved.equal?(type)
          # TypeVar was never resolved — type erasure to Object (:value)
          # This is expected for polymorphic functions (like Kotlin generics).
          # For non-polymorphic functions, this indicates an inference gap.
          return :value
        end
        case type
        when TypeChecker::Types::INTEGER then :i64
        when TypeChecker::Types::FLOAT then :double
        when TypeChecker::Types::TRUE_CLASS, TypeChecker::Types::FALSE_CLASS then :i8
        when TypeChecker::Types::BOOL then :i8
        when TypeChecker::Types::NIL then :void
        else
          if type.is_a?(TypeChecker::Types::ClassInstance)
            case type.name
            when :Integer then :i64
            when :Float then :double
            when :String then :string
            when :Bool then :i8
            else
              # User-defined class types from HM inference — use Object (:value).
              :value
            end
          else
            :value
          end
        end
      end

      def method_descriptor(func)
        params_desc = func.params.each_with_index.map do |param, i|
          t = widened_param_type(func, param, i)
          t = :value if t == :void  # Nil/void is not valid as JVM param type
          type_to_descriptor(t)
        end.join

        ret_type = function_return_type(func)
        ret_desc = type_to_descriptor(ret_type)

        "(#{params_desc})#{ret_desc}"
      end

      # Normalize capture types for lambda/block compilation.
      # Reference types are normalized to :value (Object) to avoid VerifyError
      # when a captured variable's type changes in a loop (e.g., KArray → Object
      # after invokedynamic reassignment).
      def safe_capture_type(var_name)
        t = @variable_types[var_name] || :value
        case t
        when :i64, :double, :i8 then t
        else :value
        end
      end

      def type_to_descriptor(type)
        case type
        when :i64 then "J"
        when :double then "D"
        when :i8 then "Z"
        when :void then "V"
        when :string then "Ljava/lang/String;"
        when :array then "Lkonpeito/runtime/KArray;"
        when :hash then "Lkonpeito/runtime/KHash;"
        when :value then "Ljava/lang/Object;"
        else
          type_s = type.to_s
          if type_s.start_with?("class:")
            "L#{user_class_jvm_name(type_s.sub("class:", ""))};"
          else
            "Ljava/lang/Object;"
          end
        end
      end

      # Operator method names that are invalid as JVM identifiers
      JVM_OPERATOR_NAME_MAP = {
        "+" => "op_plus", "-" => "op_minus", "*" => "op_mul", "/" => "op_div",
        "%" => "op_mod", "**" => "op_pow", "==" => "op_eq", "!=" => "op_neq",
        "<" => "op_lt", ">" => "op_gt", "<=" => "op_le", ">=" => "op_ge",
        "<=>" => "op_cmp", "<<" => "op_lshift", ">>" => "op_rshift",
        "&" => "op_and", "|" => "op_or", "^" => "op_xor", "~" => "op_not",
        "[]" => "op_aref", "[]=" => "op_aset", "+@" => "op_uplus", "-@" => "op_uminus",
        "=~" => "op_match", "!~" => "op_nmatch",
      }.freeze

      # java.lang.Object final methods that cannot be overridden
      JVM_RESERVED_METHODS = %w[notify notifyAll wait getClass].freeze

      def jvm_method_name(name)
        # Convert Ruby method names to valid JVM names
        name = name.to_s
        # Operator names first (before gsub mangles the characters)
        return JVM_OPERATOR_NAME_MAP[name] if JVM_OPERATOR_NAME_MAP.key?(name)
        name = name.gsub("?", "_q").gsub("!", "_bang").gsub("=", "_eq")
        # Avoid reserved names (JVM keywords and java.lang.Object final methods)
        name = "k_#{name}" if %w[main class interface].include?(name)
        name = "rb_#{name}" if JVM_RESERVED_METHODS.include?(name)
        name
      end

      def arithmetic_operator?(name)
        %w[+ - * / %].include?(name)
      end

      def comparison_operator?(name)
        %w[< > <= >= == !=].include?(name)
      end

      # Scan an initialize function body for a SuperCall node
      def find_super_call_in_body(basic_blocks)
        basic_blocks.each do |bb|
          bb.instructions.each do |inst|
            return inst if inst.is_a?(HIR::SuperCall)
          end
        end
        nil
      end

      # Check if a user-defined class receiver has a specific method defined
      def user_class_has_method?(receiver, method_name)
        recv_class_name = resolve_receiver_class(receiver)
        return false unless recv_class_name
        !!find_class_instance_method(recv_class_name, method_name)
      end

      def arithmetic_instruction(op, type)
        result = case type
                 when :i64
                   case op
                   when "+" then { "op" => "ladd" }
                   when "-" then { "op" => "lsub" }
                   when "*" then { "op" => "lmul" }
                   when "/" then { "op" => "invokestatic", "owner" => "java/lang/Math",
                                    "name" => "floorDiv", "descriptor" => "(JJ)J" }
                   when "%" then { "op" => "invokestatic", "owner" => "java/lang/Math",
                                    "name" => "floorMod", "descriptor" => "(JJ)J" }
                   end
                 when :double
                   case op
                   when "+" then { "op" => "dadd" }
                   when "-" then { "op" => "dsub" }
                   when "*" then { "op" => "dmul" }
                   when "/" then { "op" => "ddiv" }
                   when "%" then { "op" => "drem" }
                   end
                 end

        unless result
          warn "JVM: unsupported arithmetic: #{op} on type #{type}"
          # Fallback: try as long arithmetic
          result = case op
                   when "+" then { "op" => "ladd" }
                   when "-" then { "op" => "lsub" }
                   when "*" then { "op" => "lmul" }
                   when "/" then { "op" => "invokestatic", "owner" => "java/lang/Math",
                                    "name" => "floorDiv", "descriptor" => "(JJ)J" }
                   when "%" then { "op" => "invokestatic", "owner" => "java/lang/Math",
                                    "name" => "floorMod", "descriptor" => "(JJ)J" }
                   end
        end

        result
      end

      # Insert checkcast before getfield on user classes when the preceding aload
      # loaded from a parameter slot (typed as Object). For invokevirtual, only do
      # this for zero-arg methods where the preceding aload is guaranteed to be the
      # receiver. For methods with args, the preceding aload is the last argument,
      # not the receiver, so we must not add checkcast on it.
      def insert_missing_checkcasts(instructions)
        result = []
        user_class_prefix = "konpeito/generated/"
        instructions.each_with_index do |inst, i|
          op = inst["op"]
          owner = inst["owner"]
          next (result << inst) unless owner && owner.start_with?(user_class_prefix)

          if op == "getfield"
            # For getfield, the preceding aload is always the receiver
            prev = result.last
            if prev && prev["op"] == "aload" && prev["var"] != 0
              prev_prev = result.size >= 2 ? result[-2] : nil
              unless prev_prev && prev_prev["op"] == "checkcast" && prev_prev["type"] == owner
                result << { "op" => "checkcast", "type" => owner }
              end
            end
          elsif op == "invokevirtual"
            # Only insert checkcast for zero-arg methods where the preceding aload
            # is the receiver (not a method argument)
            descriptor = inst["descriptor"] || ""
            is_zero_arg = descriptor.start_with?("()")
            if is_zero_arg
              prev = result.last
              if prev && prev["op"] == "aload" && prev["var"] != 0
                prev_prev = result.size >= 2 ? result[-2] : nil
                unless prev_prev && prev_prev["op"] == "checkcast" && prev_prev["type"] == owner
                  result << { "op" => "checkcast", "type" => owner }
                end
              end
            end
          end
          result << inst
        end
        result
      end

      # Sanitize void returns: replace non-void return sequences with void return.
      # In void methods, the HIR may generate "load value; xreturn" sequences.
      # We need to strip the value load and replace xreturn with return.
      def insert_return_checkcast(instructions, cast_type)
        result = []
        instructions.each do |inst|
          if inst["op"] == "areturn"
            result << { "op" => "checkcast", "type" => cast_type }
          end
          result << inst
        end
        result
      end

      # Convert areturn (Object return) to primitive return when method return type is primitive.
      # This handles cases like reduce returning a boxed Long but method descriptor expecting long.
      # Convert lreturn/dreturn to box + areturn when method returns Object
      def convert_primitive_return_to_object(instructions)
        result = []
        instructions.each do |inst|
          case inst["op"]
          when "lreturn"
            result << { "op" => "invokestatic", "owner" => "java/lang/Long",
                        "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            result << { "op" => "areturn" }
          when "dreturn"
            result << { "op" => "invokestatic", "owner" => "java/lang/Double",
                        "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            result << { "op" => "areturn" }
          when "ireturn"
            result << { "op" => "invokestatic", "owner" => "java/lang/Boolean",
                        "name" => "valueOf", "descriptor" => "(Z)Ljava/lang/Boolean;" }
            result << { "op" => "areturn" }
          when "return"
            # void return → push null and areturn (for methods with Object return descriptor)
            result << { "op" => "aconst_null" }
            result << { "op" => "areturn" }
          else
            result << inst
          end
        end
        result
      end

      def convert_object_return_to_primitive(instructions, ret_type)
        result = []
        instructions.each do |inst|
          if inst["op"] == "areturn"
            # Replace areturn with: checkcast + unbox + primitive return
            if ret_type == :i64
              result << { "op" => "checkcast", "type" => "java/lang/Number" }
              result << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                          "name" => "longValue", "descriptor" => "()J" }
              result << { "op" => "lreturn" }
            elsif ret_type == :double
              result << { "op" => "checkcast", "type" => "java/lang/Number" }
              result << { "op" => "invokevirtual", "owner" => "java/lang/Number",
                          "name" => "doubleValue", "descriptor" => "()D" }
              result << { "op" => "dreturn" }
            elsif ret_type == :i8
              result << { "op" => "checkcast", "type" => "java/lang/Boolean" }
              result << { "op" => "invokevirtual", "owner" => "java/lang/Boolean",
                          "name" => "booleanValue", "descriptor" => "()Z" }
              result << { "op" => "ireturn" }
            else
              result << inst
            end
          else
            result << inst
          end
        end
        result
      end

      def sanitize_void_returns(instructions)
        result = []
        i = 0
        while i < instructions.size
          inst = instructions[i]
          op = inst["op"]

          if %w[areturn lreturn dreturn ireturn].include?(op)
            # Remove the preceding value-loading instruction(s)
            # Pattern: aload/lload/dload/iload + xreturn  → return
            # Pattern: aconst_null + astore + aload + areturn → return
            # Strip back: remove any preceding loads/stores for the return value
            while result.size > 0
              prev = result.last
              prev_op = prev["op"]
              if %w[aload lload dload iload aconst_null lconst_0 lconst_1
                    dconst_0 dconst_1 iconst_0 iconst_1 iconst_m1
                    bipush sipush ldc].include?(prev_op)
                result.pop
              elsif %w[astore lstore dstore istore].include?(prev_op)
                result.pop
              else
                break
              end
            end
            result << { "op" => "return" }
          else
            result << inst
          end
          i += 1
        end
        result
      end

      def return_instruction?(inst)
        %w[return lreturn dreturn ireturn areturn].include?(inst["op"])
      end

      # Check if an instruction loads a single value onto the stack
      # (used to clean up dangling loads before void returns in constructors)
      def value_load_instruction?(inst)
        %w[aload iload lload dload fload aconst_null iconst lconst_0 lconst_1
           dconst_0 dconst_1 fconst_0 fconst_1 fconst_2 ldc ldc2_w
           bipush sipush].include?(inst["op"])
      end

      def detect_return_type_from_instructions(instructions)
        instructions.reverse_each do |inst|
          case inst["op"]
          when "lreturn" then return :i64
          when "dreturn" then return :double
          when "ireturn" then return :i8
          when "areturn" then return :value
          when "return" then return :void
          end
        end
        function_return_type_fallback
      end

      def function_return_type_fallback
        :value
      end

      def default_return(type)
        case type
        when :i64 then { "op" => "lconst_0" }  # Will need lreturn after
        when :double then { "op" => "dconst_0" }
        when :void then { "op" => "return" }
        else { "op" => "return" }
        end
      end

      def new_label(prefix = "L")
        @label_counter += 1
        "#{prefix}_#{@label_counter}"
      end

      def print_top_of_stack(type)
        instructions = []
        instructions << { "op" => "getstatic",
                          "owner" => "java/lang/System", "name" => "out",
                          "descriptor" => "Ljava/io/PrintStream;" }
        instructions << { "op" => "swap" } if type == :value || type == :i8

        # For long/double we need dup_x2 or store+load pattern
        if type == :i64 || type == :double
          # Store to temp, get System.out, load temp
          # Actually, let's just print at the call site instead
          return []
        end

        desc = case type
               when :i64 then "(J)V"
               when :double then "(D)V"
               when :i8 then "(Z)V"
               else "(Ljava/lang/Object;)V"
               end

        instructions << { "op" => "invokevirtual",
                          "owner" => "java/io/PrintStream", "name" => "println",
                          "descriptor" => desc }
        instructions
      end

      # ========================================================================
      # NativeArray (Primitive Arrays) + StaticArray
      # ========================================================================

      def resolve_jvm_element_type(element_type)
        case element_type
        when :Int64 then :i64
        when :Float64 then :double
        else :value
        end
      end

      # NativeArray.new(size) → newarray long / newarray double
      def generate_jvm_native_array_alloc(inst)
        result_var = inst.result_var
        elem_type = resolve_jvm_element_type(inst.element_type)
        instructions = []

        # Load size and convert to int (JVM arrays use int size)
        instructions.concat(load_value_as_int(inst.size))

        case elem_type
        when :i64
          instructions << { "op" => "newarray", "type" => "long" }
        when :double
          instructions << { "op" => "newarray", "type" => "double" }
        else
          instructions << { "op" => "anewarray", "type" => "java/lang/Object" }
        end

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_native_array_element_type[result_var] = elem_type
        end
        instructions
      end

      # arr[i] → laload / daload / aaload
      def generate_jvm_native_array_get(inst)
        result_var = inst.result_var
        arr_var = extract_var_name(inst.array)
        elem_type = arr_var ? (@variable_native_array_element_type[arr_var] || resolve_jvm_element_type(inst.element_type)) : resolve_jvm_element_type(inst.element_type)
        instructions = []

        # Load array ref
        instructions.concat(load_value(inst.array, :value))
        # Load index and convert to int
        instructions.concat(load_value_as_int(inst.index))

        case elem_type
        when :i64
          instructions << { "op" => "laload" }
          if result_var
            ensure_slot(result_var, :i64)
            instructions << store_instruction(result_var, :i64)
            @variable_types[result_var] = :i64
          end
        when :double
          instructions << { "op" => "daload" }
          if result_var
            ensure_slot(result_var, :double)
            instructions << store_instruction(result_var, :double)
            @variable_types[result_var] = :double
          end
        else
          instructions << { "op" => "aaload" }
          if result_var
            ensure_slot(result_var, :value)
            instructions << store_instruction(result_var, :value)
            @variable_types[result_var] = :value
          end
        end
        instructions
      end

      # arr[i] = value → lastore / dastore / aastore
      def generate_jvm_native_array_set(inst)
        arr_var = extract_var_name(inst.array)
        elem_type = arr_var ? (@variable_native_array_element_type[arr_var] || resolve_jvm_element_type(inst.element_type)) : resolve_jvm_element_type(inst.element_type)
        instructions = []

        # Load array ref
        instructions.concat(load_value(inst.array, :value))
        # Load index and convert to int
        instructions.concat(load_value_as_int(inst.index))
        # Load value
        instructions.concat(load_value(inst.value, elem_type))

        case elem_type
        when :i64
          instructions << { "op" => "lastore" }
        when :double
          instructions << { "op" => "dastore" }
        else
          instructions << { "op" => "aastore" }
        end
        instructions
      end

      # arr.length → arraylength + i2l
      def generate_jvm_native_array_length(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.array, :value))
        instructions << { "op" => "arraylength" }
        instructions << { "op" => "i2l" }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # Dispatch NativeArray method calls ([], []=, length) from HIR::Call
      # These go through the normal Call path in HIR (not NativeArrayGet/Set HIR nodes)
      def generate_native_array_method_call(method_name, receiver, args, result_var)
        recv_var = extract_var_name(receiver)
        elem_type = @variable_native_array_element_type[recv_var]

        case method_name
        when "[]"
          return nil unless args.size == 1
          generate_native_array_call_get(receiver, args.first, elem_type, result_var)
        when "[]="
          return nil unless args.size == 2
          generate_native_array_call_set(receiver, args[0], args[1], elem_type, result_var)
        when "length", "size"
          generate_native_array_call_length(receiver, result_var)
        else
          nil
        end
      end

      # arr[i] via Call → laload / daload
      def generate_native_array_call_get(receiver, index, elem_type, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :value))
        instructions.concat(load_value_as_int(index))

        case elem_type
        when :i64
          instructions << { "op" => "laload" }
          if result_var
            ensure_slot(result_var, :i64)
            instructions << store_instruction(result_var, :i64)
            @variable_types[result_var] = :i64
          end
        when :double
          instructions << { "op" => "daload" }
          if result_var
            ensure_slot(result_var, :double)
            instructions << store_instruction(result_var, :double)
            @variable_types[result_var] = :double
          end
        else
          instructions << { "op" => "aaload" }
          if result_var
            ensure_slot(result_var, :value)
            instructions << store_instruction(result_var, :value)
            @variable_types[result_var] = :value
          end
        end
        instructions
      end

      # arr[i] = value via Call → lastore / dastore
      def generate_native_array_call_set(receiver, index, value, elem_type, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :value))
        instructions.concat(load_value_as_int(index))
        instructions.concat(load_value(value, elem_type))

        case elem_type
        when :i64    then instructions << { "op" => "lastore" }
        when :double then instructions << { "op" => "dastore" }
        else              instructions << { "op" => "aastore" }
        end

        # []=  returns the assigned value
        if result_var
          instructions.concat(load_value(value, elem_type))
          ensure_slot(result_var, elem_type)
          instructions << store_instruction(result_var, elem_type)
          @variable_types[result_var] = elem_type
        end
        instructions
      end

      # arr.length via Call → arraylength + i2l
      def generate_native_array_call_length(receiver, result_var)
        instructions = []
        instructions.concat(load_value(receiver, :value))
        instructions << { "op" => "arraylength" }
        instructions << { "op" => "i2l" }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # StaticArray.new(initial_value) → newarray with compile-time size
      def generate_jvm_static_array_alloc(inst)
        result_var = inst.result_var
        elem_type = resolve_jvm_element_type(inst.element_type)
        size = inst.size
        instructions = []

        # Push compile-time constant size
        instructions << { "op" => "ldc2_w", "value" => size }
        instructions << { "op" => "l2i" }

        case elem_type
        when :i64
          instructions << { "op" => "newarray", "type" => "long" }
        when :double
          instructions << { "op" => "newarray", "type" => "double" }
        end

        # If initial_value is provided, fill the array
        if inst.initial_value
          # Store array ref temporarily
          temp = "__static_arr_temp_#{@label_counter}"
          @label_counter += 1
          ensure_slot(temp, :value)
          instructions << { "op" => "dup" }
          instructions << store_instruction(temp, :value)

          size.times do |i|
            instructions << load_instruction(temp, :value)
            instructions << { "op" => "ldc2_w", "value" => i }
            instructions << { "op" => "l2i" }
            instructions.concat(load_value(inst.initial_value, elem_type))
            case elem_type
            when :i64    then instructions << { "op" => "lastore" }
            when :double then instructions << { "op" => "dastore" }
            end
          end
        end

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_native_array_element_type[result_var] = elem_type
        end
        instructions
      end

      # StaticArray#size → compile-time constant
      def generate_jvm_static_array_size(inst)
        result_var = inst.result_var
        size = inst.size
        instructions = []

        instructions << { "op" => "ldc2_w", "value" => size }
        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # ========================================================================
      # Concurrency — Fiber
      # ========================================================================

      KFIBER_CLASS = "konpeito/runtime/KFiber"

      # Fiber.new { block } → KFiber(Callable<Object>)
      def generate_fiber_new(inst)
        result_var = inst.result_var
        block_def = inst.block_def
        return [] unless result_var && block_def

        instructions = []

        # Compile block as static method (same pattern as Thread.new)
        all_captures = block_def.captures || []
        captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
        capture_types = captures.map { |c| safe_capture_type(c.name.to_s) }

        block_method_name = compile_block_as_method_with_types(block_def, capture_types, [], :value, filtered_captures: captures)

        # Load capture variables
        captures.each_with_index do |cap, i|
          instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), capture_types[i]))
        end

        # invokedynamic to create Callable<Object> via LambdaMetafactory
        capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        indy_desc = "(#{capture_desc})Ljava/util/concurrent/Callable;"
        block_method_params_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        block_method_full_desc = "(#{block_method_params_desc})Ljava/lang/Object;"

        instructions << {
          "op" => "invokedynamic",
          "name" => "call",
          "descriptor" => indy_desc,
          "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
          "bootstrapName" => "metafactory",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => [
            { "type" => "methodType", "descriptor" => "()Ljava/lang/Object;" },
            { "type" => "handle", "tag" => "H_INVOKESTATIC",
              "owner" => @current_enclosing_class,
              "name" => block_method_name,
              "descriptor" => block_method_full_desc },
            { "type" => "methodType", "descriptor" => "()Ljava/lang/Object;" }
          ]
        }

        # new KFiber(callable)
        temp_slot = allocate_temp_slot(:value)
        instructions << { "op" => "astore", "var" => temp_slot }
        instructions << { "op" => "new", "type" => KFIBER_CLASS }
        instructions << { "op" => "dup" }
        instructions << { "op" => "aload", "var" => temp_slot }
        instructions << { "op" => "invokespecial",
                          "owner" => KFIBER_CLASS,
                          "name" => "<init>",
                          "descriptor" => "(Ljava/util/concurrent/Callable;)V" }

        ensure_slot(result_var, :value)
        instructions << store_instruction(result_var, :value)
        @variable_types[result_var] = :value
        @variable_concurrency_types[result_var] = :fiber
        instructions
      end

      # fiber.resume or fiber.resume(value) → KFiber.resume(Object)
      def generate_fiber_resume(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.fiber, :value))
        instructions << { "op" => "checkcast", "type" => KFIBER_CLASS }

        if inst.args && !inst.args.empty?
          # resume with argument
          instructions.concat(load_value(inst.args.first, :value))
          instructions << { "op" => "invokevirtual",
                            "owner" => KFIBER_CLASS,
                            "name" => "resume",
                            "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;" }
        else
          # resume without argument
          instructions << { "op" => "invokevirtual",
                            "owner" => KFIBER_CLASS,
                            "name" => "resume",
                            "descriptor" => "()Ljava/lang/Object;" }
        end

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      # Fiber.yield(value) → KFiber.fiberYield(Object)
      def generate_fiber_yield(inst)
        result_var = inst.result_var
        instructions = []

        if inst.args && !inst.args.empty?
          instructions.concat(load_value(inst.args.first, :value))
          instructions << { "op" => "invokestatic",
                            "owner" => KFIBER_CLASS,
                            "name" => "fiberYield",
                            "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;" }
        else
          instructions << { "op" => "invokestatic",
                            "owner" => KFIBER_CLASS,
                            "name" => "fiberYield",
                            "descriptor" => "()Ljava/lang/Object;" }
        end

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      # fiber.alive? → KFiber.isAlive()
      def generate_fiber_alive(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.fiber, :value))
        instructions << { "op" => "checkcast", "type" => KFIBER_CLASS }
        instructions << { "op" => "invokevirtual",
                          "owner" => KFIBER_CLASS,
                          "name" => "isAlive",
                          "descriptor" => "()Z" }

        if result_var
          # Convert boolean to Boolean object
          instructions << { "op" => "invokestatic",
                            "owner" => "java/lang/Boolean",
                            "name" => "valueOf",
                            "descriptor" => "(Z)Ljava/lang/Boolean;" }
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      # Fiber.current → KFiber.current()
      def generate_fiber_current(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "invokestatic",
                          "owner" => KFIBER_CLASS,
                          "name" => "current",
                          "descriptor" => "()L#{KFIBER_CLASS};" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ========================================================================
      # Concurrency — Thread, Mutex, ConditionVariable, SizedQueue
      # ========================================================================

      # Thread.new { block } → KThread(Callable<Object>)
      def generate_thread_new(inst)
        result_var = inst.result_var
        block_def = inst.block_def
        return [] unless result_var && block_def

        instructions = []

        # Compile block as static method
        all_captures = block_def.captures || []
        # Filter out shared mutable captures — they use static fields instead
        captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
        capture_types = captures.map { |c| safe_capture_type(c.name.to_s) }

        # Thread block always returns Object
        block_method_name = compile_block_as_method_with_types(block_def, capture_types, [], :value, filtered_captures: captures)

        # Load capture variables (only non-shared captures become lambda params)
        captures.each_with_index do |cap, i|
          instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), capture_types[i]))
        end

        # invokedynamic to create Callable<Object> via LambdaMetafactory
        capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        indy_desc = "(#{capture_desc})Ljava/util/concurrent/Callable;"

        block_method_params_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        block_method_full_desc = "(#{block_method_params_desc})Ljava/lang/Object;"

        instructions << {
          "op" => "invokedynamic",
          "name" => "call",
          "descriptor" => indy_desc,
          "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
          "bootstrapName" => "metafactory",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => [
            { "type" => "methodType", "descriptor" => "()Ljava/lang/Object;" },
            { "type" => "handle", "tag" => "H_INVOKESTATIC",
              "owner" => @current_enclosing_class,
              "name" => block_method_name,
              "descriptor" => block_method_full_desc },
            { "type" => "methodType", "descriptor" => "()Ljava/lang/Object;" }
          ]
        }

        # new KThread(callable) — stack: callable -> KThread
        # We need to: new KThread, dup, push callable down, invokespecial
        # Easier: store callable to temp, new+dup, load callable, invokespecial
        temp_slot = allocate_temp_slot(:value)
        instructions << { "op" => "astore", "var" => temp_slot }

        instructions << { "op" => "new", "type" => "konpeito/runtime/KThread" }
        instructions << { "op" => "dup" }
        instructions << { "op" => "aload", "var" => temp_slot }
        instructions << { "op" => "invokespecial",
                          "owner" => "konpeito/runtime/KThread",
                          "name" => "<init>",
                          "descriptor" => "(Ljava/util/concurrent/Callable;)V" }

        ensure_slot(result_var, :value)
        instructions << store_instruction(result_var, :value)
        @variable_types[result_var] = :value
        @variable_concurrency_types[result_var] = :thread
        instructions
      end

      # thread.join → KThread.join()
      def generate_thread_join(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.thread, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KThread" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KThread",
                          "name" => "join",
                          "descriptor" => "()Lkonpeito/runtime/KThread;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # thread.value → KThread.getValue()
      def generate_thread_value(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.thread, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KThread" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KThread",
                          "name" => "getValue",
                          "descriptor" => "()Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Thread.current → Thread.currentThread()
      def generate_thread_current(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "invokestatic",
                          "owner" => "java/lang/Thread",
                          "name" => "currentThread",
                          "descriptor" => "()Ljava/lang/Thread;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Mutex.new → new ReentrantLock()
      def generate_mutex_new(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "new", "type" => "java/util/concurrent/locks/ReentrantLock" }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial",
                          "owner" => "java/util/concurrent/locks/ReentrantLock",
                          "name" => "<init>",
                          "descriptor" => "()V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :mutex
        end
        instructions
      end

      # mutex.lock → ReentrantLock.lock()
      def generate_mutex_lock(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.mutex, :value))
        instructions << { "op" => "checkcast", "type" => "java/util/concurrent/locks/ReentrantLock" }

        if result_var
          instructions << { "op" => "dup" }
        end

        instructions << { "op" => "invokevirtual",
                          "owner" => "java/util/concurrent/locks/ReentrantLock",
                          "name" => "lock",
                          "descriptor" => "()V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # mutex.unlock → ReentrantLock.unlock()
      def generate_mutex_unlock(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.mutex, :value))
        instructions << { "op" => "checkcast", "type" => "java/util/concurrent/locks/ReentrantLock" }

        if result_var
          instructions << { "op" => "dup" }
        end

        instructions << { "op" => "invokevirtual",
                          "owner" => "java/util/concurrent/locks/ReentrantLock",
                          "name" => "unlock",
                          "descriptor" => "()V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # mutex.synchronize { block } → lock + try/finally { unlock }
      def generate_mutex_synchronize(inst)
        result_var = inst.result_var
        block_def = inst.block_def
        return [] unless block_def

        instructions = []

        # Load mutex and cast to ReentrantLock
        instructions.concat(load_value(inst.mutex, :value))
        instructions << { "op" => "checkcast", "type" => "java/util/concurrent/locks/ReentrantLock" }

        # Store mutex ref for use in finally block
        mutex_slot = allocate_temp_slot(:value)
        instructions << { "op" => "dup" }
        instructions << { "op" => "astore", "var" => mutex_slot }

        # Call lock()
        instructions << { "op" => "invokevirtual",
                          "owner" => "java/util/concurrent/locks/ReentrantLock",
                          "name" => "lock",
                          "descriptor" => "()V" }

        # Compile block body as static method
        all_captures = block_def.captures || []
        # Filter out shared mutable captures — they use static fields instead
        captures = all_captures.reject { |c| @shared_mutable_captures&.include?(c.name.to_s) }
        capture_types = captures.map { |c| safe_capture_type(c.name.to_s) }
        block_method_name = compile_block_as_method_with_types(block_def, capture_types, [], :value, filtered_captures: captures)

        # Labels for try/finally
        try_start = new_label("sync_try_start")
        try_end = new_label("sync_try_end")
        handler_label = new_label("sync_handler")
        after_label = new_label("sync_after")

        # Register catch-all exception handler for finally
        @pending_exception_table << {
          "start" => try_start,
          "end" => try_end,
          "handler" => handler_label,
          "type" => nil  # catch all
        }

        # Try block: invoke the block
        instructions << { "op" => "label", "name" => try_start }

        # Load captures and invokedynamic to get KBlock (only non-shared captures)
        captures.each_with_index do |cap, i|
          instructions.concat(load_value(HIR::LocalVar.new(name: cap.name), capture_types[i]))
        end

        capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        block_method_params_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        block_method_full_desc = "(#{block_method_params_desc})Ljava/lang/Object;"

        kblock_iface = get_or_create_kblock([], :value)
        indy_desc = "(#{capture_desc})L#{kblock_iface};"
        call_desc = kblock_call_descriptor([], :value)

        instructions << {
          "op" => "invokedynamic",
          "name" => "call",
          "descriptor" => indy_desc,
          "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
          "bootstrapName" => "metafactory",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => [
            { "type" => "methodType", "descriptor" => call_desc },
            { "type" => "handle", "tag" => "H_INVOKESTATIC",
              "owner" => @current_enclosing_class,
              "name" => block_method_name,
              "descriptor" => block_method_full_desc },
            { "type" => "methodType", "descriptor" => call_desc }
          ]
        }

        # Call KBlock.call() to execute block
        instructions << { "op" => "invokeinterface",
                          "owner" => kblock_iface,
                          "name" => "call",
                          "descriptor" => call_desc }

        # Store block result
        block_result_slot = allocate_temp_slot(:value)
        instructions << { "op" => "astore", "var" => block_result_slot }

        instructions << { "op" => "label", "name" => try_end }

        # Normal path: unlock
        instructions << { "op" => "aload", "var" => mutex_slot }
        instructions << { "op" => "invokevirtual",
                          "owner" => "java/util/concurrent/locks/ReentrantLock",
                          "name" => "unlock",
                          "descriptor" => "()V" }

        # Load result and goto after
        instructions << { "op" => "aload", "var" => block_result_slot }
        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end
        instructions << { "op" => "goto", "target" => after_label }

        # Exception handler: unlock and rethrow
        instructions << { "op" => "label", "name" => handler_label }
        exc_slot = allocate_temp_slot(:value)
        instructions << { "op" => "astore", "var" => exc_slot }
        instructions << { "op" => "aload", "var" => mutex_slot }
        instructions << { "op" => "invokevirtual",
                          "owner" => "java/util/concurrent/locks/ReentrantLock",
                          "name" => "unlock",
                          "descriptor" => "()V" }
        instructions << { "op" => "aload", "var" => exc_slot }
        instructions << { "op" => "athrow" }

        instructions << { "op" => "label", "name" => after_label }
        instructions
      end

      # ConditionVariable.new → new KConditionVariable()
      def generate_cv_new(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "new", "type" => "konpeito/runtime/KConditionVariable" }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial",
                          "owner" => "konpeito/runtime/KConditionVariable",
                          "name" => "<init>",
                          "descriptor" => "()V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :cv
        end
        instructions
      end

      # cv.wait(mutex) → KConditionVariable.await()
      def generate_cv_wait(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.cv, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KConditionVariable" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KConditionVariable",
                          "name" => "await",
                          "descriptor" => "()V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # cv.signal → KConditionVariable.signal()
      def generate_cv_signal(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.cv, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KConditionVariable" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KConditionVariable",
                          "name" => "signal",
                          "descriptor" => "()V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # cv.broadcast → KConditionVariable.broadcast()
      def generate_cv_broadcast(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.cv, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KConditionVariable" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KConditionVariable",
                          "name" => "broadcast",
                          "descriptor" => "()V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << { "op" => "aconst_null" }
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # SizedQueue.new(max) → new KSizedQueue(int)
      def generate_sized_queue_new(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "new", "type" => "konpeito/runtime/KSizedQueue" }
        instructions << { "op" => "dup" }

        # Load max_size and convert to int
        instructions.concat(load_value_as_int(inst.max_size))

        instructions << { "op" => "invokespecial",
                          "owner" => "konpeito/runtime/KSizedQueue",
                          "name" => "<init>",
                          "descriptor" => "(I)V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :sized_queue
        end
        instructions
      end

      # sq.push(value) → KSizedQueue.push(Object)
      def generate_sized_queue_push(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.queue, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KSizedQueue" }

        if result_var
          instructions << { "op" => "dup" }
        end

        # Load value, box if needed
        val_var = extract_var_name(inst.value)
        val_type = val_var ? (@variable_types[val_var] || :value) : :value
        instructions.concat(load_value(inst.value, val_type))
        if val_type == :i64
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                            "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        elsif val_type == :double
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                            "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
        end

        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KSizedQueue",
                          "name" => "push",
                          "descriptor" => "(Ljava/lang/Object;)V" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # sq.pop → KSizedQueue.pop()
      def generate_sized_queue_pop(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.queue, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KSizedQueue" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KSizedQueue",
                          "name" => "pop",
                          "descriptor" => "()Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ========================================
      # Ractor generator methods
      # ========================================

      # Ractor.new { block } → KRactor(Callable)
      def generate_ractor_new(inst)
        result_var = inst.result_var
        block_def = inst.block_def
        return [] unless result_var && block_def

        instructions = []

        # Compile block as static method
        captures = block_def.captures || []
        capture_types = captures.map { |c| @variable_types[c.name.to_s] || :value }

        # Ractor block always returns Object
        block_method_name = compile_block_as_method_with_types(block_def, capture_types, [], :value)

        # Load capture variables
        capture_types.each_with_index do |ct, i|
          instructions.concat(load_value(HIR::LocalVar.new(name: captures[i].name), ct))
        end

        # invokedynamic to create Callable<Object> via LambdaMetafactory
        capture_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        indy_desc = "(#{capture_desc})Ljava/util/concurrent/Callable;"

        block_method_params_desc = capture_types.map { |t| type_to_descriptor(t) }.join
        block_method_full_desc = "(#{block_method_params_desc})Ljava/lang/Object;"

        instructions << {
          "op" => "invokedynamic",
          "name" => "call",
          "descriptor" => indy_desc,
          "bootstrapOwner" => "java/lang/invoke/LambdaMetafactory",
          "bootstrapName" => "metafactory",
          "bootstrapDescriptor" => "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;",
          "bootstrapArgs" => [
            { "type" => "methodType", "descriptor" => "()Ljava/lang/Object;" },
            { "type" => "handle", "tag" => "H_INVOKESTATIC",
              "owner" => @current_enclosing_class,
              "name" => block_method_name,
              "descriptor" => block_method_full_desc },
            { "type" => "methodType", "descriptor" => "()Ljava/lang/Object;" }
          ]
        }

        # Store callable to temp, then new KRactor(callable) or KRactor(callable, name)
        temp_slot = allocate_temp_slot(:value)
        instructions << { "op" => "astore", "var" => temp_slot }

        instructions << { "op" => "new", "type" => "konpeito/runtime/KRactor" }
        instructions << { "op" => "dup" }
        instructions << { "op" => "aload", "var" => temp_slot }

        if inst.name
          # KRactor(Callable, String) constructor
          instructions.concat(load_value(inst.name, :value))
          instructions << { "op" => "checkcast", "type" => "java/lang/String" }
          instructions << { "op" => "invokespecial",
                            "owner" => "konpeito/runtime/KRactor",
                            "name" => "<init>",
                            "descriptor" => "(Ljava/util/concurrent/Callable;Ljava/lang/String;)V" }
        else
          # KRactor(Callable) constructor
          instructions << { "op" => "invokespecial",
                            "owner" => "konpeito/runtime/KRactor",
                            "name" => "<init>",
                            "descriptor" => "(Ljava/util/concurrent/Callable;)V" }
        end

        ensure_slot(result_var, :value)
        instructions << store_instruction(result_var, :value)
        @variable_types[result_var] = :value
        @variable_concurrency_types[result_var] = :ractor
        instructions
      end

      # ractor.send(msg) → KRactor.send(Object)
      def generate_ractor_send(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.ractor, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }

        # Box value if primitive
        value_var = extract_var_name(inst.value)
        value_type = value_var ? (@variable_types[value_var] || :value) : :value
        instructions.concat(load_value(inst.value, value_type))
        if value_type == :i64
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                            "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        elsif value_type == :double
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                            "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
        end

        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "send",
                          "descriptor" => "(Ljava/lang/Object;)V" }

        if result_var
          # Return the ractor itself
          instructions.concat(load_value(inst.ractor, :value))
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :ractor
        end
        instructions
      end

      # Ractor.receive → KRactor.receiveOnCurrent()
      def generate_ractor_receive(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "receiveOnCurrent",
                          "descriptor" => "()Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ractor.join → KRactor.join()
      def generate_ractor_join(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.ractor, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "join",
                          "descriptor" => "()Lkonpeito/runtime/KRactor;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :ractor
        end
        instructions
      end

      # ractor.value → KRactor.getValue()
      def generate_ractor_value(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.ractor, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "getValue",
                          "descriptor" => "()Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ractor.close → KRactor.close()
      def generate_ractor_close(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.ractor, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "close",
                          "descriptor" => "()V" }

        if result_var
          instructions << { "op" => "aconst_null" }
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Ractor.current → KRactor.current()
      def generate_ractor_current(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "current",
                          "descriptor" => "()Lkonpeito/runtime/KRactor;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :ractor
        end
        instructions
      end

      # Ractor.main → KRactor.main()
      def generate_ractor_main(inst)
        result_var = inst.result_var
        instructions = []

        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "main",
                          "descriptor" => "()Lkonpeito/runtime/KRactor;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :ractor
        end
        instructions
      end

      # ractor.name → KRactor.getName()
      def generate_ractor_name(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.ractor, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "getName",
                          "descriptor" => "()Ljava/lang/String;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Ractor[:key] → KRactor.current().getLocal(key)
      def generate_ractor_local_get(inst)
        result_var = inst.result_var
        instructions = []

        # Get current Ractor
        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "current",
                          "descriptor" => "()Lkonpeito/runtime/KRactor;" }

        # Convert key to string
        instructions.concat(load_value(inst.key, :value))
        instructions << { "op" => "invokevirtual",
                          "owner" => "java/lang/Object",
                          "name" => "toString",
                          "descriptor" => "()Ljava/lang/String;" }

        # Call getLocal(String)
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "getLocal",
                          "descriptor" => "(Ljava/lang/String;)Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Ractor[:key] = value → KRactor.current().setLocal(key, value)
      def generate_ractor_local_set(inst)
        result_var = inst.result_var
        instructions = []

        # Get current Ractor
        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "current",
                          "descriptor" => "()Lkonpeito/runtime/KRactor;" }

        # Convert key to string
        instructions.concat(load_value(inst.key, :value))
        instructions << { "op" => "invokevirtual",
                          "owner" => "java/lang/Object",
                          "name" => "toString",
                          "descriptor" => "()Ljava/lang/String;" }

        # Load value (box if primitive)
        value_var = extract_var_name(inst.value)
        value_type = value_var ? (@variable_types[value_var] || :value) : :value
        instructions.concat(load_value(inst.value, value_type))
        if value_type == :i64
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                            "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        elsif value_type == :double
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                            "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
        end

        # Call setLocal(String, Object)
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "setLocal",
                          "descriptor" => "(Ljava/lang/String;Ljava/lang/Object;)Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        else
          instructions << { "op" => "pop" }
        end
        instructions
      end

      # Ractor.make_shareable(obj) → returns obj as-is (JVM stub)
      def generate_ractor_make_sharable(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.value, :value))

        # Call static makeSharable(Object) → Object
        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "makeSharable",
                          "descriptor" => "(Ljava/lang/Object;)Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Ractor.shareable?(obj) → returns true (JVM stub)
      def generate_ractor_sharable(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.value, :value))

        # Call static isSharable(Object) → boolean
        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "isSharable",
                          "descriptor" => "(Ljava/lang/Object;)Z" }
        # Convert boolean to i64 for consistency
        instructions << { "op" => "i2l" }

        if result_var
          ensure_slot(result_var, :i64)
          instructions << store_instruction(result_var, :i64)
          @variable_types[result_var] = :i64
        end
        instructions
      end

      # ractor.monitor(port) → KRactor.monitor(KRactorPort)
      def generate_ractor_monitor(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.ractor, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
        instructions.concat(load_value(inst.port, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "monitor",
                          "descriptor" => "(Lkonpeito/runtime/KRactorPort;)V" }

        if result_var
          instructions << { "op" => "aconst_null" }
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # ractor.unmonitor(port) → KRactor.unmonitor(KRactorPort)
      def generate_ractor_unmonitor(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.ractor, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
        instructions.concat(load_value(inst.port, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "unmonitor",
                          "descriptor" => "(Lkonpeito/runtime/KRactorPort;)V" }

        if result_var
          instructions << { "op" => "aconst_null" }
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Ractor::Port.new → new KRactorPort()
      def generate_ractor_port_new(inst)
        result_var = inst.result_var
        return [] unless result_var

        instructions = []

        instructions << { "op" => "new", "type" => "konpeito/runtime/KRactorPort" }
        instructions << { "op" => "dup" }
        instructions << { "op" => "invokespecial",
                          "owner" => "konpeito/runtime/KRactorPort",
                          "name" => "<init>",
                          "descriptor" => "()V" }

        ensure_slot(result_var, :value)
        instructions << store_instruction(result_var, :value)
        @variable_types[result_var] = :value
        @variable_concurrency_types[result_var] = :ractor_port
        instructions
      end

      # port.send(msg) → KRactorPort.send(Object)
      def generate_ractor_port_send(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.port, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }

        # Box value if primitive
        value_var = extract_var_name(inst.value)
        value_type = value_var ? (@variable_types[value_var] || :value) : :value
        instructions.concat(load_value(inst.value, value_type))
        if value_type == :i64
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                            "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
        elsif value_type == :double
          instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                            "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
        end

        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactorPort",
                          "name" => "send",
                          "descriptor" => "(Ljava/lang/Object;)V" }

        if result_var
          instructions.concat(load_value(inst.port, :value))
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
          @variable_concurrency_types[result_var] = :ractor_port
        end
        instructions
      end

      # port.receive → KRactorPort.receive()
      def generate_ractor_port_receive(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.port, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactorPort",
                          "name" => "receive",
                          "descriptor" => "()Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # port.close → KRactorPort.close()
      def generate_ractor_port_close(inst)
        result_var = inst.result_var
        instructions = []

        instructions.concat(load_value(inst.port, :value))
        instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
        instructions << { "op" => "invokevirtual",
                          "owner" => "konpeito/runtime/KRactorPort",
                          "name" => "close",
                          "descriptor" => "()V" }

        if result_var
          instructions << { "op" => "aconst_null" }
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Ractor.select(*sources) → KRactor.select(Object[])
      def generate_ractor_select(inst)
        result_var = inst.result_var
        instructions = []

        sources = inst.sources

        # Build Object[] array: new Object[N], then aastore each
        instructions << { "op" => "ldc", "value" => sources.size }
        instructions << { "op" => "anewarray", "type" => "java/lang/Object" }

        sources.each_with_index do |src, i|
          instructions << { "op" => "dup" }
          instructions << { "op" => "ldc", "value" => i }
          instructions.concat(load_value(src, :value))
          instructions << { "op" => "aastore" }
        end

        instructions << { "op" => "invokestatic",
                          "owner" => "konpeito/runtime/KRactor",
                          "name" => "select",
                          "descriptor" => "([Ljava/lang/Object;)[Ljava/lang/Object;" }

        if result_var
          ensure_slot(result_var, :value)
          instructions << store_instruction(result_var, :value)
          @variable_types[result_var] = :value
        end
        instructions
      end

      # Dispatch method calls on concurrency objects
      def generate_concurrency_method_call(conc_type, method_name, receiver, args, result_var)
        instructions = []

        case conc_type
        when :thread
          case method_name
          when "join"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KThread" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KThread",
                              "name" => "join",
                              "descriptor" => "()Lkonpeito/runtime/KThread;" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
              @variable_concurrency_types[result_var] = :thread
            end
            return instructions
          when "value"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KThread" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KThread",
                              "name" => "getValue",
                              "descriptor" => "()Ljava/lang/Object;" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "alive?"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KThread" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KThread",
                              "name" => "isAlive",
                              "descriptor" => "()Z" }
            # Convert boolean to long for consistency
            instructions << { "op" => "i2l" }
            if result_var
              ensure_slot(result_var, :i64)
              instructions << store_instruction(result_var, :i64)
              @variable_types[result_var] = :i64
            end
            return instructions
          end

        when :mutex
          case method_name
          when "lock"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "java/util/concurrent/locks/ReentrantLock" }
            instructions << { "op" => "dup" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "java/util/concurrent/locks/ReentrantLock",
                              "name" => "lock",
                              "descriptor" => "()V" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
              @variable_concurrency_types[result_var] = :mutex
            end
            return instructions
          when "unlock"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "java/util/concurrent/locks/ReentrantLock" }
            instructions << { "op" => "dup" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "java/util/concurrent/locks/ReentrantLock",
                              "name" => "unlock",
                              "descriptor" => "()V" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
              @variable_concurrency_types[result_var] = :mutex
            end
            return instructions
          end

        when :cv
          case method_name
          when "wait"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KConditionVariable" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KConditionVariable",
                              "name" => "await",
                              "descriptor" => "()V" }
            if result_var
              instructions.concat(load_value(receiver, :value))
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "signal"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KConditionVariable" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KConditionVariable",
                              "name" => "signal",
                              "descriptor" => "()V" }
            if result_var
              instructions.concat(load_value(receiver, :value))
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "broadcast"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KConditionVariable" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KConditionVariable",
                              "name" => "broadcast",
                              "descriptor" => "()V" }
            if result_var
              instructions.concat(load_value(receiver, :value))
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          end

        when :sized_queue
          case method_name
          when "max"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KSizedQueue" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KSizedQueue",
                              "name" => "max",
                              "descriptor" => "()I" }
            instructions << { "op" => "i2l" }
            if result_var
              ensure_slot(result_var, :i64)
              instructions << store_instruction(result_var, :i64)
              @variable_types[result_var] = :i64
            end
            return instructions
          when "size"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KSizedQueue" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KSizedQueue",
                              "name" => "size",
                              "descriptor" => "()I" }
            instructions << { "op" => "i2l" }
            if result_var
              ensure_slot(result_var, :i64)
              instructions << store_instruction(result_var, :i64)
              @variable_types[result_var] = :i64
            end
            return instructions
          when "push"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KSizedQueue" }
            # Box arg if needed
            arg = args.first
            arg_var = extract_var_name(arg)
            arg_type = arg_var ? (@variable_types[arg_var] || :value) : :value
            instructions.concat(load_value(arg, arg_type))
            if arg_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif arg_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            end
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KSizedQueue",
                              "name" => "push",
                              "descriptor" => "(Ljava/lang/Object;)V" }
            if result_var
              instructions.concat(load_value(receiver, :value))
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "pop"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KSizedQueue" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KSizedQueue",
                              "name" => "pop",
                              "descriptor" => "()Ljava/lang/Object;" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          end

        when :ractor
          case method_name
          when "send", "<<"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
            arg = args.first
            arg_var = extract_var_name(arg)
            arg_type = arg_var ? (@variable_types[arg_var] || :value) : :value
            instructions.concat(load_value(arg, arg_type))
            if arg_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif arg_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            end
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactor",
                              "name" => "send",
                              "descriptor" => "(Ljava/lang/Object;)V" }
            if result_var
              instructions.concat(load_value(receiver, :value))
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
              @variable_concurrency_types[result_var] = :ractor
            end
            return instructions
          when "join"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactor",
                              "name" => "join",
                              "descriptor" => "()Lkonpeito/runtime/KRactor;" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
              @variable_concurrency_types[result_var] = :ractor
            end
            return instructions
          when "value"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactor",
                              "name" => "getValue",
                              "descriptor" => "()Ljava/lang/Object;" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "close"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactor",
                              "name" => "close",
                              "descriptor" => "()V" }
            if result_var
              instructions << { "op" => "aconst_null" }
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "name"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactor",
                              "name" => "getName",
                              "descriptor" => "()Ljava/lang/String;" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "monitor"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
            arg = args.first
            instructions.concat(load_value(arg, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactor",
                              "name" => "monitor",
                              "descriptor" => "(Lkonpeito/runtime/KRactorPort;)V" }
            if result_var
              instructions << { "op" => "aconst_null" }
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "unmonitor"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactor" }
            arg = args.first
            instructions.concat(load_value(arg, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactor",
                              "name" => "unmonitor",
                              "descriptor" => "(Lkonpeito/runtime/KRactorPort;)V" }
            if result_var
              instructions << { "op" => "aconst_null" }
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          end

        when :ractor_port
          case method_name
          when "send", "<<"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
            arg = args.first
            arg_var = extract_var_name(arg)
            arg_type = arg_var ? (@variable_types[arg_var] || :value) : :value
            instructions.concat(load_value(arg, arg_type))
            if arg_type == :i64
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Long",
                                "name" => "valueOf", "descriptor" => "(J)Ljava/lang/Long;" }
            elsif arg_type == :double
              instructions << { "op" => "invokestatic", "owner" => "java/lang/Double",
                                "name" => "valueOf", "descriptor" => "(D)Ljava/lang/Double;" }
            end
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactorPort",
                              "name" => "send",
                              "descriptor" => "(Ljava/lang/Object;)V" }
            if result_var
              instructions.concat(load_value(receiver, :value))
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
              @variable_concurrency_types[result_var] = :ractor_port
            end
            return instructions
          when "receive"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactorPort",
                              "name" => "receive",
                              "descriptor" => "()Ljava/lang/Object;" }
            if result_var
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "close"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactorPort",
                              "name" => "close",
                              "descriptor" => "()V" }
            if result_var
              instructions << { "op" => "aconst_null" }
              ensure_slot(result_var, :value)
              instructions << store_instruction(result_var, :value)
              @variable_types[result_var] = :value
            end
            return instructions
          when "closed?"
            instructions.concat(load_value(receiver, :value))
            instructions << { "op" => "checkcast", "type" => "konpeito/runtime/KRactorPort" }
            instructions << { "op" => "invokevirtual",
                              "owner" => "konpeito/runtime/KRactorPort",
                              "name" => "isClosed",
                              "descriptor" => "()Z" }
            instructions << { "op" => "i2l" }
            if result_var
              ensure_slot(result_var, :i64)
              instructions << store_instruction(result_var, :i64)
              @variable_types[result_var] = :i64
            end
            return instructions
          end
        end

        nil  # Not handled
      end

      # Allocate a temporary local variable slot
      def allocate_temp_slot(type)
        @temp_counter ||= 0
        @temp_counter += 1
        temp_name = "__temp_#{@temp_counter}"
        allocate_slot(temp_name, type)
      end
    end
  end
end
