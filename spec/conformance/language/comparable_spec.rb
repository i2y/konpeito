require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/comparable/*
# Tests Comparable mixin with user-defined <=> operator

class Temperature
  include Comparable

  def initialize(degrees)
    @degrees = degrees
  end

  def degrees
    @degrees
  end

  def <=>(other)
    @degrees <=> other.degrees
  end
end

# Basic <=> operator
def test_spaceship_operator
  a = Temperature.new(100)
  b = Temperature.new(200)
  assert_equal(-1, (a <=> b), "<=> returns -1 when less than")
  assert_equal(0, (a <=> a), "<=> returns 0 when equal")
  assert_equal(1, (b <=> a), "<=> returns 1 when greater than")
end

# Comparison operators from Comparable
def test_less_than
  a = Temperature.new(100)
  b = Temperature.new(200)
  assert_true(a < b, "Comparable#< returns true when less than")
  assert_false(b < a, "Comparable#< returns false when greater than")
  assert_false(a < a, "Comparable#< returns false when equal")
end

def test_greater_than
  a = Temperature.new(100)
  b = Temperature.new(200)
  assert_true(b > a, "Comparable#> returns true when greater than")
  assert_false(a > b, "Comparable#> returns false when less than")
  assert_false(a > a, "Comparable#> returns false when equal")
end

def test_less_than_or_equal
  a = Temperature.new(100)
  b = Temperature.new(200)
  c = Temperature.new(100)
  assert_true(a <= b, "Comparable#<= returns true when less than")
  assert_true(a <= c, "Comparable#<= returns true when equal")
  assert_false(b <= a, "Comparable#<= returns false when greater than")
end

def test_greater_than_or_equal
  a = Temperature.new(100)
  b = Temperature.new(200)
  c = Temperature.new(100)
  assert_true(b >= a, "Comparable#>= returns true when greater than")
  assert_true(a >= c, "Comparable#>= returns true when equal")
  assert_false(a >= b, "Comparable#>= returns false when less than")
end

# between?
def test_between
  a = Temperature.new(50)
  lo = Temperature.new(0)
  hi = Temperature.new(100)
  assert_true(a.between?(lo, hi), "Comparable#between? returns true when in range")
  assert_false(a.between?(hi, Temperature.new(200)), "Comparable#between? returns false when below range")
  assert_true(lo.between?(lo, hi), "Comparable#between? returns true for lower boundary")
  assert_true(hi.between?(lo, hi), "Comparable#between? returns true for upper boundary")
end

# clamp
def test_clamp
  a = Temperature.new(150)
  lo = Temperature.new(0)
  hi = Temperature.new(100)
  result = a.clamp(lo, hi)
  assert_equal(100, result.degrees, "Comparable#clamp clamps to upper bound")

  b = Temperature.new(-50)
  result2 = b.clamp(lo, hi)
  assert_equal(0, result2.degrees, "Comparable#clamp clamps to lower bound")

  c = Temperature.new(50)
  result3 = c.clamp(lo, hi)
  assert_equal(50, result3.degrees, "Comparable#clamp returns self when in range")
end

# sort using <=>
def test_sort_with_spaceship
  temps = [Temperature.new(300), Temperature.new(100), Temperature.new(200)]
  sorted = temps.sort
  assert_equal(100, sorted[0].degrees, "sort uses <=> - first is smallest")
  assert_equal(200, sorted[1].degrees, "sort uses <=> - second is middle")
  assert_equal(300, sorted[2].degrees, "sort uses <=> - third is largest")
end

def run_tests
  spec_reset
  test_spaceship_operator
  test_less_than
  test_greater_than
  test_less_than_or_equal
  test_greater_than_or_equal
  test_between
  test_clamp
  test_sort_with_spaceship
  spec_summary
end

run_tests
