# Regular Ruby script — NOT compiled by Konpeito.
# Loads the compiled physics extension and uses it.
require_relative "physics"

xs = Array.new(100) { rand }
ys = Array.new(100) { rand }
puts Physics.sum_distances(xs, ys, 100)
