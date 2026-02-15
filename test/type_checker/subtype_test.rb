# frozen_string_literal: true

require "test_helper"

class SubtypeTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
  end

  # Internal Types module tests
  def test_integer_subtype_of_numeric
    int_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Integer)
    num_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Numeric)
    assert int_type.subtype_of?(num_type)
  end

  def test_float_subtype_of_numeric
    float_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Float)
    num_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Numeric)
    assert float_type.subtype_of?(num_type)
  end

  def test_integer_subtype_of_object
    int_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Integer)
    obj_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Object)
    assert int_type.subtype_of?(obj_type)
  end

  def test_string_not_subtype_of_numeric
    str_type = Konpeito::TypeChecker::Types::ClassInstance.new(:String)
    num_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Numeric)
    refute str_type.subtype_of?(num_type)
  end

  def test_runtime_error_subtype_of_standard_error
    runtime_type = Konpeito::TypeChecker::Types::ClassInstance.new(:RuntimeError)
    std_type = Konpeito::TypeChecker::Types::ClassInstance.new(:StandardError)
    assert runtime_type.subtype_of?(std_type)
  end

  def test_type_error_subtype_of_exception
    type_error = Konpeito::TypeChecker::Types::ClassInstance.new(:TypeError)
    exception = Konpeito::TypeChecker::Types::ClassInstance.new(:Exception)
    assert type_error.subtype_of?(exception)
  end

  def test_same_type_is_subtype
    int_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Integer)
    assert int_type.subtype_of?(int_type)
  end

  def test_untyped_is_subtype_of_anything
    untyped = Konpeito::TypeChecker::Types::UNTYPED
    int_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Integer)
    assert untyped.subtype_of?(int_type)
  end

  # Union type tests
  def test_union_subtype
    int_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Integer)
    str_type = Konpeito::TypeChecker::Types::ClassInstance.new(:String)
    obj_type = Konpeito::TypeChecker::Types::ClassInstance.new(:Object)

    union = Konpeito::TypeChecker::Types::Union.new([int_type, str_type])
    # Union of subtypes should be subtype of common ancestor
    assert union.subtype_of?(obj_type)
  end

  # RBS subtype tests (if RBS types are available)
  def test_rbs_integer_subtype_of_numeric
    skip "RBS not fully loaded" unless @loader.loaded?

    int_type = RBS::Types::ClassInstance.new(
      name: RBS::TypeName.new(name: :Integer, namespace: RBS::Namespace.root),
      args: [],
      location: nil
    )
    num_type = RBS::Types::ClassInstance.new(
      name: RBS::TypeName.new(name: :Numeric, namespace: RBS::Namespace.root),
      args: [],
      location: nil
    )

    assert @loader.subtype?(int_type, num_type)
  end

  def test_rbs_string_not_subtype_of_integer
    skip "RBS not fully loaded" unless @loader.loaded?

    str_type = RBS::Types::ClassInstance.new(
      name: RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root),
      args: [],
      location: nil
    )
    int_type = RBS::Types::ClassInstance.new(
      name: RBS::TypeName.new(name: :Integer, namespace: RBS::Namespace.root),
      args: [],
      location: nil
    )

    refute @loader.subtype?(str_type, int_type)
  end

  def test_rbs_any_accepts_all
    skip "RBS not fully loaded" unless @loader.loaded?

    int_type = RBS::Types::ClassInstance.new(
      name: RBS::TypeName.new(name: :Integer, namespace: RBS::Namespace.root),
      args: [],
      location: nil
    )
    any_type = RBS::Types::Bases::Any.new(location: nil)

    assert @loader.subtype?(int_type, any_type)
  end
end
