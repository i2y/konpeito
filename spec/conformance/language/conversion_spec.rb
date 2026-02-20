require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/integer/to_f_spec.rb, core/integer/to_s_spec.rb,
# core/integer/to_i_spec.rb, core/float/to_i_spec.rb, core/float/to_f_spec.rb,
# core/float/to_s_spec.rb, core/string/to_i_spec.rb, core/string/to_f_spec.rb,
# core/string/to_s_spec.rb, core/nil_class/to_i_spec.rb,
# core/nil_class/to_f_spec.rb, core/nil_class/to_s_spec.rb,
# core/nil_class/to_a_spec.rb, core/true_class/to_s_spec.rb,
# core/false_class/to_s_spec.rb

# Integer#to_f (core/integer/to_f_spec.rb)
def test_integer_to_f_returns_float
  assert_equal(0.0, 0.to_f, "Integer#to_f returns 0.0 for 0")
end

def test_integer_to_f_positive
  assert_equal(10.0, 10.to_f, "Integer#to_f returns 10.0 for 10")
end

def test_integer_to_f_negative
  assert_equal(-5.0, -5.to_f, "Integer#to_f returns -5.0 for -5")
end

# Integer#to_s (core/integer/to_s_spec.rb)
def test_integer_to_s_returns_string
  assert_equal("0", 0.to_s, "Integer#to_s returns '0' for 0")
end

def test_integer_to_s_positive
  assert_equal("42", 42.to_s, "Integer#to_s returns '42' for 42")
end

def test_integer_to_s_negative
  assert_equal("-100", -100.to_s, "Integer#to_s returns '-100' for -100")
end

# Integer#to_i (core/integer/to_i_spec.rb)
def test_integer_to_i_returns_self
  assert_equal(5, 5.to_i, "Integer#to_i returns self")
end

def test_integer_to_i_negative
  assert_equal(-3, -3.to_i, "Integer#to_i returns self for negative")
end

# Float#to_i (core/float/to_i_spec.rb)
def test_float_to_i_truncates_positive
  assert_equal(1, 1.9.to_i, "Float#to_i returns the truncated value for positive float")
end

def test_float_to_i_truncates_negative
  assert_equal(-1, -1.9.to_i, "Float#to_i returns the truncated value for negative float")
end

def test_float_to_i_zero
  assert_equal(0, 0.0.to_i, "Float#to_i returns 0 for 0.0")
end

def test_float_to_int_truncates
  assert_equal(1, 1.9.to_int, "Float#to_int returns the truncated value")
end

# Float#to_f (core/float/to_f_spec.rb)
def test_float_to_f_returns_self
  assert_equal(1.5, 1.5.to_f, "Float#to_f returns self")
end

def test_float_to_f_negative
  assert_equal(-3.14, -3.14.to_f, "Float#to_f returns self for negative float")
end

# Float#to_s (core/float/to_s_spec.rb)
def test_float_to_s_zero
  assert_equal("0.0", 0.0.to_s, "Float#to_s returns '0.0' for 0.0")
end

def test_float_to_s_negative_zero
  assert_equal("-0.0", -0.0.to_s, "Float#to_s returns '-0.0' for -0.0")
end

def test_float_to_s_positive
  assert_equal("1.5", 1.5.to_s, "Float#to_s returns '1.5' for 1.5")
end

# String#to_i (core/string/to_i_spec.rb)
def test_string_to_i_numeric
  assert_equal(123, "123".to_i, "String#to_i returns an Integer for a numeric string")
end

def test_string_to_i_negative
  assert_equal(-45, "-45".to_i, "String#to_i parses a negative numeric string")
end

def test_string_to_i_leading_whitespace
  assert_equal(123, "   123".to_i, "String#to_i ignores leading whitespace")
end

def test_string_to_i_non_numeric
  assert_equal(0, "abc".to_i, "String#to_i returns 0 for a non-numeric string")
end

def test_string_to_i_partial_numeric
  assert_equal(123, "123abc".to_i, "String#to_i parses leading numeric portion")
end

# String#to_f (core/string/to_f_spec.rb)
def test_string_to_f_numeric
  assert_equal(1.5, "1.5".to_f, "String#to_f returns a Float for a numeric string")
end

def test_string_to_f_negative
  assert_equal(-3.14, "-3.14".to_f, "String#to_f parses a negative float string")
end

def test_string_to_f_non_numeric
  assert_equal(0.0, "abc".to_f, "String#to_f returns 0.0 for a non-numeric string")
end

# String#to_s (core/string/to_s_spec.rb)
def test_string_to_s_returns_self
  assert_equal("hello", "hello".to_s, "String#to_s returns self")
end

# NilClass#to_i (core/nil_class/to_i_spec.rb)
def test_nil_to_i
  assert_equal(0, nil.to_i, "NilClass#to_i returns 0")
end

# NilClass#to_f (core/nil_class/to_f_spec.rb)
def test_nil_to_f
  assert_equal(0.0, nil.to_f, "NilClass#to_f returns 0.0")
end

# NilClass#to_s (core/nil_class/to_s_spec.rb)
def test_nil_to_s
  assert_equal("", nil.to_s, "NilClass#to_s returns an empty string")
end

# NilClass#to_a (core/nil_class/to_a_spec.rb)
def test_nil_to_a
  result = nil.to_a
  assert_equal(0, result.length, "NilClass#to_a returns an empty array")
end

# TrueClass#to_s (core/true_class/to_s_spec.rb)
def test_true_to_s
  assert_equal("true", true.to_s, "TrueClass#to_s returns 'true'")
end

# FalseClass#to_s (core/false_class/to_s_spec.rb)
def test_false_to_s
  assert_equal("false", false.to_s, "FalseClass#to_s returns 'false'")
end

def run_tests
  spec_reset
  test_integer_to_f_returns_float
  test_integer_to_f_positive
  test_integer_to_f_negative
  test_integer_to_s_returns_string
  test_integer_to_s_positive
  test_integer_to_s_negative
  test_integer_to_i_returns_self
  test_integer_to_i_negative
  test_float_to_i_truncates_positive
  test_float_to_i_truncates_negative
  test_float_to_i_zero
  test_float_to_int_truncates
  test_float_to_f_returns_self
  test_float_to_f_negative
  test_float_to_s_zero
  test_float_to_s_negative_zero
  test_float_to_s_positive
  test_string_to_i_numeric
  test_string_to_i_negative
  test_string_to_i_leading_whitespace
  test_string_to_i_non_numeric
  test_string_to_i_partial_numeric
  test_string_to_f_numeric
  test_string_to_f_negative
  test_string_to_f_non_numeric
  test_string_to_s_returns_self
  test_nil_to_i
  test_nil_to_f
  test_nil_to_s
  test_nil_to_a
  test_true_to_s
  test_false_to_s
  spec_summary
end

run_tests
