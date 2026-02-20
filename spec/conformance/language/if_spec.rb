require_relative "../lib/konpeito_spec"

def test_if_true_evaluates_then
  result = if true
    "then"
  else
    "else"
  end
  assert_equal("then", result, "if true evaluates then branch")
end

def test_if_false_evaluates_else
  result = if false
    "then"
  else
    "else"
  end
  assert_equal("else", result, "if false evaluates else branch")
end

def test_if_nil_is_falsy
  result = if nil
    "then"
  else
    "else"
  end
  assert_equal("else", result, "if nil evaluates else branch")
end

def test_if_zero_is_truthy
  result = if 0
    "truthy"
  else
    "falsy"
  end
  assert_equal("truthy", result, "if 0 is truthy in Ruby")
end

def test_if_empty_string_is_truthy
  s = ""
  result = if s
    "truthy"
  else
    "falsy"
  end
  assert_equal("truthy", result, "if empty string is truthy in Ruby")
end

def test_if_without_else_returns_nil
  result = if false
    "then"
  end
  assert_nil(result, "if without else returns nil when condition is false")
end

def test_elsif_chain
  x = 2
  result = if x == 1
    "one"
  elsif x == 2
    "two"
  elsif x == 3
    "three"
  else
    "other"
  end
  assert_equal("two", result, "elsif evaluates correct branch")
end

def test_elsif_falls_to_else
  x = 99
  result = if x == 1
    "one"
  elsif x == 2
    "two"
  else
    "other"
  end
  assert_equal("other", result, "elsif falls through to else")
end

def test_unless_true_skips_body
  result = unless true
    "body"
  else
    "else"
  end
  assert_equal("else", result, "unless true evaluates else branch")
end

def test_unless_false_evaluates_body
  result = unless false
    "body"
  else
    "else"
  end
  assert_equal("body", result, "unless false evaluates body")
end

def test_unless_nil_evaluates_body
  result = unless nil
    "body"
  else
    "else"
  end
  assert_equal("body", result, "unless nil evaluates body")
end

def test_nested_if
  x = 10
  result = if x > 5
    if x > 15
      "big"
    else
      "medium"
    end
  else
    "small"
  end
  assert_equal("medium", result, "nested if evaluates correctly")
end

def test_if_with_comparison_operators
  assert_true(5 > 3, "5 > 3")
  assert_true(3 < 5, "3 < 5")
  assert_true(5 >= 5, "5 >= 5")
  assert_true(5 <= 5, "5 <= 5")
  assert_true(5 == 5, "5 == 5")
  assert_true(5 != 3, "5 != 3")
end

def test_if_returns_last_expression
  result = if true
    1
    2
    3
  end
  assert_equal(3, result, "if returns last expression in branch")
end

def run_tests
  spec_reset
  test_if_true_evaluates_then
  test_if_false_evaluates_else
  test_if_nil_is_falsy
  test_if_zero_is_truthy
  test_if_empty_string_is_truthy
  test_if_without_else_returns_nil
  test_elsif_chain
  test_elsif_falls_to_else
  test_unless_true_skips_body
  test_unless_false_evaluates_body
  test_unless_nil_evaluates_body
  test_nested_if
  test_if_with_comparison_operators
  test_if_returns_last_expression
  spec_summary
end

run_tests
