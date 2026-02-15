# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class RegexpTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_simple_regexp_match
    source = <<~RUBY
      def matches_hello(str)
        /hello/.match?(str)
      end
    RUBY

    result = compile_and_run(source, 'matches_hello("hello world")')
    assert_equal true, result

    result2 = compile_and_run(source, 'matches_hello("goodbye")')
    assert_equal false, result2
  end

  def test_regexp_with_ignore_case
    source = <<~RUBY
      def matches_case_insensitive(str)
        /hello/i.match?(str)
      end
    RUBY

    result = compile_and_run(source, 'matches_case_insensitive("HELLO world")')
    assert_equal true, result
  end

  def test_regexp_return
    source = <<~RUBY
      def get_pattern
        /test/
      end
    RUBY

    result = compile_and_run(source, "get_pattern")
    assert_instance_of Regexp, result
    assert_equal(/test/, result)
  end

  def test_regexp_with_multiline
    source = <<~RUBY
      def multiline_match(str)
        /^world/m.match?(str)
      end
    RUBY

    result = compile_and_run(source, "multiline_match(\"hello\\nworld\")")
    assert_equal true, result
  end

  def test_regexp_with_special_chars
    source = <<~RUBY
      def digit_match(str)
        /\\d+/.match?(str)
      end
    RUBY

    result = compile_and_run(source, 'digit_match("abc123")')
    assert_equal true, result
  end

  def test_regexp_gsub
    source = <<~RUBY
      def replace_vowels(str)
        str.gsub(/[aeiou]/, "*")
      end
    RUBY

    result = compile_and_run(source, 'replace_vowels("hello")')
    assert_equal "h*ll*", result
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
