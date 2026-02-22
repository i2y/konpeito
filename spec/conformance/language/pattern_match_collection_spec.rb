require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/pattern_matching_spec.rb - collection patterns
# Tests array patterns, hash patterns, rest patterns, and nested patterns

# Array pattern basics
def test_array_pattern_two_elements
  result = case [10, 20]
  in [a, b] then a + b
  else 0
  end
  assert_equal(30, result, "array pattern [a, b] matches two-element array")
end

def test_array_pattern_three_elements
  result = case [1, 2, 3]
  in [a, b, c] then a + b + c
  else 0
  end
  assert_equal(6, result, "array pattern [a, b, c] matches three-element array")
end

def test_array_pattern_length_mismatch
  result = case [1, 2, 3]
  in [a, b] then "two"
  in [a, b, c] then "three"
  else "other"
  end
  assert_equal("three", result, "array pattern skips when length does not match")
end

# Array pattern with rest
def test_array_pattern_rest
  result = case [1, 2, 3, 4, 5]
  in [first, *rest] then first
  else 0
  end
  assert_equal(1, result, "array pattern [first, *rest] captures first element")
end

def test_array_pattern_rest_length
  rest_arr = nil
  case [1, 2, 3, 4, 5]
  in [first, *rest] then rest_arr = rest
  end
  assert_equal(4, rest_arr.length, "rest captures remaining elements")
  assert_equal(2, rest_arr[0], "rest first element is second of original")
end

def test_array_pattern_first_and_last
  result = case [1, 2, 3, 4, 5]
  in [first, *mid, last] then first + last
  else 0
  end
  assert_equal(6, result, "array pattern [first, *mid, last] captures first and last")
end

# Hash pattern
def test_hash_pattern_shorthand
  result = case {name: "Alice", age: 30}
  in {name:} then name
  else "unknown"
  end
  assert_equal("Alice", result, "hash pattern {name:} captures value for key")
end

def test_hash_pattern_multiple_keys
  result = case {x: 10, y: 20}
  in {x:, y:} then x + y
  else 0
  end
  assert_equal(30, result, "hash pattern {x:, y:} captures multiple values")
end

# Nested patterns
def test_nested_array_in_array
  result = case [[1, 2], [3, 4]]
  in [[a, b], [c, d]] then a + b + c + d
  else 0
  end
  assert_equal(10, result, "nested array pattern matches inner arrays")
end

def run_tests
  spec_reset
  test_array_pattern_two_elements
  test_array_pattern_three_elements
  test_array_pattern_length_mismatch
  test_array_pattern_rest
  test_array_pattern_rest_length
  test_array_pattern_first_and_last
  test_hash_pattern_shorthand
  test_hash_pattern_multiple_keys
  test_nested_array_in_array
  spec_summary
end

run_tests
