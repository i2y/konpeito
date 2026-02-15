# frozen_string_literal: true

require "test_helper"
require "fileutils"

class NumberedParamsTest < Minitest::Test
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

  def test_numbered_param_map
    source = <<~RUBY
      def np_map_double
        [1, 2, 3].map { _1 * 2 }
      end
    RUBY
    output = compile_to_bundle(source, "test_np_map")
    require output
    assert_equal [2, 4, 6], np_map_double
  end

  def test_numbered_param_select
    source = <<~RUBY
      def np_select_even
        [1, 2, 3, 4, 5, 6].select { _1 % 2 == 0 }
      end
    RUBY
    output = compile_to_bundle(source, "test_np_select")
    require output
    assert_equal [2, 4, 6], np_select_even
  end

  def test_numbered_param_each
    source = <<~RUBY
      def np_sum_each
        total = 0
        [10, 20, 30].each { total = total + _1 }
        total
      end
    RUBY
    output = compile_to_bundle(source, "test_np_each")
    require output
    assert_equal 60, np_sum_each
  end

  def test_numbered_param_reduce
    source = <<~RUBY
      def np_reduce_sum
        [1, 2, 3, 4, 5].reduce(0) { _1 + _2 }
      end
    RUBY
    output = compile_to_bundle(source, "test_np_reduce")
    require output
    assert_equal 15, np_reduce_sum
  end
end
