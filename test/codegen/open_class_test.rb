# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class OpenClassTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("open_class_test")
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

  def test_reopen_ruby_core_class_generates_const_get
    source = <<~RUBY
      class String
        def kp_custom_method
          42
        end
      end
    RUBY

    c_code = get_init_c_code(source, "open_string")
    assert_includes c_code, 'rb_const_get(rb_cObject, rb_intern("String"))'
    refute_includes c_code, 'rb_define_class("String"'
  end

  def test_reopen_ruby_core_class_runtime
    source = <<~RUBY
      class String
        def kp_shout
          self + "!"
        end
      end
    RUBY

    compile_and_load(source, "open_str_rt")
    assert_equal "hello!", "hello".kp_shout
  end

  def test_reopen_user_class_merges_methods
    source = <<~RUBY
      class OpenUserClass
        def first_method
          1
        end
      end

      class OpenUserClass
        def second_method
          2
        end
      end
    RUBY

    c_code = get_init_c_code(source, "open_user")
    # Should only define the class once
    assert_equal 1, c_code.scan('rb_define_class("OpenUserClass"').count
    # Both methods should be registered
    assert_includes c_code, '"first_method"'
    assert_includes c_code, '"second_method"'
  end

  def test_reopen_user_class_runtime
    source = <<~RUBY
      class OpenUserRuntime
        def method_a
          10
        end
      end

      class OpenUserRuntime
        def method_b
          20
        end
      end
    RUBY

    compile_and_load(source, "open_user_rt")
    obj = OpenUserRuntime.new
    assert_equal 10, obj.method_a
    assert_equal 20, obj.method_b
  end
end
