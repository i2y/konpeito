# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class VisibilityTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = Dir.mktmpdir("visibility_test")
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

  def test_private_block_form_generates_correct_c
    source = <<~RUBY
      class VisPrivBlock
        def pub_method
          42
        end

        private

        def priv_method
          99
        end
      end
    RUBY

    c_code = get_init_c_code(source, "vis_priv_block")
    assert_includes c_code, 'rb_define_method(cVisPrivBlock, "pub_method"'
    assert_includes c_code, 'rb_define_private_method(cVisPrivBlock, "priv_method"'
  end

  def test_private_per_method_form_generates_correct_c
    source = <<~RUBY
      class VisPrivPerMethod
        def pub_method
          42
        end

        def secret
          99
        end

        private :secret
      end
    RUBY

    c_code = get_init_c_code(source, "vis_priv_per_method")
    assert_includes c_code, 'rb_define_method(cVisPrivPerMethod, "pub_method"'
    assert_includes c_code, 'rb_define_private_method(cVisPrivPerMethod, "secret"'
  end

  def test_protected_block_form_generates_correct_c
    source = <<~RUBY
      class VisProtBlock
        def pub_method
          42
        end

        protected

        def prot_method
          77
        end
      end
    RUBY

    c_code = get_init_c_code(source, "vis_prot_block")
    assert_includes c_code, 'rb_define_method(cVisProtBlock, "pub_method"'
    assert_includes c_code, 'rb_define_protected_method(cVisProtBlock, "prot_method"'
  end

  def test_public_resets_visibility
    source = <<~RUBY
      class VisPublicReset
        private

        def secret
          1
        end

        public

        def visible
          2
        end
      end
    RUBY

    c_code = get_init_c_code(source, "vis_pub_reset")
    assert_includes c_code, 'rb_define_private_method(cVisPublicReset, "secret"'
    assert_includes c_code, 'rb_define_method(cVisPublicReset, "visible"'
    refute_includes c_code, 'rb_define_private_method(cVisPublicReset, "visible"'
  end

  def test_private_method_runtime_behavior
    source = <<~RUBY
      class VisRuntime
        def call_helper
          helper
        end

        private

        def helper
          42
        end
      end
    RUBY

    compile_and_load(source, "vis_runtime")

    obj = VisRuntime.new
    assert_equal 42, obj.call_helper
    assert_raises(NoMethodError) { obj.helper }
  end
end
