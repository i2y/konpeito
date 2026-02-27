require_relative "../lib/konpeito_spec"

# Array functional methods

def test_array_zip
  a = [1, 2, 3]
  b = [4, 5, 6]
  result = a.zip(b)
  assert_equal([1, 4], result[0], "zip pairs first elements")
  assert_equal([2, 5], result[1], "zip pairs second elements")
  assert_equal([3, 6], result[2], "zip pairs third elements")
end

def test_array_each_cons
  result = []
  [1, 2, 3, 4, 5].each_cons(3) { |g| result << g }
  assert_equal(3, result.length, "each_cons yields correct number of groups")
  assert_equal([1, 2, 3], result[0], "each_cons first group")
  assert_equal([2, 3, 4], result[1], "each_cons second group")
  assert_equal([3, 4, 5], result[2], "each_cons third group")
end

def test_array_each_slice
  result = []
  [1, 2, 3, 4, 5].each_slice(2) { |s| result << s }
  assert_equal(3, result.length, "each_slice yields correct number of slices")
  assert_equal([1, 2], result[0], "each_slice first slice")
  assert_equal([3, 4], result[1], "each_slice second slice")
  assert_equal([5], result[2], "each_slice last partial slice")
end

def test_array_tally
  result = ["a", "b", "a", "c", "b", "a"].tally
  assert_equal(3, result["a"], "tally counts a correctly")
  assert_equal(2, result["b"], "tally counts b correctly")
  assert_equal(1, result["c"], "tally counts c correctly")
end

def test_array_flatten
  a = [1, [2, 3], [4, [5, 6]]]
  assert_equal([1, 2, 3, 4, 5, 6], a.flatten, "flatten fully unnests arrays")
end

def test_array_flatten_with_depth
  a = [1, [2, [3, [4]]]]
  assert_equal([1, 2, [3, [4]]], a.flatten(1), "flatten(1) unnests one level")
  assert_equal([1, 2, 3, [4]], a.flatten(2), "flatten(2) unnests two levels")
end

def test_array_uniq
  a = [1, 2, 2, 3, 3, 3]
  assert_equal([1, 2, 3], a.uniq, "uniq removes duplicates")
end

def test_array_combination
  result = [1, 2, 3].combination(2).to_a
  assert_equal(3, result.length, "combination(2) has 3 elements for 3-element array")
  assert_equal([1, 2], result[0], "first combination is [1,2]")
  assert_equal([1, 3], result[1], "second combination is [1,3]")
  assert_equal([2, 3], result[2], "third combination is [2,3]")
end

def test_array_product
  result = [1, 2].product([3, 4])
  assert_equal(4, result.length, "product returns cartesian product")
  assert_equal([1, 3], result[0], "product first pair")
  assert_equal([1, 4], result[1], "product second pair")
  assert_equal([2, 3], result[2], "product third pair")
  assert_equal([2, 4], result[3], "product fourth pair")
end

def run_tests
  spec_reset
  test_array_zip
  test_array_each_cons
  test_array_each_slice
  test_array_tally
  test_array_flatten
  test_array_flatten_with_depth
  test_array_uniq
  test_array_combination
  test_array_product
  spec_summary
end

run_tests
