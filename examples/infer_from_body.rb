# Example: inferring types from method body without calls

# Case 1: Can infer from literal operations
def double(x)
  x * 2  # 2 is Integer, so x must support * with Integer
end

# Case 2: Can infer from return type hints
def make_greeting(name)
  "Hello, " + name  # String + name → name is String
end

# Case 3: Cannot infer without more context
def identity(x)
  x  # What is x? Could be anything
end

# Case 4: Can infer from multiple operations
def calculate(a, b)
  sum = a + b
  sum * 2  # 2 is Integer, sum must be numeric
  # But we still don't know if a, b are Integer or Float
end
