require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/super_spec.rb

class SupBase
  def greet(name)
    "Hello, " + name
  end

  def value
    10
  end
end

class SupChild < SupBase
  def greet(name)
    super(name) + "!"
  end

  def value
    super + 5
  end
end

class SupGrandparent
  def who
    "grandparent"
  end
end

class SupParent < SupGrandparent
  def who
    "parent"
  end
end

class SupGrandchild < SupParent
  def who
    super + " -> child"
  end
end

class SupInitBase
  def initialize(x)
    @x = x
  end

  def x
    @x
  end
end

class SupInitChild < SupInitBase
  def initialize(x, y)
    super(x)
    @y = y
  end

  def y
    @y
  end
end

class SupAccum
  def compute(n)
    n
  end
end

class SupDouble < SupAccum
  def compute(n)
    super(n) * 2
  end
end

class SupAddTen < SupDouble
  def compute(n)
    super(n) + 10
  end
end

class SupBaseDefault
  def greet(name = "World")
    "Hello, " + name
  end
end

class SupChildDefault < SupBaseDefault
  def greet(name = "World")
    super(name) + "!!"
  end
end

def test_super_with_args
  c = SupChild.new
  assert_equal("Hello, Alice!", c.greet("Alice"), "super passes args to parent method")
end

def test_super_with_arithmetic
  c = SupChild.new
  assert_equal(15, c.value, "super returns parent value for arithmetic")
end

def test_super_chain_two_levels
  gc = SupGrandchild.new
  assert_equal("parent -> child", gc.who, "super chains through two levels")
end

def test_super_in_initialize
  c = SupInitChild.new(1, 2)
  assert_equal(1, c.x, "super in initialize sets parent ivar")
  assert_equal(2, c.y, "child initialize sets own ivar")
end

def test_super_multi_level_computation
  obj = SupAddTen.new
  result = obj.compute(5)
  assert_equal(20, result, "multi-level super: (5 * 2) + 10 = 20")
end

def test_super_with_default_args
  c = SupChildDefault.new
  assert_equal("Hello, World!!", c.greet, "super with default args works")
  assert_equal("Hello, Ruby!!", c.greet("Ruby"), "super with explicit args works")
end

def run_tests
  spec_reset
  test_super_with_args
  test_super_with_arithmetic
  test_super_chain_two_levels
  test_super_in_initialize
  test_super_multi_level_computation
  test_super_with_default_args
  spec_summary
end

run_tests
