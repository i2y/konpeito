require_relative "../lib/konpeito_spec"

# Regexp and MatchData methods

def test_regexp_match_returns_matchdata
  md = /(\d+)/.match("foo 42 bar")
  assert_true(!md.nil?, "match returns MatchData for a match")
  assert_equal("42", md[0], "match[0] returns full match")
  assert_equal("42", md[1], "match[1] returns first capture")
end

def test_regexp_match_returns_nil_on_no_match
  md = /xyz/.match("hello world")
  assert_nil(md, "match returns nil when no match")
end

def test_regexp_op_match_returns_position
  pos = /\d+/ =~ "foo 42 bar"
  assert_equal(4, pos, "=~ returns match position")
end

def test_regexp_op_match_nil
  pos = /xyz/ =~ "hello"
  assert_nil(pos, "=~ returns nil when no match")
end

def test_string_op_match
  pos = "hello 42" =~ /\d+/
  assert_equal(6, pos, "String#=~ returns match position")
end

def test_matchdata_captures
  md = /(\w+)\s+(\w+)/.match("hello world")
  assert_equal("hello", md.captures[0], "captures returns first capture group")
  assert_equal("world", md.captures[1], "captures returns second capture group")
end

def test_matchdata_pre_post_match
  md = /world/.match("hello world foo")
  assert_equal("hello ", md.pre_match, "pre_match returns text before match")
  assert_equal(" foo", md.post_match, "post_match returns text after match")
end

def test_matchdata_named_captures
  md = /(?<year>\d{4})-(?<month>\d{2})/.match("2024-03")
  assert_equal("2024", md[:year], "named_captures accesses by name")
  assert_equal("03", md[:month], "named_captures accesses month by name")
end

def test_regexp_case_insensitive
  assert_true(/hello/i.match?("HELLO"), "case insensitive regexp matches uppercase")
  assert_true(/hello/i.match?("Hello"), "case insensitive regexp matches mixed case")
end

def test_string_match_q
  assert_true("hello 42".match?(/\d+/), "match? returns true for a match")
  assert_true(!("hello".match?(/\d+/)), "match? returns false when no match")
end

def run_tests
  spec_reset
  test_regexp_match_returns_matchdata
  test_regexp_match_returns_nil_on_no_match
  test_regexp_op_match_returns_position
  test_regexp_op_match_nil
  test_string_op_match
  test_matchdata_captures
  test_matchdata_pre_post_match
  test_matchdata_named_captures
  test_regexp_case_insensitive
  test_string_match_q
  spec_summary
end

run_tests
