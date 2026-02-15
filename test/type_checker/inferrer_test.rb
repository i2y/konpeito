# frozen_string_literal: true

require "test_helper"

class InferrerTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @inferrer = Konpeito::TypeChecker::Inferrer.new(@loader)
  end

  def infer(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    @inferrer.infer(ast)
  end

  # Literal types
  def test_infer_integer
    type = infer("42")
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type
  end

  def test_infer_float
    type = infer("3.14")
    assert_equal Konpeito::TypeChecker::Types::FLOAT, type
  end

  def test_infer_string
    type = infer('"hello"')
    assert_equal Konpeito::TypeChecker::Types::STRING, type
  end

  def test_infer_symbol
    type = infer(":foo")
    assert_equal Konpeito::TypeChecker::Types::SYMBOL, type
  end

  def test_infer_true
    type = infer("true")
    assert_equal Konpeito::TypeChecker::Types::TRUE_CLASS, type
  end

  def test_infer_false
    type = infer("false")
    assert_equal Konpeito::TypeChecker::Types::FALSE_CLASS, type
  end

  def test_infer_nil
    type = infer("nil")
    assert_equal Konpeito::TypeChecker::Types::NIL, type
  end

  # Array
  def test_infer_empty_array
    type = infer("[]")
    assert_instance_of Konpeito::TypeChecker::Types::ClassInstance, type
    assert_equal :Array, type.name
  end

  def test_infer_integer_array
    type = infer("[1, 2, 3]")
    assert_instance_of Konpeito::TypeChecker::Types::ClassInstance, type
    assert_equal :Array, type.name
    assert_equal [Konpeito::TypeChecker::Types::INTEGER], type.type_args
  end

  def test_infer_mixed_array
    type = infer('[1, "hello"]')
    assert_instance_of Konpeito::TypeChecker::Types::ClassInstance, type
    assert_equal :Array, type.name
    assert type.type_args.first.union?
  end

  # Hash
  def test_infer_empty_hash
    type = infer("{}")
    assert_instance_of Konpeito::TypeChecker::Types::ClassInstance, type
    assert_equal :Hash, type.name
  end

  def test_infer_symbol_string_hash
    type = infer('{ foo: "bar" }')
    assert_instance_of Konpeito::TypeChecker::Types::ClassInstance, type
    assert_equal :Hash, type.name
    assert_equal Konpeito::TypeChecker::Types::SYMBOL, type.type_args[0]
    assert_equal Konpeito::TypeChecker::Types::STRING, type.type_args[1]
  end

  # Variable assignment
  def test_infer_local_variable_write
    type = infer("x = 42")
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type
  end

  def test_infer_local_variable_read_after_write
    # Use a single expression with multiple statements
    type = infer("x = 42; x")
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type
  end

  # Control flow
  def test_infer_if_expression
    type = infer('if true; 1; else; "str"; end')
    assert type.union?
  end

  def test_infer_if_without_else
    type = infer("if true; 1; end")
    assert type.union?
  end

  # Method call
  def test_infer_comparison_returns_bool
    type = infer("1 == 2")
    assert_equal Konpeito::TypeChecker::Types::BOOL, type
  end

  def test_infer_to_s_returns_string
    type = infer("42.to_s")
    assert_equal Konpeito::TypeChecker::Types::STRING, type
  end

  def test_infer_to_i_returns_integer
    type = infer('"42".to_i')
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type
  end

  # Method definition
  def test_infer_def_returns_symbol
    type = infer("def foo; end")
    assert_equal Konpeito::TypeChecker::Types::SYMBOL, type
  end
end
