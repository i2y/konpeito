# frozen_string_literal: true

require "test_helper"
require "fileutils"

class CustomExceptionTest < Minitest::Test
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

  def get_init_c_code(source, name)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: name)
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@output_dir, "#{name}.bundle"),
      module_name: name
    )

    backend.send(:generate_init_c_code)
  end

  def test_custom_exception_superclass_in_init_code
    source = <<~RUBY
      class MyError < StandardError
      end

      def test_custom_error
        begin
          raise MyError, "custom error"
        rescue MyError
          "caught custom"
        rescue StandardError
          "caught standard"
        end
      end
    RUBY

    c_code = get_init_c_code(source, "custom_exc_ir")
    assert_includes c_code, "rb_eStandardError"
    refute_match(/rb_define_class\("MyError", rb_cObject\)/, c_code)
  end

  def test_custom_exception_hierarchy
    source = <<~RUBY
      class AppError < RuntimeError
      end

      class ValidationError < AppError
      end
    RUBY

    c_code = get_init_c_code(source, "exc_hierarchy")
    # AppError should use rb_eRuntimeError
    assert_includes c_code, 'rb_define_class("AppError", rb_eRuntimeError)'
    # ValidationError should use cAppError (user-defined)
    assert_includes c_code, 'rb_define_class("ValidationError", cAppError)'

    # AppError must be defined before ValidationError (topological sort)
    app_pos = c_code.index('rb_define_class("AppError"')
    val_pos = c_code.index('rb_define_class("ValidationError"')
    assert app_pos < val_pos, "AppError should be defined before ValidationError"
  end

  def test_regular_class_still_uses_rb_cObject
    source = <<~RUBY
      class SimpleClass
        def hello
          "hello"
        end
      end
    RUBY

    c_code = get_init_c_code(source, "simple_class")
    assert_includes c_code, 'rb_define_class("SimpleClass", rb_cObject)'
  end
end
