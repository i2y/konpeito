# frozen_string_literal: true

require "test_helper"
require "fileutils"

class MultiAssignTest < Minitest::Test
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

  def test_multi_assign_basic
    source = <<~RUBY
      def ma_basic
        a, b = [10, 20]
        a + b
      end
    RUBY
    output = compile_to_bundle(source, "test_ma_basic")
    require output
    assert_equal 30, ma_basic
  end

  def test_multi_assign_three_vars
    source = <<~RUBY
      def ma_three
        a, b, c = [1, 2, 3]
        a + b + c
      end
    RUBY
    output = compile_to_bundle(source, "test_ma_three")
    require output
    assert_equal 6, ma_three
  end

  def test_multi_assign_strings
    source = <<~RUBY
      def ma_strings
        x, y = ["hello", "world"]
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ma_strings")
    require output
    assert_equal "hello", ma_strings
  end
end
