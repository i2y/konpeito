# Text widget - displays text
# Port of Castella Text

# Text alignment constants
TEXT_ALIGN_LEFT = 0
TEXT_ALIGN_CENTER = 1
TEXT_ALIGN_RIGHT = 2

class Text < Widget
  def initialize(text)
    super()
    @text = text
    @font_family_val = nil
    @font_size_val = 14.0
    @color_val = 0xFFC0CAF5
    @custom_color = false
    @kind_val = 0
    @text_align = TEXT_ALIGN_LEFT
    @font_weight = 0
    @font_slant = 0
  end

  def font_size(s)
    @font_size_val = s
    self
  end

  def font_family(f)
    @font_family_val = f
    self
  end

  def resolved_font_family
    if @font_family_val != nil
      @font_family_val
    else
      $theme.font_family
    end
  end

  def bold
    @font_weight = 1
    self
  end

  def italic
    @font_slant = 1
    self
  end

  def color(c)
    @color_val = c
    @custom_color = true
    self
  end

  def kind(k)
    @kind_val = k
    self
  end

  def align(a)
    @text_align = a
    self
  end

  def set_text(t)
    @text = t
    mark_dirty
  end

  def get_text
    @text
  end

  def measure(painter)
    ff = resolved_font_family
    w = painter.measure_text_width(@text, ff, @font_size_val)
    h = painter.measure_text_height(ff, @font_size_val)
    Size.new(w, h)
  end

  def redraw(painter, completely)
    ff = resolved_font_family
    ascent = painter.get_text_ascent(ff, @font_size_val)
    th = painter.measure_text_height(ff, @font_size_val)

    # Vertical centering when widget is taller than text
    if @height > th
      y_offset = (@height - th) / 2.0 + ascent
    else
      y_offset = ascent
    end

    # Horizontal alignment
    x_offset = 0.0
    if @text_align == TEXT_ALIGN_CENTER
      text_w = painter.measure_text_width(@text, ff, @font_size_val)
      x_offset = (@width - text_w) / 2.0
      if x_offset < 0.0
        x_offset = 0.0
      end
    elsif @text_align == TEXT_ALIGN_RIGHT
      text_w = painter.measure_text_width(@text, ff, @font_size_val)
      x_offset = @width - text_w
      if x_offset < 0.0
        x_offset = 0.0
      end
    end
    c = @custom_color ? @color_val : $theme.text_color_for_kind(@kind_val)
    painter.draw_text(@text, x_offset, y_offset, ff, @font_size_val, c, @font_weight, @font_slant)
  end
end

# Top-level helper
def Text(text)
  Text.new(text)
end
