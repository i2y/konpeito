# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class VariadicArgsTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_keyword_rest_simple
    source = <<~RUBY
      def collect_options(**opts)
        opts
      end
    RUBY

    result = compile_and_run(source, 'collect_options(a: 1, b: 2)')
    assert_equal({ a: 1, b: 2 }, result)
  end

  # Test that **kwargs can be called with no arguments
  def test_keyword_rest_empty
    source = <<~RUBY
      def no_options(**opts)
        opts
      end
    RUBY

    result = compile_and_run(source, 'no_options')
    assert_equal({}, result)
  end

  def test_keyword_rest_with_positional
    source = <<~RUBY
      def mixed(x, **opts)
        [x, opts]
      end
    RUBY

    result = compile_and_run(source, 'mixed(10, name: "test", count: 5)')
    assert_equal [10, { name: "test", count: 5 }], result
  end

  def test_keyword_rest_access
    source = <<~RUBY
      def get_value(**opts)
        opts[:key]
      end
    RUBY

    result = compile_and_run(source, 'get_value(key: "found")')
    assert_equal "found", result
  end

  # *args tests
  def test_rest_args_simple
    source = <<~RUBY
      def collect_all(*args)
        args
      end
    RUBY

    result = compile_and_run(source, 'collect_all(1, 2, 3)')
    assert_equal [1, 2, 3], result
  end

  def test_rest_args_empty
    source = <<~RUBY
      def collect_all(*args)
        args
      end
    RUBY

    result = compile_and_run(source, 'collect_all')
    assert_equal [], result
  end

  def test_rest_args_with_leading
    source = <<~RUBY
      def with_leading(first, *rest)
        [first, rest]
      end
    RUBY

    result = compile_and_run(source, 'with_leading(1, 2, 3, 4)')
    assert_equal [1, [2, 3, 4]], result
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
