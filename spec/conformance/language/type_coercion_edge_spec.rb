require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/*/to_* - type coercion edge cases

# nil coercions
def test_nil_to_a
  result = nil.to_a
  assert_equal(0, result.length, "nil.to_a returns empty array")
end

def test_nil_to_s
  assert_equal("", nil.to_s, "nil.to_s returns empty string")
end

def test_nil_to_i
  assert_equal(0, nil.to_i, "nil.to_i returns 0")
end

def test_nil_to_f
  assert_true(nil.to_f == 0.0, "nil.to_f returns 0.0")
end

# String to numeric coercions
def test_string_to_i_valid
  assert_equal(42, "42".to_i, "String#to_i converts valid integer string")
end

def test_string_to_i_invalid
  assert_equal(0, "abc".to_i, "String#to_i returns 0 for non-numeric string")
end

def test_string_to_i_partial
  assert_equal(123, "123abc".to_i, "String#to_i converts leading digits")
end

def test_string_to_f_valid
  assert_true("3.14".to_f == 3.14, "String#to_f converts valid float string")
end

def test_string_to_f_invalid
  assert_true("abc".to_f == 0.0, "String#to_f returns 0.0 for non-numeric string")
end

# Boolean coercions with !!
def test_double_bang_truthy
  assert_true(!!42, "!!42 is true")
  assert_true(!!"hello", "!!string is true")
  assert_true(!![1], "!!array is true")
  assert_true(!!true, "!!true is true")
end

def test_double_bang_falsy
  assert_false(!!nil, "!!nil is false")
  assert_false(!!false, "!!false is false")
end

# Integer() strict conversion
def test_integer_conversion_valid
  assert_equal(42, Integer("42"), "Integer('42') returns 42")
  assert_equal(0, Integer("0"), "Integer('0') returns 0")
  assert_equal(-5, Integer("-5"), "Integer('-5') returns -5")
end

# Float() strict conversion
def test_float_conversion_valid
  assert_true(Float("3.14") == 3.14, "Float('3.14') returns 3.14")
  assert_true(Float("0") == 0.0, "Float('0') returns 0.0")
end

# to_s on various types
def test_to_s_conversions
  assert_equal("42", 42.to_s, "Integer#to_s converts to string")
  assert_equal("3.14", 3.14.to_s, "Float#to_s converts to string")
  assert_equal("true", true.to_s, "true.to_s returns 'true'")
  assert_equal("false", false.to_s, "false.to_s returns 'false'")
  assert_equal("hello", :hello.to_s, "Symbol#to_s returns string")
end

def run_tests
  spec_reset
  test_nil_to_a
  test_nil_to_s
  test_nil_to_i
  test_nil_to_f
  test_string_to_i_valid
  test_string_to_i_invalid
  test_string_to_i_partial
  test_string_to_f_valid
  test_string_to_f_invalid
  test_double_bang_truthy
  test_double_bang_falsy
  test_integer_conversion_valid
  test_float_conversion_valid
  test_to_s_conversions
  spec_summary
end

run_tests
