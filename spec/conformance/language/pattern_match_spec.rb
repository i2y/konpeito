require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/pattern_matching_spec.rb

# Literal patterns
def test_pattern_match_integer_literal
  result = case 1
  in 1 then "one"
  in 2 then "two"
  else "other"
  end
  assert_equal("one", result, "case/in matches integer literal")
end

def test_pattern_match_string_literal
  result = case "hello"
  in "hello" then "matched"
  in "world" then "world"
  else "other"
  end
  assert_equal("matched", result, "case/in matches string literal")
end

def test_pattern_match_else
  result = case 99
  in 1 then "one"
  in 2 then "two"
  else "other"
  end
  assert_equal("other", result, "case/in falls through to else")
end

# Variable patterns
def test_pattern_match_variable_binding
  result = case 42
  in n then n
  else 0
  end
  assert_equal(42, result, "case/in binds matched value to variable")
end

# Alternation patterns
def test_pattern_match_alternation
  result = case 2
  in 1 | 2 | 3 then "small"
  else "big"
  end
  assert_equal("small", result, "case/in matches alternation pattern")
end

def test_pattern_match_alternation_no_match
  result = case 10
  in 1 | 2 | 3 then "small"
  else "big"
  end
  assert_equal("big", result, "case/in alternation falls through when no match")
end

# Type/constant patterns
def test_pattern_match_type_integer
  result = case 42
  in Integer then "integer"
  in String then "string"
  else "other"
  end
  assert_equal("integer", result, "case/in matches Integer type")
end

def test_pattern_match_type_string
  result = case "hello"
  in Integer then "integer"
  in String then "string"
  else "other"
  end
  assert_equal("string", result, "case/in matches String type")
end

# Guard patterns
def helper_classify_with_guard(x)
  case x
  in n if n > 10 then "big"
  in n if n > 0 then "positive"
  else "other"
  end
end

def test_pattern_match_guard_big
  result = helper_classify_with_guard(20)
  assert_equal("big", result, "case/in guard matches n > 10")
end

def test_pattern_match_guard_positive
  result = helper_classify_with_guard(5)
  assert_equal("positive", result, "case/in guard matches n > 0")
end

def test_pattern_match_guard_other
  result = helper_classify_with_guard(0)
  assert_equal("other", result, "case/in guard falls to else for 0")
end

# Capture patterns
def test_pattern_match_capture
  result = case 10
  in Integer => n then n * 2
  else 0
  end
  assert_equal(20, result, "case/in capture pattern binds and uses value")
end

# Array patterns
def test_pattern_match_array_two_elements
  result = case [1, 2]
  in [a, b] then a + b
  else 0
  end
  assert_equal(3, result, "case/in matches array pattern [a, b]")
end

def test_pattern_match_array_three_elements
  result = case [10, 20, 30]
  in [a, b, c] then a + b + c
  else 0
  end
  assert_equal(60, result, "case/in matches array pattern [a, b, c]")
end

# Hash patterns
def test_pattern_match_hash_shorthand
  result = case {x: 1, y: 2}
  in {x:, y:} then x + y
  else 0
  end
  assert_equal(3, result, "case/in matches hash pattern {x:, y:}")
end

# Pin patterns
def helper_match_pin(x, expected)
  case x
  in ^expected then "match"
  else "no match"
  end
end

def test_pattern_match_pin_match
  result = helper_match_pin(42, 42)
  assert_equal("match", result, "case/in pin pattern matches equal value")
end

def test_pattern_match_pin_no_match
  result = helper_match_pin(42, 99)
  assert_equal("no match", result, "case/in pin pattern does not match different value")
end

def run_tests
  spec_reset
  test_pattern_match_integer_literal
  test_pattern_match_string_literal
  test_pattern_match_else
  test_pattern_match_variable_binding
  test_pattern_match_alternation
  test_pattern_match_alternation_no_match
  test_pattern_match_type_integer
  test_pattern_match_type_string
  test_pattern_match_guard_big
  test_pattern_match_guard_positive
  test_pattern_match_guard_other
  test_pattern_match_capture
  test_pattern_match_array_two_elements
  test_pattern_match_array_three_elements
  test_pattern_match_hash_shorthand
  test_pattern_match_pin_match
  test_pattern_match_pin_no_match
  spec_summary
end

run_tests
