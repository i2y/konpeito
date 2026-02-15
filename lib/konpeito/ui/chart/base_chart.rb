# BaseChart - abstract base class for all chart widgets
# Provides margin management, title, legend, and hover detection

# Chart margin constants
CHART_MARGIN_TOP = 40.0
CHART_MARGIN_RIGHT = 20.0
CHART_MARGIN_BOTTOM = 50.0
CHART_MARGIN_LEFT = 60.0

# Default series colors (8-color palette, Tokyo Night inspired)
def series_color(index)
  i = index % 8
  c = 0
  if i == 0
    c = 4288807671
  elsif i == 1
    c = 4288452202
  elsif i == 2
    c = 4294604430
  elsif i == 3
    c = 4292886376
  elsif i == 4
    c = 4290530039
  elsif i == 5
    c = 4285791434
  elsif i == 6
    c = 4294934372
  else
    c = 4286361599
  end
  c
end

class BaseChart < Widget
  def initialize
    super()
    @margin_top = CHART_MARGIN_TOP
    @margin_right = CHART_MARGIN_RIGHT
    @margin_bottom = CHART_MARGIN_BOTTOM
    @margin_left = CHART_MARGIN_LEFT
    @title_text = nil
    @show_legend = true
    @hover_index = -1
    @hover_series = -1
    @mouse_x = -1.0
    @mouse_y = -1.0
    @painter = nil
    @width_policy = EXPANDING
    @height_policy = EXPANDING
  end

  def title(t)
    @title_text = t
    self
  end

  def legend(show)
    @show_legend = show
    self
  end

  def margins(top, right, bottom, left)
    @margin_top = top
    @margin_right = right
    @margin_bottom = bottom
    @margin_left = left
    self
  end

  def plot_x
    @margin_left
  end

  def plot_y
    @margin_top
  end

  def plot_w
    w = @width - @margin_left - @margin_right
    if w < 0.0
      w = 0.0
    end
    w
  end

  def plot_h
    h = @height - @margin_top - @margin_bottom
    if h < 0.0
      h = 0.0
    end
    h
  end

  def redraw(painter, completely)
    @painter = painter
    bg = $theme.bg_primary
    painter.fill_rect(0.0, 0.0, @width, @height, bg)
    draw_title(painter)
    render_chart(painter, plot_x, plot_y, plot_w, plot_h)
  end

  def draw_title(painter)
    return if @title_text == nil
    tw = painter.measure_text_width(@title_text, $theme.font_family, 16.0)
    tx = (@width - tw) / 2.0
    ascent = painter.get_text_ascent($theme.font_family, 16.0)
    tc = $theme.text_primary
    painter.draw_text(@title_text, tx, 8.0 + ascent, $theme.font_family, 16.0, tc)
  end

  def render_chart(painter, px, py, pw, ph)
  end

  # Draw one legend item
  def draw_legend_item(painter, label, color, cx, y)
    painter.fill_rect(cx, y, 12.0, 12.0, color)
    lx = cx + 16.0
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    tc = $theme.text_secondary
    painter.draw_text(label, lx, y + ascent, $theme.font_family, 11.0, tc)
    lw = painter.measure_text_width(label, $theme.font_family, 11.0)
    lx + lw + 16.0
  end

  # Draw legend items
  def draw_legend(painter, labels, colors, x, y)
    return if labels.length == 0
    cx = x
    i = 0
    while i < labels.length
      c = colors[i % colors.length]
      cx = draw_legend_item(painter, labels[i], c, cx, y)
      i = i + 1
    end
  end

  # Draw one Y-axis tick (grid line + tick mark)
  def draw_y_tick(painter, px, pw, yy, grid_color, border_color)
    painter.draw_line(px, yy, px + pw, yy, grid_color, 1.0)
    painter.draw_line(px - 4.0, yy, px, yy, border_color, 1.0)
  end

  # Draw one Y-axis tick label
  def draw_y_tick_label(painter, px, yy, label, label_color)
    lw = painter.measure_text_width(label, $theme.font_family, 11.0)
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    lx = px - lw - 6.0
    ly = yy + ascent / 2.0
    painter.draw_text(label, lx, ly, $theme.font_family, 11.0, label_color)
  end

  # Draw Y-axis with tick marks and grid lines
  def draw_y_axis(painter, px, py, pw, ph, ticks, scale)
    bc = $theme.border
    painter.draw_line(px, py, px, py + ph, bc, 1.0)
    gc = painter.with_alpha(bc, 60)
    lc = $theme.text_secondary
    i = 0
    while i < ticks.length
      yy = scale.map(ticks[i])
      draw_y_tick(painter, px, pw, yy, gc, bc)
      label = format_axis_value(painter, ticks[i])
      draw_y_tick_label(painter, px, yy, label, lc)
      i = i + 1
    end
  end

  # Draw X-axis line
  def draw_x_axis_line(painter, px, py, pw, ph)
    bc = $theme.border
    painter.draw_line(px, py + ph, px + pw, py + ph, bc, 1.0)
  end

  # Mouse tracking for hover
  def cursor_pos(ev)
    @mouse_x = ev.pos.x
    @mouse_y = ev.pos.y
    old_hi = @hover_index
    old_hs = @hover_series
    update_hover
    if @hover_index != old_hi
      mark_dirty
      update
    elsif @hover_series != old_hs
      mark_dirty
      update
    end
  end

  def mouse_out
    changed = false
    if @hover_index != -1
      @hover_index = -1
      changed = true
    end
    if @hover_series != -1
      @hover_series = -1
      changed = true
    end
    if changed
      @mouse_x = -1.0
      @mouse_y = -1.0
      mark_dirty
      update
    end
  end

  def update_hover
  end
end
