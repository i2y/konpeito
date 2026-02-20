require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/integer/* and core/float/*

# Integer arithmetic (core/integer/plus_spec.rb, minus_spec.rb, multiply_spec.rb, divide_spec.rb)
def test_integer_plus
  assert_equal(5, 2 + 3, "Integer#+ returns self plus the given Integer")
end

def test_integer_minus
  assert_equal(6, 10 - 4, "Integer#- returns self minus the given Integer")
end

def test_integer_multiply
  assert_equal(42, 6 * 7, "Integer#* returns self multiplied by the given Integer")
end

def test_integer_divide
  assert_equal(3, 15 / 4, "Integer#/ returns self divided by the given argument (integer division)")
  assert_equal(-2, -7 / 4, "Integer#/ supports dividing negative numbers (floor division)")
end

def test_integer_modulo
  assert_equal(1, 10 % 3, "Integer#% returns the modulus obtained from dividing self by the given argument")
  assert_equal(2, -7 % 3, "Integer#% follows Ruby's floor-division modulo semantics for negative numbers")
end

def test_integer_negative_arithmetic
  assert_equal(-2, -5 + 3, "Integer arithmetic with negative numbers")
  assert_equal(-8, -5 - 3, "Integer subtraction with negative numbers")
end

# Integer comparison (core/integer/gt_spec.rb, lt_spec.rb, gte_spec.rb, lte_spec.rb, shared/equal.rb)
def test_integer_comparison
  assert_true(5 > 3, "Integer#> returns true if self is greater than the given argument")
  assert_false(3 > 5, "Integer#> returns false if self is not greater")
  assert_true(3 < 5, "Integer#< returns true if self is less than the given argument")
  assert_false(5 < 3, "Integer#< returns false if self is not less")
  assert_true(5 >= 5, "Integer#>= returns true if self is greater than or equal to other")
  assert_true(6 >= 5, "Integer#>= returns true if self is greater")
  assert_true(5 <= 5, "Integer#<= returns true if self is less than or equal to other")
  assert_true(4 <= 5, "Integer#<= returns true if self is less")
  assert_true(5 == 5, "Integer#== returns true if self has the same value as other")
  assert_false(5 == 4, "Integer#== returns false for different values")
  assert_true(5 != 4, "Integer#!= returns true for different values")
  assert_false(5 != 5, "Integer#!= returns false for same values")
end

# Integer#abs (core/integer/shared/abs.rb)
def test_integer_abs
  assert_equal(5, (-5).abs, "Integer#abs returns self's absolute value for negative")
  assert_equal(5, 5.abs, "Integer#abs returns self for positive")
  assert_equal(0, 0.abs, "Integer#abs returns 0 for 0")
end

# Integer#even? (core/integer/even_spec.rb)
def test_integer_even
  assert_true(4.even?, "Integer#even? returns true for a positive even number")
  assert_true((-4).even?, "Integer#even? returns true for a negative even number")
  assert_false(3.even?, "Integer#even? returns false for a positive odd number")
  assert_false((-3).even?, "Integer#even? returns false for a negative odd number")
  assert_true(0.even?, "Integer#even? returns true for 0")
end

# Integer#odd? (core/integer/odd_spec.rb)
def test_integer_odd
  assert_true(3.odd?, "Integer#odd? returns true for a positive odd number")
  assert_true((-3).odd?, "Integer#odd? returns true for a negative odd number")
  assert_false(4.odd?, "Integer#odd? returns false for a positive even number")
  assert_false((-4).odd?, "Integer#odd? returns false for a negative even number")
  assert_false(0.odd?, "Integer#odd? returns false for 0")
end

# Integer#zero? (core/integer/zero_spec.rb)
def test_integer_zero
  assert_true(0.zero?, "Integer#zero? returns true if self is 0")
  assert_false(1.zero?, "Integer#zero? returns false if self is not 0")
  assert_false((-1).zero?, "Integer#zero? returns false for negative non-zero")
end

# Integer#positive? / Integer#negative?
def test_integer_positive_negative
  assert_true(5.positive?, "Integer#positive? returns true for positive")
  assert_false(0.positive?, "Integer#positive? returns false for zero")
  assert_false((-5).positive?, "Integer#positive? returns false for negative")
  assert_true((-3).negative?, "Integer#negative? returns true for negative")
  assert_false(0.negative?, "Integer#negative? returns false for zero")
  assert_false(5.negative?, "Integer#negative? returns false for positive")
end

# Integer#to_s (core/integer/to_s_spec.rb)
def test_integer_to_s
  assert_equal("42", 42.to_s, "Integer#to_s returns self converted to a String using base 10")
  assert_equal("-42", (-42).to_s, "Integer#to_s handles negative numbers")
  assert_equal("0", 0.to_s, "Integer#to_s handles zero")
end

# Integer#to_f (core/integer/to_f_spec.rb)
def test_integer_to_f
  result = 42.to_f
  assert_true(result == 42.0, "Integer#to_f returns self converted to a Float")
end

# Float arithmetic (core/float/plus_spec.rb, minus_spec.rb, multiply_spec.rb, divide_spec.rb)
def test_float_arithmetic
  result_add = 1.5 + 2.5
  assert_true(result_add == 4.0, "Float#+ returns self plus other")
  result_sub = 5.5 - 2.0
  assert_true(result_sub == 3.5, "Float#- returns self minus other")
  result_mul = 3.0 * 2.0
  assert_true(result_mul == 6.0, "Float#* returns self multiplied by other")
  result_div = 10.0 / 4.0
  assert_true(result_div == 2.5, "Float#/ returns self divided by other")
end

# Float comparison (core/float/gt_spec.rb, lt_spec.rb, shared/equal.rb)
def test_float_comparison
  assert_true(1.5 < 2.5, "Float#< returns true if self is less than other")
  assert_true(2.5 > 1.5, "Float#> returns true if self is greater than other")
  assert_true(3.0 == 3.0, "Float#== returns true if self has the same value as other")
  assert_true(3.0 >= 3.0, "Float#>= returns true for equal values")
  assert_true(3.0 <= 3.0, "Float#<= returns true for equal values")
end

# Float#abs (core/float/shared/abs.rb)
def test_float_abs
  result = (-5.5).abs
  assert_true(result == 5.5, "Float#abs returns the absolute value")
  result2 = 5.5.abs
  assert_true(result2 == 5.5, "Float#abs returns self for positive")
end

# Float#zero? (core/float/zero_spec.rb)
def test_float_zero
  assert_true(0.0.zero?, "Float#zero? returns true if self is 0.0")
  assert_false(1.0.zero?, "Float#zero? returns false if self is not 0.0")
end

# Float#positive? / Float#negative? (core/float/positive_spec.rb, negative_spec.rb)
def test_float_positive_negative
  assert_true(1.0.positive?, "Float#positive? returns true for positive")
  assert_false(0.0.positive?, "Float#positive? returns false for zero")
  assert_false((-1.0).positive?, "Float#positive? returns false for negative")
  assert_true((-1.0).negative?, "Float#negative? returns true for negative")
  assert_false(0.0.negative?, "Float#negative? returns false for zero")
  assert_false(1.0.negative?, "Float#negative? returns false for positive")
end

def run_tests
  spec_reset
  test_integer_plus
  test_integer_minus
  test_integer_multiply
  test_integer_divide
  test_integer_modulo
  test_integer_negative_arithmetic
  test_integer_comparison
  test_integer_abs
  test_integer_even
  test_integer_odd
  test_integer_zero
  test_integer_positive_negative
  test_integer_to_s
  test_integer_to_f
  test_float_arithmetic
  test_float_comparison
  test_float_abs
  test_float_zero
  test_float_positive_negative
  spec_summary
end

run_tests
