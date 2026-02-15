# frozen_string_literal: true

require "test_helper"
require "fileutils"

class CRubyBackendTest < Minitest::Test
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

  def test_generates_bundle_file
    source = "def test_method; 42; end"
    output = compile_to_bundle(source, "test_simple")

    assert File.exist?(output), "Bundle file should be created"
    assert File.size(output) > 0, "Bundle file should not be empty"
  end

  def test_bundle_is_valid_shared_library
    source = "def another_method; 1 + 2; end"
    output = compile_to_bundle(source, "test_valid")

    # Check file type using file command
    file_output = `file #{output}`.strip

    case RbConfig::CONFIG["host_os"]
    when /darwin/
      assert_includes file_output, "Mach-O"
      assert_includes file_output, "dynamically linked shared library"
    when /linux/
      assert_includes file_output, "ELF"
      assert_includes file_output, "shared object"
    end
  end

  def test_bundle_has_init_function
    source = "def init_test; 'hello'; end"
    output = compile_to_bundle(source, "test_init")

    # Use nm to check for Init function
    nm_output = `nm #{output} 2>/dev/null`.strip

    assert_includes nm_output, "Init_test_init", "Should have Init function"
  end

  def test_bundle_can_be_loaded
    source = <<~RUBY
      def loadable_method
        100
      end
    RUBY
    output = compile_to_bundle(source, "test_loadable")

    # Try to require the bundle - it should not raise
    # Note: The methods won't be available because we haven't registered them
    # but the Init function should be callable
    assert_nothing_raised do
      require output
    end
  end

  def test_rescue_basic_compiles
    source = <<~RUBY
      def test_rescue_basic
        begin
          raise "error"
        rescue
          "caught"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_rescue_basic")
    assert File.exist?(output), "Bundle file should be created"
  end

  def test_rescue_with_exception_class_compiles
    source = <<~RUBY
      def test_rescue_typed
        begin
          raise StandardError, "bad"
        rescue StandardError => e
          e
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_rescue_typed")
    assert File.exist?(output), "Bundle file should be created"
  end

  def test_rescue_with_ensure_compiles
    source = <<~RUBY
      def test_rescue_ensure
        result = nil
        begin
          result = "try"
        rescue
          result = "rescue"
        ensure
          result = "ensure"
        end
        result
      end
    RUBY
    output = compile_to_bundle(source, "test_rescue_ensure")
    assert File.exist?(output), "Bundle file should be created"
  end

  def test_case_basic_compiles
    source = <<~RUBY
      def test_case_basic(x)
        case x
        when 1
          "one"
        when 2
          "two"
        else
          "other"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_case_basic")
    assert File.exist?(output), "Bundle file should be created"
  end

  def test_case_multiple_conditions_compiles
    source = <<~RUBY
      def test_case_multi(x)
        case x
        when 1, 2, 3
          "small"
        when 4, 5, 6
          "medium"
        else
          "large"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_case_multi")
    assert File.exist?(output), "Bundle file should be created"
  end

  def test_case_without_else_compiles
    source = <<~RUBY
      def test_case_no_else(x)
        case x
        when 1
          "one"
        when 2
          "two"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_case_no_else")
    assert File.exist?(output), "Bundle file should be created"
  end

  def test_for_loop_basic_compiles
    source = <<~RUBY
      def test_for_basic(arr)
        result = 0
        for x in arr
          result = result + x
        end
        result
      end
    RUBY
    output = compile_to_bundle(source, "test_for_basic")
    assert File.exist?(output), "Bundle file should be created"
  end

  def test_for_loop_with_range_compiles
    source = <<~RUBY
      def test_for_range
        result = 0
        for i in 1..10
          result = result + i
        end
        result
      end
    RUBY
    output = compile_to_bundle(source, "test_for_range")
    assert File.exist?(output), "Bundle file should be created"
  end

  private

  def assert_nothing_raised
    yield
  rescue => e
    flunk "Expected no exception, but got: #{e.class}: #{e.message}"
  end
end
