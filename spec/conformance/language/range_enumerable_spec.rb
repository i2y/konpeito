require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/range/each_spec.rb, core/enumerable/*
# Tests Range enumeration methods (distinct from range_spec.rb which tests literals/include?/size)

# Range#map (core/range/map_spec.rb)
def test_range_map
  result = (1..5).map { |i| i * 2 }
  assert_equal(5, result.length, "Range#map returns array of correct length")
  assert_equal(2, result[0], "Range#map first element is 2")
  assert_equal(10, result[4], "Range#map last element is 10")
end

def test_range_map_exclusive
  result = (1...4).map { |i| i * 10 }
  assert_equal(3, result.length, "exclusive Range#map returns correct length")
  assert_equal(10, result[0], "exclusive Range#map first element")
  assert_equal(30, result[2], "exclusive Range#map last element")
end

# Range#select (core/range/select_spec.rb)
def test_range_select
  result = (1..10).select { |i| i > 7 }
  assert_equal(3, result.length, "Range#select returns matching elements")
  assert_equal(8, result[0], "Range#select first matching element")
  assert_equal(10, result[2], "Range#select last matching element")
end

def test_range_select_even
  result = (1..10).select { |i| i % 2 == 0 }
  assert_equal(5, result.length, "Range#select even numbers from 1..10")
  assert_equal(2, result[0], "Range#select first even")
  assert_equal(10, result[4], "Range#select last even")
end

# Range#reduce (core/enumerable/reduce_spec.rb applied to Range)
def test_range_reduce_with_initial
  result = (1..5).reduce(0) { |sum, i| sum + i }
  assert_equal(15, result, "Range#reduce sums 1..5 with initial 0")
end

def test_range_reduce_without_initial
  result = (1..5).reduce { |sum, i| sum + i }
  assert_equal(15, result, "Range#reduce sums 1..5 without initial")
end

# Range#any? (core/enumerable/any_spec.rb)
def test_range_any
  assert_true((1..10).any? { |i| i > 5 }, "Range#any? returns true when element matches")
  assert_false((1..10).any? { |i| i > 20 }, "Range#any? returns false when no match")
end

# Range#all? (core/enumerable/all_spec.rb)
def test_range_all
  assert_true((1..5).all? { |i| i > 0 }, "Range#all? returns true when all match")
  assert_false((1..5).all? { |i| i > 3 }, "Range#all? returns false when not all match")
end

# Range#none? (core/enumerable/none_spec.rb)
def test_range_none
  assert_true((1..5).none? { |i| i > 10 }, "Range#none? returns true when no match")
  assert_false((1..5).none? { |i| i > 3 }, "Range#none? returns false when some match")
end

# Range#min / Range#max (core/range/min_spec.rb, max_spec.rb)
def test_range_min_max
  assert_equal(1, (1..10).min, "Range#min returns the first element")
  assert_equal(10, (1..10).max, "Range#max returns the last element")
end

# Range#sum (core/enumerable/sum_spec.rb)
def test_range_sum
  assert_equal(15, (1..5).sum, "Range#sum returns the sum of all elements")
  assert_equal(0, (1...1).sum, "Range#sum returns 0 for empty range")
end

def run_tests
  spec_reset
  test_range_map
  test_range_map_exclusive
  test_range_select
  test_range_select_even
  test_range_reduce_with_initial
  test_range_reduce_without_initial
  test_range_any
  test_range_all
  test_range_none
  test_range_min_max
  test_range_sum
  spec_summary
end

run_tests
