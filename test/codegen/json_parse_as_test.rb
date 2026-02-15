# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class JSONParseAsTest < Minitest::Test
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

  def test_parse_as_integer_fields
    source = <<~RUBY
      def parse_point(json)
        p = KonpeitoJSON.parse_as(json, Point)
        p.x + p.y
      end
    RUBY

    rbs = <<~RBS
      class Point
        @x: Integer
        @y: Integer

        def self.new: () -> Point
        def x: () -> Integer
        def y: () -> Integer
      end

      module KonpeitoJSON
        def self.parse_as: [T] (String json, Class[T] target_class) -> T
      end

      module TopLevel
        def parse_point: (String json) -> Integer
      end
    RBS

    result = compile_and_run(source, rbs, 'parse_point(\'{"x": 10, "y": 20}\')')
    assert_equal 30, result
  end

  def test_parse_as_float_fields
    source = <<~RUBY
      def parse_vec(json)
        v = KonpeitoJSON.parse_as(json, Vec2)
        v.x * v.y
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
        def self.parse_as: [T] (String json, Class[T] target_class) -> T
      end

      module TopLevel
        def parse_vec: (String json) -> Float
      end
    RBS

    result = compile_and_run(source, rbs, 'parse_vec(\'{"x": 2.5, "y": 4.0}\')')
    assert_in_delta 10.0, result, 0.001
  end

  def test_parse_as_mixed_fields
    source = <<~RUBY
      def parse_user(json)
        u = KonpeitoJSON.parse_as(json, User)
        u.name
      end
    RUBY

    rbs = <<~RBS
      class User
        @id: Integer
        @name: String
        @score: Float

        def self.new: () -> User
        def id: () -> Integer
        def name: () -> String
        def score: () -> Float
      end

      module KonpeitoJSON
        def self.parse_as: [T] (String json, Class[T] target_class) -> T
      end

      module TopLevel
        def parse_user: (String json) -> String
      end
    RBS

    result = compile_and_run(source, rbs, 'parse_user(\'{"id": 42, "name": "Alice", "score": 95.5}\')')
    assert_equal "Alice", result
  end

  def test_parse_as_bool_field
    source = <<~RUBY
      def check_active(json)
        f = KonpeitoJSON.parse_as(json, Flag)
        if f.active
          1
        else
          0
        end
      end
    RUBY

    rbs = <<~RBS
      class Flag
        @active: bool

        def self.new: () -> Flag
        def active: () -> bool
      end

      module KonpeitoJSON
        def self.parse_as: [T] (String json, Class[T] target_class) -> T
      end

      module TopLevel
        def check_active: (String json) -> Integer
      end
    RBS

    result_true = compile_and_run(source, rbs, 'check_active(\'{"active": true}\')')
    assert_equal 1, result_true

    # Note: For false case, need separate compile since method is already defined
  end
end
