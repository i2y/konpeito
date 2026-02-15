# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class SplatCallTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("splat_call_test")
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

  def test_splat_array_to_method
    compile_and_load(<<~RUBY, "splat_basic")
      def kp_splat_target(a, b, c)
        a + b + c
      end

      def kp_splat_call
        args = [10, 20, 30]
        kp_splat_target(*args)
      end
    RUBY

    assert_equal 60, kp_splat_call
  end

  def test_splat_with_fixed_args
    compile_and_load(<<~RUBY, "splat_mixed")
      def kp_splat_mixed_target(a, b, c)
        a + b + c
      end

      def kp_splat_mixed_call
        rest = [20, 30]
        kp_splat_mixed_target(10, *rest)
      end
    RUBY

    assert_equal 60, kp_splat_mixed_call
  end

  def test_splat_with_method_call
    compile_and_load(<<~RUBY, "splat_method")
      def kp_splat_join
        parts = ["hello", "world"]
        parts.join(*[", "])
      end
    RUBY

    assert_equal "hello, world", kp_splat_join
  end
end
