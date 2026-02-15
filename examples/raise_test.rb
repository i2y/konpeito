# Example: raise

def check_positive(n)
  if n < 0
    raise "negative number"
  end
  n
end

def safe_divide(a, b)
  if b == 0
    raise "division by zero"
  end
  a / b
end
