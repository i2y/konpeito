# frozen_string_literal: true

module Konpeito
  # Known standard library names that can be loaded at runtime via rb_require
  # This list is derived from Ruby's bundled RBS stdlib definitions
  KNOWN_STDLIB_LIBRARIES = %w[
    json fileutils find pathname tempfile timeout uri yaml
    digest openssl socket stringio csv date time set
    net/http net/https net/ftp net/smtp net/pop net/imap
    securerandom base64 benchmark erb logger optparse
    pp prettyprint pstore monitor mutex_m thwait
    tsort weakref shellwords abbrev ostruct open-uri
    singleton forwardable delegate observable ripper
    drb cgi webrick etc
  ].freeze

  # Wrapper for merged AST that provides ProgramNode-like interface
  class MergedAST
    attr_reader :statements, :locals

    def initialize(base_ast, merged_statements)
      @locals = base_ast.locals
      @statements = MergedStatements.new(merged_statements)
    end

    def is_a?(klass)
      return true if klass == Prism::ProgramNode
      super
    end

    def compact_child_nodes
      [@statements]
    end

    # TypedNode.node_type derives from class name — mimic Prism::ProgramNode
    def class
      Prism::ProgramNode
    end
  end

  class MergedStatements
    attr_reader :body

    def initialize(body)
      @body = body
    end

    def compact_child_nodes
      @body
    end

    def is_a?(klass)
      return true if klass == Prism::StatementsNode
      super
    end

    # TypedNode.node_type derives from class name — mimic Prism::StatementsNode
    def class
      Prism::StatementsNode
    end
  end

  class DependencyResolver
    attr_reader :resolved_files, :rbs_paths, :stdlib_requires, :runtime_native_extensions

    def initialize(base_paths: [], verbose: false, cache_manager: nil)
      @base_paths = base_paths
      @verbose = verbose
      @cache_manager = cache_manager
      @resolved_files = {}  # path => AST
      @resolving = Set.new  # For circular dependency detection
      @rbs_paths = []       # Auto-detected RBS paths
      @resolve_order = []   # Order of resolved files (for AST merging)
      @stdlib_requires = [] # Stdlib libraries to load at runtime
      @runtime_native_extensions = [] # Native extensions loaded at runtime (not for linking)
      @cache_hits = 0       # Statistics for verbose output
      @cache_misses = 0
    end

    # Resolve all dependencies starting from entry_file
    # Returns [merged_ast, rbs_paths, stdlib_requires, runtime_native_extensions]
    def resolve(entry_file)
      entry_path = File.expand_path(entry_file)
      resolve_file(entry_path)

      # Log cache statistics in verbose mode
      if @verbose && @cache_manager && (@cache_hits > 0 || @cache_misses > 0)
        log "Cache: #{@cache_hits} hits, #{@cache_misses} misses"
      end

      merged_ast = merge_asts
      [merged_ast, @rbs_paths.uniq, @stdlib_requires.uniq, @runtime_native_extensions.uniq]
    end

    private

    def resolve_file(path)
      return if @resolved_files.key?(path)

      if @resolving.include?(path)
        cycle = @resolving.to_a
        cycle_start = cycle.index(path)
        cycle_files = cycle[cycle_start..].map { |p| File.basename(p) }
        cycle_files << File.basename(path)  # Complete the cycle
        cycle_path = cycle_files.join(" -> ")
        raise DependencyError.new(
          "Circular dependency detected: #{cycle_path}",
          from_file: @resolving.to_a.last,
          cycle: cycle_files
        )
      end

      unless File.exist?(path)
        raise DependencyError.new(
          "File not found: #{path}",
          missing_file: path
        )
      end

      log "Resolving: #{path}"
      @resolving.add(path)

      # Try to use cached AST if available
      ast = nil
      if @cache_manager
        cached_ast = @cache_manager.get_ast(path)
        if cached_ast
          log "  (cached)"
          ast = cached_ast
          @cache_hits += 1
        end
      end

      # Parse the file if not cached
      unless ast
        ast = Parser::PrismAdapter.parse_file(path)
        @cache_misses += 1

        # Store in cache
        if @cache_manager
          @cache_manager.put_ast(path, ast)
        end
      end

      @resolved_files[path] = ast

      # Check for corresponding RBS file (alongside .rb, or in types/ subdirectory)
      rbs_path = path.sub(/\.rb$/, ".rbs")
      if File.exist?(rbs_path)
        log "  Found RBS: #{rbs_path}"
        @rbs_paths << rbs_path
      else
        dir = File.dirname(path)
        # Check types/ subdirectory (common convention for separate type definitions)
        types_rbs = File.join(dir, "types", File.basename(path, ".rb") + ".rbs")
        if File.exist?(types_rbs)
          log "  Found RBS: #{types_rbs}"
          @rbs_paths << types_rbs
        else
          # Check parent dir's types/ with subdirectory name as filename
          # e.g., widgets/text.rb -> ../types/widgets.rbs
          parent_dir = File.dirname(dir)
          subdir_name = File.basename(dir)
          parent_types_rbs = File.join(parent_dir, "types", subdir_name + ".rbs")
          if File.exist?(parent_types_rbs) && !@rbs_paths.include?(parent_types_rbs)
            log "  Found RBS: #{parent_types_rbs}"
            @rbs_paths << parent_types_rbs
          end
        end
      end

      # Clear existing dependencies for this file (in case of re-analysis)
      if @cache_manager
        @cache_manager.clear_dependencies(path)
      end

      # Detect and resolve requires
      requires = Parser::PrismAdapter.detect_requires(ast)
      requires.each do |req|
        dep_path = find_file(req[:name], from_file: path, is_relative: req[:type] == :require_relative)
        if dep_path
          # Register dependency: this file depends on dep_path
          if @cache_manager
            @cache_manager.add_dependency(path, dep_path)
          end
          resolve_file(dep_path)
        elsif req[:type] == :require && stdlib_library?(req[:name])
          # Known stdlib library - will be loaded at runtime via rb_require
          log "  Detected stdlib require: #{req[:name]}"
          @stdlib_requires << req[:name]
        elsif req[:type] == :require_relative
          # Check if this points to a native extension (.bundle/.so/.dll)
          if native_extension_exists?(req[:name], from_file: path)
            log "  Detected native extension (runtime load): #{req[:name]}"
            # Track both the base name (for linker exclusion) and the absolute path
            # (for rb_require in Init function).
            # e.g. "../stdlib/ui/konpeito_ui" → base: "konpeito_ui", path: "/abs/path/to/konpeito_ui"
            abs_path = File.expand_path(req[:name], File.dirname(path))
            @runtime_native_extensions << { base: File.basename(req[:name]), path: abs_path }
          else
            # require_relative must be resolvable
            raise DependencyError.new(
              "Cannot resolve require_relative: #{req[:name]} from #{path}",
              from_file: path,
              line: req[:line],
              missing_file: req[:name]
            )
          end
        else
          # Unknown require - likely a gem that must be required at runtime
          raise DependencyError.new(
            "Cannot resolve require: #{req[:name]}. " \
            "If this is a gem, use require at runtime in Ruby code instead of compile-time.",
            from_file: path,
            line: req[:line],
            missing_file: req[:name]
          )
        end
      end

      @resolving.delete(path)
      @resolve_order << path
    end

    def find_file(name, from_file:, is_relative:)
      # Add .rb extension if not present
      name_with_ext = name.end_with?(".rb") ? name : "#{name}.rb"

      if is_relative
        # require_relative: resolve relative to the current file
        dir = File.dirname(from_file)
        path = File.expand_path(name_with_ext, dir)
        return path if File.exist?(path)
      else
        # require: search in base_paths and relative to entry file
        search_paths = @base_paths + [File.dirname(from_file)]
        search_paths.each do |base|
          path = File.expand_path(name_with_ext, base)
          return path if File.exist?(path)
        end
      end

      nil # Not found (may be stdlib)
    end

    def merge_asts
      return @resolved_files.values.first if @resolve_order.size == 1

      # Merge all ASTs in dependency order (dependencies first)
      all_statements = []

      @resolve_order.each do |path|
        ast = @resolved_files[path]
        next unless ast.is_a?(Prism::ProgramNode)

        # Extract statements, filtering out require/require_relative calls
        ast.statements.body.each do |stmt|
          next if require_statement?(stmt)
          all_statements << stmt
        end
      end

      # Create a wrapper that provides the same interface as ProgramNode
      first_ast = @resolved_files[@resolve_order.first]
      MergedAST.new(first_ast, all_statements)
    end

    def require_statement?(stmt)
      return false unless stmt.is_a?(Prism::CallNode)
      return false unless stmt.receiver.nil?
      %w[require require_relative].include?(stmt.name.to_s)
    end

    def log(message)
      puts message if @verbose
    end

    # Check if a require_relative target points to a native extension (.bundle/.so/.dll)
    def native_extension_exists?(name, from_file:)
      dir = File.dirname(from_file)
      base = File.expand_path(name, dir)
      # Check for common native extension file extensions
      %w[.bundle .so .dll .dylib].any? { |ext| File.exist?("#{base}#{ext}") }
    end

    # Check if a name is a known stdlib library
    def stdlib_library?(name)
      # Normalize: convert dashes to underscores for matching
      normalized = name.tr("-", "_")
      KNOWN_STDLIB_LIBRARIES.include?(name) ||
        KNOWN_STDLIB_LIBRARIES.include?(normalized) ||
        KNOWN_STDLIB_LIBRARIES.include?(name.tr("_", "-"))
    end
  end

end
