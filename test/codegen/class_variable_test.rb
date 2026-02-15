# frozen_string_literal: true

require "test_helper"

class ClassVariableTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
  end

  def compile_to_ir(source)
    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: @loader)
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test", rbs_loader: @loader)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = hir_builder.build(typed_ast)
    llvm_gen.generate(hir)
    llvm_gen.to_ir
  end

  def test_class_variable_read_calls_rb_cvar_get
    source = <<~RUBY
      class Counter
        def count
          @@count
        end
      end
    RUBY
    ir = compile_to_ir(source)
    assert_includes ir, "rb_cvar_get", "Should call rb_cvar_get for class variable read"
    assert_includes ir, "rb_intern", "Should intern the class variable name"
  end

  def test_class_variable_write_calls_rb_cvar_set
    source = <<~RUBY
      class Counter
        def reset
          @@count = 0
        end
      end
    RUBY
    ir = compile_to_ir(source)
    assert_includes ir, "rb_cvar_set", "Should call rb_cvar_set for class variable write"
    assert_includes ir, "rb_intern", "Should intern the class variable name"
  end

  def test_class_variable_read_and_write
    source = <<~RUBY
      class Counter
        def increment
          @@count = @@count + 1
        end
      end
    RUBY
    ir = compile_to_ir(source)
    assert_includes ir, "rb_cvar_get", "Should read class variable"
    assert_includes ir, "rb_cvar_set", "Should write class variable"
  end

  def test_class_method_with_class_variable
    source = <<~RUBY
      class Counter
        def self.count
          @@count
        end
      end
    RUBY
    ir = compile_to_ir(source)
    assert_includes ir, "rb_cvar_get", "Class method should access class variable"
  end

  def test_class_variable_uses_rb_class_of_for_instance_methods
    source = <<~RUBY
      class Counter
        def get_count
          @@count
        end
      end
    RUBY
    ir = compile_to_ir(source)
    # Instance methods need to get class from self via rb_class_of
    assert_includes ir, "rb_class_of", "Instance method should use rb_class_of to get class"
  end

  def test_class_variable_initialization
    source = <<~RUBY
      class Counter
        def self.init
          @@count = 0
          @@count
        end
      end
    RUBY
    ir = compile_to_ir(source)
    assert_includes ir, "rb_cvar_set", "Should initialize class variable"
    assert_includes ir, "rb_cvar_get", "Should read back class variable"
  end

  def test_multiple_class_variables
    source = <<~RUBY
      class Stats
        def track
          @@count = @@count + 1
          @@total = @@total + 10
        end
      end
    RUBY
    ir = compile_to_ir(source)
    # Should have multiple rb_cvar_get and rb_cvar_set calls
    # Each class variable access requires rb_intern for its name
    assert_includes ir, "@@count"
    assert_includes ir, "@@total"
  end
end
