# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/konpeito/type_checker/rbs_loader"
require_relative "../../lib/konpeito/type_checker/types"

class SIMDClassTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def test_simd_class_annotation_parsing
    rbs = <<~RBS
      %a{simd}      class Vector4
        @x: Float
        @y: Float
        @z: Float
        @w: Float

        def self.new: () -> Vector4
        def add: (Vector4 other) -> Vector4
        def dot: (Vector4 other) -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "vector.rbs")
    File.write(rbs_path, rbs)

    @loader.load(rbs_paths: [rbs_path])

    assert @loader.simd_class?(:Vector4)
    simd_type = @loader.simd_class_type(:Vector4)
    assert_instance_of Konpeito::TypeChecker::Types::SIMDClassType, simd_type
    assert_equal :Vector4, simd_type.name
    assert_equal [:x, :y, :z, :w], simd_type.field_names
    assert_equal 4, simd_type.vector_width
  end

  def test_simd_class_field_index
    rbs = <<~RBS
      %a{simd}      class Vector3
        @x: Float
        @y: Float
        @z: Float

        def self.new: () -> Vector3
      end
    RBS

    rbs_path = File.join(@tmp_dir, "vector3.rbs")
    File.write(rbs_path, rbs)

    @loader.load(rbs_paths: [rbs_path])

    simd_type = @loader.simd_class_type(:Vector3)
    assert_equal 0, simd_type.field_index(:x)
    assert_equal 1, simd_type.field_index(:y)
    assert_equal 2, simd_type.field_index(:z)
    assert_nil simd_type.field_index(:w)
  end

  def test_simd_class_llvm_vector_width
    # Vector2 -> 2
    # Vector3 -> 4 (padded)
    # Vector4 -> 4
    # Vector8 -> 8

    rbs2 = <<~RBS
      %a{simd}      class Vec2
        @x: Float
        @y: Float
        def self.new: () -> Vec2
      end
    RBS

    rbs3 = <<~RBS
      %a{simd}      class Vec3
        @x: Float
        @y: Float
        @z: Float
        def self.new: () -> Vec3
      end
    RBS

    rbs4 = <<~RBS
      %a{simd}      class Vec4
        @x: Float
        @y: Float
        @z: Float
        @w: Float
        def self.new: () -> Vec4
      end
    RBS

    paths = []
    [rbs2, rbs3, rbs4].each_with_index do |rbs, i|
      path = File.join(@tmp_dir, "vec#{i}.rbs")
      File.write(path, rbs)
      paths << path
    end

    @loader.load(rbs_paths: paths)

    assert_equal 2, @loader.simd_class_type(:Vec2).llvm_vector_width
    assert_equal 4, @loader.simd_class_type(:Vec3).llvm_vector_width  # Padded to 4
    assert_equal 4, @loader.simd_class_type(:Vec4).llvm_vector_width
  end

  def test_simd_class_methods
    rbs = <<~RBS
      %a{simd}      class Vector4
        @x: Float
        @y: Float
        @z: Float
        @w: Float

        def self.new: () -> Vector4
        def add: (Vector4 other) -> Vector4
        def dot: (Vector4 other) -> Float
        def scale: (Float s) -> Vector4
      end
    RBS

    rbs_path = File.join(@tmp_dir, "vector.rbs")
    File.write(rbs_path, rbs)

    @loader.load(rbs_paths: [rbs_path])

    simd_type = @loader.simd_class_type(:Vector4)

    add_method = simd_type.lookup_method(:add)
    assert add_method
    assert_equal [:Self], add_method.param_types
    assert_equal :Self, add_method.return_type

    dot_method = simd_type.lookup_method(:dot)
    assert dot_method
    assert_equal [:Self], dot_method.param_types
    assert_equal :Float64, dot_method.return_type

    scale_method = simd_type.lookup_method(:scale)
    assert scale_method
    assert_equal [:Float64], scale_method.param_types
    assert_equal :Self, scale_method.return_type
  end

  def test_simd_class_rejects_non_float_fields
    rbs = <<~RBS
      %a{simd}      class InvalidSIMD
        @x: Float
        @y: Integer
        @z: Float
        @w: Float
        def self.new: () -> InvalidSIMD
      end
    RBS

    rbs_path = File.join(@tmp_dir, "invalid.rbs")
    File.write(rbs_path, rbs)

    out, err = capture_io do
      @loader.load(rbs_paths: [rbs_path])
    end

    # Should warn about non-Float field (warn outputs to stderr)
    combined = out + err
    assert_includes combined, "must be Float"
  end

  def test_simd_class_rejects_invalid_field_count
    rbs = <<~RBS
      %a{simd}      class InvalidSIMD
        @a: Float
        @b: Float
        @c: Float
        @d: Float
        @e: Float
        def self.new: () -> InvalidSIMD
      end
    RBS

    rbs_path = File.join(@tmp_dir, "invalid.rbs")
    File.write(rbs_path, rbs)

    out, err = capture_io do
      @loader.load(rbs_paths: [rbs_path])
    end

    # 5 fields is not a valid SIMD width (warn outputs to stderr)
    combined = out + err
    assert_includes combined, "must have"
  end

  def test_simd_class_type_field_check
    simd_type = Konpeito::TypeChecker::Types::SIMDClassType.new(
      :Vector4,
      [:x, :y, :z, :w]
    )

    assert simd_type.field?(:x)
    assert simd_type.field?(:y)
    assert simd_type.field?(:z)
    assert simd_type.field?(:w)
    refute simd_type.field?(:unknown)
  end

  def test_simd_class_type_string_representation
    simd_type = Konpeito::TypeChecker::Types::SIMDClassType.new(
      :Vector4,
      [:x, :y, :z, :w]
    )

    assert_equal "SIMDClass[Vector4]<4 x double>", simd_type.to_s
  end

  def test_simd_class_type_allowed_widths
    # Valid widths: 2, 3, 4, 8, 16
    assert_equal [2, 3, 4, 8, 16], Konpeito::TypeChecker::Types::SIMDClassType::ALLOWED_WIDTHS
  end
end
