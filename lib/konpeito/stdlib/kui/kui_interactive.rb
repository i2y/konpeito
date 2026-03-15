# frozen_string_literal: true

# KUI Interactive Widgets — buttons, checkboxes, toggles, text input
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Interactive Widgets
# ════════════════════════════════════════════

# Button with click callback.
# Renders as a clickable box with hover highlight.
#: (String text, Integer size) -> Integer
def button(text, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_btn", id)
  _kui_layout(0, 8, 8, 4, 4, 0, 0, 0, 0, 0, 2, 2)

  # Hover / focus highlight
  hover = _kui_pointer_over_i("_btn", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    end
  end
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])

  _kui_text_color(text, size, 255, 255, 255)
  _kui_close

  # Click detection (mouse click or keyboard Enter on focus)
  if _kui_was_clicked_i("_btn", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# Menu item with cursor selection highlight.
# Shows ">" prefix when selected (cursor == index).
#: (String text, Integer index, Integer cursor, Integer size) -> Integer
def menu_item(text, index, cursor, size: 16)
  id = kui_auto_id
  _kui_open_i("_mi", id)
  _kui_layout(0, 8, 8, 2, 2, 4, 1, 0, 0, 0, 0, 2)

  if cursor == index
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    _kui_text_color("> ", size, 255, 255, 100)
    _kui_text_color(text, size, 255, 255, 255)
  else
    hover = _kui_pointer_over_i("_mi", id)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
    _kui_text_color("  ", size, 255, 255, 255)
    _kui_text(text, size)
  end

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Extended Interactive Widgets
# ════════════════════════════════════════════

# Checkbox with toggle callback.
# Renders as [x] or [ ] followed by text.
# checked: 1 = checked, 0 = unchecked.
# Yields block when toggled.
#: (String text, Integer checked, Integer size) -> Integer
def checkbox(text, checked, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_cb", id)
  _kui_layout(0, 4, 8, 2, 2, 4, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_cb", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
  end

  if checked == 1
    _kui_text_color("[x] ", size, KUITheme.c[24], KUITheme.c[25], KUITheme.c[26])
  else
    _kui_text_color("[ ] ", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  end
  _kui_text(text, size)
  _kui_close

  if _kui_was_clicked_i("_cb", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# Radio button.
# Renders as (*) or ( ) followed by text.
# index: this radio's index, selected: currently selected index.
# Yields block when selected.
#: (String text, Integer index, Integer selected, Integer size) -> Integer
def radio(text, index, selected, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_rb", id)
  _kui_layout(0, 4, 8, 2, 2, 4, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_rb", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
  end

  if index == selected
    _kui_text_color("(*) ", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  else
    _kui_text_color("( ) ", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  end
  _kui_text(text, size)
  _kui_close

  if _kui_was_clicked_i("_rb", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# Toggle switch.
# Renders as [ON] or [OFF] followed by text.
# on: 1 = on, 0 = off.
# Yields block when toggled.
#: (String text, Integer on, Integer size) -> Integer
def toggle(text, on, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_tg", id)
  _kui_layout(0, 4, 8, 2, 2, 4, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_tg", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
  end

  if on == 1
    _kui_text_color("[ON]  ", size, KUITheme.c[24], KUITheme.c[25], KUITheme.c[26])
  else
    _kui_text_color("[OFF] ", size, KUITheme.c[27], KUITheme.c[28], KUITheme.c[29])
  end
  _kui_text(text, size)
  _kui_close

  if _kui_was_clicked_i("_tg", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# ════════════════════════════════════════════
# Spinner
# ════════════════════════════════════════════

# Animated spinner using frame counter.
# Displays rotating characters: - \ | /
#: (Integer size) -> Integer
def spinner(size: 16)
  frame = KUIState.ids[0] + KUIState.ids[1]
  phase = (frame / 8) % 4
  if phase == 0
    _kui_text_color("-", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  end
  if phase == 1
    _kui_text_color("\\", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  end
  if phase == 2
    _kui_text_color("|", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  end
  if phase == 3
    _kui_text_color("/", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  end
  return 0
end

# ════════════════════════════════════════════
# Text Input
# ════════════════════════════════════════════

# Single-line text input widget.
# buf_id: text buffer ID (0-31), managed by C-side buffer.
# Handles keyboard input (characters, backspace, delete, cursor movement).
# Returns KUI_KEY_ENTER when submitted, 0 otherwise.
#: (Integer buf_id, Integer w, Integer size) -> Integer
def text_input(buf_id, w: 40, size: 16)
  id = kui_auto_id

  # Check if this text input is focused
  focused = _kui_is_focused

  # Click-to-focus: if mouse clicked on this element, set focus to it
  # Must be before _kui_register_focusable so s[1] still holds this element's index
  if _kui_was_clicked_i("_ti", id) == 1
    _kui_set_focus_current
  end
  _kui_register_focusable

  # Only process keyboard input if this text_input is focused
  if focused == 1
    # Handle character input (drain full queue for IME)
    ch = _kui_char_pressed
    while ch >= 32
      _kui_textbuf_putchar(buf_id, ch)
      ch = _kui_char_pressed
    end

    # Handle special keys
    key = kui_key_pressed
    if key == KUI_KEY_BACKSPACE
      _kui_textbuf_backspace(buf_id)
    end
    if key == KUI_KEY_DELETE
      _kui_textbuf_delete(buf_id)
    end
    if key == KUI_KEY_LEFT
      _kui_textbuf_cursor_left(buf_id)
    end
    if key == KUI_KEY_RIGHT
      _kui_textbuf_cursor_right(buf_id)
    end
    if key == KUI_KEY_HOME
      _kui_textbuf_cursor_home(buf_id)
    end
    if key == KUI_KEY_END
      _kui_textbuf_cursor_end(buf_id)
    end
  end

  # Render text box
  _kui_open_i("_ti", id)
  hp = size / 2
  vp = size / 4
  th = size + vp * 2 + 4
  _kui_layout(0, hp, hp, vp, vp, 0, 2, w, 2, th, 0, 2)
  if focused == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    _kui_set_border(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  else
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
    _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  end

  # Render buffer content with cursor
  buf_len = _kui_textbuf_len(buf_id)
  cur = _kui_textbuf_cursor_pos(buf_id)

  if buf_len > 0
    if cur > 0
      _kui_textbuf_render_range(buf_id, 0, cur, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
    end
  end

  # Cursor character (blinking) — only show when focused; space placeholder when unfocused
  if focused == 1
    blink = (KUIState.ids[1] / 15) % 2
    if blink == 0
      _kui_text_color("|", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    else
      _kui_text_color(" ", size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
    end
  else
    if buf_len == 0
      _kui_text_color(" ", size, KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
    end
  end

  if buf_len > 0
    if cur < buf_len
      _kui_textbuf_render_range(buf_id, cur, buf_len, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
    end
  end

  _kui_close

  if focused == 1
    key = kui_key_pressed
    if key == KUI_KEY_ENTER
      return KUI_KEY_ENTER
    end
  end
  return 0
end

# Clear a text input buffer.
#: (Integer buf_id) -> Integer
def kui_textbuf_clear(buf_id)
  _kui_textbuf_clear(buf_id)
  return 0
end

# Get text input buffer length.
#: (Integer buf_id) -> Integer
def kui_textbuf_len(buf_id)
  return _kui_textbuf_len(buf_id)
end

# Copy text buffer contents from src to dst.
#: (Integer dst, Integer src) -> Integer
def kui_textbuf_copy(dst, src)
  _kui_textbuf_copy(dst, src)
  return 0
end

# Render text buffer content as a text element.
#: (Integer buf_id, Integer size, Integer r, Integer g, Integer b) -> Integer
def kui_textbuf_render(buf_id, size: 16, r: 255, g: 255, b: 255)
  _kui_textbuf_render(buf_id, size, r, g, b)
  return 0
end

# ════════════════════════════════════════════
# Selectable List
# ════════════════════════════════════════════

# Selectable list container with keyboard navigation.
# selected: current selection index (user manages this).
# count: total number of items.
# visible: max visible items (0 = show all).
# Yields block for each visible item — user should render items inside.
#: (Integer selected, Integer count, Integer visible) -> Integer
def selectable_list(selected, count, visible: 0)
  id = kui_auto_id
  _kui_open_i("_sl", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0)
  _kui_scroll_v
  yield
  _kui_close
  return 0
end

# Single item in a selectable list.
# index: this item's index, selected: currently selected index.
# Renders with highlight when selected.
#: (String text, Integer index, Integer selected, Integer size) -> Integer
def list_item(text, index, selected, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_li", id)
  _kui_layout(0, 8, 8, 2, 2, 4, 1, 0, 0, 0, 0, 2)

  if index == selected
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    _kui_text_color(text, size, 255, 255, 255)
  else
    hover = _kui_pointer_over_i("_li", id)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      if focused == 1
        _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
      end
    end
    _kui_text(text, size)
  end

  _kui_close

  if _kui_was_clicked_i("_li", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end
