# Button widget - clickable button with label
# Port of Castella Button

class Button < Widget
  def initialize(label)
    super()
    @label = label
    @font_size_val = 14.0
    @kind_val = 0
    @custom_bg = false
    @custom_text = false
    @bg_color = 0xFF7AA2F7
    @text_color = 0xFF1A1B26
    @hover_color = 0xFF89B4FA
    @radius = 4.0
    @hovered = false
    @click_handler = nil
    @width_policy = CONTENT
    @height_policy = CONTENT
    @pad_top = 8.0
    @pad_right = 16.0
    @pad_bottom = 8.0
    @pad_left = 16.0
  end

  def kind(k)
    @kind_val = k
    self
  end

  def on_click(&block)
    @click_handler = block
    self
  end

  def font_size(s)
    @font_size_val = s
    self
  end

  def bg(c)
    @bg_color = c
    @custom_bg = true
    self
  end

  def text_color(c)
    @text_color = c
    @custom_text = true
    self
  end

  def measure(painter)
    tw = painter.measure_text_width(@label, $theme.font_family, @font_size_val)
    th = painter.measure_text_height($theme.font_family, @font_size_val)
    Size.new(tw + @pad_left + @pad_right, th + @pad_top + @pad_bottom)
  end

  def redraw(painter, completely)
    # Use theme colors based on kind, unless custom colors were set
    if @custom_bg
      bg_c = @hovered ? @hover_color : @bg_color
    else
      if @hovered
        bg_c = $theme.button_hover(@kind_val)
      else
        bg_c = $theme.button_bg(@kind_val)
      end
    end
    if @custom_text
      tc = @text_color
    else
      tc = $theme.button_text(@kind_val)
    end

    painter.fill_round_rect(0.0, 0.0, @width, @height, @radius, bg_c)
    ascent = painter.get_text_ascent($theme.font_family, @font_size_val)
    th = painter.measure_text_height($theme.font_family, @font_size_val)
    text_y = (@height - th) / 2.0 + ascent
    painter.draw_text(@label, @pad_left, text_y, $theme.font_family, @font_size_val, tc)
  end

  def mouse_up(ev)
    @click_handler.call if @click_handler
  end

  def mouse_over
    @hovered = true
    mark_dirty
    update
  end

  def mouse_out
    @hovered = false
    mark_dirty
    update
  end
end

# Top-level helper
def Button(label)
  Button.new(label)
end
