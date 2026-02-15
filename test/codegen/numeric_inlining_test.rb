# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class NumericInliningTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_integer_abs_positive
    source = <<~RUBY
      def int_abs_pos(n)
        n.abs
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_abs_pos: (Integer n) -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "int_abs_pos(42)")
    assert_equal 42, result
  end

  def test_integer_abs_negative
    source = <<~RUBY
      def int_abs_neg(n)
        n.abs
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_abs_neg: (Integer n) -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "int_abs_neg(-42)")
    assert_equal 42, result
  end

  def test_integer_abs_zero
    source = <<~RUBY
      def int_abs_zero(n)
        n.abs
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_abs_zero: (Integer n) -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "int_abs_zero(0)")
    assert_equal 0, result
  end

  def test_integer_even
    source = <<~RUBY
      def int_even(n)
        n.even?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_even: (Integer n) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "int_even(4)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_even(3)")
    assert_equal true, compile_and_run_typed(source, rbs, "int_even(0)")
  end

  def test_integer_odd
    source = <<~RUBY
      def int_odd(n)
        n.odd?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_odd: (Integer n) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "int_odd(3)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_odd(4)")
  end

  def test_integer_zero
    source = <<~RUBY
      def int_zero(n)
        n.zero?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_zero: (Integer n) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "int_zero(0)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_zero(1)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_zero(-1)")
  end

  def test_integer_positive
    source = <<~RUBY
      def int_pos(n)
        n.positive?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_pos: (Integer n) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "int_pos(5)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_pos(0)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_pos(-5)")
  end

  def test_integer_negative
    source = <<~RUBY
      def int_neg(n)
        n.negative?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def int_neg: (Integer n) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "int_neg(-5)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_neg(0)")
    assert_equal false, compile_and_run_typed(source, rbs, "int_neg(5)")
  end

  def test_integer_abs_in_loop
    source = <<~RUBY
      def sum_abs(n)
        total = 0
        i = -5
        while i <= n
          total = total + i.abs
          i = i + 1
        end
        total
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def sum_abs: (Integer n) -> Integer
      end
    RBS

    # -5.abs + -4.abs + ... + 0.abs + ... + 5.abs = 5+4+3+2+1+0+1+2+3+4+5 = 30
    result = compile_and_run_typed(source, rbs, "sum_abs(5)")
    assert_equal 30, result
  end

  def test_integer_abs_chain
    source = <<~RUBY
      def abs_diff(a, b)
        (a - b).abs
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def abs_diff: (Integer a, Integer b) -> Integer
      end
    RBS

    assert_equal 7, compile_and_run_typed(source, rbs, "abs_diff(3, 10)")
    assert_equal 7, compile_and_run_typed(source, rbs, "abs_diff(10, 3)")
  end

  def test_float_abs
    source = <<~RUBY
      def float_abs(x)
        x.abs
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def float_abs: (Float x) -> Float
      end
    RBS

    assert_in_delta 3.14, compile_and_run_typed(source, rbs, "float_abs(-3.14)"), 0.001
    assert_in_delta 3.14, compile_and_run_typed(source, rbs, "float_abs(3.14)"), 0.001
  end

  def test_float_zero
    source = <<~RUBY
      def float_zero(x)
        x.zero?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def float_zero: (Float x) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "float_zero(0.0)")
    assert_equal false, compile_and_run_typed(source, rbs, "float_zero(1.0)")
  end

  def test_float_positive
    source = <<~RUBY
      def float_pos(x)
        x.positive?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def float_pos: (Float x) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "float_pos(1.5)")
    assert_equal false, compile_and_run_typed(source, rbs, "float_pos(-1.5)")
    assert_equal false, compile_and_run_typed(source, rbs, "float_pos(0.0)")
  end

  def test_float_negative
    source = <<~RUBY
      def float_neg(x)
        x.negative?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def float_neg: (Float x) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, "float_neg(-1.5)")
    assert_equal false, compile_and_run_typed(source, rbs, "float_neg(1.5)")
  end

  private

  def compile_and_run_typed(source, rbs, call_expr)
    source_file = File.join(@tmp_dir, "test.rb")
    rbs_file = File.join(@tmp_dir, "test.rbs")
    output_file = File.join(@tmp_dir, "test.bundle")

    File.write(source_file, source)
    File.write(rbs_file, rbs)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      rbs_paths: [rbs_file]
    )
    compiler.compile

    require output_file

    eval(call_expr)
  end
end
