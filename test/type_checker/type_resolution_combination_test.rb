# frozen_string_literal: true

require "test_helper"
require "prism"

# Comprehensive type resolution tests: HM inference + JAR introspection + RBS
# Tests the combination of all three type sources following TDD style.
#
# Principle: HM inference is primary. RBS/JAR are supplementary.
# Unresolvable types should be errors, not silent fallbacks.
class TypeResolutionCombinationTest < Minitest::Test
  Types = Konpeito::TypeChecker::Types
  TypeVar = Konpeito::TypeChecker::TypeVar

  def setup
    @rbs_loader = Konpeito::TypeChecker::RBSLoader.new.load
  end

  # ── Helpers ──────────────────────────────────────────────────────

  # Infer types without any RBS (pure HM inference)
  def infer_no_rbs(code)
    ast = Prism.parse(code).value
    hm = Konpeito::TypeChecker::HMInferrer.new(nil)
    hm.analyze(ast)
    [hm, hm.instance_variable_get(:@env).first]
  end

  # Infer types with RBS loaded (default stdlib RBS)
  def infer_with_rbs(code)
    ast = Prism.parse(code).value
    hm = Konpeito::TypeChecker::HMInferrer.new(@rbs_loader)
    hm.analyze(ast)
    [hm, hm.instance_variable_get(:@env).first]
  end

  # Infer types with custom inline RBS content
  def infer_with_inline_rbs(code, rbs_content)
    loader = Konpeito::TypeChecker::RBSLoader.new
    loader.load(inline_rbs_content: rbs_content)
    ast = Prism.parse(code).value
    hm = Konpeito::TypeChecker::HMInferrer.new(loader)
    hm.analyze(ast)
    [hm, hm.instance_variable_get(:@env).first]
  end

  # Infer types with manually injected JVM class info
  def infer_with_jvm(code, jvm_classes: {}, rbs_content: nil)
    loader = Konpeito::TypeChecker::RBSLoader.new
    if rbs_content
      loader.load(inline_rbs_content: rbs_content)
    else
      loader.load
    end
    jvm_classes.each { |k, v| loader.jvm_classes[k.to_s] = v }
    ast = Prism.parse(code).value
    hm = Konpeito::TypeChecker::HMInferrer.new(loader)
    hm.analyze(ast)
    [hm, hm.instance_variable_get(:@env).first]
  end

  # Finalize a type (resolve TypeVars)
  def fin(hm, type)
    hm.finalize(type)
  end

  # Get the type of a variable from env
  def var_type(hm, env, name)
    scheme = env[name.to_sym]
    return nil unless scheme
    fin(hm, scheme.type)
  end

  # Get function type from @function_types
  def func_type(hm, name)
    ft = hm.instance_variable_get(:@function_types)
    type = ft[name.to_sym]
    type ? fin(hm, type) : nil
  end

  # Assert type is a TypeVar (unresolved)
  def assert_typevar(type, msg = nil)
    resolved = type.is_a?(TypeVar) ? type.prune : type
    assert resolved.is_a?(TypeVar), msg || "Expected TypeVar but got #{resolved.class}: #{resolved}"
  end

  # ══════════════════════════════════════════════════════════════════
  # Category A: Pure HM Inference — Literals & Basic Expressions
  # ══════════════════════════════════════════════════════════════════

  def test_hm_integer_literal
    hm, env = infer_no_rbs("x = 42")
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_float_literal
    hm, env = infer_no_rbs("x = 3.14")
    assert_equal Types::FLOAT, var_type(hm, env, :x)
  end

  def test_hm_string_literal
    hm, env = infer_no_rbs("x = 'hello'")
    assert_equal Types::STRING, var_type(hm, env, :x)
  end

  def test_hm_bool_true_literal
    hm, env = infer_no_rbs("x = true")
    assert_equal Types::TRUE_CLASS, var_type(hm, env, :x)
  end

  def test_hm_bool_false_literal
    hm, env = infer_no_rbs("x = false")
    assert_equal Types::FALSE_CLASS, var_type(hm, env, :x)
  end

  def test_hm_nil_literal
    hm, env = infer_no_rbs("x = nil")
    assert_equal Types::NIL, var_type(hm, env, :x)
  end

  def test_hm_symbol_literal
    hm, env = infer_no_rbs("x = :foo")
    assert_equal Types::SYMBOL, var_type(hm, env, :x)
  end

  def test_hm_regexp_literal
    hm, env = infer_no_rbs("x = /pattern/")
    assert_equal Types::REGEXP, var_type(hm, env, :x)
  end

  def test_hm_range_literal
    hm, env = infer_no_rbs("x = 1..10")
    assert_equal Types::RANGE, var_type(hm, env, :x)
  end

  def test_hm_string_interpolation
    hm, env = infer_no_rbs('x = "hello #{42}"')
    assert_equal Types::STRING, var_type(hm, env, :x)
  end

  def test_hm_array_homogeneous_integers
    hm, env = infer_no_rbs("arr = [1, 2, 3]")
    type = var_type(hm, env, :arr)
    assert_equal :Array, type.name
    assert_equal Types::INTEGER, type.type_args.first
  end

  def test_hm_array_empty
    hm, env = infer_no_rbs("arr = []")
    type = var_type(hm, env, :arr)
    assert_equal :Array, type.name
    # Empty array has TypeVar element
    assert type.type_args.first.is_a?(TypeVar) || type.type_args.first == Types::UNTYPED
  end

  def test_hm_hash_string_to_integer
    hm, env = infer_no_rbs('h = { "a" => 1 }')
    type = var_type(hm, env, :h)
    assert_equal :Hash, type.name
    assert_equal Types::STRING, type.type_args[0]
    assert_equal Types::INTEGER, type.type_args[1]
  end

  def test_hm_hash_empty
    hm, env = infer_no_rbs("h = {}")
    type = var_type(hm, env, :h)
    assert_equal :Hash, type.name
  end

  def test_hm_arithmetic_int_plus_int
    hm, env = infer_no_rbs("x = 5; y = x + 1")
    assert_equal Types::INTEGER, var_type(hm, env, :y)
  end

  def test_hm_arithmetic_int_times_float
    hm, env = infer_no_rbs("x = 5 * 2.0")
    assert_equal Types::FLOAT, var_type(hm, env, :x)
  end

  def test_hm_string_concat
    hm, env = infer_no_rbs('x = "a" + "b"')
    assert_equal Types::STRING, var_type(hm, env, :x)
  end

  def test_hm_comparison_returns_bool
    hm, env = infer_no_rbs("x = 5 > 3")
    type = var_type(hm, env, :x)
    assert_includes [Types::BOOL, Types::TRUE_CLASS, Types::FALSE_CLASS], type
  end

  def test_hm_to_s_returns_string
    hm, env = infer_no_rbs("x = 42.to_s")
    assert_equal Types::STRING, var_type(hm, env, :x)
  end

  def test_hm_variable_chain
    hm, env = infer_no_rbs("x = 1; y = x + 2; z = y * 3")
    assert_equal Types::INTEGER, var_type(hm, env, :z)
  end

  # ══════════════════════════════════════════════════════════════════
  # Category B: Function & Method Type Inference
  # ══════════════════════════════════════════════════════════════════

  def test_hm_function_return_from_body
    hm, _env = infer_no_rbs("def f; 42; end")
    ft = func_type(hm, :f)
    assert_equal Types::INTEGER, ft.return_type
  end

  def test_hm_function_param_from_callsite
    code = <<~RUBY
      def f(x)
        x + 1
      end
      result = f(5)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_polymorphic_instantiation
    code = <<~RUBY
      def identity(x)
        x
      end
      a = identity(42)
      b = identity("hello")
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :a)
    assert_equal Types::STRING, var_type(hm, env, :b)
  end

  def test_hm_class_new_returns_instance
    code = <<~RUBY
      class MyClass
      end
      x = MyClass.new
    RUBY
    hm, env = infer_no_rbs(code)
    type = var_type(hm, env, :x)
    assert type.is_a?(Types::ClassInstance), "Expected ClassInstance, got #{type.class}"
    assert_equal :MyClass, type.name
  end

  def test_hm_class_method_return_from_body
    code = <<~RUBY
      class Calculator
        def compute
          42
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ft = func_type(hm, :"Calculator#compute")
    assert_equal Types::INTEGER, fin(hm, ft.return_type)
  end

  def test_hm_class_instance_method_call
    code = <<~RUBY
      class Calculator
        def compute
          42
        end
      end
      c = Calculator.new
      r = c.compute
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :r)
  end

  def test_hm_multi_param_function
    # Deferred constraint resolution: `a + b + c` deferred during body analysis,
    # then resolved after call-site unifies a=Integer, b=Integer, c=Integer
    code = <<~RUBY
      def add3(a, b, c)
        a + b + c
      end
      result = add3(1, 2, 3)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_multi_param_function_with_concrete_literal
    # When one operand is a literal (concrete type), the chain resolves
    code = <<~RUBY
      def add_with_offset(a, b)
        a + b + 10
      end
      result = add_with_offset(1, 2)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_recursive_function
    code = <<~RUBY
      def factorial(n)
        if n <= 1
          1
        else
          n * factorial(n - 1)
        end
      end
      result = factorial(5)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_nested_function_calls
    code = <<~RUBY
      def double(x)
        x * 2
      end
      def add_one(x)
        double(x) + 1
      end
      result = add_one(5)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_deeply_nested_calls
    code = <<~RUBY
      def a(x)
        x
      end
      def b(x)
        a(x)
      end
      def c(x)
        b(x)
      end
      result = c(42)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_class_inheritance_method
    code = <<~RUBY
      class Animal
        def legs
          4
        end
      end
      class Dog < Animal
      end
      d = Dog.new
      n = d.legs
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :n)
  end

  def test_hm_super_call_type
    code = <<~RUBY
      class Base
        def value
          10
        end
      end
      class Child < Base
        def value
          super + 1
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ft = func_type(hm, :"Child#value")
    assert_equal Types::INTEGER, fin(hm, ft.return_type)
  end

  def test_hm_class_ivar_type_from_assignment
    code = <<~RUBY
      class Counter
        def initialize
          @count = 0
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ivar_types = hm.ivar_types
    assert ivar_types["Counter"]
    assert_equal Types::INTEGER, ivar_types["Counter"]["@count"]
  end

  def test_hm_singleton_method
    code = <<~RUBY
      class Factory
        def self.create
          Factory.new
        end
      end
      obj = Factory.create
    RUBY
    hm, env = infer_no_rbs(code)
    type = var_type(hm, env, :obj)
    assert type.is_a?(Types::ClassInstance), "Expected ClassInstance, got #{type.class}"
    assert_equal :Factory, type.name
  end

  def test_hm_function_as_expression
    code = <<~RUBY
      y = if true
        1
      else
        2
      end
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :y)
  end

  # ══════════════════════════════════════════════════════════════════
  # Category C: Nested Calls & Complex Expressions
  # ══════════════════════════════════════════════════════════════════

  def test_hm_nested_arithmetic
    hm, env = infer_no_rbs("x = (1 + 2) * (3 + 4)")
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_nested_conditional
    code = <<~RUBY
      x = if 1 > 0
        if 2 > 1
          42
        else
          0
        end
      else
        -1
      end
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_nested_call_return_type_flows
    code = <<~RUBY
      def inner(x)
        x * 2
      end
      def outer
        inner(5)
      end
      result = outer
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_call_with_literal_and_var
    # Deferred constraint resolution: `a + b` deferred, resolved after f(x, 20)
    code = <<~RUBY
      x = 10
      def f(a, b)
        a + b
      end
      result = f(x, 20)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_call_with_literal_in_body
    # When at least one operand in the body is a literal, type resolves
    code = <<~RUBY
      x = 10
      def f(a)
        a + 5
      end
      result = f(x)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_method_call_on_method_result
    code = <<~RUBY
      def make_arr
        [1, 2, 3]
      end
      result = make_arr.size
    RUBY
    hm, env = infer_with_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_nested_class_method_calls
    code = <<~RUBY
      class Calc
        def x
          1
        end
        def y
          x + 2
        end
      end
      c = Calc.new
      result = c.y
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_conditional_in_method
    code = <<~RUBY
      def abs_val(x)
        if x > 0
          x
        else
          0
        end
      end
      result = abs_val(5)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_both_branches_same_type
    code = <<~RUBY
      def classify(x)
        if x > 0
          1
        else
          2
        end
      end
      result = classify(5)
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_hm_string_method_chain
    hm, env = infer_no_rbs('"hello".to_s.length')
    # length call - may or may not resolve without RBS
    # At minimum, no crash
    assert env
  end

  def test_hm_array_first_type
    hm, env = infer_with_rbs("arr = [1, 2, 3]; x = arr.first")
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  # ══════════════════════════════════════════════════════════════════
  # Category D: Block Inference
  # ══════════════════════════════════════════════════════════════════

  def test_hm_block_map_int_to_int
    code = <<~RUBY
      arr = [1, 2, 3]
      doubled = arr.map { |x| x * 2 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :doubled)
    assert_equal :Array, type.name
    assert_equal Types::INTEGER, type.type_args.first
  end

  def test_hm_block_map_int_to_string
    code = <<~RUBY
      arr = [1, 2, 3]
      strings = arr.map { |x| x.to_s }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :strings)
    assert_equal :Array, type.name
    assert_equal Types::STRING, type.type_args.first
  end

  def test_hm_block_select_preserves_type
    code = <<~RUBY
      arr = [1, 2, 3]
      filtered = arr.select { |x| x > 1 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :filtered)
    assert_equal :Array, type.name
    assert_equal Types::INTEGER, type.type_args.first
  end

  def test_hm_block_each_returns_array
    code = <<~RUBY
      arr = [1, 2, 3]
      result = arr.each { |x| x.to_s }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    # RBS defines Array#each as returning Enumerator (not self/Array)
    assert_includes [:Array, :Enumerator], type.name
  end

  def test_hm_block_reduce_accumulator
    code = <<~RUBY
      arr = [1, 2, 3]
      sum = arr.reduce(0) { |acc, x| acc + x }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :sum)
    # reduce with Integer accumulator should return Integer
    assert_includes [Types::INTEGER, Types::UNTYPED], type
  end

  def test_hm_block_any_returns_bool
    code = <<~RUBY
      arr = [1, 2, 3]
      result = arr.any? { |x| x > 2 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_includes [Types::BOOL, Types::TRUE_CLASS, Types::FALSE_CLASS], type
  end

  def test_hm_block_all_returns_bool
    code = <<~RUBY
      arr = [1, 2, 3]
      result = arr.all? { |x| x > 0 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_includes [Types::BOOL, Types::TRUE_CLASS, Types::FALSE_CLASS], type
  end

  def test_hm_block_none_returns_bool
    code = <<~RUBY
      arr = [1, 2, 3]
      result = arr.none? { |x| x > 5 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_includes [Types::BOOL, Types::TRUE_CLASS, Types::FALSE_CLASS], type
  end

  def test_hm_block_find
    code = <<~RUBY
      arr = [1, 2, 3]
      result = arr.find { |x| x > 2 }
    RUBY
    hm, env = infer_with_rbs(code)
    # find may return Integer or nil
    type = var_type(hm, env, :result)
    assert type, "find should return a type"
  end

  def test_hm_numbered_block_params
    code = <<~RUBY
      arr = [1, 2, 3]
      doubled = arr.map { _1 * 2 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :doubled)
    assert_equal :Array, type.name
  end

  def test_hm_it_block_param
    code = <<~RUBY
      arr = [1, 2, 3]
      doubled = arr.map { it * 2 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :doubled)
    assert_equal :Array, type.name
  end

  def test_hm_nested_blocks
    code = <<~RUBY
      arrs = [[1, 2], [3, 4]]
      result = arrs.map { |arr| arr.map { |x| x * 2 } }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal :Array, type.name
  end

  # ══════════════════════════════════════════════════════════════════
  # Category E: Closure & Capture Variables
  # ══════════════════════════════════════════════════════════════════

  def test_hm_block_captures_outer_integer
    code = <<~RUBY
      y = 10
      arr = [1, 2, 3]
      result = arr.map { |x| x + y }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal :Array, type.name
    assert_equal Types::INTEGER, type.type_args.first
  end

  def test_hm_block_captures_string
    code = <<~RUBY
      prefix = "num:"
      arr = [1, 2, 3]
      result = arr.map { |x| prefix + x.to_s }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal :Array, type.name
    assert_equal Types::STRING, type.type_args.first
  end

  def test_hm_block_modifies_outer_var
    code = <<~RUBY
      total = 0
      arr = [1, 2, 3]
      arr.each { |x| total = total + x }
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :total)
  end

  def test_hm_yield_passes_integer
    code = <<~RUBY
      def f
        yield(42)
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_empty hm.errors
  end

  def test_hm_block_given_returns_bool
    code = <<~RUBY
      def f
        block_given?
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ft = func_type(hm, :f)
    # block_given? returns Bool (production fix: recognized as built-in)
    type = fin(hm, ft.return_type)
    assert_equal Types::BOOL, type
  end

  def test_hm_times_block
    code = <<~RUBY
      result = 3.times { |i| i + 1 }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    # Integer#times with block returns self (Integer) per RBS
    # May return Integer or Enumerator depending on RBS version
    assert_includes [Types::INTEGER, nil], type
  end

  def test_hm_capture_class_instance_field
    # Block captures outer variable `p` (class instance) and calls method on it
    # Needs RBS for Array#map block return type inference
    code = <<~RUBY
      class PointHelper
        def val
          1
        end
      end
      p = PointHelper.new
      arr = [1, 2, 3]
      result = arr.map { |x| p.val + x }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal :Array, type.name
  end

  def test_hm_nested_block_capture
    code = <<~RUBY
      z = 1
      outer = [1, 2]
      result = outer.map { |x| [3, 4].map { |y| x + y + z } }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal :Array, type.name
  end

  # ══════════════════════════════════════════════════════════════════
  # Category F: Proc/Lambda
  # ══════════════════════════════════════════════════════════════════

  def test_hm_lambda_literal
    code = "f = -> { 42 }"
    hm, env = infer_no_rbs(code)
    # Lambda should produce some type (may be TypeVar if not explicitly supported)
    assert env[:f], "Lambda should bind to variable"
  end

  def test_hm_lambda_with_params
    code = "f = ->(x) { x + 1 }"
    hm, env = infer_no_rbs(code)
    assert env[:f], "Lambda with params should bind"
  end

  def test_hm_lambda_captures_outer
    code = <<~RUBY
      x = 10
      f = -> { x + 1 }
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :x)
    assert env[:f], "Lambda capturing outer var should bind"
  end

  def test_hm_lambda_no_crash
    # At minimum, lambda expressions should not crash the inferrer
    code = <<~RUBY
      f = -> { "hello" }
      g = ->(a, b) { a + b }
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_empty hm.errors
  end

  # ══════════════════════════════════════════════════════════════════
  # Category G: Variadic & Keyword Arguments
  # ══════════════════════════════════════════════════════════════════

  def test_hm_rest_args_type
    code = <<~RUBY
      def f(*args)
        args
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ft = func_type(hm, :f)
    ret = fin(hm, ft.return_type)
    assert_equal :Array, ret.name
  end

  def test_hm_rest_args_with_fixed
    code = <<~RUBY
      def f(a, *rest)
        rest
      end
      result = f(1, 2, 3)
    RUBY
    hm, env = infer_no_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal :Array, type.name
  end

  def test_hm_kwargs_type
    code = <<~RUBY
      def f(**kwargs)
        kwargs
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ft = func_type(hm, :f)
    ret = fin(hm, ft.return_type)
    assert_equal :Hash, ret.name
  end

  def test_hm_keyword_required
    # Keyword arg type propagation from call site — now resolved via deferred constraints
    code = <<~RUBY
      def greet(name:)
        name
      end
      result = greet(name: "Alice")
    RUBY
    hm, env = infer_no_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal Types::STRING, type
  end

  def test_hm_keyword_optional_default
    # Default value type (Integer from `1`) is now propagated to param TypeVar
    code = <<~RUBY
      def f(count: 1)
        count
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ft = func_type(hm, :f)
    ret = fin(hm, ft.return_type)
    assert_equal Types::INTEGER, ret
  end

  def test_hm_keyword_mixed_with_positional
    code = <<~RUBY
      def f(a, name:, count: 0)
        a
      end
      result = f(1, name: "x", count: 5)
    RUBY
    hm, env = infer_no_rbs(code)
    type = var_type(hm, env, :result)
    assert_equal Types::INTEGER, type
  end

  def test_hm_rest_args_element_access
    code = <<~RUBY
      def f(*args)
        args.first
      end
    RUBY
    hm, _env = infer_with_rbs(code)
    # rest args elements are TypeVar, first returns element
    ft = func_type(hm, :f)
    assert ft, "Function type should exist"
  end

  def test_hm_kwargs_no_crash
    code = <<~RUBY
      def f(a, b:, c: 0, **rest)
        a
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_empty hm.errors
  end

  # ══════════════════════════════════════════════════════════════════
  # Category H: Control Flow & Branch Unification
  # ══════════════════════════════════════════════════════════════════

  def test_hm_if_else_same_type
    hm, env = infer_no_rbs("x = if true; 1; else; 2; end")
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_if_else_both_string
    hm, env = infer_no_rbs('x = if true; "a"; else; "b"; end')
    assert_equal Types::STRING, var_type(hm, env, :x)
  end

  def test_hm_unless_type
    hm, env = infer_no_rbs('x = unless false; "yes"; else; "no"; end')
    assert_equal Types::STRING, var_type(hm, env, :x)
  end

  def test_hm_while_returns_nil
    hm, env = infer_no_rbs("x = while false; 1; end")
    assert_equal Types::NIL, var_type(hm, env, :x)
  end

  def test_hm_until_returns_nil
    hm, env = infer_no_rbs("x = until true; 1; end")
    assert_equal Types::NIL, var_type(hm, env, :x)
  end

  def test_hm_ternary_same_type
    hm, env = infer_no_rbs("x = true ? 1 : 2")
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_case_when_string_branches
    code = <<~RUBY
      x = case 1
          when 1 then "one"
          when 2 then "two"
          else "other"
          end
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::STRING, var_type(hm, env, :x)
  end

  def test_hm_flow_narrowing_nil_check
    code = <<~RUBY
      def f(x)
        if x == nil
          "nil"
        else
          x.to_s
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_empty hm.errors
  end

  def test_hm_flow_narrowing_and
    code = <<~RUBY
      def f(a, b)
        if a && b
          a.to_s + b.to_s
        else
          "missing"
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_empty hm.errors
  end

  def test_hm_logical_and_returns_right
    hm, env = infer_no_rbs("x = true && 42")
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_logical_or_returns_left
    hm, env = infer_no_rbs('x = 42 || "fallback"')
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_if_without_else_no_crash
    code = "x = if true; 42; end"
    hm, env = infer_no_rbs(code)
    # Should not crash, type may be Integer or nil union
    assert env[:x]
  end

  # ══════════════════════════════════════════════════════════════════
  # Category I: Compound Assignment & Multi-Assignment
  # ══════════════════════════════════════════════════════════════════

  def test_hm_compound_plus_assign
    code = "x = 1; x += 2"
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_hm_compound_or_assign
    code = "x = nil; x ||= 42"
    hm, env = infer_no_rbs(code)
    type = var_type(hm, env, :x)
    assert type, "||= should produce a type"
  end

  def test_hm_compound_and_assign
    code = "x = 42; x &&= 0"
    hm, env = infer_no_rbs(code)
    type = var_type(hm, env, :x)
    assert type, "&&= should produce a type"
  end

  def test_hm_multi_assign
    code = "a, b = [1, 2]"
    hm, env = infer_no_rbs(code)
    # Multi-assign returns RHS; individual vars may not get typed
    assert env
  end

  def test_hm_ivar_compound_assign
    code = <<~RUBY
      class Counter
        def initialize
          @x = 0
        end
        def inc
          @x += 1
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_equal Types::INTEGER, hm.ivar_types.dig("Counter", "@x")
  end

  def test_hm_cvar_type_tracking
    code = <<~RUBY
      class Config
        @@count = 0
        def inc
          @@count += 1
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    # Class variable should be tracked
    cvars = hm.instance_variable_get(:@cvar_types)
    assert cvars["Config"]
  end

  def test_hm_global_var_type
    code = "$g = 42"
    hm, _env = infer_no_rbs(code)
    globals = hm.instance_variable_get(:@global_var_types)
    assert_equal Types::INTEGER, globals["$g"]
  end

  # ══════════════════════════════════════════════════════════════════
  # Category J: HM Error Cases
  # ══════════════════════════════════════════════════════════════════

  def test_hm_error_unknown_method_on_typevar
    code = <<~RUBY
      def f(x)
        x.totally_unknown_method_xyz
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert hm.inference_errors.any?, "Should record error for unknown method"
  end

  def test_hm_error_message_contains_method_name
    code = <<~RUBY
      def f(x)
        x.mysterious_method_abc
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    error = hm.inference_errors.first
    assert_includes error, "mysterious_method_abc"
  end

  def test_hm_error_returns_typevar
    code = <<~RUBY
      def f(x)
        x.unknown_method_xyz
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    ft = func_type(hm, :f)
    ret = fin(hm, ft.return_type)
    # Return should be TypeVar (unresolved) since the method is unknown
    assert ret.is_a?(TypeVar) || ret == Types::UNTYPED,
           "Expected TypeVar or UNTYPED for unknown method, got #{ret.class}: #{ret}"
  end

  def test_hm_error_multiple_unknown
    code = <<~RUBY
      def f(x)
        x.unknown_foo_abc
        x.unknown_bar_def
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert hm.inference_errors.size >= 2, "Should record multiple errors"
  end

  def test_hm_no_error_for_known_methods
    code = <<~RUBY
      def f
        42.to_s
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_empty hm.inference_errors
  end

  def test_hm_error_count_zero_for_simple
    hm, _env = infer_no_rbs("x = 1 + 2")
    assert_empty hm.inference_errors
  end

  def test_hm_no_errors_for_class_methods
    # Deferred constraints: `a + b` is deferred, resolved after call-site
    code = <<~RUBY
      class Adder
        def add(a, b)
          a + b
        end
      end
      c = Adder.new
      r = c.add(1, 2)
    RUBY
    hm, _env = infer_no_rbs(code)
    assert_empty hm.inference_errors
  end

  def test_hm_errors_for_uncalled_typevar_method
    # If a function with TypeVar params is never called, deferred constraints
    # remain unresolved and generate errors
    code = <<~RUBY
      class Calc
        def add(a, b)
          a + b
        end
      end
    RUBY
    hm, _env = infer_no_rbs(code)
    refute_empty hm.inference_errors
    assert hm.inference_errors.any? { |e| e.include?("+") }
  end

  def test_hm_error_after_all_sources
    code = <<~RUBY
      def f(x)
        x.completely_nonexistent_method_zzz
      end
    RUBY
    # Even with RBS loaded, unknown method on TypeVar should error
    hm, _env = infer_with_rbs(code)
    assert hm.inference_errors.any?
  end

  # ══════════════════════════════════════════════════════════════════
  # Category K: RBS Supplementing HM
  # ══════════════════════════════════════════════════════════════════

  def test_rbs_refines_param_types
    code = <<~RUBY
      def add(a, b)
        a + b
      end
      result = add(1, 2)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def add: (Integer a, Integer b) -> Integer
      end
    RBS
    hm, env = infer_with_inline_rbs(code, rbs)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_rbs_generic_array_first
    code = <<~RUBY
      arr = [1, 2, 3]
      x = arr.first
    RUBY
    hm, env = infer_with_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_rbs_generic_hash_keys
    code = <<~RUBY
      h = { "a" => 1 }
      k = h.keys
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :k)
    assert_equal :Array, type.name
    assert_equal Types::STRING, type.type_args.first
  end

  def test_rbs_block_map_return_type
    code = <<~RUBY
      arr = [1, 2, 3]
      strings = arr.map { |x| x.to_s }
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :strings)
    assert_equal :Array, type.name
    assert_equal Types::STRING, type.type_args.first
  end

  def test_rbs_user_class_field_types
    code = <<~RUBY
      class Pt
        def initialize
          @x = 0.0
        end
      end
    RUBY
    rbs = <<~RBS
      class Pt
        @x: Float
        def initialize: () -> void
      end
    RBS
    hm, _env = infer_with_inline_rbs(code, rbs)
    # RBS should populate ivar types
    assert hm.ivar_types.dig("Pt", "@x")
  end

  def test_rbs_consistent_with_hm_alone
    code = <<~RUBY
      def double(x)
        x * 2
      end
      result = double(5)
    RUBY
    hm_only, env_only = infer_no_rbs(code)
    hm_rbs, env_rbs = infer_with_rbs(code)

    # Both should produce Integer
    assert_equal Types::INTEGER, var_type(hm_only, env_only, :result)
    assert_equal Types::INTEGER, var_type(hm_rbs, env_rbs, :result)
  end

  def test_rbs_supplements_generics
    code = <<~RUBY
      arr = [1, 2, 3]
      vals = arr.values_at(0, 1)
    RUBY
    hm, env = infer_with_rbs(code)
    # values_at returns Array[Integer] via RBS generic
    type = var_type(hm, env, :vals)
    assert_equal :Array, type.name
  end

  def test_rbs_overload_integer_plus
    hm, env = infer_with_rbs("x = 5 * 2")
    assert_equal Types::INTEGER, var_type(hm, env, :x)
  end

  def test_rbs_hash_values_type
    code = <<~RUBY
      h = { "a" => 1 }
      v = h.values
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :v)
    assert_equal :Array, type.name
    assert_equal Types::INTEGER, type.type_args.first
  end

  def test_rbs_singleton_new
    code = <<~RUBY
      class Widget
      end
      w = Widget.new
    RUBY
    hm, env = infer_with_rbs(code)
    type = var_type(hm, env, :w)
    assert type.is_a?(Types::ClassInstance)
    assert_equal :Widget, type.name
  end

  # ══════════════════════════════════════════════════════════════════
  # Category L: JVM Class Resolution
  # ══════════════════════════════════════════════════════════════════

  def test_jvm_class_method_lookup
    code = <<~RUBY
      Calculator = Calculator
      result = Calculator.add(1, 2)
    RUBY
    jvm = {
      "Calculator" => {
        jvm_internal_name: "com/test/Calculator",
        static_methods: {
          "add" => { params: [:i64, :i64], return: :i64 }
        },
        methods: {},
        constructor_params: []
      }
    }
    hm, env = infer_with_jvm(code, jvm_classes: jvm)
    type = var_type(hm, env, :result)
    assert_equal Types::INTEGER, type
  end

  def test_jvm_instance_method_lookup
    code = <<~RUBY
      c = Counter.new
      result = c.get_value
    RUBY
    jvm = {
      "Counter" => {
        jvm_internal_name: "com/test/Counter",
        static_methods: {},
        methods: {
          "get_value" => { params: [], return: :i64 }
        },
        constructor_params: []
      }
    }
    hm, env = infer_with_jvm(code, jvm_classes: jvm)
    type = var_type(hm, env, :result)
    assert_equal Types::INTEGER, type
  end

  def test_jvm_constructor_resolution
    code = "c = Counter.new(10)"
    jvm = {
      "Counter" => {
        jvm_internal_name: "com/test/Counter",
        static_methods: {},
        methods: {},
        constructor_params: [:i64]
      }
    }
    hm, env = infer_with_jvm(code, jvm_classes: jvm)
    type = var_type(hm, env, :c)
    assert type.is_a?(Types::ClassInstance)
    assert_equal :Counter, type.name
  end

  def test_jvm_tag_conversions
    hm_inst = Konpeito::TypeChecker::HMInferrer.new(nil)

    assert_equal Types::INTEGER, hm_inst.send(:jvm_tag_to_hm_type, :i64)
    assert_equal Types::FLOAT, hm_inst.send(:jvm_tag_to_hm_type, :double)
    assert_equal Types::STRING, hm_inst.send(:jvm_tag_to_hm_type, :string)
    assert_equal Types::BOOL, hm_inst.send(:jvm_tag_to_hm_type, :i8)
    assert_equal Types::UNTYPED, hm_inst.send(:jvm_tag_to_hm_type, :void)
    assert_equal Types::UNTYPED, hm_inst.send(:jvm_tag_to_hm_type, :value)
  end

  # ══════════════════════════════════════════════════════════════════
  # Category M: Combined Resolution Priority
  # ══════════════════════════════════════════════════════════════════

  def test_builtin_before_rbs
    # Built-in comparison should return Bool, not whatever RBS says for Numeric
    hm, env = infer_with_rbs("x = 5 > 3")
    type = var_type(hm, env, :x)
    assert_includes [Types::BOOL, Types::TRUE_CLASS, Types::FALSE_CLASS], type
  end

  def test_user_method_before_rbs_lookup
    code = <<~RUBY
      class MyObj
        def value
          42
        end
      end
      o = MyObj.new
      r = o.value
    RUBY
    hm, env = infer_with_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :r)
  end

  def test_class_hierarchy_walk
    code = <<~RUBY
      class Animal
        def sound
          "generic"
        end
      end
      class Dog < Animal
      end
      d = Dog.new
      s = d.sound
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::STRING, var_type(hm, env, :s)
  end

  def test_error_after_all_sources_exhausted
    code = <<~RUBY
      def process(x)
        x.nonexistent_method_qqq
      end
    RUBY
    jvm = {
      "SomeClass" => {
        jvm_internal_name: "com/test/SomeClass",
        static_methods: {},
        methods: { "other_method" => { params: [], return: :i64 } },
        constructor_params: []
      }
    }
    hm, _env = infer_with_jvm(code, jvm_classes: jvm)
    assert hm.inference_errors.any?, "Should have error even with JVM classes loaded"
  end

  def test_hm_resolves_then_rbs_refines
    # Simple arithmetic: HM resolves it, RBS refines if present
    code = <<~RUBY
      def compute(a, b)
        a * b + 10
      end
      result = compute(5, 3)
    RUBY
    hm, env = infer_with_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_self_call_resolved_first
    code = <<~RUBY
      def helper
        42
      end
      def main
        helper
      end
      result = main
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :result)
  end

  def test_resolution_order_user_class_before_rbs
    # User-defined class method should be found before RBS singleton lookup
    code = <<~RUBY
      class MyList
        def length
          0
        end
      end
      l = MyList.new
      n = l.length
    RUBY
    hm, env = infer_no_rbs(code)
    assert_equal Types::INTEGER, var_type(hm, env, :n)
  end

  # ══════════════════════════════════════════════════════════════════
  # Category N: Descriptor Parsing & Name Conversion
  # ══════════════════════════════════════════════════════════════════

  def test_parse_descriptor_int_params
    loader = Konpeito::TypeChecker::RBSLoader.new
    params = loader.send(:parse_callback_descriptor_params, "(II)V")
    assert_equal [:i64, :i64], params
  end

  def test_parse_descriptor_double_params
    loader = Konpeito::TypeChecker::RBSLoader.new
    params = loader.send(:parse_callback_descriptor_params, "(DD)D")
    assert_equal [:double, :double], params
  end

  def test_parse_descriptor_long_params
    loader = Konpeito::TypeChecker::RBSLoader.new
    params = loader.send(:parse_callback_descriptor_params, "(JJ)J")
    assert_equal [:i64, :i64], params
  end

  def test_parse_descriptor_string_param
    loader = Konpeito::TypeChecker::RBSLoader.new
    params = loader.send(:parse_callback_descriptor_params, "(Ljava/lang/String;)V")
    assert_equal [:string], params
  end

  def test_parse_descriptor_mixed
    loader = Konpeito::TypeChecker::RBSLoader.new
    params = loader.send(:parse_callback_descriptor_params, "(IJDLjava/lang/String;Z)V")
    assert_equal [:i64, :i64, :double, :string, :i8], params
  end

  def test_parse_descriptor_return_void
    loader = Konpeito::TypeChecker::RBSLoader.new
    ret = loader.send(:parse_callback_descriptor_return, "(II)V")
    assert_equal :void, ret
  end

  def test_parse_descriptor_return_double
    loader = Konpeito::TypeChecker::RBSLoader.new
    ret = loader.send(:parse_callback_descriptor_return, "(DD)D")
    assert_equal :double, ret
  end

  def test_parse_descriptor_return_string
    loader = Konpeito::TypeChecker::RBSLoader.new
    ret = loader.send(:parse_callback_descriptor_return, "()Ljava/lang/String;")
    assert_equal :string, ret
  end

  def test_camel_to_snake
    loader = Konpeito::TypeChecker::RBSLoader.new
    assert_equal "get_value", loader.send(:camel_to_snake, "getValue")
    assert_equal "set_background", loader.send(:camel_to_snake, "setBackground")
    assert_equal "to_string", loader.send(:camel_to_snake, "toString")
  end

  def test_snake_to_camel
    loader = Konpeito::TypeChecker::RBSLoader.new
    assert_equal "getValue", loader.send(:snake_to_camel, "get_value")
    assert_equal "setBackground", loader.send(:snake_to_camel, "set_background")
    assert_equal "toString", loader.send(:snake_to_camel, "to_string")
  end
end
