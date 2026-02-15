# Container widget - background + border + padding wrapper
# Port of Castella Container

class Container < Layout
  def initialize(child)
    super()
    add(child) if child
    @bg_color = 0
    @border_color_val = 0
    @custom_bg = false
    @custom_border = false
    @radius = 4.0
    @border_width = 1.0
    @pad_top = 12.0
    @pad_right = 12.0
    @pad_bottom = 12.0
    @pad_left = 12.0
  end

  def bg_color(c)
    @bg_color = c
    @custom_bg = true
    self
  end

  def border_color(c)
    @border_color_val = c
    @custom_border = true
    self
  end

  def border_radius(r)
    @radius = r
    self
  end

  def padding(t, r, b, l)
    @pad_top = t
    @pad_right = r
    @pad_bottom = b
    @pad_left = l
    self
  end

  def relocate_children(painter)
    if @children.length > 0
      c = @children[0]
      c.move_xy(@x + @pad_left, @y + @pad_top)
      inner_w = @width - @pad_left - @pad_right
      inner_h = @height - @pad_top - @pad_bottom
      if inner_w < 0.0
        inner_w = 0.0
      end
      if inner_h < 0.0
        inner_h = 0.0
      end
      c.resize_wh(inner_w, inner_h)
    end
  end

  def redraw(painter, completely)
    bg_c = 0
    if @custom_bg
      bg_c = @bg_color
    else
      bg_c = $theme.bg_primary
    end
    if completely || is_dirty || is_subtree_dirty
      brd_c = 0
      if @custom_border
        brd_c = @border_color_val
      else
        brd_c = $theme.border
      end
      painter.fill_round_rect(0.0, 0.0, @width, @height, @radius, bg_c)
      painter.stroke_round_rect(0.0, 0.0, @width, @height, @radius, brd_c, @border_width)
    end
    # Set bg_clear_color so redraw_children uses Container's background for child clearing
    @bg_clear_color = bg_c
    # Propagate to child layouts via global (save/restore for nesting)
    saved_bg = $__bg_clear_color
    $__bg_clear_color = bg_c
    super(painter, completely)
    $__bg_clear_color = saved_bg
  end
end

# Top-level helper
def Container(child)
  Container.new(child)
end
