require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/integer/* - bitwise operations, chr, digits, etc.

# Bitwise AND (core/integer/bit_and_spec.rb)
def test_bitwise_and
  assert_equal(0, 5 & 2, "Integer#& bitwise AND 5 & 2 = 0")
  assert_equal(1, 5 & 3, "Integer#& bitwise AND 5 & 3 = 1")
  assert_equal(255, 0xFF & 0xFF, "Integer#& bitwise AND 0xFF & 0xFF = 255")
end

# Bitwise OR (core/integer/bit_or_spec.rb)
def test_bitwise_or
  assert_equal(7, 5 | 2, "Integer#| bitwise OR 5 | 2 = 7")
  assert_equal(7, 5 | 3, "Integer#| bitwise OR 5 | 3 = 7")
  assert_equal(0, 0 | 0, "Integer#| bitwise OR 0 | 0 = 0")
end

# Bitwise XOR (core/integer/bit_xor_spec.rb)
def test_bitwise_xor
  assert_equal(7, 5 ^ 2, "Integer#^ bitwise XOR 5 ^ 2 = 7")
  assert_equal(6, 5 ^ 3, "Integer#^ bitwise XOR 5 ^ 3 = 6")
  assert_equal(0, 5 ^ 5, "Integer#^ bitwise XOR 5 ^ 5 = 0")
end

# Left shift (core/integer/left_shift_spec.rb)
def test_left_shift
  assert_equal(4, 1 << 2, "Integer#<< left shift 1 << 2 = 4")
  assert_equal(16, 2 << 3, "Integer#<< left shift 2 << 3 = 16")
  assert_equal(0, 0 << 5, "Integer#<< left shift 0 << 5 = 0")
end

# Right shift (core/integer/right_shift_spec.rb)
def test_right_shift
  assert_equal(2, 8 >> 2, "Integer#>> right shift 8 >> 2 = 2")
  assert_equal(1, 4 >> 2, "Integer#>> right shift 4 >> 2 = 1")
  assert_equal(0, 1 >> 1, "Integer#>> right shift 1 >> 1 = 0")
end

# Integer#chr (core/integer/chr_spec.rb)
def test_chr
  assert_equal("A", 65.chr, "Integer#chr returns character for ASCII code 65")
  assert_equal("a", 97.chr, "Integer#chr returns character for ASCII code 97")
  assert_equal("0", 48.chr, "Integer#chr returns character for ASCII code 48")
end

# Integer#digits (core/integer/digits_spec.rb)
def test_digits_base10
  result = 123.digits
  assert_equal(3, result.length, "Integer#digits returns array of digits")
  assert_equal(3, result[0], "Integer#digits returns least significant digit first")
  assert_equal(2, result[1], "Integer#digits returns middle digit")
  assert_equal(1, result[2], "Integer#digits returns most significant digit last")
end

def test_digits_single
  result = 5.digits
  assert_equal(1, result.length, "Integer#digits for single digit returns array of length 1")
  assert_equal(5, result[0], "Integer#digits for single digit returns that digit")
end

# Integer#[] (core/integer/element_reference_spec.rb)
def test_integer_bit_access
  assert_equal(1, 5[0], "Integer#[] returns bit 0 of 5 (binary 101)")
  assert_equal(0, 5[1], "Integer#[] returns bit 1 of 5 (binary 101)")
  assert_equal(1, 5[2], "Integer#[] returns bit 2 of 5 (binary 101)")
  assert_equal(0, 5[3], "Integer#[] returns bit 3 of 5 (binary 101)")
end

# Integer#lcm (core/integer/lcm_spec.rb)
def test_lcm
  assert_equal(12, 4.lcm(6), "Integer#lcm returns least common multiple of 4 and 6")
  assert_equal(12, 6.lcm(4), "Integer#lcm is commutative")
  assert_equal(0, 0.lcm(5), "Integer#lcm returns 0 when self is 0")
  assert_equal(0, 5.lcm(0), "Integer#lcm returns 0 when other is 0")
end

def run_tests
  spec_reset
  test_bitwise_and
  test_bitwise_or
  test_bitwise_xor
  test_left_shift
  test_right_shift
  test_chr
  test_digits_base10
  test_digits_single
  test_integer_bit_access
  test_lcm
  spec_summary
end

run_tests
