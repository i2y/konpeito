# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class RegexCaptureTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("regex_test")
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

  def test_string_scan
    compile_and_load(<<~RUBY, "regex_scan")
      def kp_scan
        "hello world foo".scan(/\\w+/)
      end
    RUBY

    assert_equal ["hello", "world", "foo"], kp_scan
  end

  def test_string_match_question
    compile_and_load(<<~RUBY, "regex_match_q")
      def kp_match_q
        "hello123".match?(/\\d+/)
      end
    RUBY

    assert_equal true, kp_match_q
  end

  def test_string_gsub_with_regex
    compile_and_load(<<~RUBY, "regex_gsub")
      def kp_regex_gsub
        "hello world".gsub(/[aeiou]/, "*")
      end
    RUBY

    assert_equal "h*ll* w*rld", kp_regex_gsub
  end
end
