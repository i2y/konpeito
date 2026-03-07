# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

module Konpeito
  module Cache
    # Manages compilation cache for `konpeito run`.
    # Content-addressed: cache key is SHA256 of all inputs.
    class RunCache
      MANIFEST_FILE = "run_manifest.json"
      DEFAULT_MAX_ENTRIES = 20

      attr_reader :cache_dir

      def initialize(cache_dir: ".konpeito_cache/run")
        @cache_dir = File.expand_path(cache_dir)
        @manifest = nil
        load_manifest
      end

      # Compute a cache key from all compilation inputs.
      def compute_cache_key(source_files:, rbs_files:, options_hash:)
        digest = Digest::SHA256.new
        source_files.sort.each { |f| digest.update(Digest::SHA256.file(f).hexdigest) }
        rbs_files.sort.each { |f| digest.update(Digest::SHA256.file(f).hexdigest) }
        digest.update(options_hash.sort.map { |k, v| "#{k}=#{v}" }.join("|"))
        digest.update(Konpeito::VERSION)
        digest.hexdigest
      end

      # Look up a cached artifact. Returns the path if it exists, nil otherwise.
      def lookup(cache_key, basename)
        entry = @manifest["entries"][cache_key]
        return nil unless entry

        artifact = artifact_path(cache_key, basename)
        return nil unless File.exist?(artifact)

        # Update last_used_at
        entry["last_used_at"] = Time.now.iso8601
        save_manifest
        artifact
      end

      # Register a compiled artifact in the manifest.
      # The artifact should already exist at artifact_dir(cache_key)/basename.
      def store(cache_key, basename)
        artifact = artifact_path(cache_key, basename)
        return nil unless File.exist?(artifact)

        @manifest["entries"][cache_key] = {
          "basename" => basename,
          "created_at" => Time.now.iso8601,
          "last_used_at" => Time.now.iso8601
        }
        save_manifest
        cleanup!
        artifact
      end

      # Directory for a given cache key's artifact.
      def artifact_dir(cache_key)
        File.join(@cache_dir, cache_key)
      end

      # Full path to the artifact file.
      def artifact_path(cache_key, basename)
        File.join(artifact_dir(cache_key), basename)
      end

      # Remove all cached entries.
      def clean!
        FileUtils.rm_rf(@cache_dir)
        FileUtils.mkdir_p(@cache_dir)
        @manifest = create_empty_manifest
        save_manifest
      end

      # Evict oldest entries beyond max_entries.
      def cleanup!(max_entries: DEFAULT_MAX_ENTRIES)
        entries = @manifest["entries"]
        return if entries.size <= max_entries

        # Sort by last_used_at ascending (oldest first)
        sorted = entries.sort_by { |_k, v| v["last_used_at"] || v["created_at"] || "" }
        to_remove = sorted.first(entries.size - max_entries)

        to_remove.each do |key, _|
          dir = artifact_dir(key)
          FileUtils.rm_rf(dir) if Dir.exist?(dir)
          entries.delete(key)
        end

        save_manifest
      end

      private

      def load_manifest
        FileUtils.mkdir_p(@cache_dir)
        manifest_path = File.join(@cache_dir, MANIFEST_FILE)

        if File.exist?(manifest_path)
          begin
            @manifest = JSON.parse(File.read(manifest_path))
            # Ensure entries key exists
            @manifest["entries"] ||= {}
          rescue JSON::ParserError
            @manifest = create_empty_manifest
          end
        else
          @manifest = create_empty_manifest
        end
      end

      def save_manifest
        manifest_path = File.join(@cache_dir, MANIFEST_FILE)
        # Write to tmp file then rename for atomicity
        tmp_path = "#{manifest_path}.tmp.#{Process.pid}"
        File.write(tmp_path, JSON.pretty_generate(@manifest))
        File.rename(tmp_path, manifest_path)
      rescue StandardError
        # Best effort — don't crash if manifest write fails
        FileUtils.rm_f(tmp_path) if tmp_path
      end

      def create_empty_manifest
        {
          "version" => Konpeito::VERSION,
          "entries" => {}
        }
      end
    end
  end
end
