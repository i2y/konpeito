require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/enumerable/* and core/array/*

# Array#map (core/array/map_spec.rb)
def test_map_returns_transformed_array
  result = [1, 2, 3].map { |x| x * 2 }
  assert_equal(3, result.length, "Array#map returns an array of the same size")
  assert_equal(2, result[0], "Array#map transforms first element")
  assert_equal(4, result[1], "Array#map transforms second element")
  assert_equal(6, result[2], "Array#map transforms third element")
end

def test_map_returns_empty_for_empty
  result = [].map { |x| x * 2 }
  assert_equal(0, result.length, "Array#map returns an empty array for an empty receiver")
end

# Array#collect (alias for map)
def test_collect_is_alias_for_map
  result = [1, 2, 3].collect { |x| x + 10 }
  assert_equal(11, result[0], "Array#collect works as an alias for map")
  assert_equal(13, result[2], "Array#collect transforms last element")
end

# Array#select (core/array/select_spec.rb)
def test_select_returns_matching_elements
  result = [1, 2, 3, 4, 5].select { |x| x > 3 }
  assert_equal(2, result.length, "Array#select returns elements for which the block returns true")
  assert_equal(4, result[0], "Array#select first matching element")
  assert_equal(5, result[1], "Array#select second matching element")
end

def test_select_returns_empty_when_none_match
  result = [1, 2, 3].select { |x| x > 10 }
  assert_equal(0, result.length, "Array#select returns empty array when no elements match")
end

# Array#filter (alias for select)
def test_filter_is_alias_for_select
  result = [1, 2, 3, 4].filter { |x| x > 2 }
  assert_equal(2, result.length, "Array#filter works as an alias for select")
  assert_equal(3, result[0], "Array#filter first matching element")
end

# Array#reject (core/array/reject_spec.rb)
def test_reject_returns_non_matching_elements
  result = [1, 2, 3, 4, 5].reject { |x| x > 3 }
  assert_equal(3, result.length, "Array#reject returns elements for which the block returns false")
  assert_equal(1, result[0], "Array#reject first non-matching element")
  assert_equal(3, result[2], "Array#reject last non-matching element")
end

def test_reject_returns_all_when_none_match
  result = [1, 2, 3].reject { |x| x > 10 }
  assert_equal(3, result.length, "Array#reject returns all elements when none match the block")
end

# Enumerable#reduce (core/enumerable/reduce_spec.rb)
def test_reduce_with_initial_value
  result = [1, 2, 3].reduce(0) { |sum, x| sum + x }
  assert_equal(6, result, "Enumerable#reduce combines elements using the block with initial value")
end

def test_reduce_without_initial_value
  result = [1, 2, 3].reduce { |sum, x| sum + x }
  assert_equal(6, result, "Enumerable#reduce uses first element as initial when no initial given")
end

def test_reduce_with_single_element_no_initial
  result = [5].reduce { |sum, x| sum + x }
  assert_equal(5, result, "Enumerable#reduce returns the element when only one element and no initial")
end

def test_reduce_empty_with_initial
  result = [].reduce(0) { |sum, x| sum + x }
  assert_equal(0, result, "Enumerable#reduce returns initial value for empty array")
end

# Enumerable#inject (alias for reduce)
def test_inject_is_alias_for_reduce
  result = [1, 2, 3].inject(0) { |sum, x| sum + x }
  assert_equal(6, result, "Enumerable#inject works as an alias for reduce with initial")
end

def test_inject_without_initial
  result = [1, 2, 3].inject { |sum, x| sum + x }
  assert_equal(6, result, "Enumerable#inject works as an alias for reduce without initial")
end

# Array#each (core/array/each_spec.rb)
def test_each_yields_each_element
  collected = []
  [1, 2, 3].each { |x| collected.push(x) }
  assert_equal(3, collected.length, "Array#each yields each element to the block")
  assert_equal(1, collected[0], "Array#each yields first element")
  assert_equal(3, collected[2], "Array#each yields last element")
end

def test_each_returns_self
  arr = [1, 2, 3]
  result = arr.each { |x| x }
  assert_equal(3, result.length, "Array#each returns self")
  assert_equal(1, result[0], "Array#each returns self with original elements")
end

# Enumerable#find (core/enumerable/find_spec.rb)
def test_find_returns_first_matching
  result = [1, 2, 3, 4].find { |x| x > 2 }
  assert_equal(3, result, "Enumerable#find returns the first element for which the block is true")
end

def test_find_returns_nil_when_none_match
  result = [1, 2, 3].find { |x| x > 10 }
  assert_nil(result, "Enumerable#find returns nil when no element matches")
end

# Enumerable#detect (alias for find)
def test_detect_is_alias_for_find
  result = [1, 2, 3, 4].detect { |x| x > 2 }
  assert_equal(3, result, "Enumerable#detect works as an alias for find")
end

# Enumerable#any? (core/enumerable/any_spec.rb)
def test_any_returns_true_when_element_matches
  assert_true([1, 2, 3].any? { |x| x > 2 }, "Enumerable#any? returns true if any element matches")
end

def test_any_returns_false_when_none_match
  assert_false([1, 2, 3].any? { |x| x > 10 }, "Enumerable#any? returns false if no element matches")
end

def test_any_returns_false_for_empty
  assert_false([].any? { |x| x > 0 }, "Enumerable#any? returns false for an empty collection")
end

# Enumerable#all? (core/enumerable/all_spec.rb)
def test_all_returns_true_when_all_match
  assert_true([1, 2, 3].all? { |x| x > 0 }, "Enumerable#all? returns true if all elements match")
end

def test_all_returns_false_when_one_fails
  assert_false([1, 2, 3].all? { |x| x > 1 }, "Enumerable#all? returns false if any element does not match")
end

def test_all_returns_true_for_empty
  assert_true([].all? { |x| x > 0 }, "Enumerable#all? returns true for an empty collection")
end

# Enumerable#none? (core/enumerable/none_spec.rb)
def test_none_returns_true_when_none_match
  assert_true([1, 2, 3].none? { |x| x > 10 }, "Enumerable#none? returns true if no element matches")
end

def test_none_returns_false_when_one_matches
  assert_false([1, 2, 3].none? { |x| x > 2 }, "Enumerable#none? returns false if any element matches")
end

def test_none_returns_true_for_empty
  assert_true([].none? { |x| x > 0 }, "Enumerable#none? returns true for an empty collection")
end

# Enumerable#count (core/enumerable/count_spec.rb)
def test_count_returns_total_elements
  assert_equal(3, [1, 2, 3].count, "Enumerable#count returns the number of elements")
  assert_equal(0, [].count, "Enumerable#count returns 0 for empty array")
end

def test_count_with_block
  result = [1, 2, 3, 4, 5].count { |x| x > 2 }
  assert_equal(3, result, "Enumerable#count returns the number of elements for which the block returns true")
end

# Enumerable#min (core/enumerable/min_spec.rb)
def test_min_returns_smallest_element
  assert_equal(1, [3, 1, 2].min, "Enumerable#min returns the minimum element")
end

def test_min_returns_nil_for_empty
  assert_nil([].min, "Enumerable#min returns nil for an empty collection")
end

# Enumerable#max (core/enumerable/max_spec.rb)
def test_max_returns_largest_element
  assert_equal(3, [3, 1, 2].max, "Enumerable#max returns the maximum element")
end

def test_max_returns_nil_for_empty
  assert_nil([].max, "Enumerable#max returns nil for an empty collection")
end

# Array#sort (core/array/sort_spec.rb)
def test_sort_returns_sorted_array
  result = [3, 1, 2].sort
  assert_equal(1, result[0], "Array#sort returns a sorted array - first element")
  assert_equal(2, result[1], "Array#sort returns a sorted array - second element")
  assert_equal(3, result[2], "Array#sort returns a sorted array - third element")
end

def test_sort_with_block
  result = [3, 1, 2].sort { |a, b| b <=> a }
  assert_equal(3, result[0], "Array#sort with block sorts in custom order - first element")
  assert_equal(2, result[1], "Array#sort with block sorts in custom order - second element")
  assert_equal(1, result[2], "Array#sort with block sorts in custom order - third element")
end

# Enumerable#flat_map (core/enumerable/flat_map_spec.rb)
def test_flat_map_flattens_one_level
  result = [[1, 2], [3]].flat_map { |a| a }
  assert_equal(3, result.length, "Enumerable#flat_map flattens the result one level")
  assert_equal(1, result[0], "Enumerable#flat_map first element")
  assert_equal(3, result[2], "Enumerable#flat_map last element")
end

# Enumerable#each_with_index (core/enumerable/each_with_index_spec.rb)
def test_each_with_index_yields_element_and_index
  elements = []
  indices = []
  [10, 20, 30].each_with_index { |e, i| elements.push(e); indices.push(i) }
  assert_equal(3, elements.length, "each_with_index yields each element")
  assert_equal(10, elements[0], "each_with_index yields first element")
  assert_equal(30, elements[2], "each_with_index yields last element")
  assert_equal(0, indices[0], "each_with_index yields first index as 0")
  assert_equal(2, indices[2], "each_with_index yields last index")
end

# Enumerable#sum (core/enumerable/sum_spec.rb)
def test_sum_returns_total
  assert_equal(6, [1, 2, 3].sum, "Enumerable#sum returns the sum of elements")
  assert_equal(0, [].sum, "Enumerable#sum returns 0 for empty array")
end

def test_sum_with_block
  result = [1, 2, 3].sum { |x| x * 10 }
  assert_equal(60, result, "Enumerable#sum with block sums the block results")
end

# Array#first (core/array/first_spec.rb)
def test_first_with_count
  result = [1, 2, 3, 4, 5].first(2)
  assert_equal(2, result.length, "Array#first(n) returns the first n elements")
  assert_equal(1, result[0], "Array#first(n) first element")
  assert_equal(2, result[1], "Array#first(n) second element")
end

# Array#last (core/array/last_spec.rb)
def test_last_with_count
  result = [1, 2, 3, 4, 5].last(2)
  assert_equal(2, result.length, "Array#last(n) returns the last n elements")
  assert_equal(4, result[0], "Array#last(n) first element of result")
  assert_equal(5, result[1], "Array#last(n) second element of result")
end

# Array#include? (core/array/include_spec.rb)
def test_include_with_various_types
  assert_true(["a", "b", "c"].include?("b"), "Array#include? returns true for matching string")
  assert_false(["a", "b", "c"].include?("z"), "Array#include? returns false for non-matching string")
  assert_true([nil, false, true].include?(nil), "Array#include? returns true for nil in array")
end

# Array#uniq (core/array/uniq_spec.rb)
def test_uniq_removes_duplicates
  result = [1, 1, 2, 2, 3, 3].uniq
  assert_equal(3, result.length, "Array#uniq returns an array with no duplicates")
  assert_equal(1, result[0], "Array#uniq first element")
  assert_equal(2, result[1], "Array#uniq second element")
  assert_equal(3, result[2], "Array#uniq third element")
end

def test_uniq_returns_same_for_no_duplicates
  result = [1, 2, 3].uniq
  assert_equal(3, result.length, "Array#uniq returns same size when no duplicates")
end

# Array#flatten (core/array/flatten_spec.rb)
def test_flatten_returns_one_dimensional
  result = [1, [2, [3]]].flatten
  assert_equal(3, result.length, "Array#flatten returns a one-dimensional flattening recursively")
  assert_equal(1, result[0], "Array#flatten first element")
  assert_equal(2, result[1], "Array#flatten second element")
  assert_equal(3, result[2], "Array#flatten third element")
end

def test_flatten_with_depth
  result = [1, [2, [3]]].flatten(1)
  assert_equal(3, result.length, "Array#flatten(1) flattens one level")
  assert_equal(1, result[0], "Array#flatten(1) first element")
  assert_equal(2, result[1], "Array#flatten(1) second element")
  # result[2] should be [3] - an array
  assert_true(result[2].is_a?(Array), "Array#flatten(1) stops at one level leaving nested array")
end

# Array#zip (core/array/zip_spec.rb)
def test_zip_merges_elements
  result = [1, 2, 3].zip([4, 5, 6])
  assert_equal(3, result.length, "Array#zip returns array of paired elements")
  assert_equal(1, result[0][0], "Array#zip first pair first element")
  assert_equal(4, result[0][1], "Array#zip first pair second element")
  assert_equal(3, result[2][0], "Array#zip last pair first element")
  assert_equal(6, result[2][1], "Array#zip last pair second element")
end

def test_zip_fills_nil_for_shorter
  result = [1, 2, 3].zip([4])
  assert_equal(3, result.length, "Array#zip pads shorter array with nil")
  assert_equal(4, result[0][1], "Array#zip first pair has value from shorter array")
  assert_nil(result[1][1], "Array#zip second pair has nil from shorter array")
  assert_nil(result[2][1], "Array#zip third pair has nil from shorter array")
end

# Array#take (core/array/take_spec.rb)
def test_take_returns_first_n
  result = [1, 2, 3, 4, 5].take(3)
  assert_equal(3, result.length, "Array#take returns the first n elements")
  assert_equal(1, result[0], "Array#take first element")
  assert_equal(3, result[2], "Array#take last element")
end

# Array#drop (core/array/drop_spec.rb)
def test_drop_returns_remaining
  result = [1, 2, 3, 4, 5].drop(3)
  assert_equal(2, result.length, "Array#drop returns the remaining elements after dropping n")
  assert_equal(4, result[0], "Array#drop first remaining element")
  assert_equal(5, result[1], "Array#drop last remaining element")
end

def run_tests
  spec_reset
  test_map_returns_transformed_array
  test_map_returns_empty_for_empty
  test_collect_is_alias_for_map
  test_select_returns_matching_elements
  test_select_returns_empty_when_none_match
  test_filter_is_alias_for_select
  test_reject_returns_non_matching_elements
  test_reject_returns_all_when_none_match
  test_reduce_with_initial_value
  test_reduce_without_initial_value
  test_reduce_with_single_element_no_initial
  test_reduce_empty_with_initial
  test_inject_is_alias_for_reduce
  test_inject_without_initial
  test_each_yields_each_element
  test_each_returns_self
  test_find_returns_first_matching
  test_find_returns_nil_when_none_match
  test_detect_is_alias_for_find
  test_any_returns_true_when_element_matches
  test_any_returns_false_when_none_match
  test_any_returns_false_for_empty
  test_all_returns_true_when_all_match
  test_all_returns_false_when_one_fails
  test_all_returns_true_for_empty
  test_none_returns_true_when_none_match
  test_none_returns_false_when_one_matches
  test_none_returns_true_for_empty
  test_count_returns_total_elements
  test_count_with_block
  test_min_returns_smallest_element
  test_min_returns_nil_for_empty
  test_max_returns_largest_element
  test_max_returns_nil_for_empty
  test_sort_returns_sorted_array
  test_sort_with_block
  test_flat_map_flattens_one_level
  test_each_with_index_yields_element_and_index
  test_sum_returns_total
  test_sum_with_block
  test_first_with_count
  test_last_with_count
  test_include_with_various_types
  test_uniq_removes_duplicates
  test_uniq_returns_same_for_no_duplicates
  test_flatten_returns_one_dimensional
  test_flatten_with_depth
  test_zip_merges_elements
  test_zip_fills_nil_for_shorter
  test_take_returns_first_n
  test_drop_returns_remaining
  spec_summary
end

run_tests
