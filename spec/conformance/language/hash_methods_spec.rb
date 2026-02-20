require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/hash/*
# Additional Hash methods not covered by hash_spec.rb

# Hash#keys (core/hash/keys_spec.rb)
def test_keys_returns_array_of_keys_in_order
  h = {a: 1, b: 2, c: 3}
  k = h.keys
  assert_equal(3, k.length, "Hash#keys returns an array with all keys")
  assert_equal(:a, k[0], "Hash#keys first key matches insertion order")
  assert_equal(:b, k[1], "Hash#keys second key matches insertion order")
  assert_equal(:c, k[2], "Hash#keys third key matches insertion order")
end

def test_keys_returns_empty_array_for_empty_hash
  assert_equal(0, {}.keys.length, "Hash#keys returns an empty array for an empty hash")
end

# Hash#values (core/hash/values_spec.rb)
def test_values_returns_array_of_values_in_order
  h = {a: 1, b: 2, c: 3}
  v = h.values
  assert_equal(3, v.length, "Hash#values returns an array with all values")
  assert_equal(1, v[0], "Hash#values first value matches insertion order")
  assert_equal(2, v[1], "Hash#values second value matches insertion order")
  assert_equal(3, v[2], "Hash#values third value matches insertion order")
end

def test_values_returns_empty_array_for_empty_hash
  assert_equal(0, {}.values.length, "Hash#values returns an empty array for an empty hash")
end

# Hash#key? (core/hash/shared/key.rb)
def test_key_question_returns_true_if_key_present
  h = {a: 1, b: 2}
  assert_true(h.key?(:a), "Hash#key? returns true if argument is a key")
  assert_false(h.key?(:z), "Hash#key? returns false if argument is not a key")
end

# Hash#include? (core/hash/shared/key.rb)
def test_include_returns_true_if_key_present
  h = {a: 1, b: 2}
  assert_true(h.include?(:a), "Hash#include? returns true if argument is a key")
  assert_false(h.include?(:z), "Hash#include? returns false if argument is not a key")
end

# Hash#has_value? (core/hash/has_value_spec.rb)
def test_has_value_returns_true_if_value_present
  h = {a: 1, b: 2, c: 3}
  assert_true(h.has_value?(1), "Hash#has_value? returns true if the value exists")
  assert_false(h.has_value?(99), "Hash#has_value? returns false if the value does not exist")
end

def test_has_value_returns_true_for_nil_value
  h = {a: nil}
  assert_true(h.has_value?(nil), "Hash#has_value? returns true for nil value")
end

# Hash#value? (core/hash/has_value_spec.rb)
def test_value_question_is_alias_for_has_value
  h = {a: 1, b: 2}
  assert_true(h.value?(2), "Hash#value? returns true if the value exists")
  assert_false(h.value?(99), "Hash#value? returns false if the value does not exist")
end

# Hash#to_a (core/hash/to_a_spec.rb)
def test_to_a_returns_array_of_pairs
  h = {a: 1, b: 2}
  arr = h.to_a
  assert_equal(2, arr.length, "Hash#to_a returns an array of [key, value] pairs")
  assert_equal(:a, arr[0][0], "Hash#to_a first pair key")
  assert_equal(1, arr[0][1], "Hash#to_a first pair value")
  assert_equal(:b, arr[1][0], "Hash#to_a second pair key")
  assert_equal(2, arr[1][1], "Hash#to_a second pair value")
end

def test_to_a_returns_empty_array_for_empty_hash
  assert_equal(0, {}.to_a.length, "Hash#to_a returns an empty array for an empty hash")
end

# Hash#fetch (core/hash/fetch_spec.rb)
def test_fetch_returns_value_for_existing_key
  h = {a: 1, b: 2}
  assert_equal(1, h.fetch(:a), "Hash#fetch returns the value for an existing key")
  assert_equal(2, h.fetch(:b), "Hash#fetch returns the value for another existing key")
end

def test_fetch_with_default_returns_default_for_missing_key
  h = {a: 1}
  assert_equal(42, h.fetch(:z, 42), "Hash#fetch returns the default value when key is not found")
end

def test_fetch_with_default_returns_value_for_existing_key
  h = {a: 1}
  assert_equal(1, h.fetch(:a, 42), "Hash#fetch returns the value (not default) when key exists")
end

# Hash#store (core/hash/store_spec.rb)
def test_store_associates_key_with_value
  h = {}
  h.store(:a, 1)
  assert_equal(1, h[:a], "Hash#store associates the key with the value")
end

def test_store_overwrites_existing_value
  h = {a: 1}
  h.store(:a, 99)
  assert_equal(99, h[:a], "Hash#store overwrites existing value")
end

# Hash#clear (core/hash/clear_spec.rb)
def test_clear_removes_all_entries
  h = {a: 1, b: 2, c: 3}
  h.clear
  assert_equal(0, h.size, "Hash#clear removes all key-value pairs")
  assert_true(h.empty?, "Hash#clear makes the hash empty")
end

def test_clear_on_empty_hash
  h = {}
  h.clear
  assert_equal(0, h.size, "Hash#clear on empty hash keeps it empty")
end

# Hash#select (core/hash/select_spec.rb)
def test_select_returns_hash_of_matching_entries
  h = {a: 1, b: 2, c: 3, d: 4}
  result = h.select { |k, v| v > 2 }
  assert_equal(2, result.size, "Hash#select returns entries for which block is true")
  assert_equal(3, result[:c], "Hash#select includes matching entry c")
  assert_equal(4, result[:d], "Hash#select includes matching entry d")
end

def test_select_returns_empty_when_none_match
  h = {a: 1, b: 2}
  result = h.select { |k, v| v > 10 }
  assert_equal(0, result.size, "Hash#select returns empty hash when no entries match")
end

# Hash#reject (core/hash/reject_spec.rb)
def test_reject_returns_hash_without_matching_entries
  h = {a: 1, b: 2, c: 3, d: 4}
  result = h.reject { |k, v| v > 2 }
  assert_equal(2, result.size, "Hash#reject returns entries for which block is false")
  assert_equal(1, result[:a], "Hash#reject includes non-matching entry a")
  assert_equal(2, result[:b], "Hash#reject includes non-matching entry b")
end

def test_reject_returns_all_when_none_match
  h = {a: 1, b: 2}
  result = h.reject { |k, v| v > 10 }
  assert_equal(2, result.size, "Hash#reject returns all entries when none match")
end

# Hash#map (core/hash/map_spec.rb)
def test_map_returns_array
  h = {a: 1, b: 2, c: 3}
  result = h.map { |k, v| v * 2 }
  assert_equal(3, result.length, "Hash#map returns an array of the same size")
  assert_true(result.include?(2), "Hash#map includes transformed value 2")
  assert_true(result.include?(4), "Hash#map includes transformed value 4")
  assert_true(result.include?(6), "Hash#map includes transformed value 6")
end

# Hash#any? (core/hash/any_spec.rb)
def test_any_with_block_returns_true_when_match
  h = {a: 1, b: 2, c: 3}
  assert_true(h.any? { |k, v| v > 2 }, "Hash#any? returns true if any entry satisfies the block")
end

def test_any_with_block_returns_false_when_no_match
  h = {a: 1, b: 2, c: 3}
  assert_false(h.any? { |k, v| v > 10 }, "Hash#any? returns false if no entry satisfies the block")
end

def test_any_returns_false_for_empty_hash
  assert_false({}.any? { |k, v| v > 0 }, "Hash#any? returns false for an empty hash")
end

# Hash#all? (core/hash/all_spec.rb)
def test_all_with_block_returns_true_when_all_match
  h = {a: 1, b: 2, c: 3}
  assert_true(h.all? { |k, v| v > 0 }, "Hash#all? returns true if all entries satisfy the block")
end

def test_all_with_block_returns_false_when_one_fails
  h = {a: 1, b: 2, c: 3}
  assert_false(h.all? { |k, v| v > 1 }, "Hash#all? returns false if any entry does not satisfy the block")
end

def test_all_returns_true_for_empty_hash
  assert_true({}.all? { |k, v| v > 0 }, "Hash#all? returns true for an empty hash")
end

# Hash#none? (core/hash/none_spec.rb)
def test_none_with_block_returns_true_when_no_match
  h = {a: 1, b: 2, c: 3}
  assert_true(h.none? { |k, v| v > 10 }, "Hash#none? returns true if no entry satisfies the block")
end

def test_none_with_block_returns_false_when_one_matches
  h = {a: 1, b: 2, c: 3}
  assert_false(h.none? { |k, v| v > 2 }, "Hash#none? returns false if any entry satisfies the block")
end

def test_none_returns_true_for_empty_hash
  assert_true({}.none? { |k, v| v > 0 }, "Hash#none? returns true for an empty hash")
end

# Hash#count (core/hash/count_spec.rb)
def test_count_returns_number_of_entries
  assert_equal(3, {a: 1, b: 2, c: 3}.count, "Hash#count returns the number of entries")
  assert_equal(0, {}.count, "Hash#count returns 0 for an empty hash")
end

def test_count_with_block
  h = {a: 1, b: 2, c: 3, d: 4}
  result = h.count { |k, v| v > 2 }
  assert_equal(2, result, "Hash#count with block returns number of entries for which block is true")
end

# Hash#each_key (core/hash/each_key_spec.rb)
def test_each_key_yields_each_key
  h = {a: 1, b: 2, c: 3}
  keys = []
  h.each_key { |k| keys.push(k) }
  assert_equal(3, keys.length, "Hash#each_key yields each key")
  assert_true(keys.include?(:a), "Hash#each_key includes key :a")
  assert_true(keys.include?(:b), "Hash#each_key includes key :b")
  assert_true(keys.include?(:c), "Hash#each_key includes key :c")
end

# Hash#each_value (core/hash/each_value_spec.rb)
def test_each_value_yields_each_value
  h = {a: 1, b: 2, c: 3}
  vals = []
  h.each_value { |v| vals.push(v) }
  assert_equal(3, vals.length, "Hash#each_value yields each value")
  assert_true(vals.include?(1), "Hash#each_value includes value 1")
  assert_true(vals.include?(2), "Hash#each_value includes value 2")
  assert_true(vals.include?(3), "Hash#each_value includes value 3")
end

# Hash#flatten (core/hash/flatten_spec.rb)
def test_flatten_returns_one_dimensional_array
  h = {a: 1, b: 2}
  result = h.flatten
  assert_equal(4, result.length, "Hash#flatten returns a one-dimensional array")
  assert_equal(:a, result[0], "Hash#flatten first element is first key")
  assert_equal(1, result[1], "Hash#flatten second element is first value")
  assert_equal(:b, result[2], "Hash#flatten third element is second key")
  assert_equal(2, result[3], "Hash#flatten fourth element is second value")
end

def test_flatten_empty_hash
  assert_equal(0, {}.flatten.length, "Hash#flatten returns empty array for empty hash")
end

def run_tests
  spec_reset
  test_keys_returns_array_of_keys_in_order
  test_keys_returns_empty_array_for_empty_hash
  test_values_returns_array_of_values_in_order
  test_values_returns_empty_array_for_empty_hash
  test_key_question_returns_true_if_key_present
  test_include_returns_true_if_key_present
  test_has_value_returns_true_if_value_present
  test_has_value_returns_true_for_nil_value
  test_value_question_is_alias_for_has_value
  test_to_a_returns_array_of_pairs
  test_to_a_returns_empty_array_for_empty_hash
  test_fetch_returns_value_for_existing_key
  test_fetch_with_default_returns_default_for_missing_key
  test_fetch_with_default_returns_value_for_existing_key
  test_store_associates_key_with_value
  test_store_overwrites_existing_value
  test_clear_removes_all_entries
  test_clear_on_empty_hash
  test_select_returns_hash_of_matching_entries
  test_select_returns_empty_when_none_match
  test_reject_returns_hash_without_matching_entries
  test_reject_returns_all_when_none_match
  test_map_returns_array
  test_any_with_block_returns_true_when_match
  test_any_with_block_returns_false_when_no_match
  test_any_returns_false_for_empty_hash
  test_all_with_block_returns_true_when_all_match
  test_all_with_block_returns_false_when_one_fails
  test_all_returns_true_for_empty_hash
  test_none_with_block_returns_true_when_no_match
  test_none_with_block_returns_false_when_one_matches
  test_none_returns_true_for_empty_hash
  test_count_returns_number_of_entries
  test_count_with_block
  test_each_key_yields_each_key
  test_each_value_yields_each_value
  test_flatten_returns_one_dimensional_array
  test_flatten_empty_hash
  spec_summary
end

run_tests
