# frozen_string_literal: true

# Konpeito stdlib: Raylib bindings (Ruby stubs)
#
# These empty method definitions allow the Ruby source to reference Raylib
# methods. The actual implementations are in raylib_native.c and are linked
# directly via @cfunc annotations in raylib.rbs.

module Raylib
  # Window
  def self.init_window(w, h, title) end
  def self.close_window() end
  def self.window_should_close() end
  def self.set_target_fps(fps) end
  def self.get_frame_time() end
  def self.get_time() end
  def self.get_screen_width() end
  def self.get_screen_height() end
  def self.set_window_title(title) end
  def self.set_window_size(w, h) end
  def self.window_focused?() end
  def self.window_resized?() end
  def self.toggle_fullscreen() end
  def self.get_fps() end

  # Drawing
  def self.begin_drawing() end
  def self.end_drawing() end
  def self.clear_background(color) end
  def self.draw_rectangle(x, y, w, h, color) end
  def self.draw_rectangle_lines(x, y, w, h, color) end
  def self.draw_circle(cx, cy, radius, color) end
  def self.draw_circle_lines(cx, cy, radius, color) end
  def self.draw_line(x1, y1, x2, y2, color) end
  def self.draw_line_ex(x1, y1, x2, y2, thick, color) end
  def self.draw_triangle(x1, y1, x2, y2, x3, y3, color) end
  def self.draw_pixel(x, y, color) end

  # Text
  def self.draw_text(text, x, y, size, color) end
  def self.measure_text(text, size) end

  # Input — Keyboard
  def self.key_down?(key) end
  def self.key_pressed?(key) end
  def self.key_released?(key) end
  def self.key_up?(key) end
  def self.get_key_pressed() end
  def self.get_char_pressed() end

  # Input — Mouse
  def self.get_mouse_x() end
  def self.get_mouse_y() end
  def self.mouse_button_pressed?(btn) end
  def self.mouse_button_down?(btn) end
  def self.mouse_button_released?(btn) end
  def self.get_mouse_wheel_move() end

  # Colors
  def self.color_white() end
  def self.color_black() end
  def self.color_red() end
  def self.color_green() end
  def self.color_blue() end
  def self.color_yellow() end
  def self.color_orange() end
  def self.color_pink() end
  def self.color_purple() end
  def self.color_darkgray() end
  def self.color_lightgray() end
  def self.color_gray() end
  def self.color_raywhite() end
  def self.color_darkblue() end
  def self.color_skyblue() end
  def self.color_lime() end
  def self.color_darkgreen() end
  def self.color_darkpurple() end
  def self.color_violet() end
  def self.color_brown() end
  def self.color_darkbrown() end
  def self.color_beige() end
  def self.color_maroon() end
  def self.color_gold() end
  def self.color_magenta() end
  def self.color_blank() end
  def self.color_new(r, g, b, a) end
  def self.color_alpha(color, alpha) end

  # Key Constants
  def self.key_right() end
  def self.key_left() end
  def self.key_up() end
  def self.key_down() end
  def self.key_space() end
  def self.key_enter() end
  def self.key_escape() end
  def self.key_a() end
  def self.key_b() end
  def self.key_c() end
  def self.key_d() end
  def self.key_e() end
  def self.key_f() end
  def self.key_g() end
  def self.key_h() end
  def self.key_i() end
  def self.key_j() end
  def self.key_k() end
  def self.key_l() end
  def self.key_m() end
  def self.key_n() end
  def self.key_o() end
  def self.key_p() end
  def self.key_q() end
  def self.key_r() end
  def self.key_s() end
  def self.key_t() end
  def self.key_u() end
  def self.key_v() end
  def self.key_w() end
  def self.key_x() end
  def self.key_y() end
  def self.key_z() end
  def self.key_zero() end
  def self.key_one() end
  def self.key_two() end
  def self.key_three() end
  def self.key_four() end
  def self.key_five() end
  def self.key_six() end
  def self.key_seven() end
  def self.key_eight() end
  def self.key_nine() end

  # Mouse Button Constants
  def self.mouse_left() end
  def self.mouse_right() end
  def self.mouse_middle() end

  # Random
  def self.get_random_value(min, max) end
end
