require_relative "../lib/konpeito_spec"

def test_plus_equals_integer
  x = 2
  x += 5
  assert_equal(7, x, "+= adds and assigns for integers")
end

def test_plus_equals_string
  x = "hello"
  x += " world"
  assert_equal("hello world", x, "+= concatenates and assigns for strings")
end

def test_minus_equals_integer
  x = 10
  x -= 3
  assert_equal(7, x, "-= subtracts and assigns for integers")
end

def test_multiply_equals_integer
  x = 4
  x *= 3
  assert_equal(12, x, "*= multiplies and assigns for integers")
end

def test_divide_equals_integer
  x = 20
  x /= 5
  assert_equal(4, x, "/= divides and assigns for integers")
end

def test_modulo_equals_integer
  x = 17
  x %= 5
  assert_equal(2, x, "%= computes modulo and assigns for integers")
end

def test_exponent_equals_integer
  x = 2
  x **= 10
  assert_equal(1024, x, "**= raises to power and assigns for integers")
end

def test_or_equals_nil
  x = nil
  x ||= 42
  assert_equal(42, x, "||= assigns when variable is nil")
end

def test_or_equals_false
  x = false
  x ||= 42
  assert_equal(42, x, "||= assigns when variable is false")
end

def test_or_equals_truthy
  x = 10
  x ||= 42
  assert_equal(10, x, "||= does not assign when variable is truthy")
end

def test_and_equals_nil
  x = nil
  x &&= 42
  assert_nil(x, "&&= does not assign when variable is nil")
end

def test_and_equals_false
  x = false
  x &&= 42
  assert_false(x, "&&= does not assign when variable is false")
end

def test_and_equals_truthy
  x = 10
  x &&= 42
  assert_equal(42, x, "&&= assigns when variable is truthy")
end

def test_compound_returns_assigned_value
  x = 5
  result = (x += 3)
  assert_equal(8, result, "compound assignment returns the assigned value")
  assert_equal(8, x, "compound assignment updates the variable")
end

def run_tests
  spec_reset
  test_plus_equals_integer
  test_plus_equals_string
  test_minus_equals_integer
  test_multiply_equals_integer
  test_divide_equals_integer
  test_modulo_equals_integer
  test_exponent_equals_integer
  test_or_equals_nil
  test_or_equals_false
  test_or_equals_truthy
  test_and_equals_nil
  test_and_equals_false
  test_and_equals_truthy
  test_compound_returns_assigned_value
  spec_summary
end

run_tests
