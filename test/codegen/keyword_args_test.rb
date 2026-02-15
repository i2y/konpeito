# frozen_string_literal: true

require "test_helper"

class KeywordArgsTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test")
  end

  def compile_to_ir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)
    @llvm_gen.generate(hir)
    @llvm_gen.to_ir
  end

  def compile_to_hir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    @hir_builder.build(typed_ast)
  end

  # Test that keyword parameters are parsed correctly in HIR
  def test_keyword_param_in_hir
    hir = compile_to_hir(<<~RUBY)
      def greet(name:, count: 1)
        name * count
      end
    RUBY

    func = hir.functions.find { |f| f.name == "greet" }
    assert func, "Should have greet function"

    # Check keyword parameters
    keyword_params = func.params.select(&:keyword)
    assert_equal 2, keyword_params.size

    name_param = keyword_params.find { |p| p.name == "name" }
    count_param = keyword_params.find { |p| p.name == "count" }

    assert name_param, "Should have name keyword param"
    assert count_param, "Should have count keyword param"
    assert count_param.default_value, "count should have default value"
  end

  # Test that keyword arguments in calls are detected in HIR
  def test_keyword_args_in_call_hir
    hir = compile_to_hir(<<~RUBY)
      def greet(name:, count: 1)
        name
      end

      def test
        greet(name: "hello", count: 3)
      end
    RUBY

    test_func = hir.functions.find { |f| f.name == "test" }
    assert test_func, "Should have test function"

    # Find the call instruction
    call_inst = nil
    test_func.body.each do |block|
      block.instructions.each do |inst|
        if inst.is_a?(Konpeito::HIR::Call) && inst.method_name == "greet"
          call_inst = inst
          break
        end
      end
    end

    assert call_inst, "Should have call to greet"
    assert call_inst.has_keyword_args?, "Call should have keyword arguments"
    assert call_inst.keyword_args[:name], "Should have name keyword arg"
    assert call_inst.keyword_args[:count], "Should have count keyword arg"
  end

  # Test that LLVM IR is generated for function with keyword params
  def test_keyword_param_function_declaration
    ir = compile_to_ir(<<~RUBY)
      def greet(name:, count: 1)
        name
      end
    RUBY

    # Function should be declared - with self + kwargs_hash = 2 params
    assert_includes ir, "define i64 @rn_greet(i64 %"
  end

  # Test that rb_hash_lookup2 is used for keyword extraction
  def test_keyword_extraction_uses_rb_hash_lookup2
    ir = compile_to_ir(<<~RUBY)
      def greet(name:)
        name
      end
    RUBY

    assert_includes ir, "rb_hash_lookup2"
  end

  # Test mixed regular and keyword params
  def test_mixed_params
    hir = compile_to_hir(<<~RUBY)
      def process(x, y, name:, value: 0)
        x + y
      end
    RUBY

    func = hir.functions.find { |f| f.name == "process" }
    assert func, "Should have process function"

    regular_params = func.params.reject(&:keyword)
    keyword_params = func.params.select(&:keyword)

    assert_equal 2, regular_params.size, "Should have 2 regular params"
    assert_equal 2, keyword_params.size, "Should have 2 keyword params"
  end

  # Test that required keyword arguments have validation code
  def test_required_keyword_validation_in_ir
    ir = compile_to_ir(<<~RUBY)
      def greet(name:)
        name
      end
    RUBY

    # Should have icmp comparison for Qundef check
    assert_includes ir, "icmp eq", "Should have equality check for Qundef"

    # Should reference rb_eArgumentError
    assert_includes ir, "rb_eArgumentError", "Should reference ArgumentError exception class"

    # Should have error message for missing keyword
    assert_includes ir, "missing keyword: name", "Should have error message with keyword name"

    # Should have basic blocks for error handling
    assert_includes ir, "kwarg_missing_name", "Should have error block for missing keyword"
    assert_includes ir, "kwarg_ok_name", "Should have continue block for valid keyword"

    # Should have unreachable after rb_raise (rb_raise never returns)
    assert_includes ir, "unreachable", "Should have unreachable after rb_raise"
  end

  # Test that optional keywords do NOT generate validation code
  def test_optional_keyword_no_validation
    ir = compile_to_ir(<<~RUBY)
      def greet(name: "default")
        name
      end
    RUBY

    # Optional keywords should NOT have the missing keyword error path
    refute_includes ir, "missing keyword:", "Optional keyword should not have validation error message"
    refute_includes ir, "kwarg_missing_", "Optional keyword should not have error block"
  end

  # Test multiple required keywords all get validation
  def test_multiple_required_keywords_validation
    ir = compile_to_ir(<<~RUBY)
      def process(first:, second:)
        first + second
      end
    RUBY

    # Both required keywords should have validation
    assert_includes ir, "missing keyword: first", "Should validate first keyword"
    assert_includes ir, "missing keyword: second", "Should validate second keyword"
    assert_includes ir, "kwarg_missing_first", "Should have error block for first"
    assert_includes ir, "kwarg_missing_second", "Should have error block for second"
  end
end
