# frozen_string_literal: true

require "test_helper"
require "konpeito/codegen/inliner"

class InlinerTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
  end

  def compile_to_hir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    @hir_builder.build(typed_ast)
  end

  # Test MAX_INLINE_INSTRUCTIONS constant
  def test_max_inline_instructions_constant
    assert_equal 10, Konpeito::Codegen::Inliner::MAX_INLINE_INSTRUCTIONS
  end

  # Test MAX_INLINE_DEPTH constant
  def test_max_inline_depth_constant
    assert_equal 3, Konpeito::Codegen::Inliner::MAX_INLINE_DEPTH
  end

  # Test small function is identified as inline candidate
  def test_small_function_is_inline_candidate
    hir = compile_to_hir(<<~RUBY)
      def add(a, b)
        a + b
      end
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    # Need to call private methods for testing
    inliner.send(:build_function_map)
    inliner.send(:build_call_graph)
    inliner.send(:identify_candidates)

    # Top-level function with simple body should be candidate
    # (note: function is top-level, so owner_class is nil)
    candidates = inliner.instance_variable_get(:@inline_candidates)
    assert candidates["add"], "Small function should be inline candidate"
  end

  # Test main function is never an inline candidate
  def test_main_function_not_inline_candidate
    hir = compile_to_hir(<<~RUBY)
      x = 42
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    inliner.send(:build_function_map)
    inliner.send(:build_call_graph)
    inliner.send(:identify_candidates)

    candidates = inliner.instance_variable_get(:@inline_candidates)
    refute candidates["__main__"], "__main__ should never be inline candidate"
  end

  # Test class method is not inline candidate
  def test_class_method_not_inline_candidate
    hir = compile_to_hir(<<~RUBY)
      class Foo
        def small_method
          42
        end
      end
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    inliner.send(:build_function_map)
    inliner.send(:build_call_graph)
    inliner.send(:identify_candidates)

    candidates = inliner.instance_variable_get(:@inline_candidates)
    # Instance methods of classes have owner_class set, so they're not candidates
    refute candidates["small_method"], "Class method should not be inline candidate"
  end

  # Test large function is not inline candidate
  def test_large_function_not_inline_candidate
    # Create a function with many instructions (more than 10)
    hir = compile_to_hir(<<~RUBY)
      def large_function(x)
        a = x + 1
        b = a + 2
        c = b + 3
        d = c + 4
        e = d + 5
        f = e + 6
        g = f + 7
        h = g + 8
        i = h + 9
        j = i + 10
        k = j + 11
        k
      end
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    inliner.send(:build_function_map)
    inliner.send(:build_call_graph)
    inliner.send(:identify_candidates)

    candidates = inliner.instance_variable_get(:@inline_candidates)
    refute candidates["large_function"], "Large function should not be inline candidate"
  end

  # Test recursive function is not inline candidate
  def test_recursive_function_not_inline_candidate
    hir = compile_to_hir(<<~RUBY)
      def factorial(n)
        if n <= 1
          1
        else
          n * factorial(n - 1)
        end
      end
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    inliner.send(:build_function_map)
    inliner.send(:build_call_graph)
    inliner.send(:identify_candidates)

    candidates = inliner.instance_variable_get(:@inline_candidates)
    refute candidates["factorial"], "Recursive function should not be inline candidate"
  end

  # Test optimize method runs without error
  def test_optimize_runs_successfully
    hir = compile_to_hir(<<~RUBY)
      def double(x)
        x * 2
      end

      def compute(y)
        double(y) + 1
      end
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    # Should not raise
    inliner.optimize

    # Check that inlined_count is tracked
    assert_kind_of Integer, inliner.inlined_count
  end

  # Test call graph is built correctly
  def test_call_graph_built_correctly
    hir = compile_to_hir(<<~RUBY)
      def a
        b
      end

      def b
        42
      end
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    inliner.send(:build_function_map)
    inliner.send(:build_call_graph)

    call_graph = inliner.instance_variable_get(:@call_graph)
    # 'a' should call 'b' (self call on implicit receiver)
    # Note: This depends on how the HIR is constructed
    assert call_graph.key?("a"), "Call graph should have entry for 'a'"
    assert call_graph.key?("b"), "Call graph should have entry for 'b'"
  end

  # Test instruction counting
  def test_instruction_counting
    hir = compile_to_hir(<<~RUBY)
      def simple
        1 + 2
      end
    RUBY

    inliner = Konpeito::Codegen::Inliner.new(hir)
    inliner.send(:build_function_map)

    func = inliner.instance_variable_get(:@functions)["simple"]
    assert func, "Should have simple function in map"

    # Count instructions in the function
    instruction_count = func.body.sum { |block| block.instructions.size }
    assert instruction_count <= Konpeito::Codegen::Inliner::MAX_INLINE_INSTRUCTIONS,
           "Simple function should have <= MAX_INLINE_INSTRUCTIONS"
  end
end
