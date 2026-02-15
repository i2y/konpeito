# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class InlineIteratorTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # Integer#times tests
  def test_integer_times_basic
    source = <<~RUBY
      def count_up(n)
        sum = 0
        n.times { |i| sum = sum + i }
        sum
      end
    RUBY

    result = compile_and_run(source, "count_up(5)")
    assert_equal 10, result  # 0 + 1 + 2 + 3 + 4 = 10
  end

  def test_integer_times_zero
    source = <<~RUBY
      def count_zero
        sum = 0
        0.times { |i| sum = sum + 1 }
        sum
      end
    RUBY

    result = compile_and_run(source, "count_zero")
    assert_equal 0, result
  end

  def test_integer_times_without_block_param
    source = <<~RUBY
      def repeat_action(n)
        count = 0
        n.times { count = count + 1 }
        count
      end
    RUBY

    result = compile_and_run(source, "repeat_action(3)")
    assert_equal 3, result
  end

  def test_integer_times_returns_receiver
    source = <<~RUBY
      def times_return(n)
        n.times { |i| i }
      end
    RUBY

    result = compile_and_run(source, "times_return(5)")
    assert_equal 5, result
  end

  # Array#find/detect tests
  def test_array_find_found
    source = <<~RUBY
      def find_even(arr)
        arr.find { |x| x % 2 == 0 }
      end
    RUBY

    result = compile_and_run(source, "find_even([1, 3, 4, 5, 6])")
    assert_equal 4, result
  end

  def test_array_find_not_found
    source = <<~RUBY
      def find_negative(arr)
        arr.find { |x| x < 0 }
      end
    RUBY

    result = compile_and_run(source, "find_negative([1, 2, 3])")
    assert_nil result
  end

  def test_array_detect_alias
    source = <<~RUBY
      def detect_large(arr)
        arr.detect { |x| x > 10 }
      end
    RUBY

    result = compile_and_run(source, "detect_large([1, 5, 15, 20])")
    assert_equal 15, result
  end

  def test_array_find_first_element
    source = <<~RUBY
      def find_first(arr)
        arr.find { |x| x > 0 }
      end
    RUBY

    result = compile_and_run(source, "find_first([5, 10, 15])")
    assert_equal 5, result
  end

  # Array#any? tests
  def test_array_any_true
    source = <<~RUBY
      def has_negative(arr)
        arr.any? { |x| x < 0 }
      end
    RUBY

    result = compile_and_run(source, "has_negative([1, 2, -3, 4])")
    assert_equal true, result
  end

  def test_array_any_false
    source = <<~RUBY
      def has_negative(arr)
        arr.any? { |x| x < 0 }
      end
    RUBY

    result = compile_and_run(source, "has_negative([1, 2, 3, 4])")
    assert_equal false, result
  end

  def test_array_any_empty
    source = <<~RUBY
      def any_empty(arr)
        arr.any? { |x| x > 0 }
      end
    RUBY

    result = compile_and_run(source, "any_empty([])")
    assert_equal false, result
  end

  # Array#all? tests
  def test_array_all_true
    source = <<~RUBY
      def all_positive(arr)
        arr.all? { |x| x > 0 }
      end
    RUBY

    result = compile_and_run(source, "all_positive([1, 2, 3, 4])")
    assert_equal true, result
  end

  def test_array_all_false
    source = <<~RUBY
      def all_positive(arr)
        arr.all? { |x| x > 0 }
      end
    RUBY

    result = compile_and_run(source, "all_positive([1, 2, -3, 4])")
    assert_equal false, result
  end

  def test_array_all_empty
    source = <<~RUBY
      def all_empty(arr)
        arr.all? { |x| x > 0 }
      end
    RUBY

    result = compile_and_run(source, "all_empty([])")
    assert_equal true, result  # vacuous truth
  end

  # Array#none? tests
  def test_array_none_true
    source = <<~RUBY
      def no_negative(arr)
        arr.none? { |x| x < 0 }
      end
    RUBY

    result = compile_and_run(source, "no_negative([1, 2, 3, 4])")
    assert_equal true, result
  end

  def test_array_none_false
    source = <<~RUBY
      def no_negative(arr)
        arr.none? { |x| x < 0 }
      end
    RUBY

    result = compile_and_run(source, "no_negative([1, 2, -3, 4])")
    assert_equal false, result
  end

  def test_array_none_empty
    source = <<~RUBY
      def none_empty(arr)
        arr.none? { |x| x > 0 }
      end
    RUBY

    result = compile_and_run(source, "none_empty([])")
    assert_equal true, result  # vacuous truth
  end

  # Edge cases
  def test_find_with_truthy_values
    source = <<~RUBY
      def find_truthy(arr)
        arr.find { |x| x }
      end
    RUBY

    result = compile_and_run(source, "find_truthy([nil, false, 0, 1])")
    assert_equal 0, result  # 0 is truthy in Ruby
  end

  def test_any_with_nil_and_false
    source = <<~RUBY
      def any_truthy(arr)
        arr.any? { |x| x }
      end
    RUBY

    result = compile_and_run(source, "any_truthy([nil, false])")
    assert_equal false, result
  end

  def test_all_with_nil_and_false
    source = <<~RUBY
      def all_truthy(arr)
        arr.all? { |x| x }
      end
    RUBY

    result = compile_and_run(source, "all_truthy([1, 2, nil])")
    assert_equal false, result
  end

  private

  def compile_and_run(source, call_expr)
    source_file = File.join(@tmp_dir, "test.rb")
    output_file = File.join(@tmp_dir, "test.bundle")

    File.write(source_file, source)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file
    )
    compiler.compile

    require output_file

    eval(call_expr)
  end
end
