# frozen_string_literal: true

require "test_helper"
require "fileutils"

class EndlessMethodTest < Minitest::Test
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

  def test_endless_method_simple
    source = <<~RUBY
      def em_answer = 42
    RUBY
    output = compile_to_bundle(source, "test_em_simple")
    require output
    assert_equal 42, em_answer
  end

  def test_endless_method_with_param
    source = <<~RUBY
      def em_double(x) = x * 2
    RUBY
    output = compile_to_bundle(source, "test_em_param")
    require output
    assert_equal 10, em_double(5)
    assert_equal 0, em_double(0)
  end

  def test_endless_method_with_two_params
    source = <<~RUBY
      def em_add(a, b) = a + b
    RUBY
    output = compile_to_bundle(source, "test_em_two")
    require output
    assert_equal 7, em_add(3, 4)
  end

  def test_endless_method_string
    source = <<~RUBY
      def em_greet(name) = "Hello, " + name
    RUBY
    output = compile_to_bundle(source, "test_em_str")
    require output
    assert_equal "Hello, World", em_greet("World")
  end
end
