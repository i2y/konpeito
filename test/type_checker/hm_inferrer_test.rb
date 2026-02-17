# frozen_string_literal: true

require "test_helper"
require "prism"

class HMInferrerTest < Minitest::Test
  def setup
    @rbs_loader = Konpeito::TypeChecker::RBSLoader.new.load
  end

  def infer(code)
    ast = Prism.parse(code).value
    hm = Konpeito::TypeChecker::HMInferrer.new(@rbs_loader)
    hm.analyze(ast)
    [hm, hm.instance_variable_get(:@env).first]
  end

  def test_integer_literal
    hm, env = infer("x = 42")
    assert_equal Konpeito::TypeChecker::Types::INTEGER, hm.finalize(env[:x].type)
  end

  def test_float_literal
    hm, env = infer("x = 3.14")
    assert_equal Konpeito::TypeChecker::Types::FLOAT, hm.finalize(env[:x].type)
  end

  def test_string_literal
    hm, env = infer("x = 'hello'")
    assert_equal Konpeito::TypeChecker::Types::STRING, hm.finalize(env[:x].type)
  end

  def test_array_of_integers
    hm, env = infer("arr = [1, 2, 3]")
    type = hm.finalize(env[:arr].type)
    assert_equal :Array, type.name
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type.type_args.first
  end

  def test_hash_of_string_to_integer
    hm, env = infer('h = { "a" => 1 }')
    type = hm.finalize(env[:h].type)
    assert_equal :Hash, type.name
    assert_equal Konpeito::TypeChecker::Types::STRING, type.type_args[0]
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type.type_args[1]
  end

  def test_function_type_inference
    code = <<-RUBY
      def add_one(x)
        x + 1
      end
      result = add_one(5)
    RUBY
    hm, env = infer(code)

    # Function type should be (Integer) -> Integer
    func_types = hm.instance_variable_get(:@function_types)
    func_type = hm.finalize(func_types[:add_one])
    assert_equal "(Integer) -> Integer", func_type.to_s

    # Result should be Integer
    assert_equal Konpeito::TypeChecker::Types::INTEGER, hm.finalize(env[:result].type)
  end

  def test_array_first_polymorphic
    hm, env = infer("arr = [1, 2, 3]; x = arr.first")
    assert_equal Konpeito::TypeChecker::Types::INTEGER, hm.finalize(env[:x].type)
  end

  def test_array_map_polymorphic
    code = <<-RUBY
      arr = [1, 2, 3]
      doubled = arr.map { |x| x * 2 }
    RUBY
    hm, env = infer(code)

    type = hm.finalize(env[:doubled].type)
    assert_equal :Array, type.name
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type.type_args.first
  end

  def test_array_map_type_transform
    code = <<-RUBY
      arr = [1, 2, 3]
      strings = arr.map { |x| x.to_s }
    RUBY
    hm, env = infer(code)

    type = hm.finalize(env[:strings].type)
    assert_equal :Array, type.name
    assert_equal Konpeito::TypeChecker::Types::STRING, type.type_args.first
  end

  def test_hash_keys_polymorphic
    hm, env = infer('h = { "a" => 1 }; k = h.keys')
    type = hm.finalize(env[:k].type)
    assert_equal :Array, type.name
    assert_equal Konpeito::TypeChecker::Types::STRING, type.type_args.first
  end

  def test_hash_values_polymorphic
    hm, env = infer('h = { "a" => 1 }; v = h.values')
    type = hm.finalize(env[:v].type)
    assert_equal :Array, type.name
    assert_equal Konpeito::TypeChecker::Types::INTEGER, type.type_args.first
  end

  def test_overload_resolution_integer_times_integer
    hm, env = infer("x = 5 * 2")
    assert_equal Konpeito::TypeChecker::Types::INTEGER, hm.finalize(env[:x].type)
  end

  def test_overload_resolution_integer_times_float
    hm, env = infer("x = 5 * 2.0")
    assert_equal Konpeito::TypeChecker::Types::FLOAT, hm.finalize(env[:x].type)
  end

  def test_identity_function_polymorphic
    code = <<-RUBY
      def identity(x)
        x
      end
      a = identity(42)
      b = identity("hello")
    RUBY
    hm, env = infer(code)

    # identity is polymorphic: (τ1) -> τ1
    # But when called, types should be instantiated
    assert_equal Konpeito::TypeChecker::Types::INTEGER, hm.finalize(env[:a].type)
    assert_equal Konpeito::TypeChecker::Types::STRING, hm.finalize(env[:b].type)
  end

  # ==============================================
  # Overload resolution: RBS alias (::int, ::string) handling
  # ==============================================

  def test_overload_array_index_assignment
    # Array#[]= has overloads with ::int (RBS alias) as first param.
    # The correct overload (int, Elem) should be selected over (Range, Array).
    code = <<-RUBY
      arr = [nil, nil, nil]
      arr[0] = [1, 2]
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  # ==============================================
  # Literal type compatibility
  # ==============================================

  def test_integer_literal_compatible_with_integer
    # Integer literals (e.g., from <=>) should be compatible with Integer
    code = <<-RUBY
      def compare(a, b)
        cmp = (a <=> b)
        if cmp == nil
          cmp = 0
        end
        cmp
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  def test_string_literal_type
    # String literal values should be compatible with String
    hm, env = infer('x = "hello"')
    assert_equal Konpeito::TypeChecker::Types::STRING, hm.finalize(env[:x].type)
    assert_empty hm.errors
  end

  # ==============================================
  # Flow-sensitive type narrowing tests
  # ==============================================

  def test_narrowing_simple_truthy
    # Simple truthiness check: `if x` should narrow x to non-nil in then-branch
    code = <<-RUBY
      def process(x)
        if x
          x.to_s
        else
          "default"
        end
      end
    RUBY
    hm, _env = infer(code)
    # Should compile without errors
    assert_empty hm.errors
  end

  def test_narrowing_equal_nil
    # `if x == nil` should narrow x to nil in then-branch, non-nil in else
    code = <<-RUBY
      def process(x)
        if x == nil
          "is nil"
        else
          x.to_s
        end
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  def test_narrowing_not_equal_nil
    # `if x != nil` should narrow x to non-nil in then-branch
    code = <<-RUBY
      def safe_length(str)
        if str != nil
          str.length
        else
          0
        end
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  def test_narrowing_nil_method
    # `if x.nil?` should narrow x to nil in then-branch, non-nil in else
    code = <<-RUBY
      def check(val)
        if val.nil?
          "nil"
        else
          val.to_s
        end
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  def test_narrowing_and_operator
    # `if a && b` should narrow both a and b to non-nil in then-branch
    code = <<-RUBY
      def both_present(a, b)
        if a && b
          a.to_s + b.to_s
        else
          "missing"
        end
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  def test_narrowing_or_operator
    # `if a || b` - conservative approach: no narrowing in either branch
    code = <<-RUBY
      def either_present(a, b)
        if a || b
          "one exists"
        else
          "neither"
        end
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  def test_narrowing_reversed_nil_comparison
    # `if nil == x` should work the same as `if x == nil`
    code = <<-RUBY
      def process(x)
        if nil == x
          "is nil"
        else
          x.to_s
        end
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end

  def test_narrowing_nested_conditions
    # Nested conditions should work correctly
    code = <<-RUBY
      def process(a, b)
        if a
          if b
            a.to_s + b.to_s
          else
            a.to_s
          end
        else
          "no a"
        end
      end
    RUBY
    hm, _env = infer(code)
    assert_empty hm.errors
  end
end
