# frozen_string_literal: true

# KUI Overlay Widgets — accordion, dropdown, tooltip, toast, dialogs
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Accordion / Collapsible Section
# ════════════════════════════════════════════

# Collapsible section with toggle header.
# open: 1 = expanded, 0 = collapsed.
# Yields :toggle when header clicked, :content for section body when open.
#: (String title, Integer open, Integer size) -> Integer
def accordion(title, open, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_acc", id)
  _kui_layout(0, 8, 8, 4, 4, 4, 1, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_acc", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
    end
  end

  if open == 1
    _kui_text_color("v ", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  else
    _kui_text_color("> ", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  end
  _kui_text(title, size)
  _kui_close

  if _kui_was_clicked_i("_acc", id) == 1
    yield(:toggle)
  end
  _kui_register_focusable

  if open == 1
    aid = kui_auto_id
    _kui_open_i("_acb", aid)
    _kui_layout(1, 16, 8, 4, 4, 4, 1, 0, 0, 0, 0, 0)
    yield(:content)
    _kui_close
  end

  return 0
end

# ════════════════════════════════════════════
# Dropdown / Select
# ════════════════════════════════════════════

# Dropdown trigger — click to expand options panel below.
# Only one dropdown open at a time (managed via KUIWidgetState.s[8]).
# selected_text: label shown on the trigger button.
# User yields dropdown_item calls inside the block.
#: (String selected_text, Integer size) -> Integer
def dropdown(selected_text, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  is_open = 0
  if KUIWidgetState.s[8] == id
    is_open = 1
  end

  # Trigger button
  _kui_open_i("_dd", id)
  _kui_layout(0, 8, 8, 4, 4, 4, 0, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_dd", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    else
      _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
    end
  end
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])

  _kui_text(selected_text, size)
  if is_open == 1
    _kui_text_color(" ^", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  else
    _kui_text_color(" v", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  end
  _kui_close

  # Toggle on click
  if _kui_was_clicked_i("_dd", id) == 1
    if is_open == 1
      KUIWidgetState.s[8] = 0
    else
      KUIWidgetState.s[8] = id
    end
  end
  _kui_register_focusable

  # Options panel — inline below trigger when open
  if KUIWidgetState.s[8] == id
    oid = kui_auto_id
    _kui_open_i("_ddo", oid)
    _kui_layout(1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0)
    _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
    _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
    yield
    _kui_close
  end

  return 0
end

# Single item inside a dropdown.
# Yields when clicked (and auto-closes the dropdown).
#: (String text, Integer size) -> Integer
def dropdown_item(text, size: 16)
  id = kui_auto_id
  focused = _kui_is_focused
  _kui_open_i("_ddi", id)
  _kui_layout(0, 8, 8, 2, 2, 0, 1, 0, 0, 0, 0, 2)

  hover = _kui_pointer_over_i("_ddi", id)
  if hover == 1
    _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
  else
    if focused == 1
      _kui_set_bg(KUITheme.c[15], KUITheme.c[16], KUITheme.c[17])
    end
  end
  _kui_text(text, size)
  _kui_close

  if _kui_was_clicked_i("_ddi", id) == 1
    KUIWidgetState.s[8] = 0
    yield
  end
  _kui_register_focusable
  return 0
end

# ════════════════════════════════════════════
# Tooltip
# ════════════════════════════════════════════

# Tooltip wrapper — shows hint text below the wrapped content on hover/focus.
# Usage:
#   with_tooltip "Click to save" do
#     button "Save" do ... end
#   end
#: (String hint_text, Integer size) -> Integer
def with_tooltip(hint_text, size: 12)
  id = kui_auto_id
  _kui_open_i("_ttp", id)
  _kui_layout(1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0)
  yield
  hover = _kui_pointer_over_i("_ttp", id)
  if hover == 1
    _kui_text_color(hint_text, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  end
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Toast / Snackbar
# ════════════════════════════════════════════

# Toast constants
KUI_TOAST_INFO = 0
KUI_TOAST_SUCCESS = 1
KUI_TOAST_DANGER = 2
KUI_TOAST_WARNING = 3

# Activate a toast slot.
# slot: 0-3, duration: frames to show (60 = ~1 sec at 60fps).
# type: KUI_TOAST_INFO / SUCCESS / DANGER / WARNING.
#: (Integer slot, Integer duration, Integer type) -> Integer
def kui_show_toast(slot, duration: 180, type: 0)
  if slot < 0
    return 0
  end
  if slot > 3
    return 0
  end
  base = 16 + slot * 4
  KUIWidgetState.s[base] = 1
  KUIWidgetState.s[base + 1] = KUIState.ids[1]
  KUIWidgetState.s[base + 2] = duration
  KUIWidgetState.s[base + 3] = type
  return 0
end

# Check if a toast slot is currently active.
# Auto-expires based on duration. Returns 1 if active, 0 if not.
#: (Integer slot) -> Integer
def kui_toast_active(slot)
  if slot < 0
    return 0
  end
  if slot > 3
    return 0
  end
  base = 16 + slot * 4
  if KUIWidgetState.s[base] == 0
    return 0
  end
  elapsed = KUIState.ids[1] - KUIWidgetState.s[base + 1]
  if elapsed > KUIWidgetState.s[base + 2]
    KUIWidgetState.s[base] = 0
    return 0
  end
  return 1
end

# Dismiss a toast slot immediately.
#: (Integer slot) -> Integer
def kui_dismiss_toast(slot)
  if slot < 0
    return 0
  end
  if slot > 3
    return 0
  end
  base = 16 + slot * 4
  KUIWidgetState.s[base] = 0
  return 0
end

# Render a toast notification.
# Only visible if the slot is active (auto-expires).
# message: text to display.
#: (Integer slot, String message, Integer size) -> Integer
def toast(slot, message, size: 14)
  if kui_toast_active(slot) == 0
    return 0
  end
  base = 16 + slot * 4
  type = KUIWidgetState.s[base + 3]

  id = kui_auto_id
  _kui_open_i("_tst", id)
  _kui_layout(0, 12, 12, 6, 6, 4, 0, 0, 0, 0, 0, 2)

  if type == KUI_TOAST_INFO
    _kui_set_bg(KUITheme.c[32], KUITheme.c[33], KUITheme.c[34])
  end
  if type == KUI_TOAST_SUCCESS
    _kui_set_bg(KUITheme.c[24], KUITheme.c[25], KUITheme.c[26])
  end
  if type == KUI_TOAST_DANGER
    _kui_set_bg(KUITheme.c[27], KUITheme.c[28], KUITheme.c[29])
  end
  if type == KUI_TOAST_WARNING
    _kui_set_bg(KUITheme.c[35], KUITheme.c[36], KUITheme.c[37])
  end

  _kui_text_color(message, size, 255, 255, 255)
  _kui_close
  return 0
end

# Render all active toasts in a vertical stack.
# Call this in your draw function to show toasts at a desired location.
# User should position the toast_stack inside their layout.
#: () -> Integer
def toast_stack
  id = kui_auto_id
  _kui_open_i("_tss", id)
  _kui_layout(1, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Context Menu
# ════════════════════════════════════════════

# Context menu — floating options panel.
# visible: 1 to show, 0 to hide (caller manages visibility).
# Yields block where user renders menu items (use dropdown_item).
#: (Integer visible, Integer w) -> Integer
def context_menu(visible, w: 150)
  if visible == 0
    return 0
  end
  id = kui_auto_id
  _kui_open_i("_ctx", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, w, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  _kui_floating(0, 0, 200)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Alert Dialog
# ════════════════════════════════════════════

# Alert dialog — modal with title, message, and OK button.
# Yields when OK is clicked.
#: (String title, String message, Integer w, Integer h) -> Integer
def alert_dialog(title, message, w: 400, h: 200)
  modal w, h, pad: 16, gap: 8 do
    label title, size: 20
    divider
    label message, size: 16
    spacer
    hpanel gap: 8 do
      spacer
      button " OK ", size: 16 do
        yield
      end
      spacer
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Confirm Dialog
# ════════════════════════════════════════════

# Confirm dialog — modal with title, message, and Confirm/Cancel buttons.
# Yields :confirm or :cancel.
#: (String title, String message, Integer w, Integer h) -> Integer
def confirm_dialog(title, message, w: 400, h: 200)
  modal w, h, pad: 16, gap: 8 do
    label title, size: 20
    divider
    label message, size: 16
    spacer
    hpanel gap: 8 do
      spacer
      button " OK ", size: 16 do
        yield(:confirm)
      end
      button " Cancel ", size: 16 do
        yield(:cancel)
      end
      spacer
    end
  end
  return 0
end
