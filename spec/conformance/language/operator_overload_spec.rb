require_relative "../lib/konpeito_spec"

# Tests operator overloading on user-defined classes

class OpVec
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

  def +(other)
    OpVec.new(@x + other.x, @y + other.y)
  end

  def -(other)
    OpVec.new(@x - other.x, @y - other.y)
  end

  def ==(other)
    @x == other.x && @y == other.y
  end
end

class OpScalable
  def initialize(value)
    @value = value
  end

  def value
    @value
  end

  def *(factor)
    OpScalable.new(@value * factor)
  end

  def /(divisor)
    OpScalable.new(@value / divisor)
  end
end

class OpContainer
  def initialize
    @data = {}
  end

  def []=(key, val)
    @data[key] = val
  end

  def [](key)
    @data[key]
  end
end

class OpComparable
  def initialize(val)
    @val = val
  end

  def val
    @val
  end

  def <=>(other)
    @val <=> other.val
  end
end

def test_op_plus
  v1 = OpVec.new(1, 2)
  v2 = OpVec.new(3, 4)
  v3 = v1 + v2
  assert_equal(4, v3.x, "operator + on x component")
  assert_equal(6, v3.y, "operator + on y component")
end

def test_op_minus
  v1 = OpVec.new(5, 8)
  v2 = OpVec.new(2, 3)
  v3 = v1 - v2
  assert_equal(3, v3.x, "operator - on x component")
  assert_equal(5, v3.y, "operator - on y component")
end

def test_op_equals
  v1 = OpVec.new(1, 2)
  v2 = OpVec.new(1, 2)
  v3 = OpVec.new(3, 4)
  assert_true(v1 == v2, "operator == returns true for equal vectors")
  assert_false(v1 == v3, "operator == returns false for different vectors")
end

def test_op_chain
  v1 = OpVec.new(1, 1)
  v2 = OpVec.new(2, 2)
  v3 = OpVec.new(3, 3)
  result = v1 + v2 + v3
  assert_equal(6, result.x, "chained + on x component")
  assert_equal(6, result.y, "chained + on y component")
end

def test_op_multiply
  s = OpScalable.new(10)
  result = s * 3
  assert_equal(30, result.value, "operator * scales value")
end

def test_op_divide
  s = OpScalable.new(20)
  result = s / 4
  assert_equal(5, result.value, "operator / divides value")
end

def test_op_indexer_set_and_get
  c = OpContainer.new
  c["name"] = "Alice"
  c["age"] = 30
  assert_equal("Alice", c["name"], "operator []= and [] for string key")
  assert_equal(30, c["age"], "operator []= and [] for integer value")
end

def test_op_spaceship
  a = OpComparable.new(5)
  b = OpComparable.new(10)
  c = OpComparable.new(5)
  assert_equal(-1, a <=> b, "<=> returns -1 when less")
  assert_equal(1, b <=> a, "<=> returns 1 when greater")
  assert_equal(0, a <=> c, "<=> returns 0 when equal")
end

def run_tests
  spec_reset
  test_op_plus
  test_op_minus
  test_op_equals
  test_op_chain
  test_op_multiply
  test_op_divide
  test_op_indexer_set_and_get
  test_op_spaceship
  spec_summary
end

run_tests
