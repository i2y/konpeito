# Easing functions for animation
# All functions take t in [0.0, 1.0] and return a value in [0.0, 1.0]

EASING_PI = 3.14159265358979323846

module Easing
  def self.linear(t)
    t
  end

  def self.ease_in(t)
    t * t
  end

  def self.ease_out(t)
    1.0 - (1.0 - t) * (1.0 - t)
  end

  def self.ease_in_out(t)
    if t < 0.5
      2.0 * t * t
    else
      1.0 - (-2.0 * t + 2.0) * (-2.0 * t + 2.0) / 2.0
    end
  end

  def self.ease_in_cubic(t)
    t * t * t
  end

  def self.ease_out_cubic(t)
    v = 1.0 - t
    1.0 - v * v * v
  end

  def self.ease_in_out_cubic(t)
    if t < 0.5
      4.0 * t * t * t
    else
      v = -2.0 * t + 2.0
      1.0 - v * v * v / 2.0
    end
  end

  def self.bounce(t)
    if t < 1.0 / 2.75
      7.5625 * t * t
    elsif t < 2.0 / 2.75
      t2 = t - 1.5 / 2.75
      7.5625 * t2 * t2 + 0.75
    elsif t < 2.5 / 2.75
      t2 = t - 2.25 / 2.75
      7.5625 * t2 * t2 + 0.9375
    else
      t2 = t - 2.625 / 2.75
      7.5625 * t2 * t2 + 0.984375
    end
  end
end
