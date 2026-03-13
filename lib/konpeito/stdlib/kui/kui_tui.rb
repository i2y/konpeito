# frozen_string_literal: true

# KUI TUI Backend — ClayTUI (Clay + termbox2) implementation
#
# This file wraps ClayTUI behind the unified _kui_* function interface
# that the KUI DSL layer calls.
#
# Usage:
#   require_relative "kui_tui"
#
# Referencing ClayTUI module triggers the compiler's auto-detection
# to link its native C implementation. No compiler changes needed.
#
# rbs_inline: enabled

require_relative "kui_theme"
require_relative "kui_events"
require_relative "kui"

# @rbs module KUITuiState
# @rbs   @s: NativeArray[Integer, 8]
# @rbs end

# KUITuiState.s slots:
#   [0] = focus_index (current focused element for keyboard nav)
#   [1] = focus_count (total focusable elements this frame)
#   [2] = last_key    (cached key from peek_event)
#   [3] = mouse_x     (cached mouse x from event)
#   [4] = mouse_y     (cached mouse y from event)
#   [5] = mouse_down  (1 if mouse clicked this frame)
#   [6] = running     (1 = running, 0 = should quit)
#   [7] = event_type  (cached event type)

# ── Lifecycle ──

#: (String title, Integer w, Integer h) -> Integer
def _kui_init(title, w, h)
  tw = ClayTUI.term_width
  th = ClayTUI.term_height
  ClayTUI.init(tw * 1.0, th * 1.0)
  ClayTUI.set_measure_text
  KUITuiState.s[0] = 0
  KUITuiState.s[1] = 0
  KUITuiState.s[6] = 1
  return 0
end

#: () -> Integer
def _kui_destroy
  ClayTUI.destroy
  return 0
end

#: () -> Integer
def _kui_begin_frame
  tw = ClayTUI.term_width
  th = ClayTUI.term_height
  ClayTUI.set_dimensions(tw * 1.0, th * 1.0)

  # Reset per-frame state
  KUITuiState.s[1] = 0
  KUITuiState.s[5] = 0
  KUITuiState.s[2] = 0
  KUITuiState.s[7] = 0

  # Poll events (non-blocking)
  evt = ClayTUI.peek_event(16)
  if evt > 0
    etype = ClayTUI.event_type
    KUITuiState.s[7] = etype

    if etype == 1
      # Key event
      key = ClayTUI.event_key
      KUITuiState.s[2] = key

      if key == ClayTUI.key_esc
        KUITuiState.s[6] = 0
      end
    end

    if etype == 2
      # Resize event
      ClayTUI.set_dimensions(ClayTUI.event_w * 1.0, ClayTUI.event_h * 1.0)
    end

    if etype == 3
      # Mouse event
      KUITuiState.s[3] = ClayTUI.event_mouse_x
      KUITuiState.s[4] = ClayTUI.event_mouse_y
      KUITuiState.s[5] = 1
      ClayTUI.set_pointer(KUITuiState.s[3] * 1.0, KUITuiState.s[4] * 1.0, 1)
    end
  end

  ClayTUI.begin_layout
  return 0
end

#: () -> Integer
def _kui_end_frame
  ClayTUI.end_layout
  ClayTUI.render
  return 0
end

#: () -> Integer
def _kui_running
  return KUITuiState.s[6]
end

# ── Element Construction ──

#: (String id) -> Integer
def _kui_open(id)
  ClayTUI.open(id)
  return 0
end

#: (String id, Integer index) -> Integer
def _kui_open_i(id, index)
  ClayTUI.open_i(id, index)
  return 0
end

#: () -> Integer
def _kui_close
  ClayTUI.close
  return 0
end

# ── Layout ──

#: () -> Integer
def _kui_set_vbox
  ClayTUI.vbox
  ClayTUI.width_grow
  ClayTUI.height_grow
  return 0
end

