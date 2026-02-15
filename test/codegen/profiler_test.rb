# frozen_string_literal: true

require "test_helper"
require "llvm/core"
require "konpeito/codegen/profiler"

class ProfilerTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new
    @loader.load
  end

  def test_profiler_creation
    mod = LLVM::Module.new("test_profiler")
    builder = LLVM::Builder.new

    profiler = Konpeito::Codegen::Profiler.new(mod, builder)

    assert_equal 0, profiler.num_functions
    assert_empty profiler.function_ids
  end

  def test_profiler_registers_functions
    mod = LLVM::Module.new("test_profiler")
    builder = LLVM::Builder.new

    profiler = Konpeito::Codegen::Profiler.new(mod, builder)

    id1 = profiler.register_function("foo")
    id2 = profiler.register_function("bar")
    id3 = profiler.register_function("foo")  # Duplicate

    assert_equal 0, id1
    assert_equal 1, id2
    assert_equal 0, id3  # Should return same ID for duplicate
    assert_equal 2, profiler.num_functions
  end

  def test_profiler_declares_runtime_functions
    mod = LLVM::Module.new("test_profiler")
    builder = LLVM::Builder.new

    Konpeito::Codegen::Profiler.new(mod, builder)

    # Check that runtime functions are declared
    assert mod.functions["konpeito_profile_enter"]
    assert mod.functions["konpeito_profile_exit"]
    assert mod.functions["konpeito_profile_init"]
    assert mod.functions["konpeito_profile_finalize"]
  end

  def test_profile_disabled_by_default
    source = <<~RUBY
      def add(a, b)
        a + b
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    builder = Konpeito::AST::TypedASTBuilder.new(@loader, use_hm: true)
    typed_ast = builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: @loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test",
      rbs_loader: @loader,
      profile: false
    )
    llvm_gen.generate(hir)

    ir = llvm_gen.to_ir

    # Profile functions should not be called when profiling is disabled
    refute_includes ir, "call void @konpeito_profile_enter"
    refute_includes ir, "call void @konpeito_profile_exit"
  end

  def test_profile_enabled_adds_instrumentation
    source = <<~RUBY
      def add(a, b)
        a + b
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    builder = Konpeito::AST::TypedASTBuilder.new(@loader, use_hm: true)
    typed_ast = builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: @loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test",
      rbs_loader: @loader,
      profile: true
    )
    llvm_gen.generate(hir)

    ir = llvm_gen.to_ir

    # Profile functions should be declared and called when profiling is enabled
    assert_includes ir, "declare void @konpeito_profile_enter"
    assert_includes ir, "declare void @konpeito_profile_exit"
    assert_includes ir, "call void @konpeito_profile_enter"
    assert_includes ir, "call void @konpeito_profile_exit"
  end

  def test_profiler_skips_main_function
    source = <<~RUBY
      def foo
        42
      end
      foo
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    builder = Konpeito::AST::TypedASTBuilder.new(@loader, use_hm: true)
    typed_ast = builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: @loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test",
      rbs_loader: @loader,
      profile: true
    )
    llvm_gen.generate(hir)

    # The profiler should only register "foo", not "__main__"
    assert_equal 1, llvm_gen.profiler.num_functions
    assert llvm_gen.profiler.function_ids.key?("foo")
    refute llvm_gen.profiler.function_ids.key?("__main__")
  end

  def test_profiler_tracks_class_methods
    source = <<~RUBY
      class Calculator
        def add(x, y)
          x + y
        end
      end
    RUBY

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    builder = Konpeito::AST::TypedASTBuilder.new(@loader, use_hm: true)
    typed_ast = builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: @loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test",
      rbs_loader: @loader,
      profile: true
    )
    llvm_gen.generate(hir)

    # Should track class methods with proper display name
    assert llvm_gen.profiler.function_ids.key?("Calculator#add")
  end
end
