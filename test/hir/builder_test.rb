# frozen_string_literal: true

require "test_helper"

class HIRBuilderTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
  end

  def build_hir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    @hir_builder.build(typed_ast)
  end

  def test_build_returns_program
    program = build_hir("42")
    assert_instance_of Konpeito::HIR::Program, program
  end

  def test_program_has_main_function
    program = build_hir("42")
    assert program.functions.any? { |f| f.name == "__main__" }
  end

  def test_integer_literal_generates_integer_lit
    program = build_hir("42")
    main = program.functions.find { |f| f.name == "__main__" }
    entry = main.entry_block

    int_lit = entry.instructions.find { |i| i.is_a?(Konpeito::HIR::IntegerLit) }
    refute_nil int_lit
    assert_equal 42, int_lit.value
  end

  def test_string_literal_generates_string_lit
    program = build_hir('"hello"')
    main = program.functions.find { |f| f.name == "__main__" }
    entry = main.entry_block

    str_lit = entry.instructions.find { |i| i.is_a?(Konpeito::HIR::StringLit) }
    refute_nil str_lit
    assert_equal "hello", str_lit.value
  end

  def test_method_definition_creates_function
    program = build_hir("def foo; 42; end")
    foo = program.functions.find { |f| f.name == "foo" }

    refute_nil foo
    assert foo.is_instance_method
  end

  def test_method_with_params
    program = build_hir("def add(a, b); a + b; end")
    add = program.functions.find { |f| f.name == "add" }

    refute_nil add
    assert_equal 2, add.params.size
    assert_equal "a", add.params[0].name
    assert_equal "b", add.params[1].name
  end

  def test_local_variable_assignment
    program = build_hir("x = 42")
    main = program.functions.find { |f| f.name == "__main__" }
    entry = main.entry_block

    store = entry.instructions.find { |i| i.is_a?(Konpeito::HIR::StoreLocal) }
    refute_nil store
    assert_equal "x", store.var.name
  end

  def test_if_generates_branch
    program = build_hir("if true; 1; else; 2; end")
    main = program.functions.find { |f| f.name == "__main__" }

    # Should have multiple blocks
    assert main.body.size > 1

    # Entry should have a branch terminator
    entry = main.entry_block
    assert_instance_of Konpeito::HIR::Branch, entry.terminator
  end

  def test_while_generates_loop_blocks
    program = build_hir("while true; 1; end")
    main = program.functions.find { |f| f.name == "__main__" }

    # Should have condition, body, and exit blocks
    assert main.body.size >= 3

    # Should have jumps back to condition
    body_block = main.body.find { |b| b.label.include?("body") }
    if body_block&.terminator
      assert_instance_of Konpeito::HIR::Jump, body_block.terminator
    end
  end

  def test_method_call_generates_call
    program = build_hir("1 + 2")
    main = program.functions.find { |f| f.name == "__main__" }
    entry = main.entry_block

    call = entry.instructions.find { |i| i.is_a?(Konpeito::HIR::Call) }
    refute_nil call
    assert_equal "+", call.method_name
  end

  def test_array_literal
    program = build_hir("[1, 2, 3]")
    main = program.functions.find { |f| f.name == "__main__" }
    entry = main.entry_block

    array = entry.instructions.find { |i| i.is_a?(Konpeito::HIR::ArrayLit) }
    refute_nil array
    assert_equal 3, array.elements.size
  end

  def test_return_generates_return_terminator
    program = build_hir("def foo; return 42; end")
    foo = program.functions.find { |f| f.name == "foo" }
    entry = foo.entry_block

    assert_instance_of Konpeito::HIR::Return, entry.terminator
  end
end
