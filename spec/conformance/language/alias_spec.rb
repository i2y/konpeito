require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/alias_spec.rb

class AlBasic
  def original
    "original"
  end

  alias copied original
end

class AlWithArgs
  def add(a, b)
    a + b
  end

  alias sum add
end

class AlMethod
  def greet
    "hello"
  end

  alias_method :hi, :greet
end

class AlMethodArgs
  def multiply(a, b)
    a * b
  end

  alias_method :product, :multiply
end

class AlChain
  def base
    "base"
  end

  alias step1 base
  alias step2 step1
end

class AlOverride
  def speak
    "old"
  end

  alias old_speak speak

  def speak
    "new"
  end
end

def test_alias_keyword_basic
  obj = AlBasic.new
  assert_equal("original", obj.original, "original method works")
  assert_equal("original", obj.copied, "alias copies method behavior")
end

def test_alias_keyword_with_args
  obj = AlWithArgs.new
  assert_equal(7, obj.add(3, 4), "original method with args works")
  assert_equal(7, obj.sum(3, 4), "alias with args works identically")
end

def test_alias_method_basic
  obj = AlMethod.new
  assert_equal("hello", obj.greet, "original method works")
  assert_equal("hello", obj.hi, "alias_method copies method behavior")
end

def test_alias_method_with_args
  obj = AlMethodArgs.new
  assert_equal(12, obj.multiply(3, 4), "original method with args works")
  assert_equal(12, obj.product(3, 4), "alias_method with args works identically")
end

def test_alias_chain
  obj = AlChain.new
  assert_equal("base", obj.base, "base method works")
  assert_equal("base", obj.step1, "first alias works")
  assert_equal("base", obj.step2, "chained alias works")
end

def test_alias_preserves_old_behavior
  obj = AlOverride.new
  assert_equal("new", obj.speak, "redefined method returns new value")
  assert_equal("old", obj.old_speak, "alias preserves old behavior after redefine")
end

def run_tests
  spec_reset
  test_alias_keyword_basic
  test_alias_keyword_with_args
  test_alias_method_basic
  test_alias_method_with_args
  test_alias_chain
  test_alias_preserves_old_behavior
  spec_summary
end

run_tests
