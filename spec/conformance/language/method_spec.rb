require_relative "../lib/konpeito_spec"

def simple_add(a, b)
  a + b
end

def test_method_basic_call
  result = simple_add(3, 4)
  assert_equal(7, result, "method with two args returns sum")
end

def returns_constant
  42
end

def test_method_returns_last_expression
  assert_equal(42, returns_constant, "method returns last expression")
end

def explicit_return(x)
  return x * 2
  999
end

def test_method_explicit_return
  assert_equal(10, explicit_return(5), "explicit return skips remaining code")
end

def early_return(x)
  if x > 0
    return "positive"
  end
  "non-positive"
end

def test_method_early_return
  assert_equal("positive", early_return(5), "early return from if")
  assert_equal("non-positive", early_return(-1), "falls through when condition false")
end

def with_default(x, y = 10)
  x + y
end

def test_method_default_args
  assert_equal(15, with_default(5), "default arg used when not provided")
  assert_equal(8, with_default(5, 3), "default arg overridden when provided")
end

def factorial(n)
  if n <= 1
    return 1
  end
  n * factorial(n - 1)
end

def test_method_recursion
  assert_equal(1, factorial(1), "factorial(1) = 1")
  assert_equal(6, factorial(3), "factorial(3) = 6")
  assert_equal(120, factorial(5), "factorial(5) = 120")
end

def fibonacci(n)
  if n <= 1
    return n
  end
  fibonacci(n - 1) + fibonacci(n - 2)
end

def test_method_fibonacci
  assert_equal(0, fibonacci(0), "fibonacci(0) = 0")
  assert_equal(1, fibonacci(1), "fibonacci(1) = 1")
  assert_equal(8, fibonacci(6), "fibonacci(6) = 8")
end

def with_keyword(name:, greeting: "Hello")
  greeting + ", " + name
end

def test_method_keyword_args
  assert_equal("Hello, Alice", with_keyword(name: "Alice"), "keyword arg with default")
  assert_equal("Hi, Bob", with_keyword(name: "Bob", greeting: "Hi"), "keyword arg override")
end

def no_args
  "no args"
end

def test_method_no_args
  assert_equal("no args", no_args, "method with no arguments")
end

def run_tests
  spec_reset
  test_method_basic_call
  test_method_returns_last_expression
  test_method_explicit_return
  test_method_early_return
  test_method_default_args
  test_method_recursion
  test_method_fibonacci
  test_method_keyword_args
  test_method_no_args
  spec_summary
end

run_tests
