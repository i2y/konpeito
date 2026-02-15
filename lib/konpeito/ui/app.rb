# rbs_inline: enabled

# App - main application loop with event dispatching
# Port of ~/castella/castella/core.py App

class App
  #: (JWMFrame frame, untyped widget) -> void
  def initialize(frame, widget)
    @@current = self
    @frame = frame
    @root = widget
    @downed = nil
    @focused = nil
    @mouse_overed = nil
    @prev_abs_x = 0.0
    @prev_abs_y = 0.0
    @prev_rel_x = 0.0
    @prev_rel_y = 0.0
    @focusables = []
    @prev_frame_w = 0.0
    @prev_frame_h = 0.0
    @cursor_x = 0.0
    @cursor_y = 0.0
    @animations = []
    @last_frame_time = 0
  end

  #: () -> App?
  def self.current
    @@current
  end

  # Clear references to a widget being detached
  #: (untyped w) -> void
  def clear_widget_refs(w)
    if @mouse_overed == w
      @mouse_overed = nil
    end
    if @focused == w
      @focused = nil
    end
    if @downed == w
      @downed = nil
    end
  end

  #: (untyped widget) -> void
  def post_update(widget)
    @frame.post_update(nil)
  end

  #: () -> void
  def run
    frame = @frame
    root = @root
    app = self

    frame.on_redraw { |painter, completely|
      # Tick animations
      now = painter.current_time_millis
      if @last_frame_time > 0
        dt = (now - @last_frame_time).to_f
        if dt > 100.0
          dt = 100.0  # Cap to avoid jumps
        end
        any_active = false
        i = 0
        while i < @animations.length
          still_going = @animations[i].tick(dt)
          if still_going
            any_active = true
          end
          i = i + 1
        end
        # Remove finished animations
        new_anims = []
        i = 0
        while i < @animations.length
          if @animations[i].animating?
            new_anims << @animations[i]
          end
          i = i + 1
        end
        @animations = new_anims
        if any_active
          completely = true
          frame.post_update(nil)
        end
      end
      @last_frame_time = now

      frame_size = frame.get_size
      # Detect resize → force complete redraw
      if frame_size.width != @prev_frame_w || frame_size.height != @prev_frame_h
        @prev_frame_w = frame_size.width
        @prev_frame_h = frame_size.height
        completely = true
      end

      # Resize root based on size policy
      rw = root.get_width_policy == EXPANDING ? frame_size.width : root.get_width
      rh = root.get_height_policy == EXPANDING ? frame_size.height : root.get_height
      root.resize_wh(rw, rh)
      root.move_xy(0.0, 0.0)

      if completely
        painter.clear($theme.bg_canvas)
      end
      root.redraw(painter, completely)
    }

    frame.on_mouse_down { |ev|
      result = root.dispatch(ev.pos)
      target = result[0]
      p = result[1]
      if target
        @prev_abs_x = ev.pos.x
        @prev_abs_y = ev.pos.y
        ev.pos = p
        @prev_rel_x = p.x
        @prev_rel_y = p.y
        target.mouse_down(ev)
        app.set_downed(target)
      end
    }

    frame.on_mouse_up { |ev|
      downed = app.get_downed
      if downed
        # Focus management: unfocus old, focus new
        old_focused = app.get_focused
        if old_focused != nil && old_focused != downed
          old_focused.unfocused
        end
        app.set_focused(downed)
        downed.focused

        # Convert to local coordinates relative to downed widget
        local_p = Point.new(ev.pos.x - downed.get_x, ev.pos.y - downed.get_y)
        ev.pos = local_p
        downed.mouse_up(ev)
        app.set_downed(nil)
      end
    }

    frame.on_cursor_pos { |ev|
      app.set_cursor_xy(ev.pos.x, ev.pos.y)
      result = root.dispatch(ev.pos)
      target = result[0]
      p = result[1]
      downed = app.get_downed
      overed = app.get_mouse_overed

      if target == nil
        # Cursor left all widgets
        if overed != nil
          overed.mouse_out
          app.set_mouse_overed(nil)
        end
      elsif downed == nil
        # No button pressed - handle hover
        if overed == nil
          app.set_mouse_overed(target)
          target.mouse_over
        elsif overed != target
          overed.mouse_out
          app.set_mouse_overed(target)
          target.mouse_over
        end
        # Notify target of cursor position
        if p != nil
          target.cursor_pos(MouseEvent.new(p, 0))
        end
      else
        # Button pressed - handle drag
        diff_x = ev.pos.x - @prev_abs_x
        diff_y = ev.pos.y - @prev_abs_y
        @prev_abs_x = ev.pos.x
        @prev_abs_y = ev.pos.y
        drag_pos = Point.new(@prev_rel_x + diff_x, @prev_rel_y + diff_y)
        @prev_rel_x = drag_pos.x
        @prev_rel_y = drag_pos.y
        downed.mouse_drag(MouseEvent.new(drag_pos, 0))
      end
    }

    frame.on_mouse_wheel { |ev|
      cursor = Point.new(app.get_cursor_x, app.get_cursor_y)
      result = root.dispatch_to_scrollable(cursor, false)
      target = result[0]
      if target != nil
        target.mouse_wheel(ev)
      end
    }

    frame.on_input_char { |text|
      focused = app.get_focused
      focused.input_char(text) if focused
    }

    frame.on_input_key { |key_code, modifiers|
      # Tab (JWM Key.TAB ordinal = 13): cycle focus
      if key_code == 13
        shift = (modifiers & 1) != 0
        app.cycle_focus(root, shift)
      else
        focused = app.get_focused
        focused.input_key(key_code, modifiers) if focused
      end
    }

    frame.on_ime_preedit { |text, sel_start, sel_end|
      focused = app.get_focused
      focused.ime_preedit(text, sel_start, sel_end) if focused
    }

    frame.run
  end

  # Accessors for event state (used from blocks)
  #: (untyped w) -> void
  def set_downed(w)
    @downed = w
  end

  #: () -> untyped
  def get_downed
    @downed
  end

  #: (untyped w) -> void
  def set_focused(w)
    @focused = w
  end

  #: () -> untyped
  def get_focused
    @focused
  end

  #: (untyped w) -> void
  def set_mouse_overed(w)
    @mouse_overed = w
  end

  #: () -> untyped
  def get_mouse_overed
    @mouse_overed
  end

  #: (Float x, Float y) -> void
  def set_cursor_xy(x, y)
    @cursor_x = x
    @cursor_y = y
  end

  #: () -> Float
  def get_cursor_x
    @cursor_x
  end

  #: () -> Float
  def get_cursor_y
    @cursor_y
  end

  # --- Animation ---

  #: (untyped anim) -> void
  def register_animation(anim)
    i = 0
    while i < @animations.length
      return if @animations[i] == anim
      i = i + 1
    end
    @animations << anim
    @frame.post_update(nil)
  end

  #: (untyped anim) -> void
  def unregister_animation(anim)
    new_list = []
    i = 0
    while i < @animations.length
      if @animations[i] != anim
        new_list << @animations[i]
      end
      i = i + 1
    end
    @animations = new_list
  end

  # --- Clipboard ---

  #: () -> String
  def get_clipboard_text
    @frame.get_clipboard_text
  end

  #: (String text) -> void
  def set_clipboard_text(text)
    @frame.set_clipboard_text(text)
  end

  # --- Text Input / IME ---

  #: () -> void
  def enable_text_input
    @frame.enable_text_input
  end

  #: () -> void
  def disable_text_input
    @frame.disable_text_input
  end

  #: (Integer x, Integer y, Integer w, Integer h) -> void
  def set_ime_cursor_rect(x, y, w, h)
    @frame.set_ime_cursor_rect(x, y, w, h)
  end

  # --- Focus Management ---
  # Collect focusable widgets from tree into @focusables array

  #: (untyped widget) -> void
  def collect_focusables_from(widget)
    if widget.is_focusable
      @focusables << widget
    end
    children = widget.get_children
    i = 0
    while i < children.length
      collect_focusables_from(children[i])
      i = i + 1
    end
  end

  #: (untyped root, bool reverse) -> void
  def cycle_focus(root, reverse)
    @focusables = []
    collect_focusables_from(root)
    count = @focusables.length
    return if count == 0

    # Find current focused index
    current_idx = -1
    i = 0
    while i < count
      if @focusables[i] == @focused
        current_idx = i
      end
      i = i + 1
    end

    # Compute next index
    next_idx = 0
    if reverse
      next_idx = current_idx - 1
      if next_idx < 0
        next_idx = count - 1
      end
    else
      next_idx = current_idx + 1
      if next_idx >= count
        next_idx = 0
      end
    end

    new_focus = @focusables[next_idx]
    old = @focused
    if old != nil
      old.unfocused
    end
    @focused = new_focus
    new_focus.focused
  end
  # Initialize @@current
  @@current = nil
end
