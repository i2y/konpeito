require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/kernel/* - common Kernel methods

# Kernel#freeze / Kernel#frozen? (core/kernel/freeze_spec.rb, frozen_spec.rb)
def test_freeze_integer
  x = 42
  assert_true(x.frozen?, "Integer is always frozen")
end

def test_freeze_symbol
  assert_true(:hello.frozen?, "Symbol is always frozen")
end

def test_freeze_array
  arr = [1, 2, 3]
  assert_false(arr.frozen?, "Array is not frozen by default")
  arr.freeze
  assert_true(arr.frozen?, "Array#freeze makes the array frozen")
end

# Kernel#nil? (core/kernel/nil_spec.rb)
def test_nil_predicate
  assert_true(nil.nil?, "nil.nil? returns true")
  assert_false(0.nil?, "0.nil? returns false")
  assert_false("".nil?, "empty string.nil? returns false")
  assert_false(false.nil?, "false.nil? returns false")
end

# Kernel#respond_to? (core/kernel/respond_to_spec.rb)
def test_respond_to
  assert_true("hello".respond_to?(:length), "String responds to :length")
  assert_true([1, 2].respond_to?(:push), "Array responds to :push")
  assert_false(42.respond_to?(:push), "Integer does not respond to :push")
end

# Kernel#is_a? / kind_of? / instance_of? (core/kernel/is_a_spec.rb)
def test_is_a_hierarchy
  assert_true(42.is_a?(Integer), "42 is_a? Integer")
  assert_true(42.is_a?(Numeric), "42 is_a? Numeric")
  assert_true(42.is_a?(Object), "42 is_a? Object")
  assert_false(42.is_a?(String), "42 is not a String")
end

def test_kind_of
  assert_true("hello".kind_of?(String), "String kind_of? String")
  assert_true("hello".kind_of?(Object), "String kind_of? Object")
end

# Kernel#Integer (core/kernel/Integer_spec.rb)
def test_kernel_integer_conversion
  assert_equal(42, Integer("42"), "Integer() converts string to integer")
  assert_equal(42, Integer(42), "Integer() returns integer unchanged")
  assert_equal(255, Integer("0xFF"), "Integer() converts hex string")
end

def run_tests
  spec_reset
  test_freeze_integer
  test_freeze_symbol
  test_freeze_array
  test_nil_predicate
  test_respond_to
  test_is_a_hierarchy
  test_kind_of
  test_kernel_integer_conversion
  spec_summary
end

run_tests
