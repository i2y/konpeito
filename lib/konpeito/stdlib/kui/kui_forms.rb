# frozen_string_literal: true

# KUI Form Widgets — number_stepper, search_bar, segmented_control,
# slider, textarea, switch, rating, color_picker, date_picker
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Number Stepper
# ════════════════════════════════════════════

# Number stepper — [-] value [+] buttons.
# Yields -1 on decrement, +1 on increment.
#: (Integer value, Integer min, Integer max, Integer size) -> Integer
def number_stepper(value, min, max, size: 16)
  id = kui_auto_id
  _kui_open_i("_ns", id)
  _kui_layout(0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2)

  # Minus button
  mid = kui_auto_id
  _kui_open_i("_nsm", mid)
  _kui_layout(0, 6, 6, 2, 2, 0, 0, 0, 0, 0, 2, 2)
  if value <= min
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
    _kui_text_color("-", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  else
    hover = _kui_pointer_over_i("_nsm", mid)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    end
    _kui_text_color("-", size, 255, 255, 255)
  end
  _kui_close

  if value > min
    if _kui_was_clicked_i("_nsm", mid) == 1
      yield(-1)
    end
  end

  # Value display
  vid = kui_auto_id
  _kui_open_i("_nsv", vid)
  _kui_layout(0, 8, 8, 2, 2, 0, 0, 0, 0, 0, 2, 2)
  _kui_draw_num(value, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
  _kui_close

  # Plus button
  pid = kui_auto_id
  _kui_open_i("_nsp", pid)
  _kui_layout(0, 6, 6, 2, 2, 0, 0, 0, 0, 0, 2, 2)
  if value >= max
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
    _kui_text_color("+", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  else
    hover = _kui_pointer_over_i("_nsp", pid)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    end
    _kui_text_color("+", size, 255, 255, 255)
  end
  _kui_close

  if value < max
    if _kui_was_clicked_i("_nsp", pid) == 1
      yield(1)
    end
  end

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Search Bar
# ════════════════════════════════════════════

# Search bar — text input with search icon prefix.
# Returns KUI_KEY_ENTER when submitted, 0 otherwise.
#: (Integer buf_id, Integer w, Integer size) -> Integer
def search_bar(buf_id, w: 200, size: 16)
  id = kui_auto_id
  _kui_open_i("_srch", id)
  _kui_layout(0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 2)
  _kui_text_color("[?] ", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  result = text_input(buf_id, w: w, size: size)
  _kui_close
  return result
end

# ════════════════════════════════════════════
# Segmented Control
# ════════════════════════════════════════════

# Single segment button within a segmented control.
#: (String text, Integer index, Integer active, Integer size) -> Integer
def segment_button(text, index, active, size: 14)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_seg", id)
  _kui_layout(0, 8, 8, 4, 4, 0, 0, 0, 0, 0, 2, 2)

  if index == active
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    _kui_text_color(text, size, 255, 255, 255)
  else
    hover = _kui_pointer_over_i("_seg", id)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      if focused == 1
        _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
      else
        _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
      end
    end
    _kui_text(text, size)
  end

  _kui_close

  if _kui_was_clicked_i("_seg", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# Segmented control container.
#: (Integer active) -> Integer
def segmented_control(active)
  id = kui_auto_id
  _kui_open_i("_sgc", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Slider / Range
# ════════════════════════════════════════════

# Horizontal slider — click to increment, Left/Right arrows for fine control.
# Each click advances by 5% of range. Keyboard: +/- 1 per press.
#: (Integer value, Integer min, Integer max, Integer w, Integer size) -> Integer
def slider(value, min, max, w: 200, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  range = max - min
  step = range / 20
  if step < 1
    step = 1
  end

  # Render two halves: left (decrement) and right (increment)
  _kui_open_i("_sld", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 2, w, 2, size, 0, 2)

  hover = _kui_pointer_over_i("_sld", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  end
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])

  # Fill bar
  if range > 0
    fill_w = (value - min) * w / range
    if fill_w < 0
      fill_w = 0
    end
    if fill_w > w
      fill_w = w
    end
    if fill_w > 0
      _kui_open_i("_sldf", id)
      _kui_layout(0, 0, 0, 0, 0, 0, 2, fill_w, 2, size, 0, 0)
      if focused == 1
        _kui_set_bg(KUITheme.c[9], KUITheme.c[10], KUITheme.c[11])
      else
        _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
      end
      _kui_close
    end
  end

  _kui_close

  # Click: detect left half vs right half using two invisible zones
  lid = kui_auto_id
  _kui_open_i("_sldl", lid)
  half_w = w / 2
  _kui_layout(0, 0, 0, 0, 0, 0, 2, half_w, 2, 0, 0, 0)
  _kui_close

  rid = kui_auto_id
  _kui_open_i("_sldr", rid)
  _kui_layout(0, 0, 0, 0, 0, 0, 2, half_w, 2, 0, 0, 0)
  _kui_close

  # Click on slider → increment by step
  if _kui_was_clicked_i("_sld", id) == 1
    _kui_set_focus_current
    new_val = value + step
    if new_val > max
      new_val = max
    end
    if new_val != value
      yield(new_val)
    end
  end

  # Keyboard control
  if focused == 1
    key = kui_key_pressed
    if key == KUI_KEY_RIGHT
      new_val = value + step
      if new_val > max
        new_val = max
      end
      if new_val != value
        yield(new_val)
      end
    end
    if key == KUI_KEY_LEFT
      new_val = value - step
      if new_val < min
        new_val = min
      end
      if new_val != value
        yield(new_val)
      end
    end
  end

  _kui_register_focusable
  return 0
end

# ════════════════════════════════════════════
# Textarea (Multi-line Text Input)
# ════════════════════════════════════════════

# Multi-line text input using consecutive text buffers.
# first_buf_id: first buffer ID (uses first_buf_id .. first_buf_id+lines-1).
# active_line: current cursor line (caller manages, 0-based).
# Yields new active_line on Up/Down navigation.
#: (Integer first_buf_id, Integer active_line, Integer lines, Integer w, Integer size) -> Integer
def textarea(first_buf_id, active_line, lines: 4, w: 40, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused

  if _kui_was_clicked_i("_ta", id) == 1
    _kui_set_focus_current
  end
  _kui_register_focusable

  if focused == 1
    cur_buf = first_buf_id + active_line

    ch = _kui_char_pressed
    while ch >= 32
      _kui_textbuf_putchar(cur_buf, ch)
      ch = _kui_char_pressed
    end

    key = kui_key_pressed
    if key == KUI_KEY_BACKSPACE
      _kui_textbuf_backspace(cur_buf)
    end
    if key == KUI_KEY_DELETE
      _kui_textbuf_delete(cur_buf)
    end
    if key == KUI_KEY_LEFT
      _kui_textbuf_cursor_left(cur_buf)
    end
    if key == KUI_KEY_RIGHT
      _kui_textbuf_cursor_right(cur_buf)
    end
    if key == KUI_KEY_HOME
      _kui_textbuf_cursor_home(cur_buf)
    end
    if key == KUI_KEY_END
      _kui_textbuf_cursor_end(cur_buf)
    end
    if key == KUI_KEY_UP
      if active_line > 0
        yield(active_line - 1)
      end
    end
    if key == KUI_KEY_DOWN
      if active_line < lines - 1
        yield(active_line + 1)
      end
    end
  end

  # Render
  _kui_open_i("_ta", id)
  hp = size / 2
  vp = size / 4
  th = (size + vp) * lines + vp * 2 + 4
  _kui_layout(1, hp, hp, vp, vp, 0, 2, w, 2, th, 0, 0)
  if focused == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    _kui_set_border(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  else
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
    _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  end

  line = 0
  while line < lines
    buf = first_buf_id + line
    buf_len = _kui_textbuf_len(buf)
    lid = kui_auto_id
    _kui_open_i("_tal", lid)
    _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)

    if focused == 1
      if line == active_line
        cur = _kui_textbuf_cursor_pos(buf)
        if cur > 0
          _kui_textbuf_render_range(buf, 0, cur, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
        end
        blink = (KUIState.ids[1] / 15) % 2
        if blink == 0
          _kui_text_color("|", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
        else
          _kui_text_color(" ", size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
        end
        if cur < buf_len
          _kui_textbuf_render_range(buf, cur, buf_len, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
        end
      else
        if buf_len > 0
          _kui_textbuf_render(buf, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
        else
          _kui_text_color(" ", size, KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
        end
      end
    else
      if buf_len > 0
        _kui_textbuf_render(buf, size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
      else
        _kui_text_color(" ", size, KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
      end
    end

    _kui_close
    line = line + 1
  end

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Switch (Enhanced Toggle)
# ════════════════════════════════════════════

# Visual switch — [O  ] / [  O] with track and knob.
# on: 1 = on, 0 = off. Yields when toggled.
#: (String text, Integer on, Integer size) -> Integer
def switch(text, on, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_sw", id)
  _kui_layout(0, 4, 8, 2, 2, 6, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_sw", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
  end

  # Track
  sid = kui_auto_id
  _kui_open_i("_swt", sid)
  _kui_layout(0, 2, 2, 2, 2, 0, 2, size * 2, 2, size, 0, 2)
  if on == 1
    _kui_set_bg(KUITheme.c[24], KUITheme.c[25], KUITheme.c[26])
  else
    _kui_set_bg(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  end

  # Spacer + knob for position
  if on == 1
    kid = kui_auto_id
    _kui_open_i("_sws", kid)
    _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)
    _kui_close
  end
  kid2 = kui_auto_id
  _kui_open_i("_swk", kid2)
  _kui_layout(0, 0, 0, 0, 0, 0, 2, size - 4, 2, size - 4, 0, 0)
  _kui_set_bg(255, 255, 255)
  _kui_close
  if on == 0
    kid3 = kui_auto_id
    _kui_open_i("_sws2", kid3)
    _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)
    _kui_close
  end

  _kui_close

  _kui_text(text, size)
  _kui_close

  if _kui_was_clicked_i("_sw", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# ════════════════════════════════════════════
# Rating Stars
# ════════════════════════════════════════════

# Star rating input. Yields new value on click/arrow key.
# value: 0 = none, 1-max.
#: (Integer value, Integer max, Integer size) -> Integer
def rating(value, max, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_rat", id)
  _kui_layout(0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2)

  if focused == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  end

  star = 1
  while star <= max
    sid = kui_auto_id
    _kui_open_i("_rs", sid)
    _kui_layout(0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2)
    if star <= value
      _kui_text_color("*", size, KUITheme.c[35], KUITheme.c[36], KUITheme.c[37])
    else
      _kui_text_color("*", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
    end
    _kui_close
    if _kui_was_clicked_i("_rs", sid) == 1
      yield(star)
    end
    star = star + 1
  end

  _kui_close

  if focused == 1
    key = kui_key_pressed
    if key == KUI_KEY_RIGHT
      new_val = value + 1
      if new_val > max
        new_val = max
      end
      if new_val != value
        yield(new_val)
      end
    end
    if key == KUI_KEY_LEFT
      new_val = value - 1
      if new_val < 0
        new_val = 0
      end
      if new_val != value
        yield(new_val)
      end
    end
  end

  _kui_register_focusable
  return 0
end

# ════════════════════════════════════════════
# Color Picker (3 sliders + preview)
# ════════════════════════════════════════════

# Simple RGB color picker. Yields (component, new_value) on change.
# component: 0=r, 1=g, 2=b. new_value: 0-255.
#: (Integer r, Integer g, Integer b, Integer w) -> Integer
def color_picker(r, g, b, w: 200)
  id = kui_auto_id
  _kui_open_i("_cpk", id)
  _kui_layout(1, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0)

  # Preview box
  pid = kui_auto_id
  _kui_open_i("_cpv", pid)
  _kui_layout(0, 0, 0, 0, 0, 0, 2, w, 2, 24, 0, 0)
  _kui_set_bg(r, g, b)
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  _kui_close

  # R
  hpanel gap: 4 do
    _kui_text_color("R", 14, 220, 80, 80)
    slider r, 0, 255, w: w - 30, size: 12 do |nv|
      yield(0, nv)
    end
  end
  # G
  hpanel gap: 4 do
    _kui_text_color("G", 14, 80, 200, 80)
    slider g, 0, 255, w: w - 30, size: 12 do |nv|
      yield(1, nv)
    end
  end
  # B
  hpanel gap: 4 do
    _kui_text_color("B", 14, 80, 120, 220)
    slider b, 0, 255, w: w - 30, size: 12 do |nv|
      yield(2, nv)
    end
  end

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Date Picker (3 steppers)
# ════════════════════════════════════════════

# Simple date picker. Yields (component, delta) on change.
# component: 0=year, 1=month, 2=day. delta: -1 or +1.
#: (Integer year, Integer month, Integer day) -> Integer
def date_picker(year, month, day)
  id = kui_auto_id
  _kui_open_i("_dpk", id)
  _kui_layout(0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 2)

  number_stepper year, 1900, 2100, size: 14 do |delta|
    yield(0, delta)
  end
  _kui_text_color("/", 14, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  number_stepper month, 1, 12, size: 14 do |delta|
    yield(1, delta)
  end
  _kui_text_color("/", 14, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  number_stepper day, 1, 31, size: 14 do |delta|
    yield(2, delta)
  end

  _kui_close
  return 0
end
