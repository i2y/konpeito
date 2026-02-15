# frozen_string_literal: true

require "test_helper"
require "fileutils"

class GlobalVariableTest < Minitest::Test
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

  def test_global_variable_write_and_read
    source = <<~RUBY
      def gv_set_and_get
        $gv_test_val = 42
        $gv_test_val
      end
    RUBY
    output = compile_to_bundle(source, "test_gv_rw")
    require output
    assert_equal 42, gv_set_and_get
  end

  def test_global_variable_string
    source = <<~RUBY
      def gv_string
        $gv_test_str = "hello"
        $gv_test_str
      end
    RUBY
    output = compile_to_bundle(source, "test_gv_str")
    require output
    assert_equal "hello", gv_string
  end
end
