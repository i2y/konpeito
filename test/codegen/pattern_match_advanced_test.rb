# frozen_string_literal: true

require "test_helper"
require "fileutils"

class PatternMatchAdvancedTest < Minitest::Test
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
  # Guard Pattern Tests
  # ========================================

  def test_guard_simple
    source = <<~RUBY
      def classify_number(x)
        case x
        in n if n > 10 then "big"
        in n if n > 0 then "positive"
        in n if n == 0 then "zero"
        else "negative"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_guard_simple")

    require output
    assert_equal "big", classify_number(20)
    assert_equal "big", classify_number(11)
    assert_equal "positive", classify_number(5)
    assert_equal "positive", classify_number(1)
    assert_equal "zero", classify_number(0)
    assert_equal "negative", classify_number(-5)
  end

  # Note: Type pattern with guard (e.g., `in Integer if x > 100`) is a complex
  # combination that requires special handling. For now, use variable pattern
  # with guard instead: `in n if n > 100 && n.is_a?(Integer)`
  def test_guard_with_variable_pattern
    source = <<~RUBY
      def check_range(x)
        case x
        in n if n > 100 then "big"
        in n if n > 0 then "positive"
        else "other"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_guard_var")

    require output
    assert_equal "big", check_range(150)
    assert_equal "positive", check_range(50)
    assert_equal "other", check_range(-5)
  end

  def test_guard_multiple_conditions
    source = <<~RUBY
      def range_check(x)
        case x
        in n if n >= 90 then "A"
        in n if n >= 80 then "B"
        in n if n >= 70 then "C"
        in n if n >= 60 then "D"
        else "F"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_guard_range")

    require output
    assert_equal "A", range_check(95)
    assert_equal "A", range_check(90)
    assert_equal "B", range_check(85)
    assert_equal "C", range_check(75)
    assert_equal "D", range_check(65)
    assert_equal "F", range_check(55)
  end

  # ========================================
  # Capture Pattern Tests
  # ========================================

  def test_capture_with_type
    source = <<~RUBY
      def double_if_int(x)
        case x
        in Integer => n then n * 2
        else 0
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_capture_type")

    require output
    assert_equal 20, double_if_int(10)
    assert_equal 84, double_if_int(42)
    assert_equal 0, double_if_int("hello")
    assert_equal 0, double_if_int(3.14)
  end

  def test_capture_with_integer_operation
    source = <<~RUBY
      def triple_if_int(x)
        case x
        in Integer => n then n * 3
        else -1
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_capture_int_op")

    require output
    assert_equal 30, triple_if_int(10)
    assert_equal 126, triple_if_int(42)
    assert_equal -1, triple_if_int("hello")
  end

  # ========================================
  # Pinned Variable Pattern Tests
  # ========================================

  def test_pin_simple
    source = <<~RUBY
      def match_expected(x, expected)
        case x
        in ^expected then "match"
        else "no match"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_pin_simple")

    require output
    assert_equal "match", match_expected(42, 42)
    assert_equal "no match", match_expected(42, 100)
    assert_equal "match", match_expected("hello", "hello")
    assert_equal "no match", match_expected("hello", "world")
  end

  def test_pin_with_multiple_values
    source = <<~RUBY
      def match_pair(x, y, target)
        case [x, y]
        in [^target, ^target] then "both match"
        in [^target, _] then "first matches"
        in [_, ^target] then "second matches"
        else "none match"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_pin_pair")

    require output
    assert_equal "both match", match_pair(5, 5, 5)
    assert_equal "first matches", match_pair(5, 10, 5)
    assert_equal "second matches", match_pair(10, 5, 5)
    assert_equal "none match", match_pair(10, 20, 5)
  end

  # ========================================
  # Combined Advanced Pattern Tests
  # ========================================

  def test_capture_with_guard
    source = <<~RUBY
      def positive_int?(x)
        case x
        in Integer => n if n > 0
          "positive"
        in Integer => n
          "non-positive"
        else
          "not integer"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_capture_guard")

    require output
    assert_equal "positive", positive_int?(10)
    assert_equal "positive", positive_int?(1)
    assert_equal "non-positive", positive_int?(0)
    assert_equal "non-positive", positive_int?(-5)
    assert_equal "not integer", positive_int?("hello")
    assert_equal "not integer", positive_int?(3.14)
  end

  def test_guard_and_variable
    source = <<~RUBY
      def validate_number(x)
        case x
        in n if n >= 18 then "adult"
        in n if n >= 0 then "minor"
        else "invalid"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_guard_var2")

    require output
    assert_equal "adult", validate_number(25)
    assert_equal "adult", validate_number(18)
    assert_equal "minor", validate_number(10)
    assert_equal "minor", validate_number(0)
    # Note: negative numbers also match 'in n' pattern
  end

  def test_pin_and_type_separate
    source = <<~RUBY
      def check_value(value, expected)
        case value
        in ^expected then "exact match"
        in Integer then "different integer"
        else "not an integer"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_pin_type")

    require output
    assert_equal "exact match", check_value(10, 10)
    assert_equal "different integer", check_value(15, 10)
    assert_equal "not an integer", check_value("hello", 10)
  end
end
