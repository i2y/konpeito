# frozen_string_literal: true

require "test_helper"

class HIRModuleTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
  end

  def build_hir(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    @hir_builder.build(typed_ast)
  end

  def test_module_definition
    source = <<~RUBY
      module MyModule
        def foo
          42
        end
      end
    RUBY
    program = build_hir(source)
    mod = program.modules.find { |m| m.name == "MyModule" }
    refute_nil mod
    assert_includes mod.methods, "foo"
  end

  def test_module_singleton_method
    source = <<~RUBY
      module MyModule
        def self.class_method
          42
        end
      end
    RUBY
    program = build_hir(source)
    mod = program.modules.find { |m| m.name == "MyModule" }
    refute_nil mod
    assert_includes mod.singleton_methods, "class_method"
    refute_includes mod.methods, "class_method"
  end

  def test_module_with_both_method_types
    source = <<~RUBY
      module MyModule
        def instance_method
          1
        end

        def self.class_method
          2
        end
      end
    RUBY
    program = build_hir(source)
    mod = program.modules.find { |m| m.name == "MyModule" }
    refute_nil mod
    assert_includes mod.methods, "instance_method"
    assert_includes mod.singleton_methods, "class_method"
    refute_includes mod.methods, "class_method"
    refute_includes mod.singleton_methods, "instance_method"
  end

  def test_extend_in_class
    source = <<~RUBY
      module Mixin
        def foo
          1
        end
      end

      class MyClass
        extend Mixin
      end
    RUBY
    program = build_hir(source)
    klass = program.classes.find { |c| c.name == "MyClass" }
    refute_nil klass
    assert_includes klass.extended_modules, "Mixin"
    refute_includes klass.included_modules, "Mixin"
  end

  def test_prepend_in_class
    source = <<~RUBY
      module Mixin
        def foo
          1
        end
      end

      class MyClass
        prepend Mixin
      end
    RUBY
    program = build_hir(source)
    klass = program.classes.find { |c| c.name == "MyClass" }
    refute_nil klass
    assert_includes klass.prepended_modules, "Mixin"
    refute_includes klass.included_modules, "Mixin"
  end

  def test_include_extend_prepend_combined
    source = <<~RUBY
      module M1
        def m1; end
      end

      module M2
        def m2; end
      end

      module M3
        def m3; end
      end

      class MyClass
        include M1
        extend M2
        prepend M3
      end
    RUBY
    program = build_hir(source)
    klass = program.classes.find { |c| c.name == "MyClass" }
    refute_nil klass
    assert_includes klass.included_modules, "M1"
    assert_includes klass.extended_modules, "M2"
    assert_includes klass.prepended_modules, "M3"
  end

  def test_module_constant
    source = <<~RUBY
      module MyModule
        VERSION = "1.0.0"
      end
    RUBY
    program = build_hir(source)
    mod = program.modules.find { |m| m.name == "MyModule" }
    refute_nil mod
    assert mod.constants.key?("VERSION")
  end

  def test_module_multiple_constants
    source = <<~RUBY
      module Config
        DEBUG = true
        VERSION = "2.0"
        MAX_SIZE = 100
      end
    RUBY
    program = build_hir(source)
    mod = program.modules.find { |m| m.name == "Config" }
    refute_nil mod
    assert mod.constants.key?("DEBUG")
    assert mod.constants.key?("VERSION")
    assert mod.constants.key?("MAX_SIZE")
  end
end
