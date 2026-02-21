require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/module_spec.rb

module ModGreeting
  def greet
    "hello"
  end
end

module ModFarewell
  def farewell
    "goodbye"
  end
end

class ModPerson
  include ModGreeting

  def name
    "Alice"
  end
end

class ModPolite
  include ModGreeting
  include ModFarewell
end

module ModUtils
  def self.double(x)
    x * 2
  end

  def self.triple(x)
    x * 3
  end
end

module ModConstants
  VERSION = "1.0"
  MAX = 100
end

module ModBase
  def speak
    "base"
  end
end

class ModOverride
  include ModBase

  def speak
    "override"
  end
end

module ModPrepended
  def speak
    "prepended"
  end
end

class ModPrependTarget
  def speak
    "original"
  end
end

class ModPrependTarget
  prepend ModPrepended
end

module ModExtended
  def class_hello
    "class_hello"
  end
end

class ModExtendTarget
  extend ModExtended
end

def test_module_include_provides_instance_methods
  p = ModPerson.new
  assert_equal("hello", p.greet, "include adds module methods as instance methods")
end

def test_module_include_coexists_with_class_methods
  p = ModPerson.new
  assert_equal("Alice", p.name, "class own methods still work after include")
end

def test_module_multiple_includes
  p = ModPolite.new
  assert_equal("hello", p.greet, "first included module method works")
  assert_equal("goodbye", p.farewell, "second included module method works")
end

def test_module_singleton_method
  assert_equal(6, ModUtils.double(3), "module def self.method works")
  assert_equal(9, ModUtils.triple(3), "second module singleton method works")
end

def test_module_constants
  assert_equal("1.0", ModConstants::VERSION, "module constant string accessible")
  assert_equal(100, ModConstants::MAX, "module constant integer accessible")
end

def test_class_overrides_module_method
  o = ModOverride.new
  assert_equal("override", o.speak, "class method overrides included module method")
end

def test_prepend_overrides_class_method
  t = ModPrependTarget.new
  assert_equal("prepended", t.speak, "prepend overrides the class method")
end

def test_extend_adds_class_methods
  assert_equal("class_hello", ModExtendTarget.class_hello, "extend adds module methods as class methods")
end

def test_module_is_a_check
  p = ModPerson.new
  assert_true(p.is_a?(ModGreeting), "instance is_a? returns true for included module")
  assert_true(p.is_a?(ModPerson), "instance is_a? returns true for own class")
end

def run_tests
  spec_reset
  test_module_include_provides_instance_methods
  test_module_include_coexists_with_class_methods
  test_module_multiple_includes
  test_module_singleton_method
  test_module_constants
  test_class_overrides_module_method
  test_prepend_overrides_class_method
  test_extend_adds_class_methods
  test_module_is_a_check
  spec_summary
end

run_tests
