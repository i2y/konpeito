# frozen_string_literal: true

require "test_helper"
require "fileutils"

class SuperTest < Minitest::Test
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

  def test_super_hir_generation
    source = <<~RUBY
      class Animal
        def speak
          "generic"
        end
      end

      class Dog < Animal
        def speak
          super
        end
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    # Verify SuperCall node is generated
    super_found = false
    hir.functions.each do |func|
      func.body.each do |block|
        block.instructions.each do |inst|
          if inst.is_a?(Konpeito::HIR::SuperCall)
            super_found = true
          end
        end
      end
    end
    assert super_found, "SuperCall HIR node should be generated"
  end
end
