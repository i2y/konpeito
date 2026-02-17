# MultilineText widget - displays multiline text with optional word wrapping
# Port of Castella MultilineText

class MultilineText < Widget
  def initialize(text)
    super()
    @text = text
    @font_family = nil
    @font_size_val = 14.0
    @color_val = 0xFFC0CAF5
    @custom_color = false
    @kind_val = 0
    @padding_val = 8.0
    @line_spacing = 4.0
    @wrap_enabled = false
    @border_width_val = 1.0
    @cached_lines = []
  end

  def font_family(f)
    @font_family = f
    self
  end

  def resolved_font_family
    if @font_family != nil
      @font_family
    else
      $theme.font_family
    end
  end

  def font_size(s)
    @font_size_val = s
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

  def padding(p)
    @padding_val = p
    self
  end

  def line_spacing(s)
    @line_spacing = s
    self
  end

  def wrap_text(w)
    @wrap_enabled = w
    self
  end

  def set_text(t)
    @text = t
    @cached_lines = []
    mark_dirty
  end

  def get_text
    @text
  end

  def measure(painter)
    lines = split_lines(painter)
    @cached_lines = lines
    if lines.length == 0
      return Size.new(@padding_val * 2.0, @padding_val * 2.0)
    end
    ff = resolved_font_family
    max_w = 0.0
    i = 0
    while i < lines.length
      lw = painter.measure_text_width(lines[i], ff, @font_size_val)
      if lw > max_w
        max_w = lw
      end
      i = i + 1
    end
    w = max_w + (@padding_val + @border_width_val) * 2.0
    h = @font_size_val * lines.length + @line_spacing * (lines.length - 1) + @padding_val * 2.0 + @border_width_val * 2.0
    Size.new(w, h)
  end

  def redraw(painter, completely)
    lines = split_lines(painter)
    @cached_lines = lines

    # Background
    bg_c = $theme.bg_primary
    brd_c = $theme.border
    painter.fill_rect(0.0, 0.0, @width, @height, bg_c)
    painter.stroke_rect(0.0, 0.0, @width, @height, brd_c, @border_width_val)

    # Text
    ff = resolved_font_family
    c = @custom_color ? @color_val : $theme.text_color_for_kind(@kind_val)
    ascent = painter.get_text_ascent(ff, @font_size_val)
    y = @padding_val + @border_width_val + ascent
    i = 0
    while i < lines.length
      painter.draw_text(lines[i], @padding_val + @border_width_val, y, ff, @font_size_val, c)
      y = y + @font_size_val + @line_spacing
      i = i + 1
    end
  end

  def split_lines(painter)
    raw_lines = @text.split("\n")
    if !@wrap_enabled
      return raw_lines
    end
    # Word wrapping
    ff = resolved_font_family
    line_width = @width - (@padding_val + @border_width_val) * 2.0
    if line_width <= 0.0
      return raw_lines
    end
    result = []
    ri = 0
    while ri < raw_lines.length
      line = raw_lines[ri]
      words = line.split(" ")
      if words.length == 0
        result.push("")
        ri = ri + 1
        next
      end
      current_words = []
      current_width = 0.0
      wi = 0
      while wi < words.length
        word = words[wi]
        word_w = painter.measure_text_width(word, ff, @font_size_val)
        space_w = 0.0
        if current_words.length > 0
          space_w = painter.measure_text_width(" ", ff, @font_size_val)
        end
        if current_width + space_w + word_w > line_width
          if current_words.length > 0
            result.push(current_words.join(" "))
            current_words = [word]
            current_width = word_w
          else
            # Single word wider than line - just include it
            result.push(word)
            current_words = []
            current_width = 0.0
          end
        else
          current_words.push(word)
          current_width = current_width + space_w + word_w
        end
        wi = wi + 1
      end
      if current_words.length > 0
        result.push(current_words.join(" "))
      end
      ri = ri + 1
    end
    result
  end
end

# Top-level helper
def MultilineText(text)
  MultilineText.new(text)
end
