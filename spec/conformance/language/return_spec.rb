require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/return_spec.rb

# Helper methods for return tests

def return_with_value
  return 1
end

def return_without_value
  return
end

def return_stops_execution
  return 42
  999
end

def return_with_expression(x)
  return x * 3 + 1
end

def return_from_if_true(x)
  if x > 0
    return "positive"
  end
  "non-positive"
end

def return_from_if_else(x)
  if x > 0
    return "positive"
  else
    return "non-positive"
  end
end

def return_from_while
  i = 0
  while i < 10
    if i == 5
      return i
    end
    i = i + 1
  end
  -1
end

def return_multiple_early(x)
  if x < 0
    return "negative"
  end
  if x == 0
    return "zero"
  end
  if x < 10
    return "small"
  end
  "large"
end

def implicit_return_integer
  42
end

def implicit_return_string
  "hello"
end

def implicit_return_nil_method
  x = 1
  nil
end

def return_single_element_array
  return [1]
end

def return_multi_element_array
  return [1, 2, 3]
end

# Tests

def test_return_returns_object_directly
  assert_equal(1, return_with_value, "return returns any object directly")
end

def test_return_returns_nil_by_default
  assert_nil(return_without_value, "return returns nil by default")
end

def test_return_stops_method_execution
  assert_equal(42, return_stops_execution, "return ends method execution, code after return is not executed")
end

def test_return_with_expression
  assert_equal(16, return_with_expression(5), "return evaluates and returns the expression")
end

def test_return_from_if_when_true
  assert_equal("positive", return_from_if_true(5), "return from within if body when condition is true")
end

def test_return_from_if_falls_through
  assert_equal("non-positive", return_from_if_true(-1), "method continues past if when condition is false")
end

def test_return_from_if_else_branches
  assert_equal("positive", return_from_if_else(5), "return from if branch")
  assert_equal("non-positive", return_from_if_else(-1), "return from else branch")
end

def test_return_from_while_loop
  assert_equal(5, return_from_while, "return exits the while loop and the method")
end

def test_return_multiple_early_returns
  assert_equal("negative", return_multiple_early(-5), "early return for negative")
  assert_equal("zero", return_multiple_early(0), "early return for zero")
  assert_equal("small", return_multiple_early(7), "early return for small positive")
  assert_equal("large", return_multiple_early(100), "falls through all guards to final expression")
end

def test_implicit_return_last_expression
  assert_equal(42, implicit_return_integer, "implicit return returns the last expression (integer)")
  assert_equal("hello", implicit_return_string, "implicit return returns the last expression (string)")
end

def test_implicit_return_nil
  assert_nil(implicit_return_nil_method, "implicit return returns nil when last expression is nil")
end

def test_return_single_element_array
  result = return_single_element_array
  assert_equal(1, result.length, "return returns a single element array directly")
  assert_equal(1, result[0], "return returns the array with correct element")
end

def test_return_multi_element_array
  result = return_multi_element_array
  assert_equal(3, result.length, "return returns a multi element array directly")
  assert_equal(1, result[0], "return multi element array first element")
  assert_equal(3, result[2], "return multi element array last element")
end

def run_tests
  spec_reset
  test_return_returns_object_directly
  test_return_returns_nil_by_default
  test_return_stops_method_execution
  test_return_with_expression
  test_return_from_if_when_true
  test_return_from_if_falls_through
  test_return_from_if_else_branches
  test_return_from_while_loop
  test_return_multiple_early_returns
  test_implicit_return_last_expression
  test_implicit_return_nil
  test_return_single_element_array
  test_return_multi_element_array
  spec_summary
end

run_tests
