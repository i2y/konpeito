# Checkbox widget - toggleable checkbox with label
# Port of Castella Checkbox

class Checkbox < Widget
  def initialize(label)
    super()
    @label = label
    @checked = false
    @on_toggle_handler = nil
    @has_toggle_handler = false
    @font_size_val = 14.0
    @check_color = 0
    @text_color_val = 0
    @box_color = 0
    @hover_color = 0
    @custom_check = false
    @custom_text = false
    @hovered = false
  end

  def checked(v)
    @checked = v
    mark_dirty
    self
  end

  def is_checked
    @checked
  end

  def on_toggle(&block)
    @on_toggle_handler = block
    @has_toggle_handler = true
    self
  end

  def font_size(s)
    @font_size_val = s
    self
  end

  def check_color(c)
    @check_color = c
    @custom_check = true
    self
  end

  def text_color(c)
    @text_color_val = c
    @custom_text = true
    self
  end

  def mouse_up(ev)
    if @checked
      @checked = false
    else
      @checked = true
    end
    mark_dirty
    update
    if @has_toggle_handler
      @on_toggle_handler.call(@checked)
    end
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

  def measure(painter)
    tw = painter.measure_text_width(@label, $theme.font_family, @font_size_val)
    th = painter.measure_text_height($theme.font_family, @font_size_val)
    box_size = th
    gap = 8.0
    Size.new(box_size + gap + tw, th)
  end

  def redraw(painter, completely)
    th = painter.measure_text_height($theme.font_family, @font_size_val)
    ascent = painter.get_text_ascent($theme.font_family, @font_size_val)
    box_size = th
    gap = 8.0

    # Resolve colors from theme
    chk_c = @custom_check ? @check_color : $theme.accent
    txt_c = @custom_text ? @text_color_val : $theme.text_primary
    box_c = $theme.border
    hov_c = $theme.bg_secondary

    # Checkbox box border
    border_c = @hovered ? hov_c : box_c
    painter.stroke_rect(0.0, 0.0, box_size, box_size, border_c, 1.5)

    # Checkmark fill (when checked)
    if @checked
      inset = 3.0
      painter.fill_rect(inset, inset, box_size - inset * 2.0, box_size - inset * 2.0, chk_c)
    end

    # Label text
    painter.draw_text(@label, box_size + gap, ascent, $theme.font_family, @font_size_val, txt_c)
  end
end

# Top-level helper
def Checkbox(label)
  Checkbox.new(label)
end
