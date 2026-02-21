require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/class_spec.rb (re-opening)

class OcAnimal
  def speak
    "..."
  end
end

class OcAnimal
  def name
    "animal"
  end
end

class OcCounter
  def initialize
    @count = 0
  end

  def count
    @count
  end
end

class OcCounter
  def increment
    @count = @count + 1
  end

  def reset
    @count = 0
  end
end

class OcBase
  def base_method
    "from_base"
  end
end

class OcBase
  def added_method
    "added"
  end
end

def test_open_class_adds_method
  a = OcAnimal.new
  assert_equal("animal", a.name, "re-opened class adds new method")
end

def test_open_class_preserves_existing_method
  a = OcAnimal.new
  assert_equal("...", a.speak, "re-opened class preserves existing method")
end

def test_open_class_adds_multiple_methods
  c = OcCounter.new
  c.increment
  c.increment
  assert_equal(2, c.count, "re-opened class methods work together")
  c.reset
  assert_equal(0, c.count, "re-opened class reset method works")
end

def test_open_class_original_initialize_works
  c = OcCounter.new
  assert_equal(0, c.count, "original initialize still works after re-open")
end

def test_open_class_both_definitions_available
  b = OcBase.new
  assert_equal("from_base", b.base_method, "original method available")
  assert_equal("added", b.added_method, "method from re-opened class available")
end

def test_open_core_class_integer
  # Integer#even? and Integer#odd? are built-in, test calling them
  assert_true(4.even?, "Integer#even? works on core class")
  assert_false(3.even?, "Integer#even? returns false for odd")
end

def test_open_core_class_string
  # String built-in methods
  assert_equal(5, "hello".length, "String#length works on core class")
  assert_equal("HELLO", "hello".upcase, "String#upcase works on core class")
end

def run_tests
  spec_reset
  test_open_class_adds_method
  test_open_class_preserves_existing_method
  test_open_class_adds_multiple_methods
  test_open_class_original_initialize_works
  test_open_class_both_definitions_available
  test_open_core_class_integer
  test_open_core_class_string
  spec_summary
end

run_tests
