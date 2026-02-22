require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/proc/* and core/lambda/* - advanced features

# Lambda arity
def test_lambda_arity_zero
  f = -> { 42 }
  assert_equal(0, f.arity, "lambda with no args has arity 0")
end

def test_lambda_arity_one
  f = -> (x) { x }
  assert_equal(1, f.arity, "lambda with one arg has arity 1")
end

def test_lambda_arity_two
  f = -> (a, b) { a + b }
  assert_equal(2, f.arity, "lambda with two args has arity 2")
end

# Lambda is_a? Proc
def test_lambda_is_proc
  f = -> { 42 }
  assert_true(f.is_a?(Proc), "lambda is_a? Proc")
end

# Lambda#lambda?
def test_lambda_predicate
  f = -> { 42 }
  assert_true(f.lambda?, "lambda#lambda? returns true")
end

# Closure mutation
def test_lambda_closure_mutation
  x = 0
  inc = -> { x = x + 1 }
  inc.call
  inc.call
  inc.call
  assert_equal(3, x, "lambda closure can mutate captured variable")
end

# Higher-order: lambda returning lambda
def test_lambda_returning_lambda
  adder = -> (n) { -> (x) { x + n } }
  add5 = adder.call(5)
  assert_equal(15, add5.call(10), "lambda returning lambda captures outer variable")
  assert_equal(8, add5.call(3), "lambda returning lambda reuses captured value")
end

# Passing block with &
def helper_with_block(arr, &blk)
  arr.map(&blk)
end

def test_block_parameter
  result = helper_with_block([1, 2, 3]) { |x| x * 10 }
  assert_equal(10, result[0], "&block parameter captures and passes block")
  assert_equal(30, result[2], "&block parameter works with map")
end

def run_tests
  spec_reset
  test_lambda_arity_zero
  test_lambda_arity_one
  test_lambda_arity_two
  test_lambda_is_proc
  test_lambda_predicate
  test_lambda_closure_mutation
  test_lambda_returning_lambda
  test_block_parameter
  spec_summary
end

run_tests
