require_relative "../lib/konpeito_spec"

def test_break_exits_while
  i = 0
  while i < 10
    if i == 5
      break
    end
    i = i + 1
  end
  assert_equal(5, i, "break exits while loop at i=5")
end

def test_break_exits_until
  i = 0
  until i >= 100
    if i == 3
      break
    end
    i = i + 1
  end
  assert_equal(3, i, "break exits until loop at i=3")
end

def test_break_infinite_loop
  count = 0
  while true
    count = count + 1
    if count == 7
      break
    end
  end
  assert_equal(7, count, "break exits infinite while true loop")
end

def test_break_at_start
  executed = false
  while true
    break
    executed = true
  end
  assert_false(executed, "break at start skips rest of loop body")
end

def test_break_nested_inner_only
  outer_count = 0
  inner_total = 0
  while outer_count < 3
    inner = 0
    while inner < 10
      if inner == 2
        break
      end
      inner = inner + 1
    end
    inner_total = inner_total + inner
    outer_count = outer_count + 1
  end
  assert_equal(3, outer_count, "break in inner loop does not affect outer loop")
  assert_equal(6, inner_total, "inner loop breaks at 2 each time, total = 6")
end

def run_tests
  spec_reset
  test_break_exits_while
  test_break_exits_until
  test_break_infinite_loop
  test_break_at_start
  test_break_nested_inner_only
  spec_summary
end

run_tests
