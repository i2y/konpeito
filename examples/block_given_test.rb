# Example: using block_given?

class OptionalBlock
  def maybe_yield(value)
    if block_given?
      yield value
    else
      value
    end
  end

  def double_or_default(n)
    if block_given?
      yield n
    else
      n * 2
    end
  end
end
