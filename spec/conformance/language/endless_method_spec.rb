require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/def_spec.rb (endless method)

def em_square(x) = x * x

def em_add(a, b) = a + b

def em_hello = "hello"

def em_ternary(x) = x > 0 ? "positive" : "non-positive"

def em_string_op(s) = s + "!"

class EmCalc
  def double(x) = x * 2

  def name = "calculator"
end

def test_endless_method_basic
  assert_equal("hello", em_hello, "endless method returns expression value")
end

def test_endless_method_with_one_arg
  assert_equal(25, em_square(5), "endless method with argument works")
end

def test_endless_method_with_two_args
  assert_equal(7, em_add(3, 4), "endless method with two arguments works")
end

def test_endless_method_ternary
  assert_equal("positive", em_ternary(5), "endless method with ternary positive")
  assert_equal("non-positive", em_ternary(-1), "endless method with ternary non-positive")
end

def test_endless_method_string
  assert_equal("wow!", em_string_op("wow"), "endless method with string concatenation")
end

def test_endless_method_in_class
  c = EmCalc.new
  assert_equal(10, c.double(5), "endless method in class works")
end

def test_endless_method_no_args_in_class
  c = EmCalc.new
  assert_equal("calculator", c.name, "endless method with no args in class works")
end

def run_tests
  spec_reset
  test_endless_method_basic
  test_endless_method_with_one_arg
  test_endless_method_with_two_args
  test_endless_method_ternary
  test_endless_method_string
  test_endless_method_in_class
  test_endless_method_no_args_in_class
  spec_summary
end

run_tests
