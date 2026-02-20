require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/rescue_spec.rb and language/ensure_spec.rb

# Basic rescue (language/rescue_spec.rb)
def test_rescue_handles_exception
  result = begin
    raise "boom"
    "not reached"
  rescue
    "caught"
  end
  assert_equal("caught", result, "can be used to handle a specific exception")
end

def test_rescue_returns_value_from_rescue
  result = begin
    raise "error"
    1
  rescue
    2
  end
  assert_equal(2, result, "returns value from rescue if an exception was raised")
end

def test_rescue_standard_error
  result = begin
    raise StandardError, "err"
    "not reached"
  rescue StandardError
    "caught"
  end
  assert_equal("caught", result, "rescues StandardError")
end

def test_rescue_with_variable
  result = begin
    raise "boom"
  rescue => e
    e.message
  end
  assert_equal("boom", result, "captures exception in a local variable")
end

def test_no_exception_skips_rescue
  result = begin
    "no error"
  rescue
    "caught"
  end
  assert_equal("no error", result, "rescue body not executed when no exception")
end

# Ensure (language/ensure_spec.rb)
def test_ensure_runs_when_exception_raised
  executed = false
  begin
    begin
      raise "boom"
    rescue
      # caught
    ensure
      executed = true
    end
  end
  assert_true(executed, "ensure is executed when an exception is raised and rescued")
end

def test_ensure_runs_when_no_exception
  executed = false
  begin
    "ok"
  rescue
    "caught"
  ensure
    executed = true
  end
  assert_true(executed, "ensure is executed when nothing is raised")
end

def test_ensure_with_rescue
  rescued = false
  ensured = false
  begin
    raise "boom"
  rescue
    rescued = true
  ensure
    ensured = true
  end
  assert_true(rescued, "rescue block executes")
  assert_true(ensured, "ensure block also executes")
end

# Rescue else (language/rescue_spec.rb)
def test_rescue_else_runs_when_no_exception
  result = begin
    "ok"
  rescue
    "caught"
  else
    "else ran"
  end
  assert_equal("else ran", result, "returns value from else section if no exceptions were raised")
end

def test_rescue_else_not_run_when_exception
  result = begin
    raise "boom"
  rescue
    "caught"
  else
    "else ran"
  end
  assert_equal("caught", result, "will not execute an else block if an exception was raised")
end

# Raise RuntimeError (core/kernel/raise_spec.rb)
def test_raise_runtime_error
  result = begin
    raise "test message"
  rescue RuntimeError => e
    e.message
  end
  assert_equal("test message", result, "raise with string raises RuntimeError with that message")
end

# Nested begin/rescue
def test_nested_rescue
  result = begin
    begin
      raise "inner"
    rescue
      "inner caught"
    end
  rescue
    "outer caught"
  end
  assert_equal("inner caught", result, "inner rescue catches inner exception")
end

def run_tests
  spec_reset
  test_rescue_handles_exception
  test_rescue_returns_value_from_rescue
  test_rescue_standard_error
  test_rescue_with_variable
  test_no_exception_skips_rescue
  test_ensure_runs_when_exception_raised
  test_ensure_runs_when_no_exception
  test_ensure_with_rescue
  test_rescue_else_runs_when_no_exception
  test_rescue_else_not_run_when_exception
  test_raise_runtime_error
  test_nested_rescue
  spec_summary
end

run_tests
