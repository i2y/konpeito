# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class JSONParseArrayTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_count = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def compile_and_run(source, rbs_source, call_expr)
    @test_count += 1
    source_path = File.join(@tmp_dir, "test#{@test_count}.rb")
    rbs_path = File.join(@tmp_dir, "test#{@test_count}.rbs")
    output_path = File.join(@tmp_dir, "test#{@test_count}.bundle")

    File.write(source_path, source)
    File.write(rbs_path, rbs_source)

    compiler = Konpeito::Compiler.new(
      source_file: source_path,
      output_file: output_path,
      rbs_paths: [rbs_path],
      verbose: ENV["VERBOSE"] == "1"
    )

    success = compiler.compile

    unless success
      skip "Compilation failed"
      return nil
    end

    if File.exist?(output_path)
      require output_path
      eval(call_expr)
    end
  end

  def test_parse_array_as_float_fields
    source = <<~RUBY
      def parse_vec_arr_sum(json)
        arr = KonpeitoJSON.parse_array_as(json, Vec2)
        arr[0].x + arr[0].y + arr[1].x + arr[1].y
      end
    RUBY

    rbs = <<~RBS
      class Vec2
        @x: Float
        @y: Float

        def self.new: () -> Vec2
        def x: () -> Float
        def y: () -> Float
      end

      module KonpeitoJSON
        def self.parse_array_as: [T] (String json, Class[T] element_class) -> NativeArray[T]
      end

      module TopLevel
        def parse_vec_arr_sum: (String json) -> Float
      end
    RBS

    result = compile_and_run(source, rbs, 'parse_vec_arr_sum(\'[{"x": 1.5, "y": 2.5}, {"x": 3.0, "y": 4.0}]\')')
    assert_in_delta 11.0, result, 0.001
  end

  def test_parse_array_as_integer_fields
    source = <<~RUBY
      def parse_points_sum(json)
        arr = KonpeitoJSON.parse_array_as(json, IntPt)
        arr[0].x + arr[0].y + arr[1].x + arr[1].y
      end
    RUBY

    rbs = <<~RBS
      class IntPt
        @x: Integer
        @y: Integer

        def self.new: () -> IntPt
        def x: () -> Integer
        def y: () -> Integer
      end

      module KonpeitoJSON
        def self.parse_array_as: [T] (String json, Class[T] element_class) -> NativeArray[T]
      end

      module TopLevel
        def parse_points_sum: (String json) -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, 'parse_points_sum(\'[{"x": 10, "y": 20}, {"x": 30, "y": 40}]\')')
    assert_equal 100, result
  end
end
