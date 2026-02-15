# frozen_string_literal: true

require "test_helper"
require "fileutils"

class CompoundAssignmentTest < Minitest::Test
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

  # ========================================
  # += -= *= operator write
  # ========================================

  def test_plus_eq
    source = <<~RUBY
      def ca_plus_eq
        x = 10
        x += 5
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_plus_eq")
    require output
    assert_equal 15, ca_plus_eq
  end

  def test_minus_eq
    source = <<~RUBY
      def ca_minus_eq
        x = 10
        x -= 3
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_minus_eq")
    require output
    assert_equal 7, ca_minus_eq
  end

  def test_multiply_eq
    source = <<~RUBY
      def ca_multiply_eq
        x = 5
        x *= 3
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_multiply_eq")
    require output
    assert_equal 15, ca_multiply_eq
  end

  def test_plus_eq_in_loop
    source = <<~RUBY
      def ca_sum_to_n(n)
        total = 0
        i = 1
        while i <= n
          total += i
          i += 1
        end
        total
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_loop")
    require output
    assert_equal 55, ca_sum_to_n(10)
  end

  def test_string_concat_eq
    source = <<~RUBY
      def ca_string_concat
        s = "hello"
        s += " world"
        s
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_str_concat")
    require output
    assert_equal "hello world", ca_string_concat
  end

  # ========================================
  # ||= or-write
  # ========================================

  def test_or_eq_nil
    source = <<~RUBY
      def ca_or_eq_nil
        x = nil
        x ||= 42
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_or_nil")
    require output
    assert_equal 42, ca_or_eq_nil
  end

  def test_or_eq_no_overwrite
    source = <<~RUBY
      def ca_or_eq_keep
        x = 1
        x ||= 42
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_or_keep")
    require output
    assert_equal 1, ca_or_eq_keep
  end

  def test_or_eq_false
    source = <<~RUBY
      def ca_or_eq_false
        x = false
        x ||= "default"
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_or_false")
    require output
    assert_equal "default", ca_or_eq_false
  end

  # ========================================
  # &&= and-write
  # ========================================

  def test_and_eq_truthy
    source = <<~RUBY
      def ca_and_eq_truthy
        x = 1
        x &&= 42
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_and_truthy")
    require output
    assert_equal 42, ca_and_eq_truthy
  end

  def test_and_eq_falsy
    source = <<~RUBY
      def ca_and_eq_falsy(x)
        x &&= 42
        x
      end
    RUBY
    output = compile_to_bundle(source, "test_ca_and_falsy")
    require output
    assert_equal 42, ca_and_eq_falsy(1)
    assert_equal 42, ca_and_eq_falsy("hello")
  end

  # ========================================
  # Instance variable compound assignment
  # ========================================

  def test_ivar_plus_eq
    source = <<~RUBY
      class CounterCompound
        def initialize
          @count = 0
        end

        def increment
          @count += 1
          @count
        end
      end

      def ca_counter_test
        c = CounterCompound.new
        c.increment
        c.increment
        c.increment
      end
    RUBY
    output = compile_to_bundle(source, "test_ivar_ca")
    require output
    assert_equal 3, ca_counter_test
  end
end
