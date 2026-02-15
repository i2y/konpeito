# Tabs widget - tabbed container with header buttons
# Port of Castella Tabs

class Tabs < Layout
  def initialize(labels, contents)
    super()
    @tab_labels = labels
    @tab_contents = contents
    @selected = 0
    @tab_height = 36.0
    @font_size_val = 13.0
    @width_policy = EXPANDING
    @height_policy = EXPANDING
    @tab_widths = []
    # Add initial content
    if @tab_contents.length > 0
      add(@tab_contents[0])
    end
  end

  def select_tab(index)
    if index >= 0
      if index < @tab_contents.length
        if index != @selected
          @selected = index
          clear_children
          add(@tab_contents[@selected])
          mark_dirty
          mark_layout_dirty
          update
        end
      end
    end
    self
  end

  def relocate_children(painter)
    # Content area starts below tab header
    content_y = @y + @tab_height
    content_h = @height - @tab_height
    if content_h < 0.0
      content_h = 0.0
    end
    if @children.length > 0
      c = @children[0]
      c.move_xy(@x, content_y)
      c.resize_wh(@width, content_h)
    end
  end

  def measure(painter)
    Size.new(@width, @height)
  end

  def redraw(painter, completely)
    # 1) Layout + draw children first (redraw_children may clear the entire area)
    relocate_children(painter)
    redraw_children(painter, completely)

    # 2) Draw tab bar ON TOP so it is not overwritten by background clear
    draw_tab_bar(painter)
  end

  def draw_tab_bar(painter)
    tab_bg = $theme.bg_canvas
    tab_active_bg = $theme.bg_primary
    tab_text_c = $theme.text_secondary
    tab_active_text = $theme.text_primary
    tab_border_c = $theme.border
    tab_indicator_c = $theme.accent

    # Tab bar background
    painter.fill_rect(0.0, 0.0, @width, @tab_height, tab_bg)

    # Calculate tab widths based on labels
    @tab_widths = []
    pad_h = 16.0
    i = 0
    while i < @tab_labels.length
      tw = painter.measure_text_width(@tab_labels[i], $theme.font_family, @font_size_val)
      @tab_widths.push(tw + pad_h * 2.0)
      i = i + 1
    end

    # Draw each tab header
    ascent = painter.get_text_ascent($theme.font_family, @font_size_val)
    draw_tab_headers(painter, ascent, tab_active_bg, tab_active_text, tab_text_c, tab_indicator_c)

    # Border line below tabs
    painter.draw_line(0.0, @tab_height, @width, @tab_height, tab_border_c, 1.0)
  end

  def draw_tab_headers(painter, ascent, active_bg, active_tc, inactive_tc, indicator_c)
    tab_x = 0.0
    i = 0
    while i < @tab_labels.length
      tw = @tab_widths[i]
      draw_one_tab(painter, i, tab_x, tw, ascent, active_bg, active_tc, inactive_tc, indicator_c)
      tab_x = tab_x + tw
      i = i + 1
    end
  end

  def draw_one_tab(painter, i, tab_x, tw, ascent, active_bg, active_tc, inactive_tc, indicator_c)
    is_selected = (i == @selected)

    # Tab background
    if is_selected
      painter.fill_rect(tab_x, 0.0, tw, @tab_height, active_bg)
    end

    # Tab label
    if is_selected
      tc = active_tc
    else
      tc = inactive_tc
    end
    label_w = painter.measure_text_width(@tab_labels[i], $theme.font_family, @font_size_val)
    text_x = tab_x + (tw - label_w) / 2.0
    text_y = (@tab_height - painter.measure_text_height($theme.font_family, @font_size_val)) / 2.0 + ascent
    painter.draw_text(@tab_labels[i], text_x, text_y, $theme.font_family, @font_size_val, tc)

    # Active indicator line at bottom
    if is_selected
      painter.fill_rect(tab_x, @tab_height - 2.0, tw, 2.0, indicator_c)
    end
  end

  def mouse_down(ev)
    # Check if click is in the tab header area
    click_y = ev.pos.y
    if click_y < @tab_height
      find_clicked_tab(ev.pos.x)
    end
  end

  def find_clicked_tab(click_x)
    tab_x = 0.0
    i = 0
    while i < @tab_widths.length
      tw = @tab_widths[i]
      if click_x >= tab_x
        if click_x < tab_x + tw
          select_tab(i)
          return
        end
      end
      tab_x = tab_x + tw
      i = i + 1
    end
  end
end

# Top-level helper
def Tabs(labels, contents)
  Tabs.new(labels, contents)
end
