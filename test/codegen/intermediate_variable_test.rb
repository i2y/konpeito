# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class IntermediateVariableTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_intermediate_variable_unboxed_float
    # Test that intermediate variables preserve unboxed Float type
    source = <<~RUBY
      def compute_distance(x1, y1, x2, y2)
        dx = x2 - x1
        dy = y2 - y1
        dx * dx + dy * dy
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def compute_distance: (Float x1, Float y1, Float x2, Float y2) -> Float
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # The intermediate variables dx and dy should use unboxed Float operations
    # Check that fsub is used for subtraction (not rb_funcallv)
    assert_match(/fsub double/, ir, "dx = x2 - x1 should use fsub for unboxed Float subtraction")

    # Check that fmul is used for multiplication (not rb_funcallv)
    assert_match(/fmul double/, ir, "dx * dx should use fmul for unboxed Float multiplication")

    # Check that fadd is used for addition (not rb_funcallv)
    assert_match(/fadd double/, ir, "Should use fadd for unboxed Float addition")
  end

  def test_intermediate_variable_unboxed_integer
    # Test that intermediate variables preserve unboxed Integer type
    source = <<~RUBY
      def compute_sum_squares(a, b)
        diff = a - b
        sum = a + b
        diff * diff + sum * sum
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def compute_sum_squares: (Integer a, Integer b) -> Integer
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Check that sub is used for subtraction
    assert_match(/sub i64/, ir, "diff = a - b should use sub for unboxed Integer subtraction")

    # Check that mul is used for multiplication
    assert_match(/mul i64/, ir, "diff * diff should use mul for unboxed Integer multiplication")

    # Check that add is used for addition
    assert_match(/add i64/, ir, "Should use add for unboxed Integer addition")
  end

  def test_chained_intermediate_variables
    # Test that chained intermediate variables maintain unboxed types
    source = <<~RUBY
      def compute_chain(a, b, c)
        temp1 = a + b
        temp2 = temp1 * c
        temp3 = temp2 - a
        temp3 + b
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def compute_chain: (Float a, Float b, Float c) -> Float
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # All operations should be unboxed
    assert_match(/fadd double/, ir, "temp1 = a + b should use fadd")
    assert_match(/fmul double/, ir, "temp2 = temp1 * c should use fmul")
    assert_match(/fsub double/, ir, "temp3 = temp2 - a should use fsub")
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

    # Generate LLVM IR
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "intermediate_var_test")
    llvm_gen.generate(hir)
    llvm_gen.to_ir
  end
end
