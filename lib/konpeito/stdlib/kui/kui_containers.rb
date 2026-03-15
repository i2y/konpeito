# frozen_string_literal: true

# KUI Styled Containers — card, header, footer, sidebar, modal, tabs, status bar
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Styled Containers
# ════════════════════════════════════════════

# Card — surface-colored panel with border.
#: (Integer pad, Integer gap) -> Integer
def card(pad: 12, gap: 8)
  id = kui_auto_id
  _kui_open_i("_crd", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# Header bar — primary-colored horizontal bar.
#: (Integer pad) -> Integer
def header(pad: 8)
  id = kui_auto_id
  _kui_open_i("_hdr", id)
  _kui_layout(0, pad, pad, pad, pad, 8, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  yield
  _kui_close
  return 0
end

# Footer bar — subtle bottom bar.
#: (Integer pad) -> Integer
def footer(pad: 8)
  id = kui_auto_id
  _kui_open_i("_ftr", id)
  _kui_layout(0, pad, pad, pad, pad, 8, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  yield
  _kui_close
  return 0
end

# Sidebar — fixed-width vertical panel.
#: (Integer w, Integer pad, Integer gap) -> Integer
def sidebar(w, pad: 8, gap: 4)
  id = kui_auto_id
  _kui_open_i("_sb", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 2, w, 1, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Modal / Dialog
# ════════════════════════════════════════════

# Modal overlay — centered floating panel.
# Renders as a floating element with semi-transparent backdrop.
#: (Integer w, Integer h) -> Integer
def modal(w, h, pad: 1, gap: 1)
  id = kui_auto_id

  # Backdrop (full-screen semi-transparent)
  _kui_open_i("_mbg", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 2, 2)
  _kui_set_bg(0, 0, 0)
  _kui_floating(0, 0, 100)

  # Modal content
  _kui_open_i("_mdl", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 2, w, 2, h, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close

  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Tabs
# ════════════════════════════════════════════

# Tab bar — horizontal row of tab buttons.
# active: currently active tab index.
# Yields block where user should call tab_button for each tab.
#: (Integer active) -> Integer
def tab_bar(active)
  id = kui_auto_id
  _kui_open_i("_tb", id)
  _kui_layout(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  yield
  _kui_close
  return 0
end

# Single tab button. Yields when clicked.
#: (String text, Integer index, Integer active, Integer size) -> Integer
def tab_button(text, index, active, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_tbt", id)
  _kui_layout(0, 12, 12, 6, 6, 0, 0, 0, 0, 0, 2, 2)

  if index == active
    _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    _kui_text_color(text, size, 255, 255, 255)
  else
    hover = _kui_pointer_over_i("_tbt", id)
    if hover == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      if focused == 1
        _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
      end
    end
    _kui_text(text, size)
  end

  _kui_close

  if _kui_was_clicked_i("_tbt", id) == 1
    yield
  end
  _kui_register_focusable
  return 0
end

# Tab content panel — shows content for the active tab.
#: (Integer pad, Integer gap) -> Integer
def tab_content(pad: 8, gap: 4)
  id = kui_auto_id
  _kui_open_i("_tcp", id)
  _kui_layout(1, pad, pad, pad, pad, gap, 1, 0, 1, 0, 0, 0)
  _kui_scroll_v
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Status Bar
# ════════════════════════════════════════════

# Status bar — fixed at bottom with left/center/right segments.
#: (Integer pad) -> Integer
def status_bar(pad: 4)
  id = kui_auto_id
  _kui_open_i("_stb", id)
  _kui_layout(0, pad, pad, pad, pad, 0, 1, 0, 0, 0, 0, 2)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  yield
  _kui_close
  return 0
end

# Status bar left segment.
#: () -> Integer
def status_left
  id = kui_auto_id
  _kui_open_i("_stl", id)
  _kui_layout(0, 4, 4, 0, 0, 4, 0, 0, 0, 0, 0, 2)
  yield
  _kui_close
  return 0
end

# Status bar center segment (spacer + content + spacer).
#: () -> Integer
def status_center
  spacer
  id = kui_auto_id
  _kui_open_i("_stc", id)
  _kui_layout(0, 4, 4, 0, 0, 4, 0, 0, 0, 0, 2, 2)
  yield
  _kui_close
  spacer
  return 0
end

# Status bar right segment.
#: () -> Integer
def status_right
  spacer
  id = kui_auto_id
  _kui_open_i("_str", id)
  _kui_layout(0, 4, 4, 0, 0, 4, 0, 0, 0, 0, 0, 2)
  yield
  _kui_close
  return 0
end
