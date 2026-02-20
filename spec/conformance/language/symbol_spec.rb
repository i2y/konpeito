require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/symbol/*

# Symbol creation
def test_symbol_literal
  sym = :hello
  assert_equal(:hello, sym, "symbol literal creates a symbol")
end

# Symbol#to_s (core/symbol/to_s_spec.rb)
def test_symbol_to_s
  assert_equal("hello", :hello.to_s, "Symbol#to_s returns the string form")
  assert_equal("foo_bar", :foo_bar.to_s, "Symbol#to_s handles underscores")
end

# Symbol#id2name (core/symbol/id2name_spec.rb)
def test_symbol_id2name
  assert_equal("test", :test.id2name, "Symbol#id2name returns the symbol name as string")
end

# Symbol#name
def test_symbol_name
  assert_equal("hello", :hello.name, "Symbol#name returns the symbol name as string")
end

# Symbol equality (core/symbol/equal_value_spec.rb)
def test_symbol_equality
  assert_true(:a == :a, "same symbols are equal")
  assert_false(:a == :b, "different symbols are not equal")
end

def test_symbol_inequality
  assert_true(:a != :b, "different symbols are not equal with !=")
  assert_false(:a != :a, "same symbols are not unequal with !=")
end

# Symbol as hash key
def test_symbol_as_hash_key
  h = {name: "alice", age: 30}
  assert_equal("alice", h[:name], "symbol works as hash key")
  assert_equal(30, h[:age], "symbol hash key returns correct value")
end

# Symbol#inspect
def test_symbol_inspect
  result = :hello.inspect
  assert_equal(":hello", result, "Symbol#inspect returns :name format")
end

# Symbol comparison
def test_symbol_to_s_roundtrip
  sym = :test
  str = sym.to_s
  assert_equal("test", str, "Symbol#to_s converts to string")
end

def run_tests
  spec_reset
  test_symbol_literal
  test_symbol_to_s
  test_symbol_id2name
  test_symbol_name
  test_symbol_equality
  test_symbol_inequality
  test_symbol_as_hash_key
  test_symbol_inspect
  test_symbol_to_s_roundtrip
  spec_summary
end

run_tests
