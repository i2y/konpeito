require_relative "../lib/konpeito_spec"

# Integer step and iteration methods

def test_integer_upto
  result = []
  1.upto(5) { |i| result << i }
  assert_equal(5, result.length, "upto iterates correct count")
  assert_equal(1, result[0], "upto starts at 1")
  assert_equal(5, result[-1], "upto ends at 5")
end

def test_integer_downto
  result = []
  5.downto(1) { |i| result << i }
  assert_equal(5, result.length, "downto iterates correct count")
  assert_equal(5, result[0], "downto starts at 5")
  assert_equal(1, result[-1], "downto ends at 1")
end

def test_integer_step_up
  result = []
  1.step(10, 3) { |i| result << i }
  assert_equal(1, result[0], "step starts at 1")
  assert_equal(4, result[1], "step increments by 3")
  assert_equal(4, result.length, "step has correct count")
end

def test_integer_succ
  assert_equal(2, 1.succ, "succ of 1 is 2")
  assert_equal(0, (-1).succ, "succ of -1 is 0")
end

def test_integer_next
  assert_equal(2, 1.next, "next is alias for succ")
end

def test_integer_pred
  assert_equal(0, 1.pred, "pred of 1 is 0")
  assert_equal(-2, (-1).pred, "pred of -1 is -2")
end

def test_integer_gcd
  assert_equal(6, 12.gcd(18), "gcd of 12 and 18 is 6")
  assert_equal(1, 7.gcd(13), "gcd of primes is 1")
end

def test_integer_lcm
  assert_equal(36, 12.lcm(18), "lcm of 12 and 18 is 36")
  assert_equal(91, 7.lcm(13), "lcm of primes is product")
end

def test_integer_digits
  assert_equal([1, 2, 3], 321.digits, "digits returns array of digits in reverse")
  assert_equal([0], 0.digits, "digits of 0 is [0]")
end

def test_integer_bit_length
  assert_equal(0, 0.bit_length, "bit_length of 0 is 0")
  assert_equal(1, 1.bit_length, "bit_length of 1 is 1")
  assert_equal(3, 5.bit_length, "bit_length of 5 is 3")
end

def run_tests
  spec_reset
  test_integer_upto
  test_integer_downto
  test_integer_step_up
  test_integer_succ
  test_integer_next
  test_integer_pred
  test_integer_gcd
  test_integer_lcm
  test_integer_digits
  test_integer_bit_length
  spec_summary
end

run_tests
