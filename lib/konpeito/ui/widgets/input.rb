# Input widget - single-line text input with IME, selection, and clipboard support
# Port of Castella Input
#
# State is held in InputState (defined in core.rb) which persists across
# Component rebuilds. The widget delegates all text/cursor/selection/IME
# operations to InputState and handles rendering + event dispatch.
#
# JWM Key ordinals used in input_key:
#   ENTER=11, BACKSPACE=12, ESCAPE=17, END=21, HOME=22, LEFT=23, RIGHT=25, DELETE=75
#   A=43, C=45, V=64, X=66

class Input < Widget
  def initialize(state)
    super()
    @state = state
    @focused = false
    @font_size_val = 14.0
    @bg_color = 0
    @text_color = 0
    @placeholder_color = 0
    @border_color = 0
    @focus_border = 0
    @use_theme = true
    @radius = 4.0
    @focusable = true
    @width_policy = EXPANDING
    @height_policy = CONTENT
    @pad_top = 8.0
    @pad_right = 12.0
    @pad_bottom = 8.0
    @pad_left = 12.0
    # Character position cache for click-to-position
    @char_positions = []
    @text_start_x = 0.0
    # on_change callback
    @on_change_cb = nil
  end

  def get_text
    @state.value
  end

  def set_text(t)
    @state.set(t)
    mark_dirty
  end

  def font_size(s)
    @font_size_val = s
    self
  end

  def on_change(&block)
    @on_change_cb = block
    self
  end

  def measure(painter)
    th = painter.measure_text_height($theme.font_family, @font_size_val)
    Size.new(@width, th + @pad_top + @pad_bottom)
  end

  # --- Rendering ---

  def redraw(painter, completely)
    # Resolve colors from theme
    bg_c = @use_theme ? $theme.bg_primary : @bg_color
    tc = @use_theme ? $theme.text_primary : @text_color
    pc = @use_theme ? $theme.text_secondary : @placeholder_color
    brd_c = @use_theme ? $theme.border : @border_color
    fbc = @use_theme ? $theme.border_focus : @focus_border

    bc = @focused ? fbc : brd_c
    painter.fill_round_rect(0.0, 0.0, @width, @height, @radius, bg_c)
    painter.stroke_round_rect(0.0, 0.0, @width, @height, @radius, bc, 1.0)

    ascent = painter.get_text_ascent($theme.font_family, @font_size_val)
    display_text = @state.get_display_text
    @text_start_x = @pad_left

    if display_text.length > 0
      # Draw selection highlight first (behind text)
      if @state.has_selection
        draw_selection_highlight(painter, display_text, ascent)
      end

      painter.draw_text(display_text, @text_start_x, @pad_top + ascent, $theme.font_family, @font_size_val, tc)

      # Build character position cache for click-to-position
      @char_positions = [0.0]
      i = 0
      while i < display_text.length
        sub = display_text[0, i + 1]
        w = painter.measure_text_width(sub, $theme.font_family, @font_size_val)
        @char_positions.push(w)
        i = i + 1
      end

      # Draw preedit underline
      if @state.has_preedit && @focused
        draw_preedit_underline(painter, ascent, tc)
      end
    else
      painter.draw_text(@state.get_placeholder, @text_start_x, @pad_top + ascent, $theme.font_family, @font_size_val, pc)
      @char_positions = [0.0]
    end

    # Cursor (when focused)
    if @focused
      draw_cursor(painter, tc)
    end
  end

  def draw_preedit_underline(painter, ascent, tc)
    text_before_preedit = ""
    cursor = @state.get_cursor
    if cursor > 0
      text_before_preedit = @state.value[0, cursor]
    end
    preedit_start_x = @pad_left + painter.measure_text_width(text_before_preedit, $theme.font_family, @font_size_val)
    preedit_width = painter.measure_text_width(@state.get_preedit_text, $theme.font_family, @font_size_val)
    underline_y = @pad_top + ascent + 2.0
    painter.fill_rect(preedit_start_x, underline_y, preedit_width, 2.0, tc)
  end

  def draw_cursor(painter, tc)
    text_before_caret = compute_text_before_caret
    cursor_x = @pad_left + painter.measure_text_width(text_before_caret, $theme.font_family, @font_size_val)
    painter.draw_line(cursor_x, @pad_top, cursor_x, @height - @pad_bottom, tc, 1.0)

    # Notify IME of cursor position
    notify_ime_cursor_rect(cursor_x)
  end

  def compute_text_before_caret
    result = ""
    cursor = @state.get_cursor
    if @state.has_preedit
      if cursor > 0
        result = @state.value[0, cursor]
      end
      result = result + @state.get_preedit_text[0, @state.get_preedit_cursor]
    else
      if cursor > 0
        result = @state.value[0, cursor]
      end
    end
    result
  end

  def draw_selection_highlight(painter, display_text, ascent)
    if @state.has_selection
      range = @state.get_selection_range
      s = range[0]
      e = range[1]
      # Clamp to display text
      if s > display_text.length
        s = display_text.length
      end
      if e > display_text.length
        e = display_text.length
      end
      if s < e
        x_start = @pad_left
        if s > 0
          x_start = @pad_left + painter.measure_text_width(display_text[0, s], $theme.font_family, @font_size_val)
        end
        x_end = @pad_left + painter.measure_text_width(display_text[0, e], $theme.font_family, @font_size_val)

        sel_color = $theme.bg_selected
        painter.fill_rect(x_start, @pad_top, x_end - x_start, @height - @pad_top - @pad_bottom, sel_color)
      end
    end
  end

  def notify_ime_cursor_rect(cursor_x)
    app = App.current
    if app != nil
      app.set_ime_cursor_rect(
        (@x + cursor_x).to_i,
        @y.to_i,
        1,
        @height.to_i
      )
    end
  end

  # --- Focus ---

  def focused
    @focused = true
    @state.start_editing
    app = App.current
    if app != nil
      app.enable_text_input
    end
    mark_dirty
    update
  end

  def restore_focus
    @focused = true
    app = App.current
    if app != nil
      app.enable_text_input
    end
    mark_dirty
  end

  def unfocused
    @focused = false
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
    @focused = true
    # Click-to-position
    click_x = ev.pos.x
    rel_x = click_x - @text_start_x
    char_pos = pos_from_click(rel_x)

    # Clear preedit on click
    if @state.has_preedit
      @state.clear_preedit
    end

    # Start selection
    @state.start_selection(char_pos)

    mark_dirty
    update
  end

  def mouse_drag(ev)
    if @state.is_selecting
      rel_x = ev.pos.x - @text_start_x
      char_pos = pos_from_click(rel_x)
      @state.update_selection(char_pos)
      mark_dirty
      update
    end
  end

  def mouse_up(ev)
    @state.end_selection
  end

  def pos_from_click(rel_x)
    result = @state.value.length
    if rel_x <= 0.0
      result = 0
    else
      found = false
      i = 1
      while i < @char_positions.length && !found
        pos = @char_positions[i]
        if pos > rel_x
          prev_pos = @char_positions[i - 1]
          if (rel_x - prev_pos) < (pos - rel_x)
            result = i - 1
          else
            result = i
          end
          found = true
        end
        i = i + 1
      end
    end
    result
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
    # Clear preedit when text is committed
    if @state.has_preedit
      @state.clear_preedit
    end
    # Delete selection if any
    if @state.has_selection
      @state.delete_selection
    end
    @state.insert(text)
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

    # Check for Cmd (bit 3 = MAC_COMMAND) or Ctrl (bit 1) modifier
    is_cmd = (modifiers & 8) != 0 || (modifiers & 2) != 0

    if is_cmd
      handle_cmd_key(key_code)
      return
    end

    # Clear selection on navigation keys
    if key_code == 23 || key_code == 25
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
    # Workaround: single-char preedit + backspace/escape
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
    # Backspace (JWM ordinal 12)
    if key_code == 12
      if @state.delete_prev
        @on_change_cb.call(@state.value) if @on_change_cb
        mark_dirty
        update
      end
    # Delete (JWM ordinal 75)
    elsif key_code == 75
      if @state.delete_next
        @on_change_cb.call(@state.value) if @on_change_cb
        mark_dirty
        update
      end
    # Left arrow (JWM ordinal 23)
    elsif key_code == 23
      if @state.move_prev
        mark_dirty
        update
      end
    # Right arrow (JWM ordinal 25)
    elsif key_code == 25
      if @state.move_next
        mark_dirty
        update
      end
    # Home (JWM ordinal 22) - move to beginning
    elsif key_code == 22
      if @state.move_home
        mark_dirty
        update
      end
    # End (JWM ordinal 21) - move to end
    elsif key_code == 21
      if @state.move_end
        mark_dirty
        update
      end
    end
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
    paste_text(text)
  end

  def paste_text(text)
    # Single line: take first line only
    first_line = find_first_line(text)
    @state.insert(first_line)
    @on_change_cb.call(@state.value) if @on_change_cb
    mark_dirty
    update
  end

  def find_first_line(text)
    result = text
    found = false
    newline_idx = 0
    while newline_idx < text.length && !found
      if text[newline_idx] == "\n"
        result = text[0, newline_idx]
        found = true
      end
      newline_idx = newline_idx + 1
    end
    result
  end
end

# Top-level helper — accepts placeholder string for backward compatibility
def Input(placeholder)
  Input.new(InputState.new(placeholder))
end
