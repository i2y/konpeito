require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/singleton_class_spec.rb

class ScPerson
  class << self
    def species
      "human"
    end

    def greeting
      "hello"
    end
  end

  def initialize(name)
    @name = name
  end

  def name
    @name
  end
end

module ScHelper
  class << self
    def utility
      "useful"
    end

    def version
      42
    end
  end
end

class ScMixed
  def self.regular_class_method
    "regular"
  end

  class << self
    def singleton_method
      "singleton"
    end
  end
end

class ScBase
  class << self
    def base_class_method
      "base"
    end
  end
end

class ScChild < ScBase
  class << self
    def child_class_method
      "child"
    end
  end
end

def test_singleton_class_defines_class_method
  assert_equal("human", ScPerson.species, "class << self defines class method")
end

def test_singleton_class_multiple_methods
  assert_equal("hello", ScPerson.greeting, "class << self second method works")
end

def test_singleton_class_instance_still_works
  p = ScPerson.new("Alice")
  assert_equal("Alice", p.name, "instance methods still work with singleton class")
end

def test_singleton_class_in_module
  assert_equal("useful", ScHelper.utility, "class << self in module defines module method")
  assert_equal(42, ScHelper.version, "class << self in module second method works")
end

def test_singleton_class_coexists_with_def_self
  assert_equal("regular", ScMixed.regular_class_method, "def self.method still works")
  assert_equal("singleton", ScMixed.singleton_method, "class << self method works alongside")
end

def test_singleton_class_with_inheritance
  assert_equal("base", ScChild.base_class_method, "inherited class method from singleton class")
  assert_equal("child", ScChild.child_class_method, "own singleton class method works")
end

def run_tests
  spec_reset
  test_singleton_class_defines_class_method
  test_singleton_class_multiple_methods
  test_singleton_class_instance_still_works
  test_singleton_class_in_module
  test_singleton_class_coexists_with_def_self
  test_singleton_class_with_inheritance
  spec_summary
end

run_tests
