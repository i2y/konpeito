# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class StaticArrayTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_counter = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # ===================
  # StaticArray allocation and basic operations
  # ===================

  def test_static_array_alloc_and_size
    source = <<~RUBY
      def test_size
        arr = StaticArray4Float.new
        arr.size
      end
    RUBY

    result = compile_and_run(source, "test_size")
    assert_equal 4, result
  end

  def test_static_array_get_set_float
    source = <<~RUBY
      def test_get_set
        arr = StaticArray4Float.new
        arr[0] = 1.5
        arr[1] = 2.5
        arr[2] = 3.0
        arr[3] = 4.0
        arr[0] + arr[1] + arr[2] + arr[3]
      end
    RUBY

    result = compile_and_run(source, "test_get_set")
    assert_in_delta 11.0, result, 0.001
  end

  def test_static_array_get_set_int
    source = <<~RUBY
      def test_int
        arr = StaticArray4Int.new
        arr[0] = 10
        arr[1] = 20
        arr[2] = 30
        arr[3] = 40
        arr[0] + arr[1] + arr[2] + arr[3]
      end
    RUBY

    result = compile_and_run(source, "test_int")
    assert_equal 100, result
  end

  def test_static_array_init_with_value
    source = <<~RUBY
      def test_init
        arr = StaticArray4Int.new(42)
        arr[0] + arr[1] + arr[2] + arr[3]
      end
    RUBY

    result = compile_and_run(source, "test_init")
    assert_equal 168, result  # 42 * 4
  end

  def test_static_array_loop_sum
    source = <<~RUBY
      def test_loop_sum
        arr = StaticArray4Float.new
        arr[0] = 1.0
        arr[1] = 2.0
        arr[2] = 3.0
        arr[3] = 4.0

        total = 0.0
        i = 0
        while i < 4
          total = total + arr[i]
          i = i + 1
        end
        total
      end
    RUBY

    result = compile_and_run(source, "test_loop_sum")
    assert_in_delta 10.0, result, 0.001
  end

  def test_static_array_larger_size
    source = <<~RUBY
      def test_larger
        arr = StaticArray16Int.new(1)
        total = 0
        i = 0
        while i < 16
          total = total + arr[i]
          i = i + 1
        end
        total
      end
    RUBY

    result = compile_and_run(source, "test_larger")
    assert_equal 16, result  # 16 * 1
  end

  private

  def compile_and_run(source, call_expr)
    @test_counter += 1
    source_file = File.join(@tmp_dir, "test_#{@test_counter}.rb")
    rbs_file = File.join(@tmp_dir, "test_#{@test_counter}.rbs")
    output_file = File.join(@tmp_dir, "test_#{@test_counter}.bundle")

    File.write(source_file, source)

    # Write RBS file with StaticArray types
    rbs_content = <<~RBS
      %a{native}      class StaticArray4Float
        def self.new: () -> StaticArray4Float
                   | (Float value) -> StaticArray4Float

        def []: (Integer index) -> Float
        def []=: (Integer index, Float value) -> Float
        def size: () -> Integer
      end

      %a{native}      class StaticArray4Int
        def self.new: () -> StaticArray4Int
                   | (Integer value) -> StaticArray4Int

        def []: (Integer index) -> Integer
        def []=: (Integer index, Integer value) -> Integer
        def size: () -> Integer
      end

      %a{native}      class StaticArray16Int
        def self.new: () -> StaticArray16Int
                   | (Integer value) -> StaticArray16Int

        def []: (Integer index) -> Integer
        def []=: (Integer index, Integer value) -> Integer
        def size: () -> Integer
      end

      module TopLevel
        def test_size: () -> Integer
        def test_get_set: () -> Float
        def test_int: () -> Integer
        def test_init: () -> Integer
        def test_loop_sum: () -> Float
        def test_larger: () -> Integer
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
