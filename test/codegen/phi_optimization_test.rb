# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class PhiOptimizationTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_if_integer_unboxed
    # Test that if/else with all Integer branches generates unboxed phi
    source = <<~RUBY
      def choose_int(cond)
        if cond
          10
        else
          20
        end
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def choose_int: (bool cond) -> Integer
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Should have phi with i64 type (not calling rb_int2inum before phi)
    # The phi should be: phi i64 [ 10, %... ], [ 20, %... ]
    assert_match(/phi i64.*\[ 10,/, ir, "Should generate unboxed i64 phi for Integer branches")
  end

  def test_if_float_unboxed
    # Test that if/else with all Float branches generates unboxed phi
    source = <<~RUBY
      def choose_float(cond)
        if cond
          1.5
        else
          2.5
        end
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def choose_float: (bool cond) -> Float
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Should have phi with double type
    assert_match(/phi double/, ir, "Should generate unboxed double phi for Float branches")
  end

  def test_case_integer_unboxed
    # Test that case/when with all Integer branches generates unboxed phi
    source = <<~RUBY
      def classify(n)
        case n
        when 1 then 10
        when 2 then 20
        else 30
        end
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def classify: (Integer n) -> Integer
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Should have phi with i64 type for case_merge block
    assert_match(/case_merge:.*phi i64/m, ir, "Should generate unboxed i64 phi for case/when Integer branches")
  end

  def test_case_float_unboxed
    # Test that case/when with all Float branches generates unboxed phi
    source = <<~RUBY
      def classify_float(n)
        case n
        when 1 then 1.5
        when 2 then 2.5
        else 3.5
        end
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def classify_float: (Integer n) -> Float
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Should have phi with double type
    assert_match(/case_merge:.*phi double/m, ir, "Should generate unboxed double phi for case/when Float branches")
  end

  def test_mixed_types_boxed
    # Test that mixed types fall back to boxing
    source = <<~RUBY
      def choose_mixed(cond)
        if cond
          1
        else
          nil
        end
      end
    RUBY

    ir = compile_to_ir(source, nil)

    # Should call rb_int2inum to box the integer for phi
    assert_match(/rb_int2inum/, ir, "Should box Integer when mixed with nil")
  end

  def test_int_float_promotion
    # Test that Integer/Float mix promotes to Float
    source = <<~RUBY
      def choose_numeric(cond)
        if cond
          1
        else
          2.5
        end
      end
    RUBY

    ir = compile_to_ir(source, nil)

    # Should have phi with double type
    # Note: For compile-time constants, LLVM converts 1 to 1.0 directly
    # (no sitofp needed for constant-to-constant conversion)
    assert_match(/phi double/, ir, "Should promote to double phi for Integer/Float mix")
    # The integer 1 should be converted to 1.0 at compile time
    assert_match(/1\.0+e\+00/, ir, "Integer constant should be converted to Float constant")
  end

  def test_unboxed_phi_arithmetic
    # Test that unboxed phi result can be used in subsequent unboxed arithmetic
    source = <<~RUBY
      def compute(cond, x)
        base = if cond then 10 else 20 end
        base * x + 5
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def compute: (bool cond, Integer x) -> Integer
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # The phi should be unboxed and used directly in mul/add
    assert_match(/phi i64/, ir, "Should have unboxed phi")
    assert_match(/mul i64/, ir, "Should use unboxed mul for base * x")
    assert_match(/add i64/, ir, "Should use unboxed add for ... + 5")
  end

  def test_case_in_integer_unboxed
    # Test that case/in with all Integer branches generates unboxed phi
    source = <<~RUBY
      def match_int(x)
        case x
        in 1 then 100
        in 2 then 200
        else 300
        end
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def match_int: (Integer x) -> Integer
      end
    RBS

    ir = compile_to_ir(source, rbs)

    # Should have phi with i64 type for match_merge block
    assert_match(/match_merge:.*phi i64/m, ir, "Should generate unboxed i64 phi for case/in Integer branches")
  end

  private

  def compile_to_ir(source, rbs)
    # Write files
    source_path = File.join(@tmp_dir, "test.rb")
    File.write(source_path, source)

    if rbs
      rbs_path = File.join(@tmp_dir, "test.rbs")
      File.write(rbs_path, rbs)
      loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])
    else
      loader = Konpeito::TypeChecker::RBSLoader.new.load
    end

    # Build typed AST
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    # Build HIR
    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    # Generate LLVM IR
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "phi_opt_test")
    llvm_gen.generate(hir)
    llvm_gen.to_ir
  end
end
