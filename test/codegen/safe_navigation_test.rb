# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class SafeNavigationTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("safe_nav_test")
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

  def test_safe_nav_on_nil
    compile_and_load(<<~RUBY, "safe_nav_nil")
      def kp_safe_nav_nil
        x = nil
        x&.to_s
      end
    RUBY

    assert_nil kp_safe_nav_nil
  end

  def test_safe_nav_on_non_nil
    compile_and_load(<<~RUBY, "safe_nav_str")
      def kp_safe_nav_str
        x = "hello"
        x&.length
      end
    RUBY

    assert_equal 5, kp_safe_nav_str
  end

  def test_safe_nav_chained
    compile_and_load(<<~RUBY, "safe_nav_chain")
      def kp_safe_nav_chain(x)
        x&.to_s&.length
      end
    RUBY

    assert_nil kp_safe_nav_chain(nil)
    assert_equal 2, kp_safe_nav_chain(42)
  end
end
