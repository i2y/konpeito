# frozen_string_literal: true

require "test_helper"

class ProcLambdaTest < Minitest::Test
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

  def compile_to_hir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    @hir_builder.build(typed_ast)
  end

  # Test that lambda literal creates ProcNew HIR node
  def test_lambda_creates_proc_new_hir
    hir = compile_to_hir(<<~RUBY)
      def test
        f = ->(x) { x * 2 }
        f
      end
    RUBY

    test_func = hir.functions.find { |f| f.name == "test" }
    assert test_func, "Should have test function"

    # Find the ProcNew instruction
    proc_new_inst = nil
    test_func.body.each do |block|
      block.instructions.each do |inst|
        if inst.is_a?(Konpeito::HIR::ProcNew)
          proc_new_inst = inst
          break
        end
      end
    end

    assert proc_new_inst, "Should have ProcNew instruction"
    assert proc_new_inst.block_def, "ProcNew should have block_def"
    assert proc_new_inst.block_def.is_lambda, "block_def should be marked as lambda"
  end

  # Test that lambda params are captured
  def test_lambda_params
    hir = compile_to_hir(<<~RUBY)
      def test
        f = ->(x, y) { x + y }
        f
      end
    RUBY

    test_func = hir.functions.find { |f| f.name == "test" }
    proc_new_inst = nil
    test_func.body.each do |block|
      block.instructions.each do |inst|
        if inst.is_a?(Konpeito::HIR::ProcNew)
          proc_new_inst = inst
          break
        end
      end
    end

    assert proc_new_inst, "Should have ProcNew instruction"
    assert_equal 2, proc_new_inst.block_def.params.size, "Lambda should have 2 params"
  end

  # Test that LLVM IR is generated for lambda
  def test_lambda_generates_llvm_ir
    ir = compile_to_ir(<<~RUBY)
      def test
        f = ->(x) { x }
        f
      end
    RUBY

    # Should have rb_proc_new call
    assert_includes ir, "rb_proc_new"
    # Should have a callback function for the lambda
    assert_includes ir, "block_callback_proc"
  end

  # Test lambda with no params
  def test_lambda_no_params
    hir = compile_to_hir(<<~RUBY)
      def test
        f = -> { 42 }
        f
      end
    RUBY

    test_func = hir.functions.find { |f| f.name == "test" }
    proc_new_inst = nil
    test_func.body.each do |block|
      block.instructions.each do |inst|
        if inst.is_a?(Konpeito::HIR::ProcNew)
          proc_new_inst = inst
          break
        end
      end
    end

    assert proc_new_inst, "Should have ProcNew instruction"
    assert_equal 0, proc_new_inst.block_def.params.size, "Lambda should have 0 params"
  end

  # Test rb_proc_call is declared
  def test_proc_call_declaration
    ir = compile_to_ir("42")
    assert_includes ir, "@rb_proc_call"
  end
end
