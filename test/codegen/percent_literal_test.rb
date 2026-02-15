# frozen_string_literal: true

require "test_helper"
require "fileutils"

class PercentLiteralTest < Minitest::Test
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

  def compile_to_bundle(source, name)
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
    output_file
  end

  def test_percent_w_literal
    source = <<~RUBY
      def pl_words
        %w[foo bar baz]
      end
    RUBY
    output = compile_to_bundle(source, "test_pl_w")
    require output
    assert_equal ["foo", "bar", "baz"], pl_words
  end

  def test_percent_i_literal
    source = <<~RUBY
      def pl_symbols
        %i[a b c]
      end
    RUBY
    output = compile_to_bundle(source, "test_pl_i")
    require output
    assert_equal [:a, :b, :c], pl_symbols
  end

  def test_percent_w_with_length
    source = <<~RUBY
      def pl_word_count
        words = %w[one two three four]
        words.length
      end
    RUBY
    output = compile_to_bundle(source, "test_pl_wlen")
    require output
    assert_equal 4, pl_word_count
  end
end
