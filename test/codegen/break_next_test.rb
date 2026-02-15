# frozen_string_literal: true

require "test_helper"
require "fileutils"

class BreakNextTest < Minitest::Test
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

  def test_break_in_while
    source = <<~RUBY
      def bn_break_while(n)
        i = 0
        while i < n
          if i == 5
            break
          end
          i += 1
        end
        i
      end
    RUBY
    output = compile_to_bundle(source, "test_bn_break")
    require output
    assert_equal 5, bn_break_while(10)
    assert_equal 3, bn_break_while(3)
  end

  def test_next_in_while
    source = <<~RUBY
      def bn_next_while(n)
        total = 0
        i = 0
        while i < n
          i += 1
          if i == 5
            next
          end
          total += i
        end
        total
      end
    RUBY
    output = compile_to_bundle(source, "test_bn_next")
    require output
    # Sum 1..10 except 5 = 55 - 5 = 50
    assert_equal 50, bn_next_while(10)
  end

  def test_break_infinite_loop
    source = <<~RUBY
      def bn_break_infinite
        i = 0
        while true
          i += 1
          if i == 10
            break
          end
        end
        i
      end
    RUBY
    output = compile_to_bundle(source, "test_bn_infinite")
    require output
    assert_equal 10, bn_break_infinite
  end

  def test_until_loop
    source = <<~RUBY
      def bn_until_loop
        i = 0
        until i == 5
          i += 1
        end
        i
      end
    RUBY
    output = compile_to_bundle(source, "test_bn_until")
    require output
    assert_equal 5, bn_until_loop
  end

  def test_until_with_break
    source = <<~RUBY
      def bn_until_break
        i = 0
        until false
          i += 1
          if i == 7
            break
          end
        end
        i
      end
    RUBY
    output = compile_to_bundle(source, "test_bn_until_brk")
    require output
    assert_equal 7, bn_until_break
  end
end
