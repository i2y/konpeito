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
require_relative "kui_state"
require_relative "kui"
require_relative "kui_interactive"
require_relative "kui_containers"
require_relative "kui_data"
require_relative "kui_forms"
require_relative "kui_overlay"
require_relative "kui_layouts"
require_relative "kui_nav"
require_relative "kui_markdown"

# @rbs module KUIGuiState
# @rbs   @s: NativeArray[Integer, 4]
# @rbs end
# KUIGuiState.s slots:
#   [0] = focus_index (current focused element)
#   [1] = focus_count (total focusable elements this frame)

# ── Lifecycle ──

#: (String title, Integer w, Integer h) -> Integer
def _kui_init(title, w, h)
  flags = Raylib.flag_window_resizable + Raylib.flag_window_highdpi
  Raylib.set_config_flags(flags)
  Raylib.init_window(w, h, title)
  Raylib.set_target_fps(60)
  rw = Raylib.get_render_width
  rh = Raylib.get_render_height
  Clay.init(rw * 1.0, rh * 1.0)
  Clay.set_measure_text_raylib
  Clay.register_resize_callback
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
  rw = Raylib.get_render_width
  rh = Raylib.get_render_height
  sw = Raylib.get_screen_width
  sh = Raylib.get_screen_height
  Clay.set_dimensions(rw * 1.0, rh * 1.0)
  # Scale mouse coordinates from screen space to render space
  mx = Raylib.get_mouse_x * rw / sw
  my = Raylib.get_mouse_y * rh / sh
  md = Raylib.mouse_button_down?(Raylib.mouse_left)
  Clay.set_pointer(mx * 1.0, my * 1.0, md)
  # Update scroll
  wheel = Raylib.get_mouse_wheel_move
  dt = Raylib.get_frame_time
  Clay.update_scroll(0.0, wheel * 40.0, dt)
  # Reset per-frame focus counter
  KUIGuiState.s[1] = 0
  Clay.begin_layout
  return 0
end

# Called from C (GLFW refresh callback) during live window resize.
# Performs a full frame: begin_layout → draw → end_layout → render.
# Convention: the user app defines a top-level `draw` method.
#: () -> Integer
def _kui_resize_frame
  kui_reset_ids
  KUIState.ids[1] = KUIState.ids[1] + 1
  rw = Raylib.get_render_width
  rh = Raylib.get_render_height
  Clay.set_dimensions(rw * 1.0, rh * 1.0)
  KUIGuiState.s[1] = 0
  Clay.begin_layout
  draw
  Clay.end_layout
  Raylib.begin_drawing
  Raylib.clear_background(Raylib.color_new(KUITheme.c[0], KUITheme.c[1], KUITheme.c[2], 255))
  Clay.render_raylib
  Raylib.end_drawing
  return 0
end

#: () -> Integer
def _kui_end_frame
  Clay.end_layout
  Clay.set_bg_color(KUITheme.c[0], KUITheme.c[1], KUITheme.c[2])
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
  if Raylib.key_pressed?(Raylib.key_tab) == 1
    return KUI_KEY_TAB
  end
  if Raylib.key_pressed?(Raylib.key_backspace) == 1
    return KUI_KEY_BACKSPACE
  end
  if Raylib.key_pressed?(Raylib.key_delete) == 1
    return KUI_KEY_DELETE
  end
  if Raylib.key_pressed?(Raylib.key_home) == 1
    return KUI_KEY_HOME
  end
  if Raylib.key_pressed?(Raylib.key_end) == 1
    return KUI_KEY_END
  end
  if Raylib.key_pressed?(Raylib.key_page_up) == 1
    return KUI_KEY_PGUP
  end
  if Raylib.key_pressed?(Raylib.key_page_down) == 1
    return KUI_KEY_PGDN
  end
  if Raylib.key_pressed?(Raylib.key_f1) == 1
    return KUI_KEY_F1
  end
  if Raylib.key_pressed?(Raylib.key_f2) == 1
    return KUI_KEY_F2
  end
  if Raylib.key_pressed?(Raylib.key_f3) == 1
    return KUI_KEY_F3
  end
  if Raylib.key_pressed?(Raylib.key_f4) == 1
    return KUI_KEY_F4
  end
  if Raylib.key_pressed?(Raylib.key_f5) == 1
    return KUI_KEY_F5
  end
  if Raylib.key_pressed?(Raylib.key_f6) == 1
    return KUI_KEY_F6
  end
  if Raylib.key_pressed?(Raylib.key_f7) == 1
    return KUI_KEY_F7
  end
  if Raylib.key_pressed?(Raylib.key_f8) == 1
    return KUI_KEY_F8
  end
  if Raylib.key_pressed?(Raylib.key_f9) == 1
    return KUI_KEY_F9
  end
  if Raylib.key_pressed?(Raylib.key_f10) == 1
    return KUI_KEY_F10
  end
  if Raylib.key_pressed?(Raylib.key_f11) == 1
    return KUI_KEY_F11
  end
  if Raylib.key_pressed?(Raylib.key_f12) == 1
    return KUI_KEY_F12
  end
  return KUI_KEY_NONE
end

# Get character code from current frame.
# Returns 0 if no character was pressed.
#: () -> Integer
def _kui_char_pressed
  return Raylib.get_char_pressed
end

# Get modifier key state (bitmask: SHIFT=1, CTRL=2, ALT=4).
#: () -> Integer
def _kui_mod_pressed
  mod = 0
  if Raylib.key_down?(Raylib.key_left_shift) == 1
    mod = mod + 1
  end
  if Raylib.key_down?(Raylib.key_right_shift) == 1
    mod = mod + 1
  end
  if Raylib.key_down?(Raylib.key_left_control) == 1
    mod = mod + 2
  end
  if Raylib.key_down?(Raylib.key_right_control) == 1
    mod = mod + 2
  end
  if Raylib.key_down?(Raylib.key_left_alt) == 1
    mod = mod + 4
  end
  if Raylib.key_down?(Raylib.key_right_alt) == 1
    mod = mod + 4
  end
  return mod
