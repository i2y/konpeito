# frozen_string_literal: true

# KUI GUI Backend — Clay + Raylib implementation
#
# This file wraps Clay (layout) and Raylib (rendering/input) behind the
# unified _kui_* function interface that the KUI DSL layer calls.
#
# Usage:
#   require_relative "kui_gui"
#
# Referencing Clay and Raylib modules triggers the compiler's auto-detection
# to link their native C implementations. No compiler changes needed.
#
# rbs_inline: enabled

require_relative "kui_theme"
require_relative "kui_events"
require_relative "kui"

# ── Lifecycle ──

#: (String title, Integer w, Integer h) -> Integer
def _kui_init(title, w, h)
  Raylib.set_config_flags(Raylib.flag_window_resizable)
  Raylib.init_window(w, h, title)
  Raylib.set_target_fps(60)
  Clay.init(w * 1.0, h * 1.0)
  Clay.set_measure_text_raylib
  return 0
end

#: () -> Integer
def _kui_destroy
  Clay.destroy
  Raylib.close_window
  return 0
end

#: () -> Integer
def _kui_begin_frame
  w = Raylib.get_screen_width
  h = Raylib.get_screen_height
  Clay.set_dimensions(w * 1.0, h * 1.0)
  mx = Raylib.get_mouse_x
  my = Raylib.get_mouse_y
  md = Raylib.mouse_button_down?(Raylib.mouse_left)
  Clay.set_pointer(mx * 1.0, my * 1.0, md)
  # Update scroll
  wheel = Raylib.get_mouse_wheel_move
  dt = Raylib.get_frame_time
  Clay.update_scroll(0.0, wheel * 40.0, dt)
  Clay.begin_layout
  return 0
end

#: () -> Integer
def _kui_end_frame
  Clay.end_layout
  Raylib.begin_drawing
  Raylib.clear_background(Raylib.color_new(KUITheme.c[0], KUITheme.c[1], KUITheme.c[2], 255))
  Clay.render_raylib
  Raylib.end_drawing
  return 0
end

#: () -> Integer
def _kui_running
  if Raylib.window_should_close == 0
    return 1
  end
  return 0
end

# ── Element Construction ──

#: (String id) -> Integer
def _kui_open(id)
  Clay.open(id)
  return 0
end

#: (String id, Integer index) -> Integer
def _kui_open_i(id, index)
  Clay.open_i(id, index)
  return 0
end

#: () -> Integer
def _kui_close
  Clay.close
  return 0
end

# ── Layout ──

#: () -> Integer
def _kui_set_vbox
  Clay.layout(1, 0, 0, 0, 0, 0, 1, 0.0, 1, 0.0, 0, 0)
  return 0
end

#: () -> Integer
def _kui_set_hbox
  Clay.layout(0, 0, 0, 0, 0, 0, 1, 0.0, 0, 0.0, 0, 0)
  return 0
end

#: (Integer l, Integer r, Integer t, Integer b) -> Integer
def _kui_set_pad(l, r, t, b)
  Clay.layout(1, l, r, t, b, 0, 1, 0.0, 1, 0.0, 0, 0)
  return 0
end

#: (Integer gap) -> Integer
def _kui_set_gap(gap)
  Clay.layout(1, 0, 0, 0, 0, gap, 1, 0.0, 1, 0.0, 0, 0)
  return 0
end

# Combined layout setter (direction, padding, gap, sizing, alignment)
#: (Integer dir, Integer pl, Integer pr, Integer pt, Integer pb, Integer gap, Integer swt, Integer swv, Integer sht, Integer shv, Integer ax, Integer ay) -> Integer
def _kui_layout(dir, pl, pr, pt, pb, gap, swt, swv, sht, shv, ax, ay)
  Clay.layout(dir, pl, pr, pt, pb, gap, swt, swv * 1.0, sht, shv * 1.0, ax, ay)
  return 0
end

#: () -> Integer
def _kui_set_width_grow
  # Already set via layout call — this is a no-op marker
  return 0
end

#: () -> Integer
def _kui_set_width_fit
  return 0
end

