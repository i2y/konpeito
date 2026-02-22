require_relative "../lib/konpeito_spec"

# Tests require_relative behavior and constant/method resolution across files
# Note: This spec tests within a single file since conformance tests
# are self-contained. Tests basic require_relative and stdlib require.

# require_relative for helpers (already used by every spec)
def test_require_relative_loads_helpers
  # If we got here, require_relative worked to load konpeito_spec
  assert_true(defined?(assert_equal) != nil, "require_relative loads methods from helper file")
end

def test_require_relative_loads_globals
  # konpeito_spec defines $__spec_pass / $__spec_fail
  assert_true(defined?($__spec_pass) != nil, "require_relative makes globals available")
end

# Constants defined in current file
REQUIRE_TEST_CONST = 42

def test_constant_resolution
  assert_equal(42, REQUIRE_TEST_CONST, "constants defined at top level are accessible")
end

# Math constants from stdlib
def test_math_constants
  assert_true(Math::PI > 3.14, "Math::PI is accessible and greater than 3.14")
  assert_true(Math::PI < 3.15, "Math::PI is less than 3.15")
end

# Math methods
def test_math_sqrt
  assert_equal(2.0, Math.sqrt(4), "Math.sqrt(4) returns 2.0")
end

# String encoding constants
def test_encoding_constants
  s = "hello"
  enc = s.encoding
  assert_equal("UTF-8", enc.to_s, "default string encoding is UTF-8")
end

def run_tests
  spec_reset
  test_require_relative_loads_helpers
  test_require_relative_loads_globals
  test_constant_resolution
  test_math_constants
  test_math_sqrt
  test_encoding_constants
  spec_summary
end

run_tests
