# RadioButtons widget - exclusive selection from a list
# Port of Castella RadioButtons
# Single widget that renders all options (avoids cross-class method calls)

class RadioButtons < Widget
  def initialize(options)
    super()
    @options = options
    @option_count = options.length
    @selected = 0
    @change_handler = nil
    @hovered_index = -1
    # Colors (Tokyo Night)
    @text_color = 0xFFC0CAF5
    @ring_color = 0xFF565F89
    @selected_color = 0xFF7AA2F7
    @font_size_val = 14.0
    @item_height = 32.0
  end

  def with_selected(index)
    @selected = index
    self
  end

  def on_change(&block)
    @change_handler = block
    self
  end

  def get_selected
    @selected
  end

  def measure(painter)
    max_w = 0.0
    i = 0
    while i < @option_count
      tw = painter.measure_text_width(@options[i], $theme.font_family, @font_size_val)
      w = tw + 32.0
      if w > max_w
        max_w = w
      end
      i = i + 1
    end
    Size.new(max_w, @item_height * @option_count)
  end

  def redraw(painter, completely)
    circle_r = 7.0
    i = 0
    while i < @option_count
      iy = @item_height * i
      cx = circle_r + 4.0
      cy = iy + @item_height / 2.0

      # Outer ring
      painter.fill_circle(cx, cy, circle_r, @ring_color)
      painter.fill_circle(cx, cy, circle_r - 1.5, 0xFF1A1B26)

      # Selected dot
      if @selected == i
        painter.fill_circle(cx, cy, 4.0, @selected_color)
      end

      # Label
      ascent = painter.get_text_ascent($theme.font_family, @font_size_val)
      text_x = cx + circle_r + 8.0
      th = painter.measure_text_height($theme.font_family, @font_size_val)
      text_y = iy + (@item_height - th) / 2.0 + ascent
      painter.draw_text(@options[i], text_x, text_y, $theme.font_family, @font_size_val, @text_color)

      i = i + 1
    end
  end

  def mouse_down(ev)
    index = (ev.pos.y / @item_height).to_i
    if index >= 0 && index < @option_count && index != @selected
      @selected = index
      @change_handler.call(@selected) if @change_handler
      mark_dirty
      update
    end
  end
end

# Top-level helper
def RadioButtons(options)
  RadioButtons.new(options)
end
