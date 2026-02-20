require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/unless_spec.rb

# unless with false condition executes body
def test_unless_false_executes_body
  result = unless false
    "body"
  end
  assert_equal("body", result, "unless with false condition executes the body")
end

# unless with true condition skips body
def test_unless_true_skips_body
  result = unless true
    "body"
  end
  assert_nil(result, "unless with true condition returns nil when no else")
end

# unless with nil condition executes body (nil is falsy)
def test_unless_nil_executes_body
  result = unless nil
    "body"
  end
  assert_equal("body", result, "unless with nil condition executes the body")
end

# unless with else clause - condition false
def test_unless_false_with_else
  result = unless false
    "body"
  else
    "else"
  end
  assert_equal("body", result, "unless false with else evaluates body")
end

# unless with else clause - condition true
def test_unless_true_with_else
  result = unless true
    "body"
  else
    "else"
  end
  assert_equal("else", result, "unless true with else evaluates else branch")
end

# unless as modifier - condition false
def test_unless_modifier_false_condition
  result = "value" unless false
  assert_equal("value", result, "modifier unless with false condition returns the value")
end

# unless as modifier - condition true
def test_unless_modifier_true_condition
  result = nil
  result = "value" unless true
  assert_nil(result, "modifier unless with true condition does not execute")
end

# 0 is truthy in Ruby, so unless 0 skips the body
def test_unless_zero_is_truthy
  result = unless 0
    "body"
  else
    "else"
  end
  assert_equal("else", result, "unless 0 skips body because 0 is truthy")
end

# empty string is truthy in Ruby, so unless "" skips the body
def test_unless_empty_string_is_truthy
  s = ""
  result = unless s
    "body"
  else
    "else"
  end
  assert_equal("else", result, "unless empty string skips body because empty string is truthy")
end

# unless returns last expression of the body
def test_unless_returns_last_expression
  result = unless false
    1
    2
    3
  end
  assert_equal(3, result, "unless returns the last expression in body")
end

# nested unless
def test_nested_unless
  x = nil
  result = unless x
    unless false
      "inner body"
    else
      "inner else"
    end
  else
    "outer else"
  end
  assert_equal("inner body", result, "nested unless evaluates correctly")
end

def run_tests
  spec_reset
  test_unless_false_executes_body
  test_unless_true_skips_body
  test_unless_nil_executes_body
  test_unless_false_with_else
  test_unless_true_with_else
  test_unless_modifier_false_condition
  test_unless_modifier_true_condition
  test_unless_zero_is_truthy
  test_unless_empty_string_is_truthy
  test_unless_returns_last_expression
  test_nested_unless
  spec_summary
end

run_tests
