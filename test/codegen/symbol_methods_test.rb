# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class SymbolMethodsTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_symbol_to_s
    source = <<~RUBY
      def sym_to_s_test
        :hello.to_s
      end
    RUBY

    result = compile_and_run(source, "sym_to_s_test")
    assert_equal "hello", result
  end

  def test_symbol_id2name
    source = <<~RUBY
      def sym_id2name_test
        :world.id2name
      end
    RUBY

    result = compile_and_run(source, "sym_id2name_test")
    assert_equal "world", result
  end

  def test_symbol_name
    source = <<~RUBY
      def sym_name_test
        :ruby.name
      end
    RUBY

    result = compile_and_run(source, "sym_name_test")
    assert_equal "ruby", result
  end

  def test_symbol_to_s_in_interpolation
    source = <<~RUBY
      def sym_interp_test
        s = :konpeito
        "name: \#{s.to_s}"
      end
    RUBY

    result = compile_and_run(source, "sym_interp_test")
    assert_equal "name: konpeito", result
  end

  def test_symbol_to_s_special_chars
    source = <<~RUBY
      def sym_special_test
        :foo_bar.to_s
      end
    RUBY

    result = compile_and_run(source, "sym_special_test")
    assert_equal "foo_bar", result
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
