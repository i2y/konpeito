require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/array/* - advanced Array methods not in array_spec.rb

# Array#pop (core/array/pop_spec.rb)
def test_pop_removes_last_element
  arr = [1, 2, 3]
  result = arr.pop
  assert_equal(3, result, "Array#pop returns the last element")
  assert_equal(2, arr.length, "Array#pop removes the last element from the array")
  assert_equal(2, arr[1], "Array#pop remaining last element is correct")
end

def test_pop_empty_array
  arr = []
  result = arr.pop
  assert_nil(result, "Array#pop returns nil for an empty array")
end

# Array#shift (core/array/shift_spec.rb)
def test_shift_removes_first_element
  arr = [1, 2, 3]
  result = arr.shift
  assert_equal(1, result, "Array#shift returns the first element")
  assert_equal(2, arr.length, "Array#shift removes the first element from the array")
  assert_equal(2, arr[0], "Array#shift new first element is correct")
end

def test_shift_empty_array
  arr = []
  result = arr.shift
  assert_nil(result, "Array#shift returns nil for an empty array")
end

# Array#unshift (core/array/unshift_spec.rb)
def test_unshift_prepends_element
  arr = [2, 3]
  arr.unshift(1)
  assert_equal(3, arr.length, "Array#unshift increases array length")
  assert_equal(1, arr[0], "Array#unshift prepends the element")
  assert_equal(2, arr[1], "Array#unshift preserves existing elements")
end

# Array#rotate (core/array/rotate_spec.rb)
def test_rotate_default
  result = [1, 2, 3, 4].rotate
  assert_equal(2, result[0], "Array#rotate moves first element to end - new first")
  assert_equal(1, result[3], "Array#rotate moves first element to end - new last")
end

def test_rotate_with_count
  result = [1, 2, 3, 4].rotate(2)
  assert_equal(3, result[0], "Array#rotate(2) rotates by 2 positions - new first")
  assert_equal(2, result[3], "Array#rotate(2) rotates by 2 positions - new last")
end

def test_rotate_negative
  result = [1, 2, 3, 4].rotate(-1)
  assert_equal(4, result[0], "Array#rotate(-1) rotates right by 1 position")
  assert_equal(3, result[3], "Array#rotate(-1) last element is 3")
end

# Array#delete (core/array/delete_spec.rb)
def test_delete_removes_value
  arr = [1, 2, 3, 2, 4]
  result = arr.delete(2)
  assert_equal(2, result, "Array#delete returns the deleted value")
  assert_equal(3, arr.length, "Array#delete removes all occurrences")
  assert_false(arr.include?(2), "Array#delete removes all matching elements")
end

def test_delete_returns_nil_when_not_found
  arr = [1, 2, 3]
  result = arr.delete(5)
  assert_nil(result, "Array#delete returns nil when element not found")
  assert_equal(3, arr.length, "Array#delete does not modify array when not found")
end

# Array#delete_at (core/array/delete_at_spec.rb)
def test_delete_at_removes_element_at_index
  arr = [1, 2, 3, 4]
  result = arr.delete_at(1)
  assert_equal(2, result, "Array#delete_at returns the removed element")
  assert_equal(3, arr.length, "Array#delete_at removes one element")
  assert_equal(3, arr[1], "Array#delete_at shifts elements down")
end

# Array#compact (core/array/compact_spec.rb)
def test_compact_removes_nils
  result = [1, nil, 2, nil, 3].compact
  assert_equal(3, result.length, "Array#compact removes nil elements")
  assert_equal(1, result[0], "Array#compact first element")
  assert_equal(3, result[2], "Array#compact last element")
end

# Array#concat (core/array/concat_spec.rb)
def test_concat_appends_elements
  arr = [1, 2]
  arr.concat([3, 4])
  assert_equal(4, arr.length, "Array#concat appends all elements from other array")
  assert_equal(3, arr[2], "Array#concat first appended element")
  assert_equal(4, arr[3], "Array#concat second appended element")
end

# Array#index (core/array/index_spec.rb)
def test_index_returns_position
  assert_equal(1, [10, 20, 30].index(20), "Array#index returns index of first matching element")
  assert_nil([10, 20, 30].index(99), "Array#index returns nil when not found")
end

# Array#reverse (core/array/reverse_spec.rb - extended)
def test_reverse_preserves_original
  arr = [1, 2, 3]
  result = arr.reverse
  assert_equal(3, result[0], "Array#reverse first element of reversed array")
  assert_equal(1, result[2], "Array#reverse last element of reversed array")
  assert_equal(1, arr[0], "Array#reverse does not modify the original array")
end

def run_tests
  spec_reset
  test_pop_removes_last_element
  test_pop_empty_array
  test_shift_removes_first_element
  test_shift_empty_array
  test_unshift_prepends_element
  test_rotate_default
  test_rotate_with_count
  test_rotate_negative
  test_delete_removes_value
  test_delete_returns_nil_when_not_found
  test_delete_at_removes_element_at_index
  test_compact_removes_nils
  test_concat_appends_elements
  test_index_returns_position
  test_reverse_preserves_original
  spec_summary
end

run_tests
