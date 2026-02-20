require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/range/*

# Range#to_a (core/range/to_a_spec.rb)
def test_inclusive_range_to_a
  result = (1..5).to_a
  assert_equal(5, result.length, "Range#to_a converts inclusive range to array with correct length")
  assert_equal(1, result[0], "Range#to_a inclusive range first element")
  assert_equal(5, result[4], "Range#to_a inclusive range last element")
end

def test_exclusive_range_to_a
  result = (1...5).to_a
  assert_equal(4, result.length, "Range#to_a converts exclusive range to array with correct length")
  assert_equal(1, result[0], "Range#to_a exclusive range first element")
  assert_equal(4, result[3], "Range#to_a exclusive range last element")
end

def test_empty_range_to_a
  result = (5..3).to_a
  assert_equal(0, result.length, "Range#to_a returns empty array for descending-ordered range")
end

# Range#include? (core/range/shared/cover_and_include.rb, shared/include.rb)
def test_include_returns_true_for_element
  assert_true((1..10).include?(5), "Range#include? returns true if other is an element of self")
  assert_true((1..10).include?(1), "Range#include? returns true if argument is equal to the first value")
  assert_true((1..10).include?(10), "Range#include? returns true if argument is equal to the last value")
end

def test_include_returns_false_for_non_element
  assert_false((1..10).include?(11), "Range#include? returns false if the range does not contain the argument")
  assert_false((1..10).include?(0), "Range#include? returns false for value before range")
end

def test_exclusive_include
  assert_false((1...5).include?(5), "Range#include? with exclusive range does not include end value")
  assert_true((1...5).include?(4), "Range#include? with exclusive range includes value before end")
end

# Range#size (core/range/size_spec.rb)
def test_size_returns_number_of_elements
  assert_equal(100, (1..100).size, "Range#size returns the number of elements in the range")
  assert_equal(99, (1...100).size, "Range#size returns correct count for exclusive range")
end

def test_size_returns_zero_for_empty_range
  assert_equal(0, (5..3).size, "Range#size returns 0 if last is less than first")
end

# Range#each (core/range/each_spec.rb)
def test_each_passes_elements_to_block
  sum = 0
  (1..5).each { |i| sum = sum + i }
  assert_equal(15, sum, "Range#each passes each element to the given block")
end

# Range#first / Range#last (core/range/first_spec.rb, last_spec.rb)
def test_first_returns_first_element
  assert_equal(1, (1..10).first, "Range#first returns the first element")
end

def test_last_returns_last_element
  assert_equal(10, (1..10).last, "Range#last returns the last element")
end

# Negative range
def test_negative_range_to_a
  result = (-3..3).to_a
  assert_equal(7, result.length, "negative range to_a returns correct length")
  assert_equal(-3, result[0], "negative range first element is -3")
  assert_equal(0, result[3], "negative range middle element is 0")
  assert_equal(3, result[6], "negative range last element is 3")
end

def run_tests
  spec_reset
  test_inclusive_range_to_a
  test_exclusive_range_to_a
  test_empty_range_to_a
  test_include_returns_true_for_element
  test_include_returns_false_for_non_element
  test_exclusive_include
  test_size_returns_number_of_elements
  test_size_returns_zero_for_empty_range
  test_each_passes_elements_to_block
  test_first_returns_first_element
  test_last_returns_last_element
  test_negative_range_to_a
  spec_summary
end

run_tests
