require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/constants_spec.rb

class CoMath
  PI = 3
  E = 2
end

module CoConfig
  VERSION = "2.0"
  DEBUG = false
end

class CoOuter
  LABEL = "outer"

  class CoInner
    LABEL = "inner"
  end
end

class CoMultiple
  A = 1
  B = 2
  C = 3

  def self.sum
    A + B + C
  end
end

class CoUsage
  FACTOR = 10

  def compute(x)
    x * FACTOR
  end
end

def test_class_constant_integer
  assert_equal(3, CoMath::PI, "class constant integer accessible via ::")
  assert_equal(2, CoMath::E, "second class constant integer accessible")
end

def test_module_constant_string
  assert_equal("2.0", CoConfig::VERSION, "module constant string accessible via ::")
end

def test_module_constant_boolean
  assert_false(CoConfig::DEBUG, "module constant boolean accessible via ::")
end

def test_constant_in_class_method
  assert_equal(6, CoMultiple.sum, "constants usable in class method computation")
end

def test_constant_in_instance_method
  obj = CoUsage.new
  assert_equal(50, obj.compute(5), "constant usable in instance method")
end

def test_nested_class_constants
  assert_equal("outer", CoOuter::LABEL, "outer class constant")
  assert_equal("inner", CoOuter::CoInner::LABEL, "nested class constant")
end

def test_defined_constant
  result = defined?(CoMath::PI)
  assert_equal("constant", result, "defined? returns 'constant' for existing constant")
end

def test_multiple_constants_independent
  assert_equal(1, CoMultiple::A, "first constant value")
  assert_equal(2, CoMultiple::B, "second constant value")
  assert_equal(3, CoMultiple::C, "third constant value")
end

def run_tests
  spec_reset
  test_class_constant_integer
  test_module_constant_string
  test_module_constant_boolean
  test_constant_in_class_method
  test_constant_in_instance_method
  test_nested_class_constants
  test_defined_constant
  test_multiple_constants_independent
  spec_summary
end

run_tests
