# frozen_string_literal: true

require "test_helper"
require "fileutils"

class RangeTest < Minitest::Test
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

  def test_inclusive_range
    source = <<~RUBY
      def rng_inclusive
        r = 1..5
        r.to_a
      end
    RUBY
    output = compile_to_bundle(source, "test_rng_incl")
    require output
    assert_equal [1, 2, 3, 4, 5], rng_inclusive
  end

  def test_exclusive_range
    source = <<~RUBY
      def rng_exclusive
        r = 1...5
        r.to_a
      end
    RUBY
    output = compile_to_bundle(source, "test_rng_excl")
    require output
    assert_equal [1, 2, 3, 4], rng_exclusive
  end

  def test_range_include
    source = <<~RUBY
      def rng_include(x)
        r = 1..10
        r.include?(x)
      end
    RUBY
    output = compile_to_bundle(source, "test_rng_include")
    require output
    assert_equal true, rng_include(5)
    assert_equal false, rng_include(11)
  end

  def test_range_size
    source = <<~RUBY
      def rng_size
        r = 1..100
        r.size
      end
    RUBY
    output = compile_to_bundle(source, "test_rng_size")
    require output
    assert_equal 100, rng_size
  end
end
