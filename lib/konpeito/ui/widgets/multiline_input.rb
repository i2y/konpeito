# MultilineInput widget - multi-line editable text area with IME, selection, clipboard
# Port of Castella MultilineInput
#
# State is held in MultilineInputState (defined in core.rb) which persists across
# Component rebuilds. The widget delegates all text/cursor/selection/IME
# operations to MultilineInputState and handles rendering + event dispatch.
#
# JWM Key ordinals:
#   ENTER=11, BACKSPACE=12, ESCAPE=17, END=21, HOME=22, LEFT=23, UP=24, RIGHT=25, DOWN=26, DELETE=75
#   A=43, C=45, V=64, X=66

SCROLLBAR_WIDTH = 10.0

class MultilineInput < Widget
  def initialize(state)
    super()
    @state = state
    @focused_flag = false
    @font_size_val = 14.0
    @line_spacing = 4.0
    @wrap = true
    @bg_color = 0
    @text_color = 0
    @border_color = 0
    @focus_border = 0
    @use_theme = true
    @radius = 4.0
    @focusable = true
    @width_policy = EXPANDING
    @height_policy = FIXED
    @height = 200.0
    @pad_top = 8.0
    @pad_right = 8.0
    @pad_bottom = 8.0
    @pad_left = 8.0
    @border_width = 1.0
    # Scroll state (view-level, not in MultilineInputState for content_height dependency)
    @content_height = 0.0
    # Scrollbar drag state
    @scroll_box_y = nil  # [x, y, w, h] or nil
    @under_dragging_y = false
    @last_drag_y = 0.0
    # Display lines cache (for click handling)
    @last_display_lines = nil
    # Character position cache
    @char_positions_cache = nil
    # on_change callback
    @on_change_cb = nil
  end

  # --- API / method chaining ---

  def font_size(s)
    @font_size_val = s
    self
  end

  def wrap_text(flag)
    @wrap = flag
    self
  end

  def line_spacing(s)
    @line_spacing = s
    self
  end

  def on_change(&block)
    @on_change_cb = block
    self
  end

  def get_text
    @state.value
  end

  def set_text(t)
    @state.set_text(t)
    mark_dirty
    update
  end

  # --- Measure ---

  def measure(painter)
    Size.new(@width, @height)
  end

  # --- Word wrapping ---

  def get_wrapped_lines(painter, line_width)
    display_lines = []  # Each entry: [logical_row, display_text, start_col]
    lines = @state.get_lines

    i = 0
    while i < lines.length
      line = lines[i]
      # Insert preedit at cursor position
      if @state.has_preedit && i == @state.get_row
        line = build_preedit_line(line)
      end

      if !@wrap || line_width <= 0
        display_lines << [i, line, 0]
      elsif line.length == 0
        display_lines << [i, "", 0]
      else
        wrap_single_line(painter, line_width, i, line, display_lines)
      end

      i = i + 1
    end

    display_lines
  end

  def build_preedit_line(line)
    col = @state.get_col
    before = ""
    if col > 0
      before = line[0, col]
    end
    after_len = line.length - col
    after = ""
    if after_len > 0
      after = line[col, after_len]
    end
    before + @state.get_preedit_text + after
  end

  def wrap_single_line(painter, line_width, logical_row, line, display_lines)
    col_offset = 0
    remaining = line

    while remaining.length > 0
      text_w = painter.measure_text_width(remaining, $theme.font_family, @font_size_val)
      if text_w <= line_width
        display_lines << [logical_row, remaining, col_offset]
        remaining = ""
      else
        break_idx = find_break_index(painter, remaining, line_width)
        break_idx = try_word_boundary_break(remaining, break_idx)

        display_lines << [logical_row, remaining[0, break_idx], col_offset]
        col_offset = col_offset + break_idx
        remaining = remaining[break_idx, remaining.length - break_idx]
      end
    end
  end

  def find_break_index(painter, text, line_width)
    break_idx = text.length
    found = false
    j = 1
    while j <= text.length && !found
      sub_w = painter.measure_text_width(text[0, j], $theme.font_family, @font_size_val)
      if sub_w > line_width
        break_idx = j - 1
        if break_idx < 1
          break_idx = 1
        end
        found = true
      end
      j = j + 1
    end
    break_idx
  end

  def try_word_boundary_break(text, break_idx)
    result = break_idx
    space_idx = -1
    k = break_idx
    while k >= 0 && space_idx == -1
      if text[k] == " "
        space_idx = k
      end
      k = k - 1
    end
    if space_idx > 0
      result = space_idx + 1
    end
    result
  end

  def find_cursor_display_pos(painter, display_lines)
    cursor_row = @state.get_row
    cursor_col = @state.get_col
    display_cursor_col = cursor_col
    if @state.has_preedit
      display_cursor_col = cursor_col + @state.get_preedit_cursor
    end

    result_idx = 0
    result_x = 0.0
    found = false

    # Forward search for matching display line
    i = 0
    while i < display_lines.length && !found
      dl = display_lines[i]
      logical_row = dl[0]
      text = dl[1]
      start_col = dl[2]
      if logical_row == cursor_row
        end_col = start_col + text.length
        if start_col <= display_cursor_col && display_cursor_col <= end_col
          text_before = ""
          offset = display_cursor_col - start_col
          if offset > 0
            text_before = text[0, offset]
          end
          result_idx = i
          result_x = painter.measure_text_width(text_before, $theme.font_family, @font_size_val)
          found = true
        end
      end
      i = i + 1
    end

    # Fallback: last line of cursor row
    if !found
      i = display_lines.length - 1
      while i >= 0 && !found
        dl = display_lines[i]
        if dl[0] == cursor_row
          result_idx = i
          result_x = painter.measure_text_width(dl[1], $theme.font_family, @font_size_val)
          found = true
        end
        i = i - 1
      end
    end

    [result_idx, result_x]
  end

  # --- Rendering ---

  def redraw(painter, completely)
    bg_c = @use_theme ? $theme.bg_primary : @bg_color
    tc = @use_theme ? $theme.text_primary : @text_color
    brd_c = @use_theme ? $theme.border : @border_color
    fbc = @use_theme ? $theme.border_focus : @focus_border
    sel_color = $theme.bg_selected

    bc = @focused_flag ? fbc : brd_c
    painter.fill_round_rect(0.0, 0.0, @width, @height, @radius, bg_c)
    painter.stroke_round_rect(0.0, 0.0, @width, @height, @radius, bc, 1.0)

    ascent = painter.get_text_ascent($theme.font_family, @font_size_val)
    font_size = @font_size_val
    padding = @pad_left
    border_width = @border_width

    # Calculate line width with scrollbar space reserved
    scrollbar_width = SCROLLBAR_WIDTH
    line_width = @width - (padding + border_width) * 2.0 - scrollbar_width
    display_lines = get_wrapped_lines(painter, line_width)

    # Calculate content height
    num_lines = display_lines.length
    spacing_total = compute_spacing_total(num_lines)
    @content_height = font_size * num_lines + spacing_total + padding * 2.0

    visible_height = @height - border_width * 2.0
    needs_scrollbar = @content_height > @height

    if !needs_scrollbar
      line_width = @width - (padding + border_width) * 2.0
      display_lines = get_wrapped_lines(painter, line_width)
      num_lines = display_lines.length
      spacing_total = compute_spacing_total(num_lines)
      @content_height = font_size * num_lines + spacing_total + padding * 2.0
      @scroll_box_y = nil
      scrollbar_width = 0.0
    end

    @last_display_lines = display_lines

    # Build character position cache
    build_char_positions_cache(painter, display_lines, font_size)

    # Auto-scroll to keep cursor visible when editing
    scroll_y = @state.get_scroll_y
    if @focused_flag && !@state.is_manual_scroll
      scroll_y = auto_scroll_to_cursor(painter, display_lines, font_size, padding, visible_height, scroll_y)
      @state.set_scroll_y(scroll_y)
    end

    # Clamp scroll
    scroll_y = clamp_scroll(visible_height, scroll_y)
    @state.set_scroll_y(scroll_y)

    # Clip content area
    content_width = @width - border_width * 2.0 - scrollbar_width
    if content_width < 0.0
      content_width = 0.0
    end
    painter.save
    painter.clip_rect(border_width, border_width, content_width, visible_height)
    painter.translate(0.0, 0.0 - scroll_y)

    # Draw selection highlight
    if @state.has_selection
      draw_selection_highlight(painter, display_lines, sel_color)
    end

    # Draw text lines
    draw_text_lines(painter, display_lines, padding, ascent, font_size, tc)

    # Draw preedit underline
    if @state.has_preedit && @focused_flag
      draw_preedit_underline(painter, display_lines, padding, ascent, font_size, tc)
    end

    # Draw cursor
    if @focused_flag
      draw_cursor(painter, display_lines, padding, font_size, tc)
    end

    painter.restore

    # Draw scrollbar
    if needs_scrollbar
      draw_scrollbar(painter, border_width, scrollbar_width, visible_height)
    end
  end

  def compute_spacing_total(num_lines)
    result = 0.0
    if num_lines > 1
      result = @line_spacing * (num_lines - 1)
    end
    result
  end

  def build_char_positions_cache(painter, display_lines, font_size)
    @char_positions_cache = []
    i = 0
    while i < display_lines.length
      dl = display_lines[i]
      text = dl[1]
      positions = [0.0]
      cumulative = 0.0
      j = 0
      while j < text.length
        ch_w = painter.measure_text_width(text[j], $theme.font_family, font_size)
        cumulative = cumulative + ch_w
        positions << cumulative
        j = j + 1
      end
      @char_positions_cache << positions
      i = i + 1
    end
  end

  def auto_scroll_to_cursor(painter, display_lines, font_size, padding, visible_height, scroll_y)
    cursor_info = find_cursor_display_pos(painter, display_lines)
    display_idx = cursor_info[0]
    cursor_top = padding + display_idx * (font_size + @line_spacing)
    cursor_bottom = cursor_top + font_size
    if cursor_top - scroll_y < 0.0
      scroll_y = cursor_top
      if scroll_y < 0.0
        scroll_y = 0.0
      end
    elsif cursor_bottom - scroll_y > visible_height
      scroll_y = cursor_bottom - visible_height
    end
    scroll_y
  end

  def clamp_scroll(visible_height, scroll_y)
    max_scroll = @content_height - @height
    if max_scroll < 0.0
      max_scroll = 0.0
    end
    if scroll_y < 0.0
      scroll_y = 0.0
    end
    if scroll_y > max_scroll
      scroll_y = max_scroll
    end
    scroll_y
  end

  def draw_text_lines(painter, display_lines, padding, ascent, font_size, tc)
    i = 0
    while i < display_lines.length
      dl = display_lines[i]
      text = dl[1]
      y = padding + ascent + i * (font_size + @line_spacing)
      if text.length > 0
        painter.draw_text(text, padding, y, $theme.font_family, font_size, tc)
      end
      i = i + 1
    end
  end

  def draw_preedit_underline(painter, display_lines, padding, ascent, font_size, tc)
    cursor_info = find_cursor_display_pos(painter, display_lines)
    display_idx = cursor_info[0]
    dl = display_lines[display_idx]
    text = dl[1]
    start_col = dl[2]
    preedit_start_offset = @state.get_col - start_col
    if preedit_start_offset < 0
      preedit_start_offset = 0
    end
    text_before = ""
    if preedit_start_offset > 0
      text_before = text[0, preedit_start_offset]
    end
    preedit_start_x = padding + painter.measure_text_width(text_before, $theme.font_family, font_size)
    preedit_w = painter.measure_text_width(@state.get_preedit_text, $theme.font_family, font_size)
    underline_y = padding + ascent + display_idx * (font_size + @line_spacing) + 2.0
    painter.fill_rect(preedit_start_x, underline_y, preedit_w, 2.0, tc)
  end

  def draw_cursor(painter, display_lines, padding, font_size, tc)
    cursor_info = find_cursor_display_pos(painter, display_lines)
    display_idx = cursor_info[0]
    x_offset = cursor_info[1]
    cursor_x = padding + x_offset
    cursor_y = padding + display_idx * (font_size + @line_spacing)
    painter.draw_line(cursor_x, cursor_y, cursor_x, cursor_y + font_size, tc, 1.0)

    # Notify IME of cursor position
    scroll_y = @state.get_scroll_y
    abs_cursor_x = @x + cursor_x
    abs_cursor_y = @y + cursor_y - scroll_y
    app = App.current
    if app != nil
      app.set_ime_cursor_rect(abs_cursor_x.to_i, abs_cursor_y.to_i, 1, font_size.to_i)
    end
  end

  def draw_scrollbar(painter, border_width, scrollbar_width, visible_height)
    scrollbar_x = @width - scrollbar_width - border_width
    # Track
    scrollbar_bg = $theme.scrollbar_bg
    painter.fill_rect(scrollbar_x, border_width, scrollbar_width, visible_height, scrollbar_bg)
    # Thumb
    scroll_y = @state.get_scroll_y
    if @content_height > 0.0
      thumb_height = (visible_height / @content_height) * visible_height
      if thumb_height < 20.0
        thumb_height = 20.0
      end
      scroll_range = @content_height - @height
      thumb_y = 0.0
      if scroll_range > 0.0
        thumb_y = (scroll_y / scroll_range) * (visible_height - thumb_height)
      end
      scrollbar_fg = $theme.scrollbar_fg
      painter.fill_rect(scrollbar_x, border_width + thumb_y, scrollbar_width, thumb_height, scrollbar_fg)
      @scroll_box_y = [scrollbar_x, border_width + thumb_y, scrollbar_width, thumb_height]
    end
  end

  def draw_selection_highlight(painter, display_lines, sel_color)
    if !@state.has_selection
      return
    end
    range = @state.get_selection_range
    sr = range[0]
    sc = range[1]
    er = range[2]
    ec = range[3]
    font_size = @font_size_val
    padding = @pad_left

    i = 0
    while i < display_lines.length
      dl = display_lines[i]
      logical_row = dl[0]
      text = dl[1]
      line_start_col = dl[2]

      # Only process lines within the selection range
      if logical_row >= sr && logical_row <= er
        draw_selection_for_line(painter, i, logical_row, text, line_start_col, sr, sc, er, ec, font_size, padding, sel_color)
      end

      i = i + 1
    end
  end

  def draw_selection_for_line(painter, display_idx, logical_row, text, line_start_col, sr, sc, er, ec, font_size, padding, sel_color)
    line_end_col = line_start_col + text.length

    # Determine selection start column for this display line
    sel_start_in_line = 0
    if logical_row == sr
      sel_start_col = sc
      if sel_start_col < line_start_col
        sel_start_col = line_start_col
      end
      sel_start_in_line = sel_start_col - line_start_col
    end

    # Determine selection end column for this display line
    sel_end_in_line = text.length
    if logical_row == er
      sel_end_col = ec
      if sel_end_col > line_end_col
        sel_end_col = line_end_col
      end
      sel_end_in_line = sel_end_col - line_start_col
    end

    if sel_start_in_line < sel_end_in_line
      y = padding + display_idx * (font_size + @line_spacing)
      x_start = padding
      if sel_start_in_line > 0
        x_start = padding + painter.measure_text_width(text[0, sel_start_in_line], $theme.font_family, font_size)
      end
      x_end = padding + painter.measure_text_width(text[0, sel_end_in_line], $theme.font_family, font_size)
      painter.fill_rect(x_start, y, x_end - x_start, font_size, sel_color)
    end
  end

  # --- Scrollable ---

  def is_scrollable
    true
  end

  def dispatch_to_scrollable(p, is_direction_x)
    result_widget = nil
    result_point = nil
    if !is_direction_x && contain(p)
      result_widget = self
      result_point = p
    end
    [result_widget, result_point]
  end

  # --- Focus ---

  def focused
    @focused_flag = true
    app = App.current
    if app != nil
      app.enable_text_input
    end
    mark_dirty
    update
  end

  def restore_focus
    @focused_flag = true
    app = App.current
    if app != nil
      app.enable_text_input
    end
    mark_dirty
  end

  def unfocused
    @focused_flag = false
    @state.finish_editing
    app = App.current
    if app != nil
      app.disable_text_input
    end
    mark_dirty
    update
  end

  # --- Mouse events ---

  def mouse_down(ev)
    # Check if click is on scrollbar thumb
    if @scroll_box_y != nil
      if click_on_scrollbar_thumb(ev)
        @under_dragging_y = true
        @last_drag_y = ev.pos.y
        return
      end
    end

    # Click in text area
    @focused_flag = true
    if @state.has_preedit
      @state.clear_preedit
    end

    pos = pos_from_point(ev.pos)
    @state.start_selection(pos[0], pos[1])
    @state.set_manual_scroll(false)

    mark_dirty
    update
  end

  def click_on_scrollbar_thumb(ev)
    sx = @scroll_box_y[0]
    sy = @scroll_box_y[1]
    sw = @scroll_box_y[2]
    sh = @scroll_box_y[3]
    ev.pos.x >= sx && ev.pos.x < sx + sw && ev.pos.y >= sy && ev.pos.y < sy + sh
  end

  def mouse_up(ev)
    @state.end_selection
    @under_dragging_y = false
  end

  def mouse_drag(ev)
    if @under_dragging_y
      handle_scrollbar_drag(ev)
      return
    end

    if @state.is_selecting
      pos = pos_from_point(ev.pos)
      @state.update_selection(pos[0], pos[1])
      mark_dirty
      update
    end
  end

  def handle_scrollbar_drag(ev)
    delta_y = ev.pos.y - @last_drag_y
    @last_drag_y = ev.pos.y
    if delta_y == 0.0
      return
    end

    visible_height = @height - @border_width * 2.0
    scroll_range = @content_height - @height
    if scroll_range <= 0.0
      return
    end

    thumb_height = (visible_height / @content_height) * visible_height
    if thumb_height < 20.0
      thumb_height = 20.0
    end
    track_range = visible_height - thumb_height
    if track_range <= 0.0
      return
    end

    scroll_y = @state.get_scroll_y
    scroll_delta = (delta_y / track_range) * scroll_range
    new_scroll = scroll_y + scroll_delta
    if new_scroll < 0.0
      new_scroll = 0.0
    end
    if new_scroll > scroll_range
      new_scroll = scroll_range
    end
    if new_scroll != scroll_y
      @state.set_scroll_y(new_scroll)
      @state.set_manual_scroll(true)
      mark_dirty
      update
    end
  end

  def mouse_wheel(ev)
    delta = ev.delta_y
    if delta == 0.0
      return
    end
    max_scroll = @content_height - @height
    if max_scroll <= 0.0
      return
    end
    scroll_y = @state.get_scroll_y
    # Scroll by wheel delta (negative = scroll down on macOS)
    new_scroll = scroll_y - delta * 3.0
    if new_scroll < 0.0
      new_scroll = 0.0
    end
    if new_scroll > max_scroll
      new_scroll = max_scroll
    end
    if new_scroll != scroll_y
      @state.set_scroll_y(new_scroll)
      @state.set_manual_scroll(true)
      mark_dirty
      update
    end
  end

  def pos_from_point(point)
    font_size = @font_size_val
    padding = @pad_left
    border_width = @border_width
    scroll_y = @state.get_scroll_y

    click_y = point.y + scroll_y - border_width
    display_line_idx = 0
    if click_y >= padding
      display_line_idx = ((click_y - padding) / (font_size + @line_spacing)).to_i
    end

    display_lines = @last_display_lines
    if display_lines == nil || display_lines.length == 0
      return [0, 0]
    end

    if display_line_idx < 0
      display_line_idx = 0
    end
    if display_line_idx >= display_lines.length
      display_line_idx = display_lines.length - 1
    end

    dl = display_lines[display_line_idx]
    logical_row = dl[0]
    start_col = dl[2]

    click_x = point.x - padding
    col = start_col
    if click_x > 0.0
      col = find_col_from_click_x(display_line_idx, start_col, click_x)
    end

    lines = @state.get_lines
    line_len = lines[logical_row].length
    if col > line_len
      col = line_len
    end
    [logical_row, col]
  end

  def find_col_from_click_x(display_line_idx, start_col, click_x)
    col = start_col
    if @char_positions_cache != nil && display_line_idx < @char_positions_cache.length
      positions = @char_positions_cache[display_line_idx]
      found = false
      k = 0
      while k < positions.length && !found
        if positions[k] > click_x
          if k > 0
            prev_pos = positions[k - 1]
            curr_pos = positions[k]
            if (click_x - prev_pos) < (curr_pos - click_x)
              col = start_col + k - 1
            else
              col = start_col + k
            end
          else
            col = start_col + k
          end
          found = true
        else
          col = start_col + k
        end
        k = k + 1
      end
    end
    col
  end

  # --- IME ---

  def ime_preedit(text, sel_start, sel_end)
    if text != nil && text.length > 0
      @state.set_preedit(text, sel_start)
    else
      @state.clear_preedit
    end
    mark_dirty
    update
  end

  # --- Text input ---

  def input_char(text)
    # Clear preedit when committed
    if @state.has_preedit
      @state.clear_preedit
    end
    # Delete selection if any
    if @state.has_selection
      @state.delete_selection
    end
    # Insert text at cursor
    @state.insert_char(text)
    @on_change_cb.call(@state.value) if @on_change_cb
    mark_dirty
    update
  end

  # --- Key input ---

  def input_key(key_code, modifiers)
    # During IME preedit, let IME handle key events
    if @state.has_preedit
      handle_preedit_key(key_code)
      return
    end

    @state.set_manual_scroll(false)
    # Cmd (bit 3 = MAC_COMMAND) or Ctrl (bit 1) for Linux/Windows
    is_cmd = (modifiers & 8) != 0 || (modifiers & 2) != 0

    if is_cmd
      handle_cmd_key(key_code)
      return
    end

    # Clear selection on navigation keys
    if key_code == 23 || key_code == 25 || key_code == 24 || key_code == 26
      @state.clear_selection
    end

    # Delete selection on content-modifying keys
    if (key_code == 12 || key_code == 75) && @state.has_selection
      @state.delete_selection
      @on_change_cb.call(@state.value) if @on_change_cb
      mark_dirty
      update
      return
    end

    handle_navigation_key(key_code)
  end

  def handle_preedit_key(key_code)
    if @state.get_preedit_text.length == 1
      if key_code == 12 || key_code == 17
        @state.clear_preedit
        mark_dirty
        update
      end
    end
  end

  def handle_cmd_key(key_code)
    # Cmd+C (Copy) - C ordinal = 45
    if key_code == 45
      handle_copy
    # Cmd+X (Cut) - X ordinal = 66
    elsif key_code == 66
      handle_cut
    # Cmd+V (Paste) - V ordinal = 64
    elsif key_code == 64
      handle_paste
    # Cmd+A (Select All) - A ordinal = 43
    elsif key_code == 43
      @state.select_all
      mark_dirty
      update
    end
  end

  def handle_navigation_key(key_code)
    # Backspace (12)
    if key_code == 12
      if @state.delete_prev
        @on_change_cb.call(@state.value) if @on_change_cb
        mark_dirty
        update
      end
    # Delete (75)
    elsif key_code == 75
      if @state.delete_next
        @on_change_cb.call(@state.value) if @on_change_cb
        mark_dirty
        update
      end
    # Left (23)
    elsif key_code == 23
      @state.move_left
      mark_dirty
      update
    # Right (25)
    elsif key_code == 25
      @state.move_right
      mark_dirty
      update
    # Up (24)
    elsif key_code == 24
      @state.move_up
      mark_dirty
      update
    # Down (26)
    elsif key_code == 26
      @state.move_down
      mark_dirty
      update
    # Enter (11)
    elsif key_code == 11
      handle_enter
    # Home (22)
    elsif key_code == 22
      if @state.move_home
        mark_dirty
        update
      end
    # End (21)
    elsif key_code == 21
      if @state.move_end
        mark_dirty
        update
      end
    end
  end

  def handle_enter
    if @state.has_selection
      @state.delete_selection
    end
    @state.insert_newline
    @on_change_cb.call(@state.value) if @on_change_cb
    mark_dirty
    update
  end

  # --- Clipboard ---

  def handle_copy
    text = @state.get_selected_text
    if text.length > 0
      app = App.current
      if app != nil
        app.set_clipboard_text(text)
      end
    end
  end

  def handle_cut
    text = @state.get_selected_text
    if text.length > 0
      @state.delete_selection
      app = App.current
      if app != nil
        app.set_clipboard_text(text)
      end
      @on_change_cb.call(@state.value) if @on_change_cb
      mark_dirty
      update
    end
  end

  def handle_paste
    app = App.current
    if app == nil
      return
    end
    text = app.get_clipboard_text
    if text == nil
      return
    end
    if text.length == 0
      return
    end
    if @state.has_selection
      @state.delete_selection
    end
    # Handle multi-line paste
    @state.paste_text(text)
    @on_change_cb.call(@state.value) if @on_change_cb
    mark_dirty
    update
  end
end

# Top-level helper — accepts initial text string for backward compatibility
def MultilineInput(text)
  MultilineInput.new(MultilineInputState.new(text))
end
