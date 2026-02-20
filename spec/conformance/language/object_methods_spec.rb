require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/object/*, core/kernel/*

# Object#class (core/object/class_spec.rb)
def test_class_returns_integer_for_fixnum
  assert_equal(Integer, 1.class, "Object#class returns Integer for a Fixnum")
end

def test_class_returns_string
  assert_equal(String, "hello".class, "Object#class returns String for a String")
end

def test_class_returns_array
  assert_equal(Array, [1, 2].class, "Object#class returns Array for an Array")
end

def test_class_returns_hash
  assert_equal(Hash, {}.class, "Object#class returns Hash for a Hash")
end

def test_class_returns_float
  assert_equal(Float, 1.5.class, "Object#class returns Float for a Float")
end

def test_class_returns_symbol
  assert_equal(Symbol, :sym.class, "Object#class returns Symbol for a Symbol")
end

# Object#is_a? / Object#kind_of? (core/object/is_a_spec.rb)
def test_is_a_returns_true_for_exact_class
  assert_true(1.is_a?(Integer), "Object#is_a? returns true if given class is the object's class")
end

def test_is_a_returns_true_for_ancestor
  assert_true(1.is_a?(Numeric), "Object#is_a? returns true if given class is an ancestor")
end

def test_is_a_returns_false_for_unrelated_class
  assert_false(1.is_a?(String), "Object#is_a? returns false if given class is not the object's class or ancestor")
end

def test_kind_of_returns_true_for_exact_class
  assert_true("hello".kind_of?(String), "Object#kind_of? returns true if given class is the object's class")
end

def test_kind_of_returns_false_for_unrelated_class
  assert_false("hello".kind_of?(Integer), "Object#kind_of? returns false if given class is not the object's class or ancestor")
end

# Object#nil? (core/object/nil_spec.rb)
def test_nil_question_returns_false_for_integer
  assert_false(1.nil?, "Object#nil? returns false for an Integer")
end

def test_nil_question_returns_false_for_string
  assert_false("hello".nil?, "Object#nil? returns false for a String")
end

def test_nil_question_returns_true_for_nil
  assert_true(nil.nil?, "Object#nil? returns true for nil")
end

# Object#respond_to? (core/object/respond_to_spec.rb)
def test_respond_to_returns_true_for_existing_method
  assert_true("hello".respond_to?(:length), "Object#respond_to? returns true if obj responds to the given method")
end

def test_respond_to_returns_false_for_nonexistent_method
  assert_false(1.respond_to?(:no_such_method), "Object#respond_to? returns false if obj does not respond to the given method")
end

def test_respond_to_to_s
  assert_true(1.respond_to?(:to_s), "Object#respond_to? returns true for to_s on Integer")
end

# Object#to_s (core/object/to_s_spec.rb)
def test_to_s_integer
  assert_equal("42", 42.to_s, "Object#to_s returns '42' for integer 42")
end

def test_to_s_string
  assert_equal("hello", "hello".to_s, "Object#to_s returns the string itself for a String")
end

def test_to_s_true
  assert_equal("true", true.to_s, "Object#to_s returns 'true' for true")
end

# Object#inspect (core/object/inspect_spec.rb)
def test_inspect_integer
  assert_equal("42", 42.inspect, "Object#inspect returns '42' for integer 42")
end

def test_inspect_string
  assert_equal("\"hello\"", "hello".inspect, "Object#inspect returns '\"hello\"' for string 'hello'")
end

def test_inspect_nil
  assert_equal("nil", nil.inspect, "Object#inspect returns 'nil' for nil")
end

# Object#frozen? (core/object/frozen_spec.rb)
def test_frozen_true_is_frozen
  assert_true(true.frozen?, "Object#frozen? returns true for true")
end

def test_frozen_nil_is_frozen
  assert_true(nil.frozen?, "Object#frozen? returns true for nil")
end

def test_frozen_integer_is_frozen
  assert_true(1.frozen?, "Object#frozen? returns true for an Integer")
end

def test_frozen_symbol_is_frozen
  assert_true(:sym.frozen?, "Object#frozen? returns true for a Symbol")
end

# Object#freeze (core/object/freeze_spec.rb)
def test_freeze_returns_self
  str = "hello"
  result = str.freeze
  assert_equal(str, result, "Object#freeze returns the receiver")
end

def test_freeze_makes_frozen
  str = "hello"
  str.freeze
  assert_true(str.frozen?, "Object#freeze sets the object as frozen")
end

# Object#equal? (core/object/equal_value_spec.rb)
def test_equal_identity_same_object
  a = "test"
  assert_true(a.equal?(a), "Object#equal? returns true for the same object")
end

def test_equal_identity_different_objects
  a = "test"
  b = "test"
  assert_false(a.equal?(b), "Object#equal? returns false for different objects with same value")
end

def test_equal_identity_integers
  assert_true(1.equal?(1), "Object#equal? returns true for identical integers")
end

# Object#== (core/object/equal_value_spec.rb)
def test_double_equals_integers
  assert_true(1 == 1, "Object#== returns true for equal integers")
end

def test_double_equals_strings
  assert_true("abc" == "abc", "Object#== returns true for equal strings")
end

def test_double_equals_different_values
  assert_false(1 == 2, "Object#== returns false for different values")
end

# Kernel#puts (core/kernel/puts_spec.rb)
def test_puts_returns_nil
  result = puts("")
  assert_nil(result, "Kernel#puts returns nil")
end

def run_tests
  spec_reset
  test_class_returns_integer_for_fixnum
  test_class_returns_string
  test_class_returns_array
  test_class_returns_hash
  test_class_returns_float
  test_class_returns_symbol
  test_is_a_returns_true_for_exact_class
  test_is_a_returns_true_for_ancestor
  test_is_a_returns_false_for_unrelated_class
  test_kind_of_returns_true_for_exact_class
  test_kind_of_returns_false_for_unrelated_class
  test_nil_question_returns_false_for_integer
  test_nil_question_returns_false_for_string
  test_nil_question_returns_true_for_nil
  test_respond_to_returns_true_for_existing_method
  test_respond_to_returns_false_for_nonexistent_method
  test_respond_to_to_s
  test_to_s_integer
  test_to_s_string
  test_to_s_true
  test_inspect_integer
  test_inspect_string
  test_inspect_nil
  test_frozen_true_is_frozen
  test_frozen_nil_is_frozen
  test_frozen_integer_is_frozen
  test_frozen_symbol_is_frozen
  test_freeze_returns_self
  test_freeze_makes_frozen
  test_equal_identity_same_object
  test_equal_identity_different_objects
  test_equal_identity_integers
  test_double_equals_integers
  test_double_equals_strings
  test_double_equals_different_values
  test_puts_returns_nil
  spec_summary
end

run_tests
