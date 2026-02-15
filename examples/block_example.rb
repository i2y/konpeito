# Example with blocks

class Iterator
  def times(n)
    i = 0
    while i < n
      yield i
      i = i + 1
    end
    n
  end

  def each_pair(a, b)
    yield a
    yield b
    nil
  end
end

def with_block
  yield 42
end
