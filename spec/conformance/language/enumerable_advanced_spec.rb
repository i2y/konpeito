require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/enumerable/* - advanced methods not in enumerable_spec.rb

# Array#sort_by (core/enumerable/sort_by_spec.rb)
def test_sort_by_basic
  result = [3, 1, 2].sort_by { |x| x }
  assert_equal(1, result[0], "Array#sort_by sorts by block result - first")
  assert_equal(2, result[1], "Array#sort_by sorts by block result - second")
  assert_equal(3, result[2], "Array#sort_by sorts by block result - third")
end

def test_sort_by_string_length
  result = ["cherry", "fig", "apple"].sort_by { |s| s.length }
  assert_equal("fig", result[0], "Array#sort_by by string length - shortest first")
  assert_equal("cherry", result[2], "Array#sort_by by string length - longest last")
end

# Array#min_by / Array#max_by (core/enumerable/min_by_spec.rb, max_by_spec.rb)
def test_min_by
  result = ["cherry", "fig", "apple"].min_by { |s| s.length }
  assert_equal("fig", result, "Array#min_by returns element with minimum block value")
end

def test_max_by
  result = ["cherry", "fig", "apple"].max_by { |s| s.length }
  assert_equal("cherry", result, "Array#max_by returns element with maximum block value")
end

# Array#group_by (core/enumerable/group_by_spec.rb)
def test_group_by
  result = [1, 2, 3, 4, 5, 6].group_by { |x| x % 2 == 0 }
  evens = result[true]
  odds = result[false]
  assert_equal(3, evens.length, "Array#group_by groups even numbers")
  assert_equal(3, odds.length, "Array#group_by groups odd numbers")
  assert_equal(2, evens[0], "Array#group_by first even is 2")
  assert_equal(1, odds[0], "Array#group_by first odd is 1")
end

# Array#each_with_object (core/enumerable/each_with_object_spec.rb)
def test_each_with_object
  result = [1, 2, 3].each_with_object([]) { |x, memo| memo.push(x * 10) }
  assert_equal(3, result.length, "Array#each_with_object returns the memo object")
  assert_equal(10, result[0], "Array#each_with_object first element")
  assert_equal(30, result[2], "Array#each_with_object last element")
end

# Array#take_while (core/enumerable/take_while_spec.rb)
def test_take_while
  result = [1, 2, 3, 4, 5].take_while { |x| x < 4 }
  assert_equal(3, result.length, "Array#take_while takes elements while condition is true")
  assert_equal(1, result[0], "Array#take_while first element")
  assert_equal(3, result[2], "Array#take_while last element before condition fails")
end

def test_take_while_none_match
  result = [5, 6, 7].take_while { |x| x < 3 }
  assert_equal(0, result.length, "Array#take_while returns empty when first element fails")
end

# Array#drop_while (core/enumerable/drop_while_spec.rb)
def test_drop_while
  result = [1, 2, 3, 4, 5].drop_while { |x| x < 3 }
  assert_equal(3, result.length, "Array#drop_while drops elements while condition is true")
  assert_equal(3, result[0], "Array#drop_while first remaining element")
  assert_equal(5, result[2], "Array#drop_while last element")
end

# Array#partition (core/enumerable/partition_spec.rb)
def test_partition
  t, f = [1, 2, 3, 4, 5].partition { |x| x > 3 }
  assert_equal(2, t.length, "Array#partition true group has correct count")
  assert_equal(3, f.length, "Array#partition false group has correct count")
  assert_equal(4, t[0], "Array#partition first true element")
  assert_equal(1, f[0], "Array#partition first false element")
end

# Array#flat_map (core/enumerable/flat_map_spec.rb - extended)
def test_flat_map_with_transform
  result = [1, 2, 3].flat_map { |x| [x, x * 10] }
  assert_equal(6, result.length, "Array#flat_map flattens transformed arrays")
  assert_equal(1, result[0], "Array#flat_map first element")
  assert_equal(10, result[1], "Array#flat_map second element")
  assert_equal(3, result[4], "Array#flat_map fifth element")
  assert_equal(30, result[5], "Array#flat_map sixth element")
end

# Array#tally (core/enumerable/tally_spec.rb)
def test_tally
  result = ["a", "b", "a", "c", "b", "a"].tally
  assert_equal(3, result["a"], "Array#tally counts occurrences of 'a'")
  assert_equal(2, result["b"], "Array#tally counts occurrences of 'b'")
  assert_equal(1, result["c"], "Array#tally counts occurrences of 'c'")
end

def run_tests
  spec_reset
  test_sort_by_basic
  test_sort_by_string_length
  test_min_by
  test_max_by
  test_group_by
  test_each_with_object
  test_take_while
  test_take_while_none_match
  test_drop_while
  test_partition
  test_flat_map_with_transform
  test_tally
  spec_summary
end

run_tests
