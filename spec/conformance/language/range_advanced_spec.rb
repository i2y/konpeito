require_relative "../lib/konpeito_spec"

# Advanced Range methods

def test_range_cover
  r = (1..10)
  assert_true(r.cover?(5), "cover? returns true for included value")
  assert_true(r.cover?(1), "cover? returns true for begin value")
  assert_true(r.cover?(10), "cover? returns true for end value")
  assert_true(!r.cover?(11), "cover? returns false for value outside range")
end

def test_range_exclusive_cover
  r = (1...10)
  assert_true(r.cover?(9), "exclusive range covers 9")
  assert_true(!r.cover?(10), "exclusive range does not cover end")
end

def test_range_first_n
  assert_equal([1, 2, 3], (1..10).first(3), "first(3) returns first 3 elements")
  assert_equal(1, (1..10).first, "first returns first element")
end

def test_range_last_n
  assert_equal([8, 9, 10], (1..10).last(3), "last(3) returns last 3 elements")
  assert_equal(10, (1..10).last, "last returns last element")
end

def test_range_size
  assert_equal(10, (1..10).size, "size returns number of elements")
  assert_equal(9, (1...10).size, "exclusive range size excludes end")
  assert_equal(0, (5..1).size, "empty range size is 0")
end

def test_range_count
  assert_equal(10, (1..10).count, "count returns total elements")
  assert_equal(5, (1..10).count { |n| n > 5 }, "count with block counts matching elements")
end

def test_range_include
  assert_true((1..5).include?(3), "include? returns true for included value")
  assert_true(!(1..5).include?(6), "include? returns false for excluded value")
end

def test_range_member
  assert_true((1..5).member?(3), "member? is alias for include?")
  assert_true(!(1..5).member?(0), "member? returns false for excluded value")
end

def test_range_step
  result = []
  (1..10).step(3) { |n| result << n }
  assert_equal(1, result[0], "step starts at begin")
  assert_equal(4, result[1], "step increments correctly")
  assert_equal(4, result.length, "step has correct count")
end

def test_range_each
  sum = 0
  (1..5).each { |n| sum += n }
  assert_equal(15, sum, "each iterates over all elements")
end

def test_range_map
  result = (1..5).map { |n| n * 2 }
  assert_equal([2, 4, 6, 8, 10], result, "map transforms range elements")
end

def test_range_to_a
  assert_equal([1, 2, 3, 4, 5], (1..5).to_a, "to_a converts range to array")
  assert_equal([1, 2, 3, 4], (1...5).to_a, "exclusive range to_a excludes end")
end

def run_tests
  spec_reset
  test_range_cover
  test_range_exclusive_cover
  test_range_first_n
  test_range_last_n
  test_range_size
  test_range_count
  test_range_include
  test_range_member
  test_range_step
  test_range_each
  test_range_map
  test_range_to_a
  spec_summary
end

run_tests
