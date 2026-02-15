# PieChart - pie/donut chart widget
# Supports slice labels, percentages, hover, donut mode

PIE_PI = 3.14159265358979323846

class PieChart < BaseChart
  def initialize(labels, values)
    super()
    @labels = labels
    @values = values
    @donut = false
    @donut_ratio = 0.5
    @show_pct = true
    @show_labels = true
    @start_angle = -90.0
    # Computed per-frame
    @cx = 0.0
    @cy = 0.0
    @radius = 20.0
    @total = 0.0
  end

  def donut(v)
    @donut = v
    self
  end

  def donut_ratio(r)
    @donut_ratio = r
    self
  end

  def show_percentages(v)
    @show_pct = v
    self
  end

  def show_labels(v)
    @show_labels = v
    self
  end

  def start_angle(a)
    @start_angle = a
    self
  end

  def set_data(labels, values)
    @labels = labels
    @values = values
    mark_dirty
    update
  end

  def render_chart(painter, px, py, pw, ph)
    return if @labels.length == 0
    setup_pie(px, py, pw, ph)
    return if @total <= 0.0
    draw_slices(painter)
    draw_donut_hole(painter)
    draw_pie_legend(painter, px)
  end

  def setup_pie(px, py, pw, ph)
    @total = compute_total
    chart_size = pw
    if ph < pw
      chart_size = ph
    end
    @radius = chart_size / 2.0 - 10.0
    if @radius < 20.0
      @radius = 20.0
    end
    @cx = px + pw / 2.0
    @cy = py + ph / 2.0
  end

  def compute_total
    total = 0.0
    i = 0
    while i < @values.length
      total = total + @values[i]
      i = i + 1
    end
    total
  end

  def draw_slices(painter)
    angle = @start_angle
    i = 0
    while i < @values.length
      angle = draw_one_slice(painter, i, angle)
      i = i + 1
    end
  end

  def draw_one_slice(painter, i, angle)
    fraction = @values[i] / @total
    sweep = fraction * 360.0
    c = series_color(i)
    if @hover_index == i
      c = painter.lighten_color(c, 0.3)
    end
    painter.fill_arc(@cx, @cy, @radius, angle, sweep, c)
    if @show_pct
      if fraction >= 0.03
        draw_slice_label(painter, angle, sweep, fraction)
      end
    end
    angle + sweep
  end

  def draw_slice_label(painter, angle, sweep, fraction)
    mid_angle = angle + sweep / 2.0
    rad = mid_angle * PIE_PI / 180.0
    label_r = compute_label_radius
    lx = @cx + label_r * painter.math_cos(rad)
    ly = @cy + label_r * painter.math_sin(rad)
    pct_val = fraction * 100.0
    pct = painter.number_to_string(pct_val) + "%"
    pw2 = painter.measure_text_width(pct, $theme.font_family, 11.0)
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    painter.draw_text(pct, lx - pw2 / 2.0, ly + ascent / 2.0, $theme.font_family, 11.0, 4294967295)
  end

  def compute_label_radius
    if @donut
      @radius * (1.0 + @donut_ratio) / 2.0
    else
      @radius * 0.65
    end
  end

  def draw_donut_hole(painter)
    if @donut
      inner_r = @radius * @donut_ratio
      painter.fill_circle(@cx, @cy, inner_r, $theme.bg_primary)
    end
  end

  def draw_pie_legend(painter, px)
    if @show_legend
      legend_y = @cy + @radius + 16.0
      colors = []
      i = 0
      while i < @labels.length
        colors << series_color(i)
        i = i + 1
      end
      draw_legend(painter, @labels, colors, px + 8.0, legend_y)
    end
  end

  def update_hover
    return if @painter == nil
    mx = @mouse_x
    my = @mouse_y
    dx = mx - @cx
    dy = my - @cy
    dist = @painter.math_sqrt(dx * dx + dy * dy)
    if dist > @radius
      @hover_index = -1
      return
    end
    if @donut
      inner = @radius * @donut_ratio
      if dist < inner
        @hover_index = -1
        return
      end
    end
    find_hover_slice(dx, dy)
  end

  def find_hover_slice(dx, dy)
    angle_rad = @painter.math_atan2(dy, dx)
    angle_deg = angle_rad * 180.0 / PIE_PI
    relative = angle_deg - @start_angle
    relative = normalize_angle(relative)
    total = compute_total
    if total <= 0.0
      @hover_index = -1
      return
    end
    find_slice_at_angle(relative, total)
  end

  def normalize_angle(a)
    while a < 0.0
      a = a + 360.0
    end
    while a >= 360.0
      a = a - 360.0
    end
    a
  end

  def find_slice_at_angle(relative, total)
    cumulative = 0.0
    i = 0
    while i < @values.length
      fraction = @values[i] / total
      sweep = fraction * 360.0
      if relative >= cumulative
        if relative < cumulative + sweep
          @hover_index = i
          return
        end
      end
      cumulative = cumulative + sweep
      i = i + 1
    end
    @hover_index = -1
  end
end

def PieChart(labels, values)
  PieChart.new(labels, values)
end
