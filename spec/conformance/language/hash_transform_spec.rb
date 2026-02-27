require_relative "../lib/konpeito_spec"

# Hash transformation methods

def test_hash_transform_keys
  h = {a: 1, b: 2, c: 3}
  result = h.transform_keys { |k| k.to_s }
  assert_equal("a", result.keys[0], "transform_keys converts symbol keys to strings")
  assert_equal(1, result["a"], "transform_keys preserves values")
end

def test_hash_transform_values
  h = {a: 1, b: 2, c: 3}
  result = h.transform_values { |v| v * 10 }
  assert_equal(10, result[:a], "transform_values multiplies value a")
  assert_equal(20, result[:b], "transform_values multiplies value b")
  assert_equal(30, result[:c], "transform_values multiplies value c")
end

def test_hash_filter_map_as_select_map
  h = {a: 1, b: 2, c: 3, d: 4}
  result = h.select { |k, v| v > 2 }.map { |k, v| [k, v * 2] }.to_h
  assert_equal(6, result[:c], "select+map equivalent gives correct result for c")
  assert_equal(8, result[:d], "select+map equivalent gives correct result for d")
end

def test_hash_dig
  h = {a: {b: {c: 42}}}
  assert_equal(42, h.dig(:a, :b, :c), "dig accesses nested hash")
  assert_nil(h.dig(:a, :x, :c), "dig returns nil for missing key")
end

def test_hash_fetch_with_default
  h = {a: 1}
  assert_equal(1, h.fetch(:a), "fetch returns value for existing key")
  assert_equal(99, h.fetch(:b, 99), "fetch returns default for missing key")
end

def test_hash_fetch_with_block
  h = {a: 1}
  result = h.fetch(:missing) { |k| -1 }
  assert_equal(-1, result, "fetch with block calls block for missing key")
end

def test_hash_slice
  h = {a: 1, b: 2, c: 3, d: 4}
  result = h.slice(:a, :c)
  assert_equal(1, result[:a], "slice includes key a")
  assert_equal(3, result[:c], "slice includes key c")
  assert_equal(2, result.size, "slice returns only requested keys")
end

def test_hash_except
  h = {a: 1, b: 2, c: 3}
  result = h.except(:b)
  assert_equal(1, result[:a], "except keeps key a")
  assert_equal(3, result[:c], "except keeps key c")
  assert_nil(result[:b], "except removes key b")
end

def test_hash_compact
  h = {a: 1, b: nil, c: 3, d: nil}
  result = h.compact
  assert_equal(1, result[:a], "compact keeps non-nil a")
  assert_equal(3, result[:c], "compact keeps non-nil c")
  assert_equal(2, result.size, "compact removes nil values")
end

def test_hash_invert
  h = {a: 1, b: 2}
  result = h.invert
  assert_equal(:a, result[1], "invert swaps keys and values for 1")
  assert_equal(:b, result[2], "invert swaps keys and values for 2")
end

def run_tests
  spec_reset
  test_hash_transform_keys
  test_hash_transform_values
  test_hash_filter_map_as_select_map
  test_hash_dig
  test_hash_fetch_with_default
  test_hash_fetch_with_block
  test_hash_slice
  test_hash_except
  test_hash_compact
  test_hash_invert
  spec_summary
end

run_tests
