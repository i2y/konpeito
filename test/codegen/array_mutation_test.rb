# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class ArrayMutationTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_array_index_set_basic
    source = <<~RUBY
      def arr_set_test
        arr = [1, 2, 3]
        arr[0] = 10
        arr[2] = 30
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_set_test")
    assert_equal [10, 2, 30], result
  end

  def test_array_index_set_with_variable
    source = <<~RUBY
      def arr_set_var_test
        arr = [0, 0, 0, 0, 0]
        i = 0
        while i < 5
          arr[i] = i * 10
          i = i + 1
        end
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_set_var_test")
    assert_equal [0, 10, 20, 30, 40], result
  end

  def test_array_index_set_negative
    source = <<~RUBY
      def arr_set_neg_test
        arr = [1, 2, 3]
        arr[-1] = 99
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_set_neg_test")
    assert_equal [1, 2, 99], result
  end

  def test_array_unshift
    source = <<~RUBY
      def arr_unshift_test
        arr = [2, 3]
        arr.unshift(1)
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_unshift_test")
    assert_equal [1, 2, 3], result
  end

  def test_array_prepend
    source = <<~RUBY
      def arr_prepend_test
        arr = [2, 3]
        arr.prepend(1)
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_prepend_test")
    assert_equal [1, 2, 3], result
  end

  def test_array_delete
    source = <<~RUBY
      def arr_delete_test
        arr = [1, 2, 3, 2, 4]
        arr.delete(2)
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_delete_test")
    assert_equal [1, 3, 4], result
  end

  def test_array_delete_at
    source = <<~RUBY
      def arr_delete_at_test
        arr = [10, 20, 30, 40]
        removed = arr.delete_at(1)
        [arr, removed]
      end
    RUBY

    result = compile_and_run(source, "arr_delete_at_test")
    assert_equal [[10, 30, 40], 20], result
  end

  def test_array_set_in_loop
    source = <<~RUBY
      def arr_double_test
        arr = [0, 0, 0, 0, 0]
        i = 0
        while i < 5
          arr[i] = i + 10
          i = i + 1
        end
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_double_test")
    assert_equal [10, 11, 12, 13, 14], result
  end

  def test_array_index_set_returns_value
    source = <<~RUBY
      def arr_set_return_test
        arr = [1, 2, 3]
        result = (arr[1] = 99)
        result
      end
    RUBY

    result = compile_and_run(source, "arr_set_return_test")
    assert_equal 99, result
  end

  def test_array_delete_at_negative
    source = <<~RUBY
      def arr_delete_at_neg_test
        arr = [10, 20, 30]
        arr.delete_at(-1)
        arr
      end
    RUBY

    result = compile_and_run(source, "arr_delete_at_neg_test")
    assert_equal [10, 20], result
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
