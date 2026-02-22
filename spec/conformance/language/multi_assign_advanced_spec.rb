require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/assignment_spec.rb - advanced multiple assignment

# Basic multi-assign (extended from multi_assign_spec.rb)
def test_multi_assign_from_array
  a, b, c = [10, 20, 30]
  assert_equal(10, a, "multi-assign destructures first element")
  assert_equal(20, b, "multi-assign destructures second element")
  assert_equal(30, c, "multi-assign destructures third element")
end

# Left splat: a, *b = arr
def test_multi_assign_left_splat
  first, *rest = [1, 2, 3, 4, 5]
  assert_equal(1, first, "multi-assign left splat captures first element")
  assert_equal(4, rest.length, "multi-assign left splat captures remaining in array")
  assert_equal(2, rest[0], "multi-assign left splat rest first element")
  assert_equal(5, rest[3], "multi-assign left splat rest last element")
end

# Trailing: a, *b, c = arr
def test_multi_assign_middle_splat
  first, *mid, last = [1, 2, 3, 4, 5]
  assert_equal(1, first, "multi-assign middle splat first element")
  assert_equal(5, last, "multi-assign middle splat last element")
  assert_equal(3, mid.length, "multi-assign middle splat captures middle elements")
  assert_equal(2, mid[0], "multi-assign middle splat first middle element")
end

# Swap: a, b = b, a
def test_multi_assign_swap
  a = 1
  b = 2
  a, b = b, a
  assert_equal(2, a, "multi-assign swap assigns b's original value to a")
  assert_equal(1, b, "multi-assign swap assigns a's original value to b")
end

# Too few elements
def test_multi_assign_fewer_elements
  a, b, c = [1, 2]
  assert_equal(1, a, "multi-assign with fewer elements assigns first")
  assert_equal(2, b, "multi-assign with fewer elements assigns second")
  assert_nil(c, "multi-assign with fewer elements assigns nil for missing")
end

# Too many elements
def test_multi_assign_more_elements
  a, b = [1, 2, 3, 4]
  assert_equal(1, a, "multi-assign with more elements assigns first")
  assert_equal(2, b, "multi-assign with more elements assigns second only")
end

# Nested array destructuring
def test_multi_assign_method_return
  result = [10, 20]
  a, b = result
  assert_equal(10, a, "multi-assign from variable holding array")
  assert_equal(20, b, "multi-assign from variable holding array second")
end

# Splat with no remaining
def test_multi_assign_splat_empty_rest
  first, *rest = [42]
  assert_equal(42, first, "multi-assign splat with single element assigns first")
  assert_equal(0, rest.length, "multi-assign splat with single element gives empty rest")
end

def run_tests
  spec_reset
  test_multi_assign_from_array
  test_multi_assign_left_splat
  test_multi_assign_middle_splat
  test_multi_assign_swap
  test_multi_assign_fewer_elements
  test_multi_assign_more_elements
  test_multi_assign_method_return
  test_multi_assign_splat_empty_rest
  spec_summary
end

run_tests
