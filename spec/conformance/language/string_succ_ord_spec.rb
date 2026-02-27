require_relative "../lib/konpeito_spec"

# String successor and ordinal methods

def test_string_ord
  assert_equal(65, "A".ord, "ord returns ASCII value of A")
  assert_equal(97, "a".ord, "ord returns ASCII value of a")
  assert_equal(48, "0".ord, "ord returns ASCII value of 0")
end

def test_string_succ
  assert_equal("b", "a".succ, "succ of a is b")
  assert_equal("ba", "az".succ, "succ of az is ba")
  assert_equal("B", "A".succ, "succ of A is B")
end

def test_string_next_alias
  assert_equal("b", "a".next, "next is alias for succ")
  assert_equal("ba", "az".next, "next of az is ba")
end

def test_string_casecmp
  assert_equal(0, "abc".casecmp("ABC"), "casecmp returns 0 for equal ignoring case")
  assert_equal(-1, "abc".casecmp("abd"), "casecmp returns -1 when less")
  assert_equal(1, "abd".casecmp("abc"), "casecmp returns 1 when greater")
end

def test_string_casecmp_question
  assert_true("abc".casecmp?("ABC"), "casecmp? returns true for equal ignoring case")
  assert_true(!("abc".casecmp?("xyz")), "casecmp? returns false for different strings")
end

def test_string_partition
  result = "hello world".partition(" ")
  assert_equal("hello", result[0], "partition before returns 'hello'")
  assert_equal(" ", result[1], "partition separator is space")
  assert_equal("world", result[2], "partition after returns 'world'")
end

def test_string_rpartition
  result = "hello world bar".rpartition(" ")
  assert_equal("hello world", result[0], "rpartition before returns 'hello world'")
  assert_equal(" ", result[1], "rpartition separator is space")
  assert_equal("bar", result[2], "rpartition after returns 'bar'")
end

def test_string_center
  assert_equal("  hi  ", "hi".center(6), "center pads to length 6")
  assert_equal("hi", "hi".center(2), "center does not truncate")
  assert_equal("**hi**", "hi".center(6, "*"), "center uses custom pad character")
end

def test_string_delete
  assert_equal("hll", "hello".delete("aeiou"), "delete removes vowels")
  assert_equal("hello", "hello".delete("xyz"), "delete returns unchanged if chars not found")
end

def test_string_count_chars
  assert_equal(2, "hello".count("l"), "count returns number of matching chars")
  assert_equal(0, "hello".count("z"), "count returns 0 for no matching chars")
end

def run_tests
  spec_reset
  test_string_ord
  test_string_succ
  test_string_next_alias
  test_string_casecmp
  test_string_casecmp_question
  test_string_partition
  test_string_rpartition
  test_string_center
  test_string_delete
  test_string_count_chars
  spec_summary
end

run_tests
