require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/class/* and language/class_spec.rb

# Class.new / instantiation (core/class/new_spec.rb)
class SimpleAnimal
  def initialize(name)
    @name = name
  end

  def name
    @name
  end
end

def test_class_new_creates_instance
  a = SimpleAnimal.new("cat")
  assert_true(a.is_a?(SimpleAnimal), "Class.new creates an instance of the class")
end

def test_class_new_passes_args_to_initialize
  a = SimpleAnimal.new("dog")
  assert_equal("dog", a.name, "Class.new passes arguments to initialize")
end

# Instance methods (language/class_spec.rb)
class Calculator
  def add(a, b)
    a + b
  end

  def multiply(a, b)
    a * b
  end
end

def test_instance_method_call
  calc = Calculator.new
  assert_equal(7, calc.add(3, 4), "instance method returns computed value")
  assert_equal(12, calc.multiply(3, 4), "second instance method works independently")
end

# Instance variables via accessor methods (core/class/new_spec.rb)
class Counter
  def initialize
    @count = 0
  end

  def count
    @count
  end

  def increment
    @count = @count + 1
  end
end

def test_instance_variables_are_per_object
  c1 = Counter.new
  c2 = Counter.new
  c1.increment
  c1.increment
  c2.increment
  assert_equal(2, c1.count, "first counter incremented twice")
  assert_equal(1, c2.count, "second counter incremented once, independent of first")
end

# Class methods / def self.method (core/class/new_spec.rb)
class MathHelper
  def self.square(x)
    x * x
  end

  def self.double(x)
    x + x
  end
end

def test_class_method_call
  assert_equal(25, MathHelper.square(5), "class method def self.method can be called on the class")
  assert_equal(10, MathHelper.double(5), "second class method works independently")
end

# Inheritance (language/class_spec.rb, core/class/superclass_spec.rb)
class Shape
  def area
    0
  end

  def description
    "shape"
  end
end

class Circle < Shape
  def initialize(radius)
    @radius = radius
  end

  def area
    @radius * @radius * 3
  end
end

def test_inheritance_instance_of_subclass
  c = Circle.new(5)
  assert_true(c.is_a?(Circle), "instance is a Circle")
  assert_true(c.is_a?(Shape), "instance is also a Shape via inheritance")
end

def test_inherited_method
  c = Circle.new(5)
  assert_equal("shape", c.description, "subclass inherits methods from parent")
end

def test_method_override
  c = Circle.new(5)
  assert_equal(75, c.area, "subclass overrides parent method")
end

# super (language/super_spec.rb)
class Base
  def greet(name)
    "Hello, " + name
  end
end

class Derived < Base
  def greet(name)
    super(name) + "!"
  end
end

def test_super_calls_parent_method
  d = Derived.new
  assert_equal("Hello, Alice!", d.greet("Alice"), "super calls the parent class method")
end

# initialize with defaults (core/class/new_spec.rb)
class Greeter
  def initialize(greeting = "Hi")
    @greeting = greeting
  end

  def greet(name)
    @greeting + ", " + name
  end
end

def test_initialize_with_default_arg
  g1 = Greeter.new
  g2 = Greeter.new("Hey")
  assert_equal("Hi, World", g1.greet("World"), "initialize uses default argument")
  assert_equal("Hey, World", g2.greet("World"), "initialize uses provided argument")
end

# Multiple instance variables (language/class_spec.rb)
class Point
  def initialize(x, y)
    @x = x
    @y = y
  end

  def x
    @x
  end

  def y
    @y
  end

  def to_s
    "(" + @x.to_s + ", " + @y.to_s + ")"
  end
end

def test_multiple_instance_variables
  p = Point.new(3, 4)
  assert_equal(3, p.x, "first instance variable accessible via reader")
  assert_equal(4, p.y, "second instance variable accessible via reader")
end

def test_to_s_on_custom_class
  p = Point.new(3, 4)
  assert_equal("(3, 4)", p.to_s, "custom to_s returns formatted string")
end

# Instance method using other instance methods (language/class_spec.rb)
class Rectangle
  def initialize(w, h)
    @width = w
    @height = h
  end

  def width
    @width
  end

  def height
    @height
  end

  def area
    @width * @height
  end

  def perimeter
    2 * (@width + @height)
  end
end

def test_methods_using_instance_variables
  r = Rectangle.new(3, 5)
  assert_equal(15, r.area, "method computes using instance variables")
  assert_equal(16, r.perimeter, "another method computes using instance variables")
end

# Chained inheritance (core/class/superclass_spec.rb)
class A
  def who
    "A"
  end
end

class B < A
  def who
    "B"
  end
end

class C < B
end

def test_chained_inheritance
  c = C.new
  assert_true(c.is_a?(C), "instance is a C")
  assert_true(c.is_a?(B), "instance is a B via inheritance")
  assert_true(c.is_a?(A), "instance is an A via chained inheritance")
  assert_equal("B", c.who, "inherits nearest override from B, not A")
end

# class method and instance method coexistence
class Converter
  def self.to_celsius(f)
    (f - 32) * 5 / 9
  end

  def initialize(factor)
    @factor = factor
  end

  def convert(value)
    value * @factor
  end
end

def test_class_and_instance_methods_coexist
  assert_equal(100, Converter.to_celsius(212), "class method works")
  c = Converter.new(2)
  assert_equal(10, c.convert(5), "instance method works on same class")
end

def run_tests
  spec_reset
  test_class_new_creates_instance
  test_class_new_passes_args_to_initialize
  test_instance_method_call
  test_instance_variables_are_per_object
  test_class_method_call
  test_inheritance_instance_of_subclass
  test_inherited_method
  test_method_override
  test_super_calls_parent_method
  test_initialize_with_default_arg
  test_multiple_instance_variables
  test_to_s_on_custom_class
  test_methods_using_instance_variables
  test_chained_inheritance
  test_class_and_instance_methods_coexist
  spec_summary
end

run_tests