#: () -> Integer
def _kui_set_hbox
  ClayTUI.hbox
  ClayTUI.width_grow
  ClayTUI.height_fit
  return 0
end

#: (Integer l, Integer r, Integer t, Integer b) -> Integer
def _kui_set_pad(l, r, t, b)
  ClayTUI.pad(l, r, t, b)
  return 0
end

#: (Integer gap) -> Integer
def _kui_set_gap(gap)
  ClayTUI.gap(gap)
  return 0
end

# Combined layout setter — maps to individual ClayTUI calls
# dir: 0=LEFT_TO_RIGHT, 1=TOP_TO_BOTTOM
# swt/sht: 0=FIT, 1=GROW, 2=FIXED
#: (Integer dir, Integer pl, Integer pr, Integer pt, Integer pb, Integer gap, Integer swt, Integer swv, Integer sht, Integer shv, Integer ax, Integer ay) -> Integer
def _kui_layout(dir, pl, pr, pt, pb, gap, swt, swv, sht, shv, ax, ay)
  if dir == 0
    ClayTUI.hbox
  else
    ClayTUI.vbox
  end
  if pl > 0
    ClayTUI.pad(pl, pr, pt, pb)
  end
  if gap > 0
    ClayTUI.gap(gap)
  end
  if swt == 0
    ClayTUI.width_fit
  end
  if swt == 1
    ClayTUI.width_grow
  end
  if swt == 2
    ClayTUI.width_fixed(swv * 1.0)
  end
  if sht == 0
    ClayTUI.height_fit
  end
  if sht == 1
    ClayTUI.height_grow
  end
  if sht == 2
    ClayTUI.height_fixed(shv * 1.0)
  end
  if ax > 0
    ClayTUI.align(ax, ay)
  end
  return 0
end

#: () -> Integer
def _kui_set_width_grow
  ClayTUI.width_grow
  return 0
end

#: () -> Integer
def _kui_set_width_fit
  ClayTUI.width_fit
  return 0
end

#: (Integer v) -> Integer
def _kui_set_width_fixed(v)
  ClayTUI.width_fixed(v * 1.0)
  return 0
end

#: () -> Integer
def _kui_set_height_grow
  ClayTUI.height_grow
  return 0
end

#: () -> Integer
def _kui_set_height_fit
  ClayTUI.height_fit
  return 0
end

#: (Integer v) -> Integer
def _kui_set_height_fixed(v)
  ClayTUI.height_fixed(v * 1.0)
  return 0
end

# ── Decoration ──

#: (Integer r, Integer g, Integer b) -> Integer
def _kui_set_bg(r, g, b)
  ClayTUI.bg(r, g, b)
  return 0
end

#: (Integer r, Integer g, Integer b) -> Integer
def _kui_set_border(r, g, b)
  ClayTUI.border(r * 1.0, g * 1.0, b * 1.0, 255.0, 1, 1, 1, 1, 0.0)
  return 0
end

# ── Text ──

#: (String text, Integer size) -> Integer
def _kui_text(text, size)
  fr = KUITheme.c[3]
  fg = KUITheme.c[4]
  fb = KUITheme.c[5]
  ClayTUI.text(text, fr, fg, fb)
  return 0
end

#: (String text, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_text_color(text, size, r, g, b)
  ClayTUI.text(text, r, g, b)
  return 0
end

# ── Pointer / Click ──

#: (String id, Integer index) -> Integer
def _kui_pointer_over_i(id, index)
  return ClayTUI.pointer_over_i(id, index)
end

# TUI click: either mouse click on element, or Enter key when focused
#: (String id, Integer index) -> Integer
def _kui_was_clicked_i(id, index)
  # Mouse click
  if KUITuiState.s[5] == 1
    over = ClayTUI.pointer_over_i(id, index)
    if over == 1
      return 1
    end
  end
  # Keyboard: focus_index matches and Enter pressed
  if KUITuiState.s[2] == ClayTUI.key_enter
    fi = KUITuiState.s[0]
    fc = KUITuiState.s[1]
    # focus_count tracks which focusable element this is
    if fi == fc
      return 1
    end
  end
  return 0
