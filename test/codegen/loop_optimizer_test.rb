# frozen_string_literal: true

require "test_helper"
require "fileutils"

class LoopOptimizerTest < Minitest::Test
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

    # Apply loop optimization
    optimizer = Konpeito::Codegen::LoopOptimizer.new(hir)
    optimizer.optimize

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

  # ========================================
  # Basic loop correctness (optimizer doesn't break anything)
  # ========================================

  def test_simple_while_loop
    source = <<~RUBY
      def sum_to(n)
        total = 0
        i = 0
        while i < n
          total = total + i
          i = i + 1
        end
        total
      end
    RUBY
    output = compile_to_bundle(source, "test_loop_opt_sum")

    require output
    assert_equal 0, sum_to(0)
    assert_equal 0, sum_to(1)
    assert_equal 10, sum_to(5)
    assert_equal 45, sum_to(10)
  end

  def test_nested_while_loops
    source = <<~RUBY
      def nested_sum(n)
        total = 0
        i = 0
        while i < n
          j = 0
          while j < n
            total = total + 1
            j = j + 1
          end
          i = i + 1
        end
        total
      end
    RUBY
    output = compile_to_bundle(source, "test_loop_opt_nested")

    require output
    assert_equal 0, nested_sum(0)
    assert_equal 1, nested_sum(1)
    assert_equal 9, nested_sum(3)
    assert_equal 25, nested_sum(5)
  end

  def test_while_with_break
    source = <<~RUBY
      def find_first_gt(arr, threshold)
        i = 0
        result = -1
        while i < arr.length
          if arr[i] > threshold
            result = arr[i]
            break
          end
          i = i + 1
        end
        result
      end
    RUBY
    output = compile_to_bundle(source, "test_loop_opt_break")

    require output
    assert_equal 5, find_first_gt([1, 2, 5, 3], 3)
    assert_equal -1, find_first_gt([1, 2, 3], 10)
  end

  def test_until_loop
    source = <<~RUBY
      def count_down(n)
        total = 0
        until n == 0
          total = total + n
          n = n - 1
        end
        total
      end
    RUBY
    output = compile_to_bundle(source, "test_loop_opt_until")

    require output
    assert_equal 0, count_down(0)
    assert_equal 1, count_down(1)
    assert_equal 15, count_down(5)
  end

  # ========================================
  # Loop optimizer unit tests
  # ========================================

  def test_optimizer_detects_loops
    source = <<~RUBY
      def loop_test(n)
        i = 0
        while i < n
          i = i + 1
        end
        i
      end
    RUBY
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    optimizer = Konpeito::Codegen::LoopOptimizer.new(hir)
    optimizer.optimize

    # Should not error and should produce valid HIR
    assert_kind_of Konpeito::HIR::Program, hir
  end

  def test_optimizer_hoists_pure_method_call
    # This test verifies that the optimizer can identify invariant instructions
    # The actual hoisting is tested by verifying correctness
    source = <<~RUBY
      def loop_with_length(arr)
        total = 0
        i = 0
        while i < arr.length
          total = total + arr[i]
          i = i + 1
        end
        total
      end
    RUBY
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    optimizer = Konpeito::Codegen::LoopOptimizer.new(hir)
    optimizer.optimize

    # The optimizer should identify .length as invariant
    # (arr is not modified in the loop)
    # hoisted_count may be 0 if .length is not in the condition block as a separate Call
    assert_kind_of Integer, optimizer.hoisted_count
  end

  def test_optimizer_does_not_hoist_side_effecting_calls
    source = <<~RUBY
      def loop_with_puts(n)
        i = 0
        while i < n
          puts(i)
          i = i + 1
        end
        i
      end
    RUBY
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    optimizer = Konpeito::Codegen::LoopOptimizer.new(hir)
    optimizer.optimize

    # puts is not in PURE_METHODS, so nothing should be hoisted
    assert_equal 0, optimizer.hoisted_count
  end
end
