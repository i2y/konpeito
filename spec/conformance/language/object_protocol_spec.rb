require_relative "../lib/konpeito_spec"

# Object protocol methods

def test_object_tap
  result = [1, 2, 3].tap { |a| a.push(4) }
  assert_equal(4, result.length, "tap returns receiver and executes block")
  assert_equal(4, result[-1], "tap block can modify receiver")
end

def test_object_then
  result = 5.then { |n| n * 2 }
  assert_equal(10, result, "then returns block result")
end

def test_object_yield_self
  result = "hello".yield_self { |s| s.upcase }
  assert_equal("HELLO", result, "yield_self is alias for then")
end

def test_object_respond_to_public
  assert_true("hello".respond_to?(:upcase), "respond_to? returns true for public method")
  assert_true(!("hello".respond_to?(:nonexistent)), "respond_to? returns false for missing method")
end

def test_object_send_public
  result = "hello".send(:upcase)
  assert_equal("HELLO", result, "send calls public method by name")
end

def test_object_send_with_args
  result = [1, 2, 3].send(:push, 4)
  assert_equal(4, result.length, "send with arguments works")
end

def test_object_nil_nil_q
  assert_true(nil.nil?, "nil.nil? returns true")
  assert_true(!(42.nil?), "42.nil? returns false")
  assert_true(!("hello".nil?), "string.nil? returns false")
end

def test_object_freeze_and_frozen_q
  str = "mutable"
  assert_true(!str.frozen?, "unfrozen string is not frozen")
  str.freeze
  assert_true(str.frozen?, "frozen string is frozen")
end

def test_integer_always_frozen
  assert_true(42.frozen?, "integers are always frozen")
end

def test_symbol_always_frozen
  assert_true(:hello.frozen?, "symbols are always frozen")
end

def test_object_is_a_q
  assert_true(42.is_a?(Integer), "42 is_a? Integer")
  assert_true("hello".is_a?(String), "string is_a? String")
  assert_true([].is_a?(Array), "array is_a? Array")
end

def test_object_class
  assert_equal(Integer, 42.class, "42.class is Integer")
  assert_equal(String, "hello".class, "string.class is String")
end

def run_tests
  spec_reset
  test_object_tap
  test_object_then
  test_object_yield_self
  test_object_respond_to_public
  test_object_send_public
  test_object_send_with_args
  test_object_nil_nil_q
  test_object_freeze_and_frozen_q
  test_integer_always_frozen
  test_symbol_always_frozen
  test_object_is_a_q
  test_object_class
  spec_summary
end

run_tests
