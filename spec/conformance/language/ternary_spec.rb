require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/if_spec.rb (ternary operator section)

# Ternary with true condition
def test_ternary_true_returns_then_value
  result = true ? "then" : "else"
  assert_equal("then", result, "ternary with true returns then value")
end

# Ternary with false condition
def test_ternary_false_returns_else_value
  result = false ? "then" : "else"
  assert_equal("else", result, "ternary with false returns else value")
end

# Ternary with nil condition
def test_ternary_nil_returns_else_value
  result = nil ? "then" : "else"
  assert_equal("else", result, "ternary with nil returns else value")
end

# Truthiness: 0 is truthy in Ruby
def test_ternary_zero_is_truthy
  result = 0 ? "truthy" : "falsy"
  assert_equal("truthy", result, "ternary with 0 is truthy")
end

# Truthiness: empty string is truthy in Ruby
def test_ternary_empty_string_is_truthy
  result = "" ? "truthy" : "falsy"
  assert_equal("truthy", result, "ternary with empty string is truthy")
end

# Truthiness: empty array is truthy in Ruby
def test_ternary_empty_array_is_truthy
  result = [] ? "truthy" : "falsy"
  assert_equal("truthy", result, "ternary with empty array is truthy")
end

# Ternary with comparison expression as condition
def test_ternary_with_comparison_expression
  x = 10
  result = x > 5 ? "big" : "small"
  assert_equal("big", result, "ternary with comparison expression evaluates correctly")
end

# Nested ternary
def test_nested_ternary
  x = 2
  result = x == 1 ? "one" : (x == 2 ? "two" : "other")
  assert_equal("two", result, "nested ternary evaluates correctly")
end

# Ternary as method argument
def test_ternary_as_method_argument
  arr = [1, 2, 3]
  arr.push(true ? 4 : 5)
  assert_equal(4, arr[3], "ternary as method argument evaluates correctly")
end

# Ternary with arithmetic expressions in branches
def test_ternary_with_expressions_in_branches
  a = 3
  b = 7
  result = a < b ? a + b : a - b
  assert_equal(10, result, "ternary evaluates expression in selected branch")
end

def run_tests
  spec_reset
  test_ternary_true_returns_then_value
  test_ternary_false_returns_else_value
  test_ternary_nil_returns_else_value
  test_ternary_zero_is_truthy
  test_ternary_empty_string_is_truthy
  test_ternary_empty_array_is_truthy
  test_ternary_with_comparison_expression
  test_nested_ternary
  test_ternary_as_method_argument
  test_ternary_with_expressions_in_branches
  spec_summary
end

run_tests