end

# Register a focusable element (call for each button/interactive widget)
#: () -> Integer
def _kui_register_focusable
  KUITuiState.s[1] = KUITuiState.s[1] + 1
  return 0
end

# Check if the current focusable element is focused
#: () -> Integer
def _kui_is_focused
  fi = KUITuiState.s[0]
  fc = KUITuiState.s[1]
  if fi == fc
    return 1
  end
  return 0
end

# ── Input ──

#: () -> Integer
def _kui_key_pressed
  key = KUITuiState.s[2]
  if key == ClayTUI.key_arrow_up
    return KUI_KEY_UP
  end
  if key == ClayTUI.key_arrow_down
    return KUI_KEY_DOWN
  end
  if key == ClayTUI.key_arrow_left
    return KUI_KEY_LEFT
  end
  if key == ClayTUI.key_arrow_right
    return KUI_KEY_RIGHT
  end
  if key == ClayTUI.key_enter
    return KUI_KEY_ENTER
  end
  if key == ClayTUI.key_esc
    return KUI_KEY_ESC
  end
  if key == ClayTUI.key_space
    return KUI_KEY_SPACE
  end
  if key == ClayTUI.key_tab
    return KUI_KEY_TAB
  end
  if key == ClayTUI.key_backspace
    return KUI_KEY_BACKSPACE
  end
  return KUI_KEY_NONE
end

# ── Focus Navigation ──
# Call at end of frame to handle Tab/Arrow focus cycling

#: () -> Integer
def _kui_update_focus
  key = KUITuiState.s[2]
  total = KUITuiState.s[1]
  if total > 0
    if key == ClayTUI.key_tab
      KUITuiState.s[0] = (KUITuiState.s[0] + 1) % total
    end
    if key == ClayTUI.key_arrow_down
      KUITuiState.s[0] = (KUITuiState.s[0] + 1) % total
    end
    if key == ClayTUI.key_arrow_up
      fi = KUITuiState.s[0] - 1
      if fi < 0
        fi = total - 1
      end
      KUITuiState.s[0] = fi
    end
  end
  return 0
end

# ── Font (no-op for TUI) ──

#: (String path, Integer size) -> Integer
def _kui_load_font(path, size)
  return 0
end

# ── Number Display Helpers ──

#: (Integer d, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_draw_d(d, size, r, g, b)
  if d == 0
    ClayTUI.text("0", r, g, b)
  end
  if d == 1
    ClayTUI.text("1", r, g, b)
  end
  if d == 2
    ClayTUI.text("2", r, g, b)
  end
  if d == 3
    ClayTUI.text("3", r, g, b)
  end
  if d == 4
    ClayTUI.text("4", r, g, b)
  end
  if d == 5
    ClayTUI.text("5", r, g, b)
  end
  if d == 6
    ClayTUI.text("6", r, g, b)
  end
  if d == 7
    ClayTUI.text("7", r, g, b)
  end
  if d == 8
    ClayTUI.text("8", r, g, b)
  end
  if d == 9
    ClayTUI.text("9", r, g, b)
  end
  return 0
end

#: (Integer n, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_draw_num(n, size, r, g, b)
  if n < 0
    ClayTUI.text("-", r, g, b)
    n = 0 - n
  end
  if n >= 100000
    _kui_draw_d(n / 100000, size, r, g, b)
  end
  if n >= 10000
    _kui_draw_d((n / 10000) % 10, size, r, g, b)
  end
  if n >= 1000
    _kui_draw_d((n / 1000) % 10, size, r, g, b)
  end
  if n >= 100
    _kui_draw_d((n / 100) % 10, size, r, g, b)
  end
  if n >= 10
    _kui_draw_d((n / 10) % 10, size, r, g, b)
  end
  _kui_draw_d(n % 10, size, r, g, b)
  return 0
end
