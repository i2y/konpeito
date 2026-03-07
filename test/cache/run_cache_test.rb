# frozen_string_literal: true

require "test_helper"
require "konpeito/cache"
require "tmpdir"

class RunCacheTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("konpeito_run_cache_test")
    @cache = Konpeito::Cache::RunCache.new(cache_dir: @tmpdir)

    # Create test source files
    @src_dir = File.join(@tmpdir, "src")
    FileUtils.mkdir_p(@src_dir)
    @source1 = File.join(@src_dir, "main.rb")
    @source2 = File.join(@src_dir, "helper.rb")
    @rbs1 = File.join(@src_dir, "main.rbs")
    File.write(@source1, "def main; 42; end")
    File.write(@source2, "def helper; 1; end")
    File.write(@rbs1, "module TopLevel\n  def main: () -> Integer\nend")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_compute_cache_key_consistent
    key1 = @cache.compute_cache_key(
      source_files: [@source1, @source2],
      rbs_files: [@rbs1],
      options_hash: { "inline_rbs" => "false", "target" => "native" }
    )
    key2 = @cache.compute_cache_key(
      source_files: [@source1, @source2],
      rbs_files: [@rbs1],
      options_hash: { "inline_rbs" => "false", "target" => "native" }
    )
    assert_equal key1, key2
    assert_equal 64, key1.length
  end

  def test_compute_cache_key_order_independent
    key1 = @cache.compute_cache_key(
      source_files: [@source1, @source2],
      rbs_files: [@rbs1],
      options_hash: { "inline_rbs" => "false" }
    )
    key2 = @cache.compute_cache_key(
      source_files: [@source2, @source1],
      rbs_files: [@rbs1],
      options_hash: { "inline_rbs" => "false" }
    )
    assert_equal key1, key2
  end

  def test_compute_cache_key_changes_with_content
    key1 = @cache.compute_cache_key(
      source_files: [@source1],
      rbs_files: [],
      options_hash: {}
    )
    File.write(@source1, "def main; 99; end")
    key2 = @cache.compute_cache_key(
      source_files: [@source1],
      rbs_files: [],
      options_hash: {}
    )
    refute_equal key1, key2
  end

  def test_compute_cache_key_changes_with_options
    key1 = @cache.compute_cache_key(
      source_files: [@source1],
      rbs_files: [],
      options_hash: { "inline_rbs" => "false" }
    )
    key2 = @cache.compute_cache_key(
      source_files: [@source1],
      rbs_files: [],
      options_hash: { "inline_rbs" => "true" }
    )
    refute_equal key1, key2
  end

  def test_compute_cache_key_changes_with_rbs
    key1 = @cache.compute_cache_key(
      source_files: [@source1],
      rbs_files: [],
      options_hash: {}
    )
    key2 = @cache.compute_cache_key(
      source_files: [@source1],
      rbs_files: [@rbs1],
      options_hash: {}
    )
    refute_equal key1, key2
  end

  def test_lookup_returns_nil_for_missing
    result = @cache.lookup("nonexistent_key", "main.bundle")
    assert_nil result
  end

  def test_store_and_lookup_round_trip
    key = "test_cache_key_abc123"
    basename = "main.bundle"

    # Create artifact in the expected location
    dir = @cache.artifact_dir(key)
    FileUtils.mkdir_p(dir)
    artifact_path = File.join(dir, basename)
    File.write(artifact_path, "fake artifact content")

    # Store
    result = @cache.store(key, basename)
    assert_equal artifact_path, result

    # Lookup
    found = @cache.lookup(key, basename)
    assert_equal artifact_path, found
    assert File.exist?(found)
  end

  def test_lookup_returns_nil_if_artifact_deleted
    key = "test_key_deleted"
    basename = "main.bundle"

    dir = @cache.artifact_dir(key)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, basename), "content")
    @cache.store(key, basename)

    # Delete the artifact file
    FileUtils.rm_rf(dir)

    assert_nil @cache.lookup(key, basename)
  end

  def test_clean_removes_all
    key = "test_clean_key"
    basename = "main.bundle"

    dir = @cache.artifact_dir(key)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, basename), "content")
    @cache.store(key, basename)

    @cache.clean!

    assert_nil @cache.lookup(key, basename)
    refute Dir.exist?(dir)
  end

  def test_cleanup_evicts_oldest
    basenames = []
    keys = []
    5.times do |i|
      key = "key_#{i}"
      basename = "file_#{i}.bundle"
      keys << key
      basenames << basename

      dir = @cache.artifact_dir(key)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, basename), "content #{i}")
      @cache.store(key, basename)
    end

    # All 5 should exist
    5.times do |i|
      assert @cache.lookup(keys[i], basenames[i])
    end

    # Now cleanup with max_entries: 3 — should evict 2 oldest
    @cache.cleanup!(max_entries: 3)

    # The 2 oldest (key_0, key_1) should be evicted
    assert_nil @cache.lookup(keys[0], basenames[0])
    assert_nil @cache.lookup(keys[1], basenames[1])

    # The 3 newest should remain
    (2..4).each do |i|
      assert @cache.lookup(keys[i], basenames[i])
    end
  end

  def test_artifact_dir
    key = "abc123"
    expected = File.join(@tmpdir, key)
    assert_equal expected, @cache.artifact_dir(key)
  end

  def test_manifest_persists_across_instances
    key = "persist_test"
    basename = "main.bundle"

    dir = @cache.artifact_dir(key)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, basename), "content")
    @cache.store(key, basename)

    # Create a new instance pointing at the same directory
    cache2 = Konpeito::Cache::RunCache.new(cache_dir: @tmpdir)
    found = cache2.lookup(key, basename)
    assert_equal File.join(dir, basename), found
  end
end
