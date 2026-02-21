require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/class_variable_spec.rb

class CvCounter
  @@count = 0

  def self.count
    @@count
  end

  def self.reset
    @@count = 0
  end

  def increment
    @@count = @@count + 1
  end

  def current
    @@count
  end
end

class CvInitialized
  @@value = 42

  def self.value
    @@value
  end
end

class CvMultiple
  @@x = 1
  @@y = 2

  def self.x
    @@x
  end

  def self.y
    @@y
  end

  def self.sum
    @@x + @@y
  end
end

def test_class_variable_initial_value
  assert_equal(42, CvInitialized.value, "class variable has initial value")
end

def test_class_variable_from_class_method
  CvCounter.reset
  assert_equal(0, CvCounter.count, "class variable readable from class method")
end

def test_class_variable_from_instance_method
  CvCounter.reset
  c = CvCounter.new
  assert_equal(0, c.current, "class variable readable from instance method")
end

def test_class_variable_modified_by_instance
  CvCounter.reset
  c = CvCounter.new
  c.increment
  c.increment
  assert_equal(2, CvCounter.count, "class variable modified by instance visible to class")
end

def test_class_variable_shared_across_instances
  CvCounter.reset
  c1 = CvCounter.new
  c2 = CvCounter.new
  c1.increment
  c2.increment
  c2.increment
  assert_equal(3, c1.current, "class variable shared across all instances")
end

def test_class_variable_multiple
  assert_equal(1, CvMultiple.x, "first class variable accessible")
  assert_equal(2, CvMultiple.y, "second class variable accessible")
  assert_equal(3, CvMultiple.sum, "class variables usable in computation")
end

def run_tests
  spec_reset
  test_class_variable_initial_value
  test_class_variable_from_class_method
  test_class_variable_from_instance_method
  test_class_variable_modified_by_instance
  test_class_variable_shared_across_instances
  test_class_variable_multiple
  spec_summary
end

run_tests
