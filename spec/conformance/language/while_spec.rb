require_relative "../lib/konpeito_spec"

def test_while_basic_counter
  i = 0
  while i < 5
    i = i + 1
  end
  assert_equal(5, i, "while loop counts to 5")
end

def test_while_never_executes
  i = 0
  while false
    i = i + 1
  end
  assert_equal(0, i, "while false never executes body")
end

def test_while_with_accumulator
  sum = 0
  i = 1
  while i <= 10
    sum = sum + i
    i = i + 1
  end
  assert_equal(55, sum, "while loop sums 1 to 10")
end

def test_until_basic
  i = 0
  until i >= 5
    i = i + 1
  end
  assert_equal(5, i, "until loop counts to 5")
end

def test_until_never_executes
  i = 0
  until true
    i = i + 1
  end
  assert_equal(0, i, "until true never executes body")
end

def test_while_with_complex_condition
  i = 0
  j = 10
  while i < j
    i = i + 1
    j = j - 1
  end
  assert_equal(5, i, "while with two-variable condition")
  assert_equal(5, j, "while with two-variable condition (j)")
end

def test_while_single_iteration
  count = 0
  x = true
  while x
    count = count + 1
    x = false
  end
  assert_equal(1, count, "while executes exactly once when condition becomes false")
end

def test_nested_while
  total = 0
  i = 0
  while i < 3
    j = 0
    while j < 3
      total = total + 1
      j = j + 1
    end
    i = i + 1
  end
  assert_equal(9, total, "nested while loops 3x3 = 9")
end

def run_tests
  spec_reset
  test_while_basic_counter
  test_while_never_executes
  test_while_with_accumulator
  test_until_basic
  test_until_never_executes
  test_while_with_complex_condition
  test_while_single_iteration
  test_nested_while
  spec_summary
end

run_tests
