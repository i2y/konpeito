# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class NativeMethodTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_native_method_call_generates_direct_function_call
    # RBS with native class (native-first, no @native annotation needed)
    rbs = <<~RBS
      class Vector2
        @x: Float
        @y: Float

        def self.new: () -> Vector2
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
        def length_squared: () -> Float
      end

      class Object
        def test_vector: () -> Float
      end
    RBS

    source = <<~RUBY
      def test_vector
        v = Vector2.new
        v.x = 3.0
        v.y = 4.0
        v.length_squared
      end
    RUBY

    # Write files
    rbs_path = File.join(@tmp_dir, "vector.rbs")
    source_path = File.join(@tmp_dir, "vector.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    # Load RBS
    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Build typed AST
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    # Build HIR
    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    # Generate LLVM IR
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "native_test")
    llvm_gen.generate(hir)
    ir = llvm_gen.to_ir

    # Verify native class struct is created
    assert_includes ir, "Native_Vector2"

    # Verify the test function is generated
    assert_includes ir, "rn_test_vector"

    # Verify struct field access (GEP instructions for x and y)
    assert_includes ir, "getelementptr"
  end

  def test_native_method_with_inheritance
    rbs = <<~RBS
      %a{native}      class Vector2
        @x: Float
        @y: Float

        def self.new: () -> Vector2
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
        def length_squared: () -> Float
      end

      %a{native}      class Vector3 < Vector2
        @z: Float

        def self.new: () -> Vector3
        def z: () -> Float
        def z=: (Float value) -> Float
      end

      class Object
        def test_inheritance: () -> Float
      end
    RBS

    source = <<~RUBY
      def test_inheritance
        v = Vector3.new
        v.x = 1.0
        v.y = 2.0
        v.z = 3.0
        v.x + v.y + v.z
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "vector3.rbs")
    source_path = File.join(@tmp_dir, "vector3.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify inheritance is parsed
    vec3 = loader.native_class_type(:Vector3)
    assert_equal :Vector2, vec3.superclass
  end

  def test_rbs_loader_parses_native_methods
    rbs = <<~RBS
      %a{native}      class Point
        @x: Float
        @y: Float

        def self.new: () -> Point
        def x: () -> Float
        def y: () -> Float
        def add: (Point other) -> Point
        def distance_to: (Point other) -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "point.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    point_type = loader.native_class_type(:Point)
    refute_nil point_type, "Point should be a native class"

    # Verify fields
    assert_equal :Float64, point_type.fields[:x]
    assert_equal :Float64, point_type.fields[:y]

    # Verify methods (excluding field accessors)
    assert point_type.methods.key?(:add), "add method should be parsed"
    assert point_type.methods.key?(:distance_to), "distance_to method should be parsed"

    # Verify method signatures
    add_sig = point_type.methods[:add]
    # Note: Point -> :Self when parsing own class name as parameter type
    assert_equal [:Self], add_sig.param_types
    assert_equal :Self, add_sig.return_type

    dist_sig = point_type.methods[:distance_to]
    assert_equal [:Self], dist_sig.param_types
    assert_equal :Float64, dist_sig.return_type
  end

  def test_hir_builder_generates_native_method_call
    rbs = <<~RBS
      %a{native}      class Vector2
        @x: Float
        @y: Float

        def self.new: () -> Vector2
        def x: () -> Float
        def y: () -> Float
        def length_squared: () -> Float
      end

      class Object
        def calc: () -> Float
      end
    RBS

    source = <<~RUBY
      def calc
        v = Vector2.new
        v.length_squared
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "vec.rbs")
    source_path = File.join(@tmp_dir, "vec.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    # Find the calc function
    calc_func = hir.functions.find { |f| f.name == "calc" }
    refute_nil calc_func, "calc function should exist"

    # Find NativeMethodCall instruction
    native_method_calls = []
    calc_func.body.each do |block|
      block.instructions.each do |inst|
        native_method_calls << inst if inst.is_a?(Konpeito::HIR::NativeMethodCall)
      end
    end

    assert_equal 1, native_method_calls.size, "Should have one NativeMethodCall"
    assert_equal :length_squared, native_method_calls.first.method_name
  end

  def test_cruby_backend_generates_typeddata_for_native_class
    rbs = <<~RBS
      %a{native}      class Vector2
        @x: Float
        @y: Float

        def self.new: () -> Vector2
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
        def length_squared: () -> Float
        def add: (Vector2 other) -> Vector2
      end

      class Object
        def test_vector: () -> Float
      end
    RBS

    source = <<~RUBY
      class Vector2
        def length_squared
          @x * @x + @y * @y
        end

        def add(other)
          result = Vector2.new
          result.x = @x + other.x
          result.y = @y + other.y
          result
        end
      end

      def test_vector
        v = Vector2.new
        v.x = 3.0
        v.y = 4.0
        v.length_squared
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "vector_typed.rbs")
    source_path = File.join(@tmp_dir, "vector_typed.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "vector_typed")
    llvm_gen.generate(hir)

    # Test CRuby backend generates TypedData code
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "vector_typed.bundle"),
      module_name: "vector_typed",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify TypedData type definition is generated (with forward declaration)
    assert_includes init_c_code, "typedef struct Native_Vector2_s Native_Vector2;"
    assert_includes init_c_code, "struct Native_Vector2_s {"
    assert_includes init_c_code, "double x;"
    assert_includes init_c_code, "double y;"

    # Verify TypedData type registration
    assert_includes init_c_code, "rb_data_type_t Vector2_type"
    assert_includes init_c_code, '.wrap_struct_name = "Vector2"'

    # Verify allocator function
    assert_includes init_c_code, "Vector2_alloc(VALUE klass)"
    assert_includes init_c_code, "TypedData_Make_Struct"

    # Verify field accessor wrappers
    assert_includes init_c_code, "Vector2_get_x(VALUE self)"
    assert_includes init_c_code, "Vector2_set_x(VALUE self, VALUE val)"
    assert_includes init_c_code, "TypedData_Get_Struct"

    # Verify native method wrapper is generated
    assert_includes init_c_code, "rn_wrap_Vector2_length_squared"
    assert_includes init_c_code, "rn_wrap_Vector2_add"

    # Verify native function declaration
    assert_includes init_c_code, "extern double rn_Vector2_length_squared(Native_Vector2* self)"
    assert_includes init_c_code, "extern Native_Vector2 rn_Vector2_add(Native_Vector2* self, Native_Vector2* other)"

    # Verify Init function registers allocator and methods
    assert_includes init_c_code, "rb_define_alloc_func"
    assert_includes init_c_code, 'rb_define_method(cVector2, "x", Vector2_get_x, 0)'
    assert_includes init_c_code, 'rb_define_method(cVector2, "x=", Vector2_set_x, 1)'
    assert_includes init_c_code, 'rb_define_method(cVector2, "length_squared", rn_wrap_Vector2_length_squared, 0)'
    assert_includes init_c_code, 'rb_define_method(cVector2, "add", rn_wrap_Vector2_add, 1)'
  end

  def test_cruby_backend_handles_method_returning_self
    rbs = <<~RBS
      %a{native}      class Point
        @x: Float
        @y: Float

        def self.new: () -> Point
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
        def add: (Point other) -> Point
      end
    RBS

    rbs_path = File.join(@tmp_dir, "point.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Minimal HIR for testing backend
    hir = Konpeito::HIR::Program.new(functions: [], classes: [])

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "point_test")
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "point_test.bundle"),
      module_name: "point_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify struct return by value handling
    assert_includes init_c_code, "Native_Point result = rn_Point_add"
    assert_includes init_c_code, 'rb_const_get(rb_cObject, rb_intern("Point"))'
    assert_includes init_c_code, "Point_alloc(result_klass)"
    assert_includes init_c_code, "*result_ptr = result;"
  end

  def test_native_class_with_reference_field
    rbs = <<~RBS
      %a{native}      class Node
        @value: Integer
        @next: Node?
        @prev: Node?

        def self.new: () -> Node
        def value: () -> Integer
        def value=: (Integer v) -> Integer
        def next: () -> Node?
        def next=: (Node? n) -> Node?
        def prev: () -> Node?
        def prev=: (Node? n) -> Node?
      end
    RBS

    rbs_path = File.join(@tmp_dir, "node.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify reference field is parsed
    node_type = loader.native_class_type(:Node)
    refute_nil node_type
    assert_equal :Int64, node_type.fields[:value]
    assert_equal({ ref: :Node }, node_type.fields[:next])
    assert_equal({ ref: :Node }, node_type.fields[:prev])

    # Verify reference detection
    assert node_type.native_class_reference?(:next)
    assert node_type.native_class_reference?(:prev)
    refute node_type.native_class_reference?(:value)

    # Verify GC marking includes references
    assert node_type.has_ruby_object_fields?
    assert_includes node_type.ruby_object_field_names, :next
    assert_includes node_type.ruby_object_field_names, :prev

    # Generate C code
    hir = Konpeito::HIR::Program.new(functions: [], classes: [])
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "node_test")
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "node_test.bundle"),
      module_name: "node_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify VALUE field in struct (references, not embedded)
    assert_match(/VALUE next;/, init_c_code)
    assert_match(/VALUE prev;/, init_c_code)

    # Verify GC mark function marks reference fields
    assert_includes init_c_code, "rb_gc_mark(obj->next);"
    assert_includes init_c_code, "rb_gc_mark(obj->prev);"

    # Verify initializer sets Qnil
    assert_includes init_c_code, "ptr->next = Qnil;"
    assert_includes init_c_code, "ptr->prev = Qnil;"
  end

  def test_native_class_with_string_field
    rbs = <<~RBS
      %a{native}      class Entity
        @id: Integer
        @name: String

        def self.new: () -> Entity
        def id: () -> Integer
        def id=: (Integer value) -> Integer
        def name: () -> String
        def name=: (String value) -> String
      end
    RBS

    rbs_path = File.join(@tmp_dir, "entity.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify String field is parsed
    entity_type = loader.native_class_type(:Entity)
    refute_nil entity_type
    assert_equal :Int64, entity_type.fields[:id]
    assert_equal :String, entity_type.fields[:name]

    # Verify has_ruby_object_fields works
    assert entity_type.has_ruby_object_fields?
    assert_equal [:name], entity_type.ruby_object_field_names

    # Generate C code
    hir = Konpeito::HIR::Program.new(functions: [], classes: [])
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "entity_test")
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "entity_test.bundle"),
      module_name: "entity_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify VALUE field in struct
    assert_includes init_c_code, "VALUE name;"

    # Verify GC mark function is generated
    assert_includes init_c_code, "Entity_mark(void *ptr)"
    assert_includes init_c_code, "rb_gc_mark(obj->name);"

    # Verify TypedData uses mark function
    assert_includes init_c_code, ".dmark = Entity_mark,"

    # Verify initializer sets Qnil
    assert_includes init_c_code, "ptr->name = Qnil;"

    # Verify getter returns VALUE directly
    assert_includes init_c_code, "return ptr->name;"

    # Verify setter stores VALUE directly
    assert_includes init_c_code, "ptr->name = val;"
  end

  def test_native_class_with_embedded_native_class_field
    rbs = <<~RBS
      %a{native}      class Vector2
        @x: Float
        @y: Float

        def self.new: () -> Vector2
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
      end

      %a{native}      class Transform
        @position: Vector2
        @scale: Float

        def self.new: () -> Transform
        def position: () -> Vector2
        def position=: (Vector2 value) -> Vector2
        def scale: () -> Float
        def scale=: (Float value) -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "transform.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify embedded field is parsed
    transform_type = loader.native_class_type(:Transform)
    refute_nil transform_type
    assert_equal :Vector2, transform_type.fields[:position]
    assert_equal :Float64, transform_type.fields[:scale]

    # Verify Vector2 is recognized as embedded NativeClass
    assert transform_type.embedded_native_class?(:position, loader.native_classes)

    # Generate C code
    hir = Konpeito::HIR::Program.new(functions: [], classes: [])
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "transform_test")
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "transform_test.bundle"),
      module_name: "transform_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify Vector2 struct comes before Transform struct (dependency order)
    vec2_pos = init_c_code.index("Native_Vector2")
    transform_pos = init_c_code.index("Native_Transform")
    assert vec2_pos < transform_pos, "Vector2 should be defined before Transform"

    # Verify Transform struct has embedded Vector2
    assert_includes init_c_code, "Native_Vector2 position;"

    # Verify getter returns a copy
    assert_includes init_c_code, "*result_ptr = ptr->position;"

    # Verify setter copies the value
    assert_includes init_c_code, "ptr->position = *val_ptr;"
  end

  def test_native_class_with_bool_field
    rbs = <<~RBS
      %a{native}      class Particle
        @x: Float
        @y: Float
        @active: bool

        def self.new: () -> Particle
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
        def active: () -> bool
        def active=: (bool value) -> bool
      end
    RBS

    rbs_path = File.join(@tmp_dir, "particle.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify Bool field is parsed
    particle_type = loader.native_class_type(:Particle)
    refute_nil particle_type
    assert_equal :Float64, particle_type.fields[:x]
    assert_equal :Float64, particle_type.fields[:y]
    assert_equal :Bool, particle_type.fields[:active]

    # Minimal HIR for testing backend
    hir = Konpeito::HIR::Program.new(functions: [], classes: [])

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "particle_test")
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "particle_test.bundle"),
      module_name: "particle_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify Bool field in struct
    assert_includes init_c_code, "int8_t active;"

    # Verify Bool getter returns Qtrue/Qfalse
    assert_includes init_c_code, "ptr->active ? Qtrue : Qfalse"

    # Verify Bool setter uses RTEST
    assert_includes init_c_code, "RTEST(val) ? 1 : 0"
  end

  def test_native_class_with_inheritance_generates_proper_struct_layout
    rbs = <<~RBS
      %a{native}      class Vector2
        @x: Float
        @y: Float

        def self.new: () -> Vector2
        def x: () -> Float
        def x=: (Float value) -> Float
        def y: () -> Float
        def y=: (Float value) -> Float
      end

      %a{native}      class Vector3 < Vector2
        @z: Float

        def self.new: () -> Vector3
        def z: () -> Float
        def z=: (Float value) -> Float
        def length_squared: () -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "vectors.rbs")
    File.write(rbs_path, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Minimal HIR for testing backend
    hir = Konpeito::HIR::Program.new(functions: [], classes: [])

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "vectors_test")
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "vectors_test.bundle"),
      module_name: "vectors_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify Vector3 struct has z field (own field)
    # Parent fields are accessed through inheritance, not embedded
    assert_includes init_c_code, "typedef struct Native_Vector3_s Native_Vector3;"
    assert_includes init_c_code, "struct Native_Vector3_s {"

    # Verify Vector3 inherits from Vector2 in class definition
    assert_includes init_c_code, 'rb_define_class("Vector3", cVector2)'

    # Verify both classes have allocators registered
    assert_includes init_c_code, "rb_define_alloc_func(cVector2, Vector2_alloc)"
    assert_includes init_c_code, "rb_define_alloc_func(cVector3, Vector3_alloc)"
  end

  def test_vtable_annotation_generates_vptr_field_and_vtable
    # Test NativeClass with vtable annotation generates vtable for polymorphism
    # Note: Method names must differ from field names (fields use @, methods don't)
    # Methods with same name as a field are treated as accessors, not virtual methods
    rbs_content = <<~RBS
      %a{native: vtable}      class Shape
        @base_area: Float

        def compute_area: () -> Float
      end

      %a{native: vtable}      class Circle < Shape
        @radius: Float

        def compute_area: () -> Float
      end
    RBS

    ruby_code = <<~RUBY
      class Shape
        def compute_area
          @base_area
        end
      end

      class Circle < Shape
        def compute_area
          3.14159 * @radius * @radius
        end
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "shapes_vtable.rbs")
    File.write(rbs_path, rbs_content)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify vtable flag is set correctly
    shape_type = loader.native_class_type(:Shape)
    circle_type = loader.native_class_type(:Circle)

    assert shape_type.vtable, "Shape should have vtable enabled"
    assert circle_type.vtable, "Circle should have vtable enabled"

    # Verify uses_vtable? works correctly
    native_classes = loader.native_classes
    assert shape_type.uses_vtable?(native_classes), "Shape uses_vtable? should be true"
    assert circle_type.uses_vtable?(native_classes), "Circle uses_vtable? should be true"

    # Verify vtable_methods returns correct layout
    shape_vtable = shape_type.vtable_methods(native_classes)
    assert_equal 1, shape_vtable.size
    assert_equal :compute_area, shape_vtable[0][0]  # method name
    assert_equal :Shape, shape_vtable[0][2]  # owner class

    circle_vtable = circle_type.vtable_methods(native_classes)
    assert_equal 1, circle_vtable.size
    assert_equal :compute_area, circle_vtable[0][0]  # method name
    assert_equal :Circle, circle_vtable[0][2]  # owner (overridden)

    # Verify vtable_index
    assert_equal 0, shape_type.vtable_index(:compute_area, native_classes)
    assert_equal 0, circle_type.vtable_index(:compute_area, native_classes)

    source_path = File.join(@tmp_dir, "shapes_vtable.rb")
    File.write(source_path, ruby_code)

    ast = Konpeito::Parser::PrismAdapter.parse(ruby_code)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    generator = Konpeito::Codegen::LLVMGenerator.new(module_name: "shapes_test")
    generator.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      generator,
      output_file: "shapes_test.bundle",
      module_name: "shapes_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify vptr field in struct
    assert_includes init_c_code, "void **vptr;  /* Pointer to vtable */"

    # Verify vtable generation
    assert_includes init_c_code, "static void *vtable_Shape[]"
    assert_includes init_c_code, "static void *vtable_Circle[]"

    # Verify vtable entries point to correct functions
    assert_includes init_c_code, "(void *)rn_Shape_compute_area"
    assert_includes init_c_code, "(void *)rn_Circle_compute_area"

    # Verify vptr is initialized in allocator
    assert_includes init_c_code, "ptr->vptr = vtable_Shape;"
    assert_includes init_c_code, "ptr->vptr = vtable_Circle;"
  end

  def test_vtable_inheritance_preserves_method_order
    # Test that subclass vtable has same method order as parent for polymorphism
    rbs_content = <<~RBS
      %a{native: vtable}      class Animal
        @legs: Int64

        def speak: () -> Float
        def move: () -> Float
      end

      %a{native: vtable}      class Dog < Animal
        @name: Float

        def speak: () -> Float
        def bark: () -> Float
      end
    RBS

    rbs_path = File.join(@tmp_dir, "animals_vtable.rbs")
    File.write(rbs_path, rbs_content)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    native_classes = loader.native_classes
    animal_type = loader.native_class_type(:Animal)
    dog_type = loader.native_class_type(:Dog)

    # Animal vtable: [speak, move]
    animal_vtable = animal_type.vtable_methods(native_classes)
    assert_equal 2, animal_vtable.size
    assert_equal :speak, animal_vtable[0][0]
    assert_equal :move, animal_vtable[1][0]

    # Dog vtable: [speak(overridden), move(inherited), bark(new)]
    dog_vtable = dog_type.vtable_methods(native_classes)
    assert_equal 3, dog_vtable.size

    # First two slots MUST match Animal's vtable order for polymorphism
    assert_equal :speak, dog_vtable[0][0]
    assert_equal :Dog, dog_vtable[0][2]  # Overridden by Dog

    assert_equal :move, dog_vtable[1][0]
    assert_equal :Animal, dog_vtable[1][2]  # Inherited from Animal

    # New method at the end
    assert_equal :bark, dog_vtable[2][0]
    assert_equal :Dog, dog_vtable[2][2]

    # Verify vtable indices are consistent
    # speak is at index 0 in both
    assert_equal 0, animal_type.vtable_index(:speak, native_classes)
    assert_equal 0, dog_type.vtable_index(:speak, native_classes)

    # move is at index 1 in both
    assert_equal 1, animal_type.vtable_index(:move, native_classes)
    assert_equal 1, dog_type.vtable_index(:move, native_classes)

    # bark is only in Dog at index 2
    assert_nil animal_type.vtable_index(:bark, native_classes)
    assert_equal 2, dog_type.vtable_index(:bark, native_classes)
  end

  def test_non_vtable_class_does_not_generate_vptr
    # Test that classes without @native vtable don't have vptr
    rbs_content = <<~RBS
      %a{native}      class Point
        @x: Float
        @y: Float

        def distance: () -> Float
      end
    RBS

    ruby_code = <<~RUBY
      class Point
        def distance
          @x * @x + @y * @y
        end
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "point_no_vtable.rbs")
    File.write(rbs_path, rbs_content)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    point_type = loader.native_class_type(:Point)
    refute point_type.vtable, "Point should not have vtable"
    refute point_type.uses_vtable?(loader.native_classes), "Point uses_vtable? should be false"

    source_path = File.join(@tmp_dir, "point_no_vtable.rb")
    File.write(source_path, ruby_code)

    ast = Konpeito::Parser::PrismAdapter.parse(ruby_code)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    generator = Konpeito::Codegen::LLVMGenerator.new(module_name: "point_test")
    generator.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      generator,
      output_file: "point_test.bundle",
      module_name: "point_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify no vptr field in struct
    refute_includes init_c_code, "void **vptr"

    # Verify no vtable generation
    refute_includes init_c_code, "static void *vtable_Point"

    # But regular fields should be there
    assert_includes init_c_code, "double x;"
    assert_includes init_c_code, "double y;"
  end

  def test_native_method_with_parameters_uses_rbs_types
    # Test that native methods with parameters use RBS types not inference
    # This was causing segfault when parameter types were not propagated correctly
    rbs_content = <<~RBS
      %a{native}      class Calculator
        @result: Float

        def compute: (Float a, Float b) -> Float
        def compute_with_int: (Integer x) -> Float
      end
    RBS

    ruby_code = <<~RUBY
      class Calculator
        def compute(a, b)
          a + b
        end

        def compute_with_int(x)
          @result + x
        end
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "calculator.rbs")
    File.write(rbs_path, rbs_content)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    # Verify method signatures are loaded
    calc_type = loader.native_class_type(:Calculator)
    compute_sig = calc_type.methods[:compute]
    refute_nil compute_sig
    assert_equal [:Float64, :Float64], compute_sig.param_types
    assert_equal :Float64, compute_sig.return_type

    compute_int_sig = calc_type.methods[:compute_with_int]
    refute_nil compute_int_sig
    assert_equal [:Int64], compute_int_sig.param_types
    assert_equal :Float64, compute_int_sig.return_type

    source_path = File.join(@tmp_dir, "calculator.rb")
    File.write(source_path, ruby_code)

    ast = Konpeito::Parser::PrismAdapter.parse(ruby_code)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    # Find the compute function in HIR and verify parameter types come from RBS
    compute_func = hir.functions.find { |f| f.name == "compute" }
    refute_nil compute_func, "compute function should be in HIR"
    assert_equal 2, compute_func.params.size

    # Parameter types should be Float from RBS (which is :Float64 internally)
    # Not untyped from type inference
    assert_equal :Float, compute_func.params[0].type.name, "First param should have Float type from RBS"
    assert_equal :Float, compute_func.params[1].type.name, "Second param should have Float type from RBS"

    # Also check compute_with_int
    compute_int_func = hir.functions.find { |f| f.name == "compute_with_int" }
    refute_nil compute_int_func
    assert_equal 1, compute_int_func.params.size
    assert_equal :Integer, compute_int_func.params[0].type.name, "Param should have Integer type from RBS"

    # Generate and verify C wrapper code
    generator = Konpeito::Codegen::LLVMGenerator.new(module_name: "calculator_test")
    generator.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      generator,
      output_file: "calculator_test.bundle",
      module_name: "calculator_test",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify wrapper converts Ruby VALUEs to native types
    assert_includes init_c_code, "NUM2DBL(arg0)"  # Float conversion
    assert_includes init_c_code, "NUM2DBL(arg1)"  # Float conversion
    assert_includes init_c_code, "NUM2LONG(arg0)"  # Integer conversion for compute_with_int
  end

  # NativeClass GC Integration Tests

  def test_native_class_with_value_fields_generates_gc_mark_function
    # Test that VALUE fields (String, Array, Hash) are properly handled for GC
    rbs = <<~RBS
      class Person
        @age: Integer
        @height: Float
        @name: String
        @tags: Array

        def self.new: () -> Person
        def age: () -> Integer
        def age=: (Integer value) -> Integer
        def height: () -> Float
        def height=: (Float value) -> Float
        def name: () -> String
        def name=: (String value) -> String
        def tags: () -> Array
        def tags=: (Array value) -> Array
      end

      module TopLevel
        def test_person: () -> Integer
      end
    RBS

    source = <<~RUBY
      def test_person
        p = Person.new
        p.age = 30
        p.height = 1.75
        p.age
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "person_gc.rbs")
    source_path = File.join(@tmp_dir, "person_gc.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "person_gc")
    llvm_gen.generate(hir)
    ir = llvm_gen.to_ir

    # Verify native struct is created with correct types
    assert_includes ir, "Native_Person"

    # Test CRuby backend generates GC mark function and TypedData
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "person_gc.bundle"),
      module_name: "person_gc",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify struct has VALUE fields
    assert_includes init_c_code, "int64_t age;", "age should be int64_t"
    assert_includes init_c_code, "double height;", "height should be double"
    assert_includes init_c_code, "VALUE name;", "name should be VALUE"
    assert_includes init_c_code, "VALUE tags;", "tags should be VALUE"

    # Verify GC mark function is generated
    assert_includes init_c_code, "Person_mark", "GC mark function should be generated"
    assert_includes init_c_code, "rb_gc_mark(obj->name)", "name field should be GC marked"
    assert_includes init_c_code, "rb_gc_mark(obj->tags)", "tags field should be GC marked"

    # Verify TypedData type has dmark callback
    assert_includes init_c_code, ".dmark = Person_mark", "TypedData should have mark callback"

    # Verify VALUE fields are initialized to Qnil
    assert_includes init_c_code, "ptr->name = Qnil", "name should be initialized to Qnil"
    assert_includes init_c_code, "ptr->tags = Qnil", "tags should be initialized to Qnil"
  end

  def test_native_class_with_hash_field_generates_gc_mark
    rbs = <<~RBS
      class Config
        @timeout: Integer
        @settings: Hash

        def self.new: () -> Config
        def timeout: () -> Integer
        def timeout=: (Integer value) -> Integer
        def settings: () -> Hash
        def settings=: (Hash value) -> Hash
      end

      module TopLevel
        def test_config: () -> Integer
      end
    RBS

    source = <<~RUBY
      def test_config
        c = Config.new
        c.timeout = 30
        c.timeout
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "config_gc.rbs")
    source_path = File.join(@tmp_dir, "config_gc.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "config_gc")
    llvm_gen.generate(hir)

    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: File.join(@tmp_dir, "config_gc.bundle"),
      module_name: "config_gc",
      rbs_loader: loader
    )

    init_c_code = backend.send(:generate_init_c_code)

    # Verify Hash field is VALUE
    assert_includes init_c_code, "VALUE settings;", "settings should be VALUE"

    # Verify GC mark function marks the Hash field
    assert_includes init_c_code, "rb_gc_mark(obj->settings)", "settings field should be GC marked"

    # Verify settings is initialized to Qnil
    assert_includes init_c_code, "ptr->settings = Qnil", "settings should be initialized to Qnil"
  end

  def test_llvm_ir_generates_value_type_for_string_field
    rbs = <<~RBS
      class NamedPoint
        @x: Float
        @name: String

        def self.new: () -> NamedPoint
        def x: () -> Float
        def x=: (Float value) -> Float
        def name: () -> String
        def name=: (String value) -> String
      end

      module TopLevel
        def test_named_point: () -> Float
      end
    RBS

    source = <<~RUBY
      def test_named_point
        p = NamedPoint.new
        p.x = 1.5
        p.x
      end
    RUBY

    rbs_path = File.join(@tmp_dir, "named_point.rbs")
    source_path = File.join(@tmp_dir, "named_point.rb")
    File.write(rbs_path, rbs)
    File.write(source_path, source)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "named_point")
    llvm_gen.generate(hir)
    ir = llvm_gen.to_ir

    # Verify LLVM struct has correct layout:
    # - double for Float field (x)
    # - i64 for String field (name) - VALUE is i64
    assert_includes ir, "Native_NamedPoint"

    # The struct should contain both double and i64 types
    # (i64 is used for VALUE fields to store Ruby objects)
    assert_match(/Native_NamedPoint.*=.*type.*\{.*double.*i64.*\}/m, ir)
  end
end
