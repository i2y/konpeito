# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class ModuleNativeArrayTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_module_native_array_basic_get_set
    source = <<~RUBY
      module Storage
      end

      def main
        Storage.data[0] = 10
        Storage.data[1] = 20
        Storage.data[2] = 30
        Storage.data[3] = 40
        Storage.data[0] + Storage.data[1] + Storage.data[2] + Storage.data[3]
      end
    RUBY

    result = compile_and_run(source, "main", <<~RBS)
      module Storage
        @data: NativeArray[Integer, 4]
      end

      module TopLevel
        def main: () -> Integer
      end
    RBS

    assert_equal 100, result
  end

  def test_module_native_array_persistence_across_functions
    source = <<~RUBY
      module State
      end

      def store_value
        State.counter[0] = 42
        0
      end

      def load_value
        State.counter[0]
      end

      def main
        store_value
        load_value
      end
    RUBY

    result = compile_and_run(source, "main", <<~RBS)
      module State
        @counter: NativeArray[Integer, 1]
      end

      module TopLevel
        def store_value: () -> Integer
        def load_value: () -> Integer
        def main: () -> Integer
      end
    RBS

    assert_equal 42, result
  end

  def test_module_native_array_float
    source = <<~RUBY
      module Buf
      end

      def main
        Buf.vals[0] = 1.5
        Buf.vals[1] = 2.5
        Buf.vals[2] = 3.0
        Buf.vals[0] + Buf.vals[1] + Buf.vals[2]
      end
    RUBY

    result = compile_and_run(source, "main", <<~RBS)
      module Buf
        @vals: NativeArray[Float, 3]
      end

      module TopLevel
        def main: () -> Float
      end
    RBS

    assert_in_delta 7.0, result, 0.001
  end

  def test_module_native_array_multiple_fields
    source = <<~RUBY
      module Game
      end

      def main
        Game.x[0] = 10
        Game.x[1] = 20
        Game.y[0] = 100
        Game.y[1] = 200
        Game.x[0] + Game.x[1] + Game.y[0] + Game.y[1]
      end
    RUBY

    result = compile_and_run(source, "main", <<~RBS)
      module Game
        @x: NativeArray[Integer, 3]
        @y: NativeArray[Integer, 3]
      end

      module TopLevel
        def main: () -> Integer
      end
    RBS

    assert_equal 330, result
  end

  def test_module_native_array_loop_access
    source = <<~RUBY
      module Arr
      end

      def main
        i = 0
        while i < 10
          Arr.data[i] = i * i
          i = i + 1
        end
        Arr.data[0] + Arr.data[9]
      end
    RUBY

    result = compile_and_run(source, "main", <<~RBS)
      module Arr
        @data: NativeArray[Integer, 10]
      end

      module TopLevel
        def main: () -> Integer
      end
    RBS

    assert_equal 81, result  # 0*0 + 9*9
  end

  private

  def compile_and_run(source, call_expr, rbs_content)
    @test_counter ||= 0
    @test_counter += 1
    basename = "mna_test_#{Process.pid}_#{@test_counter}"

    source_file = File.join(@tmp_dir, "#{basename}.rb")
    rbs_file = File.join(@tmp_dir, "#{basename}.rbs")
    output_file = File.join(@tmp_dir, "#{basename}#{SHARED_EXT}")

    File.write(source_file, source)
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
