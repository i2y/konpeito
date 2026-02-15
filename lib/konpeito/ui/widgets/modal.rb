# Modal dialog - overlay with backdrop and centered content
# Port of Castella Modal
#
# Usage:
#   modal = Modal.new(dialog_content)
#   # Place inside a Box with main content:
#   Box(main_content, modal)
#   # Open/close:
#   modal.open_modal
#   modal.close_modal

class Modal < Widget
  def initialize(content)
    super()
    @modal_content = content
    @visible = false
    @content_added = false
    @backdrop_color = 0x80000000
    @dialog_radius = 8.0
    @dialog_w = 320.0
    @dialog_h = 200.0
    @title_text = nil
    @title_font_size = 16.0
    @width_policy = EXPANDING
    @height_policy = EXPANDING
    @z_index_val = 98
  end

  def dialog_size(w, h)
    @dialog_w = w
    @dialog_h = h
    self
  end

  def title(t)
    @title_text = t
    self
  end

  def open_modal
    @visible = true
    mark_dirty
    update
  end

  def close_modal
    @visible = false
    mark_dirty
    update
  end

  def is_open
    @visible
  end

  def measure(painter)
    Size.new(@width, @height)
  end

  def redraw(painter, completely)
    if !@visible
      return
    end

    # Draw semi-transparent backdrop
    painter.fill_rect(0.0, 0.0, @width, @height, @backdrop_color)

    # Calculate dialog position (centered)
    dx = (@width - @dialog_w) / 2.0
    dy = (@height - @dialog_h) / 2.0

    # Resolve colors from theme
    dialog_bg_c = $theme.bg_primary
    dialog_border_c = $theme.border
    title_c = $theme.text_primary
    close_c = $theme.error

    # Draw dialog background
    painter.fill_round_rect(dx, dy, @dialog_w, @dialog_h, @dialog_radius, dialog_bg_c)
    painter.stroke_round_rect(dx, dy, @dialog_w, @dialog_h, @dialog_radius, dialog_border_c, 1.0)

    # Draw title if set
    title_h = 0.0
    if @title_text != nil
      title_h = 40.0
      ascent = painter.get_text_ascent($theme.font_family, @title_font_size)
      painter.draw_text(@title_text, dx + 16.0, dy + 12.0 + ascent, $theme.font_family, @title_font_size, title_c)
      # Close button (X) in top right
      close_x = dx + @dialog_w - 32.0
      painter.draw_text("X", close_x, dy + 12.0 + ascent, $theme.font_family, @title_font_size, close_c)
      # Divider line below title
      painter.draw_line(dx, dy + 40.0, dx + @dialog_w, dy + 40.0, dialog_border_c, 1.0)
    end

    # Draw content inside dialog using save/restore + translate + clip
    content_x = dx + 12.0
    content_y = dy + title_h + 12.0
    content_w = @dialog_w - 24.0
    content_h = @dialog_h - title_h - 24.0

    # Position and size the content widget
    @modal_content.move_xy(@x + content_x, @y + content_y)
    @modal_content.resize_wh(content_w, content_h)

    # Save painter state, translate to content origin, clip, draw, restore
    painter.save
    painter.translate(content_x, content_y)
    painter.clip_rect(0.0, 0.0, content_w, content_h)
    @modal_content.redraw(painter, true)
    painter.restore
  end

  def dispatch(p)
    if !@visible
      return [nil, nil]
    end
    if contain(p)
      # Try dispatching to modal content first
      content_result = @modal_content.dispatch(p)
      target = content_result[0]
      if target != nil
        return content_result
      end
      # Click was on modal but not on content child - return self
      local_p = Point.new(p.x - @x, p.y - @y)
      [self, local_p]
    else
      [nil, nil]
    end
  end

  def mouse_up(ev)
    if !@visible
      return
    end
    # Check if click is on the close button (X)
    if @title_text != nil
      dx = (@width - @dialog_w) / 2.0
      dy = (@height - @dialog_h) / 2.0
      close_x = dx + @dialog_w - 40.0
      close_y = dy
      cx = ev.pos.x
      cy = ev.pos.y
      if cx >= close_x && cx <= dx + @dialog_w && cy >= close_y && cy <= close_y + 40.0
        close_modal
        return
      end
    end
    # Check if click is on the backdrop (outside dialog)
    dx = (@width - @dialog_w) / 2.0
    dy = (@height - @dialog_h) / 2.0
    cx = ev.pos.x
    cy = ev.pos.y
    if cx < dx || cx > dx + @dialog_w || cy < dy || cy > dy + @dialog_h
      close_modal
    end
  end
end

# Top-level helper
def Modal(content)
  Modal.new(content)
end
