# @cfunc demo - direct C function calls to libm

class LibM
  def self.sin(x)
    # Implementation is in C (libm)
  end

  def self.cos(x)
    # Implementation is in C (libm)
  end

  def self.sqrt(x)
    # Implementation is in C (libm)
  end
end

def test_cfunc
  pi = 3.14159265358979

  # Direct call to C sin function
  sin_val = LibM.sin(pi / 2.0)

  # Direct call to C cos function
  cos_val = LibM.cos(0.0)

  # Direct call to C sqrt function
  sqrt_val = LibM.sqrt(16.0)

  # Return sum to verify
  sin_val + cos_val + sqrt_val
end
