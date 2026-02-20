require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/string/*
# Additional String methods not covered by string_spec.rb

# String#center (core/string/center_spec.rb)
def test_center_returns_centered_string
  assert_equal("  hello  ", "hello".center(9), "String#center returns a new string centered with spaces")
end

def test_center_with_pad_string
  assert_equal("--hello---", "hello".center(10, "-"), "String#center pads with the given pad string")
end

def test_center_returns_self_when_width_less_than_length
  assert_equal("hello", "hello".center(3), "String#center returns self when width is less than length")
end

def test_center_returns_self_when_width_equals_length
  assert_equal("hello", "hello".center(5), "String#center returns self when width equals length")
end

def test_center_with_multichar_pad
  assert_equal("abchelloabc", "hello".center(11, "abc"), "String#center uses the pad string cyclically")
end

# String#ljust (core/string/ljust_spec.rb)
def test_ljust_returns_left_justified_string
  assert_equal("hello    ", "hello".ljust(9), "String#ljust pads the right side with spaces")
end

def test_ljust_with_pad_string
  assert_equal("hello----", "hello".ljust(9, "-"), "String#ljust pads with the given pad string")
end

def test_ljust_returns_self_when_width_less_than_length
  assert_equal("hello", "hello".ljust(3), "String#ljust returns self when width is less than length")
end

# String#rjust (core/string/rjust_spec.rb)
def test_rjust_returns_right_justified_string
  assert_equal("    hello", "hello".rjust(9), "String#rjust pads the left side with spaces")
end

def test_rjust_with_pad_string
  assert_equal("----hello", "hello".rjust(9, "-"), "String#rjust pads with the given pad string")
end

def test_rjust_returns_self_when_width_less_than_length
  assert_equal("hello", "hello".rjust(3), "String#rjust returns self when width is less than length")
end

# String#count (core/string/count_spec.rb)
def test_count_returns_number_of_occurrences
  assert_equal(2, "hello".count("l"), "String#count returns the number of times the given character appears")
end

def test_count_with_character_set
  assert_equal(3, "hello".count("lo"), "String#count counts all characters in the given set")
end

def test_count_returns_zero_when_no_match
  assert_equal(0, "hello".count("z"), "String#count returns 0 when no characters match")
end

def test_count_with_negated_set
  assert_equal(2, "hello".count("^lo"), "String#count with negated set counts characters not in the set")
end

# String#delete (core/string/delete_spec.rb)
def test_delete_removes_characters_in_set
  assert_equal("heo", "hello".delete("l"), "String#delete returns a new string with the given characters removed")
end

def test_delete_with_multiple_chars
  assert_equal("he", "hello".delete("lo"), "String#delete removes all characters in the given set")
end

def test_delete_returns_self_when_no_match
  assert_equal("hello", "hello".delete("z"), "String#delete returns a copy when no characters match")
end

# String#squeeze (core/string/squeeze_spec.rb)
def test_squeeze_removes_consecutive_duplicate_chars
  assert_equal("yelo", "yyeellloo".squeeze, "String#squeeze removes runs of the same character")
end

def test_squeeze_with_char_set
  assert_equal("yeellloo", "yyeellloo".squeeze("y"), "String#squeeze limits squeezing to the given character set")
end

def test_squeeze_with_consecutive_duplicates
  assert_equal("helo", "hello".squeeze, "String#squeeze removes consecutive duplicate l from hello")
end

# String#tr (core/string/tr_spec.rb)
def test_tr_translates_characters
  assert_equal("hippo", "hello".tr("el", "ip"), "String#tr returns a new string with characters translated")
end

def test_tr_with_range
  assert_equal("HELLO", "hello".tr("a-z", "A-Z"), "String#tr supports ranges in from/to strings")
end

def test_tr_deletes_with_empty_to
  assert_equal("hll", "hello".tr("aeiou", ""), "String#tr with empty to_str deletes the from characters")
end

# String#scan (core/string/scan_spec.rb)
def test_scan_with_string_pattern
  result = "hello world hello".scan("hello")
  assert_equal(2, result.length, "String#scan returns all occurrences of the string pattern")
  assert_equal("hello", result[0], "String#scan first match is correct")
  assert_equal("hello", result[1], "String#scan second match is correct")
end

def test_scan_with_regexp
  result = "one 1 two 2 three 3".scan(/\d+/)
  assert_equal(3, result.length, "String#scan returns all matches of the regexp")
  assert_equal("1", result[0], "String#scan first regexp match")
  assert_equal("2", result[1], "String#scan second regexp match")
  assert_equal("3", result[2], "String#scan third regexp match")
end

def test_scan_returns_empty_array_when_no_match
  result = "hello".scan("xyz")
  assert_equal(0, result.length, "String#scan returns an empty array when there are no matches")
end

# String#match (core/string/match_spec.rb)
def test_match_returns_match_data_on_success
  m = "hello".match(/e(..)/)
  assert_true(m != nil, "String#match returns a MatchData when there is a match")
  assert_equal("ell", m[0], "String#match returns the full match as element 0")
  assert_equal("ll", m[1], "String#match returns the first capture group as element 1")
end

def test_match_returns_nil_on_failure
  m = "hello".match(/xyz/)
  assert_nil(m, "String#match returns nil when there is no match")
end

# String#match? (core/string/match_spec.rb)
def test_match_predicate_returns_true_on_match
  assert_true("hello".match?(/ell/), "String#match? returns true when the pattern matches")
end

def test_match_predicate_returns_false_on_no_match
  assert_false("hello".match?(/xyz/), "String#match? returns false when the pattern does not match")
end

# String#index (core/string/index_spec.rb)
def test_index_returns_position_of_first_occurrence
  assert_equal(1, "hello".index("ell"), "String#index returns the index of the first occurrence of the given substring")
end

def test_index_returns_zero_for_match_at_start
  assert_equal(0, "hello".index("hel"), "String#index returns 0 when the match is at the start")
end

def test_index_returns_nil_when_not_found
  assert_nil("hello".index("xyz"), "String#index returns nil if the substring is not found")
end

def test_index_with_offset
  assert_equal(6, "hello hello".index("hello", 1), "String#index with offset starts searching from the given position")
end

# String#rindex (core/string/rindex_spec.rb)
def test_rindex_returns_position_of_last_occurrence
  assert_equal(6, "hello hello".rindex("hello"), "String#rindex returns the index of the last occurrence of the given substring")
end

def test_rindex_returns_nil_when_not_found
  assert_nil("hello".rindex("xyz"), "String#rindex returns nil if the substring is not found")
end

def test_rindex_with_offset
  assert_equal(0, "hello hello".rindex("hello", 5), "String#rindex with offset searches backward from the given position")
end

# String#insert (core/string/insert_spec.rb)
def test_insert_at_positive_index
  assert_equal("hXello", "hello".insert(1, "X"), "String#insert inserts the string before the character at the given index")
end

def test_insert_at_negative_index
  assert_equal("hellXo", "hello".insert(-2, "X"), "String#insert with negative index counts from the end")
end

def test_insert_at_beginning
  assert_equal("Xhello", "hello".insert(0, "X"), "String#insert at index 0 prepends the string")
end

# String#capitalize (core/string/capitalize_spec.rb)
def test_capitalize_returns_copy_with_first_char_uppercased
  assert_equal("Hello", "hello".capitalize, "String#capitalize returns a copy of self with the first character uppercased and the remainder lowercased")
end

def test_capitalize_lowercases_remainder
  assert_equal("Hello", "HELLO".capitalize, "String#capitalize lowercases the remainder of the string")
end

def test_capitalize_empty_string
  assert_equal("", "".capitalize, "String#capitalize returns an empty string for an empty string")
end

def test_capitalize_already_capitalized
  assert_equal("Hello", "Hello".capitalize, "String#capitalize returns a copy when already capitalized")
end

# String#swapcase (core/string/swapcase_spec.rb)
def test_swapcase_swaps_case_of_each_character
  assert_equal("hELLO", "Hello".swapcase, "String#swapcase returns a new string with uppercase/lowercase swapped")
end

def test_swapcase_all_uppercase
  assert_equal("hello", "HELLO".swapcase, "String#swapcase converts all uppercase to lowercase")
end

def test_swapcase_all_lowercase
  assert_equal("HELLO", "hello".swapcase, "String#swapcase converts all lowercase to uppercase")
end

def test_swapcase_empty_string
  assert_equal("", "".swapcase, "String#swapcase returns an empty string for an empty string")
end

# String#chomp (core/string/chomp_spec.rb)
def test_chomp_removes_trailing_newline
  assert_equal("hello", "hello\n".chomp, "String#chomp removes a trailing newline")
end

def test_chomp_removes_trailing_carriage_return_newline
  assert_equal("hello", "hello\r\n".chomp, "String#chomp removes a trailing \\r\\n")
end

def test_chomp_removes_trailing_carriage_return
  assert_equal("hello", "hello\r".chomp, "String#chomp removes a trailing \\r")
end

def test_chomp_returns_copy_without_trailing_newline
  assert_equal("hello", "hello".chomp, "String#chomp returns a copy when there is no trailing newline")
end

def test_chomp_with_separator
  assert_equal("hel", "hello".chomp("lo"), "String#chomp with a separator removes the separator from the end")
end

# String#chop (core/string/chop_spec.rb)
def test_chop_removes_last_character
  assert_equal("hell", "hello".chop, "String#chop returns a new string with the last character removed")
end

def test_chop_removes_carriage_return_newline_as_one
  assert_equal("hello", "hello\r\n".chop, "String#chop removes \\r\\n as a single character")
end

def test_chop_returns_empty_for_single_char
  assert_equal("", "x".chop, "String#chop returns an empty string when the string has a single character")
end

def test_chop_returns_empty_for_empty_string
  assert_equal("", "".chop, "String#chop returns an empty string for an empty string")
end

# String#hex (core/string/hex_spec.rb)
def test_hex_interprets_leading_characters_as_hex
  assert_equal(255, "ff".hex, "String#hex interprets the leading characters as a hexadecimal digit string")
end

def test_hex_with_0x_prefix
  assert_equal(255, "0xff".hex, "String#hex accepts 0x prefix")
end

def test_hex_with_uppercase
  assert_equal(255, "FF".hex, "String#hex is case-insensitive")
end

def test_hex_returns_zero_for_invalid
  assert_equal(0, "xyz".hex, "String#hex returns 0 if there are no valid hex digits")
end

def test_hex_stops_at_first_invalid
  assert_equal(10, "ag".hex, "String#hex stops at the first invalid hex character")
end

# String#oct (core/string/oct_spec.rb)
def test_oct_interprets_leading_characters_as_octal
  assert_equal(83, "123".oct, "String#oct interprets the leading characters as an octal digit string")
end

def test_oct_returns_zero_for_invalid
  assert_equal(0, "abc".oct, "String#oct returns 0 if there are no valid octal digits")
end

def test_oct_stops_at_first_invalid
  assert_equal(7, "78".oct, "String#oct stops at the first invalid octal character")
end

# String#to_sym / String#intern (core/string/to_sym_spec.rb)
def test_to_sym_returns_symbol
  assert_equal(:hello, "hello".to_sym, "String#to_sym returns the symbol corresponding to self")
end

def test_intern_returns_symbol
  assert_equal(:hello, "hello".intern, "String#intern returns the symbol corresponding to self")
end

def test_to_sym_with_spaces
  assert_equal(:"hello world", "hello world".to_sym, "String#to_sym handles strings with spaces")
end

# String#each_line (core/string/each_line_spec.rb)
def test_each_line_yields_each_line
  lines = []
  "hello\nworld\nfoo".each_line { |l| lines.push(l) }
  assert_equal(3, lines.length, "String#each_line yields each line")
  assert_equal("hello\n", lines[0], "String#each_line includes the newline in yielded lines")
  assert_equal("world\n", lines[1], "String#each_line second line includes newline")
  assert_equal("foo", lines[2], "String#each_line last line without trailing newline")
end

def test_each_line_with_custom_separator
  lines = []
  "one-two-three".each_line("-") { |l| lines.push(l) }
  assert_equal(3, lines.length, "String#each_line with separator splits on the given separator")
  assert_equal("one-", lines[0], "String#each_line with separator includes the separator")
  assert_equal("two-", lines[1], "String#each_line with separator second segment")
  assert_equal("three", lines[2], "String#each_line with separator last segment without separator")
end

# String#encode (core/string/encode_spec.rb - basic)
def test_encode_returns_string_with_given_encoding
  s = "hello".encode("UTF-8")
  assert_equal("hello", s, "String#encode returns a copy transcoded to the given encoding")
end

def test_encode_ascii_to_utf8
  s = "hello".encode("ASCII")
  assert_equal("hello", s.encode("UTF-8"), "String#encode can transcode from ASCII to UTF-8")
end

def run_tests
  spec_reset
  test_center_returns_centered_string
  test_center_with_pad_string
  test_center_returns_self_when_width_less_than_length
  test_center_returns_self_when_width_equals_length
  test_center_with_multichar_pad
  test_ljust_returns_left_justified_string
  test_ljust_with_pad_string
  test_ljust_returns_self_when_width_less_than_length
  test_rjust_returns_right_justified_string
  test_rjust_with_pad_string
  test_rjust_returns_self_when_width_less_than_length
  test_count_returns_number_of_occurrences
  test_count_with_character_set
  test_count_returns_zero_when_no_match
  test_count_with_negated_set
  test_delete_removes_characters_in_set
  test_delete_with_multiple_chars
  test_delete_returns_self_when_no_match
  test_squeeze_removes_consecutive_duplicate_chars
  test_squeeze_with_char_set
  test_squeeze_with_consecutive_duplicates
  test_tr_translates_characters
  test_tr_with_range
  test_tr_deletes_with_empty_to
  test_scan_with_string_pattern
  test_scan_with_regexp
  test_scan_returns_empty_array_when_no_match
  test_match_returns_match_data_on_success
  test_match_returns_nil_on_failure
  test_match_predicate_returns_true_on_match
  test_match_predicate_returns_false_on_no_match
  test_index_returns_position_of_first_occurrence
  test_index_returns_zero_for_match_at_start
  test_index_returns_nil_when_not_found
  test_index_with_offset
  test_rindex_returns_position_of_last_occurrence
  test_rindex_returns_nil_when_not_found
  test_rindex_with_offset
  test_insert_at_positive_index
  test_insert_at_negative_index
  test_insert_at_beginning
  test_capitalize_returns_copy_with_first_char_uppercased
  test_capitalize_lowercases_remainder
  test_capitalize_empty_string
  test_capitalize_already_capitalized
  test_swapcase_swaps_case_of_each_character
  test_swapcase_all_uppercase
  test_swapcase_all_lowercase
  test_swapcase_empty_string
  test_chomp_removes_trailing_newline
  test_chomp_removes_trailing_carriage_return_newline
  test_chomp_removes_trailing_carriage_return
  test_chomp_returns_copy_without_trailing_newline
  test_chomp_with_separator
  test_chop_removes_last_character
  test_chop_removes_carriage_return_newline_as_one
  test_chop_returns_empty_for_single_char
  test_chop_returns_empty_for_empty_string
  test_hex_interprets_leading_characters_as_hex
  test_hex_with_0x_prefix
  test_hex_with_uppercase
  test_hex_returns_zero_for_invalid
  test_hex_stops_at_first_invalid
  test_oct_interprets_leading_characters_as_octal
  test_oct_returns_zero_for_invalid
  test_oct_stops_at_first_invalid
  test_to_sym_returns_symbol
  test_intern_returns_symbol
  test_to_sym_with_spaces
  test_each_line_yields_each_line
  test_each_line_with_custom_separator
  test_encode_returns_string_with_given_encoding
  test_encode_ascii_to_utf8
  spec_summary
end

run_tests
