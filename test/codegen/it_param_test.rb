# frozen_string_literal: true

require "test_helper"
require "fileutils"

class ItParamTest < Minitest::Test
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

  def test_it_param_map
    source = <<~RUBY
      def ip_map_double
        [1, 2, 3].map { it * 2 }
      end
    RUBY
    output = compile_to_bundle(source, "test_ip_map")
    require output
    assert_equal [2, 4, 6], ip_map_double
  end

  def test_it_param_select
    source = <<~RUBY
      def ip_select_positive
        [-1, 0, 1, 2, -3].select { it > 0 }
      end
    RUBY
    output = compile_to_bundle(source, "test_ip_select")
    require output
    assert_equal [1, 2], ip_select_positive
  end

  def test_it_param_each
    source = <<~RUBY
      def ip_sum_each
        total = 0
        [5, 10, 15].each { total = total + it }
        total
      end
    RUBY
    output = compile_to_bundle(source, "test_ip_each")
    require output
    assert_equal 30, ip_sum_each
  end

  def test_it_param_any
    source = <<~RUBY
      def ip_has_negative
        [1, 2, -3, 4].any? { it < 0 }
      end
    RUBY
    output = compile_to_bundle(source, "test_ip_any")
    require output
    assert_equal true, ip_has_negative
  end
end
