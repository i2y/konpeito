# Switch widget - ON/OFF toggle
# Port of Castella Switch

class Switch < Widget
  def initialize
    super()
    @on = false
    @change_handler = nil
    # Colors (Tokyo Night)
    @on_color = 0xFF7AA2F7
    @off_color = 0xFF414868
    @knob_color = 0xFFFFFFFF
    @hovered = false
  end

  def with_on(v)
    @on = v
    self
  end

  def on_change(&block)
    @change_handler = block
    self
  end

  def is_on
    @on
  end

  def measure(painter)
    Size.new(44.0, 24.0)
  end

  def redraw(painter, completely)
    w = 44.0
    h = 24.0
    r = h / 2.0

    # Track
    track_color = @on ? @on_color : @off_color
    painter.fill_round_rect(0.0, 0.0, w, h, r, track_color)

    # Knob
    knob_r = 9.0
    knob_y = h / 2.0
    knob_x = 0.0
    if @on
      knob_x = w - r
    else
      knob_x = r
    end
    painter.fill_circle(knob_x, knob_y, knob_r, @knob_color)
  end

  def mouse_up(ev)
    if @on
      @on = false
    else
      @on = true
    end
    @change_handler.call(@on) if @change_handler
    mark_dirty
    update
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
def Switch()
  Switch.new
end
