# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class SliceTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_counter = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # ===================
  # SliceInt64 allocation and basic operations
  # ===================

  def test_slice_int64_alloc_and_size
    source = <<~RUBY
      def test_alloc
        s = SliceInt64.new(10)
        s.size
      end
    RUBY

    result = compile_and_run(source, "test_alloc")
    assert_equal 10, result
  end

  def test_slice_int64_get_set
    source = <<~RUBY
      def test_get_set
        s = SliceInt64.new(5)
        s[0] = 100
        s[1] = 200
        s[2] = 300
        s[0] + s[1] + s[2]
      end
    RUBY

    result = compile_and_run(source, "test_get_set")
    assert_equal 600, result
  end

  def test_slice_int64_loop_access
    source = <<~RUBY
      def test_loop
        s = SliceInt64.new(5)
        i = 0
        while i < s.size
          s[i] = i * 10
          i = i + 1
        end
        s[0] + s[1] + s[2] + s[3] + s[4]
      end
    RUBY

    result = compile_and_run(source, "test_loop")
    assert_equal 100, result  # 0 + 10 + 20 + 30 + 40
  end

  def test_slice_int64_fill
    source = <<~RUBY
      def test_fill
        s = SliceInt64.new(5)
        s.fill(42)
        s[0] + s[1] + s[2] + s[3] + s[4]
      end
    RUBY

    result = compile_and_run(source, "test_fill")
    assert_equal 210, result  # 42 * 5
  end

  # ===================
  # SliceFloat64 operations
  # ===================

  def test_slice_float64_alloc_and_size
    source = <<~RUBY
      def test_float_alloc
        s = SliceFloat64.new(10)
        s.size
      end
    RUBY

    result = compile_and_run(source, "test_float_alloc")
    assert_equal 10, result
  end

  def test_slice_float64_get_set
    source = <<~RUBY
      def test_float_get_set
        s = SliceFloat64.new(3)
        s[0] = 1.5
        s[1] = 2.5
        s[2] = 3.0
        s[0] + s[1] + s[2]
      end
    RUBY

    result = compile_and_run(source, "test_float_get_set")
    assert_in_delta 7.0, result, 0.001
  end

  def test_slice_float64_fill
    source = <<~RUBY
      def test_float_fill
        s = SliceFloat64.new(4)
        s.fill(2.5)
        s[0] + s[1] + s[2] + s[3]
      end
    RUBY

    result = compile_and_run(source, "test_float_fill")
    assert_in_delta 10.0, result, 0.001
  end

  # ===================
  # Subslice operations
  # ===================

  def test_slice_subslice
    source = <<~RUBY
      def test_subslice
        s = SliceInt64.new(10)
        i = 0
        while i < 10
          s[i] = i
          i = i + 1
        end

        sub = s[3, 4]
        sub[0] + sub[1] + sub[2] + sub[3]
      end
    RUBY

    result = compile_and_run(source, "test_subslice")
    assert_equal 18, result  # 3 + 4 + 5 + 6
  end

  def test_slice_subslice_size
    source = <<~RUBY
      def test_subslice_size
        s = SliceInt64.new(10)
        sub = s[2, 5]
        sub.size
      end
    RUBY

    result = compile_and_run(source, "test_subslice_size")
    assert_equal 5, result
  end

  # ===================
  # Copy operations
  # ===================

  def test_slice_copy_from
    source = <<~RUBY
      def test_copy
        src = SliceInt64.new(5)
        src[0] = 1
        src[1] = 2
        src[2] = 3
        src[3] = 4
        src[4] = 5

        dest = SliceInt64.new(5)
        dest.copy_from(src)
        dest[0] + dest[1] + dest[2] + dest[3] + dest[4]
      end
    RUBY

    result = compile_and_run(source, "test_copy")
    assert_equal 15, result
  end

  # ===================
  # Empty slice
  # ===================

  def test_slice_empty
    source = <<~RUBY
      def test_empty
        s = SliceInt64.empty
        s.size
      end
    RUBY

    result = compile_and_run(source, "test_empty")
    assert_equal 0, result
  end

  private

  def compile_and_run(source, call_expr)
    @test_counter += 1
    source_file = File.join(@tmp_dir, "test_#{@test_counter}.rb")
    output_file = File.join(@tmp_dir, "test_#{@test_counter}.bundle")
    rbs_file = File.join(@tmp_dir, "test_#{@test_counter}.rbs")

    File.write(source_file, source)

    rbs_content = <<~RBS
      %a{native}      class SliceInt64
        def self.new: (Integer size) -> SliceInt64
        def self.empty: () -> SliceInt64
        def []: (Integer index) -> Integer
             | (Integer start, Integer count) -> SliceInt64
        def []=: (Integer index, Integer value) -> Integer
        def size: () -> Integer
        def copy_from: (SliceInt64 source) -> SliceInt64
        def fill: (Integer value) -> SliceInt64
      end

      %a{native}      class SliceFloat64
        def self.new: (Integer size) -> SliceFloat64
        def self.empty: () -> SliceFloat64
        def []: (Integer index) -> Float
             | (Integer start, Integer count) -> SliceFloat64
        def []=: (Integer index, Float value) -> Float
        def size: () -> Integer
        def copy_from: (SliceFloat64 source) -> SliceFloat64
        def fill: (Float value) -> SliceFloat64
      end

      module TopLevel
        def test_alloc: () -> Integer
        def test_get_set: () -> Integer
        def test_loop: () -> Integer
        def test_fill: () -> Integer
        def test_float_alloc: () -> Integer
        def test_float_get_set: () -> Float
        def test_float_fill: () -> Float
        def test_subslice: () -> Integer
        def test_subslice_size: () -> Integer
        def test_copy: () -> Integer
        def test_empty: () -> Integer
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
