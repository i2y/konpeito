require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/percent_literal_spec.rb

def test_percent_w_creates_string_array
  arr = %w[foo bar baz]
  assert_equal(3, arr.length, "%w creates array with 3 elements")
  assert_equal("foo", arr[0], "%w first element is string")
  assert_equal("bar", arr[1], "%w second element is string")
  assert_equal("baz", arr[2], "%w third element is string")
end

def test_percent_i_creates_symbol_array
  arr = %i[foo bar baz]
  assert_equal(3, arr.length, "%i creates array with 3 elements")
  assert_equal(:foo, arr[0], "%i first element is symbol")
  assert_equal(:bar, arr[1], "%i second element is symbol")
  assert_equal(:baz, arr[2], "%i third element is symbol")
end

def test_percent_w_empty
  arr = %w[]
  assert_equal(0, arr.length, "%w[] creates empty array")
end

def test_percent_i_empty
  arr = %i[]
  assert_equal(0, arr.length, "%i[] creates empty array")
end

def test_percent_w_single_element
  arr = %w[hello]
  assert_equal(1, arr.length, "%w with single element has length 1")
  assert_equal("hello", arr[0], "%w single element value")
end

def test_percent_i_single_element
  arr = %i[hello]
  assert_equal(1, arr.length, "%i with single element has length 1")
  assert_equal(:hello, arr[0], "%i single element value")
end

def run_tests
  spec_reset
  test_percent_w_creates_string_array
  test_percent_i_creates_symbol_array
  test_percent_w_empty
  test_percent_i_empty
  test_percent_w_single_element
  test_percent_i_single_element
  spec_summary
end

run_tests
