require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/integer/exponent_spec.rb, core/integer/divmod_spec.rb,
# core/integer/gcd_spec.rb, core/integer/abs_spec.rb (extended),
# core/float/abs_spec.rb (extended), core/float/ceil_spec.rb,
# core/float/floor_spec.rb, core/float/round_spec.rb,
# core/float/infinite_spec.rb, core/float/nan_spec.rb,
# core/integer/zero_spec.rb (extended), core/integer/even_spec.rb (extended),
# core/integer/odd_spec.rb (extended), core/integer/positive_spec.rb (extended),
# core/integer/negative_spec.rb (extended),
# core/float/zero_spec.rb (extended),
# core/float/positive_spec.rb (extended),
# core/float/negative_spec.rb (extended)

# Integer#** (core/integer/exponent_spec.rb)
def test_integer_exponent_returns_power
  assert_equal(8, 2 ** 3, "Integer#** returns self raised to the given power")
  assert_equal(1, 2 ** 0, "Integer#** returns 1 when the exponent is 0")
  assert_equal(1, 1 ** 100, "Integer#** returns 1 for 1 raised to any power")
  assert_equal(0, 0 ** 10, "Integer#** returns 0 for 0 raised to a positive power")
end

def test_integer_exponent_negative_base
  assert_equal(9, (-3) ** 2, "Integer#** returns positive for negative base with even exponent")
  assert_equal(-27, (-3) ** 3, "Integer#** returns negative for negative base with odd exponent")
end

def test_integer_exponent_one
  assert_equal(1, 0 ** 0, "Integer#** returns 1 for 0 ** 0")
end

# Integer#divmod (core/integer/divmod_spec.rb)
def test_integer_divmod_returns_array
  result = 13.divmod(4)
  assert_equal(3, result[0], "Integer#divmod returns the quotient as first element")
  assert_equal(1, result[1], "Integer#divmod returns the remainder as second element")
end

def test_integer_divmod_negative_dividend
  result = (-10).divmod(3)
  assert_equal(-4, result[0], "Integer#divmod returns floor quotient for negative dividend")
  assert_equal(2, result[1], "Integer#divmod returns positive remainder for negative dividend")
end

def test_integer_divmod_negative_divisor
  result = 10.divmod(-3)
  assert_equal(-4, result[0], "Integer#divmod returns floor quotient for negative divisor")
  assert_equal(-2, result[1], "Integer#divmod returns negative remainder for negative divisor")
end

def test_integer_divmod_both_negative
  result = (-10).divmod(-3)
  assert_equal(3, result[0], "Integer#divmod returns positive quotient when both negative")
  assert_equal(-1, result[1], "Integer#divmod returns negative remainder when both negative")
end

# Integer#gcd (core/integer/gcd_spec.rb)
def test_integer_gcd_returns_gcd
  assert_equal(6, 12.gcd(6), "Integer#gcd returns the greatest common divisor")
  assert_equal(1, 13.gcd(7), "Integer#gcd returns 1 for coprime numbers")
  assert_equal(4, 8.gcd(12), "Integer#gcd returns the gcd of 8 and 12")
end

def test_integer_gcd_with_zero
  assert_equal(5, 5.gcd(0), "Integer#gcd returns self.abs when other is 0")
  assert_equal(5, 0.gcd(5), "Integer#gcd returns other.abs when self is 0")
  assert_equal(0, 0.gcd(0), "Integer#gcd returns 0 when both are 0")
end

def test_integer_gcd_negative
  assert_equal(6, (-12).gcd(6), "Integer#gcd returns positive gcd for negative receiver")
  assert_equal(6, 12.gcd(-6), "Integer#gcd returns positive gcd for negative argument")
  assert_equal(6, (-12).gcd(-6), "Integer#gcd returns positive gcd when both are negative")
end

# Integer#abs extended (core/integer/shared/abs.rb)
def test_integer_abs_large_number
  assert_equal(1000000, (-1000000).abs, "Integer#abs returns absolute value of large negative")
  assert_equal(1000000, 1000000.abs, "Integer#abs returns self for large positive")
end

# Integer#even? extended edge cases (core/integer/even_spec.rb)
def test_integer_even_large
  assert_true(1000000.even?, "Integer#even? returns true for large even number")
  assert_false(999999.even?, "Integer#even? returns false for large odd number")
  assert_true((-2).even?, "Integer#even? returns true for -2")
end

# Integer#odd? extended edge cases (core/integer/odd_spec.rb)
def test_integer_odd_large
  assert_true(999999.odd?, "Integer#odd? returns true for large odd number")
  assert_false(1000000.odd?, "Integer#odd? returns false for large even number")
  assert_true(1.odd?, "Integer#odd? returns true for 1")
  assert_true((-1).odd?, "Integer#odd? returns true for -1")
end

# Integer#positive? / Integer#negative? extended (core/integer/positive_spec.rb, negative_spec.rb)
def test_integer_positive_extended
  assert_true(1.positive?, "Integer#positive? returns true for 1")
  assert_true(100.positive?, "Integer#positive? returns true for 100")
end

def test_integer_negative_extended
  assert_true((-1).negative?, "Integer#negative? returns true for -1")
  assert_true((-100).negative?, "Integer#negative? returns true for -100")
end

# Float#abs extended (core/float/shared/abs.rb)
def test_float_abs_zero
  result = 0.0.abs
  assert_true(result == 0.0, "Float#abs returns 0.0 for 0.0")
end

def test_float_abs_small
  result = (-0.001).abs
  assert_true(result == 0.001, "Float#abs returns absolute value for small negative float")
end

