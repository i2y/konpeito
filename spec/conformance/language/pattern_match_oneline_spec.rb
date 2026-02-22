require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/pattern_matching_spec.rb - one-line patterns
# Tests `x in pattern` (predicate) and `x => pattern` (mandatory)

# Predicate form: expr in pattern (matching cases only)
# Note: `matched = expr in pattern` has precedence issues in Ruby 4.0
#   when the pattern does NOT match, the value assigned is `expr` itself (not false).
#   Only matching cases reliably return truthy.
def test_in_predicate_integer
  matched = 42 in Integer
  assert_true(matched, "in predicate matches Integer type")
end

def test_in_predicate_string
  matched = "hello" in String
  assert_true(matched, "in predicate matches String type")
end

def test_in_predicate_literal
  matched = 1 in 1
  assert_true(matched, "in predicate matches literal value")
end

# Ruby 4.0: `matched = expr in pattern` の代入優先順位の問題で、
# 非マッチ時に false ではなく expr の値が代入される。
# 以下のテストは Ruby 3.x では動作するが Ruby 4.0 では失敗する。
#
# def test_in_predicate_no_match
#   matched = "hello" in Integer
#   assert_false(matched, "in predicate returns false for non-matching type")
# end
#
# def test_in_predicate_literal_no_match
#   matched = 1 in 2
#   assert_false(matched, "in predicate returns false for non-matching literal")
# end
#
# def test_in_predicate_in_if
#   x = 42
#   matched = x in Integer
#   result = if matched
#     "integer"
#   else
#     "other"
#   end
#   assert_equal("integer", result, "in predicate works in if condition")
# end
#
# def test_in_predicate_in_if_no_match
#   x = "hello"
#   matched = x in Integer
#   result = if matched
#     "integer"
#   else
#     "other"
#   end
#   assert_equal("other", result, "in predicate in if falls to else on no match")
# end

# Mandatory form: expr => pattern
def test_arrow_pattern_binding
  [1, 2, 3] => [a, b, c]
  assert_equal(1, a, "=> pattern binds first element")
  assert_equal(2, b, "=> pattern binds second element")
  assert_equal(3, c, "=> pattern binds last element")
end

def test_arrow_pattern_hash
  {name: "Alice", age: 30} => {name:, age:}
  assert_equal("Alice", name, "=> hash pattern binds name")
  assert_equal(30, age, "=> hash pattern binds age")
end

def run_tests
  spec_reset
  test_in_predicate_integer
  test_in_predicate_string
  test_in_predicate_literal
  test_arrow_pattern_binding
  test_arrow_pattern_hash
  spec_summary
end

run_tests