#: (Integer v) -> Integer
def _kui_set_width_fixed(v)
  # Handled via _kui_layout
  return 0
end

#: () -> Integer
def _kui_set_height_grow
  return 0
end

#: () -> Integer
def _kui_set_height_fit
  return 0
end

#: (Integer v) -> Integer
def _kui_set_height_fixed(v)
  return 0
end

# ── Decoration ──

#: (Integer r, Integer g, Integer b) -> Integer
def _kui_set_bg(r, g, b)
  cr = KUITheme.c[30]
  Clay.bg(r * 1.0, g * 1.0, b * 1.0, 255.0, cr * 1.0)
  return 0
end

#: (Integer r, Integer g, Integer b) -> Integer
def _kui_set_border(r, g, b)
  cr = KUITheme.c[30]
  Clay.border(r * 1.0, g * 1.0, b * 1.0, 255.0, 1, 1, 1, 1, cr * 1.0)
  return 0
end

# ── Text ──

#: (String text, Integer size) -> Integer
def _kui_text(text, size)
  fid = KUITheme.c[31]
  fr = KUITheme.c[3]
  fg = KUITheme.c[4]
  fb = KUITheme.c[5]
  Clay.text(text, fid, size, fr * 1.0, fg * 1.0, fb * 1.0, 255.0, 0)
  return 0
end

#: (String text, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_text_color(text, size, r, g, b)
  fid = KUITheme.c[31]
  Clay.text(text, fid, size, r * 1.0, g * 1.0, b * 1.0, 255.0, 0)
  return 0
end

# ── Pointer / Click ──

#: (String id, Integer index) -> Integer
def _kui_pointer_over_i(id, index)
  return Clay.pointer_over_i(id, index)
end

#: (String id, Integer index) -> Integer
def _kui_was_clicked_i(id, index)
  over = Clay.pointer_over_i(id, index)
  if over == 1
    if Raylib.mouse_button_pressed?(Raylib.mouse_left) == 1
      return 1
    end
  end
  return 0
end

# ── Input ──

#: () -> Integer
def _kui_key_pressed
  if Raylib.key_pressed?(Raylib.key_up) == 1
    return KUI_KEY_UP
  end
  if Raylib.key_pressed?(Raylib.key_down) == 1
    return KUI_KEY_DOWN
  end
  if Raylib.key_pressed?(Raylib.key_left) == 1
    return KUI_KEY_LEFT
  end
  if Raylib.key_pressed?(Raylib.key_right) == 1
    return KUI_KEY_RIGHT
  end
  if Raylib.key_pressed?(Raylib.key_enter) == 1
    return KUI_KEY_ENTER
  end
  if Raylib.key_pressed?(Raylib.key_escape) == 1
    return KUI_KEY_ESC
  end
  if Raylib.key_pressed?(Raylib.key_space) == 1
    return KUI_KEY_SPACE
  end
  return KUI_KEY_NONE
end

# ── Font ──

#: (String path, Integer size) -> Integer
def _kui_load_font(path, size)
  fid = Clay.load_font(path, size)
  KUITheme.c[31] = fid
  return fid
end

# ── Number Display Helpers (digit-by-digit, no string allocation) ──

#: (Integer d, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_draw_d(d, size, r, g, b)
  fid = KUITheme.c[31]
  rf = r * 1.0
  gf = g * 1.0
  bf = b * 1.0
  if d == 0
    Clay.text("0", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 1
    Clay.text("1", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 2
    Clay.text("2", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 3
    Clay.text("3", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 4
    Clay.text("4", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 5
    Clay.text("5", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 6
    Clay.text("6", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 7
    Clay.text("7", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 8
    Clay.text("8", fid, size, rf, gf, bf, 255.0, 0)
  end
  if d == 9
    Clay.text("9", fid, size, rf, gf, bf, 255.0, 0)
  end
  return 0
end

#: (Integer n, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_draw_num(n, size, r, g, b)
  fid = KUITheme.c[31]
  rf = r * 1.0
  gf = g * 1.0
  bf = b * 1.0
  if n < 0
    Clay.text("-", fid, size, rf, gf, bf, 255.0, 0)
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
