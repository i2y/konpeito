# frozen_string_literal: true

require "test_helper"
require "prism"
require "konpeito/codegen/monomorphizer"
require "konpeito/type_checker/rbs_loader"
require "konpeito/type_checker/hm_inferrer"
require "konpeito/ast/typed_ast"
require "konpeito/hir/builder"

class MonomorphizerGenericsTest < Minitest::Test
  def test_class_specializations_detected_for_generic_class
    rbs_content = <<~RBS
      class Stack[T]
        def push: (T item) -> void
        def pop: () -> T
      end
    RBS
    loader = Konpeito::TypeChecker::RBSLoader.new.load(inline_rbs_content: rbs_content)

    code = <<~RUBY
      class Stack
        def initialize
          @data = []
        end
        def push(item)
          @data.push(item)
        end
        def pop
          @data.pop
        end
      end
      s = Stack.new
      s.push(42)
    RUBY

    hir, hm = build_hir(code, loader)
    mono = Konpeito::Codegen::Monomorphizer.new(hir, hm)
    mono.analyze

    # Should detect that Stack is generic (has type_params from RBS)
    assert loader.user_class_type_params.key?("Stack"), "RBS loader should capture Stack type params"
    assert_equal [:T], loader.user_class_type_params["Stack"]
  end

  def test_rbs_type_params_check_includes_user_defined
    rbs_content = <<~RBS
      class Container[E]
      end
    RBS
    loader = Konpeito::TypeChecker::RBSLoader.new.load(inline_rbs_content: rbs_content)

    code = <<~RUBY
      class Container
        def initialize
        end
      end
      c = Container.new
    RUBY

    hir, hm = build_hir(code, loader)
    mono = Konpeito::Codegen::Monomorphizer.new(hir, hm)

    # The user-defined type param :E should be detected as unresolved
    assert mono.send(:unresolved_type_param?, :E), ":E should be detected as unresolved type param"
    assert mono.send(:unresolved_type_param?, :T), ":T should be detected as built-in type param"
    refute mono.send(:unresolved_type_param?, :Integer), ":Integer should NOT be a type param"
  end

  private

  def build_hir(code, rbs_loader)
    ast = Prism.parse(code).value

    # Build typed AST (same pipeline as compiler)
    typed_builder = Konpeito::AST::TypedASTBuilder.new(rbs_loader, use_hm: true)
    typed_ast = typed_builder.build(ast)
    hm = typed_builder.instance_variable_get(:@hm_inferrer)

    # Build HIR from typed AST
    hir_builder = Konpeito::HIR::Builder.new(rbs_loader: rbs_loader)
    hir = hir_builder.build(typed_ast)
    [hir, hm]
  end
end
