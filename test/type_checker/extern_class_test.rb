# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/konpeito/type_checker/rbs_loader"
require_relative "../../lib/konpeito/type_checker/types"

class ExternClassTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def test_extern_class_annotation_parsing
    rbs = <<~RBS
      %a{ffi: "libsqlite3"}
      %a{extern}
      class SQLiteDB
        def self.open: (String path) -> SQLiteDB
        def execute: (String sql) -> Array
        def close: () -> void
      end
    RBS

    rbs_path = File.join(@tmp_dir, "sqlite.rbs")
    File.write(rbs_path, rbs)

    @loader.load(rbs_paths: [rbs_path])

    assert @loader.extern_class?(:SQLiteDB)
    extern_type = @loader.extern_class_type(:SQLiteDB)
    assert_instance_of Konpeito::TypeChecker::Types::ExternClassType, extern_type
    assert_equal "libsqlite3", extern_type.ffi_library
    assert_equal :SQLiteDB, extern_type.name
  end

  def test_extern_class_constructor_method
    rbs = <<~RBS
      %a{ffi: "libtest"}
      %a{extern}
      class TestLib
        def self.create: (Integer size) -> TestLib
      end
    RBS

    rbs_path = File.join(@tmp_dir, "test.rbs")
    File.write(rbs_path, rbs)

    @loader.load(rbs_paths: [rbs_path])

    extern_type = @loader.extern_class_type(:TestLib)
    method_sig = extern_type.lookup_method(:create)

    assert method_sig
    assert method_sig.is_constructor
    assert_equal "create", method_sig.c_func_name
    assert_equal [:Integer], method_sig.param_types
    assert_equal :ptr, method_sig.return_type
  end

  def test_extern_class_instance_method
    rbs = <<~RBS
      %a{ffi: "libtest"}
      %a{extern}
      class TestLib
        def self.create: () -> TestLib
        def process: (Float value) -> Float
        def destroy: () -> void
      end
    RBS

    rbs_path = File.join(@tmp_dir, "test.rbs")
    File.write(rbs_path, rbs)

    @loader.load(rbs_paths: [rbs_path])

    extern_type = @loader.extern_class_type(:TestLib)

    process_sig = extern_type.lookup_method(:process)
    assert process_sig
    refute process_sig.is_constructor
    # Instance methods have opaque pointer as first param
    assert_equal [:ptr, :Float], process_sig.param_types
    assert_equal :Float, process_sig.return_type

    destroy_sig = extern_type.lookup_method(:destroy)
    assert destroy_sig
    assert_equal :void, destroy_sig.return_type
  end

  def test_extern_class_requires_ffi_annotation
    rbs = <<~RBS
      %a{extern}
      class InvalidExtern
        def self.create: () -> InvalidExtern
      end
    RBS

    rbs_path = File.join(@tmp_dir, "invalid.rbs")
    File.write(rbs_path, rbs)

    # Should warn and skip the class
    out, err = capture_io do
      @loader.load(rbs_paths: [rbs_path])
    end

    refute @loader.extern_class?(:InvalidExtern)
    # Warning message goes to stderr or stdout
    combined_output = out + err
    assert_includes combined_output, "%a{ffi}"
  end

  def test_extern_class_ffi_library_in_all_ffi_libraries
    rbs = <<~RBS
      %a{ffi: "libcustom"}
      %a{extern}
      class CustomLib
        def self.init: () -> CustomLib
      end
    RBS

    rbs_path = File.join(@tmp_dir, "custom.rbs")
    File.write(rbs_path, rbs)

    @loader.load(rbs_paths: [rbs_path])

    assert_includes @loader.all_ffi_libraries, "libcustom"
  end

  def test_extern_method_type_class
    method_type = Konpeito::TypeChecker::Types::ExternMethodType.new(
      "test_func",
      [:Float, :Integer],
      :Float,
      is_constructor: false
    )

    assert_equal "test_func", method_type.c_func_name
    assert_equal [:Float, :Integer], method_type.param_types
    assert_equal :Float, method_type.return_type
    refute method_type.is_constructor
  end

  def test_extern_method_type_constructor
    method_type = Konpeito::TypeChecker::Types::ExternMethodType.new(
      "create",
      [:String],
      :ptr,
      is_constructor: true
    )

    assert method_type.is_constructor
    assert_equal :ptr, method_type.return_type
  end
end
