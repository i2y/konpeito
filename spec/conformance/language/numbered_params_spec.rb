require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/numbered_parameters_spec.rb (Ruby 2.7+)

def test_numbered_param_map
  result = [1, 2, 3].map { _1 * 2 }
  assert_equal(2, result[0], "_1 in map doubles first element")
  assert_equal(4, result[1], "_1 in map doubles second element")
  assert_equal(6, result[2], "_1 in map doubles third element")
end

def test_numbered_param_select
  result = [1, 2, 3, 4, 5].select { _1 > 3 }
  assert_equal(2, result.length, "_1 in select filters correctly")
  assert_equal(4, result[0], "_1 in select first match")
  assert_equal(5, result[1], "_1 in select second match")
end

def test_numbered_param_each
  sum = 0
  [10, 20, 30].each { sum = sum + _1 }
  assert_equal(60, sum, "_1 in each accumulates values")
end

def test_numbered_param_any
  assert_true([1, 2, 3].any? { _1 > 2 }, "_1 in any? returns true when match exists")
  assert_false([1, 2, 3].any? { _1 > 5 }, "_1 in any? returns false when no match")
end

def test_numbered_param_reduce_two_params
  result = [1, 2, 3, 4].reduce(0) { _1 + _2 }
  assert_equal(10, result, "_1 and _2 in reduce sums elements")
end

def test_numbered_param_map_arithmetic
  result = [10, 20, 30].map { _1 + 1 }
  assert_equal(11, result[0], "_1 + 1 in map for first element")
  assert_equal(21, result[1], "_1 + 1 in map for second element")
  assert_equal(31, result[2], "_1 + 1 in map for third element")
end

def test_numbered_param_all
  assert_true([2, 4, 6].all? { _1 > 0 }, "_1 in all? returns true when all match")
  assert_false([2, 4, 6].all? { _1 > 3 }, "_1 in all? returns false when not all match")
end

def test_numbered_param_none
  assert_true([1, 2, 3].none? { _1 > 5 }, "_1 in none? returns true when none match")
  assert_false([1, 2, 3].none? { _1 > 2 }, "_1 in none? returns false when some match")
end

def run_tests
  spec_reset
  test_numbered_param_map
  test_numbered_param_select
  test_numbered_param_each
  test_numbered_param_any
  test_numbered_param_reduce_two_params
  test_numbered_param_map_arithmetic
  test_numbered_param_all
  test_numbered_param_none
  spec_summary
end

run_tests
