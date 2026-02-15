# GaugeChart - arc gauge with thresholds and center value display
# Uses fill_arc/stroke_arc APIs for drawing

GAUGE_PI = 3.14159265358979323846

class GaugeChart < BaseChart
  def initialize(value, min_val, max_val)
    super()
    @value = value
    @min_val = min_val
    @max_val = max_val
    @thresholds = nil     # Array of [threshold_value, color] pairs
    @arc_width = 20.0
    @show_value = true
    @value_format = nil
    @unit_text = ""
    @bg_arc_color = 0xFF3B4261
  end

  def thresholds(t)
    @thresholds = t
    self
  end

  def arc_width(w)
    @arc_width = w
    self
  end

  def show_value(v)
    @show_value = v
    self
  end

  def unit(u)
    @unit_text = u
    self
  end

  def set_value(v)
    @value = v
    mark_dirty
    update
  end

  def render_chart(painter, px, py, pw, ph)
    chart_size = pw
    if ph < pw
      chart_size = ph
    end
    radius = chart_size / 2.0 - @arc_width / 2.0 - 10.0
    if radius < 30.0
      radius = 30.0
    end
    cx = px + pw / 2.0
    cy = py + ph / 2.0 + 10.0

    # Background arc (270 degrees, from 135 to 405)
    start_angle = 135.0
    sweep_total = 270.0
    painter.stroke_arc(cx, cy, radius, start_angle, sweep_total, @bg_arc_color, @arc_width)

    # Value arc
    range = @max_val - @min_val
    if range <= 0.0
      range = 1.0
    end
    fraction = (@value - @min_val) / range
    if fraction < 0.0
      fraction = 0.0
    end
    if fraction > 1.0
      fraction = 1.0
    end
    value_sweep = fraction * sweep_total
    arc_color = get_gauge_color(painter, fraction)
    painter.stroke_arc(cx, cy, radius, start_angle, value_sweep, arc_color, @arc_width)

    # Draw threshold tick marks
    draw_gauge_ticks(painter, cx, cy, radius)

    # Center value display
    if @show_value
      draw_gauge_value(painter, cx, cy)
    end

    # Min/Max labels
    draw_gauge_min_max(painter, cx, cy, radius)
  end

  def get_gauge_color(painter, fraction)
    if @thresholds == nil
      return series_color(0)
    end
    # thresholds: [[0.5, green], [0.75, yellow], [1.0, red]]
    i = 0
    while i < @thresholds.length
      threshold_frac = @thresholds[i][0]
      if fraction <= threshold_frac
        return @thresholds[i][1]
      end
      i = i + 1
    end
    # Past all thresholds, use last color
    if @thresholds.length > 0
      return @thresholds[@thresholds.length - 1][1]
    end
    series_color(0)
  end

  def draw_gauge_ticks(painter, cx, cy, radius)
    return if @thresholds == nil
    start_angle = 135.0
    sweep_total = 270.0
    tick_r_inner = radius - @arc_width / 2.0 - 2.0
    tick_r_outer = radius + @arc_width / 2.0 + 2.0
    tc = $theme.text_secondary
    i = 0
    while i < @thresholds.length
      frac = @thresholds[i][0]
      if frac < 1.0
        angle_deg = start_angle + frac * sweep_total
        angle_rad = angle_deg * GAUGE_PI / 180.0
        cos_a = painter.math_cos(angle_rad)
        sin_a = painter.math_sin(angle_rad)
        x1 = cx + tick_r_inner * cos_a
        y1 = cy + tick_r_inner * sin_a
        x2 = cx + tick_r_outer * cos_a
        y2 = cy + tick_r_outer * sin_a
        painter.draw_line(x1, y1, x2, y2, tc, 1.0)
      end
      i = i + 1
    end
  end

  def draw_gauge_value(painter, cx, cy)
    vl = painter.number_to_string(@value)
    if @unit_text != ""
      vl = vl + @unit_text
    end
    vw = painter.measure_text_width(vl, $theme.font_family, 28.0)
    ascent = painter.get_text_ascent($theme.font_family, 28.0)
    vx = cx - vw / 2.0
    vy = cy + ascent / 2.0
    tc = $theme.text_primary
    painter.draw_text(vl, vx, vy, $theme.font_family, 28.0, tc)
  end

  def draw_gauge_min_max(painter, cx, cy, radius)
    lc = $theme.text_secondary
    r_label = radius + @arc_width / 2.0 + 16.0
    # Min label at 135 degrees
    min_angle = 135.0 * GAUGE_PI / 180.0
    min_label = painter.number_to_string(@min_val)
    mlw = painter.measure_text_width(min_label, $theme.font_family, 11.0)
    mx = cx + r_label * painter.math_cos(min_angle) - mlw
    my = cy + r_label * painter.math_sin(min_angle)
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    painter.draw_text(min_label, mx, my + ascent, $theme.font_family, 11.0, lc)
    # Max label at 405 degrees = 45 degrees
    max_angle = 45.0 * GAUGE_PI / 180.0
    max_label = painter.number_to_string(@max_val)
    max_x = cx + r_label * painter.math_cos(max_angle)
    max_y = cy + r_label * painter.math_sin(max_angle)
    painter.draw_text(max_label, max_x, max_y + ascent, $theme.font_family, 11.0, lc)
  end
end

def GaugeChart(value, min_val, max_val)
  GaugeChart.new(value, min_val, max_val)
end
