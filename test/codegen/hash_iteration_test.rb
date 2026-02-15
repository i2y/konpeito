# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class HashIterationTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_hash_each_compiles
    source = <<~RUBY
      def hash_each_test
        h = { "a" => 1, "b" => 2, "c" => 3 }
        result = []
        h.each { |k, v| result.push(k) }
        result
      end
    RUBY

    result = compile_and_run(source, "hash_each_test")
    assert_kind_of Array, result
    assert_equal 3, result.size
    assert_includes result, "a"
    assert_includes result, "b"
    assert_includes result, "c"
  end

  def test_hash_each_with_values
    source = <<~RUBY
      def hash_sum_values
        h = { "x" => 10, "y" => 20, "z" => 30 }
        total = 0
        h.each { |k, v| total = total + v }
        total
      end
    RUBY

    result = compile_and_run(source, "hash_sum_values")
    assert_equal 60, result
  end

  def test_hash_map
    source = <<~RUBY
      def hash_map_test
        h = { "a" => 1, "b" => 2 }
        h.map { |k, v| v * 10 }
      end
    RUBY

    result = compile_and_run(source, "hash_map_test")
    assert_kind_of Array, result
    assert_equal 2, result.size
    assert_includes result, 10
    assert_includes result, 20
  end

  def test_hash_select
    source = <<~RUBY
      def hash_select_test
        h = { "a" => 1, "b" => 20, "c" => 3, "d" => 40 }
        h.select { |k, v| v > 10 }
      end
    RUBY

    result = compile_and_run(source, "hash_select_test")
    assert_kind_of Hash, result
    assert_equal 2, result.size
    assert_equal 20, result["b"]
    assert_equal 40, result["d"]
  end

  def test_hash_reject
    source = <<~RUBY
      def hash_reject_test
        h = { "a" => 1, "b" => 20, "c" => 3 }
        h.reject { |k, v| v > 10 }
      end
    RUBY

    result = compile_and_run(source, "hash_reject_test")
    assert_kind_of Hash, result
    assert_equal 2, result.size
    assert_equal 1, result["a"]
    assert_equal 3, result["c"]
  end

  def test_hash_any
    source = <<~RUBY
      def hash_any_test
        h = { "a" => 1, "b" => 20, "c" => 3 }
        h.any? { |k, v| v > 10 }
      end
    RUBY

    result = compile_and_run(source, "hash_any_test")
    assert_equal true, result
  end

  def test_hash_any_false
    source = <<~RUBY
      def hash_any_false_test
        h = { "a" => 1, "b" => 2, "c" => 3 }
        h.any? { |k, v| v > 100 }
      end
    RUBY

    result = compile_and_run(source, "hash_any_false_test")
    assert_equal false, result
  end

  def test_hash_all
    source = <<~RUBY
      def hash_all_test
        h = { "a" => 10, "b" => 20, "c" => 30 }
        h.all? { |k, v| v > 5 }
      end
    RUBY

    result = compile_and_run(source, "hash_all_test")
    assert_equal true, result
  end

  def test_hash_none
    source = <<~RUBY
      def hash_none_test
        h = { "a" => 1, "b" => 2, "c" => 3 }
        h.none? { |k, v| v > 100 }
      end
    RUBY

    result = compile_and_run(source, "hash_none_test")
    assert_equal true, result
  end

  def test_hash_each_empty
    source = <<~RUBY
      def hash_empty_each
        h = {}
        count = 0
        h.each { |k, v| count = count + 1 }
        count
      end
    RUBY

    result = compile_and_run(source, "hash_empty_each")
    assert_equal 0, result
  end

  def test_hash_each_pair
    source = <<~RUBY
      def hash_each_pair_test
        h = { "x" => 100 }
        total = 0
        h.each_pair { |k, v| total = total + v }
        total
      end
    RUBY

    result = compile_and_run(source, "hash_each_pair_test")
    assert_equal 100, result
  end

  def test_hash_collect
    source = <<~RUBY
      def hash_collect_test
        h = { "a" => 1, "b" => 2 }
        h.collect { |k, v| v + 100 }
      end
    RUBY

    result = compile_and_run(source, "hash_collect_test")
    assert_kind_of Array, result
    assert_includes result, 101
    assert_includes result, 102
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
