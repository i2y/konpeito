require_relative "../lib/konpeito_spec"

# Proc and lambda features

def test_lambda_call
  add = ->(a, b) { a + b }
  assert_equal(5, add.call(2, 3), "lambda call with two args")
end

def test_proc_call
  double = Proc.new { |x| x * 2 }
  assert_equal(10, double.call(5), "Proc#call works")
end

def test_symbol_to_proc_map
  words = ["hello", "world"]
  result = words.map(&:upcase)
  assert_equal("HELLO", result[0], "Symbol#to_proc converts symbol to proc for map")
  assert_equal("WORLD", result[1], "Symbol#to_proc works for all elements")
end

def test_symbol_to_proc_select
  nums = [1, 2, 3, 4, 5, 6]
  evens = nums.select(&:even?)
  assert_equal(3, evens.length, "Symbol#to_proc works with select")
  assert_equal(2, evens[0], "Symbol#to_proc select keeps even numbers")
end

def test_lambda_as_block
  double = ->(x) { x * 2 }
  result = [1, 2, 3].map(&double)
  assert_equal([2, 4, 6], result, "lambda as block argument works")
end

def test_proc_closures
  x = 10
  add_x = ->(n) { n + x }
  assert_equal(15, add_x.call(5), "lambda captures outer variable")
  x = 20
  assert_equal(25, add_x.call(5), "lambda sees updated outer variable")
end

def run_tests
  spec_reset
  test_lambda_call
  test_proc_call
  test_symbol_to_proc_map
  test_symbol_to_proc_select
  test_lambda_as_block
  test_proc_closures
  spec_summary
end

run_tests
