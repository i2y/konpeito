require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/regexp/*, core/string/match_operator_spec.rb,
# core/string/scan_spec.rb, core/string/gsub_spec.rb, core/string/sub_spec.rb,
# core/matchdata/*

# Regexp literal creation (language/regexp_spec.rb)
def test_regexp_literal_creates_regexp
  r = /hello/
  assert_equal(Regexp, r.class, "Regexp literal creates a Regexp object")
end

def test_regexp_literal_source
  r = /hello world/
  assert_equal("hello world", r.source, "Regexp#source returns the original pattern string")
end

# Regexp#match (core/regexp/match_spec.rb)
def test_regexp_match_returns_match_data
  m = /l+/.match("hello")
  assert_true(m != nil, "Regexp#match returns a MatchData when there is a match")
  assert_equal("ll", m[0], "Regexp#match returns the full match as element 0")
end

def test_regexp_match_returns_nil_on_failure
  m = /xyz/.match("hello")
  assert_nil(m, "Regexp#match returns nil when there is no match")
end

def test_regexp_match_with_capture_groups
  m = /(\d+)-(\d+)/.match("date: 2025-12")
  assert_equal("2025-12", m[0], "Regexp#match returns the full match")
  assert_equal("2025", m[1], "Regexp#match returns the first capture group")
  assert_equal("12", m[2], "Regexp#match returns the second capture group")
end

# Regexp#match? (core/regexp/match_spec.rb)
def test_regexp_match_predicate_returns_true
  assert_true(/hello/.match?("hello world"), "Regexp#match? returns true when there is a match")
end

def test_regexp_match_predicate_returns_false
  assert_false(/xyz/.match?("hello world"), "Regexp#match? returns false when there is no match")
end

# String#match with Regexp (core/string/match_spec.rb)
def test_string_match_returns_match_data
  m = "hello".match(/e(..)/)
  assert_true(m != nil, "String#match returns a MatchData when there is a match")
  assert_equal("ell", m[0], "String#match returns the full match as element 0")
  assert_equal("ll", m[1], "String#match returns the first capture group")
end

def test_string_match_returns_nil_on_failure
  m = "hello".match(/xyz/)
  assert_nil(m, "String#match returns nil when there is no match")
end

# String#match? with Regexp (core/string/match_spec.rb)
def test_string_match_predicate_returns_true
  assert_true("hello".match?(/ell/), "String#match? returns true when the pattern matches")
end

def test_string_match_predicate_returns_false
  assert_false("hello".match?(/xyz/), "String#match? returns false when the pattern does not match")
end

# String#=~ (core/string/match_operator_spec.rb)
def test_string_match_operator_returns_index
  result = "hello" =~ /ell/
  assert_equal(1, result, "String#=~ returns the index of the start of the match")
end

def test_string_match_operator_returns_nil_on_no_match
  result = "hello" =~ /xyz/
  assert_nil(result, "String#=~ returns nil if there is no match")
end

def test_string_match_operator_returns_zero_for_match_at_start
  result = "hello" =~ /hel/
  assert_equal(0, result, "String#=~ returns 0 when the match is at the start")
end

# String#scan with Regexp (core/string/scan_spec.rb)
def test_scan_with_regexp_returns_all_matches
  result = "one 1 two 2 three 3".scan(/\d+/)
  assert_equal(3, result.length, "String#scan returns all matches of the regexp")
  assert_equal("1", result[0], "String#scan first regexp match")
  assert_equal("2", result[1], "String#scan second regexp match")
  assert_equal("3", result[2], "String#scan third regexp match")
end

def test_scan_returns_empty_array_when_no_match
  result = "hello".scan(/\d+/)
  assert_equal(0, result.length, "String#scan returns an empty array when there are no matches")
end

# String#gsub with Regexp (core/string/gsub_spec.rb)
def test_gsub_replaces_all_occurrences
  result = "hello world".gsub(/o/, "0")
  assert_equal("hell0 w0rld", result, "String#gsub replaces all occurrences of the pattern")
end

def test_gsub_returns_copy_when_no_match
  result = "hello".gsub(/xyz/, "abc")
  assert_equal("hello", result, "String#gsub returns a copy of self when there is no match")
end

# String#sub with Regexp (core/string/sub_spec.rb)
def test_sub_replaces_first_occurrence
  result = "hello world".sub(/o/, "0")
  assert_equal("hell0 world", result, "String#sub replaces only the first occurrence of the pattern")
end

def test_sub_returns_copy_when_no_match
  result = "hello".sub(/xyz/, "abc")
  assert_equal("hello", result, "String#sub returns a copy of self when there is no match")
end

# Regexp flags: /i (core/regexp/new_spec.rb)
def test_regexp_ignore_case_flag
  assert_true(/hello/i.match?("HELLO"), "Regexp with /i flag matches case-insensitively")
  assert_true(/hello/i.match?("Hello"), "Regexp with /i flag matches mixed case")
  assert_false(/hello/.match?("HELLO"), "Regexp without /i flag does not match different case")
end

# Regexp flags: /m (core/regexp/new_spec.rb)
def test_regexp_multiline_flag
  assert_true(/hello.world/m.match?("hello\nworld"), "Regexp with /m flag makes dot match newlines")
  assert_false(/hello.world/.match?("hello\nworld"), "Regexp without /m flag dot does not match newline")
end

# MatchData basics (core/matchdata/element_reference_spec.rb)
def test_match_data_element_reference
  m = /(.)(.)(\d+)(\d)/.match("THX1138.")
  assert_equal("HX1138", m[0], "MatchData#[] with 0 returns the full match")
  assert_equal("H", m[1], "MatchData#[] with 1 returns the first capture group")
  assert_equal("X", m[2], "MatchData#[] with 2 returns the second capture group")
  assert_equal("113", m[3], "MatchData#[] with 3 returns the third capture group")
  assert_equal("8", m[4], "MatchData#[] with 4 returns the fourth capture group")
end

# MatchData#to_s (core/matchdata/to_s_spec.rb)
def test_match_data_to_s
  m = /(\d+)/.match("abc 123 def")
  assert_equal("123", m.to_s, "MatchData#to_s returns the entire matched string")
end

# MatchData#string (core/matchdata/string_spec.rb)
def test_match_data_string
  m = /(\d+)/.match("abc 123 def")
  assert_equal("abc 123 def", m.string, "MatchData#string returns a copy of the match string")
end

def run_tests
  spec_reset
  test_regexp_literal_creates_regexp
  test_regexp_literal_source
  test_regexp_match_returns_match_data
  test_regexp_match_returns_nil_on_failure
  test_regexp_match_with_capture_groups
  test_regexp_match_predicate_returns_true
  test_regexp_match_predicate_returns_false
  test_string_match_returns_match_data
  test_string_match_returns_nil_on_failure
  test_string_match_predicate_returns_true
  test_string_match_predicate_returns_false
  test_string_match_operator_returns_index
  test_string_match_operator_returns_nil_on_no_match
  test_string_match_operator_returns_zero_for_match_at_start
  test_scan_with_regexp_returns_all_matches
  test_scan_returns_empty_array_when_no_match
  test_gsub_replaces_all_occurrences
  test_gsub_returns_copy_when_no_match
  test_sub_replaces_first_occurrence
  test_sub_returns_copy_when_no_match
  test_regexp_ignore_case_flag
  test_regexp_multiline_flag
  test_match_data_element_reference
  test_match_data_to_s
  test_match_data_string
  spec_summary
end

run_tests
