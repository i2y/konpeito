# frozen_string_literal: true

require "test_helper"
require "fileutils"

class LogicalOperatorsTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = File.join(__dir__, "..", "tmp")
    FileUtils.mkdir_p(@output_dir)
  end

  def teardown
    FileUtils.rm_rf(@output_dir)
  end

  def compile_to_bundle(source, name)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: name)
    llvm_gen.generate(hir)

    output_file = File.join(@output_dir, "#{name}.bundle")
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: output_file,
      module_name: name
    )
    backend.generate
    output_file
  end

  # ========================================
  # && (AND) Tests
  # ========================================

  def test_and_both_truthy
    source = <<~RUBY
      def and_both_truthy
        1 && 42
      end
    RUBY
    output = compile_to_bundle(source, "test_and_both_truthy")
    require output
    assert_equal 42, and_both_truthy
  end

  def test_and_left_falsy_nil
    source = <<~RUBY
      def and_left_nil
        nil && 42
      end
    RUBY
    output = compile_to_bundle(source, "test_and_left_nil")
    require output
    assert_nil and_left_nil
  end

  def test_and_left_falsy_false
    source = <<~RUBY
      def and_left_false
        false && 42
      end
    RUBY
    output = compile_to_bundle(source, "test_and_left_false")
    require output
    assert_equal false, and_left_false
  end

  def test_and_short_circuit
    source = <<~RUBY
      def and_short_circuit(x)
        nil && x
      end
    RUBY
    output = compile_to_bundle(source, "test_and_short_circuit")
    require output
    # Right side should not matter since left is nil
    assert_nil and_short_circuit(99)
  end

  # ========================================
  # || (OR) Tests
  # ========================================

  def test_or_left_truthy
    source = <<~RUBY
      def or_left_truthy
        1 || 42
      end
    RUBY
    output = compile_to_bundle(source, "test_or_left_truthy")
    require output
    assert_equal 1, or_left_truthy
  end

  def test_or_left_falsy
    source = <<~RUBY
      def or_left_falsy
        nil || 42
      end
    RUBY
    output = compile_to_bundle(source, "test_or_left_falsy")
    require output
    assert_equal 42, or_left_falsy
  end

  def test_or_left_false
    source = <<~RUBY
      def or_left_false_val
        false || "hello"
      end
    RUBY
    output = compile_to_bundle(source, "test_or_left_false_val")
    require output
    assert_equal "hello", or_left_false_val
  end

  def test_or_both_falsy
    source = <<~RUBY
      def or_both_falsy
        nil || false
      end
    RUBY
    output = compile_to_bundle(source, "test_or_both_falsy")
    require output
    assert_equal false, or_both_falsy
  end

  # ========================================
  # Nested logical operators
  # ========================================

  def test_nested_and_or
    source = <<~RUBY
      def nested_and_or
        (nil || 1) && 2
      end
    RUBY
    output = compile_to_bundle(source, "test_nested_and_or")
    require output
    assert_equal 2, nested_and_or
  end

  def test_nested_or_and
    source = <<~RUBY
      def nested_or_and
        (nil && 1) || 42
      end
    RUBY
    output = compile_to_bundle(source, "test_nested_or_and")
    require output
    assert_equal 42, nested_or_and
  end

  def test_chained_or
    source = <<~RUBY
      def chained_or
        nil || false || 99
      end
    RUBY
    output = compile_to_bundle(source, "test_chained_or")
    require output
    assert_equal 99, chained_or
  end

  def test_chained_and
    source = <<~RUBY
      def chained_and
        1 && 2 && 3
      end
    RUBY
    output = compile_to_bundle(source, "test_chained_and")
    require output
    assert_equal 3, chained_and
  end

  # ========================================
  # Logical operators with variables
  # ========================================

  def test_and_with_variable
    source = <<~RUBY
      def and_with_var(x)
        x && 10
      end
    RUBY
    output = compile_to_bundle(source, "test_and_with_var")
    require output
    assert_equal 10, and_with_var(5)
    assert_nil and_with_var(nil)
  end

  def test_or_with_variable
    source = <<~RUBY
      def or_with_var(x)
        x || 10
      end
    RUBY
    output = compile_to_bundle(source, "test_or_with_var")
    require output
    assert_equal 5, or_with_var(5)
    assert_equal 10, or_with_var(nil)
  end

  # ========================================
  # Logical NOT (!) - already works via visit_call
  # ========================================

  def test_not_operator
    source = <<~RUBY
      def not_true
        !true
      end

      def not_false
        !false
      end

      def not_nil
        !nil
      end
    RUBY
    output = compile_to_bundle(source, "test_not_operator")
    require output
    assert_equal false, not_true
    assert_equal true, not_false
    assert_equal true, not_nil
  end
end
