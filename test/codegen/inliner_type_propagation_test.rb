# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

# Test that inlined functions preserve unboxed type propagation
class InlinerTypePropagationTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_inlined_function_uses_unboxed_arithmetic
    # Small function that should be inlined
    source = <<~RUBY
      def square(x)
        x * x
      end

      def sum_of_squares(a, b)
        square(a) + square(b)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def square: (Float x) -> Float
        def sum_of_squares: (Float a, Float b) -> Float
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Check that fmul is used for multiplication (unboxed Float)
    assert_match(/fmul double/, ir, "Inlined square should use fmul for unboxed Float multiplication")

    # Check that fadd is used for addition (unboxed Float)
    assert_match(/fadd double/, ir, "sum_of_squares should use fadd for unboxed Float addition")
  end

  def test_inlined_function_with_intermediate_variable
    # Function with intermediate variable that gets inlined
    source = <<~RUBY
      def compute(x, y)
        diff = x - y
        diff * diff
      end

      def distance_squared(x1, x2)
        compute(x1, x2)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def compute: (Float x, Float y) -> Float
        def distance_squared: (Float x1, Float x2) -> Float
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Check that fsub is used (intermediate variable diff should stay unboxed)
    assert_match(/fsub double/, ir, "Inlined compute should use fsub for unboxed Float subtraction")

    # Check that fmul is used
    assert_match(/fmul double/, ir, "Inlined compute should use fmul for unboxed Float multiplication")
  end

  private

  def compile_to_ir(source, rbs)
    # Write files
    rbs_path = File.join(@tmp_dir, "test.rbs")
    source_path = File.join(@tmp_dir, "test.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    # Load RBS
    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Build typed AST
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    # Build HIR
    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    # Apply inliner
    inliner = Konpeito::Codegen::Inliner.new(hir)
    inliner.optimize

    # Generate LLVM IR
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "inliner_test")
    llvm_gen.generate(hir)
    llvm_gen.to_ir
  end
end
