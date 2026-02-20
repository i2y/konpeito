require_relative "../lib/konpeito_spec"

def test_until_runs_while_expression_is_false
  i = 0
  until i >= 5
    i = i + 1
  end
  assert_equal(5, i, "until runs while the expression is false")
end

def test_until_with_do_keyword
  i = 0
  until i >= 3 do
    i = i + 1
  end
  assert_equal(3, i, "until optionally takes a 'do' after the expression")
end

def test_until_executes_in_containing_scope
  i = 0
  until i >= 5
    i = i + 1
  end
  assert_equal(5, i, "until executes code in containing variable scope")
end

def test_until_returns_nil
  i = 0
  result = until i >= 5
    i = i + 1
  end
  assert_nil(result, "until returns nil if ended when condition became true")
end

def test_until_stops_with_break
  i = 0
  until i >= 10
    if i == 3
      break
    end
    i = i + 1
  end
  assert_equal(3, i, "until stops running body if interrupted by break")
end

def test_until_break_returns_value
  i = 0
  result = until i >= 10
    if i == 3
      break "found"
    end
    i = i + 1
  end
  assert_equal("found", result, "until returns value passed to break")
end

def test_until_break_returns_nil_without_arguments
  i = 0
  result = until i >= 10
    if i == 3
      break
    end
    i = i + 1
  end
  assert_nil(result, "until returns nil if interrupted by break with no arguments")
end

def test_until_skips_to_end_with_next
  sum = 0
  i = 0
  until i >= 5
    i = i + 1
    if i == 3
      next
    end
    sum = sum + i
  end
  assert_equal(12, sum, "until skips to end of body with next (1+2+4+5=12)")
end

def test_until_never_executes_when_condition_true
  i = 0
  until true
    i = i + 1
  end
  assert_equal(0, i, "until does not run body if the condition is already true")
end

def test_until_with_counter
  sum = 0
  n = 1
  until n > 10
    sum = sum + n
    n = n + 1
  end
  assert_equal(55, sum, "until with counter sums 1 to 10")
end

def test_until_with_complex_condition
  i = 0
  j = 10
  until i >= j
    i = i + 1
    j = j - 1
  end
  assert_equal(5, i, "until with complex two-variable condition (i)")
  assert_equal(5, j, "until with complex two-variable condition (j)")
end

def test_nested_until_loops
  total = 0
  i = 0
  until i >= 3
    j = 0
    until j >= 4
      total = total + 1
      j = j + 1
    end
    i = i + 1
  end
  assert_equal(12, total, "nested until loops 3x4 = 12")
end

def run_tests
  spec_reset
  test_until_runs_while_expression_is_false
  test_until_with_do_keyword
  test_until_executes_in_containing_scope
  test_until_returns_nil
  test_until_stops_with_break
  test_until_break_returns_value
  test_until_break_returns_nil_without_arguments
  test_until_skips_to_end_with_next
  test_until_never_executes_when_condition_true
  test_until_with_counter
  test_until_with_complex_condition
  test_nested_until_loops
  spec_summary
end

run_tests
