require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/hash/* - advanced Hash methods
# Note: Ruby 4.0 Hash iteration - some methods yield [k,v] as pair, others yield k, v separately

# Hash#each_with_object (core/enumerable/each_with_object_spec.rb)
def test_hash_each_with_object
  h = {a: 1, b: 2, c: 3}
  result = h.each_with_object([]) { |pair, memo| memo.push(pair[0]) }
  assert_equal(3, result.length, "Hash#each_with_object iterates over all entries")
end

# Hash#min_by / Hash#max_by (core/enumerable/min_by_spec.rb, max_by_spec.rb)
def test_hash_min_by_value
  h = {a: 3, b: 1, c: 2}
  result = h.min_by { |pair| pair[1] }
  assert_equal(:b, result[0], "Hash#min_by returns entry with minimum value - key")
  assert_equal(1, result[1], "Hash#min_by returns entry with minimum value - value")
end

def test_hash_max_by_value
  h = {a: 3, b: 1, c: 2}
  result = h.max_by { |pair| pair[1] }
  assert_equal(:a, result[0], "Hash#max_by returns entry with maximum value - key")
  assert_equal(3, result[1], "Hash#max_by returns entry with maximum value - value")
end

# Hash#sort_by (core/enumerable/sort_by_spec.rb)
def test_hash_sort_by_value
  h = {c: 3, a: 1, b: 2}
  result = h.sort_by { |pair| pair[1] }
  assert_equal(3, result.length, "Hash#sort_by returns sorted array of pairs")
  assert_equal(:a, result[0][0], "Hash#sort_by first sorted pair key")
  assert_equal(:c, result[2][0], "Hash#sort_by last sorted pair key")
end

# Hash#merge (core/hash/merge_spec.rb)
def test_hash_merge_basic
  h1 = {a: 1, b: 2}
  h2 = {b: 3, c: 4}
  result = h1.merge(h2)
  assert_equal(1, result[:a], "Hash#merge keeps non-overlapping from receiver")
  assert_equal(3, result[:b], "Hash#merge overwrites with other's value")
  assert_equal(4, result[:c], "Hash#merge adds new keys from other")
end

# Hash#to_a (core/hash/to_a_spec.rb)
def test_hash_to_a
  h = {a: 1, b: 2}
  result = h.to_a
  assert_equal(2, result.length, "Hash#to_a returns array of pairs")
  assert_equal(:a, result[0][0], "Hash#to_a first pair key")
  assert_equal(1, result[0][1], "Hash#to_a first pair value")
end

# Hash#select (core/hash/select_spec.rb)
# Ruby 4.0: Hash#select/reject/any?/all? は k, v を別引数として yield する。
# Ruby 3.x の |pair| 形式（pair[1] でアクセス）は Ruby 4.0 では pair がキーのみになり動作しない。
# 元のコード:
#   result = h.select { |pair| pair[1] > 2 }
#   result = h.reject { |pair| pair[1] > 2 }
#   h.any? { |pair| pair[1] > 2 }
#   h.all? { |pair| pair[1] > 0 }
def test_hash_select
  h = {a: 1, b: 2, c: 3, d: 4}
  result = h.select { |k, v| v > 2 }
  assert_equal(2, result.length, "Hash#select returns matching entries")
end

# Hash#reject (core/hash/reject_spec.rb)
def test_hash_reject
  h = {a: 1, b: 2, c: 3, d: 4}
  result = h.reject { |k, v| v > 2 }
  assert_equal(2, result.length, "Hash#reject returns non-matching entries")
end

# Hash#any? (core/enumerable/any_spec.rb)
def test_hash_any
  h = {a: 1, b: 2, c: 3}
  assert_true(h.any? { |k, v| v > 2 }, "Hash#any? returns true when entry matches")
  assert_false(h.any? { |k, v| v > 10 }, "Hash#any? returns false when no match")
end

# Hash#all? (core/enumerable/all_spec.rb)
def test_hash_all
  h = {a: 1, b: 2, c: 3}
  assert_true(h.all? { |k, v| v > 0 }, "Hash#all? returns true when all match")
  assert_false(h.all? { |k, v| v > 1 }, "Hash#all? returns false when not all match")
end

def run_tests
  spec_reset
  test_hash_each_with_object
  test_hash_min_by_value
  test_hash_max_by_value
  test_hash_sort_by_value
  test_hash_merge_basic
  test_hash_to_a
  test_hash_select
  test_hash_reject
  test_hash_any
  test_hash_all
  spec_summary
end

run_tests
