# frozen_string_literal: true

require "test_helper"

class TypedASTTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @builder = Konpeito::AST::TypedASTBuilder.new(@loader)
  end

  def build(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    @builder.build(ast)
  end

  def test_typed_node_has_type
    typed = build("42")
    assert_instance_of Konpeito::AST::TypedNode, typed
    refute_nil typed.type
  end

  def test_integer_literal_has_integer_type
    typed = build("42")
    # Program -> Statements -> Integer
    integer_node = typed.children.first.children.first
    assert_equal :integer, integer_node.node_type
    assert_equal Konpeito::TypeChecker::Types::INTEGER, integer_node.type
  end

  def test_string_literal_has_string_type
    typed = build('"hello"')
    string_node = typed.children.first.children.first
    assert_equal :string, string_node.node_type
    assert_equal Konpeito::TypeChecker::Types::STRING, string_node.type
  end

  def test_array_has_array_type
    typed = build("[1, 2, 3]")
    array_node = typed.children.first.children.first
    assert_equal :array, array_node.node_type
    assert_instance_of Konpeito::TypeChecker::Types::ClassInstance, array_node.type
    assert_equal :Array, array_node.type.name
  end

  def test_if_expression_has_children
    typed = build("if true; 1; else; 2; end")
    if_node = typed.children.first.children.first
    assert_equal :if, if_node.node_type
    assert if_node.children.size >= 2  # predicate + branches
  end

  def test_method_definition_has_body
    typed = build("def foo; 42; end")
    def_node = typed.children.first.children.first
    assert_equal :def, def_node.node_type
    refute_empty def_node.children
  end

  def test_method_call_has_receiver_and_args
    typed = build("1 + 2")
    call_node = typed.children.first.children.first
    assert_equal :call, call_node.node_type
    # Should have receiver (1) and arguments (2)
    assert call_node.children.size >= 2
  end

  def test_local_variable_assignment_has_value_child
    typed = build("x = 42")
    write_node = typed.children.first.children.first
    assert_equal :local_variable_write, write_node.node_type
    assert_equal 1, write_node.children.size
    assert_equal :integer, write_node.children.first.node_type
  end

  def test_class_definition
    typed = build("class Foo; end")
    class_node = typed.children.first.children.first
    assert_equal :class, class_node.node_type
  end
end
