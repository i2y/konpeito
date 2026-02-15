# Slider widget - draggable range input
# Port of Castella Slider

class Slider < Widget
  def initialize(min_val, max_val)
    super()
    @min_val = min_val
    @max_val = max_val
    @value = min_val
    @dragging = false
    @change_handler = nil
    @width_policy = EXPANDING
    @height_policy = FIXED
    @height = 30.0
    # Colors (Tokyo Night)
    @track_color = 0xFF414868
    @fill_color = 0xFF7AA2F7
    @thumb_color = 0xFFC0CAF5
    @thumb_hover = 0xFFFFFFFF
    @hovered = false
  end

  def with_value(v)
    if v < @min_val
      @value = @min_val
    elsif v > @max_val
      @value = @max_val
    else
      @value = v
    end
    self
  end

  def on_change(&block)
    @change_handler = block
    self
  end

  def get_value
    @value
  end

  def measure(painter)
    Size.new(200.0, 30.0)
  end

  def redraw(painter, completely)
    thumb_r = 8.0
    track_h = 4.0
    track_y = (@height - track_h) / 2.0
    track_x = thumb_r
    track_w = @width - thumb_r * 2.0
    if track_w < 0.0
      track_w = 0.0
    end

    # Track background
    painter.fill_round_rect(track_x, track_y, track_w, track_h, 2.0, @track_color)

    # Fill (progress)
    ratio = 0.0
    range = @max_val - @min_val
    if range > 0.0
      ratio = (@value - @min_val) / range
    end
    fill_w = track_w * ratio
    if fill_w > 0.0
      painter.fill_round_rect(track_x, track_y, fill_w, track_h, 2.0, @fill_color)
    end

    # Thumb circle
    thumb_x = track_x + fill_w
    thumb_y = @height / 2.0
    tc = @hovered ? @thumb_hover : @thumb_color
    painter.fill_circle(thumb_x, thumb_y, thumb_r, tc)
  end

  def mouse_down(ev)
    @dragging = true
    update_from_pos(ev.pos.x)
  end

  def mouse_drag(ev)
    if @dragging
      update_from_pos(ev.pos.x)
    end
  end

  def mouse_up(ev)
    @dragging = false
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

  def update_from_pos(x)
    thumb_r = 8.0
    track_x = thumb_r
    track_w = @width - thumb_r * 2.0
    if track_w <= 0.0
      return
    end
    ratio = (x - track_x) / track_w
    if ratio < 0.0
      ratio = 0.0
    end
    if ratio > 1.0
      ratio = 1.0
    end
    range = @max_val - @min_val
    new_val = @min_val + ratio * range
    if new_val != @value
      @value = new_val
      @change_handler.call(@value) if @change_handler
      mark_dirty
      update
    end
  end
end

# Top-level helper
def Slider(min_val, max_val)
  Slider.new(min_val, max_val)
end
