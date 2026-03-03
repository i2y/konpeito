def distance(x1, y1, x2, y2)
  dx = x2 - x1
  dy = y2 - y1
  dx * dx + dy * dy
end

def sum_distances(n)
  total = 0.0
  i = 0
  while i < n
    total = total + distance(i * 1.0, 0.0, 0.0, i * 2.0)
    i = i + 1
  end
  total
end

puts sum_distances(1000)
