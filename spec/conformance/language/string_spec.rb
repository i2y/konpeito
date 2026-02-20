require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/string/*

def test_plus_returns_concatenated_string
  result = "hello" + " " + "world"
  assert_equal("hello world", result, "String#+ returns a new string containing the given string concatenated to self")
end

def test_length_returns_length_of_self
  assert_equal(5, "hello".length, "String#length returns the length of self")
  assert_equal(0, "".length, "String#length returns 0 for empty string")
end

def test_size_is_alias_for_length
  assert_equal(5, "hello".size, "String#size returns the length of self")
end

def test_upcase_returns_copy_with_all_uppercase
  assert_equal("HELLO", "hello".upcase, "String#upcase returns a copy of self with all lowercase letters upcased")
  assert_equal("HELLO", "HELLO".upcase, "String#upcase returns a copy when already upcased")
end

def test_downcase_returns_copy_with_all_lowercase
  assert_equal("hello", "HELLO".downcase, "String#downcase returns a copy of self with all uppercase letters downcased")
  assert_equal("hello", "hello".downcase, "String#downcase returns a copy when already downcased")
end

def test_include_returns_true_if_contains_other
  assert_true("hello world".include?("world"), "String#include? returns true if self contains other_str")
  assert_false("hello".include?("xyz"), "String#include? returns false if self does not contain other_str")
  assert_true("hello".include?(""), "String#include? returns true if the other string is empty")
  assert_true("".include?(""), "String#include? returns true if both strings are empty")
end

def test_empty_returns_true_for_zero_length
  assert_true("".empty?, "String#empty? returns true if the string has a length of zero")
  assert_false("x".empty?, "String#empty? returns false if the string has content")
end

def test_strip_removes_leading_and_trailing_whitespace
  assert_equal("hello", "  hello  ".strip, "String#strip returns a new string with leading and trailing whitespace removed")
  assert_equal("", "   ".strip, "String#strip makes a string empty if it is only whitespace")
  assert_equal("hello", "hello".strip, "String#strip returns a copy of self when no whitespace")
end

def test_reverse_returns_reversed_string
  assert_equal("olleh", "hello".reverse, "String#reverse returns a new string with the characters of self in reverse order")
  assert_equal("", "".reverse, "String#reverse returns empty string for empty string")
end

def test_to_i_returns_integer
  assert_equal(42, "42".to_i, "String#to_i treats leading characters as integer")
  assert_equal(0, "abc".to_i, "String#to_i returns 0 if self is no valid integer-representation")
  assert_equal(123, "123abc".to_i, "String#to_i ignores subsequent invalid characters")
  assert_equal(-42, "-42".to_i, "String#to_i accepts negative sign")
end

def test_to_f_returns_float
  result = "3.14".to_f
  assert_true(result > 3.13, "String#to_f treats leading characters as floating point number (lower bound)")
  assert_true(result < 3.15, "String#to_f treats leading characters as floating point number (upper bound)")
  result2 = "abc".to_f
  assert_true(result2 == 0.0, "String#to_f returns 0.0 if the conversion fails")
end

def test_split_returns_array_of_substrings
  result = "a,b,c".split(",")
  assert_equal(3, result.length, "String#split returns an array of substrings based on splitting on the given string")
  assert_equal("a", result[0], "String#split first element is correct")
  assert_equal("b", result[1], "String#split second element is correct")
  assert_equal("c", result[2], "String#split third element is correct")
end

def test_start_with_returns_true_for_matching_prefix
  assert_true("hello world".start_with?("hello"), "String#start_with? returns true only if beginning match")
  assert_false("hello world".start_with?("world"), "String#start_with? returns false if beginning does not match")
  assert_true("hello".start_with?(""), "String#start_with? returns true if the search string is empty")
end

def test_end_with_returns_true_for_matching_suffix
  assert_true("hello world".end_with?("world"), "String#end_with? returns true only if ends match")
  assert_false("hello world".end_with?("hello"), "String#end_with? returns false if the end does not match")
  assert_true("hello".end_with?(""), "String#end_with? returns true if the search string is empty")
end

def test_capitalize_returns_copy_with_first_char_uppercased
  assert_equal("Hello", "hello".capitalize, "String#capitalize returns a copy with the first character uppercased and remainder lowercased")
  assert_equal("Hello", "HELLO".capitalize, "String#capitalize lowercases the remainder")
end

def run_tests
  spec_reset
  test_plus_returns_concatenated_string
  test_length_returns_length_of_self
  test_size_is_alias_for_length
  test_upcase_returns_copy_with_all_uppercase
  test_downcase_returns_copy_with_all_lowercase
  test_include_returns_true_if_contains_other
  test_empty_returns_true_for_zero_length
  test_strip_removes_leading_and_trailing_whitespace
  test_reverse_returns_reversed_string
  test_to_i_returns_integer
  test_to_f_returns_float
  test_split_returns_array_of_substrings
  test_start_with_returns_true_for_matching_prefix
  test_end_with_returns_true_for_matching_suffix
  test_capitalize_returns_copy_with_first_char_uppercased
  spec_summary
end

run_tests
