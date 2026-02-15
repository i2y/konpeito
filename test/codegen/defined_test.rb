# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class DefinedTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("defined_test")
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

  def test_defined_local_variable
    compile_and_load(<<~RUBY, "defined_local")
      def kp_defined_local
        x = 42
        defined?(x)
      end
    RUBY

    assert_equal "local-variable", kp_defined_local
  end

  def test_defined_constant
    compile_and_load(<<~RUBY, "defined_const")
      def kp_defined_const
        defined?(Integer)
      end
    RUBY

    assert_equal "constant", kp_defined_const
  end

  def test_defined_undefined_constant
    compile_and_load(<<~RUBY, "defined_undef")
      def kp_defined_undef
        defined?(NonExistentConstantXYZ123)
      end
    RUBY

    assert_nil kp_defined_undef
  end
end
