require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/rescue_spec.rb - custom exception classes

# Custom exception class hierarchy
class AppError < StandardError
end

class ValidationError < AppError
end

class NotFoundError < AppError
end

# Basic custom exception
def test_raise_custom_exception
  result = begin
    raise AppError, "app error"
  rescue AppError => e
    e.message
  end
  assert_equal("app error", result, "custom exception can be raised and rescued")
end

# Rescue catches subclasses
def test_rescue_catches_subclass
  result = begin
    raise ValidationError, "invalid"
  rescue AppError => e
    e.message
  end
  assert_equal("invalid", result, "rescue AppError catches ValidationError subclass")
end

# Specific rescue takes priority
def test_specific_rescue_priority
  result = begin
    raise ValidationError, "validation failed"
  rescue ValidationError
    "validation"
  rescue AppError
    "app"
  end
  assert_equal("validation", result, "more specific rescue takes priority over parent")
end

# Parent rescue catches when no specific match
def test_parent_rescue_fallback
  result = begin
    raise NotFoundError, "not found"
  rescue ValidationError
    "validation"
  rescue AppError
    "app"
  end
  assert_equal("app", result, "parent rescue catches when specific match not found")
end

# StandardError catches custom exceptions
def test_standard_error_catches_custom
  result = begin
    raise AppError, "custom"
  rescue StandardError => e
    e.message
  end
  assert_equal("custom", result, "StandardError catches custom exception subclasses")
end

# Unmatched exception passes through
def test_unmatched_rescue_passes_through
  result = begin
    begin
      raise NotFoundError, "not found"
    rescue ValidationError
      "validation"
    end
  rescue AppError => e
    e.message
  end
  assert_equal("not found", result, "unmatched rescue passes to outer handler")
end

# Exception class identity
def test_exception_class
  result = begin
    raise ValidationError, "test"
  rescue => e
    e.class.to_s
  end
  assert_equal("ValidationError", result, "exception class is preserved")
end

# Custom exception with ensure
def test_custom_exception_with_ensure
  ensured = false
  begin
    raise AppError, "error"
  rescue AppError
    # caught
  ensure
    ensured = true
  end
  assert_true(ensured, "ensure runs with custom exception")
end

def run_tests
  spec_reset
  test_raise_custom_exception
  test_rescue_catches_subclass
  test_specific_rescue_priority
  test_parent_rescue_fallback
  test_standard_error_catches_custom
  test_unmatched_rescue_passes_through
  test_exception_class
  test_custom_exception_with_ensure
  spec_summary
end

run_tests
