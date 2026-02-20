require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/string_spec.rb (interpolation section)

def test_interpolation_with_variable
  name = "world"
  result = "Hello, #{name}!"
  assert_equal("Hello, world!", result, "gets interpolated with \#{} when put in double quotes")
end

def test_interpolation_with_integer
  n = 42
  result = "The number is #{n}"
  assert_equal("The number is 42", result, "calls #to_s when the object is not a String (Integer)")
end

def test_interpolation_with_expression
  result = "Sum: #{3 + 4}"
  assert_equal("Sum: 7", result, "evaluates expressions inside \#{}")
end

def test_interpolation_with_multiple_expressions
  a = "x"
  b = "y"
  result = "#{a} and #{b}"
  assert_equal("x and y", result, "interpolates multiple expressions in one string")
end

def test_interpolation_empty_expression
  result = "a#{""}b"
  assert_equal("ab", result, "permits an empty expression")
end

def test_interpolation_with_method_call
  result = "Length: #{"hello".length}"
  assert_equal("Length: 5", result, "evaluates method calls inside interpolation")
end

def test_interpolation_with_boolean
  result = "Value: #{true}"
  assert_equal("Value: true", result, "calls #to_s for true")
  result2 = "Value: #{false}"
  assert_equal("Value: false", result2, "calls #to_s for false")
end

def test_interpolation_with_nil
  result = "Value: #{nil}"
  assert_equal("Value: ", result, "calls #to_s for nil (returns empty string)")
end

def test_interpolation_nested_string
  inner = "world"
  result = "Hello, #{inner + "!!"}"
  assert_equal("Hello, world!!", result, "handles nested string operations in interpolation")
end

def test_interpolation_with_float
  result = "Pi: #{3.14}"
  assert_equal("Pi: 3.14", result, "calls #to_s for Float")
end

def run_tests
  spec_reset
  test_interpolation_with_variable
  test_interpolation_with_integer
  test_interpolation_with_expression
  test_interpolation_with_multiple_expressions
  test_interpolation_empty_expression
  test_interpolation_with_method_call
  test_interpolation_with_boolean
  test_interpolation_with_nil
  test_interpolation_nested_string
  test_interpolation_with_float
  spec_summary
end

run_tests
