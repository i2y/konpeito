# Example with instance variables

class Counter
  def initialize
    @count = 0
  end

  def increment
    @count = @count + 1
  end

  def decrement
    @count = @count - 1
  end

  def value
    @count
  end
end
