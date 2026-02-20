require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/proc/* and core/lambda/*

# Lambda creation and call
def test_lambda_basic
  f = -> { 42 }
  result = f.call
  assert_equal(42, result, "lambda returns value from block")
end

def test_lambda_with_one_arg
  f = -> (x) { x * 2 }
  result = f.call(5)
  assert_equal(10, result, "lambda with one argument")
end

def test_lambda_with_two_args
  f = -> (a, b) { a + b }
  result = f.call(3, 7)
  assert_equal(10, result, "lambda with two arguments")
end

# Closure / captured variables
def test_lambda_captures_local
  x = 10
  f = -> { x + 5 }
  result = f.call
  assert_equal(15, result, "lambda captures surrounding local variable")
end

def test_lambda_captures_updated_value
  x = 1
  f = -> { x }
  x = 2
  result = f.call
  assert_equal(2, result, "lambda sees updated value of captured variable")
end

# Lambda returning various types
def test_lambda_returns_string
  f = -> { "hello" }
  result = f.call
  assert_equal("hello", result, "lambda returns string")
end

def test_lambda_returns_array
  f = -> { [1, 2, 3] }
  result = f.call
  arr = result
  assert_equal(3, arr.length, "lambda returns array with correct length")
end

# Lambda with computation
def test_lambda_computation
  square = -> (n) { n * n }
  assert_equal(1, square.call(1), "lambda square(1)")
  assert_equal(25, square.call(5), "lambda square(5)")
  assert_equal(100, square.call(10), "lambda square(10)")
end

# Multiple lambdas
def test_multiple_lambdas
  add = -> (a, b) { a + b }
  mul = -> (a, b) { a * b }
  assert_equal(7, add.call(3, 4), "first lambda (add)")
  assert_equal(12, mul.call(3, 4), "second lambda (mul)")
end

def run_tests
  spec_reset
  test_lambda_basic
  test_lambda_with_one_arg
  test_lambda_with_two_args
  test_lambda_captures_local
  test_lambda_captures_updated_value
  test_lambda_returns_string
  test_lambda_returns_array
  test_lambda_computation
  test_multiple_lambdas
  spec_summary
end

run_tests
