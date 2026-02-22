require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/integer/times_spec.rb, core/integer/upto_spec.rb, core/integer/downto_spec.rb

# Integer#times (core/integer/times_spec.rb)
def test_times_basic
  result = []
  3.times { |i| result.push(i) }
  assert_equal(3, result.length, "Integer#times yields the correct number of times")
  assert_equal(0, result[0], "Integer#times starts at 0")
  assert_equal(1, result[1], "Integer#times second yield is 1")
  assert_equal(2, result[2], "Integer#times third yield is 2")
end

def test_times_zero
  count = 0
  0.times { |i| count = count + 1 }
  assert_equal(0, count, "Integer#times with 0 does not yield")
end

def test_times_accumulator
  sum = 0
  5.times { |i| sum = sum + i }
  assert_equal(10, sum, "Integer#times accumulates sum 0+1+2+3+4=10")
end

# Integer#upto (core/integer/upto_spec.rb)
def test_upto_basic
  result = []
  1.upto(5) { |i| result.push(i) }
  assert_equal(5, result.length, "Integer#upto yields from self to other inclusive")
  assert_equal(1, result[0], "Integer#upto starts at self")
  assert_equal(5, result[4], "Integer#upto ends at other")
end

def test_upto_same_value
  result = []
  3.upto(3) { |i| result.push(i) }
  assert_equal(1, result.length, "Integer#upto with same start and end yields once")
  assert_equal(3, result[0], "Integer#upto with same start and end yields that value")
end

def test_upto_no_yield_when_greater
  count = 0
  5.upto(3) { |i| count = count + 1 }
  assert_equal(0, count, "Integer#upto does not yield when self > other")
end

# Integer#downto (core/integer/downto_spec.rb)
def test_downto_basic
  result = []
  5.downto(1) { |i| result.push(i) }
  assert_equal(5, result.length, "Integer#downto yields from self down to other inclusive")
  assert_equal(5, result[0], "Integer#downto starts at self")
  assert_equal(1, result[4], "Integer#downto ends at other")
end

def test_downto_same_value
  result = []
  3.downto(3) { |i| result.push(i) }
  assert_equal(1, result.length, "Integer#downto with same start and end yields once")
  assert_equal(3, result[0], "Integer#downto with same start and end yields that value")
end

def test_downto_no_yield_when_less
  count = 0
  1.downto(5) { |i| count = count + 1 }
  assert_equal(0, count, "Integer#downto does not yield when self < other")
end

# Nested times
def test_nested_times
  sum = 0
  3.times { |i|
    3.times { |j|
      sum = sum + 1
    }
  }
  assert_equal(9, sum, "nested Integer#times counts 3*3=9")
end

def run_tests
  spec_reset
  test_times_basic
  test_times_zero
  test_times_accumulator
  test_upto_basic
  test_upto_same_value
  test_upto_no_yield_when_greater
  test_downto_basic
  test_downto_same_value
  test_downto_no_yield_when_less
  test_nested_times
  spec_summary
end

run_tests
