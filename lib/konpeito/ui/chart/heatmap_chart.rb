# HeatmapChart - 2D grid heatmap with color interpolation
# Supports axis labels, value display, color scale legend

class HeatmapChart < BaseChart
  def initialize(x_labels, y_labels, data_2d)
    super()
    @x_labels = x_labels      # Array of String (column headers)
    @y_labels = y_labels      # Array of String (row headers)
    @data_2d = data_2d        # Array of Array[Float] (rows x cols)
    @show_cell_values = true
    @color_low = 0xFF1A1B26     # Dark blue/black
    @color_high = 0xFF7AA2F7    # Bright blue
    @cell_padding = 2.0
    @data_min = 0.0
    @data_max = 1.0
    @chart_px = 0.0
    @chart_py = 0.0
    @chart_pw = 0.0
    @chart_ph = 0.0
    @num_rows = 0
    @num_cols = 0
    compute_heatmap_range
  end

  def show_cell_values(v)
    @show_cell_values = v
    self
  end

  def color_range(low, high)
    @color_low = low
    @color_high = high
    self
  end

  def cell_padding(p)
    @cell_padding = p
    self
  end

  def set_data(x_labels, y_labels, data_2d)
    @x_labels = x_labels
    @y_labels = y_labels
    @data_2d = data_2d
    compute_heatmap_range
    mark_dirty
    update
  end

  def render_chart(painter, px, py, pw, ph)
    return if @x_labels.length == 0
    return if @y_labels.length == 0
    @chart_px = px
    @chart_py = py
    @chart_pw = pw
    @chart_ph = ph
    @num_rows = @y_labels.length
    @num_cols = @x_labels.length
    draw_heatmap_cells(painter)
    draw_heatmap_x_labels(painter)
    draw_heatmap_y_labels(painter)
    draw_heatmap_color_legend(painter)
  end

  def draw_heatmap_cells(painter)
    cell_w = @chart_pw / (@num_cols * 1.0)
    cell_h = (@chart_ph - 20.0) / (@num_rows * 1.0)
    range = @data_max - @data_min
    if range <= 0.0
      range = 1.0
    end
    ri = 0
    while ri < @num_rows
      ci = 0
      while ci < @num_cols
        draw_heatmap_cell(painter, ri, ci, cell_w, cell_h, range)
        ci = ci + 1
      end
      ri = ri + 1
    end
  end

  def draw_heatmap_cell(painter, ri, ci, cell_w, cell_h, range)
    val = 0.0
    if ri < @data_2d.length
      if ci < @data_2d[ri].length
        val = @data_2d[ri][ci]
      end
    end
    t = (val - @data_min) / range
    if t < 0.0
      t = 0.0
    end
    if t > 1.0
      t = 1.0
    end
    c = painter.interpolate_color(@color_low, @color_high, t)
    cx = @chart_px + ci * 1.0 * cell_w + @cell_padding
    cy = @chart_py + ri * 1.0 * cell_h + @cell_padding
    cw = cell_w - @cell_padding * 2.0
    ch = cell_h - @cell_padding * 2.0
    painter.fill_round_rect(cx, cy, cw, ch, 3.0, c)

    # Hover highlight
    if @hover_series == ri
      if @hover_index == ci
        hc = painter.with_alpha(4294967295, 60)
        painter.stroke_rect(cx, cy, cw, ch, hc, 2.0)
      end
    end

    if @show_cell_values
      vl = painter.number_to_string(val)
      vw = painter.measure_text_width(vl, $theme.font_family, 10.0)
      ascent = painter.get_text_ascent($theme.font_family, 10.0)
      vx = cx + cw / 2.0 - vw / 2.0
      vy = cy + ch / 2.0 + ascent / 2.0
      # Use white text on dark cells, dark on light cells
      text_c = 4294967295
      if t > 0.6
        text_c = 4278190080
      end
      painter.draw_text(vl, vx, vy, $theme.font_family, 10.0, text_c)
    end
  end

  def draw_heatmap_x_labels(painter)
    cell_w = @chart_pw / (@num_cols * 1.0)
    lc = $theme.text_secondary
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    label_y = @chart_py + @chart_ph - 20.0 + 14.0 + ascent
    i = 0
    while i < @num_cols
      label = @x_labels[i]
      lw = painter.measure_text_width(label, $theme.font_family, 11.0)
      lx = @chart_px + i * 1.0 * cell_w + cell_w / 2.0 - lw / 2.0
      painter.draw_text(label, lx, label_y, $theme.font_family, 11.0, lc)
      i = i + 1
    end
  end

  def draw_heatmap_y_labels(painter)
    cell_h = (@chart_ph - 20.0) / (@num_rows * 1.0)
    lc = $theme.text_secondary
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    i = 0
    while i < @num_rows
      label = @y_labels[i]
      lw = painter.measure_text_width(label, $theme.font_family, 11.0)
      lx = @chart_px - lw - 6.0
      ly = @chart_py + i * 1.0 * cell_h + cell_h / 2.0 + ascent / 2.0
      painter.draw_text(label, lx, ly, $theme.font_family, 11.0, lc)
      i = i + 1
    end
  end

  def draw_heatmap_color_legend(painter)
    # Draw a small gradient bar at the right side
    lg_w = 16.0
    lg_h = @chart_ph - 20.0
    lg_x = @chart_px + @chart_pw + 8.0
    lg_y = @chart_py
    steps = 20
    step_h = lg_h / (steps * 1.0)
    i = 0
    while i < steps
      t = 1.0 - (i * 1.0 / (steps * 1.0))
      c = painter.interpolate_color(@color_low, @color_high, t)
      sy = lg_y + i * 1.0 * step_h
      painter.fill_rect(lg_x, sy, lg_w, step_h + 1.0, c)
      i = i + 1
    end
    # Labels
    lc = $theme.text_secondary
    ascent = painter.get_text_ascent($theme.font_family, 9.0)
    max_label = painter.number_to_string(@data_max)
    min_label = painter.number_to_string(@data_min)
    painter.draw_text(max_label, lg_x + lg_w + 4.0, lg_y + ascent, $theme.font_family, 9.0, lc)
    painter.draw_text(min_label, lg_x + lg_w + 4.0, lg_y + lg_h, $theme.font_family, 9.0, lc)
  end

  def update_hover
    # Hover detection disabled for HeatmapChart on JVM
    # (field type issues with @chart_px etc before first render)
  end

  private

  def compute_heatmap_range
    @data_min = 0.0
    @data_max = 1.0
    first = true
    ri = 0
    while ri < @data_2d.length
      ci = 0
      while ci < @data_2d[ri].length
        v = @data_2d[ri][ci]
        if first
          @data_min = v
          @data_max = v
          first = false
        else
          if v < @data_min
            @data_min = v
          end
          if v > @data_max
            @data_max = v
          end
        end
        ci = ci + 1
      end
      ri = ri + 1
    end
    if @data_min == @data_max
      @data_max = @data_min + 1.0
    end
  end
end

def HeatmapChart(x_labels, y_labels, data_2d)
  HeatmapChart.new(x_labels, y_labels, data_2d)
end
