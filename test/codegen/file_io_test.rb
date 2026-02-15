# frozen_string_literal: true

require "test_helper"
require "fileutils"

class FileIOTest < Minitest::Test
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

  def test_file_write_and_read
    compile_and_load(<<~RUBY, "file_wr")
      def kp_file_write(path, content)
        File.write(path, content)
      end

      def kp_file_read(path)
        File.read(path)
      end
    RUBY

    tmpfile = File.join(@output_dir, "test_file.txt")
    kp_file_write(tmpfile, "hello from konpeito")
    assert_equal "hello from konpeito", kp_file_read(tmpfile)
  end

  def test_file_exist
    compile_and_load(<<~RUBY, "file_exist")
      def kp_file_exist(path)
        File.exist?(path)
      end
    RUBY

    tmpfile = File.join(@output_dir, "exist_test.txt")
    assert_equal false, kp_file_exist(tmpfile)
    File.write(tmpfile, "test")
    assert_equal true, kp_file_exist(tmpfile)
  end

  def test_file_delete
    compile_and_load(<<~RUBY, "file_del")
      def kp_file_delete(path)
        File.delete(path)
      end
    RUBY

    tmpfile = File.join(@output_dir, "delete_test.txt")
    File.write(tmpfile, "test")
    assert File.exist?(tmpfile)
    kp_file_delete(tmpfile)
    refute File.exist?(tmpfile)
  end

  def test_file_basename
    compile_and_load(<<~RUBY, "file_base")
      def kp_basename(path)
        File.basename(path)
      end
    RUBY

    assert_equal "test.rb", kp_basename("/foo/bar/test.rb")
  end

  def test_dir_exist
    compile_and_load(<<~RUBY, "dir_ops")
      def kp_dir_exist(path)
        Dir.exist?(path)
      end
    RUBY

    assert_equal true, kp_dir_exist(@output_dir)
    assert_equal false, kp_dir_exist(File.join(@output_dir, "nonexistent"))
  end
end
