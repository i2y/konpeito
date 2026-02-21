require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/private_spec.rb, protected_spec.rb, public_spec.rb

class VisBasic
  def public_method
    "public"
  end

  private

  def secret
    "secret"
  end
end

class VisWrapper
  def public_method
    "public"
  end

  def call_secret
    secret
  end

  private

  def secret
    "hidden"
  end
end

class VisNamed
  def foo
    "foo"
  end

  def bar
    "bar"
  end

  private :bar
end

class VisNamedWrapper
  def foo
    "foo"
  end

  def bar
    "bar"
  end

  def call_bar
    bar
  end

  private :bar
end

class VisProtected
  def public_method
    "public"
  end

  def compare(other)
    value == other.value
  end

  protected

  def value
    42
  end
end

class VisMultiple
  def a
    "a"
  end

  private

  def b
    "b"
  end

  def c
    "c"
  end

  public

  def d
    "d"
  end
end

class VisMultipleWrapper
  def a
    "a"
  end

  def call_b
    b
  end

  def call_c
    c
  end

  private

  def b
    "b"
  end

  def c
    "c"
  end

  public

  def d
    "d"
  end
end

def test_public_method_accessible
  obj = VisBasic.new
  assert_equal("public", obj.public_method, "public method is accessible from outside")
end

def test_private_method_via_wrapper
  obj = VisWrapper.new
  assert_equal("hidden", obj.call_secret, "private method callable from within class")
end

def test_private_named_public_still_works
  obj = VisNamed.new
  assert_equal("foo", obj.foo, "non-private method still accessible after private :bar")
end

def test_private_named_via_wrapper
  obj = VisNamedWrapper.new
  assert_equal("bar", obj.call_bar, "private :name method callable from within class")
end

def test_protected_method_comparison
  a = VisProtected.new
  b = VisProtected.new
  assert_true(a.compare(b), "protected method accessible from same class instance")
end

def test_multiple_visibility_sections
  obj = VisMultiple.new
  assert_equal("a", obj.a, "method before private is public")
  assert_equal("d", obj.d, "method after public is public")
end

def test_multiple_visibility_private_accessible_internally
  obj = VisMultipleWrapper.new
  assert_equal("b", obj.call_b, "first private method accessible internally")
  assert_equal("c", obj.call_c, "second private method accessible internally")
end

def run_tests
  spec_reset
  test_public_method_accessible
  test_private_method_via_wrapper
  test_private_named_public_still_works
  test_private_named_via_wrapper
  test_protected_method_comparison
  test_multiple_visibility_sections
  test_multiple_visibility_private_accessible_internally
  spec_summary
end

run_tests
