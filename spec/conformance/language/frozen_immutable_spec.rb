require_relative "../lib/konpeito_spec"

# freeze and frozen? semantics

def test_string_not_frozen_by_default
  s = "hello"
  assert_true(!s.frozen?, "unfrozen string is not frozen")
end

def test_string_frozen_after_freeze
  s = "hello"
  s.freeze
  assert_true(s.frozen?, "string is frozen after freeze")
end

def test_frozen_string_immutable
  s = "hello"
  s.freeze
  # Frozen string stays same content
  assert_equal("hello", s, "frozen string retains its value")
end

def test_array_not_frozen_by_default
  a = [1, 2, 3]
  assert_true(!a.frozen?, "unfrozen array is not frozen")
end

def test_array_frozen_after_freeze
  a = [1, 2, 3]
  a.freeze
  assert_true(a.frozen?, "array is frozen after freeze")
end

def test_frozen_array_immutable
  a = [1, 2]
  a.freeze
  assert_equal(2, a.length, "frozen array retains its length")
  assert_equal(1, a[0], "frozen array retains first element")
end

def test_hash_not_frozen_by_default
  h = {a: 1}
  assert_true(!h.frozen?, "unfrozen hash is not frozen")
end

def test_hash_frozen_after_freeze
  h = {a: 1}
  h.freeze
  assert_true(h.frozen?, "hash is frozen after freeze")
end

def test_integer_always_frozen
  assert_true(42.frozen?, "integers are always frozen")
  assert_true(0.frozen?, "zero is always frozen")
end

def test_symbol_always_frozen
  assert_true(:hello.frozen?, "symbols are always frozen")
end

def test_nil_always_frozen
  assert_true(nil.frozen?, "nil is always frozen")
end

def test_true_always_frozen
  assert_true(true.frozen?, "true is always frozen")
end

def test_false_always_frozen
  assert_true(false.frozen?, "false is always frozen")
end

def run_tests
  spec_reset
  test_string_not_frozen_by_default
  test_string_frozen_after_freeze
  test_frozen_string_immutable
  test_array_not_frozen_by_default
  test_array_frozen_after_freeze
  test_frozen_array_immutable
  test_hash_not_frozen_by_default
  test_hash_frozen_after_freeze
  test_integer_always_frozen
  test_symbol_always_frozen
  test_nil_always_frozen
  test_true_always_frozen
  test_false_always_frozen
  spec_summary
end

run_tests
