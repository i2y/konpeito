require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/method_spec.rb keyword arguments section

# Helper methods for keyword argument tests

def kw_required(name:)
  name
end

def kw_optional(name: "default")
  name
end

def kw_multiple_required(first:, last:)
  first + " " + last
end

def kw_multiple_optional(x: 1, y: 2, z: 3)
  x + y + z
end

def kw_mixed_required_optional(name:, greeting: "Hello")
  greeting + ", " + name
end

def kw_positional_and_keyword(a, b, name: "world")
  a.to_s + " " + b.to_s + " " + name
end

def kw_positional_default_and_keyword(a, b = 10, label: "sum")
  label + "=" + (a + b).to_s
end

def kw_integer_defaults(x: 0, y: 0)
  x + y
end

def kw_returns_keyword_value(value: 42)
  value
end

# Tests

def test_required_keyword_argument
  result = kw_required(name: "Alice")
  assert_equal("Alice", result, "required keyword argument receives the passed value")
end

def test_optional_keyword_uses_default
  result = kw_optional
  assert_equal("default", result, "optional keyword argument uses default when not provided")
end

def test_optional_keyword_overridden
  result = kw_optional(name: "custom")
  assert_equal("custom", result, "optional keyword argument uses passed value when provided")
end

def test_multiple_required_keywords
  result = kw_multiple_required(first: "John", last: "Doe")
  assert_equal("John Doe", result, "multiple required keyword arguments receive passed values")
end

def test_multiple_optional_keywords_all_defaults
  result = kw_multiple_optional
  assert_equal(6, result, "multiple optional keyword arguments all use defaults")
end

def test_multiple_optional_keywords_partial_override
  result = kw_multiple_optional(y: 20)
  assert_equal(24, result, "multiple optional keywords use defaults for unspecified and passed value for specified")
end

def test_mixed_required_and_optional_keywords
  result = kw_mixed_required_optional(name: "Bob")
  assert_equal("Hello, Bob", result, "mixed keywords use default for optional when only required is given")
end

def test_mixed_required_and_optional_keywords_both_provided
  result = kw_mixed_required_optional(name: "Bob", greeting: "Hi")
  assert_equal("Hi, Bob", result, "mixed keywords use passed values when both are provided")
end

def test_keyword_argument_order_does_not_matter
  result = kw_mixed_required_optional(greeting: "Hey", name: "Carol")
  assert_equal("Hey, Carol", result, "keyword arguments can be passed in any order")
end

def test_positional_and_keyword_arguments
  result = kw_positional_and_keyword(1, 2, name: "test")
  assert_equal("1 2 test", result, "positional and keyword arguments work together")
end

def test_positional_and_keyword_with_default
  result = kw_positional_and_keyword(1, 2)
  assert_equal("1 2 world", result, "keyword argument uses default when mixed with positional args")
end

def test_keyword_with_integer_values
  result = kw_integer_defaults(x: 10, y: 20)
  assert_equal(30, result, "keyword arguments work with integer values")
end

def run_tests
  spec_reset
  test_required_keyword_argument
  test_optional_keyword_uses_default
  test_optional_keyword_overridden
  test_multiple_required_keywords
  test_multiple_optional_keywords_all_defaults
  test_multiple_optional_keywords_partial_override
  test_mixed_required_and_optional_keywords
  test_mixed_required_and_optional_keywords_both_provided
  test_keyword_argument_order_does_not_matter
  test_positional_and_keyword_arguments
  test_positional_and_keyword_with_default
  test_keyword_with_integer_values
  spec_summary
end

run_tests
