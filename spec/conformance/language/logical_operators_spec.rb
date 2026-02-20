require_relative "../lib/konpeito_spec"

def test_and_true_true
  result = true && true
  assert_true(result, "true && true is true")
end

def test_and_true_false
  result = true && false
  assert_false(result, "true && false is false")
end

def test_and_false_true
  result = false && true
  assert_false(result, "false && true is false")
end

def test_and_false_false
  result = false && false
  assert_false(result, "false && false is false")
end

def test_or_true_true
  result = true || true
  assert_true(result, "true || true is true")
end

def test_or_true_false
  result = true || false
  assert_true(result, "true || false is true")
end

def test_or_false_true
  result = false || true
  assert_true(result, "false || true is true")
end

def test_or_false_false
  result = false || false
  assert_false(result, "false || false is false")
end

def test_and_short_circuit
  x = 1
  result = false && (x = 2)
  assert_equal(1, x, "&& short-circuits: x not assigned when left is false")
end

def test_or_short_circuit
  x = 1
  result = true || (x = 2)
  assert_equal(1, x, "|| short-circuits: x not assigned when left is true")
end

def test_and_returns_last_evaluated
  result = 5 && 10
  assert_equal(10, result, "&& returns right operand when left is truthy")
end

def test_and_returns_false_value
  result = nil && 10
  assert_nil(result, "&& returns nil when left is nil")
end

def test_or_returns_first_truthy
  result = nil || 42
  assert_equal(42, result, "|| returns right operand when left is falsy")
end

def test_or_returns_left_when_truthy
  result = 7 || 42
  assert_equal(7, result, "|| returns left operand when left is truthy")
end

def run_tests
  spec_reset
  test_and_true_true
  test_and_true_false
  test_and_false_true
  test_and_false_false
  test_or_true_true
  test_or_true_false
  test_or_false_true
  test_or_false_false
  test_and_short_circuit
  test_or_short_circuit
  test_and_returns_last_evaluated
  test_and_returns_false_value
  test_or_returns_first_truthy
  test_or_returns_left_when_truthy
  spec_summary
end

run_tests
