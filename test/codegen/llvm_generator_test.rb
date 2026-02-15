# frozen_string_literal: true

require "test_helper"

class LLVMGeneratorTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test")
  end

  def compile_to_ir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)
    @llvm_gen.generate(hir)
    @llvm_gen.to_ir
  end

  def test_generates_llvm_module
    ir = compile_to_ir("42")
    assert_includes ir, "ModuleID"
  end

  def test_generates_main_function
    ir = compile_to_ir("42")
    assert_includes ir, "rn___main__"
  end

  def test_integer_literal_calls_rb_int2inum
    ir = compile_to_ir("42")
    assert_includes ir, "rb_int2inum"
  end

  def test_string_literal_calls_rb_str_new_cstr
    ir = compile_to_ir('"hello"')
    assert_includes ir, "rb_str_new_cstr"
    assert_includes ir, "hello"
  end

  def test_method_call_uses_rb_funcallv
    ir = compile_to_ir("1 + 2")
    assert_includes ir, "rb_funcallv"
    assert_includes ir, "rb_intern"
  end

  def test_method_definition_creates_function
    ir = compile_to_ir("def foo; 42; end")
    assert_includes ir, "rn_foo"
  end

  def test_local_variable_assignment
    ir = compile_to_ir("x = 42")
    # Should have alloca or store instruction
    assert_includes ir, "rb_int2inum"
  end

  def test_if_generates_branches
    ir = compile_to_ir("if true; 1; else; 2; end")
    assert_includes ir, "br "  # branch instruction
  end

  def test_array_literal_calls_rb_ary_new
    ir = compile_to_ir("[1, 2, 3]")
    assert_includes ir, "rb_ary_new_capa"
    assert_includes ir, "rb_ary_push"
  end

  def test_hash_literal_calls_rb_hash_new
    ir = compile_to_ir("{ a: 1 }")
    assert_includes ir, "rb_hash_new"
    assert_includes ir, "rb_hash_aset"
  end

  def test_symbol_literal_uses_rb_id2sym
    ir = compile_to_ir(":foo")
    assert_includes ir, "rb_intern"
    assert_includes ir, "rb_id2sym"
  end

  def test_return_generates_ret
    ir = compile_to_ir("def foo; return 42; end")
    # Functions should have ret instruction
    assert_includes ir, "ret "
  end
end
