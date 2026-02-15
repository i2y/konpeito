# AreaChart - line chart with filled areas below
# Supports multiple series (stacked or overlapping), grid, hover detection

class AreaChart < BaseChart
  def initialize(x_labels, series_data, series_names)
    super()
    @x_labels = x_labels
    @series_data = series_data
    @series_names = series_names
    @line_width = 2.0
    @fill_alpha = 80
    @show_grid = true
    @stacked = false
    @data_min = 0.0
    @data_max = 0.0
    @y_scale = nil
    @y_ticks = nil
    @x_step = 0.0
    @num_points = 0
    @num_series = 0
    @y_range_min = 0.0
    @y_range_max = 1.0
    @chart_px = 0.0
    @chart_py = 0.0
    @chart_pw = 0.0
    @chart_ph = 0.0
    compute_area_range
  end

  def line_width(w)
    @line_width = w
    self
  end

  def fill_alpha(a)
    @fill_alpha = a
    self
  end

  def show_grid(v)
    @show_grid = v
    self
  end

  def stacked(v)
    @stacked = v
    self
  end

  def set_data(x_labels, series_data, series_names)
    @x_labels = x_labels
    @series_data = series_data
    @series_names = series_names
    compute_area_range
    mark_dirty
    update
  end

  def render_chart(painter, px, py, pw, ph)
    return if @x_labels.length == 0
    return if @series_data.length == 0
    @chart_px = px
    @chart_py = py
    @chart_pw = pw
    @chart_ph = ph
    @num_points = @x_labels.length
    @num_series = @series_data.length
    setup_area_ticks
    setup_area_y_scale
    setup_area_x_step
    draw_y_axis(painter, px, py, pw, ph, @y_ticks, @y_scale)
    draw_x_axis_line(painter, px, py, pw, ph)
    draw_area_x_labels(painter)
    draw_area_hover_line(painter)
    draw_all_areas(painter)
    draw_area_legend(painter, px, py)
  end

  def setup_area_ticks
    @y_ticks = compute_ticks(@data_min, @data_max, 5)
    @y_range_min = @data_min
    @y_range_max = @data_max
    if @y_ticks.length > 0
      @y_range_min = @y_ticks[0]
      @y_range_max = @y_ticks[@y_ticks.length - 1]
    end
  end

  def setup_area_y_scale
    bottom = @chart_py + @chart_ph
    @y_scale = LinearScale.new(@y_range_min, @y_range_max, bottom, @chart_py)
  end

  def setup_area_x_step
    @x_step = 0.0
    if @num_points > 1
      divisor = (@num_points - 1) * 1.0
      @x_step = @chart_pw / divisor
    end
  end

  def draw_area_x_labels(painter)
    lc = $theme.text_secondary
    i = 0
    while i < @num_points
      i_f = i * 1.0
      xx = @chart_px + i_f * @x_step
      label = @x_labels[i]
      lw = painter.measure_text_width(label, $theme.font_family, 11.0)
      ascent = painter.get_text_ascent($theme.font_family, 11.0)
      label_y = @chart_py + @chart_ph + 14.0 + ascent
      painter.draw_text(label, xx - lw / 2.0, label_y, $theme.font_family, 11.0, lc)
      i = i + 1
    end
  end

  def draw_area_hover_line(painter)
    if @hover_index >= 0
      if @hover_index < @num_points
        hi_f = @hover_index * 1.0
        hx = @chart_px + hi_f * @x_step
        hc = painter.with_alpha($theme.accent, 80)
        bottom = @chart_py + @chart_ph
        painter.draw_line(hx, @chart_py, hx, bottom, hc, 1.0)
      end
    end
  end

  def draw_all_areas(painter)
    baseline_y = @y_scale.map(0.0)
    bottom = @chart_py + @chart_ph
    if baseline_y > bottom
      baseline_y = bottom
    end
    # Draw areas back to front (last series first)
    si = @num_series - 1
    while si >= 0
      c = series_color(si)
      fill_c = painter.with_alpha(c, @fill_alpha)
      data = @series_data[si]
      draw_area_fill(painter, data, fill_c, baseline_y)
      draw_area_line(painter, data, c)
      si = si - 1
    end
    # Draw hover points on top
    if @hover_index >= 0
      if @hover_index < @num_points
        draw_area_hover_points(painter)
      end
    end
  end

  def draw_area_fill(painter, data, fill_c, baseline_y)
    return if @num_points < 2
    # Build path: top line left-to-right, then bottom line right-to-left
    painter.begin_path
    # First point
    x0 = @chart_px
    y0 = @y_scale.map(data[0])
    painter.path_move_to(x0, y0)
    # Line across top
    i = 1
    while i < @num_points
      i_f = i * 1.0
      xx = @chart_px + i_f * @x_step
      yy = @y_scale.map(data[i])
      painter.path_line_to(xx, yy)
      i = i + 1
    end
    # Line down to baseline at last point
    last_f = (@num_points - 1) * 1.0
    last_x = @chart_px + last_f * @x_step
    painter.path_line_to(last_x, baseline_y)
    # Line back to first x at baseline
    painter.path_line_to(@chart_px, baseline_y)
    painter.close_fill_path(fill_c)
  end

  def draw_area_line(painter, data, c)
    j = 0
    while j < @num_points - 1
      j_f = j * 1.0
      x1 = @chart_px + j_f * @x_step
      y1 = @y_scale.map(data[j])
      j1_f = (j + 1) * 1.0
      x2 = @chart_px + j1_f * @x_step
      y2 = @y_scale.map(data[j + 1])
      painter.draw_line(x1, y1, x2, y2, c, @line_width)
      j = j + 1
    end
  end

  def draw_area_hover_points(painter)
    si = 0
    while si < @num_series
      c = series_color(si)
      data = @series_data[si]
      if @hover_index < data.length
        hi_f = @hover_index * 1.0
        xx = @chart_px + hi_f * @x_step
        yy = @y_scale.map(data[@hover_index])
        painter.fill_circle(xx, yy, 5.0, c)
        vl = painter.number_to_string(data[@hover_index])
        vw = painter.measure_text_width(vl, $theme.font_family, 10.0)
        tc = $theme.text_primary
        painter.draw_text(vl, xx - vw / 2.0, yy - 8.0, $theme.font_family, 10.0, tc)
      end
      si = si + 1
    end
  end

  def draw_area_legend(painter, px, py)
    if @show_legend
      if @series_names.length > 1
        colors = []
        si = 0
        while si < @series_names.length
          colors << series_color(si)
          si = si + 1
        end
        draw_legend(painter, @series_names, colors, px + 8.0, py - 20.0)
      end
    end
  end

  def update_hover
    return if @y_scale == nil
    if @num_points <= 1
      @hover_index = -1
      return
    end
    mx = @mouse_x
    px = plot_x
    pw = plot_w
    left_bound = px - @x_step / 2.0
    right_bound = px + pw + @x_step / 2.0
    if mx < left_bound
      @hover_index = -1
      return
    end
    if mx > right_bound
      @hover_index = -1
      return
    end
    best = -1
    best_dist = 999999.0
    i = 0
    while i < @num_points
      i_f = i * 1.0
      xx = px + i_f * @x_step
      d = mx - xx
      if d < 0.0
        d = 0.0 - d
      end
      if d < best_dist
        best_dist = d
        best = i
      end
      i = i + 1
    end
    @hover_index = best
  end

  private

  def compute_area_range
    @data_min = 0.0
    @data_max = 1.0
    first = true
    si = 0
    while si < @series_data.length
      ci = 0
      while ci < @series_data[si].length
        v = @series_data[si][ci]
        if first
          @data_min = v
          @data_max = v
          first = false
        else
          if v > @data_max
            @data_max = v
          end
          if v < @data_min
            @data_min = v
          end
        end
        ci = ci + 1
      end
      si = si + 1
    end
    if @data_min > 0.0
      @data_min = 0.0
    end
    range = @data_max - @data_min
    if range > 0.0
      @data_max = @data_max + range * 0.1
    else
      @data_max = @data_max + 1.0
    end
  end
end

def AreaChart(x_labels, series_data, series_names)
  AreaChart.new(x_labels, series_data, series_names)
end
