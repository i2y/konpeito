# rbs_inline: enabled

# Column layout - vertical arrangement of children
# Port of Castella LinearLayout (vertical axis)

class Column < Layout
  def initialize
    super
    @spacing = 0.0
    @is_scrollable = false
    @scroll_offset = 0.0
    @content_height = 0.0
    @pin_bottom = false
    @sb_dragging = false
    @sb_drag_start_y = 0.0
    @sb_drag_start_offset = 0.0
  end

  #: (Float s) -> Column
  def spacing(s)
    @spacing = s
    self
  end

  #: () -> Column
  def scrollable
    @is_scrollable = true
    self
  end

  #: () -> Column
  def pin_to_bottom
    @pin_bottom = true
    self
  end

  #: () -> bool
  def is_scrollable
    @is_scrollable
  end

  #: (bool is_direction_x) -> bool
  def has_scrollbar(is_direction_x)
    if is_direction_x
      false
    else
      @is_scrollable
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
    total_h = 0.0
    max_w = 0.0
    i = 0
    while i < @children.length
      cs = @children[i].measure(painter)
      total_h = total_h + cs.height
      total_h = total_h + @spacing if i > 0
      max_w = cs.width if cs.width > max_w
      i = i + 1
    end
    Size.new(max_w, total_h)
  end

  #: (untyped painter) -> void
  def relocate_children(painter)
    remaining = @height
    expanding_total_flex = 0

    # First pass: measure FIXED/CONTENT children, collect EXPANDING
    i = 0
    while i < @children.length
      c = @children[i]
      if c.get_height_policy != EXPANDING
        # Set width before measure so word-wrapping can calculate line count
        if c.get_width_policy == EXPANDING
          c.resize_wh(@width, c.get_height)
        end
        cs = c.measure(painter)
        c.resize_wh(@width, cs.height)
        remaining = remaining - cs.height
      else
        expanding_total_flex = expanding_total_flex + c.get_flex
      end
      remaining = remaining - @spacing if i > 0
      i = i + 1
    end

    if remaining < 0.0
      remaining = 0.0
    end

    # Second pass: distribute remaining space to EXPANDING children, position all
    cy = @y
    if @is_scrollable
      cy = cy - @scroll_offset
    end
    total_content_h = 0.0
    i = 0
    while i < @children.length
      c = @children[i]
      if c.get_height_policy == EXPANDING
        h = 0.0
        if expanding_total_flex > 0 && remaining > 0.0
          h = remaining * c.get_flex / expanding_total_flex
        end
        c.resize_wh(@width, h)
      else
        # Set width for non-expanding too
        if c.get_width_policy == EXPANDING
          c.resize_wh(@width, c.get_height)
        end
      end
      c.move_xy(@x, cy)
      cy = cy + c.get_height + @spacing
      total_content_h = total_content_h + c.get_height
      total_content_h = total_content_h + @spacing if i > 0
      i = i + 1
    end
    @content_height = total_content_h

    # Auto-scroll to bottom when pinned
    if @pin_bottom && @is_scrollable
      max_scroll = @content_height - @height
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
    viewport_h = @height
    content_h = @content_height
    return if content_h <= viewport_h

    bar_width = 8.0
    thumb_color = 0xC0AAAAAA

    # Thumb
    thumb_h = viewport_h * viewport_h / content_h
    if thumb_h < 20.0
      thumb_h = 20.0
    end
    thumb_y = (@scroll_offset / content_h) * viewport_h
    if thumb_y + thumb_h > viewport_h
      thumb_y = viewport_h - thumb_h
    end
    painter.fill_round_rect(@width - bar_width + 2.0, thumb_y, bar_width - 4.0, thumb_h, 2.0, thumb_color)
  end

  # Intercept clicks on the scrollbar area before dispatching to children
  #: (Point p) -> Array
  def dispatch(p)
    if @is_scrollable && @content_height > @height && contain(p)
      local_x = p.x - @x
      if local_x >= @width - 8.0
        local_p = Point.new(local_x, p.y - @y)
        return [self, local_p]
      end
    end
    super(p)
  end

  #: (MouseEvent ev) -> void
  def mouse_down(ev)
    if @is_scrollable && @content_height > @height
      @sb_dragging = true
      @sb_drag_start_y = ev.pos.y
      @sb_drag_start_offset = @scroll_offset
      # Jump scroll to clicked position
      viewport_h = @height
      content_h = @content_height
      max_scroll = content_h - viewport_h
      @scroll_offset = (ev.pos.y / viewport_h) * max_scroll
      if @scroll_offset < 0.0
        @scroll_offset = 0.0
      end
      if @scroll_offset > max_scroll
        @scroll_offset = max_scroll
      end
      mark_dirty
      update
    end
  end

  #: (MouseEvent ev) -> void
  def mouse_drag(ev)
    if @sb_dragging
      viewport_h = @height
      content_h = @content_height
      if content_h > viewport_h
        max_scroll = content_h - viewport_h
        @scroll_offset = (ev.pos.y / viewport_h) * max_scroll
        if @scroll_offset < 0.0
          @scroll_offset = 0.0
        end
        if @scroll_offset > max_scroll
          @scroll_offset = max_scroll
        end
        mark_dirty
        update
      end
    end
  end

  #: (MouseEvent ev) -> void
  def mouse_up(ev)
    @sb_dragging = false
  end

  #: (WheelEvent ev) -> void
  def mouse_wheel(ev)
    if @is_scrollable
      scroll_speed = 30.0
      @scroll_offset = @scroll_offset - ev.delta_y * scroll_speed
      # Clamp scroll offset
      max_scroll = @content_height - @height
      if max_scroll < 0.0
        max_scroll = 0.0
      end
      if @scroll_offset < 0.0
        @scroll_offset = 0.0
      end
      if @scroll_offset > max_scroll
        @scroll_offset = max_scroll
      end
      # Toggle pin_to_bottom: disable on scroll up, re-enable at bottom
      if ev.delta_y > 0.0
        @pin_bottom = false
      end
      if max_scroll > 0.0 && @scroll_offset >= max_scroll
        @pin_bottom = true
      end
      mark_dirty
      update
    end
  end
end

# Top-level helper
#: (*untyped children) -> Column
def Column(*children)
  col = Column.new
  i = 0
  while i < children.length
    col.add(children[i])
    i = i + 1
  end
  col
end
