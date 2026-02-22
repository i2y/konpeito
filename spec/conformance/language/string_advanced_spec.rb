require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/string/* - advanced methods not in string_spec.rb or string_methods_spec.rb

# String#gsub (core/string/gsub_spec.rb)
def test_gsub_replaces_all_occurrences
  assert_equal("h-ll-", "hello".gsub("e", "-").gsub("o", "-"), "String#gsub replaces all matching substrings")
end

def test_gsub_with_regexp
  assert_equal("h-ll-", "hello".gsub(/[eo]/, "-"), "String#gsub with regexp replaces all matches")
end

def test_gsub_returns_copy_when_no_match
  assert_equal("hello", "hello".gsub("z", "-"), "String#gsub returns a copy when no match found")
end

# String#sub (core/string/sub_spec.rb)
def test_sub_replaces_first_occurrence
  assert_equal("hXllo", "hello".sub("e", "X"), "String#sub replaces only the first occurrence")
end

def test_sub_with_regexp
  assert_equal("h-llo", "hello".sub(/[eo]/, "-"), "String#sub with regexp replaces first match only")
end

# String#split (core/string/split_spec.rb)
def test_split_with_string
  result = "a,b,c".split(",")
  assert_equal(3, result.length, "String#split splits by the given separator")
  assert_equal("a", result[0], "String#split first element")
  assert_equal("c", result[2], "String#split last element")
end

def test_split_with_space
  result = "hello world foo".split(" ")
  assert_equal(3, result.length, "String#split by space separates words")
  assert_equal("hello", result[0], "String#split first word")
  assert_equal("foo", result[2], "String#split last word")
end

def test_split_with_limit
  result = "a,b,c,d".split(",", 2)
  assert_equal(2, result.length, "String#split with limit returns at most limit parts")
  assert_equal("a", result[0], "String#split with limit first part")
  assert_equal("b,c,d", result[1], "String#split with limit remainder in last part")
end

# String#chars (core/string/chars_spec.rb)
def test_chars
  result = "hello".chars
  assert_equal(5, result.length, "String#chars returns array of characters")
  assert_equal("h", result[0], "String#chars first character")
  assert_equal("o", result[4], "String#chars last character")
end

# String#bytes (core/string/bytes_spec.rb)
def test_bytes
  result = "ABC".bytes
  assert_equal(3, result.length, "String#bytes returns array of byte values")
  assert_equal(65, result[0], "String#bytes byte for A is 65")
  assert_equal(66, result[1], "String#bytes byte for B is 66")
  assert_equal(67, result[2], "String#bytes byte for C is 67")
end

# String#freeze / String#frozen? (core/string/freeze_spec.rb, frozen_spec.rb)
def test_frozen
  s = "hello"
  assert_false(s.frozen?, "String#frozen? returns false for unfrozen string")
  s.freeze
  assert_true(s.frozen?, "String#frozen? returns true after freeze")
end

# String#start_with? (core/string/start_with_spec.rb)
def test_start_with
  assert_true("hello".start_with?("hel"), "String#start_with? returns true for matching prefix")
  assert_false("hello".start_with?("xyz"), "String#start_with? returns false for non-matching prefix")
  assert_true("hello".start_with?(""), "String#start_with? returns true for empty string prefix")
end

# String#end_with? (core/string/end_with_spec.rb)
def test_end_with
  assert_true("hello".end_with?("llo"), "String#end_with? returns true for matching suffix")
  assert_false("hello".end_with?("xyz"), "String#end_with? returns false for non-matching suffix")
  assert_true("hello".end_with?(""), "String#end_with? returns true for empty string suffix")
end

def run_tests
  spec_reset
  test_gsub_replaces_all_occurrences
  test_gsub_with_regexp
  test_gsub_returns_copy_when_no_match
  test_sub_replaces_first_occurrence
  test_sub_with_regexp
  test_split_with_string
  test_split_with_space
  test_split_with_limit
  test_chars
  test_bytes
  test_frozen
  test_start_with
  test_end_with
  spec_summary
end

run_tests
