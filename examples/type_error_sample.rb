# Sample file to test diagnostic error messages

def add_numbers(a, b)
  a + b
end

def greet(name)
  "Hello, " + name
end

# Type mismatch: passing String where Integer expected
result = add_numbers(1, "two")
