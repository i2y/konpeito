# Chart helper functions
# NOTE: Color manipulation (with_alpha, lighten_color, darken_color)
# is done in KUIRuntime.java to avoid JVM verifier issues with bitwise ops.
# Call via: painter.with_alpha(color, alpha)
#           painter.lighten_color(color, amount)
#           painter.darken_color(color, amount)

# Compute nice axis tick values
# Simplified to avoid Math.log10 and ** operator (JVM compatibility)
def compute_ticks(min_val, max_val, target_count)
  ticks = []
  range = max_val - min_val
  if range <= 0.0
    ticks << min_val
    return ticks
  end
  rough_step = range / target_count
  nice_step = pick_nice_step(rough_step)
  start = compute_tick_start(min_val, nice_step)
  v = start
  while v <= max_val + nice_step * 0.001
    if v >= min_val - nice_step * 0.001
      ticks << v
    end
    v = v + nice_step
  end
  ticks
end

def pick_nice_step(rough_step)
  if rough_step >= 500.0
    return 500.0
  end
  if rough_step >= 200.0
    return 200.0
  end
  if rough_step >= 100.0
    return 100.0
  end
  if rough_step >= 50.0
    return 50.0
  end
  if rough_step >= 20.0
    return 20.0
  end
  if rough_step >= 10.0
    return 10.0
  end
  if rough_step >= 5.0
    return 5.0
  end
  if rough_step >= 2.0
    return 2.0
  end
  if rough_step >= 1.0
    return 1.0
  end
  if rough_step >= 0.5
    return 0.5
  end
  if rough_step >= 0.2
    return 0.2
  end
  0.1
end

def compute_tick_start(min_val, nice_step)
  ratio = min_val / nice_step
  int_part = ratio.to_i
  int_f = int_part * 1.0
  int_f * nice_step
end

# Format a number for axis labels
# NOTE: Uses painter.number_to_string (Java method) because
# .to_i/.to_s dispatch doesn't work on untyped JVM Objects
def format_axis_value(painter, val)
  painter.number_to_string(val)
end
