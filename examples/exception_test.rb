# Example: begin/ensure blocks

class Resource
  def initialize
    @opened = false
    @closed = false
  end

  def open
    @opened = true
  end

  def close
    @closed = true
  end

  def opened?
    @opened
  end

  def closed?
    @closed
  end

  def use_resource
    result = 0
    begin
      open
      result = 42
    ensure
      close
    end
    result
  end
end
