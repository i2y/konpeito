# frozen_string_literal: true

require "test_helper"
require "konpeito/cache"

class DependencyGraphTest < Minitest::Test
  def setup
    @graph = Konpeito::Cache::DependencyGraph.new
  end

  def test_add_dependency
    @graph.add_dependency("/a.rb", "/b.rb")

    assert_equal ["/b.rb"], @graph.get_dependencies("/a.rb")
    assert_equal ["/a.rb"], @graph.get_direct_dependents("/b.rb")
  end

  def test_get_all_dependents_transitive
    # a -> b -> c (a depends on b, b depends on c)
    @graph.add_dependency("/a.rb", "/b.rb")
    @graph.add_dependency("/b.rb", "/c.rb")

    # If c changes, both a and b need recompilation
    dependents = @graph.get_all_dependents("/c.rb")
    assert_includes dependents, "/a.rb"
    assert_includes dependents, "/b.rb"
  end

  def test_invalidation_order
    # a -> b -> c
    @graph.add_dependency("/a.rb", "/b.rb")
    @graph.add_dependency("/b.rb", "/c.rb")

    # If c changes, order should be: c, b, a (dependencies first)
    order = @graph.invalidation_order(["/c.rb"])

    # c should come before b and a
    c_idx = order.index("/c.rb")
    b_idx = order.index("/b.rb")
    a_idx = order.index("/a.rb")

    assert c_idx < b_idx, "c should be processed before b"
    assert b_idx < a_idx, "b should be processed before a"
  end

  def test_remove
    @graph.add_dependency("/a.rb", "/b.rb")
    @graph.remove("/b.rb")

    assert_empty @graph.get_dependencies("/a.rb")
    assert_empty @graph.get_direct_dependents("/b.rb")
  end

  def test_clear_dependencies
    @graph.add_dependency("/a.rb", "/b.rb")
    @graph.add_dependency("/a.rb", "/c.rb")
    @graph.clear_dependencies("/a.rb")

    assert_empty @graph.get_dependencies("/a.rb")
    # b and c should no longer have a as dependent
    assert_empty @graph.get_direct_dependents("/b.rb")
    assert_empty @graph.get_direct_dependents("/c.rb")
  end

  def test_serialization
    @graph.add_dependency("/a.rb", "/b.rb")
    @graph.add_dependency("/b.rb", "/c.rb")

    hash = @graph.to_h
    restored = Konpeito::Cache::DependencyGraph.from_h(hash)

    assert_equal ["/b.rb"], restored.get_dependencies("/a.rb")
    assert_equal ["/c.rb"], restored.get_dependencies("/b.rb")
  end

  def test_all_files
    @graph.add_dependency("/a.rb", "/b.rb")
    @graph.add_dependency("/c.rb", "/b.rb")

    files = @graph.all_files.sort
    assert_equal ["/a.rb", "/b.rb", "/c.rb"], files
  end

  def test_path_normalization
    # Relative paths should be normalized
    @graph.add_dependency("./a.rb", "./b.rb")

    # Should use absolute paths internally
    assert @graph.has_dependencies?(File.expand_path("./a.rb"))
  end
end
