require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/splat_spec.rb

def sp_sum(*args)
  total = 0
  args.each { |x| total = total + x }
  total
end

def sp_first_and_rest(first, *rest)
  [first, rest]
end

def sp_count(*args)
  args.length
end

def sp_join(*args)
  result = ""
  args.each { |s| result = result + s }
  result
end

def sp_add(a, b, c)
  a + b + c
end

def sp_greet(greeting, *names)
  result = []
  names.each { |n| result = result + [greeting + " " + n] }
  result
end

def test_splat_receives_all_args
  assert_equal(6, sp_sum(1, 2, 3), "*args receives all arguments")
end

def test_splat_empty_args
  assert_equal(0, sp_sum, "*args with no arguments gives empty array")
end

def test_splat_single_arg
  assert_equal(42, sp_sum(42), "*args with single argument works")
end

def test_splat_first_and_rest
  result = sp_first_and_rest(1, 2, 3, 4)
  assert_equal(1, result[0], "first param captures first arg")
  rest = result[1]
  assert_equal(3, rest.length, "*rest captures remaining args")
  assert_equal(2, rest[0], "*rest first element")
  assert_equal(3, rest[1], "*rest second element")
  assert_equal(4, rest[2], "*rest third element")
end

def test_splat_first_and_rest_single
  result = sp_first_and_rest(1)
  assert_equal(1, result[0], "first param captures only arg")
  rest = result[1]
  assert_equal(0, rest.length, "*rest is empty when only first arg given")
end

def test_splat_count
  assert_equal(0, sp_count, "*args count with no args")
  assert_equal(3, sp_count(1, 2, 3), "*args count with 3 args")
  assert_equal(5, sp_count("a", "b", "c", "d", "e"), "*args count with 5 args")
end

def test_splat_expand_at_call_site
  arr = [1, 2, 3]
  result = sp_add(*arr)
  assert_equal(6, result, "*array expands at call site")
end

def test_splat_string_args
  assert_equal("abc", sp_join("a", "b", "c"), "*args with strings works")
end

def test_splat_greeting_with_names
  result = sp_greet("Hi", "Alice", "Bob")
  assert_equal(2, result.length, "greeting creates array of greetings")
  assert_equal("Hi Alice", result[0], "first greeting")
  assert_equal("Hi Bob", result[1], "second greeting")
end

def run_tests
  spec_reset
  test_splat_receives_all_args
  test_splat_empty_args
  test_splat_single_arg
  test_splat_first_and_rest
  test_splat_first_and_rest_single
  test_splat_count
  test_splat_expand_at_call_site
  test_splat_string_args
  test_splat_greeting_with_names
  spec_summary
end

run_tests