end

# ── Text Buffer (delegates to Clay C) ──

#: (Integer id) -> Integer
def _kui_textbuf_clear(id)
  Clay.textbuf_clear(id)
  return 0
end

#: (Integer id, Integer ch) -> Integer
def _kui_textbuf_putchar(id, ch)
  Clay.textbuf_putchar(id, ch)
  return 0
end

#: (Integer id) -> Integer
def _kui_textbuf_backspace(id)
  Clay.textbuf_backspace(id)
  return 0
end

#: (Integer id) -> Integer
def _kui_textbuf_delete(id)
  Clay.textbuf_delete(id)
  return 0
end

#: (Integer id) -> Integer
def _kui_textbuf_cursor_left(id)
  Clay.textbuf_cursor_left(id)
  return 0
end

#: (Integer id) -> Integer
def _kui_textbuf_cursor_right(id)
  Clay.textbuf_cursor_right(id)
  return 0
end

#: (Integer id) -> Integer
def _kui_textbuf_cursor_home(id)
  Clay.textbuf_cursor_home(id)
  return 0
end

#: (Integer id) -> Integer
def _kui_textbuf_cursor_end(id)
  Clay.textbuf_cursor_end(id)
  return 0
end

#: (Integer id) -> Integer
def _kui_textbuf_len(id)
  return Clay.textbuf_len(id)
end

#: (Integer id) -> Integer
def _kui_textbuf_cursor_pos(id)
  return Clay.textbuf_cursor(id)
end

# Copy text buffer contents from src to dst.
#: (Integer dst, Integer src) -> Integer
def _kui_textbuf_copy(dst, src)
  Clay.textbuf_copy(dst, src)
  return 0
end

# Render text buffer as Clay text (GC-free via C string pool).
#: (Integer id, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_textbuf_render(id, size, r, g, b)
  fid = KUITheme.c[31]
  Clay.textbuf_render(id, fid, size, r * 1.0, g * 1.0, b * 1.0)
  return 0
end

# Render text buffer range [start, end) as Clay text.
#: (Integer id, Integer start_pos, Integer end_pos, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_textbuf_render_range(id, start_pos, end_pos, size, r, g, b)
  fid = KUITheme.c[31]
  Clay.textbuf_render_range(id, start_pos, end_pos, fid, size, r * 1.0, g * 1.0, b * 1.0)
  return 0
end

# Render single character by code (GC-free via C).
#: (Integer ch, Integer size, Integer r, Integer g, Integer b) -> Integer
def _kui_text_char(ch, size, r, g, b)
  fid = KUITheme.c[31]
  Clay.text_char(ch, fid, size, r * 1.0, g * 1.0, b * 1.0)
  return 0
end

# ── Focus System ──

# Register a focusable element (call for each interactive widget)
#: () -> Integer
def _kui_register_focusable
  KUIGuiState.s[1] = KUIGuiState.s[1] + 1
  return 0
end

# Set focus to the current focusable element (click-to-focus)
#: () -> Integer
def _kui_set_focus_current
  KUIGuiState.s[0] = KUIGuiState.s[1]
  return 0
end

# Check if the current focusable element is focused
#: () -> Integer
def _kui_is_focused
  fi = KUIGuiState.s[0]
  fc = KUIGuiState.s[1]
  if fi == fc
    return 1
  end
  return 0
end

# ── Floating / Scroll DSL helpers ──

#: (Integer ox, Integer oy, Integer z) -> Integer
def _kui_floating(ox, oy, z)
  Clay.floating(ox * 1.0, oy * 1.0, z, 0, 0)
  return 0
end

# Float relative to root window (for toast, drawer, etc.)
#: (Integer ox, Integer oy, Integer z) -> Integer
def _kui_floating_root(ox, oy, z)
  # att_parent=5 maps to CLAY_ATTACH_POINT_CENTER_CENTER for root attachment
  Clay.floating(ox * 1.0, oy * 1.0, z, 0, 0)
  return 0
end

#: () -> Integer
def _kui_scroll_v
  Clay.scroll(0, 1)
  return 0
end

#: () -> Integer
def _kui_scroll_h
  Clay.scroll(1, 0)
  return 0
end

# ── Mouse / Input State ──

# Mouse X position (render-space scaled)
#: () -> Integer
def _kui_mouse_x
  rw = Raylib.get_render_width
  sw = Raylib.get_screen_width
  return Raylib.get_mouse_x * rw / sw
end

# Mouse Y position (render-space scaled)
#: () -> Integer
def _kui_mouse_y
  rh = Raylib.get_render_height
  sh = Raylib.get_screen_height
  return Raylib.get_mouse_y * rh / sh
end

# Mouse left button currently held down
#: () -> Integer
def _kui_mouse_down
  return Raylib.mouse_button_down?(Raylib.mouse_left)
end

# Mouse left button released this frame
#: () -> Integer
def _kui_mouse_released
  return Raylib.mouse_button_released?(Raylib.mouse_left)
end

# Elapsed time in milliseconds
#: () -> Integer
def _kui_get_time_ms
  t = Raylib.get_time
  return (t * 1000).to_i
end

# ── Font ──

#: (String path, Integer size) -> Integer
def _kui_load_font(path, size)
  fid = Clay.load_font(path, size)
  KUITheme.c[31] = fid
  return fid
end

#: (String path, Integer size) -> Integer
def _kui_load_font_cjk(path, size)
  fid = Clay.load_font_cjk(path, size)
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
