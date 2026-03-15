# frozen_string_literal: true

# KUI Data Display Widgets — table, badge, avatar, progress_steps,
# list_section, sortable_header, carousel, timeline, skeleton
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Table / Data Grid
# ════════════════════════════════════════════

# Table header row.
#: (Integer pad) -> Integer
def table_header(pad: 4)
  id = kui_auto_id
  _kui_open_i("_th", id)
  _kui_layout(0, pad, pad, pad, pad, 0, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  yield
  _kui_close
  return 0
end

# Table body row. Alternates background color based on row index.
#: (Integer row_index, Integer pad) -> Integer
def table_row(row_index, pad: 4)
  id = kui_auto_id
  _kui_open_i("_tr", id)
  _kui_layout(0, pad, pad, pad, pad, 0, 1, 0, 0, 0, 0, 2)

  even = row_index % 2
  if even == 0
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  end

  yield
  _kui_close
  return 0
end

# Table cell with fixed width.
#: (Integer w, Integer pad) -> Integer
def table_cell(w, pad: 4)
  id = kui_auto_id
  _kui_open_i("_tc", id)
  _kui_layout(0, pad, pad, 0, 0, 0, 2, w, 0, 0, 0, 2)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Badge / Chip / Tag
# ════════════════════════════════════════════

# Small colored indicator label.
# Uses accent color by default, or custom RGB.
#: (String text, Integer size, Integer r, Integer g, Integer b) -> Integer
def badge(text, size: 12, r: -1, g: -1, b: -1)
  id = kui_auto_id
  _kui_open_i("_bdg", id)
  _kui_layout(0, 6, 6, 2, 2, 0, 0, 0, 0, 0, 2, 2)
  if r >= 0
    _kui_set_bg(r, g, b)
  else
    _kui_set_bg(KUITheme.c[41], KUITheme.c[42], KUITheme.c[43])
  end
  _kui_text_color(text, size, 255, 255, 255)
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Avatar
# ════════════════════════════════════════════

# Square avatar with initials or single character.
# Uses primary color by default.
#: (String text, Integer size, Integer r, Integer g, Integer b) -> Integer
def avatar(text, size: 32, r: -1, g: -1, b: -1)
  id = kui_auto_id
  _kui_open_i("_avt", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, size, 2, size, 2, 2)
  if r >= 0
    _kui_set_bg(r, g, b)
  else
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  end
  _kui_text_color(text, size / 2, 255, 255, 255)
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Progress Steps / Stepper Indicator
# ════════════════════════════════════════════

# Multi-step progress indicator: (1)---(2)---(3)
# current: current step (1-based), total: total steps.
#: (Integer current, Integer total, Integer size) -> Integer
def progress_steps(current, total, size: 14)
  id = kui_auto_id
  _kui_open_i("_ps", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2)

  step = 1
  while step <= total
    if step <= current
      _kui_text_color("(", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
      _kui_draw_num(step, size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
      _kui_text_color(")", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    else
      _kui_text_color("(", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
      _kui_draw_num(step, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
      _kui_text_color(")", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
    end
    if step < total
      _kui_text_color("---", size, KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
    end
    step = step + 1
  end

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# List Section Header
# ════════════════════════════════════════════

# Section header for grouped lists.
#: (String title, Integer size) -> Integer
def list_section(title, size: 14)
  id = kui_auto_id
  _kui_open_i("_ls", id)
  _kui_layout(0, 8, 8, 4, 2, 0, 1, 0, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[38], KUITheme.c[39], KUITheme.c[40])
  _kui_text_color(title, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Sortable Table Header
# ════════════════════════════════════════════

# Clickable table header cell for sorting. Yields on click.
#: (String text, Integer w, Integer col, Integer sort_col, Integer dir, Integer size) -> Integer
def sortable_header(text, w, col, sort_col, dir, size: 14)
  id = kui_auto_id
  _kui_open_i("_sh", id)
  _kui_layout(0, 4, 4, 4, 4, 2, 2, w, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  hover = _kui_pointer_over_i("_sh", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  end
  _kui_text_color(text, size, 255, 255, 255)
  if col == sort_col
    if dir == 0
      _kui_text_color(" ^", size, 255, 255, 200)
    else
      _kui_text_color(" v", size, 255, 255, 200)
    end
  end
  _kui_close
  if _kui_was_clicked_i("_sh", id) == 1
    yield
  end
  return 0
end

# ════════════════════════════════════════════
# Carousel Dots
# ════════════════════════════════════════════

# Page indicator dots for carousel.
#: (Integer active, Integer count, Integer size) -> Integer
def carousel_dots(active, count, size: 12)
  id = kui_auto_id
  _kui_open_i("_cd", id)
  _kui_layout(0, 0, 0, 4, 4, 4, 0, 0, 0, 0, 2, 2)
  dot = 0
  while dot < count
    if dot == active
      _kui_text_color("o", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    else
      _kui_text_color(".", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
    end
    dot = dot + 1
  end
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Timeline
# ════════════════════════════════════════════

# Timeline item with dot indicator.
#: (String text, Integer active, Integer size) -> Integer
def timeline_item(text, active, size: 14)
  id = kui_auto_id
  _kui_open_i("_tl", id)
  _kui_layout(0, 4, 8, 2, 2, 6, 0, 0, 0, 0, 0, 2)
  if active == 1
    _kui_text_color("* ", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    _kui_text(text, size)
  else
    _kui_text_color("* ", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
    _kui_text_color(text, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  end
  _kui_close
  return 0
end

# Timeline connector line between items.
#: () -> Integer
def timeline_connector
  id = kui_auto_id
  _kui_open_i("_tlc", id)
  _kui_layout(0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  _kui_text_color("|", 14, KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Skeleton / Loading Placeholder
# ════════════════════════════════════════════

# Pulsing gray placeholder rectangle.
#: (Integer w, Integer h) -> Integer
def skeleton(w, h)
  id = kui_auto_id
  _kui_open_i("_skl", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 2, w, 2, h, 0, 0)
  phase = (KUIState.ids[1] / 20) % 2
  if phase == 0
    _kui_set_bg(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  else
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  end
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Circular Progress (text)
# ════════════════════════════════════════════

# Percentage-based progress display [75%].
#: (Integer value, Integer max, Integer size) -> Integer
def circular_progress(value, max, size: 16)
  id = kui_auto_id
  pct = 0
  if max > 0
    pct = value * 100 / max
  end
  _kui_open_i("_cp", id)
  _kui_layout(0, 4, 4, 2, 2, 0, 0, 0, 0, 0, 2, 2)
  _kui_text_color("[", size, KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  _kui_draw_num(pct, size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  _kui_text_color("%]", size, KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Image Placeholder
# ════════════════════════════════════════════

# Placeholder for image content — shows [IMG].
#: (Integer texture_id, Integer w, Integer h) -> Integer
def image_placeholder(texture_id, w, h)
  id = kui_auto_id
  _kui_open_i("_img", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, w, 2, h, 2, 2)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  _kui_text_color("[IMG]", 14, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  _kui_close
  return 0
end
