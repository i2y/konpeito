# ProgressBar widget - progress indicator
# Port of Castella ProgressBar

class ProgressBar < Widget
  def initialize
    super()
    @value = 0.0
    @width_policy = EXPANDING
    @height_policy = FIXED
    @height = 8.0
    # Colors (Tokyo Night)
    @track_color = 0xFF414868
    @fill_color = 0xFF7AA2F7
    @radius = 4.0
  end

  def with_value(v)
    if v < 0.0
      @value = 0.0
    elsif v > 1.0
      @value = 1.0
    else
      @value = v
    end
    self
  end

  def set_value(v)
    if v < 0.0
      v = 0.0
    end
    if v > 1.0
      v = 1.0
    end
    if v != @value
      @value = v
      mark_dirty
      update
    end
  end

  def get_value
    @value
  end

  def fill_color(c)
    @fill_color = c
    self
  end

  def measure(painter)
    Size.new(200.0, 8.0)
  end

  def redraw(painter, completely)
    # Track background
    painter.fill_round_rect(0.0, 0.0, @width, @height, @radius, @track_color)

    # Fill
    fill_w = @width * @value
    if fill_w > 0.0
      painter.fill_round_rect(0.0, 0.0, fill_w, @height, @radius, @fill_color)
    end
  end
end

# Top-level helper
def ProgressBar()
  ProgressBar.new
end
