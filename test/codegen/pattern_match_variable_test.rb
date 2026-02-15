# frozen_string_literal: true

require "test_helper"
require "fileutils"

class PatternMatchVariableTest < Minitest::Test
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

  # Test: Simple variable return (should work)
  def test_variable_simple_return
    source = <<~RUBY
      def match_var_simple(x)
        case x
        in n then n
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_var_simple")

    require output
    assert_equal 42, match_var_simple(42)
    assert_equal "hello", match_var_simple("hello")
  end

  # Test: Variable with computation (the problematic case)
  def test_variable_with_computation
    source = <<~RUBY
      def match_var_compute(x)
        case x
        in n then n * 2
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_var_compute")

    require output
    # This is the problematic case - may segfault
    assert_equal 84, match_var_compute(42)
  end

  # Test: Variable with addition
  def test_variable_with_addition
    source = <<~RUBY
      def match_var_add(x)
        case x
        in n then n + 10
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_var_add")

    require output
    assert_equal 52, match_var_add(42)
  end
end
