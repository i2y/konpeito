# ScatterChart - XY scatter plot with point markers
# Supports multiple series, hover detection, value labels

class ScatterChart < BaseChart
  def initialize(x_data, y_data, series_names)
    super()
    @x_data = x_data          # Array of Array[Float] (one per series)
    @y_data = y_data          # Array of Array[Float] (one per series)
    @series_names = series_names
    @point_radius = 5.0
    @show_grid = true
    @data_x_min = 0.0
    @data_x_max = 1.0
    @data_y_min = 0.0
    @data_y_max = 1.0
    @x_scale = nil
    @y_scale = nil
    @x_ticks = nil
    @y_ticks = nil
    @num_series = 0
    @chart_px = 0.0
    @chart_py = 0.0
    @chart_pw = 0.0
    @chart_ph = 0.0
    compute_scatter_range
  end

  def point_radius(r)
    @point_radius = r
    self
  end

  def show_grid(v)
    @show_grid = v
    self
  end

  def set_data(x_data, y_data, series_names)
    @x_data = x_data
    @y_data = y_data
    @series_names = series_names
    compute_scatter_range
    mark_dirty
    update
  end

  def render_chart(painter, px, py, pw, ph)
    return if @x_data.length == 0
    @chart_px = px
    @chart_py = py
    @chart_pw = pw
    @chart_ph = ph
    @num_series = @x_data.length
    setup_scatter_scales
    draw_scatter_grid(painter)
    draw_y_axis(painter, px, py, pw, ph, @y_ticks, @y_scale)
    draw_x_axis_line(painter, px, py, pw, ph)
    draw_scatter_x_ticks(painter)
    draw_all_scatter_points(painter)
    draw_scatter_legend(painter, px, py)
  end

  def setup_scatter_scales
    @x_ticks = compute_ticks(@data_x_min, @data_x_max, 5)
    @y_ticks = compute_ticks(@data_y_min, @data_y_max, 5)
    x_min = @data_x_min
    x_max = @data_x_max
    y_min = @data_y_min
    y_max = @data_y_max
    if @x_ticks.length > 0
      x_min = @x_ticks[0]
      x_max = @x_ticks[@x_ticks.length - 1]
    end
    if @y_ticks.length > 0
      y_min = @y_ticks[0]
      y_max = @y_ticks[@y_ticks.length - 1]
    end
    bottom = @chart_py + @chart_ph
    right = @chart_px + @chart_pw
    @x_scale = LinearScale.new(x_min, x_max, @chart_px, right)
    @y_scale = LinearScale.new(y_min, y_max, bottom, @chart_py)
  end

  def draw_scatter_grid(painter)
    return if !@show_grid
    bc = $theme.border
    gc = painter.with_alpha(bc, 40)
    # Vertical grid lines at x ticks
    i = 0
    while i < @x_ticks.length
      xx = @x_scale.map(@x_ticks[i])
      bottom = @chart_py + @chart_ph
      painter.draw_line(xx, @chart_py, xx, bottom, gc, 1.0)
      i = i + 1
    end
  end

  def draw_scatter_x_ticks(painter)
    lc = $theme.text_secondary
    i = 0
    while i < @x_ticks.length
      xx = @x_scale.map(@x_ticks[i])
      label = painter.number_to_string(@x_ticks[i])
      lw = painter.measure_text_width(label, $theme.font_family, 11.0)
      ascent = painter.get_text_ascent($theme.font_family, 11.0)
      label_y = @chart_py + @chart_ph + 14.0 + ascent
      painter.draw_text(label, xx - lw / 2.0, label_y, $theme.font_family, 11.0, lc)
      i = i + 1
    end
  end

  def draw_all_scatter_points(painter)
    si = 0
    while si < @num_series
      c = series_color(si)
      draw_scatter_series(painter, si, c)
      si = si + 1
    end
  end

  def draw_scatter_series(painter, si, c)
    xs = @x_data[si]
    ys = @y_data[si]
    n = xs.length
    if ys.length < n
      n = ys.length
    end
    j = 0
    while j < n
      xx = @x_scale.map(xs[j])
      yy = @y_scale.map(ys[j])
      r = @point_radius
      if @hover_series == si
        if @hover_index == j
          r = @point_radius + 3.0
        end
      end
      painter.fill_circle(xx, yy, r, c)
      if @hover_series == si
        if @hover_index == j
          draw_scatter_label(painter, xs[j], ys[j], xx, yy, r)
        end
      end
      j = j + 1
    end
  end

  def draw_scatter_label(painter, xv, yv, xx, yy, r)
    xl = painter.number_to_string(xv)
    yl = painter.number_to_string(yv)
    label = "(" + xl + ", " + yl + ")"
    lw = painter.measure_text_width(label, $theme.font_family, 10.0)
    tc = $theme.text_primary
    painter.draw_text(label, xx - lw / 2.0, yy - r - 4.0, $theme.font_family, 10.0, tc)
  end

  def draw_scatter_legend(painter, px, py)
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
    return if @x_scale == nil
    mx = @mouse_x
    my = @mouse_y
    px = plot_x
    py = plot_y
    pw = plot_w
    ph = plot_h
    if mx < px
      @hover_index = -1
      @hover_series = -1
      return
    end
    if mx > px + pw
      @hover_index = -1
      @hover_series = -1
      return
    end
    if my < py
      @hover_index = -1
      @hover_series = -1
      return
    end
    if my > py + ph
      @hover_index = -1
      @hover_series = -1
      return
    end
    find_nearest_scatter_point(mx, my)
  end

  def find_nearest_scatter_point(mx, my)
    best_si = -1
    best_j = -1
    best_dist = 999999.0
    si = 0
    while si < @num_series
      xs = @x_data[si]
      ys = @y_data[si]
      n = xs.length
      if ys.length < n
        n = ys.length
      end
      j = 0
      while j < n
        xx = @x_scale.map(xs[j])
        yy = @y_scale.map(ys[j])
        dx = mx - xx
        dy = my - yy
        d = dx * dx + dy * dy
        if d < best_dist
          best_dist = d
          best_si = si
          best_j = j
        end
        j = j + 1
      end
      si = si + 1
    end
    threshold = (@point_radius + 8.0) * (@point_radius + 8.0)
    if best_dist < threshold
      @hover_series = best_si
      @hover_index = best_j
    else
      @hover_series = -1
      @hover_index = -1
    end
  end

  private

  def compute_scatter_range
    @data_x_min = 0.0
    @data_x_max = 1.0
    @data_y_min = 0.0
    @data_y_max = 1.0
    first = true
    si = 0
    while si < @x_data.length
      xs = @x_data[si]
      ys = @y_data[si]
      n = xs.length
      if ys.length < n
        n = ys.length
      end
      j = 0
      while j < n
        xv = xs[j]
        yv = ys[j]
        if first
          @data_x_min = xv
          @data_x_max = xv
          @data_y_min = yv
          @data_y_max = yv
          first = false
        else
          if xv < @data_x_min
            @data_x_min = xv
          end
          if xv > @data_x_max
            @data_x_max = xv
          end
          if yv < @data_y_min
            @data_y_min = yv
          end
          if yv > @data_y_max
            @data_y_max = yv
          end
        end
        j = j + 1
      end
      si = si + 1
    end
    xr = @data_x_max - @data_x_min
    yr = @data_y_max - @data_y_min
    if xr > 0.0
      @data_x_max = @data_x_max + xr * 0.05
      @data_x_min = @data_x_min - xr * 0.05
    else
      @data_x_max = @data_x_max + 1.0
    end
    if yr > 0.0
      @data_y_max = @data_y_max + yr * 0.05
      @data_y_min = @data_y_min - yr * 0.05
    else
      @data_y_max = @data_y_max + 1.0
    end
  end
end

def ScatterChart(x_data, y_data, series_names)
  ScatterChart.new(x_data, y_data, series_names)
end
