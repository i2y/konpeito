require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/array/*

# Array#[] (core/array/shared/slice.rb)
def test_element_reference_returns_element_at_index
  a = [1, 2, 3, 4]
  assert_equal(1, a[0], "Array#[] returns the element at index 0")
  assert_equal(3, a[2], "Array#[] returns the element at index 2")
end

def test_element_reference_negative_index
  a = [1, 2, 3, 4]
  assert_equal(4, a[-1], "Array#[] returns the element at index from the end with -1")
  assert_equal(3, a[-2], "Array#[] returns the element at index from the end with -2")
end

def test_element_reference_returns_nil_for_out_of_bounds
  a = [1, 2, 3]
  assert_nil(a[5], "Array#[] returns nil for a requested index not in the array")
  assert_nil(a[-4], "Array#[] returns nil for a negative index out of bounds")
end

# Array#length / Array#size (core/array/shared/length.rb)
def test_length_returns_number_of_elements
  assert_equal(3, [1, 2, 3].length, "Array#length returns the number of elements")
  assert_equal(0, [].length, "Array#length returns 0 for empty array")
end

def test_size_is_alias_for_length
  assert_equal(3, [1, 2, 3].size, "Array#size returns the number of elements")
end

# Array#empty? (core/array/empty_spec.rb)
def test_empty_returns_true_for_no_elements
  assert_true([].empty?, "Array#empty? returns true if the array has no elements")
  assert_false([1].empty?, "Array#empty? returns false if the array has elements")
end

# Array#push / Array#<< (core/array/shared/push.rb)
def test_push_appends_to_array
  arr = [1, 2]
  arr.push(3)
  assert_equal(3, arr.length, "Array#push appends the argument to the array")
  assert_equal(3, arr[2], "Array#push appended element is accessible")
end

# Array#first (core/array/first_spec.rb)
def test_first_returns_first_element
  assert_equal(10, [10, 20, 30].first, "Array#first returns the first element")
  assert_nil([].first, "Array#first returns nil if self is empty")
end

# Array#last (core/array/last_spec.rb)
def test_last_returns_last_element
  assert_equal(30, [10, 20, 30].last, "Array#last returns the last element")
  assert_nil([].last, "Array#last returns nil if self is empty")
end

# Array#include? (core/array/include_spec.rb)
def test_include_returns_true_if_present
  assert_true([1, 2, 3].include?(2), "Array#include? returns true if object is present")
  assert_false([1, 2, 3].include?(5), "Array#include? returns false if object is not present")
end

# Array#[]= (core/array/element_set_spec.rb)
def test_element_set_sets_value
  arr = [1, 2, 3]
  arr[1] = 99
  assert_equal(99, arr[1], "Array#[]= sets the value of the element at index")
end

# Array#+ (core/array/plus_spec.rb)
def test_plus_concatenates_arrays
  result = [1, 2] + [3, 4]
  assert_equal(4, result.length, "Array#+ concatenates two arrays")
  assert_equal(1, result[0], "Array#+ first element from first array")
  assert_equal(3, result[2], "Array#+ first element from second array")
end

# Array#flatten (core/array/flatten_spec.rb)
def test_flatten_returns_one_dimensional
  result = [[1, 2], [3, 4]].flatten
  assert_equal(4, result.length, "Array#flatten returns a one-dimensional flattening")
  assert_equal(1, result[0], "Array#flatten first element")
  assert_equal(4, result[3], "Array#flatten last element")
end

# Array#compact (core/array/compact_spec.rb)
def test_compact_removes_nil_elements
  result = [1, nil, 2, nil, 3].compact
  assert_equal(3, result.length, "Array#compact returns a copy with all nil elements removed")
  assert_equal(1, result[0], "Array#compact first element")
  assert_equal(3, result[2], "Array#compact last element")
end

# Array#uniq (core/array/uniq_spec.rb)
def test_uniq_returns_no_duplicates
  result = [1, 2, 2, 3, 3].uniq
  assert_equal(3, result.length, "Array#uniq returns an array with no duplicates")
  assert_equal(1, result[0], "Array#uniq first element")
  assert_equal(3, result[2], "Array#uniq last element")
end

# Array#reverse (core/array/reverse_spec.rb)
def test_reverse_returns_reversed
  result = [1, 2, 3].reverse
  assert_equal(3, result[0], "Array#reverse first element is last of original")
  assert_equal(2, result[1], "Array#reverse middle element stays")
  assert_equal(1, result[2], "Array#reverse last element is first of original")
end

# Array#join
def test_join_returns_string
  result = [1, 2, 3].join(", ")
  assert_equal("1, 2, 3", result, "Array#join returns elements joined by separator")
  result2 = [1, 2, 3].join
  assert_equal("123", result2, "Array#join with no separator joins elements directly")
end

def run_tests
  spec_reset
  test_element_reference_returns_element_at_index
  test_element_reference_negative_index
  test_element_reference_returns_nil_for_out_of_bounds
  test_length_returns_number_of_elements
  test_size_is_alias_for_length
  test_empty_returns_true_for_no_elements
  test_push_appends_to_array
  test_first_returns_first_element
  test_last_returns_last_element
  test_include_returns_true_if_present
  test_element_set_sets_value
  test_plus_concatenates_arrays
  test_flatten_returns_one_dimensional
  test_compact_removes_nil_elements
  test_uniq_returns_no_duplicates
  test_reverse_returns_reversed
  test_join_returns_string
  spec_summary
end

run_tests
