# frozen_string_literal: true

require "test_helper"

class PrismAdapterTest < Minitest::Test
  def test_parse_simple_integer
    ast = Konpeito::Parser::PrismAdapter.parse("42")
    assert_instance_of Prism::ProgramNode, ast
  end

  def test_parse_method_definition
    source = <<~RUBY
      def add(a, b)
        a + b
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    assert_instance_of Prism::ProgramNode, ast

    statements = ast.statements.body
    assert_equal 1, statements.size
    assert_instance_of Prism::DefNode, statements.first
  end

  def test_parse_class_definition
    source = <<~RUBY
      class Calculator
        def add(a, b)
          a + b
        end
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    statements = ast.statements.body
    assert_equal 1, statements.size
    assert_instance_of Prism::ClassNode, statements.first
  end

  def test_parse_error_raises_exception
    assert_raises Konpeito::ParseError do
      Konpeito::Parser::PrismAdapter.parse("def foo(")
    end
  end

  def test_parse_error_includes_location
    error = assert_raises Konpeito::ParseError do
      Konpeito::Parser::PrismAdapter.parse("def foo(\nend")
    end

    assert_includes error.message, "(eval):2"
  end
end
