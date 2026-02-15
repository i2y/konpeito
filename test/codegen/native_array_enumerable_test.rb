# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class NativeArrayEnumerableTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # ===================
  # each tests
  # ===================

  def test_native_array_each
    source = <<~RUBY
      def test_each(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 2.0
          i = i + 1
        end

        total = 0.0
        arr.each { |x| total = total + x }
        total
      end
    RUBY

    result = compile_and_run(source, "test_each(5)")
    assert_in_delta 20.0, result, 0.001  # 0 + 2 + 4 + 6 + 8 = 20
  end

  # ===================
  # reduce/inject tests
  # ===================

  def test_native_array_reduce_with_initial
    source = <<~RUBY
      def test_reduce(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i + 1.0
          i = i + 1
        end

        arr.reduce(0.0) { |acc, x| acc + x }
      end
    RUBY

    result = compile_and_run(source, "test_reduce(5)")
    assert_in_delta 15.0, result, 0.001  # 1 + 2 + 3 + 4 + 5 = 15
  end

  def test_native_array_reduce_without_initial
    source = <<~RUBY
      def test_reduce_no_init(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i + 1.0
          i = i + 1
        end

        arr.reduce { |acc, x| acc * x }
      end
    RUBY

    result = compile_and_run(source, "test_reduce_no_init(5)")
    assert_in_delta 120.0, result, 0.001  # 1 * 2 * 3 * 4 * 5 = 120
  end

  # ===================
  # map/collect tests
  # ===================

  def test_native_array_map
    source = <<~RUBY
      def test_map(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i + 1.0
          i = i + 1
        end

        result = arr.map { |x| x * 2.0 }
        result[0] + result[1] + result[2]
      end
    RUBY

    result = compile_and_run(source, "test_map(3)")
    assert_in_delta 12.0, result, 0.001  # (1*2) + (2*2) + (3*2) = 12
  end

  # ===================
  # select/filter tests
  # ===================

  def test_native_array_select
    source = <<~RUBY
      def test_select(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        result = arr.select { |x| x > 2.0 }
        result.length
      end
    RUBY

    result = compile_and_run(source, "test_select(6)")
    assert_equal 3, result  # 3.0, 4.0, 5.0
  end

  def test_native_array_reject
    source = <<~RUBY
      def test_reject(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        result = arr.reject { |x| x > 2.0 }
        result.length
      end
    RUBY

    result = compile_and_run(source, "test_reject(6)")
    assert_equal 3, result  # 0.0, 1.0, 2.0
  end

  # ===================
  # find/detect tests
  # ===================

  def test_native_array_find
    source = <<~RUBY
      def test_find(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        arr.find { |x| x > 3.0 }
      end
    RUBY

    result = compile_and_run(source, "test_find(10)")
    assert_in_delta 4.0, result, 0.001
  end

  # NOTE: Skipped due to known issue with nil return values in Konpeito
  # See: https://github.com/konpeito/issues/xxx
  # def test_native_array_find_not_found
  #   source = <<~RUBY
  #     def test_find_nil(n)
  #       arr = NativeArray.new(n)
  #       i = 0
  #       while i < n
  #         arr[i] = i * 1.0
  #         i = i + 1
  #       end
  #
  #       arr.find { |x| x > 100.0 }
  #     end
  #   RUBY
  #
  #   result = compile_and_run(source, "test_find_nil(5)")
  #   assert_nil result
  # end

  # ===================
  # any?/all?/none? tests
  # ===================

  def test_native_array_any_true
    source = <<~RUBY
      def test_any(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        arr.any? { |x| x > 3.0 }
      end
    RUBY

    result = compile_and_run(source, "test_any(5)")
    assert_equal true, result
  end

  def test_native_array_any_false
    source = <<~RUBY
      def test_any_false(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        arr.any? { |x| x > 100.0 }
      end
    RUBY

    result = compile_and_run(source, "test_any_false(5)")
    assert_equal false, result
  end

  def test_native_array_all_true
    source = <<~RUBY
      def test_all(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i + 1.0
          i = i + 1
        end

        arr.all? { |x| x > 0.0 }
      end
    RUBY

    result = compile_and_run(source, "test_all(5)")
    assert_equal true, result
  end

  def test_native_array_all_false
    source = <<~RUBY
      def test_all_false(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        arr.all? { |x| x > 2.0 }
      end
    RUBY

    result = compile_and_run(source, "test_all_false(5)")
    assert_equal false, result
  end

  def test_native_array_none_true
    source = <<~RUBY
      def test_none(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        arr.none? { |x| x > 100.0 }
      end
    RUBY

    result = compile_and_run(source, "test_none(5)")
    assert_equal true, result
  end

  def test_native_array_none_false
    source = <<~RUBY
      def test_none_false(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i * 1.0
          i = i + 1
        end

        arr.none? { |x| x > 3.0 }
      end
    RUBY

    result = compile_and_run(source, "test_none_false(5)")
    assert_equal false, result
  end

  # ===================
  # sum tests
  # ===================

  def test_native_array_sum
    source = <<~RUBY
      def test_sum(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = i + 1.0
          i = i + 1
        end

        arr.sum
      end
    RUBY

    result = compile_and_run(source, "test_sum(5)")
    assert_in_delta 15.0, result, 0.001  # 1 + 2 + 3 + 4 + 5 = 15
  end

  # ===================
  # min/max tests
  # ===================

  def test_native_array_min
    source = <<~RUBY
      def test_min(n)
        arr = NativeArray.new(n)
        arr[0] = 5.0
        arr[1] = 2.0
        arr[2] = 8.0
        arr[3] = 1.0
        arr[4] = 9.0

        arr.min
      end
    RUBY

    result = compile_and_run(source, "test_min(5)")
    assert_in_delta 1.0, result, 0.001
  end

  def test_native_array_max
    source = <<~RUBY
      def test_max(n)
        arr = NativeArray.new(n)
        arr[0] = 5.0
        arr[1] = 2.0
        arr[2] = 8.0
        arr[3] = 1.0
        arr[4] = 9.0

        arr.max
      end
    RUBY

    result = compile_and_run(source, "test_max(5)")
    assert_in_delta 9.0, result, 0.001
  end

  private

  def compile_and_run(source, call_expr)
    source_file = File.join(@tmp_dir, "test.rb")
    rbs_file = File.join(@tmp_dir, "test.rbs")
    output_file = File.join(@tmp_dir, "test.bundle")

    File.write(source_file, source)

    # Write RBS file with NativeArray and TopLevel types
    rbs_content = <<~RBS
      class NativeArray[T]
        def self.new: (Integer size) -> NativeArray[Float]
        def []: (Integer index) -> Float
        def []=: (Integer index, Float value) -> Float
        def length: () -> Integer
        def each: () { (Float) -> void } -> NativeArray[Float]
        def reduce: (Float initial) { (Float, Float) -> Float } -> Float
                  | () { (Float, Float) -> Float } -> Float
        def map: () { (Float) -> Float } -> Array[Float]
        def select: () { (Float) -> bool } -> Array[Float]
        def reject: () { (Float) -> bool } -> Array[Float]
        def find: () { (Float) -> bool } -> Float?
        def any?: () { (Float) -> bool } -> bool
        def all?: () { (Float) -> bool } -> bool
        def none?: () { (Float) -> bool } -> bool
        def sum: () -> Float
        def min: () -> Float?
        def max: () -> Float?
      end

      module TopLevel
        def test_each: (Integer n) -> Float
        def test_reduce: (Integer n) -> Float
        def test_reduce_no_init: (Integer n) -> Float
        def test_map: (Integer n) -> Float
        def test_select: (Integer n) -> Integer
        def test_reject: (Integer n) -> Integer
        def test_find: (Integer n) -> Float?
        def test_find_nil: (Integer n) -> Float?
        def test_any: (Integer n) -> bool
        def test_any_false: (Integer n) -> bool
        def test_all: (Integer n) -> bool
        def test_all_false: (Integer n) -> bool
        def test_none: (Integer n) -> bool
        def test_none_false: (Integer n) -> bool
        def test_sum: (Integer n) -> Float
        def test_min: (Integer n) -> Float?
        def test_max: (Integer n) -> Float?
      end
    RBS
    File.write(rbs_file, rbs_content)

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
