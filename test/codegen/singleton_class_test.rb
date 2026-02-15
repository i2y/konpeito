# frozen_string_literal: true

require "test_helper"
require "fileutils"

class SingletonClassTest < Minitest::Test
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

  def test_singleton_class_method
    source = <<~RUBY
      class ScFoo
        class << self
          def bar
            42
          end
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_sc_method")
    require output
    assert_equal 42, ScFoo.bar
  end

  def test_singleton_class_method_with_params
    source = <<~RUBY
      class ScCalc
        class << self
          def add(a, b)
            a + b
          end
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_sc_params")
    require output
    assert_equal 7, ScCalc.add(3, 4)
  end

  def test_singleton_class_multiple_methods
    source = <<~RUBY
      class ScMulti
        class << self
          def greet
            "hello"
          end

          def farewell
            "goodbye"
          end
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_sc_multi")
    require output
    assert_equal "hello", ScMulti.greet
    assert_equal "goodbye", ScMulti.farewell
  end

  def test_singleton_class_mixed_with_instance_methods
    source = <<~RUBY
      class ScMixed
        def instance_val
          10
        end

        class << self
          def class_val
            20
          end
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_sc_mixed")
    require output
    assert_equal 20, ScMixed.class_val
    assert_equal 10, ScMixed.new.instance_val
  end
end
