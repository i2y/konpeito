require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/attr_accessor, attr_reader, attr_writer

class AcReadOnly
  attr_reader :value

  def initialize(v)
    @value = v
  end
end

class AcWriteOnly
  attr_writer :value

  def initialize
    @value = 0
  end

  def get_value
    @value
  end
end

class AcReadWrite
  attr_accessor :name

  def initialize(n)
    @name = n
  end
end

class AcMultiple
  attr_accessor :x, :y, :z

  def initialize
    @x = 0
    @y = 0
    @z = 0
  end
end

class AcPerson
  attr_reader :name
  attr_accessor :age

  def initialize(name, age)
    @name = name
    @age = age
  end
end

def test_attr_reader_returns_value
  obj = AcReadOnly.new(42)
  assert_equal(42, obj.value, "attr_reader provides getter method")
end

def test_attr_writer_sets_value
  obj = AcWriteOnly.new
  obj.value = 99
  assert_equal(99, obj.get_value, "attr_writer provides setter method")
end

def test_attr_accessor_read
  obj = AcReadWrite.new("Alice")
  assert_equal("Alice", obj.name, "attr_accessor provides getter")
end

def test_attr_accessor_write
  obj = AcReadWrite.new("Alice")
  obj.name = "Bob"
  assert_equal("Bob", obj.name, "attr_accessor provides setter")
end

def test_attr_accessor_multiple
  obj = AcMultiple.new
  obj.x = 1
  obj.y = 2
  obj.z = 3
  assert_equal(1, obj.x, "attr_accessor :x works")
  assert_equal(2, obj.y, "attr_accessor :y works")
  assert_equal(3, obj.z, "attr_accessor :z works")
end

def test_attr_mixed_reader_and_accessor
  p = AcPerson.new("Alice", 30)
  assert_equal("Alice", p.name, "attr_reader name works")
  assert_equal(30, p.age, "attr_accessor age getter works")
  p.age = 31
  assert_equal(31, p.age, "attr_accessor age setter works")
end

def test_attr_accessor_initialized_in_constructor
  obj = AcMultiple.new
  assert_equal(0, obj.x, "attr_accessor returns initialized value")
end

def run_tests
  spec_reset
  test_attr_reader_returns_value
  test_attr_writer_sets_value
  test_attr_accessor_read
  test_attr_accessor_write
  test_attr_accessor_multiple
  test_attr_mixed_reader_and_accessor
  test_attr_accessor_initialized_in_constructor
  spec_summary
end

run_tests
