# FFI demo - using @ffi "libm" to link with math library
# All functions use minimal @cfunc form (method name = C function name)

module MathLib
  def self.sin(x)
  end

  def self.cos(x)
  end

  def self.sqrt(x)
  end

  def self.pow(base, exp)
  end

  def self.exp(x)
  end

  def self.log(x)
  end
end

# Demonstrate trigonometric functions
def demo_trig(angle)
  # sin^2 + cos^2 = 1 (should always return ~1.0)
  s = MathLib.sin(angle)
  c = MathLib.cos(angle)
  s * s + c * c
end

# Demonstrate power function
def demo_power(base, exp)
  MathLib.pow(base, exp)
end

# Calculate circle area: pi * r^2
def calculate_circle_area(radius)
  pi = 3.14159265358979
  pi * radius * radius
end

# Calculate hypotenuse using Pythagorean theorem
def calculate_hypotenuse(a, b)
  MathLib.sqrt(a * a + b * b)
end
