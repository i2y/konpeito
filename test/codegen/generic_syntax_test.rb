# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "konpeito"

class GenericSyntaxTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir("generic_syntax_test_")
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir) if @tmp_dir && File.exist?(@tmp_dir)
  end

  def compile_and_run(source, rbs, method_name, *args)
    source_path = File.join(@tmp_dir, "test.rb")
    rbs_path = File.join(@tmp_dir, "test.rbs")
    output_path = File.join(@tmp_dir, "test.bundle")

    File.write(source_path, source)
    File.write(rbs_path, rbs)

    compiler = Konpeito::Compiler.new(
      source_file: source_path,
      output_file: output_path,
      rbs_paths: [rbs_path],
      verbose: false
    )

    compiler.compile
    require output_path

    send(method_name, *args)
  end

  # ============================================================
  # NativeHash[K, V] tests
  # ============================================================

  def test_native_hash_generic_syntax
    source = <<~RUBY
      def hash_generic
        h = NativeHash.new
        h["foo"] = 100
        h["bar"] = 200
        h["foo"] + h["bar"]
      end
    RUBY

    rbs = <<~RBS
      class NativeHash[K, V]
        def self.new: () -> NativeHash[String, Integer]
        def []: (K key) -> V
        def []=: (K key, V value) -> V
        def size: () -> Integer
      end

      module TopLevel
        def hash_generic: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_generic)
    assert_equal 300, result
  end

  def test_native_hash_generic_return_value
    source = <<~RUBY
      def hash_return_sum
        h = NativeHash.new
        h["a"] = 10
        h["b"] = 20
        h["a"] + h["b"]
      end
    RUBY

    rbs = <<~RBS
      class NativeHash[K, V]
        def self.new: () -> NativeHash[String, Integer]
        def []: (K key) -> V
        def []=: (K key, V value) -> V
        def size: () -> Integer
      end

      module TopLevel
        def hash_return_sum: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_return_sum)
    assert_equal 30, result
  end

  # ============================================================
  # NativeArray[T] tests
  # ============================================================

  def test_native_array_generic_syntax
    source = <<~RUBY
      def array_generic
        arr = NativeArray.new(3)
        arr[0] = 1.0
        arr[1] = 2.0
        arr[2] = 3.0
        arr[0] + arr[1] + arr[2]
      end
    RUBY

    rbs = <<~RBS
      class NativeArray[T]
        def self.new: (Integer size) -> NativeArray[Float]
        def []: (Integer index) -> T
        def []=: (Integer index, T value) -> T
        def length: () -> Integer
      end

      module TopLevel
        def array_generic: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :array_generic)
    assert_in_delta 6.0, result, 0.001
  end

  # ============================================================
  # StaticArray[T, N] tests
  # ============================================================

  def test_static_array_generic_syntax
    source = <<~RUBY
      def static_array_generic
        arr = StaticArray.new
        arr[0] = 1.0
        arr[1] = 2.0
        arr[2] = 3.0
        arr[3] = 4.0
        arr[0] + arr[1] + arr[2] + arr[3]
      end
    RUBY

    rbs = <<~RBS
      class StaticArray[T, N]
        def self.new: () -> StaticArray[Float, 4]
        def []: (Integer index) -> T
        def []=: (Integer index, T value) -> T
        def size: () -> Integer
      end

      module TopLevel
        def static_array_generic: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :static_array_generic)
    assert_in_delta 10.0, result, 0.001
  end

  # ============================================================
  # Slice[T] tests
  # ============================================================

  def test_slice_generic_syntax
    source = <<~RUBY
      def slice_generic
        s = Slice.new(4)
        s[0] = 10
        s[1] = 20
        s[2] = 30
        s[3] = 40
        s[0] + s[1] + s[2] + s[3]
      end
    RUBY

    rbs = <<~RBS
      class Slice[T]
        def self.new: (Integer size) -> Slice[Int64]
        def []: (Integer index) -> T
        def []=: (Integer index, T value) -> T
        def size: () -> Integer
      end

      module TopLevel
        def slice_generic: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :slice_generic)
    assert_equal 100, result
  end
end
