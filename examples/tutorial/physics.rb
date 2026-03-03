module Physics
  def self.distance(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  def self.sum_distances(xs, ys, n)
    total = 0.0
    i = 0
    while i < n - 1
      total = total + distance(xs[i], ys[i], xs[i + 1], ys[i + 1])
      i = i + 1
    end
    total
  end
end
