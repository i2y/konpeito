# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tempfile"

class StdlibRequireTest < Minitest::Test
  def setup
    @output_dir = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(@output_dir)
  end

  def teardown
    FileUtils.rm_rf(@output_dir)
  end

  # Test stdlib detection in DependencyResolver
  def test_detects_json_stdlib
    source_file = create_temp_file("require_json.rb", <<~RUBY)
      require "json"
      def parse_it(str)
        JSON.parse(str)
      end
    RUBY

    resolver = Konpeito::DependencyResolver.new(verbose: false)
    _ast, _rbs_paths, stdlib_requires = resolver.resolve(source_file)

    assert_includes stdlib_requires, "json"
  end

  def test_detects_multiple_stdlib
    source_file = create_temp_file("require_multi.rb", <<~RUBY)
      require "json"
      require "fileutils"
      require "uri"
      def test_method
        42
      end
    RUBY

    resolver = Konpeito::DependencyResolver.new(verbose: false)
    _ast, _rbs_paths, stdlib_requires = resolver.resolve(source_file)

    assert_includes stdlib_requires, "json"
    assert_includes stdlib_requires, "fileutils"
    assert_includes stdlib_requires, "uri"
  end

  def test_detects_net_http_stdlib
    source_file = create_temp_file("require_net_http.rb", <<~RUBY)
      require "net/http"
      def test_method
        42
      end
    RUBY

    resolver = Konpeito::DependencyResolver.new(verbose: false)
    _ast, _rbs_paths, stdlib_requires = resolver.resolve(source_file)

    assert_includes stdlib_requires, "net/http"
  end

  def test_raises_for_unknown_require
    source_file = create_temp_file("require_unknown.rb", <<~RUBY)
      require "nonexistent_gem_xyz"
      def test_method
        42
      end
    RUBY

    resolver = Konpeito::DependencyResolver.new(verbose: false)

    assert_raises(Konpeito::DependencyError) do
      resolver.resolve(source_file)
    end
  end

  def test_raises_for_unresolved_require_relative
    source_file = create_temp_file("require_relative_missing.rb", <<~RUBY)
      require_relative "missing_file"
      def test_method
        42
      end
    RUBY

    resolver = Konpeito::DependencyResolver.new(verbose: false)

    assert_raises(Konpeito::DependencyError) do
      resolver.resolve(source_file)
    end
  end

  # Test RBSLoader stdlib loading
  def test_rbs_loader_loads_json_types
    loader = Konpeito::TypeChecker::RBSLoader.new
    loader.load(stdlib_libraries: ["json"])

    # JSON module should be available
    assert loader.type_exists?(:JSON), "JSON module should be loaded"
  end

  def test_rbs_loader_warns_for_unknown_stdlib
    loader = Konpeito::TypeChecker::RBSLoader.new

    # Should not raise, just warn
    _stdout, stderr = capture_io do
      loader.load(stdlib_libraries: ["nonexistent_stdlib_xyz"])
    end

    assert_match(/Warning:.*nonexistent_stdlib_xyz/, stderr)
  end

  # Test CRubyBackend rb_require generation
  def test_generates_rb_require_in_init
    source = <<~RUBY
      def test_method
        42
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    loader = Konpeito::TypeChecker::RBSLoader.new.load
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    hir_builder = Konpeito::HIR::Builder.new
    typed_ast = ast_builder.build(ast)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test_stdlib")
    llvm_gen.generate(hir)

    output_file = File.join(@output_dir, "test_stdlib.bundle")
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: output_file,
      module_name: "test_stdlib",
      stdlib_requires: ["json", "fileutils"]
    )

    # Access the generated C code
    init_code = backend.send(:generate_init_c_code)

    assert_includes init_code, 'rb_require("json")'
    assert_includes init_code, 'rb_require("fileutils")'
    assert_includes init_code, "/* Load stdlib dependencies */"
  end

  def test_no_rb_require_when_no_stdlib
    source = <<~RUBY
      def test_method
        42
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    loader = Konpeito::TypeChecker::RBSLoader.new.load
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    hir_builder = Konpeito::HIR::Builder.new
    typed_ast = ast_builder.build(ast)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test_no_stdlib")
    llvm_gen.generate(hir)

    output_file = File.join(@output_dir, "test_no_stdlib.bundle")
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: output_file,
      module_name: "test_no_stdlib",
      stdlib_requires: []
    )

    init_code = backend.send(:generate_init_c_code)

    refute_includes init_code, "rb_require"
    refute_includes init_code, "Load stdlib dependencies"
  end

  # Integration test with full compilation
  def test_full_compilation_with_json_stdlib
    source_file = create_temp_file("json_integration.rb", <<~RUBY)
      require "json"

      def test_json
        42
      end
    RUBY

    output_file = File.join(@output_dir, "json_integration.bundle")

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      verbose: false
    )

    # Should compile without raising
    compiler.compile

    assert File.exist?(output_file), "Bundle should be created"

    # Check the nm output for Init function
    nm_output = `nm #{output_file} 2>/dev/null`.strip
    assert_includes nm_output, "Init_json_integration"
  end

  private

  def create_temp_file(name, content)
    path = File.join(@output_dir, name)
    File.write(path, content)
    path
  end
end
