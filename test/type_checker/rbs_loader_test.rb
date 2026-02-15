# frozen_string_literal: true

require "test_helper"

class RBSLoaderTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new
    @loader.load
  end

  def test_loaded_after_load
    assert @loader.loaded?
  end

  def test_type_exists_for_core_types
    assert @loader.type_exists?(:Integer)
    assert @loader.type_exists?(:String)
    assert @loader.type_exists?(:Array)
    assert @loader.type_exists?(:Hash)
  end

  def test_type_exists_returns_false_for_unknown_type
    refute @loader.type_exists?(:NonExistentType12345)
  end

  def test_method_type_for_integer_plus
    types = @loader.method_type(:Integer, :+)
    refute_nil types
    refute_empty types
  end

  def test_method_type_for_string_upcase
    types = @loader.method_type(:String, :upcase)
    refute_nil types
    refute_empty types
  end

  def test_instance_methods_for_string
    methods = @loader.instance_methods(:String)
    assert_includes methods, :upcase
    assert_includes methods, :downcase
    assert_includes methods, :length
  end

  def test_parse_type
    type = @loader.parse_type("Integer")
    assert_instance_of RBS::Types::ClassInstance, type
    assert_equal :Integer, type.name.name
  end

  def test_parse_type_with_generics
    type = @loader.parse_type("Array[String]")
    assert_instance_of RBS::Types::ClassInstance, type
    assert_equal :Array, type.name.name
    assert_equal 1, type.args.size
  end
end
