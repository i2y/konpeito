# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "konpeito/codegen/mruby_backend"

# Tests for mruby backend infrastructure.
# These tests verify LLVM IR generation and C init code generation
# WITHOUT requiring mruby to be installed (no compilation/linking).
class MRubyBackendTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("konpeito_mruby_test")
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # Test that LLVMGenerator can be initialized with runtime: :mruby
  def test_llvm_generator_mruby_runtime
    gen = create_mruby_generator
    assert gen.send(:mruby?)
  end

  # Test that LLVMGenerator with CRuby runtime is not mruby
  def test_llvm_generator_cruby_runtime
    gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test_cruby",
      runtime: :cruby
    )
    hir = create_minimal_hir
    gen.generate(hir)
    refute gen.send(:mruby?)
  end

  # Test that mruby runtime generates konpeito_mruby_init_constants function
  def test_mruby_generates_init_constants
    gen = create_mruby_generator
    init_fn = gen.mod.functions["konpeito_mruby_init_constants"]
    assert init_fn, "Expected konpeito_mruby_init_constants function"
  end

  # Test that mruby runtime declares global variables for Qnil etc.
  def test_mruby_qnil_global
    gen = create_mruby_generator

    assert gen.mod.globals["konpeito_qnil"], "Expected konpeito_qnil global"
    assert gen.mod.globals["konpeito_qtrue"], "Expected konpeito_qtrue global"
    assert gen.mod.globals["konpeito_qfalse"], "Expected konpeito_qfalse global"
    assert gen.mod.globals["konpeito_qundef"], "Expected konpeito_qundef global"
  end

  # Test that mruby runtime declares konpeito_mrb_state global
  def test_mruby_state_global
    gen = create_mruby_generator
    mrb_state = gen.mod.globals["konpeito_mrb_state"]
    assert mrb_state, "Expected konpeito_mrb_state global"
  end

  # Test that CRuby-compatible functions are declared (same names as CRuby)
  def test_mruby_declares_cruby_compatible_functions
    gen = create_mruby_generator

    %w[rb_intern rb_funcallv rb_int2inum rb_num2long rb_float_new
       rb_str_new_cstr rb_ary_new rb_hash_new].each do |name|
      assert gen.mod.functions[name], "Expected #{name} function"
    end
  end

  # Test that MRubyBackend generates valid C init code
  def test_mruby_backend_generates_init_code
    gen = create_mruby_generator

    output_file = File.join(@test_dir, "test_hello")
    backend = Konpeito::Codegen::MRubyBackend.new(
      gen,
      output_file: output_file,
      module_name: "test_hello"
    )

    init_code = backend.send(:generate_init_c_code)
    assert_includes init_code, "#include <mruby.h>"
    assert_includes init_code, "int main("
    assert_includes init_code, "konpeito_mrb_state = mrb"
    assert_includes init_code, "konpeito_mruby_init_globals"
    assert_includes init_code, "konpeito_mruby_init_constants"
    assert_includes init_code, "mrb_close(mrb)"
    assert_includes init_code, "rn___main__"
  end

  # Test LLVM IR output contains CRuby-named function references
  def test_mruby_ir_contains_cruby_functions
    gen = create_mruby_generator
    ir = gen.to_ir

    # The LLVM IR should reference CRuby-named functions
    assert_includes ir, "rb_intern"
    assert_includes ir, "rb_funcallv"
    assert_includes ir, "rb_int2inum"
    assert_includes ir, "konpeito_mrb_state"
    assert_includes ir, "konpeito_qnil"
  end

  # Test that init code declares block stack functions
  def test_init_code_declares_block_stack
    gen = create_mruby_generator
    output_file = File.join(@test_dir, "test_block")
    backend = Konpeito::Codegen::MRubyBackend.new(
      gen,
      output_file: output_file,
      module_name: "test_block"
    )
    init_code = backend.send(:generate_init_c_code)
    assert_includes init_code, "konpeito_push_block"
    assert_includes init_code, "konpeito_pop_block"
  end

  # Test that wrapper functions capture blocks via mrb_get_args with "&"
  def test_wrapper_captures_block
    gen = create_mruby_generator_with_method

    output_file = File.join(@test_dir, "test_wrapper")
    backend = Konpeito::Codegen::MRubyBackend.new(
      gen,
      output_file: output_file,
      module_name: "test_wrapper"
    )

    init_code = backend.send(:generate_init_c_code)
    # Non-variadic wrappers should capture block
    assert_includes init_code, "konpeito_push_block(_block)"
    assert_includes init_code, "konpeito_pop_block()"
  end

  # Test that LLVM IR declares block-related CRuby functions
  def test_mruby_ir_declares_block_functions
    gen = create_mruby_generator
    ir = gen.to_ir

    assert_includes ir, "rb_yield"
    assert_includes ir, "rb_block_given_p"
    assert_includes ir, "rb_block_proc"
    assert_includes ir, "rb_block_call"
  end

  # Test that LLVM IR declares Fiber-related CRuby functions
  def test_mruby_ir_declares_fiber_functions
    gen = create_mruby_generator
    ir = gen.to_ir

    assert_includes ir, "rb_fiber_new"
    assert_includes ir, "rb_fiber_resume"
    assert_includes ir, "rb_fiber_yield"
  end

  # Test that LLVM IR declares Proc-related function
  def test_mruby_ir_declares_proc_functions
    gen = create_mruby_generator
    ir = gen.to_ir

    assert_includes ir, "rb_proc_new"
  end

  # Test that LLVM IR declares exception-related functions
  def test_mruby_ir_declares_exception_functions
    gen = create_mruby_generator
    ir = gen.to_ir

    assert_includes ir, "rb_rescue2"
    assert_includes ir, "rb_ensure"
    assert_includes ir, "rb_raise"
    assert_includes ir, "rb_errinfo"
    assert_includes ir, "rb_set_errinfo"
  end

  # Test that CRuby backend still works after changes (regression)
  def test_cruby_backend_unaffected
    gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test_cruby_regression",
      runtime: :cruby
    )
    hir = create_minimal_hir
    gen.generate(hir)

    # CRuby should have hardcoded Qnil/Qtrue/Qfalse
    ir = gen.to_ir
    assert_includes ir, "rb_intern"
    assert_includes ir, "rb_funcallv"
    # CRuby should NOT have konpeito_mrb_state
    refute_includes ir, "konpeito_mrb_state"
    refute_includes ir, "konpeito_qnil"
  end

  # Test that generate_license_file creates a license file with mruby MIT license
  def test_generate_license_file_basic
    gen = create_mruby_generator
    output_file = File.join(@test_dir, "test_app")
    backend = Konpeito::Codegen::MRubyBackend.new(
      gen,
      output_file: output_file,
      module_name: "test_app"
    )

    backend.send(:generate_license_file)

    license_path = "#{output_file}.LICENSES.txt"
    assert File.exist?(license_path), "Expected license file to be created"

    content = File.read(license_path)
    assert_includes content, "Konpeito"
    assert_includes content, "mruby"
    assert_includes content, "MIT"
    assert_includes content, "Copyright (c) mruby developers"
    assert_includes content, "Permission is hereby granted"
  end

  # Test that generate_license_file includes yyjson when JSON stdlib is used
  def test_generate_license_file_with_json
    gen = create_mruby_generator
    output_file = File.join(@test_dir, "test_json_app")
    backend = Konpeito::Codegen::MRubyBackend.new(
      gen,
      output_file: output_file,
      module_name: "test_json_app",
      extra_c_files: ["/path/to/json_native.c"]
    )

    backend.send(:generate_license_file)

    license_path = "#{output_file}.LICENSES.txt"
    content = File.read(license_path)
    assert_includes content, "yyjson"
    assert_includes content, "YaoYuan"
  end

  # Test that generate_license_file does NOT include yyjson when no JSON stdlib
  def test_generate_license_file_without_json
    gen = create_mruby_generator
    output_file = File.join(@test_dir, "test_no_json_app")
    backend = Konpeito::Codegen::MRubyBackend.new(
      gen,
      output_file: output_file,
      module_name: "test_no_json_app"
    )

    backend.send(:generate_license_file)

    license_path = "#{output_file}.LICENSES.txt"
    content = File.read(license_path)
    refute_includes content, "yyjson"
  end

  private

  def create_mruby_generator
    gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test_mruby",
      runtime: :mruby
    )
    hir = create_minimal_hir
    gen.generate(hir)
    gen
  end

  def create_minimal_hir
    main_block = Konpeito::HIR::BasicBlock.new(label: "entry")
    main_block.set_terminator(Konpeito::HIR::Return.new(
      value: Konpeito::HIR::NilLit.new(result_var: "t0")
    ))

    main_func = Konpeito::HIR::Function.new(
      name: "__main__",
      params: [Konpeito::HIR::Param.new(name: "self")],
      body: [main_block],
      return_type: nil
    )

    Konpeito::HIR::Program.new(
      functions: [main_func],
      classes: [],
      modules: []
    )
  end

  # Create a generator with a class that has a method (for wrapper generation tests)
  def create_mruby_generator_with_method
    gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test_mruby_method",
      runtime: :mruby
    )

    # Create a class with a method
    greet_block = Konpeito::HIR::BasicBlock.new(label: "entry")
    greet_block.set_terminator(Konpeito::HIR::Return.new(
      value: Konpeito::HIR::NilLit.new(result_var: "t1")
    ))

    greet_func = Konpeito::HIR::Function.new(
      name: "greet",
      params: [
        Konpeito::HIR::Param.new(name: "self"),
        Konpeito::HIR::Param.new(name: "name")
      ],
      body: [greet_block],
      return_type: nil,
      owner_class: "Greeter"
    )

    class_def = Konpeito::HIR::ClassDef.new(
      name: "Greeter",
      superclass: nil,
      method_names: ["greet"],
      included_modules: []
    )

    main_block = Konpeito::HIR::BasicBlock.new(label: "entry")
    main_block.set_terminator(Konpeito::HIR::Return.new(
      value: Konpeito::HIR::NilLit.new(result_var: "t0")
    ))

    main_func = Konpeito::HIR::Function.new(
      name: "__main__",
      params: [Konpeito::HIR::Param.new(name: "self")],
      body: [main_block],
      return_type: nil
    )

    hir = Konpeito::HIR::Program.new(
      functions: [greet_func, main_func],
      classes: [class_def],
      modules: []
    )

    gen.generate(hir)
    gen
  end
end
