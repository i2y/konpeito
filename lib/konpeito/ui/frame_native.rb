# rbs_inline: enabled

# NativeFrame - bridges KonpeitoUI (SDL3 + Skia) to the Castella App
# LLVM backend equivalent of JWMFrame (JVM backend)
#
# Key difference from JWMFrame: polling model instead of callbacks.
# SDL3 events are polled each frame instead of pushed via SAM callbacks.
#
# Painter methods use snake_case (matching Ruby conventions).
# JVM widgets call painter.draw_text(...) which RubyDispatch auto-converts
# to drawText; NativeFrame exposes snake_case directly.

# Try to load native extension, fall back to Ruby stub
begin
  require_relative "../stdlib/ui/konpeito_ui"
rescue LoadError
  require_relative "../stdlib/ui/ui"
end

class NativeFrame
  # Event type constants (from KonpeitoUI)
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

  #: (String title, Integer width, Integer height) -> void
  def initialize(title, width, height)
    @handle = KonpeitoUI.create_window(title, width, height)
    @running = false
    @on_redraw = nil
    @on_mouse_down = nil
    @on_mouse_up = nil
    @on_cursor_pos = nil
    @on_mouse_wheel = nil
    @on_input_char = nil
    @on_input_key = nil
    @on_resize = nil
    @on_ime_preedit = nil
  end

  # =============================================================
  # Frame interface — event callback registration
  # =============================================================

  #: () { (untyped, bool) -> void } -> void
  def on_redraw(&block)
    @on_redraw = block
  end

  #: () { (MouseEvent) -> void } -> void
  def on_mouse_down(&block)
    @on_mouse_down = block
  end

  #: () { (MouseEvent) -> void } -> void
  def on_mouse_up(&block)
    @on_mouse_up = block
  end

  #: () { (MouseEvent) -> void } -> void
  def on_cursor_pos(&block)
    @on_cursor_pos = block
  end

  #: () { (WheelEvent) -> void } -> void
  def on_mouse_wheel(&block)
    @on_mouse_wheel = block
  end

  #: () { (String) -> void } -> void
  def on_input_char(&block)
    @on_input_char = block
  end

  #: () { (Integer, Integer) -> void } -> void
  def on_input_key(&block)
    @on_input_key = block
  end

  #: () { () -> void } -> void
  def on_resize(&block)
    @on_resize = block
  end

  #: () { (String, Integer, Integer) -> void } -> void
  def on_ime_preedit(&block)
    @on_ime_preedit = block
  end

  # =============================================================
  # Frame interface — queries
  # =============================================================

  #: () -> bool
  def is_dark_mode
    KonpeitoUI.is_dark_mode(@handle)
  end

  #: () -> NativeFrame
  def get_painter
    self
  end

  #: () -> Size
  def get_size
    Size.new(KonpeitoUI.get_width(@handle), KonpeitoUI.get_height(@handle))
  end

  #: (untyped ev) -> void
  def post_update(ev)
    KonpeitoUI.mark_dirty(@handle)
    KonpeitoUI.request_frame(@handle)
  end

  # =============================================================
  # Frame interface — IME / Text Input control
  # =============================================================

  #: () -> void
  def enable_text_input
    KonpeitoUI.set_text_input_enabled(@handle, true)
  end

  #: () -> void
  def disable_text_input
    KonpeitoUI.set_text_input_enabled(@handle, false)
  end

  #: (Integer x, Integer y, Integer w, Integer h) -> void
  def set_ime_cursor_rect(x, y, w, h)
    KonpeitoUI.set_text_input_rect(@handle, x.to_i, y.to_i, w.to_i, h.to_i)
  end

  # =============================================================
  # Frame interface — clipboard
  # =============================================================

  #: () -> String
  def get_clipboard_text
    KonpeitoUI.get_clipboard_text(@handle)
  end

  #: (String text) -> void
  def set_clipboard_text(text)
    KonpeitoUI.set_clipboard_text(@handle, text)
  end

  # =============================================================
  # Painter — drawing primitives (snake_case)
  # =============================================================

  #: (Integer color) -> void
  def clear(color)
    KonpeitoUI.clear(@handle, color)
  end

  #: (Float x, Float y, Float w, Float h, Integer color) -> void
  def fill_rect(x, y, w, h, color)
    KonpeitoUI.fill_rect(@handle, x, y, w, h, color)
  end

  #: (Float x, Float y, Float w, Float h, Integer color, Float sw) -> void
  def stroke_rect(x, y, w, h, color, sw)
    KonpeitoUI.stroke_rect(@handle, x, y, w, h, color, sw)
  end

  #: (Float x, Float y, Float w, Float h, Float r, Integer color) -> void
  def fill_round_rect(x, y, w, h, r, color)
    KonpeitoUI.fill_round_rect(@handle, x, y, w, h, r, color)
  end

  #: (Float x, Float y, Float w, Float h, Float r, Integer color, Float sw) -> void
  def stroke_round_rect(x, y, w, h, r, color, sw)
    KonpeitoUI.stroke_round_rect(@handle, x, y, w, h, r, color, sw)
  end

  #: (Float cx, Float cy, Float r, Integer color) -> void
  def fill_circle(cx, cy, r, color)
    KonpeitoUI.fill_circle(@handle, cx, cy, r, color)
  end

  #: (Float cx, Float cy, Float r, Integer color, Float sw) -> void
  def stroke_circle(cx, cy, r, color, sw)
    KonpeitoUI.stroke_circle(@handle, cx, cy, r, color, sw)
  end

  #: (Float x1, Float y1, Float x2, Float y2, Integer color, Float w) -> void
  def draw_line(x1, y1, x2, y2, color, w)
    KonpeitoUI.draw_line(@handle, x1, y1, x2, y2, color, w)
  end

  #: (Float cx, Float cy, Float r, Float start_angle, Float sweep_angle, Integer color) -> void
  def fill_arc(cx, cy, r, start_angle, sweep_angle, color)
    KonpeitoUI.fill_arc(@handle, cx, cy, r, start_angle, sweep_angle, color)
  end

  #: (Float cx, Float cy, Float r, Float start_angle, Float sweep_angle, Integer color, Float sw) -> void
  def stroke_arc(cx, cy, r, start_angle, sweep_angle, color, sw)
    KonpeitoUI.stroke_arc(@handle, cx, cy, r, start_angle, sweep_angle, color, sw)
  end

  #: (Float x1, Float y1, Float x2, Float y2, Integer color, Float sw, Integer dummy) -> void
  def draw_polyline(x1, y1, x2, y2, color, sw, dummy)
    KonpeitoUI.draw_line(@handle, x1, y1, x2, y2, color, sw)
  end

  #: (Float x1, Float y1, Float x2, Float y2, Float x3, Float y3, Integer color) -> void
  def fill_triangle(x1, y1, x2, y2, x3, y3, color)
    KonpeitoUI.fill_triangle(@handle, x1, y1, x2, y2, x3, y3, color)
  end

  # =============================================================
  # Painter — text drawing
  # draw_text supports both 6-arg (normal) and 8-arg (weight/slant)
  # =============================================================

  #: (String text, Float x, Float y, String font_family, Float font_size, Integer color, *untyped extra) -> void
  def draw_text(text, x, y, font_family, font_size, color, *extra)
    if extra.length >= 2 && (extra[0] != 0 || extra[1] != 0)
      KonpeitoUI.draw_text_styled(@handle, text, x, y, font_family, font_size, color, extra[0], extra[1])
    else
      KonpeitoUI.draw_text(@handle, text, x, y, font_family, font_size, color)
    end
  end

  # =============================================================
  # Painter — text measurement
  # =============================================================

  #: (String text, String font_family, Float font_size) -> Float
  def measure_text_width(text, font_family, font_size)
    KonpeitoUI.measure_text_width(@handle, text, font_family, font_size)
  end

  #: (String font_family, Float font_size) -> Float
  def measure_text_height(font_family, font_size)
    KonpeitoUI.measure_text_height(@handle, font_family, font_size)
  end

  #: (String font_family, Float font_size) -> Float
  def get_text_ascent(font_family, font_size)
    KonpeitoUI.get_text_ascent(@handle, font_family, font_size)
  end

  # =============================================================
  # Painter — path drawing
  # =============================================================

  #: () -> void
  def begin_path
    KonpeitoUI.begin_path(@handle)
  end

  #: (Float x, Float y) -> void
  def path_move_to(x, y)
    KonpeitoUI.path_move_to(@handle, x, y)
  end

  #: (Float x, Float y) -> void
  def path_line_to(x, y)
    KonpeitoUI.path_line_to(@handle, x, y)
  end

  #: (Integer color) -> void
  def close_fill_path(color)
    KonpeitoUI.close_fill_path(@handle, color)
  end

  #: (Integer color) -> void
  def fill_path(color)
    KonpeitoUI.fill_path(@handle, color)
  end

  # =============================================================
  # Painter — canvas state
  # =============================================================

  #: () -> void
  def save
    KonpeitoUI.save(@handle)
  end

  #: () -> void
  def restore
    KonpeitoUI.restore(@handle)
  end

  #: (Float dx, Float dy) -> void
  def translate(dx, dy)
    KonpeitoUI.translate(@handle, dx, dy)
  end

  #: (Float x, Float y, Float w, Float h) -> void
  def clip_rect(x, y, w, h)
    KonpeitoUI.clip_rect(@handle, x, y, w, h)
  end

  # =============================================================
  # Painter — image operations
  # =============================================================

  #: (String path) -> Integer
  def load_image(path)
    KonpeitoUI.load_image(@handle, path)
  end

  #: (String url) -> Integer
  def load_net_image(url)
    KonpeitoUI.load_net_image(@handle, url)
  end

  #: (Integer image_id, Float x, Float y, Float w, Float h) -> void
  def draw_image(image_id, x, y, w, h)
    KonpeitoUI.draw_image(@handle, image_id, x, y, w, h)
  end

  #: (Integer image_id) -> Float
  def get_image_width(image_id)
    KonpeitoUI.get_image_width(@handle, image_id)
  end

  #: (Integer image_id) -> Float
  def get_image_height(image_id)
    KonpeitoUI.get_image_height(@handle, image_id)
  end

  # =============================================================
  # Painter — color utilities
  # =============================================================

  #: (Integer c1, Integer c2, Float t) -> Integer
  def interpolate_color(c1, c2, t)
    KonpeitoUI.interpolate_color(c1, c2, t)
  end

  #: (Integer color, Integer alpha) -> Integer
  def with_alpha(color, alpha)
    KonpeitoUI.with_alpha(color, alpha)
  end

  #: (Integer color, Float amount) -> Integer
  def lighten_color(color, amount)
    KonpeitoUI.lighten_color(color, amount)
  end

  #: (Integer color, Float amount) -> Integer
  def darken_color(color, amount)
    KonpeitoUI.darken_color(color, amount)
  end

  # =============================================================
  # Painter — math helpers
  # =============================================================

  #: (Float radians) -> Float
  def math_cos(radians)
    KonpeitoUI.math_cos(radians)
  end

  #: (Float radians) -> Float
  def math_sin(radians)
    KonpeitoUI.math_sin(radians)
  end

  #: (Float value) -> Float
  def math_sqrt(value)
    KonpeitoUI.math_sqrt(value)
  end

  #: (Float y, Float x) -> Float
  def math_atan2(y, x)
    KonpeitoUI.math_atan2(y, x)
  end

  #: (Float value) -> Float
  def math_abs(value)
    KonpeitoUI.math_abs(value)
  end

  # =============================================================
  # Painter — utilities
  # =============================================================

  #: () -> Integer
  def current_time_millis
    KonpeitoUI.current_time_millis
  end

  #: (Float value) -> String
  def number_to_string(value)
    KonpeitoUI.number_to_string(value)
  end

  # =============================================================
  # Main loop (polling model)
  # =============================================================

  #: () -> void
  def run
    @running = true
    h = @handle
    redraw_cb = @on_redraw
    mouse_down_cb = @on_mouse_down
    mouse_up_cb = @on_mouse_up
    cursor_pos_cb = @on_cursor_pos
    mouse_wheel_cb = @on_mouse_wheel
    input_char_cb = @on_input_char
    input_key_cb = @on_input_key
    resize_cb = @on_resize
    ime_preedit_cb = @on_ime_preedit

    while @running
      # Poll SDL3 events into ring buffer
      KonpeitoUI.step(h)

      # Process all queued events
      while KonpeitoUI.has_event(h)
        evt = KonpeitoUI.event_type(h)

        if evt == EVENT_QUIT
          @running = false
        elsif evt == EVENT_MOUSE_DOWN
          if mouse_down_cb
            pos = Point.new(KonpeitoUI.event_x(h), KonpeitoUI.event_y(h))
            ev = MouseEvent.new(pos, KonpeitoUI.event_button(h))
            mouse_down_cb.call(ev)
          end
        elsif evt == EVENT_MOUSE_UP
          if mouse_up_cb
            pos = Point.new(KonpeitoUI.event_x(h), KonpeitoUI.event_y(h))
            ev = MouseEvent.new(pos, KonpeitoUI.event_button(h))
            mouse_up_cb.call(ev)
          end
        elsif evt == EVENT_MOUSE_MOVE
          if cursor_pos_cb
            pos = Point.new(KonpeitoUI.event_x(h), KonpeitoUI.event_y(h))
            ev = MouseEvent.new(pos, 0)
            cursor_pos_cb.call(ev)
          end
        elsif evt == EVENT_MOUSE_WHEEL
          if mouse_wheel_cb
            pos = Point.new(KonpeitoUI.event_x(h), KonpeitoUI.event_y(h))
            wev = WheelEvent.new(pos, KonpeitoUI.event_dy(h))
            mouse_wheel_cb.call(wev)
          end
        elsif evt == EVENT_KEY_DOWN
          if input_key_cb
            input_key_cb.call(KonpeitoUI.event_key_code(h), KonpeitoUI.event_modifiers(h))
          end
        elsif evt == EVENT_TEXT_INPUT
          if input_char_cb
            input_char_cb.call(KonpeitoUI.event_text(h))
          end
        elsif evt == EVENT_RESIZE
          resize_cb.call if resize_cb
        elsif evt == EVENT_IME_PREEDIT
          if ime_preedit_cb
            ime_preedit_cb.call(
              KonpeitoUI.event_text(h),
              KonpeitoUI.event_ime_sel_start(h),
              KonpeitoUI.event_ime_sel_end(h)
            )
          end
        end

        KonpeitoUI.consume_event(h)
      end

      # Render frame only when needed (dirty flag or frame_requested)
      if KonpeitoUI.needs_redraw(h)
        # Clear flags BEFORE callback — callback may set them again (e.g. animations)
        KonpeitoUI.clear_dirty(h)
        KonpeitoUI.clear_frame_requested(h)
        KonpeitoUI.begin_frame(h)
        # Pass false for completely — app.rb upgrades to true on resize/animation
        redraw_cb.call(self, false) if redraw_cb
        KonpeitoUI.end_frame(h)
      else
        # Sleep longer when idle to reduce CPU usage
        sleep(0.008)
      end
    end

    KonpeitoUI.destroy_window(h)
  end
end
