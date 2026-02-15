# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class CFuncTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_cfunc_type_creation
    cfunc_type = Konpeito::TypeChecker::Types::CFuncType.new(
      "fast_sin",
      [:Float],
      :Float
    )

    assert_equal "fast_sin", cfunc_type.c_func_name
    assert_equal [:Float], cfunc_type.param_types
    assert_equal :Float, cfunc_type.return_type
  end

  def test_cfunc_type_to_string
    cfunc_type = Konpeito::TypeChecker::Types::CFuncType.new(
      "add_numbers",
      [:Integer, :Integer],
      :Integer
    )

    assert_equal "CFuncType(add_numbers: (Integer, Integer) -> Integer)", cfunc_type.to_s
  end

  def test_cfunc_type_llvm_mappings
    cfunc_type = Konpeito::TypeChecker::Types::CFuncType.new(
      "test_func",
      [:Float, :Integer],
      :Bool
    )

    assert_equal [:double, :int64], cfunc_type.llvm_param_types
    assert_equal :i1, cfunc_type.llvm_return_type
  end

  def test_rbs_loader_parses_cfunc_annotation_singleton
    rbs = <<~RBS
      class FastMath
        %a{cfunc: "fast_sin"}        def self.sin: (Float) -> Float

        %a{cfunc: "fast_cos"}        def self.cos: (Float) -> Float

        %a{cfunc: "fast_add"}        def self.add: (Float, Float) -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "fastmath.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify cfunc methods are parsed
    sin_cfunc = loader.cfunc_method(:FastMath, :sin, singleton: true)
    refute_nil sin_cfunc, "@cfunc for FastMath.sin should be parsed"
    assert_equal "fast_sin", sin_cfunc.c_func_name
    assert_equal [:Float], sin_cfunc.param_types
    assert_equal :Float, sin_cfunc.return_type

    cos_cfunc = loader.cfunc_method(:FastMath, :cos, singleton: true)
    refute_nil cos_cfunc
    assert_equal "fast_cos", cos_cfunc.c_func_name

    add_cfunc = loader.cfunc_method(:FastMath, :add, singleton: true)
    refute_nil add_cfunc
    assert_equal "fast_add", add_cfunc.c_func_name
    assert_equal [:Float, :Float], add_cfunc.param_types
  end

  def test_rbs_loader_parses_cfunc_integer_params
    rbs = <<~RBS
      class Utils
        %a{cfunc: "add_integers"}        def self.add: (Integer, Integer) -> Integer
      end
    RBS

    rbs_path = File.join(@tmp_dir, "utils.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    cfunc = loader.cfunc_method(:Utils, :add, singleton: true)
    refute_nil cfunc
    assert_equal [:Integer, :Integer], cfunc.param_types
    assert_equal :Integer, cfunc.return_type
  end

  def test_rbs_loader_cfunc_method_check
    rbs = <<~RBS
      class FastMath
        %a{cfunc: "fast_sin"}        def self.sin: (Float) -> Float

        def self.regular_method: (Integer) -> Integer
      end
    RBS

    rbs_path = File.join(@tmp_dir, "check.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    assert loader.cfunc_method?(:FastMath, :sin, singleton: true)
    refute loader.cfunc_method?(:FastMath, :regular_method, singleton: true)
    refute loader.cfunc_method?(:FastMath, :nonexistent, singleton: true)
  end

  def test_rbs_loader_parses_cfunc_in_module
    rbs = <<~RBS
      module LibM
        %a{cfunc: "sin"}        def self.sin: (Float) -> Float

        %a{cfunc: "cos"}        def self.cos: (Float) -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "libm.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    sin_cfunc = loader.cfunc_method(:LibM, :sin, singleton: true)
    refute_nil sin_cfunc, "@cfunc in module should be parsed"
    assert_equal "sin", sin_cfunc.c_func_name
    assert_equal [:Float], sin_cfunc.param_types
    assert_equal :Float, sin_cfunc.return_type
  end

  def test_rbs_loader_parses_cfunc_void_return
    rbs = <<~RBS
      class SideEffect
        %a{cfunc: "do_something"}        def self.execute: () -> void
      end
    RBS

    rbs_path = File.join(@tmp_dir, "sideeffect.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    cfunc = loader.cfunc_method(:SideEffect, :execute, singleton: true)
    refute_nil cfunc
    assert_equal "do_something", cfunc.c_func_name
    assert_equal [], cfunc.param_types
    assert_equal :void, cfunc.return_type
  end

  def test_cfunc_type_equality
    cfunc1 = Konpeito::TypeChecker::Types::CFuncType.new(
      "test_func",
      [:Float, :Integer],
      :Float
    )
    cfunc2 = Konpeito::TypeChecker::Types::CFuncType.new(
      "test_func",
      [:Float, :Integer],
      :Float
    )
    cfunc3 = Konpeito::TypeChecker::Types::CFuncType.new(
      "other_func",
      [:Float, :Integer],
      :Float
    )

    assert_equal cfunc1, cfunc2
    refute_equal cfunc1, cfunc3
  end

  # === @ffi annotation tests ===

  def test_ffi_annotation_parsing
    rbs = <<~RBS
      %a{ffi: "libm"}      module LibM
        %a{cfunc: "sin"}        def self.sin: (Float) -> Float

        %a{cfunc: "cos"}        def self.cos: (Float) -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "libm.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Check @ffi library is registered
    assert loader.ffi_library?(:LibM)
    assert_equal "libm", loader.ffi_library(:LibM)

    # Check @cfunc methods are parsed with short form
    sin_cfunc = loader.cfunc_method(:LibM, :sin, singleton: true)
    refute_nil sin_cfunc
    assert_equal "sin", sin_cfunc.c_func_name
    assert_equal [:Float], sin_cfunc.param_types
    assert_equal :Float, sin_cfunc.return_type
  end

  def test_ffi_annotation_with_class
    rbs = <<~RBS
      %a{ffi: "libcrypto"}      class OpenSSL
        %a{cfunc: "SHA256"}        def self.sha256: (String) -> String
      end
    RBS

    rbs_path = File.join(@tmp_dir, "openssl.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    assert loader.ffi_library?(:OpenSSL)
    assert_equal "libcrypto", loader.ffi_library(:OpenSSL)
  end

  def test_all_ffi_libraries
    rbs = <<~RBS
      %a{ffi: "libm"}      module LibM
        %a{cfunc}        def self.sin: (Float) -> Float
      end

      %a{ffi: "libz"}      module Zlib
        %a{cfunc: "compress"}        def self.compress: (String) -> String
      end

      # Regular module without @ffi
      module Regular
        def self.foo: () -> Integer
      end
    RBS

    rbs_path = File.join(@tmp_dir, "multi.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    libs = loader.all_ffi_libraries
    assert_includes libs, "libm"
    assert_includes libs, "libz"
    assert_equal 2, libs.size
  end

  def test_cfunc_minimal_form_uses_method_name
    rbs = <<~RBS
      %a{ffi: "libm"}      module Math
        %a{cfunc}        def self.sqrt: (Float) -> Float

        %a{cfunc}        def self.pow: (Float, Float) -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "math.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Minimal @cfunc should use method name as C function name
    sqrt_cfunc = loader.cfunc_method(:Math, :sqrt, singleton: true)
    refute_nil sqrt_cfunc
    assert_equal "sqrt", sqrt_cfunc.c_func_name
    assert_equal [:Float], sqrt_cfunc.param_types
    assert_equal :Float, sqrt_cfunc.return_type

    pow_cfunc = loader.cfunc_method(:Math, :pow, singleton: true)
    refute_nil pow_cfunc
    assert_equal "pow", pow_cfunc.c_func_name
    assert_equal [:Float, :Float], pow_cfunc.param_types
  end

  def test_module_without_ffi_annotation
    rbs = <<~RBS
      module Regular
        %a{cfunc: "custom_func"}        def self.custom: (Integer) -> Integer
      end
    RBS

    rbs_path = File.join(@tmp_dir, "regular.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # No @ffi annotation
    refute loader.ffi_library?(:Regular)
    assert_nil loader.ffi_library(:Regular)

    # But @cfunc should still work
    cfunc = loader.cfunc_method(:Regular, :custom, singleton: true)
    refute_nil cfunc
    assert_equal "custom_func", cfunc.c_func_name
  end
end
