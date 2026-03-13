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
