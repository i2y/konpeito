# frozen_string_literal: true

require "test_helper"
require "konpeito/cache"
require "tmpdir"

class CacheManagerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("konpeito_cache_test")
    @cache = Konpeito::Cache::CacheManager.new(cache_dir: @tmpdir)

    # Create a test source file
    @test_file = File.join(@tmpdir, "test.rb")
    File.write(@test_file, "def foo; 42; end")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_file_hash
    hash = @cache.file_hash(@test_file)
    assert_kind_of String, hash
    assert_equal 64, hash.length  # SHA256 hex length
  end

  def test_file_hash_changes_with_content
    hash1 = @cache.file_hash(@test_file)
    File.write(@test_file, "def bar; 100; end")
    hash2 = @cache.file_hash(@test_file)

    refute_equal hash1, hash2
  end

  def test_needs_recompile_new_file
    assert @cache.needs_recompile?(@test_file)
  end

  def test_put_and_get_ast
    ast = { type: :program, body: [:def, :foo] }  # Simplified AST for testing
    @cache.put_ast(@test_file, ast)

    retrieved = @cache.get_ast(@test_file)
    assert_equal ast, retrieved
  end

  def test_get_ast_returns_nil_when_file_changed
    ast = { type: :program }
    @cache.put_ast(@test_file, ast)

    # Modify the file
    File.write(@test_file, "def bar; 200; end")

    # Cache should return nil since file changed
    assert_nil @cache.get_ast(@test_file)
  end

  def test_put_and_get_types
    types_data = { function_types: { foo: "() -> Integer" } }
    @cache.put_types(@test_file, types_data)

    retrieved = @cache.get_types(@test_file)
    assert_equal types_data, retrieved
  end

  def test_invalidate
    ast = { type: :program }
    @cache.put_ast(@test_file, ast)
    @cache.invalidate(@test_file)

    assert_nil @cache.get_ast(@test_file)
  end

  def test_invalidate_propagates_to_dependents
    # Create dependent files
    main_file = File.join(@tmpdir, "main.rb")
    util_file = File.join(@tmpdir, "util.rb")
    File.write(main_file, "require_relative 'util'")
    File.write(util_file, "def helper; end")

    # Cache both
    @cache.put_ast(main_file, { main: true })
    @cache.put_ast(util_file, { util: true })
    @cache.add_dependency(main_file, util_file)

    # Invalidate util - should also invalidate main
    @cache.invalidate(util_file)

    assert_nil @cache.get_ast(util_file)
    assert_nil @cache.get_ast(main_file)
  end

  def test_clean
    @cache.put_ast(@test_file, { type: :program })
    @cache.clean!

    assert_nil @cache.get_ast(@test_file)
    assert_empty @cache.cached_files
  end

  def test_manifest_persistence
    @cache.put_ast(@test_file, { type: :program })
    @cache.save_manifest

    # Create new cache instance pointing to same directory
    new_cache = Konpeito::Cache::CacheManager.new(cache_dir: @tmpdir)

    # Should be able to read cached AST
    assert_equal({ type: :program }, new_cache.get_ast(@test_file))
  end

  def test_dependency_graph_integration
    main_file = File.join(@tmpdir, "main.rb")
    util_file = File.join(@tmpdir, "util.rb")
    File.write(main_file, "# main")
    File.write(util_file, "# util")

    @cache.add_dependency(main_file, util_file)

    order = @cache.get_recompile_order([util_file])
    assert_includes order, main_file
    assert_includes order, util_file
  end

  def test_cache_exists
    refute @cache.cache_exists?  # New cache, no manifest saved yet

    @cache.put_ast(@test_file, { type: :program })
    @cache.save_manifest

    assert @cache.cache_exists?
  end
end
