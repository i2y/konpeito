require_relative "../lib/konpeito_spec"

def test_case_when_integer
  x = 2
  result = case x
  when 1 then "one"
  when 2 then "two"
  when 3 then "three"
  else "other"
  end
  assert_equal("two", result, "case/when matches integer")
end

def test_case_when_string
  s = "hello"
  result = case s
  when "hi" then "greeting1"
  when "hello" then "greeting2"
  else "unknown"
  end
  assert_equal("greeting2", result, "case/when matches string")
end

def test_case_when_else
  x = 99
  result = case x
  when 1 then "one"
  when 2 then "two"
  else "other"
  end
  assert_equal("other", result, "case/when falls to else")
end

def test_case_when_first_match_wins
  x = 1
  result = case x
  when 1 then "first"
  when 1 then "second"
  else "other"
  end
  assert_equal("first", result, "case/when uses first matching branch")
end

def test_case_when_no_else_returns_nil
  x = 99
  result = case x
  when 1 then "one"
  when 2 then "two"
  end
  assert_nil(result, "case/when without else returns nil when no match")
end

def test_case_when_returns_value
  result = case 3
  when 1 then 10
  when 2 then 20
  when 3 then 30
  else 0
  end
  assert_equal(30, result, "case/when returns matched branch value")
end

def test_case_when_with_expression
  x = 5
  result = case x
  when 1 then "small"
  when 2 then "small"
  when 3 then "small"
  else "big"
  end
  assert_equal("big", result, "case/when with no match goes to else")
end

def test_nested_case
  x = 1
  y = "a"
  result = case x
  when 1
    case y
    when "a" then "1a"
    when "b" then "1b"
    else "1other"
    end
  when 2 then "two"
  else "other"
  end
  assert_equal("1a", result, "nested case/when works correctly")
end

def run_tests
  spec_reset
  test_case_when_integer
  test_case_when_string
  test_case_when_else
  test_case_when_first_match_wins
  test_case_when_no_else_returns_nil
  test_case_when_returns_value
  test_case_when_with_expression
  test_nested_case
  spec_summary
end

run_tests
