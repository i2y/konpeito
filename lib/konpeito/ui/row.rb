# rbs_inline: enabled

# Row layout - horizontal arrangement of children
# Port of Castella LinearLayout (horizontal axis)

class Row < Layout
  def initialize
    super
    @spacing = 0.0
    @is_scrollable = false
    @scroll_offset = 0.0
    @content_width = 0.0
    @pin_right = false
  end

  #: (Float s) -> Row
  def spacing(s)
    @spacing = s
    self
  end

  #: () -> Row
  def scrollable
    @is_scrollable = true
    self
  end

  #: () -> Row
  def pin_to_end
    @pin_right = true
    self
  end

  #: () -> bool
  def is_scrollable
    @is_scrollable
  end

  #: (bool is_direction_x) -> bool
  def has_scrollbar(is_direction_x)
    if is_direction_x
      @is_scrollable
    else
      false
    end
  end

  #: () -> Float
  def get_scroll_offset
    @scroll_offset
  end

  #: (Float v) -> void
  def set_scroll_offset(v)
    @scroll_offset = v
    mark_dirty
    update
  end

  #: (untyped painter) -> Size
  def measure(painter)
    total_w = 0.0
    max_h = 0.0
    i = 0
    while i < @children.length
      cs = @children[i].measure(painter)
      total_w = total_w + cs.width
      total_w = total_w + @spacing if i > 0
      max_h = cs.height if cs.height > max_h
      i = i + 1
    end
    Size.new(total_w, max_h)
  end

  #: (untyped painter) -> void
  def relocate_children(painter)
    remaining = @width
    expanding_total_flex = 0

    # First pass: measure FIXED/CONTENT children, collect EXPANDING
    i = 0
    while i < @children.length
      c = @children[i]
      if c.get_width_policy != EXPANDING
        # Set height before measure so height-dependent layouts work
        if c.get_height_policy == EXPANDING
          c.resize_wh(c.get_width, @height)
        end
        cs = c.measure(painter)
        c.resize_wh(cs.width, @height)
        remaining = remaining - cs.width
      else
        expanding_total_flex = expanding_total_flex + c.get_flex
      end
      remaining = remaining - @spacing if i > 0
      i = i + 1
    end

    if remaining < 0.0
      remaining = 0.0
    end

    # Second pass: distribute remaining space, position all
    cx = @x
    if @is_scrollable
      cx = cx - @scroll_offset
    end
    total_content_w = 0.0
    i = 0
    while i < @children.length
      c = @children[i]
      if c.get_width_policy == EXPANDING
        w = 0.0
        if expanding_total_flex > 0 && remaining > 0.0
          w = remaining * c.get_flex / expanding_total_flex
        end
        c.resize_wh(w, @height)
      else
        if c.get_height_policy == EXPANDING
          c.resize_wh(c.get_width, @height)
        end
      end
      c.move_xy(cx, @y)
      cx = cx + c.get_width + @spacing
      total_content_w = total_content_w + c.get_width
      total_content_w = total_content_w + @spacing if i > 0
      i = i + 1
    end
    @content_width = total_content_w

    # Auto-scroll to end when pinned
    if @pin_right && @is_scrollable
      max_scroll = @content_width - @width
      if max_scroll > 0.0
        @scroll_offset = max_scroll
      end
    end
  end

  #: (untyped painter, bool completely) -> void
  def redraw(painter, completely)
    relocate_children(painter)
    redraw_children(painter, completely)
    draw_scrollbar(painter) if @is_scrollable
  end

  #: (untyped painter) -> void
  def draw_scrollbar(painter)
    viewport_w = @width
    content_w = @content_width
    return if content_w <= viewport_w

    bar_height = 8.0
    thumb_color = 0xC0AAAAAA

    # Thumb
    thumb_w = viewport_w * viewport_w / content_w
    if thumb_w < 20.0
      thumb_w = 20.0
    end
    thumb_x = (@scroll_offset / content_w) * viewport_w
    if thumb_x + thumb_w > viewport_w
      thumb_x = viewport_w - thumb_w
    end
    painter.fill_round_rect(thumb_x, @height - bar_height + 2.0, thumb_w, bar_height - 4.0, 2.0, thumb_color)
  end

  #: (WheelEvent ev) -> void
  def mouse_wheel(ev)
    if @is_scrollable
      scroll_speed = 30.0
      @scroll_offset = @scroll_offset - ev.delta_y * scroll_speed
      # Clamp scroll offset
      max_scroll = @content_width - @width
      if max_scroll < 0.0
        max_scroll = 0.0
      end
      if @scroll_offset < 0.0
        @scroll_offset = 0.0
      end
      if @scroll_offset > max_scroll
        @scroll_offset = max_scroll
      end
      # Toggle pin_to_end: disable on scroll left, re-enable at end
      if ev.delta_y > 0.0
        @pin_right = false
      end
      if max_scroll > 0.0 && @scroll_offset >= max_scroll
        @pin_right = true
      end
      mark_dirty
      update
    end
  end
end

# Top-level helper
#: (*untyped children) -> Row
def Row(*children)
  row = Row.new
  i = 0
  while i < children.length
    row.add(children[i])
    i = i + 1
  end
  row
end
