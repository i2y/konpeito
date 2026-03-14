# frozen_string_literal: true

# KUI — Unified Declarative UI DSL
#
# Provides a backend-agnostic, yield-based DSL for building
# user interfaces. Works with both GUI (Clay + Raylib) and
# TUI (ClayTUI + termbox2) backends.
#
# The DSL calls _kui_* backend functions which are implemented
# by either kui_gui.rb or kui_tui.rb.
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Public API — Lifecycle
# ════════════════════════════════════════════

#: (String title, Integer w, Integer h) -> Integer
def kui_init(title, w, h)
  kui_reset_ids
  _kui_init(title, w, h)
  return 0
end

#: () -> Integer
def kui_destroy
  _kui_destroy
  return 0
end

#: () -> Integer
def kui_begin_frame
  kui_reset_ids
  KUIState.ids[1] = KUIState.ids[1] + 1
  _kui_begin_frame
  return 0
end

#: () -> Integer
def kui_end_frame
  _kui_end_frame
  return 0
end

#: () -> Integer
def kui_running
  return _kui_running
end

# ════════════════════════════════════════════
# Public API — Layout Containers
# ════════════════════════════════════════════

# Vertical panel — children stack top-to-bottom.
# GROW width, GROW height by default.
#: (Integer pad, Integer gap) -> Integer
def vpanel(pad: 0, gap: 0)
  id = kui_auto_id
  _kui_open_i("_vp", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 1, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# Horizontal panel — children flow left-to-right.
# GROW width, FIT height by default.
#: (Integer pad, Integer gap) -> Integer
def hpanel(pad: 0, gap: 0)
  id = kui_auto_id
  _kui_open_i("_hp", id)
  _kui_layout(0, pad, pad, pad, pad, gap, 1, 0, 0, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# Fixed-size panel — explicit width and height.
#: (Integer w, Integer h, Integer pad) -> Integer
def fixed_panel(w, h, pad: 0)
  id = kui_auto_id
  _kui_open_i("_fp", id)
  _kui_layout(1, pad, pad, pad, pad, 0, 2, w, 2, h, 0, 0)
  yield
  _kui_close
  return 0
end

# Centered panel — children centered both axes.
# GROW width, FIT height.
#: (Integer pad, Integer gap) -> Integer
def cpanel(pad: 0, gap: 0)
  id = kui_auto_id
  _kui_open_i("_cp", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 0, 0, 2, 2)
  yield
  _kui_close
  return 0
end

# Scrollable vertical panel.
#: (Integer pad, Integer gap) -> Integer
def scroll_panel(pad: 0, gap: 0)
  id = kui_auto_id
  _kui_open_i("_sp", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 1, 0, 0, 0)
  # Enable vertical scrolling (handled by Clay internally)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Text
# ════════════════════════════════════════════

# Text label using theme foreground color.
#: (String text, Integer size, Integer r, Integer g, Integer b) -> Integer
def label(text, size: 16, r: -1, g: -1, b: -1)
  if r >= 0
    _kui_text_color(text, size, r, g, b)
  else
    _kui_text(text, size)
  end
  return 0
end

# Numeric label — renders integer digit-by-digit (no string allocation).
#: (Integer value, Integer size, Integer r, Integer g, Integer b) -> Integer
def label_num(value, size: 16, r: -1, g: -1, b: -1)
  id = kui_auto_id
  _kui_open_i("_ln", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  if r >= 0
    _kui_draw_num(value, size, r, g, b)
  else
    _kui_draw_num(value, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
  end
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Interactive Widgets
# ════════════════════════════════════════════

# Button with click callback.
# Renders as a clickable box with hover highlight.
#: (String text, Integer size) -> Integer
def button(text, size: 16)
  id = kui_auto_id
  _kui_open_i("_btn", id)
  _kui_layout(0, 8, 8, 4, 4, 0, 0, 0, 0, 0, 2, 2)

  # Hover / focus highlight
  hover = _kui_pointer_over_i("_btn", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  end
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])

  _kui_text_color(text, size, 255, 255, 255)
  _kui_close

  # Click detection (mouse click or keyboard Enter on focus)
  if _kui_was_clicked_i("_btn", id) == 1
    yield
  end
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
# Public API — Decoration Widgets
# ════════════════════════════════════════════

# Spacer — fills available space (GROW both axes).
#: () -> Integer
def spacer
  id = kui_auto_id
  _kui_open_i("_spc", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0)
  _kui_close
  return 0
end

# Horizontal divider line.
#: (Integer r, Integer g, Integer b) -> Integer
def divider(r: -1, g: -1, b: -1)
  id = kui_auto_id
  _kui_open_i("_div", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 2, 1, 0, 0)
  if r >= 0
    _kui_set_bg(r, g, b)
  else
    _kui_set_bg(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  end
  _kui_close
  return 0
end

# Progress bar with fill percentage.
#: (Integer value, Integer max, Integer w, Integer h, Integer r, Integer g, Integer b) -> Integer
def progress_bar(value, max, w, h, r: -1, g: -1, b: -1)
  id = kui_auto_id
  _kui_open_i("_pb", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 2, w, 2, h, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])

  if max > 0
    fill_w = value * w / max
    if fill_w < 0
      fill_w = 0
    end
    if fill_w > w
      fill_w = w
    end
    if fill_w > 0
      _kui_open_i("_pbf", id)
      _kui_layout(0, 0, 0, 0, 0, 0, 2, fill_w, 2, h, 0, 0)
      if r >= 0
        _kui_set_bg(r, g, b)
      else
        _kui_set_bg(KUITheme.c[24], KUITheme.c[25], KUITheme.c[26])
      end
      _kui_close
    end
  end

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Styling (applied to current element)
# ════════════════════════════════════════════

# Set background color for the next/current container.
#: (Integer r, Integer g, Integer b) -> Integer
def kui_bg(r, g, b)
  _kui_set_bg(r, g, b)
  return 0
end

# Set border for the next/current container.
#: (Integer r, Integer g, Integer b) -> Integer
def kui_border(r, g, b)
  _kui_set_border(r, g, b)
  return 0
end

# ════════════════════════════════════════════
# Public API — Styled Containers
# ════════════════════════════════════════════

# Card — surface-colored panel with border.
#: (Integer pad, Integer gap) -> Integer
def card(pad: 12, gap: 8)
  id = kui_auto_id
  _kui_open_i("_crd", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# Header bar — primary-colored horizontal bar.
#: (Integer pad) -> Integer
def header(pad: 8)
  id = kui_auto_id
  _kui_open_i("_hdr", id)
  _kui_layout(0, pad, pad, pad, pad, 8, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  yield
  _kui_close
  return 0
end

# Footer bar — subtle bottom bar.
#: (Integer pad) -> Integer
def footer(pad: 8)
  id = kui_auto_id
  _kui_open_i("_ftr", id)
  _kui_layout(0, pad, pad, pad, pad, 8, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  yield
  _kui_close
  return 0
end

# Sidebar — fixed-width vertical panel.
#: (Integer w, Integer pad, Integer gap) -> Integer
def sidebar(w, pad: 8, gap: 4)
  id = kui_auto_id
  _kui_open_i("_sb", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 2, w, 1, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Convenience
# ════════════════════════════════════════════

# Load a font (GUI: actual font file, TUI: no-op).
#: (String path, Integer size) -> Integer
def kui_load_font(path, size)
  return _kui_load_font(path, size)
end

# Get unified key code for the current frame.
#: () -> Integer
def kui_key_pressed
  return _kui_key_pressed
end

# Get character code for the current frame (printable chars).
# Returns 0 if no character was pressed.
#: () -> Integer
def kui_char_pressed
  return _kui_char_pressed
end

# Get modifier key state (bitmask).
#: () -> Integer
def kui_mod_pressed
  return _kui_mod_pressed
end

# ════════════════════════════════════════════
# Public API — Interactive Widgets (Extended)
# ════════════════════════════════════════════

# Checkbox with toggle callback.
# Renders as [x] or [ ] followed by text.
# checked: 1 = checked, 0 = unchecked.
# Yields block when toggled.
#: (String text, Integer checked, Integer size) -> Integer
def checkbox(text, checked, size: 16)
  id = kui_auto_id
  _kui_open_i("_cb", id)
  _kui_layout(0, 4, 8, 2, 2, 4, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_cb", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
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
  return 0
end

# Radio button.
# Renders as (*) or ( ) followed by text.
# index: this radio's index, selected: currently selected index.
# Yields block when selected.
#: (String text, Integer index, Integer selected, Integer size) -> Integer
def radio(text, index, selected, size: 16)
  id = kui_auto_id
  _kui_open_i("_rb", id)
  _kui_layout(0, 4, 8, 2, 2, 4, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_rb", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
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
  return 0
end

# Toggle switch.
# Renders as [ON] or [OFF] followed by text.
# on: 1 = on, 0 = off.
# Yields block when toggled.
#: (String text, Integer on, Integer size) -> Integer
def toggle(text, on, size: 16)
  id = kui_auto_id
  _kui_open_i("_tg", id)
  _kui_layout(0, 4, 8, 2, 2, 4, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_tg", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
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
  return 0
end

# ════════════════════════════════════════════
# Public API — Spinner
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
# Public API — Text Input
# ════════════════════════════════════════════

# Single-line text input widget.
# buf_id: text buffer ID (0-7), managed by C-side buffer.
# Handles keyboard input (characters, backspace, delete, cursor movement).
# Returns KUI_KEY_ENTER when submitted, 0 otherwise.
#: (Integer buf_id, Integer w, Integer size) -> Integer
def text_input(buf_id, w: 40, size: 16)
  id = kui_auto_id

  # Handle character input
  ch = _kui_char_pressed
  if ch >= 32
    if ch <= 126
      _kui_textbuf_putchar(buf_id, ch)
    end
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

  # Render text box
  _kui_open_i("_ti", id)
  _kui_layout(0, 4, 4, 2, 2, 0, 2, w, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])

  # Render buffer content with cursor
  buf_len = _kui_textbuf_len(buf_id)
  cur = _kui_textbuf_cursor_pos(buf_id)

  if buf_len > 0
    if cur > 0
      _kui_textbuf_render_range(buf_id, 0, cur, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
    end
  end

  # Cursor character (blinking)
  blink = (KUIState.ids[0] / 15) % 2
  if blink == 0
    _kui_text_color("|", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  else
    _kui_text_color(" ", size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
  end

  if buf_len > 0
    if cur < buf_len
      _kui_textbuf_render_range(buf_id, cur, buf_len, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
    end
  end

  _kui_close

  if key == KUI_KEY_ENTER
    return KUI_KEY_ENTER
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

# ════════════════════════════════════════════
# Public API — Selectable List
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
  _kui_open_i("_li", id)
  _kui_layout(0, 8, 8, 2, 2, 4, 1, 0, 0, 0, 0, 2)

  if index == selected
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    _kui_text_color(text, size, 255, 255, 255)
  else
    hover = _kui_pointer_over_i("_li", id)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
    _kui_text(text, size)
  end

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Table / Data Grid
# ════════════════════════════════════════════

# Table header row.
#: (Integer pad) -> Integer
def table_header(pad: 4)
  id = kui_auto_id
  _kui_open_i("_th", id)
  _kui_layout(0, pad, pad, pad, pad, 0, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  yield
  _kui_close
  return 0
end

# Table body row. Alternates background color based on row index.
#: (Integer row_index, Integer pad) -> Integer
def table_row(row_index, pad: 4)
  id = kui_auto_id
  _kui_open_i("_tr", id)
  _kui_layout(0, pad, pad, pad, pad, 0, 1, 0, 0, 0, 0, 2)

  even = row_index % 2
  if even == 0
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  end

  yield
  _kui_close
  return 0
end

# Table cell with fixed width.
#: (Integer w, Integer pad) -> Integer
def table_cell(w, pad: 4)
  id = kui_auto_id
  _kui_open_i("_tc", id)
  _kui_layout(0, pad, pad, 0, 0, 0, 2, w, 0, 0, 0, 2)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Modal / Dialog
# ════════════════════════════════════════════

# Modal overlay — centered floating panel.
# Renders as a floating element with semi-transparent backdrop.
#: (Integer w, Integer h) -> Integer
def modal(w, h)
  id = kui_auto_id

  # Backdrop (full-screen semi-transparent)
  _kui_open_i("_mbg", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 2, 2)
  _kui_set_bg(0, 0, 0)
  _kui_floating(0, 0, 100)

  # Modal content
  _kui_open_i("_mdl", id)
  _kui_layout(1, 16, 16, 16, 16, 8, 2, w, 2, h, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Tabs
# ════════════════════════════════════════════

# Tab bar — horizontal row of tab buttons.
# active: currently active tab index.
# Yields block where user should call tab_button for each tab.
#: (Integer active) -> Integer
def tab_bar(active)
  id = kui_auto_id
  _kui_open_i("_tb", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  yield
  _kui_close
  return 0
end

# Single tab button. Yields when clicked.
#: (String text, Integer index, Integer active, Integer size) -> Integer
def tab_button(text, index, active, size: 16)
  id = kui_auto_id
  _kui_open_i("_tbt", id)
  _kui_layout(0, 12, 12, 6, 6, 0, 0, 0, 0, 0, 2, 2)

  if index == active
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    _kui_text_color(text, size, 255, 255, 255)
  else
    hover = _kui_pointer_over_i("_tbt", id)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
    _kui_text(text, size)
  end

  _kui_close

  if _kui_was_clicked_i("_tbt", id) == 1
    yield
  end
  return 0
end

# Tab content panel — shows content for the active tab.
#: (Integer pad, Integer gap) -> Integer
def tab_content(pad: 8, gap: 4)
  id = kui_auto_id
  _kui_open_i("_tcp", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 1, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Public API — Status Bar
# ════════════════════════════════════════════

# Status bar — fixed at bottom with left/center/right segments.
#: (Integer pad) -> Integer
def status_bar(pad: 4)
  id = kui_auto_id
  _kui_open_i("_stb", id)
  _kui_layout(0, pad, pad, pad, pad, 0, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# Status bar left segment.
#: () -> Integer
def status_left
  id = kui_auto_id
  _kui_open_i("_stl", id)
  _kui_layout(0, 4, 4, 0, 0, 4, 0, 0, 0, 0, 0, 2)
  yield
  _kui_close
  return 0
end

# Status bar center segment (spacer + content + spacer).
#: () -> Integer
def status_center
  spacer
  id = kui_auto_id
  _kui_open_i("_stc", id)
  _kui_layout(0, 4, 4, 0, 0, 4, 0, 0, 0, 0, 2, 2)
  yield
  _kui_close
  spacer
  return 0
end

# Status bar right segment.
#: () -> Integer
def status_right
  spacer
  id = kui_auto_id
  _kui_open_i("_str", id)
  _kui_layout(0, 4, 4, 0, 0, 4, 0, 0, 0, 0, 0, 2)
  yield
  _kui_close
  return 0
end
