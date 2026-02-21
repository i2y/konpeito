require_relative "../lib/konpeito_spec"

# Based on Ruby 3.4+/4.0 it block parameter

def test_it_param_map
  result = [1, 2, 3].map { it * 2 }
  assert_equal(2, result[0], "it in map doubles first element")
  assert_equal(4, result[1], "it in map doubles second element")
  assert_equal(6, result[2], "it in map doubles third element")
end

def test_it_param_select
  result = [1, 2, 3, 4, 5].select { it > 3 }
  assert_equal(2, result.length, "it in select filters correctly")
  assert_equal(4, result[0], "it in select first match")
  assert_equal(5, result[1], "it in select second match")
end

def test_it_param_each
  sum = 0
  [10, 20, 30].each { sum = sum + it }
  assert_equal(60, sum, "it in each accumulates values")
end

def test_it_param_any
  assert_true([1, 2, 3].any? { it > 2 }, "it in any? returns true when match exists")
  assert_false([1, 2, 3].any? { it > 5 }, "it in any? returns false when no match")
end

def test_it_param_map_string
  result = [1, 2, 3].map { it.to_s }
  assert_equal("1", result[0], "it.to_s converts first element")
  assert_equal("2", result[1], "it.to_s converts second element")
  assert_equal("3", result[2], "it.to_s converts third element")
end

def test_it_param_all
  assert_true([2, 4, 6].all? { it > 0 }, "it in all? returns true when all match")
  assert_false([2, 4, 6].all? { it > 3 }, "it in all? returns false when not all match")
end

def run_tests
  spec_reset
  test_it_param_map
  test_it_param_select
  test_it_param_each
  test_it_param_any
  test_it_param_map_string
  test_it_param_all
  spec_summary
end

run_tests
