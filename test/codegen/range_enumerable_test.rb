# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class RangeEnumerableTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_range_each_inclusive
    source = <<~RUBY
      def range_each_sum
        total = 0
        (1..5).each { |i| total = total + i }
        total
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_each_sum: () -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "range_each_sum")
    assert_equal 15, result
  end

  def test_range_each_exclusive
    source = <<~RUBY
      def range_each_excl
        total = 0
        (1...5).each { |i| total = total + i }
        total
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_each_excl: () -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "range_each_excl")
    assert_equal 10, result  # 1+2+3+4 = 10
  end

  def test_range_each_with_variable_endpoint
    source = <<~RUBY
      def range_each_var(n)
        total = 0
        (1..n).each { |i| total = total + i }
        total
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_each_var: (Integer n) -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "range_each_var(10)")
    assert_equal 55, result  # 1+2+...+10 = 55
  end

  def test_range_map
    source = <<~RUBY
      def range_map_test
        (1..5).map { |i| i * 2 }
      end
    RUBY

    result = compile_and_run(source, "range_map_test")
    assert_equal [2, 4, 6, 8, 10], result
  end

  def test_range_map_exclusive
    source = <<~RUBY
      def range_map_excl
        (1...4).map { |i| i * i }
      end
    RUBY

    result = compile_and_run(source, "range_map_excl")
    assert_equal [1, 4, 9], result
  end

  def test_range_select
    source = <<~RUBY
      def range_select_test
        (1..10).select { |i| i % 2 == 0 }
      end
    RUBY

    result = compile_and_run(source, "range_select_test")
    assert_equal [2, 4, 6, 8, 10], result
  end

  def test_range_reduce_with_initial
    source = <<~RUBY
      def range_reduce_test
        (1..5).reduce(0) { |sum, i| sum + i }
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_reduce_test: () -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "range_reduce_test")
    assert_equal 15, result
  end

  def test_range_reduce_factorial
    source = <<~RUBY
      def range_factorial(n)
        (1..n).reduce(1) { |acc, i| acc * i }
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_factorial: (Integer n) -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "range_factorial(5)")
    assert_equal 120, result
  end

  def test_range_each_single_element
    source = <<~RUBY
      def range_single
        total = 0
        (5..5).each { |i| total = total + i }
        total
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_single: () -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "range_single")
    assert_equal 5, result
  end

  def test_range_each_empty
    source = <<~RUBY
      def range_empty
        total = 0
        (5..1).each { |i| total = total + i }
        total
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_empty: () -> Integer
      end
    RBS

    result = compile_and_run_typed(source, rbs, "range_empty")
    assert_equal 0, result
  end

  def test_range_nested
    source = <<~RUBY
      def range_nested(n)
        total = 0
        (1..n).each do |i|
          (1..i).each do |j|
            total = total + 1
          end
        end
        total
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def range_nested: (Integer n) -> Integer
      end
    RBS

    # 1 + 2 + 3 + 4 + 5 = 15
    result = compile_and_run_typed(source, rbs, "range_nested(5)")
    assert_equal 15, result
  end

  def test_range_collect
    source = <<~RUBY
      def range_collect_test
        (1..3).collect { |i| i + 100 }
      end
    RUBY

    result = compile_and_run(source, "range_collect_test")
    assert_equal [101, 102, 103], result
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
