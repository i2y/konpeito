# StackedBarChart - stacked bar chart widget
# Supports multiple series stacked on top of each other, hover highlight

class StackedBarChart < BaseChart
  def initialize(categories, series_data, series_names)
    super()
    @categories = categories
    @series_data = series_data
    @series_names = series_names
    @show_values = false
    @bar_radius = 0.0
    @data_min = 0.0
    @data_max = 0.0
    @y_scale = nil
    @y_ticks = nil
    @band = nil
    @bar_w = 2.0
    @baseline_y = 0.0
    @num_series = 0
    @num_cats = 0
    @y_range_min = 0.0
    @y_range_max = 1.0
    @chart_px = 0.0
    @chart_py = 0.0
    @chart_pw = 0.0
    @chart_ph = 0.0
    compute_stacked_range
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
    compute_stacked_range
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
    @num_series = @series_data.length
    @num_cats = @categories.length
    setup_stacked_ticks
    setup_stacked_y_scale
    setup_stacked_band
    @baseline_y = @y_scale.map(0.0)
    bmax = @chart_py + @chart_ph
    if @baseline_y > bmax
      @baseline_y = bmax
    end
    draw_y_axis(painter, px, py, pw, ph, @y_ticks, @y_scale)
    draw_x_axis_line(painter, px, py, pw, ph)
    draw_stacked_cat_labels(painter)
    draw_all_stacked_bars(painter)
    draw_stacked_legend(painter, px, py)
  end

  def setup_stacked_ticks
    @y_ticks = compute_ticks(@data_min, @data_max, 5)
    @y_range_min = @data_min
    @y_range_max = @data_max
    if @y_ticks.length > 0
      @y_range_min = @y_ticks[0]
      @y_range_max = @y_ticks[@y_ticks.length - 1]
    end
  end

  def setup_stacked_y_scale
    bottom = @chart_py + @chart_ph
    @y_scale = LinearScale.new(@y_range_min, @y_range_max, bottom, @chart_py)
  end

  def setup_stacked_band
    right = @chart_px + @chart_pw
    nc = @num_cats * 1.0
    @band = BandScale.new(nc, @chart_px, right, 12.0)
    @bar_w = @band.band_width
  end

  def draw_stacked_cat_labels(painter)
    lc = $theme.text_secondary
    i = 0
    while i < @num_cats
      i_f = i * 1.0
      bx = @band.map(i_f)
      label = @categories[i]
      lw = painter.measure_text_width(label, $theme.font_family, 11.0)
      ascent = painter.get_text_ascent($theme.font_family, 11.0)
      label_x = bx + @bar_w / 2.0 - lw / 2.0
      label_y = @chart_py + @chart_ph + 14.0 + ascent
      painter.draw_text(label, label_x, label_y, $theme.font_family, 11.0, lc)
      i = i + 1
    end
  end

  def draw_all_stacked_bars(painter)
    ci = 0
    while ci < @num_cats
      draw_stacked_column(painter, ci)
      ci = ci + 1
    end
  end

  def draw_stacked_column(painter, ci)
    ci_f = ci * 1.0
    bx = @band.map(ci_f)
    cumulative = 0.0
    si = 0
    while si < @num_series
      val = @series_data[si][ci]
      top_val = cumulative + val
      bar_bottom = @y_scale.map(cumulative)
      bar_top = @y_scale.map(top_val)
      bar_h = bar_bottom - bar_top
      if bar_h < 0.0
        bar_h = 0.0 - bar_h
        bar_top = bar_bottom
      end
      c = series_color(si)
      if @hover_index == ci
        if @hover_series == si
          c = painter.lighten_color(c, 0.3)
        end
      end
      painter.fill_round_rect(bx, bar_top, @bar_w, bar_h, @bar_radius, c)
      if @show_values
        if val > 0.0
          vl = painter.number_to_string(val)
          vw = painter.measure_text_width(vl, $theme.font_family, 9.0)
          ascent = painter.get_text_ascent($theme.font_family, 9.0)
          vx = bx + @bar_w / 2.0 - vw / 2.0
          vy = bar_top + bar_h / 2.0 + ascent / 2.0
          painter.draw_text(vl, vx, vy, $theme.font_family, 9.0, 4294967295)
        end
      end
      cumulative = top_val
      si = si + 1
    end
  end

  def draw_stacked_legend(painter, px, py)
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
    find_stacked_hover(mx, my)
  end

  def find_stacked_hover(mx, my)
    @hover_index = -1
    @hover_series = -1
    ci = 0
    while ci < @num_cats
      ci_f = ci * 1.0
      bx = @band.map(ci_f)
      if mx >= bx
        if mx <= bx + @bar_w
          # Found the category, now find which series segment
          cumulative = 0.0
          si = 0
          while si < @num_series
            val = @series_data[si][ci]
            top_val = cumulative + val
            bar_bottom = @y_scale.map(cumulative)
            bar_top = @y_scale.map(top_val)
            if bar_top > bar_bottom
              tmp = bar_top
              bar_top = bar_bottom
              bar_bottom = tmp
            end
            if my >= bar_top
              if my <= bar_bottom
                @hover_index = ci
                @hover_series = si
                return
              end
            end
            cumulative = top_val
            si = si + 1
          end
          @hover_index = ci
          return
        end
      end
      ci = ci + 1
    end
  end

  private

  def compute_stacked_range
    @data_min = 0.0
    @data_max = 1.0
    return if @series_data.length == 0
    return if @categories.length == 0
    max_stack = 0.0
    ci = 0
    while ci < @categories.length
      stack_total = 0.0
      si = 0
      while si < @series_data.length
        if ci < @series_data[si].length
          stack_total = stack_total + @series_data[si][ci]
        end
        si = si + 1
      end
      if stack_total > max_stack
        max_stack = stack_total
      end
      ci = ci + 1
    end
    @data_max = max_stack
    range = @data_max - @data_min
    if range > 0.0
      @data_max = @data_max + range * 0.1
    else
      @data_max = @data_min + 1.0
    end
  end
end

def StackedBarChart(categories, series_data, series_names)
  StackedBarChart.new(categories, series_data, series_names)
end
