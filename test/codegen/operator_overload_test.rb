# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class OperatorOverloadTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
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

  VECTOR2_RBS = <<~RBS
    class Vector2
      @x: Float
      @y: Float

      def self.new: () -> Vector2
      def x: () -> Float
      def x=: (Float value) -> Float
      def y: () -> Float
      def y=: (Float value) -> Float
      def +: (Vector2 other) -> Vector2
      def -: (Vector2 other) -> Vector2
      def *: (Float scalar) -> Vector2
    end
  RBS

  def test_custom_plus_operator
    source = <<~RUBY
      class Vector2
        def x
          @x
        end
        def y
          @y
        end
        def +(other)
          result = Vector2.new
          result.x = @x + other.x
          result.y = @y + other.y
          result
        end
      end

      def test_vec_add
        v1 = Vector2.new
        v1.x = 1.0
        v1.y = 2.0
        v2 = Vector2.new
        v2.x = 3.0
        v2.y = 4.0
        v3 = v1 + v2
        v3.x + v3.y
      end
    RUBY

    rbs = VECTOR2_RBS + <<~RBS
      module TopLevel
        def test_vec_add: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :test_vec_add)
    assert_in_delta 10.0, result, 0.001
  end

  def test_custom_minus_operator
    source = <<~RUBY
      class Vector2
        def x
          @x
        end
        def y
          @y
        end
        def -(other)
          result = Vector2.new
          result.x = @x - other.x
          result.y = @y - other.y
          result
        end
      end

      def test_vec_sub
        v1 = Vector2.new
        v1.x = 5.0
        v1.y = 8.0
        v2 = Vector2.new
        v2.x = 2.0
        v2.y = 3.0
        v3 = v1 - v2
        v3.x + v3.y
      end
    RUBY

    rbs = VECTOR2_RBS + <<~RBS
      module TopLevel
        def test_vec_sub: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :test_vec_sub)
    assert_in_delta 8.0, result, 0.001
  end

  def test_custom_multiply_operator
    source = <<~RUBY
      class Vector2
        def x
          @x
        end
        def y
          @y
        end
        def *(scalar)
          result = Vector2.new
          result.x = @x * scalar
          result.y = @y * scalar
          result
        end
      end

      def test_vec_scale
        v = Vector2.new
        v.x = 3.0
        v.y = 4.0
        scaled = v * 2.0
        scaled.x + scaled.y
      end
    RUBY

    rbs = VECTOR2_RBS + <<~RBS
      module TopLevel
        def test_vec_scale: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :test_vec_scale)
    assert_in_delta 14.0, result, 0.001
  end

  def test_custom_dot_product
    source = <<~RUBY
      class Vector2
        def x
          @x
        end
        def y
          @y
        end
        def dot(other)
          @x * other.x + @y * other.y
        end
      end

      def test_vec_dot
        v1 = Vector2.new
        v1.x = 2.0
        v1.y = 3.0
        v2 = Vector2.new
        v2.x = 4.0
        v2.y = 5.0
        v1.dot(v2)
      end
    RUBY

    rbs = <<~RBS
      class Vector2
        @x: Float
        @y: Float

        def self.new: () -> Vector2
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
        def dot: (Vector2 other) -> Float
      end

      module TopLevel
        def test_vec_dot: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :test_vec_dot)
    assert_in_delta 23.0, result, 0.001
  end

  def test_operator_chaining
    source = <<~RUBY
      class Vector2
        def x
          @x
        end
        def y
          @y
        end
        def +(other)
          result = Vector2.new
          result.x = @x + other.x
          result.y = @y + other.y
          result
        end
      end

      def test_vec_chain
        v1 = Vector2.new
        v1.x = 1.0
        v1.y = 1.0
        v2 = Vector2.new
        v2.x = 2.0
        v2.y = 2.0
        v3 = Vector2.new
        v3.x = 3.0
        v3.y = 3.0
        result = v1 + v2 + v3
        result.x + result.y
      end
    RUBY

    rbs = VECTOR2_RBS + <<~RBS
      module TopLevel
        def test_vec_chain: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :test_vec_chain)
    assert_in_delta 12.0, result, 0.001
  end

  def test_operator_result_field_access
    source = <<~RUBY
      class Vector2
        def x
          @x
        end
        def y
          @y
        end
        def +(other)
          result = Vector2.new
          result.x = @x + other.x
          result.y = @y + other.y
          result
        end
      end

      def test_vec_field
        v1 = Vector2.new
        v1.x = 3.0
        v1.y = 4.0
        v2 = Vector2.new
        v2.x = 1.0
        v2.y = 2.0
        (v1 + v2).x * 2.0
      end
    RUBY

    rbs = VECTOR2_RBS + <<~RBS
      module TopLevel
        def test_vec_field: () -> Float
      end
    RBS

    result = compile_and_run(source, rbs, :test_vec_field)
    assert_in_delta 8.0, result, 0.001
  end
end
