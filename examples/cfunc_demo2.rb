# @cfunc demo with detailed output

class LibM
  def self.sin(x)
  end

  def self.cos(x)
  end

  def self.sqrt(x)
  end
end

def demo_sin(angle)
  LibM.sin(angle)
end

def demo_cos(angle)
  LibM.cos(angle)
end

def demo_sqrt(value)
  LibM.sqrt(value)
end

# Calculate distance using Pythagorean theorem
# distance = sqrt(x^2 + y^2)
def calculate_distance(x, y)
  LibM.sqrt(x * x + y * y)
end
