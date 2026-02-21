require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/global_variable_spec.rb

def gv_set_value
  $__gv_test1 = "from_method"
end

def gv_read_value
  $__gv_test1
end

def gv_set_number
  $__gv_num = 100
end

def gv_increment
  $__gv_num = $__gv_num + 1
end

def test_global_variable_assignment
  $__gv_basic = 42
  assert_equal(42, $__gv_basic, "global variable can be assigned and read")
end

def test_global_variable_string
  $__gv_str = "hello"
  assert_equal("hello", $__gv_str, "global variable holds string value")
end

def test_global_variable_across_methods
  gv_set_value
  result = gv_read_value
  assert_equal("from_method", result, "global variable shared across methods")
end

def test_global_variable_modification
  gv_set_number
  gv_increment
  gv_increment
  assert_equal(102, $__gv_num, "global variable can be modified across method calls")
end

def test_global_variable_multiple
  $__gv_a = 1
  $__gv_b = 2
  $__gv_c = 3
  sum = $__gv_a + $__gv_b + $__gv_c
  assert_equal(6, sum, "multiple global variables work independently")
end

def test_global_variable_reassignment
  $__gv_re = "first"
  $__gv_re = "second"
  assert_equal("second", $__gv_re, "global variable reassignment uses latest value")
end

def test_global_variable_boolean
  $__gv_flag = true
  assert_true($__gv_flag, "global variable holds true")
  $__gv_flag = false
  assert_false($__gv_flag, "global variable holds false after reassignment")
end

def run_tests
  spec_reset
  test_global_variable_assignment
  test_global_variable_string
  test_global_variable_across_methods
  test_global_variable_modification
  test_global_variable_multiple
  test_global_variable_reassignment
  test_global_variable_boolean
  spec_summary
end

run_tests
