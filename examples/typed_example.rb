# Example demonstrating type inference

def add(a, b)
  a + b
end

def double(x)
  x * 2
end

def greet(name)
  "Hello, " + name
end

# These calls help the inferrer determine types
result1 = add(10, 20)
result2 = double(5)
result3 = greet("World")
