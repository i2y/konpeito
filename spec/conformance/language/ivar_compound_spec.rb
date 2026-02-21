require_relative "../lib/konpeito_spec"

# Tests compound assignment operators on instance variables

class IcAccumulator
  def initialize
    @value = 0
  end

  def value
    @value
  end

  def add(n)
    @value += n
  end

  def subtract(n)
    @value -= n
  end

  def multiply(n)
    @value *= n
  end
end

class IcOrAssign
  def initialize
    @data = nil
  end

  def data
    @data
  end

  def ensure_data
    @data ||= "default"
  end

  def set_data(v)
    @data = v
  end
end

class IcAndAssign
  def initialize(val)
    @val = val
  end

  def val
    @val
  end

  def and_assign(v)
    @val &&= v
  end
end

class IcLoop
  def initialize
    @sum = 0
  end

  def sum
    @sum
  end

  def accumulate(n)
    i = 0
    while i < n
      @sum += i
      i = i + 1
    end
  end
end

def test_ivar_plus_equals
  acc = IcAccumulator.new
  acc.add(5)
  acc.add(3)
  assert_equal(8, acc.value, "@value += n accumulates correctly")
end

def test_ivar_minus_equals
  acc = IcAccumulator.new
  acc.add(10)
  acc.subtract(3)
  assert_equal(7, acc.value, "@value -= n subtracts correctly")
end

def test_ivar_multiply_equals
  acc = IcAccumulator.new
  acc.add(5)
  acc.multiply(3)
  assert_equal(15, acc.value, "@value *= n multiplies correctly")
end

def test_ivar_or_assign_nil
  obj = IcOrAssign.new
  obj.ensure_data
  assert_equal("default", obj.data, "@data ||= assigns when nil")
end

def test_ivar_or_assign_existing
  obj = IcOrAssign.new
  obj.set_data("custom")
  obj.ensure_data
  assert_equal("custom", obj.data, "@data ||= does not overwrite existing value")
end

def test_ivar_and_assign_truthy
  obj = IcAndAssign.new(10)
  obj.and_assign(42)
  assert_equal(42, obj.val, "@val &&= assigns when truthy")
end

def test_ivar_and_assign_nil
  obj = IcAndAssign.new(nil)
  obj.and_assign(42)
  assert_nil(obj.val, "@val &&= does not assign when nil")
end

def test_ivar_compound_in_loop
  obj = IcLoop.new
  obj.accumulate(5)
  assert_equal(10, obj.sum, "@sum += i in loop: 0+1+2+3+4 = 10")
end

def run_tests
  spec_reset
  test_ivar_plus_equals
  test_ivar_minus_equals
  test_ivar_multiply_equals
  test_ivar_or_assign_nil
  test_ivar_or_assign_existing
  test_ivar_and_assign_truthy
  test_ivar_and_assign_nil
  test_ivar_compound_in_loop
  spec_summary
end

run_tests
