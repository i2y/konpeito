# KonpeitoUI - Native UI runtime module (SDL3 + Skia)
#
# Ruby fallback stub for when the native extension is not available.
# This module provides the same interface as the C++ extension but
# raises an error when called, directing users to build the extension.

module KonpeitoUI
  # Event type constants
  EVENT_NONE        = 0
  EVENT_MOUSE_DOWN  = 1
  EVENT_MOUSE_UP    = 2
  EVENT_MOUSE_MOVE  = 3
  EVENT_MOUSE_WHEEL = 4
  EVENT_KEY_DOWN    = 5
  EVENT_KEY_UP      = 6
  EVENT_TEXT_INPUT  = 7
  EVENT_RESIZE      = 8
  EVENT_IME_PREEDIT = 9
  EVENT_QUIT        = 10

  # Modifier constants
  MOD_SHIFT   = 1
  MOD_CONTROL = 2
  MOD_ALT     = 4
  MOD_SUPER   = 8

  class << self
    def create_window(title, width, height)
      raise_not_available
    end

    def destroy_window(handle)
      raise_not_available
    end

    def step(handle)
      raise_not_available
    end

    def has_event(handle)
      raise_not_available
    end

    def event_type(handle)
      raise_not_available
    end

    def event_x(handle)
      raise_not_available
    end

    def event_y(handle)
      raise_not_available
    end

    def event_dx(handle)
      raise_not_available
    end

    def event_dy(handle)
      raise_not_available
    end

    def event_button(handle)
      raise_not_available
    end

    def event_key_code(handle)
      raise_not_available
    end

    def event_modifiers(handle)
      raise_not_available
    end

    def event_text(handle)
      raise_not_available
    end

    def event_ime_sel_start(handle)
      raise_not_available
    end

    def event_ime_sel_end(handle)
      raise_not_available
    end

    def consume_event(handle)
      raise_not_available
    end

    def begin_frame(handle)
      raise_not_available
    end

    def end_frame(handle)
      raise_not_available
    end

    def clear(handle, color)
      raise_not_available
    end

    def fill_rect(handle, x, y, w, h, color)
      raise_not_available
    end

    def stroke_rect(handle, x, y, w, h, color, stroke_width)
      raise_not_available
    end

    def fill_round_rect(handle, x, y, w, h, r, color)
      raise_not_available
    end

    def stroke_round_rect(handle, x, y, w, h, r, color, stroke_width)
      raise_not_available
    end

    def fill_circle(handle, cx, cy, r, color)
      raise_not_available
    end

    def stroke_circle(handle, cx, cy, r, color, stroke_width)
      raise_not_available
    end

    def draw_line(handle, x1, y1, x2, y2, color, width)
      raise_not_available
    end

    def fill_arc(handle, cx, cy, r, start_angle, sweep_angle, color)
      raise_not_available
    end

    def stroke_arc(handle, cx, cy, r, start_angle, sweep_angle, color, stroke_width)
      raise_not_available
    end

    def fill_triangle(handle, x1, y1, x2, y2, x3, y3, color)
      raise_not_available
    end

    def draw_text(handle, text, x, y, font_family, font_size, color)
      raise_not_available
    end

    def draw_text_styled(handle, text, x, y, font_family, font_size, color, weight, slant)
      raise_not_available
    end

    def measure_text_width(handle, text, font_family, font_size)
      raise_not_available
    end

    def measure_text_height(handle, font_family, font_size)
      raise_not_available
    end

    def get_text_ascent(handle, font_family, font_size)
      raise_not_available
    end

    def begin_path(handle)
      raise_not_available
    end

    def path_move_to(handle, x, y)
      raise_not_available
    end

    def path_line_to(handle, x, y)
      raise_not_available
    end

    def close_fill_path(handle, color)
      raise_not_available
    end

    def fill_path(handle, color)
      raise_not_available
    end

    def save(handle)
      raise_not_available
    end

    def restore(handle)
      raise_not_available
    end

    def translate(handle, dx, dy)
      raise_not_available
    end

    def clip_rect(handle, x, y, w, h)
      raise_not_available
    end

    def load_image(handle, path)
      raise_not_available
    end

    def load_net_image(handle, url)
      raise_not_available
    end

    def draw_image(handle, image_id, x, y, w, h)
      raise_not_available
    end

    def get_image_width(handle, image_id)
      raise_not_available
    end

    def get_image_height(handle, image_id)
      raise_not_available
    end

    def interpolate_color(c1, c2, t)
      raise_not_available
    end

    def with_alpha(color, alpha)
      raise_not_available
    end

    def lighten_color(color, amount)
      raise_not_available
    end

    def darken_color(color, amount)
      raise_not_available
    end

    def get_width(handle)
      raise_not_available
    end

    def get_height(handle)
      raise_not_available
    end

    def get_scale(handle)
      raise_not_available
    end

    def is_dark_mode(handle)
      raise_not_available
    end

    def request_frame(handle)
      raise_not_available
    end

    def mark_dirty(handle)
      raise_not_available
    end

    def set_text_input_enabled(handle, enabled)
      raise_not_available
    end

    def set_text_input_rect(handle, x, y, w, h)
      raise_not_available
    end

    def get_clipboard_text(handle)
      raise_not_available
    end

    def set_clipboard_text(handle, text)
      raise_not_available
    end

    def current_time_millis
      (Time.now.to_f * 1000).to_i
    end

    def number_to_string(value)
      value.to_s
    end

    def math_cos(radians)
      Math.cos(radians)
    end

    def math_sin(radians)
      Math.sin(radians)
    end

    def math_sqrt(value)
      Math.sqrt(value)
    end

    def math_atan2(y, x)
      Math.atan2(y, x)
    end

    def math_abs(value)
      value.abs
    end

    private

    def raise_not_available
      raise RuntimeError, <<~MSG
        KonpeitoUI native extension not available.
        Build it with:
          cd lib/konpeito/stdlib/ui && ruby extconf.rb && make

        Prerequisites:
          macOS: brew install sdl3 && export SKIA_DIR=/path/to/skia
          Linux: sudo apt install libsdl3-dev && export SKIA_DIR=/path/to/skia
      MSG
    end
  end
end
