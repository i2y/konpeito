require_relative "../lib/konpeito_spec"

# Kernel formatting and output methods

def test_sprintf_integer
  assert_equal("42", sprintf("%d", 42), "sprintf %d formats integer")
end

def test_sprintf_string
  assert_equal("hello", sprintf("%s", "hello"), "sprintf %s formats string")
end

def test_sprintf_float
  assert_equal("3.14", sprintf("%.2f", 3.14159), "sprintf %.2f formats float with 2 decimal places")
end

def test_sprintf_multiple_args
  result = sprintf("%s is %d years old", "Alice", 30)
  assert_equal("Alice is 30 years old", result, "sprintf formats multiple arguments")
end

def test_format_alias
  assert_equal("42", format("%d", 42), "format is alias for sprintf")
end

def test_string_percent_format
  result = "Hello, %s!" % "world"
  assert_equal("Hello, world!", result, "String#% formats like sprintf")
end

def test_string_percent_format_multiple
  result = "%s is %d" % ["Alice", 30]
  assert_equal("Alice is 30", result, "String#% with array formats multiple args")
end

def test_raise_with_message
  caught = false
  begin
    raise "custom error message"
    assert_true(false, "raise should have raised RuntimeError")
  rescue RuntimeError
    caught = true
  end
  assert_true(caught, "raise with string raises RuntimeError")
end

def test_raise_runtimeerror_explicit
  caught = false
  begin
    raise RuntimeError, "test error"
    assert_true(false, "raise should have raised")
  rescue RuntimeError
    caught = true
  end
  assert_true(caught, "raise RuntimeError raises exception")
end

def test_rand_float_range
  r = rand
  assert_true(r >= 0.0, "rand returns value >= 0.0")
  assert_true(r < 1.0, "rand returns value < 1.0")
end

def test_rand_integer_range
  100.times do
    r = rand(10)
    assert_true(r >= 0, "rand(10) returns value >= 0")
    assert_true(r < 10, "rand(10) returns value < 10")
  end
end

def run_tests
  spec_reset
  test_sprintf_integer
  test_sprintf_string
  test_sprintf_float
  test_sprintf_multiple_args
  test_format_alias
  test_string_percent_format
  test_string_percent_format_multiple
  test_raise_with_message
  test_raise_runtimeerror_explicit
  test_rand_float_range
  test_rand_integer_range
  spec_summary
end

run_tests
