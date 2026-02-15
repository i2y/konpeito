# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "konpeito"

class NativeHashTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir("native_hash_test_")
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

  def test_native_hash_string_integer_new
    source = <<~RUBY
      def create_hash
        h = NativeHashStringInteger.new
        42
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
      end

      module TopLevel
        def create_hash: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :create_hash)
    assert_equal 42, result
  end

  def test_native_hash_string_integer_set_and_size
    source = <<~RUBY
      def hash_set_and_size
        h = NativeHashStringInteger.new
        h["foo"] = 100
        h.size
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
      end

      module TopLevel
        def hash_set_and_size: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_set_and_size)
    assert_equal 1, result
  end

  def test_native_hash_integer_float
    source = <<~RUBY
      def hash_int_float
        h = NativeHashIntegerFloat.new
        h[1] = 3.14
        h[2] = 2.71
        h.size
      end
    RUBY

    rbs = <<~RBS
      class NativeHashIntegerFloat
        def self.new: () -> NativeHashIntegerFloat
        def []: (Integer key) -> Float
        def []=: (Integer key, Float value) -> Float
        def size: () -> Integer
      end

      module TopLevel
        def hash_int_float: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_int_float)
    assert_equal 2, result
  end

  def test_native_hash_symbol_string
    source = <<~RUBY
      def hash_symbol_string
        h = NativeHashSymbolString.new
        h[:name] = "Alice"
        h[:city] = "Tokyo"
        h.size
      end
    RUBY

    rbs = <<~RBS
      class NativeHashSymbolString
        def self.new: () -> NativeHashSymbolString
        def []: (Symbol key) -> String
        def []=: (Symbol key, String value) -> String
        def size: () -> Integer
      end

      module TopLevel
        def hash_symbol_string: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_symbol_string)
    assert_equal 2, result
  end

  def test_native_hash_clear
    source = <<~RUBY
      def hash_clear
        h = NativeHashStringInteger.new
        h["a"] = 1
        h["b"] = 2
        h.clear
        h.size
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
        def clear: () -> NativeHashStringInteger
      end

      module TopLevel
        def hash_clear: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_clear)
    assert_equal 0, result
  end

  def test_native_hash_with_native_class_value
    source = <<~RUBY
      def hash_with_point
        h = NativeHashStringPoint.new
        h.size
      end
    RUBY

    rbs = <<~RBS
      class Point
        @x: Float
        @y: Float

        def self.new: () -> Point
        def x: () -> Float
        def y: () -> Float
      end

      class NativeHashStringPoint
        def self.new: () -> NativeHashStringPoint
        def []: (String key) -> Point
        def []=: (String key, Point value) -> Point
        def size: () -> Integer
      end

      module TopLevel
        def hash_with_point: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_with_point)
    assert_equal 0, result
  end

  def test_native_hash_get
    source = <<~RUBY
      def hash_get
        h = NativeHashStringInteger.new
        h["foo"] = 100
        h["bar"] = 200
        h["foo"] + h["bar"]
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
      end

      module TopLevel
        def hash_get: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_get)
    assert_equal 300, result
  end

  def test_native_hash_get_integer_key
    source = <<~RUBY
      def hash_get_int_key
        h = NativeHashIntegerInteger.new
        h[1] = 10
        h[2] = 20
        h[3] = 30
        h[1] + h[2] + h[3]
      end
    RUBY

    rbs = <<~RBS
      class NativeHashIntegerInteger
        def self.new: () -> NativeHashIntegerInteger
        def []: (Integer key) -> Integer
        def []=: (Integer key, Integer value) -> Integer
        def size: () -> Integer
      end

      module TopLevel
        def hash_get_int_key: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_get_int_key)
    assert_equal 60, result
  end

  def test_native_hash_update_existing_key
    source = <<~RUBY
      def hash_update
        h = NativeHashStringInteger.new
        h["x"] = 10
        h["x"] = 20
        result = h["x"]
        size = h.size
        result * 10 + size
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
      end

      module TopLevel
        def hash_update: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_update)
    assert_equal 201, result  # 20 * 10 + 1 (size should remain 1)
  end

  def test_native_hash_has_key
    source = <<~RUBY
      def hash_has_key
        h = NativeHashStringInteger.new
        h["exists"] = 42
        if h.has_key?("exists")
          if h.has_key?("missing")
            0
          else
            1
          end
        else
          2
        end
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
        def has_key?: (String key) -> bool
      end

      module TopLevel
        def hash_has_key: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_has_key)
    assert_equal 1, result
  end

  def test_native_hash_delete
    source = <<~RUBY
      def hash_delete
        h = NativeHashStringInteger.new
        h["a"] = 1
        h["b"] = 2
        h["c"] = 3
        h.delete("b")
        h.size
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
        def delete: (String key) -> Integer
      end

      module TopLevel
        def hash_delete: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_delete)
    assert_equal 2, result
  end

  def test_native_hash_delete_and_reinsert
    source = <<~RUBY
      def hash_delete_reinsert
        h = NativeHashStringInteger.new
        h["key"] = 100
        h.delete("key")
        h["key"] = 200
        h["key"]
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
        def delete: (String key) -> Integer
      end

      module TopLevel
        def hash_delete_reinsert: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_delete_reinsert)
    assert_equal 200, result
  end

  def test_native_hash_keys
    source = <<~RUBY
      def hash_keys
        h = NativeHashStringInteger.new
        h["a"] = 1
        h["b"] = 2
        h["c"] = 3
        keys = h.keys
        keys.length
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringInteger
        def self.new: () -> NativeHashStringInteger
        def []: (String key) -> Integer
        def []=: (String key, Integer value) -> Integer
        def size: () -> Integer
        def keys: () -> Array
      end

      module TopLevel
        def hash_keys: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_keys)
    assert_equal 3, result
  end

  def test_native_hash_values
    source = <<~RUBY
      def hash_values
        h = NativeHashIntegerInteger.new
        h[1] = 10
        h[2] = 20
        h[3] = 30
        values = h.values
        values.length
      end
    RUBY

    rbs = <<~RBS
      class NativeHashIntegerInteger
        def self.new: () -> NativeHashIntegerInteger
        def []: (Integer key) -> Integer
        def []=: (Integer key, Integer value) -> Integer
        def size: () -> Integer
        def values: () -> Array
      end

      module TopLevel
        def hash_values: () -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, :hash_values)
    assert_equal 3, result
  end

  def test_native_hash_with_float_values
    source = <<~RUBY
      def hash_float_values
        h = NativeHashStringFloat.new
        h["pi"] = 3.14159
        h["e"] = 2.71828
        h["pi"] + h["e"]
      end
    RUBY

    rbs = <<~RBS
      class NativeHashStringFloat
        def self.new: () -> NativeHashStringFloat
        def []: (String key) -> Float
        def []=: (String key, Float value) -> Float
        def size: () -> Integer
      end

      module TopLevel
        def hash_float_values: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :hash_float_values)
    assert_in_delta 5.85987, result, 0.00001
  end
end
