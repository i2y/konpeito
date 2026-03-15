# frozen_string_literal: true

# KUI Navigation Widgets — nav_bar, bottom_nav, drawer, bottom_sheet, nav helpers
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Navigation State Helpers
# ════════════════════════════════════════════

# Push a page onto the navigation stack.
# KUIWidgetState.s[12] = depth, s[13] = current, s[14] = back target.
#: (Integer page_id) -> Integer
def kui_nav_push(page_id)
  depth = KUIWidgetState.s[12]
  KUIWidgetState.s[14] = KUIWidgetState.s[13]
  KUIWidgetState.s[13] = page_id
  KUIWidgetState.s[12] = depth + 1
  return 0
end

# Pop back to the previous page.
#: () -> Integer
def kui_nav_pop
  depth = KUIWidgetState.s[12]
  if depth > 0
    KUIWidgetState.s[13] = KUIWidgetState.s[14]
    KUIWidgetState.s[12] = depth - 1
  end
  return 0
end

# Get the current page ID.
#: () -> Integer
def kui_nav_current
  return KUIWidgetState.s[13]
end

# Get the navigation stack depth.
#: () -> Integer
def kui_nav_depth
  return KUIWidgetState.s[12]
end

# ════════════════════════════════════════════
# Navigation Bar
# ════════════════════════════════════════════

# Top navigation bar with optional back button.
# Shows back button when nav depth > 0.
# Yields block for right-side action buttons.
#: (String title, Integer size) -> Integer
def nav_bar(title, size: 20)
  header pad: 8 do
    if KUIWidgetState.s[12] > 0
      button "< Back", size: size - 4 do
        kui_nav_pop
      end
    end
    label title, size: size, r: 255, g: 255, b: 255
    spacer
    yield
  end
  return 0
end

# ════════════════════════════════════════════
# Bottom Navigation Bar
# ════════════════════════════════════════════

# Bottom navigation bar — horizontal row of nav items.
# active: currently active tab index.
#: (Integer active) -> Integer
def bottom_nav(active)
  id = kui_auto_id
  _kui_open_i("_bnv", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# Single item in a bottom navigation bar.
# Yields when clicked.
#: (String text, Integer index, Integer active, Integer size) -> Integer
def bottom_nav_item(text, index, active, size: 14)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_bni", id)
  _kui_layout(1, 8, 8, 4, 4, 2, 1, 0, 0, 0, 2, 2)

  if index == active
    _kui_text_color(text, size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  else
    hover = _kui_pointer_over_i("_bni", id)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      if focused == 1
        _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
      end
    end
    _kui_text_color(text, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  end

  _kui_close

  if _kui_was_clicked_i("_bni", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# ════════════════════════════════════════════
# Drawer (Side Panel)
# ════════════════════════════════════════════

# Side drawer panel — shows/hides based on open flag.
# GUI: fixed sidebar on the left. TUI: same.
# open: 1 = visible, 0 = hidden.
#: (Integer open, Integer w, Integer pad, Integer gap) -> Integer
def drawer(open, w: 200, pad: 8, gap: 4)
  if open == 0
    return 0
  end
  id = kui_auto_id
  _kui_open_i("_drw", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 2, w, 1, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Bottom Sheet
# ════════════════════════════════════════════

# Bottom sheet — panel that appears at the bottom.
# open: 1 = visible, 0 = hidden. h: sheet height.
#: (Integer open, Integer h, Integer pad, Integer gap) -> Integer
def bottom_sheet(open, h: 200, pad: 12, gap: 8)
  if open == 0
    return 0
  end
  id = kui_auto_id
  _kui_open_i("_bsh", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 2, h, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end
