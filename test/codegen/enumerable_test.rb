# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class EnumerableTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_array_reduce_with_initial_value
    source = <<~RUBY
      def sum_with_initial(arr)
        arr.reduce(0) { |acc, x| acc + x }
      end
    RUBY

    result = compile_and_run(source, "sum_with_initial([1, 2, 3, 4, 5])")
    assert_equal 15, result
  end

  def test_array_reduce_without_initial_value
    source = <<~RUBY
      def product(arr)
        arr.reduce { |acc, x| acc * x }
      end
    RUBY

    result = compile_and_run(source, "product([1, 2, 3, 4])")
    assert_equal 24, result
  end

  def test_array_find
    source = <<~RUBY
      def find_even(arr)
        arr.find { |x| x % 2 == 0 }
      end
    RUBY

    result = compile_and_run(source, "find_even([1, 3, 4, 5, 6])")
    assert_equal 4, result
  end

  def test_array_any
    source = <<~RUBY
      def has_negative(arr)
        arr.any? { |x| x < 0 }
      end
    RUBY

    result = compile_and_run(source, "has_negative([1, 2, -3, 4])")
    assert_equal true, result
  end

  def test_array_all
    source = <<~RUBY
      def all_positive(arr)
        arr.all? { |x| x > 0 }
      end
    RUBY

    result = compile_and_run(source, "all_positive([1, 2, 3, 4])")
    assert_equal true, result
  end

  def test_array_none
    source = <<~RUBY
      def no_negative(arr)
        arr.none? { |x| x < 0 }
      end
    RUBY

    result = compile_and_run(source, "no_negative([1, 2, 3, 4])")
    assert_equal true, result
  end

  def test_array_count_with_block
    source = <<~RUBY
      def count_even(arr)
        arr.count { |x| x % 2 == 0 }
      end
    RUBY

    result = compile_and_run(source, "count_even([1, 2, 3, 4, 5, 6])")
    assert_equal 3, result
  end

  def test_array_min_by
    source = <<~RUBY
      def shortest(arr)
        arr.min_by { |s| s.length }
      end
    RUBY

    result = compile_and_run(source, 'shortest(["apple", "pie", "banana"])')
    assert_equal "pie", result
  end

  def test_array_max_by
    source = <<~RUBY
      def longest(arr)
        arr.max_by { |s| s.length }
      end
    RUBY

    result = compile_and_run(source, 'longest(["apple", "pie", "banana"])')
    assert_equal "banana", result
  end

  def test_array_sort_by
    source = <<~RUBY
      def sort_by_length(arr)
        arr.sort_by { |s| s.length }
      end
    RUBY

    result = compile_and_run(source, 'sort_by_length(["apple", "pie", "banana"])')
    assert_equal ["pie", "apple", "banana"], result
  end

  def test_array_partition
    source = <<~RUBY
      def split_even_odd(arr)
        arr.partition { |x| x % 2 == 0 }
      end
    RUBY

    result = compile_and_run(source, "split_even_odd([1, 2, 3, 4, 5, 6])")
    assert_equal [[2, 4, 6], [1, 3, 5]], result
  end

  def test_array_flat_map
    source = <<~RUBY
      def double_each(arr)
        arr.flat_map { |x| [x, x] }
      end
    RUBY

    result = compile_and_run(source, "double_each([1, 2, 3])")
    assert_equal [1, 1, 2, 2, 3, 3], result
  end

  # Note: Hash Enumerable tests are skipped for now due to 2-argument block issues
  # TODO: Fix Hash block iterator with multiple parameters

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
