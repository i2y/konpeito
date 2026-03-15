# frozen_string_literal: true

# KUI — Unified Declarative UI DSL (Core)
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

# Percentage-width panel — width as % of parent (0-100).
# Height defaults to GROW. Use hpct for percentage height.
# Like Castella's flex: — e.g. 75 = 75% of parent width.
#: (Integer wpct, Integer hpct, Integer pad, Integer gap) -> Integer
def pct_panel(wpct, hpct: 0, pad: 0, gap: 0)
  id = kui_auto_id
  _kui_open_i("_pp", id)
  _kui_layout_pct(1, pad, pad, pad, pad, gap, wpct, hpct, 0, 0)
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

# Horizontal row with GROW height — fills vertical space equally.
# Like Castella's row(). Use inside vpanel for flex button grids.
#: (Integer gap) -> Integer
def row(gap: 0)
  id = kui_auto_id
  _kui_open_i("_gr", id)
  _kui_layout(0, 0, 0, 0, 0, gap, 1, 0, 1, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# Alias for backward compatibility.
#: (Integer gap) -> Integer
def grow_row(gap: 0)
  row gap: gap do
    yield
  end
  return 0
end

# Scrollable vertical panel.
#: (Integer pad, Integer gap) -> Integer
def scroll_panel(pad: 0, gap: 0)
  id = kui_auto_id
  _kui_open_i("_sp", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 1, 0, 0, 0)
  _kui_scroll_v
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
# Public API — Style Composition
# ════════════════════════════════════════════

# Create a packed style value from named properties.
# Packing: size + flex * 1000 + kind * 1000000
# Similar to Castella's Style.new.font_size(32).kind(KIND_WARNING).flex(3)
#: (Integer size, Integer kind, Integer flex) -> Integer
def kui_style(size: 0, kind: 0, flex: 0)
  return size + flex * 1000 + kind * 1000000
end

# Merge two styles: non-zero values in b override a.
# Similar to Castella's style_a + style_b.
#: (Integer a, Integer b) -> Integer
def kui_style_merge(a, b)
  s = b % 1000
  if s == 0
    s = a % 1000
  end
  f = (b / 1000) % 1000
  if f == 0
    f = (a / 1000) % 1000
  end
  k = b / 1000000
  if k == 0
    k = a / 1000000
  end
  return s + f * 1000 + k * 1000000
end

# ════════════════════════════════════════════
# Public API — Semantic Background Helpers
# ════════════════════════════════════════════

# Set background to named theme color. Avoids raw KUITheme.c[n] access.
# Usage: kui_bg_surface2  (instead of kui_bg(KUITheme.c[38], ...))

#: () -> Integer
def kui_bg_primary
  _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  return 0
end

#: () -> Integer
def kui_bg_surface
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  return 0
end

#: () -> Integer
def kui_bg_surface2
  _kui_set_bg(KUITheme.c[38], KUITheme.c[39], KUITheme.c[40])
  return 0
end

#: () -> Integer
def kui_bg_success
  _kui_set_bg(KUITheme.c[24], KUITheme.c[25], KUITheme.c[26])
  return 0
end

#: () -> Integer
def kui_bg_danger
  _kui_set_bg(KUITheme.c[27], KUITheme.c[28], KUITheme.c[29])
  return 0
end

#: () -> Integer
def kui_bg_info
  _kui_set_bg(KUITheme.c[32], KUITheme.c[33], KUITheme.c[34])
  return 0
end

#: () -> Integer
def kui_bg_warning
  _kui_set_bg(KUITheme.c[35], KUITheme.c[36], KUITheme.c[37])
  return 0
end

#: () -> Integer
def kui_bg_accent
  _kui_set_bg(KUITheme.c[41], KUITheme.c[42], KUITheme.c[43])
  return 0
end

# ════════════════════════════════════════════
# Public API — Kind & Color Helpers
# ════════════════════════════════════════════

# Clamp color value to 0-255 (prevents overflow in hover brightening).
#: (Integer v) -> Integer
def _kui_min255(v)
  if v > 255
    return 255
  end
  return v
end

# Map a KUI_KIND_* constant to the theme color base index.
# Used by button, badge, etc. for semantic coloring.
#: (Integer kind) -> Integer
def _kui_kind_base(kind)
  if kind == 1
    return 32
  end
  if kind == 2
    return 24
  end
  if kind == 3
    return 35
  end
  if kind == 4
    return 27
  end
  return 6
end

# ════════════════════════════════════════════
# Public API — Convenience
# ════════════════════════════════════════════

# Load a font (GUI: actual font file, TUI: no-op).
#: (String path, Integer size) -> Integer
def kui_load_font(path, size)
  return _kui_load_font(path, size)
end

# Load a font with CJK glyph ranges (GUI: CJK font file, TUI: no-op).
#: (String path, Integer size) -> Integer
def kui_load_font_cjk(path, size)
  return _kui_load_font_cjk(path, size)
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
