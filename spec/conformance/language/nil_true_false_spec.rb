require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/nil_class/*, core/true_class/*, core/false_class/*

# NilClass (core/nil_class/*)
def test_nil_equal_nil
  assert_true(nil == nil, "nil == nil is true")
end

def test_nil_not_equal_false
  assert_false(nil == false, "nil == false is false")
end

def test_nil_not_equal_zero
  assert_false(nil == 0, "nil == 0 is false")
end

def test_nil_to_s
  assert_equal("", nil.to_s, "nil.to_s returns empty string")
end

def test_nil_to_a
  result = nil.to_a
  assert_equal(0, result.length, "nil.to_a returns empty array")
end

def test_nil_inspect
  assert_equal("nil", nil.inspect, "nil.inspect returns 'nil'")
end

def test_nil_nil?
  assert_true(nil.nil?, "nil.nil? returns true")
end

def test_nil_falsy
  result = nil ? "truthy" : "falsy"
  assert_equal("falsy", result, "nil is falsy in conditional")
end

# TrueClass (core/true_class/*)
def test_true_equal_true
  assert_true(true == true, "true == true is true")
end

def test_true_not_equal_false
  assert_false(true == false, "true == false is false")
end

def test_true_to_s
  assert_equal("true", true.to_s, "true.to_s returns 'true'")
end

def test_true_inspect
  assert_equal("true", true.inspect, "true.inspect returns 'true'")
end

def test_true_nil?
  assert_false(true.nil?, "true.nil? returns false")
end

def test_true_truthy
  result = true ? "truthy" : "falsy"
  assert_equal("truthy", result, "true is truthy in conditional")
end

# FalseClass (core/false_class/*)
def test_false_equal_false
  assert_true(false == false, "false == false is true")
end

def test_false_not_equal_true
  assert_false(false == true, "false == true is false")
end

def test_false_not_equal_nil
  assert_false(false == nil, "false == nil is false")
end

def test_false_to_s
  assert_equal("false", false.to_s, "false.to_s returns 'false'")
end

def test_false_inspect
  assert_equal("false", false.inspect, "false.inspect returns 'false'")
end

def test_false_nil?
  assert_false(false.nil?, "false.nil? returns false")
end

def test_false_falsy
  result = false ? "truthy" : "falsy"
  assert_equal("falsy", result, "false is falsy in conditional")
end

# Logical operations with nil/true/false
def test_nil_and_true
  result = nil && true
  assert_nil(result, "nil && true returns nil")
end

def test_true_and_nil
  result = true && nil
  assert_nil(result, "true && nil returns nil")
end

def test_false_or_true
  result = false || true
  assert_true(result == true, "false || true returns true")
end

def test_nil_or_value
  result = nil || 42
  assert_equal(42, result, "nil || 42 returns 42")
end

def run_tests
  spec_reset
  test_nil_equal_nil
  test_nil_not_equal_false
  test_nil_not_equal_zero
  test_nil_to_s
  test_nil_to_a
  test_nil_inspect
  test_nil_nil?
  test_nil_falsy
  test_true_equal_true
  test_true_not_equal_false
  test_true_to_s
  test_true_inspect
  test_true_nil?
  test_true_truthy
  test_false_equal_false
  test_false_not_equal_true
  test_false_not_equal_nil
  test_false_to_s
  test_false_inspect
  test_false_nil?
  test_false_falsy
  test_nil_and_true
  test_true_and_nil
  test_false_or_true
  test_nil_or_value
  spec_summary
end

run_tests
