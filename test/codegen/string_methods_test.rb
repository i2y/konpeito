# frozen_string_literal: true

require "test_helper"
require "fileutils"

class StringMethodsTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = File.join(__dir__, "..", "tmp")
    FileUtils.mkdir_p(@output_dir)
  end

  def teardown
    FileUtils.rm_rf(@output_dir)
  end

  def compile_and_load(source, name)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: name)
    llvm_gen.generate(hir)

    output_file = File.join(@output_dir, "#{name}.bundle")
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: output_file,
      module_name: name
    )
    backend.generate
    require output_file
  end

  def test_string_split
    compile_and_load(<<~RUBY, "str_split")
      def test_split
        "hello world foo".split(" ")
      end
    RUBY
    assert_equal ["hello", "world", "foo"], test_split
  end

  def test_string_upcase_downcase
    compile_and_load(<<~RUBY, "str_case")
      def test_upcase
        "hello".upcase
      end

      def test_downcase
        "HELLO".downcase
      end
    RUBY
    assert_equal "HELLO", test_upcase
    assert_equal "hello", test_downcase
  end

  def test_string_strip
    compile_and_load(<<~RUBY, "str_strip")
      def test_strip
        "  hello  ".strip
      end
    RUBY
    assert_equal "hello", test_strip
  end

  def test_string_include
    compile_and_load(<<~RUBY, "str_include")
      def test_include
        "hello world".include?("world")
      end
    RUBY
    assert_equal true, test_include
  end

  def test_string_empty
    compile_and_load(<<~RUBY, "str_empty")
      def test_empty
        "".empty?
      end

      def test_not_empty
        "hello".empty?
      end
    RUBY
    assert_equal true, test_empty
    assert_equal false, test_not_empty
  end

  def test_string_chars
    compile_and_load(<<~RUBY, "str_chars")
      def test_chars
        "abc".chars
      end
    RUBY
    assert_equal ["a", "b", "c"], test_chars
  end

  def test_string_reverse
    compile_and_load(<<~RUBY, "str_reverse")
      def test_reverse
        "hello".reverse
      end
    RUBY
    assert_equal "olleh", test_reverse
  end

  def test_string_gsub
    compile_and_load(<<~RUBY, "str_gsub")
      def test_gsub
        "hello world".gsub("world", "ruby")
      end
    RUBY
    assert_equal "hello ruby", test_gsub
  end

  def test_string_start_with
    compile_and_load(<<~RUBY, "str_start")
      def test_start_with
        "hello".start_with?("hel")
      end
    RUBY
    assert_equal true, test_start_with
  end

  def test_string_bytes
    compile_and_load(<<~RUBY, "str_bytes")
      def test_bytes
        "ABC".bytes
      end
    RUBY
    assert_equal [65, 66, 67], test_bytes
  end
end
