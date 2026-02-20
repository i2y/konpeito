require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/safe_navigator_spec.rb

# &. on non-nil receiver
def test_safe_nav_calls_method_on_non_nil
  str = "hello"
  result = str&.upcase
  assert_equal("HELLO", result, "&. calls the method when receiver is non-nil")
end

def test_safe_nav_returns_result
  arr = [1, 2, 3]
  result = arr&.length
  assert_equal(3, result, "&. returns the method result for non-nil receiver")
end

# &. on nil receiver
def test_safe_nav_returns_nil_for_nil_receiver
  x = nil
  result = x&.upcase
  assert_nil(result, "&. returns nil when receiver is nil")
end

def test_safe_nav_does_not_call_method_on_nil
  x = nil
  result = x&.length
  assert_nil(result, "&. does not call the method when receiver is nil")
end

# &. chaining
def test_safe_nav_chain_non_nil
  str = "hello"
  result = str&.upcase&.reverse
  assert_equal("OLLEH", result, "&. can be chained on non-nil values")
end

def test_safe_nav_chain_first_nil
  x = nil
  result = x&.upcase&.reverse
  assert_nil(result, "&. chain returns nil when first receiver is nil")
end

# &. with different types
def test_safe_nav_integer_method
  n = 42
  result = n&.to_s
  assert_equal("42", result, "&. works with Integer receiver")
end

def test_safe_nav_array_method
  arr = [3, 1, 2]
  result = arr&.first
  assert_equal(3, result, "&. works with Array#first")
end

def run_tests
  spec_reset
  test_safe_nav_calls_method_on_non_nil
  test_safe_nav_returns_result
  test_safe_nav_returns_nil_for_nil_receiver
  test_safe_nav_does_not_call_method_on_nil
  test_safe_nav_chain_non_nil
  test_safe_nav_chain_first_nil
  test_safe_nav_integer_method
  test_safe_nav_array_method
  spec_summary
end

run_tests
