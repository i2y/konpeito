# rbs_inline: enabled

# JWMFrame - bridges KUIRuntime (Java) to the Castella App
# Port of Castella Frame protocol

KUIRuntime = Java::Konpeito::Ui::KUIRuntime

class JWMFrame
  #: (String title, Integer width, Integer height) -> void
  def initialize(title, width, height)
    @runtime = KUIRuntime.new(title, width, height)
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

  #: () -> bool
  def is_dark_mode
    @runtime.is_dark_mode
  end

  #: () -> untyped
  def get_painter
    @runtime
  end

  #: () -> Size
  def get_size
    Size.new(@runtime.get_width, @runtime.get_height)
  end

  #: (untyped ev) -> void
  def post_update(ev)
    @runtime.mark_dirty
    @runtime.request_frame
  end

  # --- IME / Text Input control ---

  #: () -> void
  def enable_text_input
    @runtime.set_text_input_enabled(true)
  end

  #: () -> void
  def disable_text_input
    @runtime.set_text_input_enabled(false)
  end

  #: (Integer x, Integer y, Integer w, Integer h) -> void
  def set_ime_cursor_rect(x, y, w, h)
    @runtime.set_text_input_rect(x, y, w, h)
  end

  # --- Clipboard ---

  #: () -> String
  def get_clipboard_text
    @runtime.get_clipboard_text
  end

  #: (String text) -> void
  def set_clipboard_text(text)
    @runtime.set_clipboard_text(text)
  end

  #: () -> void
  def run
    rt = @runtime
    redraw_cb = @on_redraw
    mouse_down_cb = @on_mouse_down
    mouse_up_cb = @on_mouse_up
    cursor_pos_cb = @on_cursor_pos
    mouse_wheel_cb = @on_mouse_wheel
    input_char_cb = @on_input_char
    input_key_cb = @on_input_key
    ime_preedit_cb = @on_ime_preedit

    rt.set_on_frame {
      redraw_cb.call(rt, false) if redraw_cb
    }

    rt.set_on_mouse { |type, x, y, button|
      pos = Point.new(x, y)
      ev = MouseEvent.new(pos, button)
      if type == 1
        mouse_down_cb.call(ev) if mouse_down_cb
      elsif type == 2
        mouse_up_cb.call(ev) if mouse_up_cb
      else
        cursor_pos_cb.call(ev) if cursor_pos_cb
      end
    }

    # Use ScrollDeltaCallback (2 params) to avoid SAM confusion with MouseCallback (4 params)
    rt.set_on_scroll_delta { |dx, dy|
      if mouse_wheel_cb != nil
        pos = Point.new(0.0, 0.0)
        ev = WheelEvent.new(pos, dy)
        mouse_wheel_cb.call(ev)
      end
    }

    rt.set_on_text { |text|
      input_char_cb.call(text) if input_char_cb
    }

    rt.set_on_key { |type, key_code, modifiers|
      if type == 1
        input_key_cb.call(key_code, modifiers) if input_key_cb
      end
    }

    rt.set_on_ime { |text, sel_start, sel_end|
      ime_preedit_cb.call(text, sel_start, sel_end) if ime_preedit_cb
    }

    rt.run
  end
end
