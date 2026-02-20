require_relative "../lib/konpeito_spec"

def test_next_skips_iteration
  sum = 0
  i = 0
  while i < 10
    i = i + 1
    if i == 5
      next
    end
    sum = sum + i
  end
  assert_equal(50, sum, "next skips i=5, sum = 55 - 5 = 50")
end

def test_next_skips_even_numbers
  sum = 0
  i = 0
  while i < 10
    i = i + 1
    if i % 2 == 0
      next
    end
    sum = sum + i
  end
  assert_equal(25, sum, "next skips even numbers, sum of odds 1+3+5+7+9=25")
end

def test_next_at_start_of_loop
  count = 0
  i = 0
  while i < 5
    i = i + 1
    next
    count = count + 1
  end
  assert_equal(0, count, "next at start skips all remaining body")
  assert_equal(5, i, "loop still iterates 5 times despite next")
end

def test_next_with_condition
  result = ""
  i = 0
  while i < 5
    i = i + 1
    if i == 3
      next
    end
    result = result + i.to_s
  end
  assert_equal("1245", result, "next with condition skips only i=3")
end

def test_next_in_nested_loop
  outer_sum = 0
  i = 0
  while i < 3
    i = i + 1
    j = 0
    inner_sum = 0
    while j < 5
      j = j + 1
      if j == 3
        next
      end
      inner_sum = inner_sum + j
    end
    outer_sum = outer_sum + inner_sum
  end
  assert_equal(36, outer_sum, "next in inner loop: (1+2+4+5)*3 = 36")
end

def run_tests
  spec_reset
  test_next_skips_iteration
  test_next_skips_even_numbers
  test_next_at_start_of_loop
  test_next_with_condition
  test_next_in_nested_loop
  spec_summary
end

run_tests
