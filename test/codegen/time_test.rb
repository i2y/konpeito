# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class TimeTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("time_test")
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

  def test_time_now
    compile_and_load(<<~RUBY, "time_now")
      def kp_time_now
        Time.now
      end
    RUBY

    result = kp_time_now
    assert_kind_of Time, result
  end

  def test_time_to_i
    compile_and_load(<<~RUBY, "time_to_i")
      def kp_time_to_i
        Time.now.to_i
      end
    RUBY

    result = kp_time_to_i
    assert_kind_of Integer, result
    assert result > 0
  end

  def test_time_to_f
    compile_and_load(<<~RUBY, "time_to_f")
      def kp_time_to_f
        Time.now.to_f
      end
    RUBY

    result = kp_time_to_f
    assert_kind_of Float, result
    assert result > 0.0
  end
end
