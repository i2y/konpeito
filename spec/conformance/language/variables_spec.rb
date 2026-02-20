require_relative "../lib/konpeito_spec"

def test_local_variable_assignment
  x = 42
  assert_equal(42, x, "local variable assignment and read")
end

def test_local_variable_reassignment
  x = 1
  x = 2
  x = 3
  assert_equal(3, x, "local variable reassignment uses latest value")
end

def test_local_variable_shadowing_in_method
  x = 10
  assert_equal(10, x, "local variable visible within method")
end

def test_local_compound_assignment
  x = 10
  x += 5
  assert_equal(15, x, "+= compound assignment")
end

def test_local_compound_subtract
  x = 10
  x -= 3
  assert_equal(7, x, "-= compound assignment")
end

def test_local_compound_multiply
  x = 4
  x *= 3
  assert_equal(12, x, "*= compound assignment")
end

def test_local_or_assign_nil
  x = nil
  x ||= 42
  assert_equal(42, x, "||= assigns when nil")
end

def test_local_or_assign_existing
  x = 10
  x ||= 42
  assert_equal(10, x, "||= does not assign when already truthy")
end

def test_global_variable
  $__test_global = 100
  assert_equal(100, $__test_global, "global variable assignment and read")
end

def set_global
  $__test_global2 = "hello"
end

def test_global_variable_across_methods
  set_global
  assert_equal("hello", $__test_global2, "global variable shared across methods")
end

def test_multiple_locals
  a = 1
  b = 2
  c = 3
  sum = a + b + c
  assert_equal(6, sum, "multiple local variables in one method")
end

def test_variable_swap
  a = 1
  b = 2
  temp = a
  a = b
  b = temp
  assert_equal(2, a, "variable swap: a becomes 2")
  assert_equal(1, b, "variable swap: b becomes 1")
end

def run_tests
  spec_reset
  test_local_variable_assignment
  test_local_variable_reassignment
  test_local_variable_shadowing_in_method
  test_local_compound_assignment
  test_local_compound_subtract
  test_local_compound_multiply
  test_local_or_assign_nil
  test_local_or_assign_existing
  test_global_variable
  test_global_variable_across_methods
  test_multiple_locals
  test_variable_swap
  spec_summary
end

run_tests
