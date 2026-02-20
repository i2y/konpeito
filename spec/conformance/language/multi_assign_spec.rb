require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/assignments_spec.rb and language/for_spec.rb

# Multiple assignment
def test_multi_assign_two_vars
  a, b = [10, 20]
  assert_equal(10, a, "multi-assignment assigns first variable")
  assert_equal(20, b, "multi-assignment assigns second variable")
end

def test_multi_assign_three_vars
  a, b, c = [1, 2, 3]
  assert_equal(1, a, "multi-assignment assigns first of three")
  assert_equal(2, b, "multi-assignment assigns second of three")
  assert_equal(3, c, "multi-assignment assigns third of three")
end

def test_multi_assign_excess_values_ignored
  a, b = [1, 2, 3]
  assert_equal(1, a, "multi-assignment with excess values assigns first correctly")
  assert_equal(2, b, "multi-assignment with excess values assigns second correctly")
end

def test_multi_assign_fewer_values_gives_nil
  a, b, c = [1, 2]
  assert_equal(1, a, "multi-assignment with fewer values assigns first correctly")
  assert_equal(2, b, "multi-assignment with fewer values assigns second correctly")
  assert_nil(c, "multi-assignment with fewer values assigns nil to extra variable")
end

def helper_multi_assign
  x, y = [100, 200]
  x + y
end

def test_multi_assign_in_method
  result = helper_multi_assign
  assert_equal(300, result, "multi-assignment works inside a method")
end

# For loop (language/for_spec.rb)
def test_for_iterates_over_array
  sum = 0
  for x in [1, 2, 3]
    sum = sum + x
  end
  assert_equal(6, sum, "for iterates over an Enumerable passing each element to the block")
end

def test_for_executes_in_containing_scope
  val = 0
  for i in [10, 20, 30]
    val = i
  end
  assert_equal(30, val, "for executes code in containing variable scope")
end

def test_for_with_break
  result = 0
  for i in [1, 2, 3, 4, 5]
    if i == 3
      break
    end
    result = i
  end
  assert_equal(2, result, "for breaks out of a loop upon break")
end

def test_for_with_next
  sum = 0
  for i in [1, 2, 3, 4, 5]
    if i == 3
      next
    end
    sum = sum + i
  end
  assert_equal(12, sum, "for starts the next iteration with next")
end

def run_tests
  spec_reset
  test_multi_assign_two_vars
  test_multi_assign_three_vars
  test_multi_assign_excess_values_ignored
  test_multi_assign_fewer_values_gives_nil
  test_multi_assign_in_method
  test_for_iterates_over_array
  test_for_executes_in_containing_scope
  test_for_with_break
  test_for_with_next
  spec_summary
end

run_tests
