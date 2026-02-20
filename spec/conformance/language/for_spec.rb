require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/for_spec.rb

# for iterates over an Enumerable passing each element to the block
def test_for_iterates_over_array
  sum = 0
  for x in [1, 2, 3]
    sum = sum + x
  end
  assert_equal(6, sum, "for iterates over an Array passing each element to the block")
end

# for executes code in the containing variable scope
def test_for_variable_accessible_after_loop
  for x in [10, 20, 30]
  end
  assert_equal(30, x, "for loop variable is accessible after the loop")
end

# for iterates over an inclusive Range
def test_for_with_inclusive_range
  sum = 0
  for i in 1..5
    sum = sum + i
  end
  assert_equal(15, sum, "for iterates over an inclusive Range (1..5)")
end

# for iterates over an exclusive Range
def test_for_with_exclusive_range
  sum = 0
  for i in 1...5
    sum = sum + i
  end
  assert_equal(10, sum, "for iterates over an exclusive Range (1...5)")
end

# for returns the collection it iterated over
def test_for_returns_collection
  result = for x in [1, 2, 3]
    x
  end
  assert_equal(3, result.length, "for returns the collection it iterated over")
  assert_equal(1, result[0], "for returns the original collection (first element)")
end

# for with break exits the loop
def test_for_with_break
  result = 0
  for i in [1, 2, 3, 4, 5]
    if i == 3
      break
    end
    result = i
  end
  assert_equal(2, result, "for with break exits the loop")
end

# for with break returns nil
def test_for_with_break_returns_nil
  result = for x in [1, 2, 3]
    break if x == 2
  end
  assert_nil(result, "for with break returns nil")
end

# for with next skips to the next iteration
def test_for_with_next
  sum = 0
  for i in [1, 2, 3, 4, 5]
    if i == 3
      next
    end
    sum = sum + i
  end
  assert_equal(12, sum, "for with next skips the current iteration")
end

# for with empty collection does not execute body
def test_for_with_empty_collection
  count = 0
  for x in []
    count = count + 1
  end
  assert_equal(0, count, "for with empty collection does not execute body")
end

# nested for loops
def test_nested_for
  total = 0
  for i in [1, 2, 3]
    for j in [10, 20]
      total = total + i + j
    end
  end
  assert_equal(102, total, "nested for loops iterate correctly")
end

# for sets the loop variable in the containing scope (not a new scope)
def test_for_updates_containing_scope_variable
  val = 0
  for i in [10, 20, 30]
    val = i
  end
  assert_equal(30, val, "for executes code in the containing variable scope")
  assert_equal(30, i, "for loop variable i is available after the loop")
end

def run_tests
  spec_reset
  test_for_iterates_over_array
  test_for_variable_accessible_after_loop
  test_for_with_inclusive_range
  test_for_with_exclusive_range
  test_for_returns_collection
  test_for_with_break
  test_for_with_break_returns_nil
  test_for_with_next
  test_for_with_empty_collection
  test_nested_for
  test_for_updates_containing_scope_variable
  spec_summary
end

run_tests
