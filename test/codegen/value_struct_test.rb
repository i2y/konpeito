# frozen_string_literal: true

require "test_helper"
require "konpeito/compiler"
require "tempfile"
require "tmpdir"

class ValueStructTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_value_struct_creation_and_field_access
    ruby_source = <<~RUBY
      def create_point
        p = Point.new
        p.x = 1.5
        p.y = 2.5
        p.x + p.y
      end
    RUBY

    rbs_source = <<~RBS
      %a{struct}      class Point
        @x: Float
        @y: Float

        def self.new: () -> Point
        def x: () -> Float
        def x=: (Float) -> Float
        def y: () -> Float
        def y=: (Float) -> Float
      end

      module TopLevel
        def create_point: () -> Float
      end
    RBS

    result = compile_and_run(ruby_source, rbs_source, "create_point")
    assert_in_delta 4.0, result, 0.001
  end

  def test_value_struct_multiple_operations
    ruby_source = <<~RUBY
      def compute_distance
        p1 = Point.new
        p1.x = 3.0
        p1.y = 4.0

        p2 = Point.new
        p2.x = 0.0
        p2.y = 0.0

        dx = p1.x - p2.x
        dy = p1.y - p2.y
        dx * dx + dy * dy
      end
    RUBY

    rbs_source = <<~RBS
      %a{struct}      class Point
        @x: Float
        @y: Float

        def self.new: () -> Point
        def x: () -> Float
        def x=: (Float) -> Float
        def y: () -> Float
        def y=: (Float) -> Float
      end

      module TopLevel
        def compute_distance: () -> Float
      end
    RBS

    result = compile_and_run(ruby_source, rbs_source, "compute_distance")
    assert_in_delta 25.0, result, 0.001  # 3^2 + 4^2 = 25
  end

  def test_value_struct_integer_fields
    ruby_source = <<~RUBY
      def point_sum
        p = IntPoint.new
        p.x = 10
        p.y = 20
        p.x + p.y
      end
    RUBY

    rbs_source = <<~RBS
      %a{struct}      class IntPoint
        @x: Integer
        @y: Integer

        def self.new: () -> IntPoint
        def x: () -> Integer
        def x=: (Integer) -> Integer
        def y: () -> Integer
        def y=: (Integer) -> Integer
      end

      module TopLevel
        def point_sum: () -> Integer
      end
    RBS

    result = compile_and_run(ruby_source, rbs_source, "point_sum")
    assert_equal 30, result
  end

  def test_value_struct_bool_fields
    ruby_source = <<~RUBY
      def check_flags
        f = Flags.new
        f.a = true
        f.b = false

        if f.a
          if f.b
            3
          else
            1
          end
        else
          2
        end
      end
    RUBY

    rbs_source = <<~RBS
      %a{struct}      class Flags
        @a: bool
        @b: bool

        def self.new: () -> Flags
        def a: () -> bool
        def a=: (bool) -> bool
        def b: () -> bool
        def b=: (bool) -> bool
      end

      module TopLevel
        def check_flags: () -> Integer
      end
    RBS

    result = compile_and_run(ruby_source, rbs_source, "check_flags")
    assert_equal 1, result
  end

  def test_value_struct_in_loop
    ruby_source = <<~RUBY
      def accumulate_loop(n)
        total = 0.0
        i = 0
        while i < n
          p = Point.new
          p.x = i * 1.0
          p.y = i * 2.0
          total = total + p.x + p.y
          i = i + 1
        end
        total
      end
    RUBY

    rbs_source = <<~RBS
      %a{struct}      class Point
        @x: Float
        @y: Float

        def self.new: () -> Point
        def x: () -> Float
        def x=: (Float) -> Float
        def y: () -> Float
        def y=: (Float) -> Float
      end

      module TopLevel
        def accumulate_loop: (Integer n) -> Float
      end
    RBS

    result = compile_and_run(ruby_source, rbs_source, "accumulate_loop", 5)
    # i=0: 0+0=0, i=1: 1+2=3, i=2: 2+4=6, i=3: 3+6=9, i=4: 4+8=12
    # total = 0+3+6+9+12 = 30
    assert_in_delta 30.0, result, 0.001
  end

  def test_value_struct_validation_rejects_value_fields
    # This should warn and fall back to reference type
    ruby_source = <<~RUBY
      def create_person
        p = Person.new
        p.age = 30
        p.age
      end
    RUBY

    rbs_source = <<~RBS
      %a{struct}      class Person
        @age: Integer
        @name: String

        def self.new: () -> Person
        def age: () -> Integer
        def age=: (Integer) -> Integer
        def name: () -> String
        def name=: (String) -> String
      end

      module TopLevel
        def create_person: () -> Integer
      end
    RBS

    # Should still work but as a reference type (with warning)
    result = compile_and_run(ruby_source, rbs_source, "create_person")
    assert_equal 30, result
  end

  private

  def compile_and_run(ruby_source, rbs_source, method_name, *args)
    rb_file = File.join(@temp_dir, "test.rb")
    rbs_file = File.join(@temp_dir, "types.rbs")
    bundle_file = File.join(@temp_dir, "test.bundle")

    File.write(rb_file, ruby_source)
    File.write(rbs_file, rbs_source)

    compiler = Konpeito::Compiler.new(
      source_file: rb_file,
      output_file: bundle_file,
      rbs_paths: [rbs_file]
    )
    compiler.compile

    require bundle_file
    send(method_name, *args)
  end
end
