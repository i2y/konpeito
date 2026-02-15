# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

module Konpeito
  module Cache
    # Manages compilation cache for incremental builds.
    # Caches AST and type inference results per file.
    class CacheManager
      MANIFEST_FILE = "manifest.json"
      AST_DIR = "ast"
      TYPES_DIR = "types"

      attr_reader :cache_dir, :dependency_graph

      def initialize(cache_dir: ".konpeito_cache")
        @cache_dir = File.expand_path(cache_dir)
        @manifest = nil
        @dependency_graph = nil
        @dirty = false

        ensure_cache_dirs
        load_manifest
      end

      # Calculate SHA256 hash of file content
      def file_hash(path)
        return nil unless File.exist?(path)

        Digest::SHA256.file(path).hexdigest
      end

      # Check if a file needs recompilation
      def needs_recompile?(path)
        path = normalize_path(path)
        current_hash = file_hash(path)
        return true unless current_hash

        cached_hash = @manifest["files"][path]&.dig("hash")
        current_hash != cached_hash
      end

      # Get cached AST for a file
      def get_ast(path)
        path = normalize_path(path)
        return nil if needs_recompile?(path)

        ast_file = ast_cache_path(path)
        return nil unless File.exist?(ast_file)

        begin
          Marshal.load(File.binread(ast_file))
        rescue StandardError
          nil
        end
      end

      # Store AST in cache
      def put_ast(path, ast)
        path = normalize_path(path)
        ast_file = ast_cache_path(path)

        FileUtils.mkdir_p(File.dirname(ast_file))
        File.binwrite(ast_file, Marshal.dump(ast))

        update_file_entry(path)
      end

      # Get cached type inference results
      def get_types(path)
        path = normalize_path(path)
        return nil if needs_recompile?(path)

        types_file = types_cache_path(path)
        return nil unless File.exist?(types_file)

        begin
          Marshal.load(File.binread(types_file))
        rescue StandardError
          nil
        end
      end

      # Store type inference results
      def put_types(path, data)
        path = normalize_path(path)
        types_file = types_cache_path(path)

        FileUtils.mkdir_p(File.dirname(types_file))
        File.binwrite(types_file, Marshal.dump(data))

        update_file_entry(path)
      end

      # Invalidate cache for a file and all its dependents
      def invalidate(path)
        path = normalize_path(path)

        # Get all affected files
        affected = [path] + @dependency_graph.get_all_dependents(path)

        affected.each do |file|
          invalidate_single(file)
        end

        @dirty = true
      end

      # Register a dependency
      def add_dependency(from, to)
        @dependency_graph.add_dependency(from, to)
        @dirty = true
      end

      # Clear dependencies for a file (called before re-analyzing)
      def clear_dependencies(path)
        @dependency_graph.clear_dependencies(path)
        @dirty = true
      end

      # Get files that need recompilation given changed files
      def get_recompile_order(changed_paths)
        @dependency_graph.invalidation_order(changed_paths)
      end

      # Clear all cache
      def clean!
        FileUtils.rm_rf(@cache_dir)
        ensure_cache_dirs
        @manifest = create_empty_manifest
        @dependency_graph = DependencyGraph.new
        @dirty = true
        save_manifest
      end

      # Save manifest to disk
      def save_manifest
        return unless @dirty

        @manifest["dependency_graph"] = @dependency_graph.to_h
        @manifest["updated_at"] = Time.now.iso8601

        manifest_path = File.join(@cache_dir, MANIFEST_FILE)
        File.write(manifest_path, JSON.pretty_generate(@manifest))
        @dirty = false
      end

      # Get all cached files
      def cached_files
        @manifest["files"].keys
      end

      # Check if cache exists and is valid
      def cache_exists?
        File.exist?(File.join(@cache_dir, MANIFEST_FILE))
      end

      private

      def normalize_path(path)
        File.expand_path(path)
      end

      def ensure_cache_dirs
        FileUtils.mkdir_p(@cache_dir)
        FileUtils.mkdir_p(File.join(@cache_dir, AST_DIR))
        FileUtils.mkdir_p(File.join(@cache_dir, TYPES_DIR))
      end

      def load_manifest
        manifest_path = File.join(@cache_dir, MANIFEST_FILE)

        if File.exist?(manifest_path)
          begin
            data = JSON.parse(File.read(manifest_path))
            @manifest = data
            @dependency_graph = DependencyGraph.from_h(data["dependency_graph"])
          rescue JSON::ParserError
            @manifest = create_empty_manifest
            @dependency_graph = DependencyGraph.new
          end
        else
          @manifest = create_empty_manifest
          @dependency_graph = DependencyGraph.new
        end
      end

      def create_empty_manifest
        {
          "version" => Konpeito::VERSION,
          "created_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "files" => {},
          "dependency_graph" => {}
        }
      end

      def update_file_entry(path)
        @manifest["files"][path] = {
          "hash" => file_hash(path),
          "cached_at" => Time.now.iso8601
        }
        @dirty = true
      end

      def invalidate_single(path)
        @manifest["files"].delete(path)

        # Remove cached files
        ast_file = ast_cache_path(path)
        types_file = types_cache_path(path)

        FileUtils.rm_f(ast_file)
        FileUtils.rm_f(types_file)
      end

      def ast_cache_path(path)
        hash = Digest::SHA256.hexdigest(path)
        File.join(@cache_dir, AST_DIR, "#{hash}.ast")
      end

      def types_cache_path(path)
        hash = Digest::SHA256.hexdigest(path)
        File.join(@cache_dir, TYPES_DIR, "#{hash}.types")
      end
    end
  end
end
