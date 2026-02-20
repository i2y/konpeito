require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/fiber/*

# Fiber.new and resume (core/fiber/new_spec.rb, core/fiber/resume_spec.rb)
def test_fiber_new_and_resume
  f = Fiber.new { 42 }
  result = f.resume
  assert_equal(42, result, "Fiber.new creates a fiber that returns a value on resume")
end

# Fiber.yield (core/fiber/yield_spec.rb)
def test_fiber_yield_returns_value
  f = Fiber.new { Fiber.yield(10) }
  result = f.resume
  assert_equal(10, result, "Fiber.yield returns the yielded value to resume")
end

def test_fiber_yield_multiple
  f = Fiber.new do
    Fiber.yield(1)
    Fiber.yield(2)
    3
  end
  r1 = f.resume
  r2 = f.resume
  r3 = f.resume
  assert_equal(1, r1, "first yield returns 1")
  assert_equal(2, r2, "second yield returns 2")
  assert_equal(3, r3, "final value returns 3")
end

# Fiber#alive? (core/fiber/alive_spec.rb)
def test_fiber_alive_before_completion
  f = Fiber.new { Fiber.yield(1); 2 }
  f.resume
  assert_true(f.alive?, "Fiber#alive? returns true before fiber completes")
end

def test_fiber_alive_after_completion
  f = Fiber.new { 1 }
  f.resume
  assert_false(f.alive?, "Fiber#alive? returns false after fiber completes")
end

# Fiber with arguments
def test_fiber_resume_passes_value_to_yield
  f = Fiber.new do
    x = Fiber.yield
    x * 2
  end
  f.resume
  result = f.resume(21)
  assert_equal(42, result, "Fiber resume passes value back to yield")
end

# Fiber as generator
def test_fiber_generator_pattern
  counter = Fiber.new do
    i = 0
    while true
      Fiber.yield(i)
      i = i + 1
    end
  end
  assert_equal(0, counter.resume, "generator yields 0")
  assert_equal(1, counter.resume, "generator yields 1")
  assert_equal(2, counter.resume, "generator yields 2")
  assert_equal(3, counter.resume, "generator yields 3")
end

def run_tests
  spec_reset
  test_fiber_new_and_resume
  test_fiber_yield_returns_value
  test_fiber_yield_multiple
  test_fiber_alive_before_completion
  test_fiber_alive_after_completion
  test_fiber_resume_passes_value_to_yield
  test_fiber_generator_pattern
  spec_summary
end

run_tests
