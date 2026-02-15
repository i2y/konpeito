# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class RescueElseTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("rescue_else_test")
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

  def test_rescue_else_no_exception
    compile_and_load(<<~RUBY, "rescue_else_ok")
      def kp_rescue_else_ok
        begin
          42
        rescue StandardError
          "error"
        else
          "no error"
        end
      end
    RUBY

    assert_equal "no error", kp_rescue_else_ok
  end

  def test_rescue_else_with_exception
    compile_and_load(<<~RUBY, "rescue_else_err")
      def kp_rescue_else_err
        begin
          raise "boom"
        rescue StandardError
          "caught"
        else
          "no error"
        end
      end
    RUBY

    assert_equal "caught", kp_rescue_else_err
  end

  def test_rescue_else_ir_generation
    source = <<~RUBY
      def test_else
        begin
          risky
        rescue StandardError
          "error"
        else
          "ok"
        end
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "rescue_else_ir")
    llvm_gen.generate(hir)
    ir = llvm_gen.to_ir

    # Should have rescue_else block
    assert_includes ir, "rescue_else"
  end
end
