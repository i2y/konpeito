# frozen_string_literal: true

require "test_helper"
require "konpeito/codegen/builtin_methods"
require "konpeito/codegen/llvm_generator"

module Konpeito
  module Codegen
    class BuiltinMethodsTest < Minitest::Test
      def test_lookup_string_method
        result = Codegen.lookup(:String, :length)
        assert_equal "rb_str_length", result[:c_func]
        assert_equal 0, result[:arity]
        assert_equal :simple, result[:conv]
      end

      def test_lookup_string_plus
        result = Codegen.lookup(:String, :+)
        assert_equal "rb_str_plus", result[:c_func]
        assert_equal 1, result[:arity]
      end

      def test_lookup_array_method
        result = Codegen.lookup(:Array, :push)
        assert_equal "rb_ary_push", result[:c_func]
        assert_equal 1, result[:arity]
      end

      def test_lookup_array_block_iterator
        result = Codegen.lookup(:Array, :each)
        assert_equal :block_iterator, result[:conv]
        assert_equal 0, result[:arity]
      end

      def test_lookup_hash_method
        result = Codegen.lookup(:Hash, :[])
        assert_equal "rb_hash_aref", result[:c_func]
        assert_equal 1, result[:arity]
      end

      def test_lookup_object_method
        result = Codegen.lookup(:Object, :===)
        assert_equal "rb_equal", result[:c_func]
        assert_equal 1, result[:arity]
      end

      def test_lookup_integer_iterator
        result = Codegen.lookup(:Integer, :times)
        assert_equal :block_iterator, result[:conv]
      end

      def test_lookup_range_iterator
        result = Codegen.lookup(:Range, :each)
        assert_equal :block_iterator, result[:conv]
      end

      def test_lookup_float_method_returns_nil
        # Float methods (floor, ceil, etc.) are not exported from libruby
        result = Codegen.lookup(:Float, :floor)
        assert_nil result
      end

      def test_lookup_nil_class_method
        result = Codegen.lookup(:NilClass, :to_a)
        assert_equal "rb_ary_new", result[:c_func]
      end

      def test_lookup_nonexistent_method
        result = Codegen.lookup(:String, :nonexistent_method)
        assert_nil result
      end

      def test_lookup_nonexistent_class
        result = Codegen.lookup(:NonexistentClass, :method)
        assert_nil result
      end

      def test_builtin_classes
        classes = Codegen.builtin_classes
        assert_includes classes, :Integer
        assert_includes classes, :String
        assert_includes classes, :Array
        assert_includes classes, :Hash
        assert_includes classes, :Object
        assert_includes classes, :Range
        assert_includes classes, :NilClass
      end

      def test_methods_for_string
        methods = Codegen.methods_for(:String)
        assert methods.key?(:length)
        assert methods.key?(:+)
        assert methods.key?(:<<)
        assert methods.key?(:concat)
      end

      def test_methods_for_nonexistent_class
        methods = Codegen.methods_for(:NonexistentClass)
        assert_equal({}, methods)
      end
    end

    class LLVMGeneratorBuiltinTest < Minitest::Test
      def setup
        @loader = Konpeito::TypeChecker::RBSLoader.new.load
        @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
        @hir_builder = Konpeito::HIR::Builder.new
        @generator = LLVMGenerator.new(module_name: "test")
      end

      def compile_to_ir(source)
        ast = Konpeito::Parser::PrismAdapter.parse(source)
        typed_ast = @ast_builder.build(ast)
        hir = @hir_builder.build(typed_ast)
        @generator.generate(hir)
        @generator.to_ir
      end

      def test_declares_rb_hash_lookup2
        # The generator should declare rb_hash_lookup2 for keyword argument support
        ir = compile_to_ir("42")
        assert_includes ir, "declare i64 @rb_hash_lookup2(i64, i64, i64)"
      end

      def test_declares_rb_ary_entry
        ir = compile_to_ir("42")
        assert_includes ir, "declare i64 @rb_ary_entry(i64, i64)"
      end

      def test_declares_rb_ary_store
        ir = compile_to_ir("42")
        assert_includes ir, "declare void @rb_ary_store(i64, i64, i64)"
      end

      def test_declares_builtin_string_methods
        # Check that builtin methods from BUILTIN_METHODS are declared
        ir = compile_to_ir("42")
        assert_includes ir, "@rb_str_length"
      end

      def test_declares_builtin_array_methods
        ir = compile_to_ir("42")
        assert_includes ir, "@rb_ary_push"
      end

      def test_declares_builtin_hash_methods
        ir = compile_to_ir("42")
        assert_includes ir, "@rb_hash_aref"
      end
    end
  end
end