# Float#ceil (core/float/ceil_spec.rb)
def test_float_ceil_positive
  assert_equal(2, 1.2.ceil, "Float#ceil returns the smallest Integer greater than or equal to self")
  assert_equal(1, 1.0.ceil, "Float#ceil returns self as Integer when already whole")
  assert_equal(1, 0.9.ceil, "Float#ceil rounds up 0.9 to 1")
end

def test_float_ceil_negative
  assert_equal(-1, (-1.2).ceil, "Float#ceil rounds toward zero for negative float")
  assert_equal(-1, (-1.0).ceil, "Float#ceil returns self as Integer for negative whole float")
  assert_equal(0, (-0.9).ceil, "Float#ceil rounds -0.9 toward zero to 0")
end

def test_float_ceil_zero
  assert_equal(0, 0.0.ceil, "Float#ceil returns 0 for 0.0")
end

# Float#floor (core/float/floor_spec.rb)
def test_float_floor_positive
  assert_equal(1, 1.9.floor, "Float#floor returns the largest Integer less than or equal to self")
  assert_equal(1, 1.0.floor, "Float#floor returns self as Integer when already whole")
  assert_equal(0, 0.9.floor, "Float#floor rounds down 0.9 to 0")
end

def test_float_floor_negative
  assert_equal(-2, (-1.2).floor, "Float#floor rounds away from zero for negative float")
  assert_equal(-1, (-1.0).floor, "Float#floor returns self as Integer for negative whole float")
  assert_equal(-1, (-0.9).floor, "Float#floor rounds -0.9 away from zero to -1")
end

def test_float_floor_zero
  assert_equal(0, 0.0.floor, "Float#floor returns 0 for 0.0")
end

# Float#round (core/float/round_spec.rb)
def test_float_round_positive
  assert_equal(2, 1.5.round, "Float#round rounds 1.5 up to 2")
  assert_equal(1, 1.4.round, "Float#round rounds 1.4 down to 1")
  assert_equal(2, 1.6.round, "Float#round rounds 1.6 up to 2")
end

def test_float_round_negative
  assert_equal(-2, (-1.5).round, "Float#round rounds -1.5 away from zero to -2")
  assert_equal(-1, (-1.4).round, "Float#round rounds -1.4 toward zero to -1")
  assert_equal(-2, (-1.6).round, "Float#round rounds -1.6 away from zero to -2")
end

def test_float_round_zero
  assert_equal(0, 0.0.round, "Float#round returns 0 for 0.0")
end

def test_float_round_whole_number
  assert_equal(3, 3.0.round, "Float#round returns the integer value for a whole float")
end

# Float#infinite? (core/float/infinite_spec.rb)
def test_float_infinite_positive
  result = Float::INFINITY.infinite?
  assert_equal(1, result, "Float#infinite? returns 1 for positive infinity")
end

def test_float_infinite_negative
  result = (-Float::INFINITY).infinite?
  assert_equal(-1, result, "Float#infinite? returns -1 for negative infinity")
end

def test_float_infinite_finite
  assert_nil(1.0.infinite?, "Float#infinite? returns nil for a finite Float")
  assert_nil(0.0.infinite?, "Float#infinite? returns nil for 0.0")
end

# Float#nan? (core/float/nan_spec.rb)
def test_float_nan_returns_true
  assert_true(Float::NAN.nan?, "Float#nan? returns true for NaN")
end

def test_float_nan_returns_false
  assert_false(1.0.nan?, "Float#nan? returns false for a finite Float")
  assert_false(0.0.nan?, "Float#nan? returns false for 0.0")
  assert_false(Float::INFINITY.nan?, "Float#nan? returns false for Infinity")
end

# Float#zero? extended (core/float/zero_spec.rb)
def test_float_zero_negative_zero
  assert_true((-0.0).zero?, "Float#zero? returns true for -0.0")
end

def test_float_zero_infinity
  assert_false(Float::INFINITY.zero?, "Float#zero? returns false for Infinity")
  assert_false(Float::NAN.zero?, "Float#zero? returns false for NaN")
end

# Float#positive? / Float#negative? extended
def test_float_positive_infinity
  assert_true(Float::INFINITY.positive?, "Float#positive? returns true for Infinity")
  assert_false((-Float::INFINITY).positive?, "Float#positive? returns false for -Infinity")
end

def test_float_negative_infinity
  assert_true((-Float::INFINITY).negative?, "Float#negative? returns true for -Infinity")
  assert_false(Float::INFINITY.negative?, "Float#negative? returns false for Infinity")
end

def run_tests
  spec_reset
  test_integer_exponent_returns_power
  test_integer_exponent_negative_base
  test_integer_exponent_one
  test_integer_divmod_returns_array
  test_integer_divmod_negative_dividend
  test_integer_divmod_negative_divisor
  test_integer_divmod_both_negative
  test_integer_gcd_returns_gcd
  test_integer_gcd_with_zero
  test_integer_gcd_negative
  test_integer_abs_large_number
  test_integer_even_large
  test_integer_odd_large
  test_integer_positive_extended
  test_integer_negative_extended
  test_float_abs_zero
  test_float_abs_small
  test_float_ceil_positive
  test_float_ceil_negative
  test_float_ceil_zero
  test_float_floor_positive
  test_float_floor_negative
  test_float_floor_zero
  test_float_round_positive
  test_float_round_negative
  test_float_round_zero
  test_float_round_whole_number
  test_float_infinite_positive
  test_float_infinite_negative
  test_float_infinite_finite
  test_float_nan_returns_true
  test_float_nan_returns_false
  test_float_zero_negative_zero
  test_float_zero_infinity
  test_float_positive_infinity
  test_float_negative_infinity
  spec_summary
end

run_tests
