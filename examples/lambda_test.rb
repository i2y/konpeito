# Lambda/Proc test

def test_lambda_basic
  # Basic lambda
  double = ->(x) { x * 2 }
  double.call(21)
end

def test_lambda_multi_args
  # Lambda with multiple args
  add = ->(a, b) { a + b }
  add.call(10, 20)
end

def test_lambda_no_args
  # Lambda with no args
  get_value = -> { 42 }
  get_value.call
end
