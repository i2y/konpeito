require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/hash/*

# Hash#[] (core/hash/element_reference_spec.rb)
def test_element_reference_returns_value_for_key
  h = {"a" => 1, "b" => 2, "c" => 3}
  assert_equal(1, h["a"], "Hash#[] returns the value for key")
  assert_equal(3, h["c"], "Hash#[] returns the value for another key")
end

def test_element_reference_returns_nil_for_missing_key
  h = {"a" => 1}
  assert_nil(h["z"], "Hash#[] returns nil as default value for missing key")
end

def test_element_reference_with_symbol_keys
  h = {x: 10, y: 20}
  assert_equal(10, h[:x], "Hash#[] returns value for symbol key")
  assert_equal(20, h[:y], "Hash#[] returns value for another symbol key")
end

def test_element_reference_does_not_return_default_for_nil_value
  h = {"a" => nil}
  assert_nil(h["a"], "Hash#[] does not return default values for keys with nil values")
end

# Hash#[]= / Hash#store (core/hash/shared/store.rb)
def test_element_set_associates_key_with_value
  h = {}
  h["key"] = "value"
  assert_equal("value", h["key"], "Hash#[]= associates the key with the value")
end

def test_element_set_overwrites_existing
  h = {"a" => 1}
  h["a"] = 99
  assert_equal(99, h["a"], "Hash#[]= overwrites existing value for same key")
end

# Hash#size / Hash#length (core/hash/shared/length.rb)
def test_size_returns_number_of_entries
  assert_equal(3, {a: 1, b: 2, c: 3}.size, "Hash#size returns the number of entries")
  assert_equal(0, {}.size, "Hash#size returns 0 for empty hash")
end

def test_length_is_alias_for_size
  assert_equal(2, {a: 1, b: 2}.length, "Hash#length returns the number of entries")
end

# Hash#keys (core/hash/keys_spec.rb)
def test_keys_returns_array_of_keys
  h = {a: 1, b: 2}
  k = h.keys
  assert_equal(2, k.length, "Hash#keys returns an array with the keys")
end

# Hash#values (core/hash/values_spec.rb)
def test_values_returns_array_of_values
  h = {a: 1, b: 2}
  v = h.values
  assert_equal(2, v.length, "Hash#values returns an array of values")
end

# Hash#has_key? / Hash#key? (core/hash/shared/key.rb)
def test_has_key_returns_true_if_key_present
  h = {a: 1, b: 2}
  assert_true(h.has_key?(:a), "Hash#has_key? returns true if argument is a key")
  assert_false(h.has_key?(:z), "Hash#has_key? returns false if argument is not a key")
end

def test_has_key_returns_true_for_nil_value
  h = {a: nil}
  assert_true(h.has_key?(:a), "Hash#has_key? returns true if the key's matching value was nil")
end

def test_has_key_returns_true_for_false_value
  h = {a: false}
  assert_true(h.has_key?(:a), "Hash#has_key? returns true if the key's matching value was false")
end

# Hash#delete (core/hash/delete_spec.rb)
def test_delete_removes_entry
  h = {a: 1, b: 2}
  h.delete(:a)
  assert_false(h.has_key?(:a), "Hash#delete removes the entry")
  assert_equal(1, h.size, "Hash#delete reduces size")
end

def test_delete_returns_nil_if_not_found
  h = {a: 1}
  result = h.delete(:z)
  assert_nil(result, "Hash#delete returns nil if the key is not found when no block is given")
end

# Hash#empty? (core/hash/empty_spec.rb)
def test_empty_returns_true_for_no_entries
  assert_true({}.empty?, "Hash#empty? returns true if the hash has no entries")
  assert_false({a: 1}.empty?, "Hash#empty? returns false if the hash has entries")
end

def run_tests
  spec_reset
  test_element_reference_returns_value_for_key
  test_element_reference_returns_nil_for_missing_key
  test_element_reference_with_symbol_keys
  test_element_reference_does_not_return_default_for_nil_value
  test_element_set_associates_key_with_value
  test_element_set_overwrites_existing
  test_size_returns_number_of_entries
  test_length_is_alias_for_size
  test_keys_returns_array_of_keys
  test_values_returns_array_of_values
  test_has_key_returns_true_if_key_present
  test_has_key_returns_true_for_nil_value
  test_has_key_returns_true_for_false_value
  test_delete_removes_entry
  test_delete_returns_nil_if_not_found
  test_empty_returns_true_for_no_entries
  spec_summary
end

run_tests
