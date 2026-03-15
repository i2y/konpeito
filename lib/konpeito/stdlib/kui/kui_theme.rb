# frozen_string_literal: true

# KUI Theme System — GC-free color palette via NativeArray
#
# Theme color slots (KUITheme.c[0..47]):
#   [0-2]   bg        — background
#   [3-5]   fg        — foreground (text)
#   [6-8]   primary   — primary accent (buttons, links)
#   [9-11]  secondary — secondary accent
#   [12-14] border    — borders / dividers
#   [15-17] hover     — hover highlight
#   [18-20] surface   — card / panel surface
#   [21-23] muted     — muted / disabled text
#   [24-26] success   — success / positive
#   [27-29] danger    — danger / negative
#   [30]    corner_r  — default corner radius (GUI only, ignored in TUI)
#   [31]    font_id   — default font ID (GUI only, 0 for TUI)
#   [32-34] info      — informational (blue indicator)
#   [35-37] warning   — warning (orange/yellow)
#   [38-40] surface2  — secondary surface (alternative panel bg)
#   [41-43] accent    — accent color (highlight, badge)
#   [44-47] reserved
#
# rbs_inline: enabled

# @rbs module KUITheme
# @rbs   @c: NativeArray[Integer, 48]
# @rbs end

# @rbs module KUIState
# @rbs   @ids: NativeArray[Integer, 4]
# @rbs end

# Text buffer state for text_input widgets (32 buffers x 256 chars)
# @rbs module KUITextBuf
# @rbs   @b: NativeArray[Integer, 8192]
# @rbs   @s: NativeArray[Integer, 96]
# @rbs end
# KUITextBuf.s slots per buffer (id * 3 + offset):
#   [0] = length
#   [1] = cursor position
#   [2] = max length (set on init)

# ── Dark Theme ──

#: () -> Integer
def kui_theme_dark
  # bg: dark indigo
  KUITheme.c[0] = 30
  KUITheme.c[1] = 30
  KUITheme.c[2] = 46
  # fg: white
  KUITheme.c[3] = 240
  KUITheme.c[4] = 240
  KUITheme.c[5] = 245
  # primary: soft blue
  KUITheme.c[6] = 100
  KUITheme.c[7] = 120
  KUITheme.c[8] = 220
  # secondary: teal
  KUITheme.c[9] = 80
  KUITheme.c[10] = 200
  KUITheme.c[11] = 180
  # border: subtle gray
  KUITheme.c[12] = 70
  KUITheme.c[13] = 70
  KUITheme.c[14] = 85
  # hover: lighter surface
  KUITheme.c[15] = 60
  KUITheme.c[16] = 60
  KUITheme.c[17] = 90
  # surface: slightly lighter than bg
  KUITheme.c[18] = 42
  KUITheme.c[19] = 42
  KUITheme.c[20] = 58
  # muted: dim text
  KUITheme.c[21] = 120
  KUITheme.c[22] = 120
  KUITheme.c[23] = 135
  # success: green
  KUITheme.c[24] = 80
  KUITheme.c[25] = 200
  KUITheme.c[26] = 100
  # danger: red
  KUITheme.c[27] = 220
  KUITheme.c[28] = 80
  KUITheme.c[29] = 80
  # corner radius (pixels for GUI, ignored in TUI)
  KUITheme.c[30] = 6
  # font_id: preserve current (don't reset loaded font)
  # info: blue
  KUITheme.c[32] = 80
  KUITheme.c[33] = 160
  KUITheme.c[34] = 240
  # warning: orange
  KUITheme.c[35] = 230
  KUITheme.c[36] = 160
  KUITheme.c[37] = 50
  # surface2: darker surface
  KUITheme.c[38] = 36
  KUITheme.c[39] = 36
  KUITheme.c[40] = 52
  # accent: purple
  KUITheme.c[41] = 160
  KUITheme.c[42] = 100
  KUITheme.c[43] = 220
  return 0
end

# ── Light Theme ──

#: () -> Integer
def kui_theme_light
  # bg: near white
  KUITheme.c[0] = 245
  KUITheme.c[1] = 245
  KUITheme.c[2] = 248
  # fg: dark gray
  KUITheme.c[3] = 30
  KUITheme.c[4] = 30
  KUITheme.c[5] = 35
  # primary: blue
  KUITheme.c[6] = 60
  KUITheme.c[7] = 100
  KUITheme.c[8] = 200
  # secondary: teal
  KUITheme.c[9] = 40
  KUITheme.c[10] = 160
  KUITheme.c[11] = 140
  # border: light gray
  KUITheme.c[12] = 200
  KUITheme.c[13] = 200
  KUITheme.c[14] = 210
  # hover: lighter highlight
  KUITheme.c[15] = 230
  KUITheme.c[16] = 230
  KUITheme.c[17] = 240
  # surface: white
  KUITheme.c[18] = 255
  KUITheme.c[19] = 255
  KUITheme.c[20] = 255
  # muted: medium gray
  KUITheme.c[21] = 140
  KUITheme.c[22] = 140
  KUITheme.c[23] = 150
  # success: green
  KUITheme.c[24] = 40
  KUITheme.c[25] = 160
  KUITheme.c[26] = 60
  # danger: red
  KUITheme.c[27] = 200
  KUITheme.c[28] = 50
  KUITheme.c[29] = 50
  # corner radius
  KUITheme.c[30] = 6
  # font_id: preserve current (don't reset loaded font)
  # info: blue
  KUITheme.c[32] = 40
  KUITheme.c[33] = 120
  KUITheme.c[34] = 220
  # warning: orange
  KUITheme.c[35] = 200
  KUITheme.c[36] = 140
  KUITheme.c[37] = 30
  # surface2: light gray
  KUITheme.c[38] = 235
  KUITheme.c[39] = 235
  KUITheme.c[40] = 240
  # accent: purple
  KUITheme.c[41] = 130
  KUITheme.c[42] = 70
  KUITheme.c[43] = 200
  return 0
end

# ── ID Management ──

#: () -> Integer
def kui_reset_ids
  KUIState.ids[0] = 0
  return 0
end

#: () -> Integer
def kui_auto_id
  KUIState.ids[0] = KUIState.ids[0] + 1
  return KUIState.ids[0]
end
