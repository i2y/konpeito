require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/defined_spec.rb

# defined? with local variables
def test_defined_local_variable
  x = 10
  result = defined?(x)
  assert_equal("local-variable", result, "defined? returns 'local-variable' for a defined local")
end

# defined? with constants
def test_defined_constant_string
  result = defined?(String)
  assert_equal("constant", result, "defined? returns 'constant' for String")
end

def test_defined_constant_integer
  result = defined?(Integer)
  assert_equal("constant", result, "defined? returns 'constant' for Integer")
end

def test_defined_constant_nil_class
  result = defined?(NilClass)
  assert_equal("constant", result, "defined? returns 'constant' for NilClass")
end

# defined? with nil/true/false literals
def test_defined_nil
  result = defined?(nil)
  assert_equal("nil", result, "defined? returns 'nil' for nil literal")
end

def test_defined_true
  result = defined?(true)
  assert_equal("true", result, "defined? returns 'true' for true literal")
end

def test_defined_false
  result = defined?(false)
  assert_equal("false", result, "defined? returns 'false' for false literal")
end

def run_tests
  spec_reset
  test_defined_local_variable
  test_defined_constant_string
  test_defined_constant_integer
  test_defined_constant_nil_class
  test_defined_nil
  test_defined_true
  test_defined_false
  spec_summary
end

run_tests
