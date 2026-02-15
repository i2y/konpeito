# frozen_string_literal: true

require "rbconfig"

module Konpeito
  # Compilation statistics collected during a build
  CompileStats = Data.define(
    :resolved_files,  # Integer - number of source files resolved
    :rbs_count,       # Integer - number of RBS definitions loaded
    :functions,       # Integer - number of functions compiled
    :classes,         # Integer - number of classes compiled
    :modules,         # Integer - number of modules compiled
    :specializations, # Integer - monomorphization specializations generated
    :inlined,         # Integer - call sites inlined
    :hoisted,         # Integer - loop-invariant instructions hoisted
    :duration_s       # Float - total compile time in seconds
  )

  class Compiler
    attr_reader :source_file, :output_file, :format, :verbose, :rbs_paths, :require_paths, :diagnostics, :debug, :profile, :incremental, :compile_stats

    def initialize(source_file:, output_file:, format: :cruby_ext, verbose: false, rbs_paths: [], optimize: true, require_paths: [], debug: false, profile: false, incremental: false, clean_cache: false, inline_rbs: false, target: :native, run_after: false, emit_ir: false, classpath: nil, library: false)
      @source_file = source_file
      @format = format
      @verbose = verbose
      @rbs_paths = rbs_paths
      @require_paths = require_paths
      @rbs_loader = nil
      @hm_inferrer = nil
      @optimize = optimize
      @stdlib_requires = []
      @diagnostics = []
      @debug = debug
      @profile = profile
      @incremental = incremental
      @clean_cache = clean_cache
      @cache_manager = nil
      @inline_rbs = inline_rbs
      @target = target
      @run_after = run_after
      @emit_ir = emit_ir
      @classpath = classpath
      @library = library
      @output_file = output_file || default_output_file(target: target)
      @compile_stats = nil
      @_resolved_file_count = 0
      @_specialization_count = 0
      @_inlined_count = 0
      @_hoisted_count = 0
    end

    def compile
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      setup_cache if @incremental

      @parsed_ast = parse
      typed_ast = type_check_ast(@parsed_ast)
      hir = generate_hir(typed_ast)
      hir = optimize_hir(hir) if @optimize
      resolve_types(hir) if @target == :jvm
      generate_code(hir)

      save_cache if @incremental

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

      # Collect stats
      rbs_count = @rbs_paths.size
      func_count = hir.functions.size
      class_count = hir.classes.size
      mod_count = hir.respond_to?(:modules) ? hir.modules.size : 0

      @compile_stats = CompileStats.new(
        resolved_files: @_resolved_file_count,
        rbs_count: rbs_count,
        functions: func_count,
        classes: class_count,
        modules: mod_count,
        specializations: @_specialization_count,
        inlined: @_inlined_count,
        hoisted: @_hoisted_count,
        duration_s: duration
      )

      output_file
    end

    def type_check
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      @parsed_ast = parse
      type_check_ast(@parsed_ast)

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      @compile_stats = CompileStats.new(
        resolved_files: @_resolved_file_count,
        rbs_count: @rbs_paths.size,
        functions: 0,
        classes: 0,
        modules: 0,
        specializations: 0,
        inlined: 0,
        hoisted: 0,
        duration_s: duration
      )

      true
    end

    private

    def parse
      log "Resolving dependencies for #{source_file}..."
      resolver = DependencyResolver.new(
        base_paths: @require_paths,
        verbose: verbose,
        cache_manager: @cache_manager
      )
      merged_ast, auto_rbs_paths, stdlib_requires, runtime_native_exts = resolver.resolve(source_file)

      # Merge auto-detected RBS paths (normalize to absolute for dedup)
      @rbs_paths = (@rbs_paths.map { |p| File.expand_path(p) } + auto_rbs_paths).uniq

      # Store stdlib requires for runtime loading
      @stdlib_requires = stdlib_requires

      # Store runtime native extensions (excluded from linker flags)
      @runtime_native_extensions = runtime_native_exts || []

      @_resolved_file_count = resolver.resolved_files.size
      @_resolved_file_paths = resolver.resolved_files.keys

      if verbose && resolver.resolved_files.size > 1
        log "Resolved #{resolver.resolved_files.size} files:"
        resolver.resolved_files.keys.each { |f| log "  - #{f}" }
      end

      if verbose && !@stdlib_requires.empty?
        log "Stdlib requires (will be loaded at runtime):"
        @stdlib_requires.each { |lib| log "  - #{lib}" }
      end

      merged_ast
    end

    def rbs_loader
      @rbs_loader ||= begin
        loader = TypeChecker::RBSLoader.new

        # Process inline RBS from all resolved source files
        # Auto-detect files with "# rbs_inline: enabled" even without --inline flag
        inline_rbs_content = nil
        files_to_scan = @_resolved_file_paths || (File.exist?(source_file) ? [source_file] : [])
        preprocessor = RBSInline::Preprocessor.new
        inline_parts = []
        files_to_scan.each do |path|
          next unless File.exist?(path)
          content = File.read(path)
          # Process if --inline flag is set OR file has rbs_inline marker
          if @inline_rbs || RBSInline::Preprocessor.has_inline_rbs?(content)
            rbs_output = preprocessor.process(content, filename: path)
            inline_parts << rbs_output unless rbs_output.strip.empty?
          end
        end
        unless inline_parts.empty?
          inline_rbs_content = inline_parts.join("\n")
          log "Generated RBS from inline annotations (#{inline_parts.size} files)" if verbose
        end

        loader.load(
          rbs_paths: rbs_paths,
          stdlib_libraries: @stdlib_requires,
          inline_rbs_content: inline_rbs_content
        )

        # Auto-register Java:: references from AST before classpath introspection
        if @target == :jvm && @classpath && !@classpath.empty? && @parsed_ast
          # ClassIntrospector requires absolute paths in classpath
          abs_classpath = @classpath.split(Platform.classpath_separator).map { |p| File.expand_path(p) }.join(Platform.classpath_separator)
          java_refs = scan_java_references(@parsed_ast)
          loader.register_java_references(java_refs, abs_classpath) unless java_refs[:refs].empty?
        end

        if @target == :jvm
          abs_cp = @classpath ? @classpath.split(Platform.classpath_separator).map { |p| File.expand_path(p) }.join(Platform.classpath_separator) : @classpath
          loader.load_classpath_types(abs_cp)
        end
        loader
      end
    end

    def type_check_ast(ast)
      log "Type checking..."

      # Read source content for diagnostic messages
      source_content = File.exist?(source_file) ? File.read(source_file) : nil

      # Build typed AST with HM inference
      builder = AST::TypedASTBuilder.new(
        rbs_loader,
        use_hm: true,
        file_path: source_file,
        source: source_content
      )
      typed_ast = builder.build(ast)

      # Save HM inferrer for monomorphization
      @hm_inferrer = builder.instance_variable_get(:@hm_inferrer)

      # Store diagnostics for later display
      @diagnostics = builder.diagnostics

      # Show inferred types in verbose mode
      if verbose && @hm_inferrer
        show_inferred_types(@hm_inferrer)
      end

      # Log unresolved type warnings (Kotlin-style validation)
      if verbose && @hm_inferrer && @hm_inferrer.respond_to?(:unresolved_type_warnings)
        warnings = @hm_inferrer.unresolved_type_warnings
        unless warnings.empty?
          log "Unresolved type warnings (#{warnings.size}):"
          warnings.each do |w|
            case w[:kind]
            when :param
              log "  #{w[:function]} param[#{w[:index]}]: #{w[:typevar]}"
            when :return
              log "  #{w[:function]} return: #{w[:typevar]}"
            end
          end
        end
      end

      typed_ast
    end

    def show_inferred_types(hm_inferrer)
      func_types = hm_inferrer.instance_variable_get(:@function_types)
      env = hm_inferrer.instance_variable_get(:@env).first

      has_output = false

      unless func_types.empty?
        log "Inferred function types:"
        func_types.each do |name, func_type|
          final_type = hm_inferrer.finalize(func_type)
          log "  #{name}: #{final_type}"
        end
        has_output = true
      end

      # Show inferred variable types (excluding functions)
      var_types = env.reject do |name, scheme|
        hm_inferrer.finalize(scheme.type).is_a?(TypeChecker::FunctionType)
      end

      unless var_types.empty?
        log "Inferred variable types:" if has_output
        var_types.each do |name, scheme|
          final_type = hm_inferrer.finalize(scheme.type)
          log "  #{name}: #{final_type}"
        end
      end
    end

    def generate_hir(typed_ast)
      log "Generating HIR..."

      builder = HIR::Builder.new(rbs_loader: @rbs_loader)
      builder.build(typed_ast)
    end

    def optimize_hir(hir)
      log "Optimizing HIR..."

      # Apply monomorphization
      if @hm_inferrer
        log "  - Monomorphization"
        @monomorphizer = Codegen::Monomorphizer.new(hir, @hm_inferrer)
        @monomorphizer.analyze
        @monomorphizer.transform

        if verbose && !@monomorphizer.specializations.empty?
          log "  Generated specializations:"
          @monomorphizer.specializations.each do |(func, types), name|
            log "    #{func}(#{types.join(', ')}) -> #{name}"
          end
        end

        if verbose && !@monomorphizer.union_dispatches.empty?
          log "  Union type dispatches:"
          @monomorphizer.union_dispatches.each do |(_target, _types), info|
            log "    #{info[:target]}(#{info[:original_types].map(&:to_s).join(', ')}):"
            info[:specializations].each do |concrete_types, specialized_name|
              log "      -> #{specialized_name} for (#{concrete_types.join(', ')})"
            end
          end
        end
      end

      @_specialization_count = @monomorphizer ? @monomorphizer.specializations.size : 0

      # Apply inlining
      log "  - Inlining"
      inliner = Codegen::Inliner.new(hir)
      inliner.optimize
      @_inlined_count = inliner.inlined_count

      if verbose && inliner.inlined_count > 0
        log "    Inlined #{inliner.inlined_count} call site(s)"
      end

      # Apply loop optimizations (LICM)
      log "  - Loop optimization"
      loop_optimizer = Codegen::LoopOptimizer.new(hir)
      loop_optimizer.optimize
      @_hoisted_count = loop_optimizer.hoisted_count

      if verbose && loop_optimizer.hoisted_count > 0
        log "    Hoisted #{loop_optimizer.hoisted_count} loop-invariant instruction(s)"
      end

      hir
    end

    def resolve_types(hir)
      require_relative "type_checker/type_resolver"

      log "Resolving types..."

      # Collect JVM interop class info from rbs_loader if available
      jvm_interop_classes = {}
      if @rbs_loader && @rbs_loader.respond_to?(:jvm_classes)
        jvm_interop_classes = @rbs_loader.jvm_classes || {}
      end

      resolver = TypeChecker::TypeResolver.new(
        hir,
        hm_inferrer: @hm_inferrer,
        rbs_loader: @rbs_loader,
        jvm_interop_classes: jvm_interop_classes,
        monomorphizer: @monomorphizer
      )

      unless resolver.resolve!
        @type_resolution_errors = resolver.errors
        if @verbose
          resolver.errors.each { |e| puts "  #{e}" }
          puts ""
          puts "  Type inference could not determine the receiver type."
          puts "  These methods may not work correctly if called at runtime."
          puts ""
        end
      end
    end

    def generate_code(hir)
      if @target == :jvm
        generate_jvm(hir)
      else
        log "Generating #{format} code..."
        case format
        when :cruby_ext
          generate_cruby_extension(hir)
        when :standalone
          generate_standalone(hir)
        else
          raise CodegenError, "Unknown format: #{format}"
        end
      end
    end

    def generate_cruby_extension(hir)
      log "Generating LLVM IR..."

      # Detect if HIR uses JSON parse_as
      uses_json_parse_as = hir_uses_json_parse_as?(hir)
      log "  - JSON parse_as detected" if uses_json_parse_as && verbose

      # Generate LLVM IR with monomorphization support
      llvm_gen = Codegen::LLVMGenerator.new(
        module_name: module_name,
        monomorphizer: @monomorphizer,
        rbs_loader: @rbs_loader,
        debug: @debug,
        profile: @profile,
        source_file: source_file
      )
      llvm_gen.generate(hir)

      log "Compiling to native code..."

      # Compile to .so/.bundle
      backend = Codegen::CRubyBackend.new(
        llvm_gen,
        output_file: output_file,
        module_name: module_name,
        rbs_loader: @rbs_loader,
        stdlib_requires: @stdlib_requires,
        runtime_native_extensions: @runtime_native_extensions || [],
        debug: @debug,
        profile: @profile,
        uses_json_parse_as: uses_json_parse_as
      )
      backend.generate

      log "Generated: #{output_file}"
    end

    def generate_standalone(hir)
      raise CodegenError, "Standalone generation not yet implemented"
    end

    def generate_jvm(hir)
      require_relative "codegen/jvm_generator"
      require_relative "codegen/jvm_backend"

      @jvm_gen = Codegen::JVMGenerator.new(
        module_name: module_name,
        monomorphizer: @monomorphizer,
        rbs_loader: @rbs_loader,
        verbose: @verbose
      )
      @jvm_gen.generate(hir)

      # TypeVar fallbacks in codegen — unresolved types use invokedynamic for
      # runtime method resolution. Report as warning, not error.
      if @jvm_gen.typevar_fallback_count > 0
        warn_msg = "#{@jvm_gen.typevar_fallback_count} unresolved type(s) — using invokedynamic fallback."
        log warn_msg
      end

      if @jvm_gen.rbs_fallback_count > 0
        log "Type resolution: #{@jvm_gen.rbs_fallback_count} RBS fallbacks (HM inference gaps)"
      end

      jvm_gen = @jvm_gen

      backend = Codegen::JVMBackend.new(
        jvm_gen,
        output_file: output_file,
        module_name: module_name,
        run_after: @run_after,
        emit_ir: @emit_ir,
        classpath: @classpath,
        library: @library
      )
      backend.generate

      log "Generated: #{output_file}"
    end

    def hir_uses_json_parse_as?(hir)
      hir.functions.any? do |func|
        func.body.any? do |bb|
          bb.instructions.any? do |instr|
            instr.is_a?(HIR::JSONParseAs) || instr.is_a?(HIR::JSONParseArrayAs)
          end
        end
      end
    end

    def module_name
      @module_name ||= File.basename(source_file, ".rb").gsub(/[^a-zA-Z0-9_]/, "_")
    end

    def default_output_file(target: :native)
      base = File.basename(source_file, ".rb")
      if target == :jvm
        "#{base}.jar"
      else
        case format
        when :cruby_ext
          "#{base}#{Platform.shared_lib_extension}"
        when :standalone
          base
        else
          base
        end
      end
    end

    def log(message)
      puts message if verbose
    end

    # Scan AST for Java:: constant references and constant aliases.
    # Returns { refs: { "Java::X::Y" => "x/Y" }, aliases: { "KCanvas" => "Java::X::Y" } }
    def scan_java_references(ast)
      refs = {}
      aliases = {}
      scan_node_for_java_refs(ast, refs, aliases)
      { refs: refs, aliases: aliases }
    end

    def scan_node_for_java_refs(node, refs, aliases)
      return unless node

      case node
      when Prism::ConstantPathNode
        full_name = extract_constant_path_name(node)
        if full_name&.start_with?("Java::")
          refs[full_name] = ruby_path_to_jvm_internal(full_name) unless refs.key?(full_name)
        end
      when Prism::ConstantWriteNode
        # KCanvas = Java::Konpeito::Canvas::Canvas
        value_node = node.value
        if value_node.is_a?(Prism::ConstantPathNode)
          full_name = extract_constant_path_name(value_node)
          if full_name&.start_with?("Java::")
            refs[full_name] = ruby_path_to_jvm_internal(full_name) unless refs.key?(full_name)
            aliases[node.name.to_s] = full_name
          end
        end
      end

      # Recurse into child nodes
      children = if node.respond_to?(:child_nodes)
                   node.child_nodes
                 elsif node.respond_to?(:compact_child_nodes)
                   node.compact_child_nodes
                 else
                   []
                 end
      children.each { |child| scan_node_for_java_refs(child, refs, aliases) }
    end

    def extract_constant_path_name(node)
      parts = []
      current = node
      while current.is_a?(Prism::ConstantPathNode)
        parts.unshift(current.name.to_s)
        current = current.parent
      end
      parts.unshift(current.name.to_s) if current.respond_to?(:name)
      parts.join("::")
    end

    # Convert "Java::Konpeito::Canvas::Canvas" → "konpeito/canvas/Canvas"
    def ruby_path_to_jvm_internal(ruby_path)
      segments = ruby_path.delete_prefix("Java::").split("::")
      segments.each_with_index.map { |s, i|
        i < segments.size - 1 ? s[0].downcase + s[1..] : s
      }.join("/")
    end

    # Incremental compilation support

    def setup_cache
      require_relative "cache"

      @cache_manager = Cache::CacheManager.new

      if @clean_cache
        log "Clearing compilation cache..."
        @cache_manager.clean!
      end
    end

    def save_cache
      return unless @cache_manager

      @cache_manager.save_manifest
      log "Cache saved." if verbose
    end

    def cache_ast(path, ast)
      return unless @cache_manager

      @cache_manager.put_ast(path, ast)
    end

    def get_cached_ast(path)
      return nil unless @cache_manager

      @cache_manager.get_ast(path)
    end

    def cache_needs_recompile?(path)
      return true unless @cache_manager

      @cache_manager.needs_recompile?(path)
    end

    def register_dependency(from, to)
      return unless @cache_manager

      @cache_manager.add_dependency(from, to)
    end
  end
end
