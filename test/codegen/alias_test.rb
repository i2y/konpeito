# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class AliasTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("alias_test")
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

  def test_alias_keyword_generates_rb_define_alias
    source = <<~RUBY
      class AliasKeyword
        def original
          42
        end

        alias aliased original
      end
    RUBY

    c_code = get_init_c_code(source, "alias_kw")
    assert_includes c_code, 'rb_define_alias(cAliasKeyword, "aliased", "original")'
  end

  def test_alias_method_call_generates_rb_define_alias
    source = <<~RUBY
      class AliasMethodCall
        def original
          99
        end

        alias_method :aliased, :original
      end
    RUBY

    c_code = get_init_c_code(source, "alias_mc")
    assert_includes c_code, 'rb_define_alias(cAliasMethodCall, "aliased", "original")'
  end

  def test_alias_runtime_behavior
    source = <<~RUBY
      class AliasRuntime
        def original
          42
        end

        alias aliased original
      end
    RUBY

    compile_and_load(source, "alias_rt")

    obj = AliasRuntime.new
    assert_equal 42, obj.original
    assert_equal 42, obj.aliased
  end
end
