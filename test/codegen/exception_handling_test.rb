# frozen_string_literal: true

require "test_helper"

class ExceptionHandlingTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
  end

  def build_hir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    @hir_builder.build(typed_ast)
  end

  def compile_to_ir(source)
    hir = build_hir(source)
    gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test")
    gen.generate(hir)
    gen.to_ir
  end

  def test_basic_begin_rescue
    source = <<~RUBY
      def test_rescue
        begin
          risky_operation
        rescue
          "rescued"
        end
      end
    RUBY
    ir = compile_to_ir(source)
    # Should use rb_rescue2
    assert_includes ir, "rb_rescue2"
  end

  def test_rescue_with_exception_class
    source = <<~RUBY
      def test_rescue
        begin
          risky
        rescue StandardError
          "caught"
        end
      end
    RUBY
    ir = compile_to_ir(source)
    assert_includes ir, "rb_eStandardError"
  end

  def test_multiple_rescue_clauses_generates_matching
    source = <<~RUBY
      def test_rescue
        begin
          risky
        rescue TypeError
          "type error"
        rescue ArgumentError
          "argument error"
        end
      end
    RUBY
    ir = compile_to_ir(source)
    # Should generate matching logic with rb_obj_is_kind_of
    assert_includes ir, "rb_obj_is_kind_of"
    assert_includes ir, "rescue_check"
    assert_includes ir, "rescue_body"
  end

  def test_rescue_with_exception_variable
    source = <<~RUBY
      def test_rescue
        begin
          risky
        rescue StandardError => e
          e
        end
      end
    RUBY
    ir = compile_to_ir(source)
    # Should capture exception value
    assert_includes ir, "rescue_handler"
  end

  def test_begin_ensure
    source = <<~RUBY
      def test_ensure
        begin
          work
        ensure
          cleanup
        end
      end
    RUBY
    hir = build_hir(source)
    # HIR should have ensure blocks
    main = hir.functions.find { |f| f.name == "test_ensure" }
    refute_nil main
  end

  def test_begin_rescue_ensure
    source = <<~RUBY
      def full_test
        begin
          risky
        rescue StandardError
          handle_error
        ensure
          cleanup
        end
      end
    RUBY
    ir = compile_to_ir(source)
    assert_includes ir, "rb_rescue2"
  end

  def test_hir_rescue_clause_structure
    source = <<~RUBY
      def test_rescue
        begin
          risky
        rescue TypeError => e
          handle_type_error(e)
        rescue ArgumentError
          handle_arg_error
        end
      end
    RUBY
    hir = build_hir(source)
    func = hir.functions.find { |f| f.name == "test_rescue" }
    refute_nil func

    # Find BeginRescue instruction
    begin_rescue = nil
    func.body.each do |block|
      block.instructions.each do |inst|
        begin_rescue = inst if inst.is_a?(Konpeito::HIR::BeginRescue)
      end
    end

    refute_nil begin_rescue
    assert_equal 2, begin_rescue.rescue_clauses.size

    # First clause: TypeError => e
    first_clause = begin_rescue.rescue_clauses[0]
    assert_includes first_clause.exception_classes, "TypeError"
    assert_equal "e", first_clause.exception_var

    # Second clause: ArgumentError (no variable)
    second_clause = begin_rescue.rescue_clauses[1]
    assert_includes second_clause.exception_classes, "ArgumentError"
    assert_nil second_clause.exception_var
  end

  def test_nested_begin_rescue
    source = <<~RUBY
      def nested_test
        begin
          begin
            inner_risky
          rescue TypeError
            "inner caught"
          end
        rescue StandardError
          "outer caught"
        end
      end
    RUBY
    ir = compile_to_ir(source)
    # Should have multiple rescue handlers
    assert_match(/rescue_handler_\d/, ir)
  end
end
