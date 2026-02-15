# Example: receiving and using blocks

class BlockReceiver
  def map_values(a, b, c)
    result_a = yield a
    result_b = yield b
    result_c = yield c
    result_a + result_b + result_c
  end

  def transform(value)
    yield value
  end
end
