# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class StringInterpolationTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_simple_string_interpolation
    source = <<~RUBY
      def greet(name)
        "Hello, \#{name}!"
      end
    RUBY

    result = compile_and_run(source, 'greet("World")')
    assert_equal "Hello, World!", result
  end

  def test_interpolation_with_integer
    source = <<~RUBY
      def format_number(n)
        "The number is \#{n}"
      end
    RUBY

    result = compile_and_run(source, "format_number(42)")
    assert_equal "The number is 42", result
  end

  def test_interpolation_with_expression
    source = <<~RUBY
      def calculate(a, b)
        "Sum: \#{a + b}"
      end
    RUBY

    result = compile_and_run(source, "calculate(3, 4)")
    assert_equal "Sum: 7", result
  end

  def test_multiple_interpolations
    source = <<~RUBY
      def info(name, age)
        "\#{name} is \#{age} years old"
      end
    RUBY

    result = compile_and_run(source, 'info("Alice", 30)')
    assert_equal "Alice is 30 years old", result
  end

  def test_interpolation_with_method_call
    source = <<~RUBY
      def upper_greeting(name)
        "Hello, \#{name.upcase}!"
      end
    RUBY

    result = compile_and_run(source, 'upper_greeting("world")')
    assert_equal "Hello, WORLD!", result
  end

  def test_interpolation_only
    source = <<~RUBY
      def wrap(value)
        "\#{value}"
      end
    RUBY

    result = compile_and_run(source, "wrap(123)")
    assert_equal "123", result
  end

  def test_nested_interpolation_expression
    source = <<~RUBY
      def complex(x, y)
        "Result: \#{(x * 2) + y}"
      end
    RUBY

    result = compile_and_run(source, "complex(5, 3)")
    assert_equal "Result: 13", result
  end

  private

  def compile_and_run(source, call_expr)
    source_file = File.join(@tmp_dir, "test.rb")
    output_file = File.join(@tmp_dir, "test.bundle")

    File.write(source_file, source)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file
    )
    compiler.compile

    require output_file

    eval(call_expr)
  end
end
