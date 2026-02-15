# frozen_string_literal: true

module Konpeito
  module Cache
    # Tracks file dependencies for incremental compilation.
    # Maintains both forward (file -> dependencies) and reverse (file -> dependents) graphs.
    class DependencyGraph
      def initialize
        @forward = {}   # path -> Set of paths this file depends on
        @reverse = {}   # path -> Set of paths that depend on this file
      end

      # Add a dependency: from depends on to
      # Example: main.rb requires utils.rb -> add_dependency("main.rb", "utils.rb")
      def add_dependency(from, to)
        from = normalize_path(from)
        to = normalize_path(to)

        @forward[from] ||= Set.new
        @forward[from] << to

        @reverse[to] ||= Set.new
        @reverse[to] << from
      end

      # Get all files that depend on the given path (direct dependents only)
      def get_direct_dependents(path)
        path = normalize_path(path)
        @reverse[path]&.to_a || []
      end

      # Get all files that depend on the given path (transitively)
      def get_all_dependents(path)
        path = normalize_path(path)
        result = Set.new
        queue = [path]

        while queue.any?
          current = queue.shift
          dependents = @reverse[current] || Set.new

          dependents.each do |dep|
            unless result.include?(dep)
              result << dep
              queue << dep
            end
          end
        end

        result.to_a
      end

      # Get all dependencies of the given path (what this file depends on)
      def get_dependencies(path)
        path = normalize_path(path)
        @forward[path]&.to_a || []
      end

      # Given a set of changed files, return all files that need recompilation
      # in dependency order (dependencies before dependents)
      def invalidation_order(changed_paths)
        changed_paths = changed_paths.map { |p| normalize_path(p) }

        # Collect all affected files (changed + their dependents)
        affected = Set.new(changed_paths)
        changed_paths.each do |path|
          get_all_dependents(path).each { |dep| affected << dep }
        end

        # Topological sort: dependencies before dependents
        topological_sort(affected.to_a)
      end

      # Check if path has any registered dependencies
      def has_dependencies?(path)
        path = normalize_path(path)
        @forward.key?(path) && @forward[path].any?
      end

      # Remove a file from the graph
      def remove(path)
        path = normalize_path(path)

        # Remove from forward graph
        if @forward[path]
          @forward[path].each do |dep|
            @reverse[dep]&.delete(path)
          end
          @forward.delete(path)
        end

        # Remove from reverse graph
        if @reverse[path]
          @reverse[path].each do |dependent|
            @forward[dependent]&.delete(path)
          end
          @reverse.delete(path)
        end
      end

      # Clear all dependencies for a file (but keep dependents)
      def clear_dependencies(path)
        path = normalize_path(path)

        if @forward[path]
          @forward[path].each do |dep|
            @reverse[dep]&.delete(path)
          end
          @forward[path] = Set.new
        end
      end

      # Clear all data
      def clear!
        @forward.clear
        @reverse.clear
      end

      # Serialize to hash for persistence
      def to_h
        {
          "forward" => @forward.transform_values(&:to_a),
          "reverse" => @reverse.transform_values(&:to_a)
        }
      end

      # Deserialize from hash
      def self.from_h(data)
        graph = new
        return graph unless data

        (data["forward"] || {}).each do |path, deps|
          graph.instance_variable_get(:@forward)[path] = Set.new(deps)
        end
        (data["reverse"] || {}).each do |path, deps|
          graph.instance_variable_get(:@reverse)[path] = Set.new(deps)
        end
        graph
      end

      # Get all known files
      def all_files
        (@forward.keys + @reverse.keys).uniq
      end

      private

      def normalize_path(path)
        File.expand_path(path)
      end

      # Topological sort using Kahn's algorithm
      # Returns files in dependency order: dependencies before dependents
      def topological_sort(files)
        return files if files.empty?

        # Build in-degree map (only for files in our set)
        # in_degree[file] = number of dependencies of file that are also in our set
        in_degree = {}
        files.each { |f| in_degree[f] = 0 }

        files.each do |file|
          (@forward[file] || Set.new).each do |dep|
            # file depends on dep, so file has an incoming edge from dep
            # Increment in_degree for file (not dep) so dependencies come first
            in_degree[file] += 1 if in_degree.key?(dep)
          end
        end

        # Start with files that have no dependencies (in-degree 0)
        queue = files.select { |f| in_degree[f] == 0 }
        result = []

        while queue.any?
          current = queue.shift
          result << current

          (@reverse[current] || Set.new).each do |dependent|
            next unless in_degree.key?(dependent)

            in_degree[dependent] -= 1
            queue << dependent if in_degree[dependent] == 0
          end
        end

        # If there are remaining files, there's a cycle - add them anyway
        remaining = files - result
        result + remaining
      end
    end
  end
end
