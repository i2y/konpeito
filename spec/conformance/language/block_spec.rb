require_relative "../lib/konpeito_spec"

def yields_value
  yield 42
end

def test_yield_basic
  result = nil
  yields_value { |x| result = x }
  assert_equal(42, result, "yield passes value to block")
end

def yields_multiple
  yield 1
  yield 2
  yield 3
end

def test_yield_multiple_times
  sum = 0
  yields_multiple { |x| sum = sum + x }
  assert_equal(6, sum, "yield called multiple times accumulates")
end

def with_block_given
  if block_given?
    "block"
  else
    "no block"
  end
end

def test_block_given_true
  result = with_block_given { }
  assert_equal("block", result, "block_given? returns true when block given")
end

def test_block_given_false
  result = with_block_given
  assert_equal("no block", result, "block_given? returns false when no block")
end

def test_array_each
  sum = 0
  [1, 2, 3, 4, 5].each { |x| sum = sum + x }
  assert_equal(15, sum, "Array#each iterates over elements")
end

def test_array_map
  result = [1, 2, 3].map { |x| x * 2 }
  assert_equal(2, result[0], "Array#map element 0")
  assert_equal(4, result[1], "Array#map element 1")
  assert_equal(6, result[2], "Array#map element 2")
end

def test_array_select
  result = [1, 2, 3, 4, 5].select { |x| x > 3 }
  assert_equal(2, result.length, "Array#select returns matching elements count")
  assert_equal(4, result[0], "Array#select first match")
  assert_equal(5, result[1], "Array#select second match")
end

def yield_with_return
  yield 10
  "done"
end

def test_yield_return_value
  result = yield_with_return { |x| x * 2 }
  assert_equal("done", result, "method with yield returns its own last expression")
end

def run_tests
  spec_reset
  test_yield_basic
  test_yield_multiple_times
  test_block_given_true
  test_block_given_false
  test_array_each
  test_array_map
  test_array_select
  test_yield_return_value
  spec_summary
end

run_tests
