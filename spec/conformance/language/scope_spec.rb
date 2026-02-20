require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/variables_spec.rb (scope section)

# Helper methods for scope isolation tests

def scope_helper_a
  x = 100
  x
end

def scope_helper_b
  x = 200
  x
end

def scope_param_method(val)
  val + 1
end

def scope_nested_outer
  a = 10
  b = scope_nested_inner
  a + b
end

def scope_nested_inner
  a = 20
  a
end

# Tests

def test_local_variables_are_local_to_method
  x = 1
  scope_helper_a
  assert_equal(1, x, "local variable is not affected by another method defining same name")
end

def test_separate_methods_have_independent_locals
  a = scope_helper_a
  b = scope_helper_b
  assert_equal(100, a, "first method returns its own local value")
  assert_equal(200, b, "second method returns its own local value")
end

def test_method_parameters_are_local
  val = 42
  result = scope_param_method(10)
  assert_equal(11, result, "method parameter receives the passed argument")
  assert_equal(42, val, "caller variable named same as parameter is not affected")
end

def test_variable_defined_in_if_is_accessible_after
  if true
    x = 10
  end
  assert_equal(10, x, "variable assigned in if body is accessible after the if")
end

def test_variable_defined_in_else_is_accessible_after
  if false
    x = 5
  else
    x = 20
  end
  assert_equal(20, x, "variable assigned in else branch is accessible after the if")
end

def test_variable_defined_in_while_is_accessible_after
  i = 0
  while i < 3
    last = i
    i = i + 1
  end
  assert_equal(2, last, "variable assigned in while body is accessible after the loop")
end

def test_nested_method_calls_do_not_share_locals
  result = scope_nested_outer
  assert_equal(30, result, "nested method calls use their own independent local variables")
end

def test_block_can_access_outer_variables
  total = 0
  [1, 2, 3].each { |x| total = total + x }
  assert_equal(6, total, "block can read and modify variables from the enclosing scope")
end

def test_block_parameter_does_not_leak_to_outer_scope
  x = 99
  [1, 2, 3].each { |x| x }
  assert_equal(99, x, "block parameter does not overwrite outer variable of same name after block")
end

def test_assignment_in_conditional_creates_variable
  if true
    new_var = "created"
  end
  assert_equal("created", new_var, "assignment in conditional creates variable in enclosing scope")
end

def run_tests
  spec_reset
  test_local_variables_are_local_to_method
  test_separate_methods_have_independent_locals
  test_method_parameters_are_local
  test_variable_defined_in_if_is_accessible_after
  test_variable_defined_in_else_is_accessible_after
  test_variable_defined_in_while_is_accessible_after
  test_nested_method_calls_do_not_share_locals
  test_block_can_access_outer_variables
  test_block_parameter_does_not_leak_to_outer_scope
  test_assignment_in_conditional_creates_variable
  spec_summary
end

run_tests
