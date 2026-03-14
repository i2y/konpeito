# frozen_string_literal: true

# Konpeito stdlib: Raylib bindings (Ruby stubs)
#
# These empty method definitions allow the Ruby source to reference Raylib
# methods. The actual implementations are in raylib_native.c and are linked
# directly via @cfunc annotations in raylib.rbs.

module Raylib
  # Window
  def self.set_config_flags(flags) end
  def self.init_window(w, h, title) end
  def self.close_window() end
  def self.window_should_close() end
  def self.set_target_fps(fps) end
  def self.get_frame_time() end
  def self.get_time() end
  def self.get_screen_width() end
  def self.get_screen_height() end
  def self.get_render_width() end
  def self.get_render_height() end
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
  def self.key_tab() end
  def self.key_backspace() end
  def self.key_delete() end
  def self.key_home() end
  def self.key_end() end
  def self.key_page_up() end
  def self.key_page_down() end
  def self.key_f1() end
  def self.key_f2() end
  def self.key_f3() end
  def self.key_f4() end
  def self.key_f5() end
  def self.key_f6() end
  def self.key_f7() end
  def self.key_f8() end
  def self.key_f9() end
  def self.key_f10() end
  def self.key_f11() end
  def self.key_f12() end
  def self.key_left_shift() end
  def self.key_right_shift() end
  def self.key_left_control() end
  def self.key_right_control() end
  def self.key_left_alt() end
  def self.key_right_alt() end
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

  # Window Flag Constants
  def self.flag_window_resizable() end
  def self.flag_window_highdpi() end
  def self.flag_msaa_4x_hint() end

  # Texture Management
  def self.load_texture(path) end
  def self.unload_texture(id) end
  def self.draw_texture(id, x, y, tint) end
  def self.draw_texture_rec(id, sx, sy, sw, sh, dx, dy, tint) end
  def self.draw_texture_pro(id, sx, sy, sw, sh, dx, dy, dw, dh, ox, oy, rotation, tint) end
  def self.get_texture_width(id) end
  def self.get_texture_height(id) end
  def self.texture_valid?(id) end
  def self.draw_texture_scaled(id, x, y, scale, tint) end

  # Audio — Device
  def self.init_audio_device() end
  def self.close_audio_device() end
  def self.audio_device_ready?() end
  def self.set_master_volume(vol) end
  def self.get_master_volume() end

  # Audio — Sound
  def self.load_sound(path) end
  def self.unload_sound(id) end
  def self.play_sound(id) end
  def self.stop_sound(id) end
  def self.pause_sound(id) end
  def self.resume_sound(id) end
  def self.sound_playing?(id) end
  def self.set_sound_volume(id, vol) end
  def self.set_sound_pitch(id, pitch) end

  # Audio — Music
  def self.load_music(path) end
  def self.unload_music(id) end
  def self.play_music(id) end
  def self.stop_music(id) end
  def self.pause_music(id) end
  def self.resume_music(id) end
  def self.update_music(id) end
  def self.music_playing?(id) end
  def self.set_music_volume(id, vol) end
  def self.set_music_pitch(id, pitch) end
  def self.get_music_time_length(id) end
  def self.get_music_time_played(id) end
  def self.seek_music(id, position) end

  # Camera2D
  def self.begin_mode_2d(offset_x, offset_y, target_x, target_y, rotation, zoom) end
  def self.end_mode_2d() end
  def self.get_world_to_screen_2d_x(world_x, world_y, offset_x, offset_y, target_x, target_y, rotation, zoom) end
  def self.get_world_to_screen_2d_y(world_x, world_y, offset_x, offset_y, target_x, target_y, rotation, zoom) end

  # File I/O
  def self.save_file_text(path, text) end
  def self.load_file_text(path) end
  def self.file_exists?(path) end
  def self.directory_exists?(path) end

  # Font Management
  def self.load_font(path) end
  def self.load_font_ex(path, size) end
  def self.unload_font(id) end
  def self.draw_text_ex(font_id, text, x, y, size, spacing, tint) end
  def self.measure_text_ex_x(font_id, text, size, spacing) end
  def self.measure_text_ex_y(font_id, text, size, spacing) end

  # Gamepad Input
  def self.gamepad_available?(gamepad) end
  def self.gamepad_button_pressed?(gamepad, button) end
  def self.gamepad_button_down?(gamepad, button) end
  def self.gamepad_button_released?(gamepad, button) end
  def self.gamepad_button_up?(gamepad, button) end
  def self.get_gamepad_axis_movement(gamepad, axis) end
  def self.get_gamepad_axis_count(gamepad) end

  # Gamepad Button Constants
  def self.gamepad_button_left_face_up() end
  def self.gamepad_button_left_face_right() end
  def self.gamepad_button_left_face_down() end
  def self.gamepad_button_left_face_left() end
  def self.gamepad_button_right_face_up() end
  def self.gamepad_button_right_face_right() end
  def self.gamepad_button_right_face_down() end
  def self.gamepad_button_right_face_left() end
  def self.gamepad_button_left_trigger_1() end
  def self.gamepad_button_left_trigger_2() end
  def self.gamepad_button_right_trigger_1() end
  def self.gamepad_button_right_trigger_2() end
  def self.gamepad_button_middle_left() end
  def self.gamepad_button_middle() end
  def self.gamepad_button_middle_right() end

  # Gamepad Axis Constants
  def self.gamepad_axis_left_x() end
  def self.gamepad_axis_left_y() end
  def self.gamepad_axis_right_x() end
  def self.gamepad_axis_right_y() end
  def self.gamepad_axis_left_trigger() end
  def self.gamepad_axis_right_trigger() end

  # Drawing — Extended Shapes
  def self.draw_rectangle_pro(x, y, w, h, ox, oy, rotation, color) end
  def self.draw_rectangle_rounded(x, y, w, h, roundness, segments, color) end
  def self.draw_rectangle_gradient_v(x, y, w, h, color1, color2) end
  def self.draw_rectangle_gradient_h(x, y, w, h, color1, color2) end
  def self.draw_circle_sector(cx, cy, radius, start_angle, end_angle, segments, color) end

  # Collision Detection
  def self.check_collision_recs(x1, y1, w1, h1, x2, y2, w2, h2) end
  def self.check_collision_circles(cx1, cy1, r1, cx2, cy2, r2) end
  def self.check_collision_circle_rec(cx, cy, radius, rx, ry, rw, rh) end
  def self.check_collision_point_rec(px, py, rx, ry, rw, rh) end
  def self.check_collision_point_circle(px, py, cx, cy, radius) end
end
