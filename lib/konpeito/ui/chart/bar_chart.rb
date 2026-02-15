# BarChart - grouped bar chart widget
# Supports multiple series, hover highlight, value labels

class BarChart < BaseChart
  def initialize(categories, series_data, series_names)
    super()
    @categories = categories
    @series_data = series_data
    @series_names = series_names
    @show_values = false
    @bar_radius = 2.0
    @data_min = 0.0
    @data_max = 0.0
    # Computed per-frame
    @y_scale = nil
    @y_ticks = nil
    @band = nil
    @bar_w = 2.0
    @bar_gap = 2.0
    @baseline_y = 0.0
    @num_series = 0
    @num_cats = 0
    @y_range_min = 0.0
    @y_range_max = 1.0
    @chart_px = 0.0
    @chart_py = 0.0
    @chart_pw = 0.0
    @chart_ph = 0.0
    compute_data_range
  end

  def show_values(v)
    @show_values = v
    self
  end

  def bar_radius(r)
    @bar_radius = r
    self
  end

  def set_data(categories, series_data, series_names)
    @categories = categories
    @series_data = series_data
    @series_names = series_names
    compute_data_range
    mark_dirty
    update
  end

  def render_chart(painter, px, py, pw, ph)
    return if @categories.length == 0
    return if @series_data.length == 0
    @chart_px = px
    @chart_py = py
    @chart_pw = pw
    @chart_ph = ph
    setup_chart_counts
    setup_chart_ticks
    setup_chart_y_scale
    setup_chart_band
    setup_chart_bar_width
    setup_chart_baseline
    draw_y_axis(painter, px, py, pw, ph, @y_ticks, @y_scale)
    draw_x_axis_line(painter, px, py, pw, ph)
    draw_cat_labels(painter)
    draw_all_bars(painter)
    draw_bar_legend(painter, px, py)
  end

  def setup_chart_counts
    @num_series = @series_data.length
    @num_cats = @categories.length
  end

  def setup_chart_ticks
    @y_ticks = compute_ticks(@data_min, @data_max, 5)
    @y_range_min = @data_min
    @y_range_max = @data_max
    if @y_ticks.length > 0
      @y_range_min = @y_ticks[0]
      @y_range_max = @y_ticks[@y_ticks.length - 1]
    end
  end

  def setup_chart_y_scale
    bottom = @chart_py + @chart_ph
    @y_scale = LinearScale.new(@y_range_min, @y_range_max, bottom, @chart_py)
  end

  def setup_chart_band
    right = @chart_px + @chart_pw
    nc = @num_cats * 1.0
    @band = BandScale.new(nc, @chart_px, right, 12.0)
  end

  def setup_chart_bar_width
    @bar_gap = 2.0
    group_w = @band.band_width
    ns = @num_series * 1.0
    ns_minus_1 = ns - 1.0
    @bar_w = (group_w - @bar_gap * ns_minus_1) / ns
    if @bar_w < 2.0
      @bar_w = 2.0
    end
  end

  def setup_chart_baseline
    @baseline_y = @y_scale.map(0.0)
    if @baseline_y < @chart_py
      @baseline_y = @chart_py
    end
    bmax = @chart_py + @chart_ph
    if @baseline_y > bmax
      @baseline_y = bmax
    end
  end

  def draw_cat_labels(painter)
    lc = $theme.text_secondary
    i = 0
    while i < @num_cats
      draw_one_cat_label(painter, i, lc)
      i = i + 1
    end
  end

  def draw_one_cat_label(painter, i, lc)
    i_f = i * 1.0
    bx = @band.map(i_f)
    label = @categories[i]
    lw = painter.measure_text_width(label, $theme.font_family, 11.0)
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    label_x = bx + @band.band_width / 2.0 - lw / 2.0
    label_y = @chart_py + @chart_ph + 14.0 + ascent
    painter.draw_text(label, label_x, label_y, $theme.font_family, 11.0, lc)
  end

  def draw_all_bars(painter)
    si = 0
    while si < @num_series
      ci = 0
      while ci < @num_cats
        draw_one_bar(painter, si, ci)
        ci = ci + 1
      end
      si = si + 1
    end
  end

  def draw_one_bar(painter, si, ci)
    val = @series_data[si][ci]
    bx = compute_bar_x(ci, si)
    bar_top = @y_scale.map(val)
    bar_h = @baseline_y - bar_top
    if bar_h < 0.0
      bar_top = @baseline_y
      bar_h = 0.0 - bar_h
    end
    c = get_bar_color(painter, si, ci)
    painter.fill_round_rect(bx, bar_top, @bar_w, bar_h, @bar_radius, c)
    if @show_values
      draw_bar_value(painter, val, bx, bar_top)
    end
  end

  def compute_bar_x(ci, si)
    ci_f = ci * 1.0
    si_f = si * 1.0
    @band.map(ci_f) + si_f * (@bar_w + @bar_gap)
  end

  def get_bar_color(painter, si, ci)
    c = series_color(si)
    if @hover_index == ci
      if @hover_series == si
        c = painter.lighten_color(c, 0.3)
      end
    end
    c
  end

  def draw_bar_value(painter, val, bx, bar_top)
    vl = format_axis_value(painter, val)
    vw = painter.measure_text_width(vl, $theme.font_family, 10.0)
    vx = bx + @bar_w / 2.0 - vw / 2.0
    vy = bar_top - 4.0
    painter.draw_text(vl, vx, vy, $theme.font_family, 10.0, $theme.text_secondary)
  end

  def draw_bar_legend(painter, px, py)
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
    return if @band == nil
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
    find_bar_hover(mx)
  end

  def find_bar_hover(mx)
    @hover_index = -1
    @hover_series = -1
    ci = 0
    while ci < @num_cats
      si = 0
      while si < @num_series
        bx = compute_bar_x(ci, si)
        if mx >= bx
          if mx <= bx + @bar_w
            @hover_index = ci
            @hover_series = si
            return
          end
        end
        si = si + 1
      end
      ci = ci + 1
    end
  end

  private

  def compute_data_range
    @data_min = 0.0
    @data_max = 1.0
    si = 0
    while si < @series_data.length
      ci = 0
      while ci < @series_data[si].length
        v = @series_data[si][ci]
        if v > @data_max
          @data_max = v
        end
        if v < @data_min
          @data_min = v
        end
        ci = ci + 1
      end
      si = si + 1
    end
    range = @data_max - @data_min
    if range > 0.0
      @data_max = @data_max + range * 0.1
    else
      @data_max = @data_min + 1.0
    end
  end
end

def BarChart(categories, series_data, series_names)
  BarChart.new(categories, series_data, series_names)
end
