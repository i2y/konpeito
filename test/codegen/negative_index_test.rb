# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class NegativeIndexTest < Minitest::Test
  def setup
    @output_dir = Dir.mktmpdir("neg_idx_test")
  end

  def teardown
    FileUtils.rm_rf(@output_dir)
  end

  def compile_and_load(ruby_source, rbs_source, name)
    rb_path = File.join(@output_dir, "#{name}.rb")
    rbs_path = File.join(@output_dir, "#{name}.rbs")
    File.write(rb_path, ruby_source)
    File.write(rbs_path, rbs_source)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)

    ast = Konpeito::Parser::PrismAdapter.parse(ruby_source)
    typed_ast = ast_builder.build(ast)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: name)
    llvm_gen.generate(hir)

    output_file = File.join(@output_dir, "#{name}.bundle")
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: output_file,
      module_name: name
    )
    backend.generate
    require output_file
  end

  def test_native_array_negative_get
    ruby_source = <<~RUBY
      def kp_neg_idx_get(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = (i + 1) * 1.0
          i = i + 1
        end
        arr[-1]
      end
    RUBY

    rbs_source = <<~RBS
      class NativeArray[T]
        def self.new: (Integer size) -> NativeArray[Float]
        def []: (Integer index) -> Float
        def []=: (Integer index, Float value) -> Float
        def length: () -> Integer
      end

      module TopLevel
        def kp_neg_idx_get: (Integer n) -> Float
      end
    RBS

    compile_and_load(ruby_source, rbs_source, "neg_idx_get")
    # arr has [1.0, 2.0, 3.0, 4.0, 5.0], arr[-1] should be 5.0
    assert_equal 5.0, kp_neg_idx_get(5)
  end

  def test_native_array_negative_set
    ruby_source = <<~RUBY
      def kp_neg_idx_set(n)
        arr = NativeArray.new(n)
        i = 0
        while i < n
          arr[i] = 0.0
          i = i + 1
        end
        arr[-1] = 99.0
        arr[n - 1]
      end
    RUBY

    rbs_source = <<~RBS
      class NativeArray[T]
        def self.new: (Integer size) -> NativeArray[Float]
        def []: (Integer index) -> Float
        def []=: (Integer index, Float value) -> Float
        def length: () -> Integer
      end

      module TopLevel
        def kp_neg_idx_set: (Integer n) -> Float
      end
    RBS

    compile_and_load(ruby_source, rbs_source, "neg_idx_set")
    assert_equal 99.0, kp_neg_idx_set(5)
  end
end
