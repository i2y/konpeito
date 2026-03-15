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

# ── Tokyo Night Theme (Castella default) ──

#: () -> Integer
def kui_theme_tokyo_night
  # bg: #1A1B26
  KUITheme.c[0] = 26
  KUITheme.c[1] = 27
  KUITheme.c[2] = 38
  # fg: #C0CAF5
  KUITheme.c[3] = 192
  KUITheme.c[4] = 202
  KUITheme.c[5] = 245
  # primary: #7AA2F7
  KUITheme.c[6] = 122
  KUITheme.c[7] = 162
  KUITheme.c[8] = 247
  # secondary: #BB9AF7
  KUITheme.c[9] = 187
  KUITheme.c[10] = 154
  KUITheme.c[11] = 247
  # border: #414868
  KUITheme.c[12] = 65
  KUITheme.c[13] = 72
  KUITheme.c[14] = 104
  # hover: #24283B lightened
  KUITheme.c[15] = 50
  KUITheme.c[16] = 54
  KUITheme.c[17] = 75
  # surface: #24283B
  KUITheme.c[18] = 36
  KUITheme.c[19] = 40
  KUITheme.c[20] = 59
  # muted: #565F89
  KUITheme.c[21] = 86
  KUITheme.c[22] = 95
  KUITheme.c[23] = 137
  # success: #9ECE6A
  KUITheme.c[24] = 158
  KUITheme.c[25] = 206
  KUITheme.c[26] = 106
  # danger: #F7768E
  KUITheme.c[27] = 247
  KUITheme.c[28] = 118
  KUITheme.c[29] = 142
  # corner radius
  KUITheme.c[30] = 6
  # info: #7AA2F7
  KUITheme.c[32] = 122
  KUITheme.c[33] = 162
  KUITheme.c[34] = 247
  # warning: #E0AF68
  KUITheme.c[35] = 224
  KUITheme.c[36] = 175
  KUITheme.c[37] = 104
  # surface2: #1A1B26 lightened
  KUITheme.c[38] = 32
  KUITheme.c[39] = 33
  KUITheme.c[40] = 48
  # accent: #BB9AF7
  KUITheme.c[41] = 187
  KUITheme.c[42] = 154
  KUITheme.c[43] = 247
  return 0
end

# ── Nord Theme ──

#: () -> Integer
def kui_theme_nord
  # bg: #2E3440
  KUITheme.c[0] = 46
  KUITheme.c[1] = 52
  KUITheme.c[2] = 64
  # fg: #ECEFF4
  KUITheme.c[3] = 236
  KUITheme.c[4] = 239
  KUITheme.c[5] = 244
  # primary: #88C0D0
  KUITheme.c[6] = 136
  KUITheme.c[7] = 192
  KUITheme.c[8] = 208
  # secondary: #81A1C1
  KUITheme.c[9] = 129
  KUITheme.c[10] = 161
  KUITheme.c[11] = 193
  # border: #4C566A
  KUITheme.c[12] = 76
  KUITheme.c[13] = 86
  KUITheme.c[14] = 106
  # hover: #434C5E
  KUITheme.c[15] = 67
  KUITheme.c[16] = 76
  KUITheme.c[17] = 94
  # surface: #3B4252
  KUITheme.c[18] = 59
  KUITheme.c[19] = 66
  KUITheme.c[20] = 82
  # muted: #D8DEE9
  KUITheme.c[21] = 216
  KUITheme.c[22] = 222
  KUITheme.c[23] = 233
  # success: #A3BE8C
  KUITheme.c[24] = 163
  KUITheme.c[25] = 190
  KUITheme.c[26] = 140
  # danger: #BF616A
  KUITheme.c[27] = 191
  KUITheme.c[28] = 97
  KUITheme.c[29] = 106
  # corner radius
  KUITheme.c[30] = 4
  # info: #88C0D0
  KUITheme.c[32] = 136
  KUITheme.c[33] = 192
  KUITheme.c[34] = 208
  # warning: #EBCB8B
  KUITheme.c[35] = 235
  KUITheme.c[36] = 203
  KUITheme.c[37] = 139
  # surface2: #3B4252 darkened
  KUITheme.c[38] = 52
  KUITheme.c[39] = 58
  KUITheme.c[40] = 72
  # accent: #5E81AC
  KUITheme.c[41] = 94
  KUITheme.c[42] = 129
  KUITheme.c[43] = 172
  return 0
end

# ── Dracula Theme ──

#: () -> Integer
def kui_theme_dracula
  # bg: #282A36
  KUITheme.c[0] = 40
  KUITheme.c[1] = 42
  KUITheme.c[2] = 54
  # fg: #F8F8F2
  KUITheme.c[3] = 248
  KUITheme.c[4] = 248
  KUITheme.c[5] = 242
  # primary: #BD93F9
  KUITheme.c[6] = 189
  KUITheme.c[7] = 147
  KUITheme.c[8] = 249
  # secondary: #FF79C6
  KUITheme.c[9] = 255
  KUITheme.c[10] = 121
  KUITheme.c[11] = 198
  # border: #6272A4
  KUITheme.c[12] = 98
  KUITheme.c[13] = 114
  KUITheme.c[14] = 164
  # hover: #44475A lightened
  KUITheme.c[15] = 78
  KUITheme.c[16] = 81
  KUITheme.c[17] = 104
  # surface: #44475A
  KUITheme.c[18] = 68
  KUITheme.c[19] = 71
  KUITheme.c[20] = 90
  # muted: #6272A4
  KUITheme.c[21] = 98
  KUITheme.c[22] = 114
  KUITheme.c[23] = 164
  # success: #50FA7B
  KUITheme.c[24] = 80
  KUITheme.c[25] = 250
  KUITheme.c[26] = 123
  # danger: #FF5555
  KUITheme.c[27] = 255
  KUITheme.c[28] = 85
  KUITheme.c[29] = 85
  # corner radius
  KUITheme.c[30] = 6
  # info: #8BE9FD
  KUITheme.c[32] = 139
  KUITheme.c[33] = 233
  KUITheme.c[34] = 253
  # warning: #F1FA8C
  KUITheme.c[35] = 241
  KUITheme.c[36] = 250
  KUITheme.c[37] = 140
  # surface2: #282A36 lightened
  KUITheme.c[38] = 55
  KUITheme.c[39] = 57
  KUITheme.c[40] = 70
  # accent: #FF79C6
  KUITheme.c[41] = 255
  KUITheme.c[42] = 121
  KUITheme.c[43] = 198
  return 0
end

# ── Catppuccin Mocha Theme ──

#: () -> Integer
def kui_theme_catppuccin
  # bg: #1E1E2E
  KUITheme.c[0] = 30
  KUITheme.c[1] = 30
  KUITheme.c[2] = 46
  # fg: #CDD6F4
  KUITheme.c[3] = 205
  KUITheme.c[4] = 214
  KUITheme.c[5] = 244
  # primary: #CBA6F7
  KUITheme.c[6] = 203
  KUITheme.c[7] = 166
  KUITheme.c[8] = 247
  # secondary: #F5C2E7
  KUITheme.c[9] = 245
  KUITheme.c[10] = 194
  KUITheme.c[11] = 231
  # border: #585B70
  KUITheme.c[12] = 88
  KUITheme.c[13] = 91
  KUITheme.c[14] = 112
  # hover: #45475A lightened
  KUITheme.c[15] = 78
  KUITheme.c[16] = 81
  KUITheme.c[17] = 100
  # surface: #313244
  KUITheme.c[18] = 49
  KUITheme.c[19] = 50
  KUITheme.c[20] = 68
  # muted: #A6ADC8
  KUITheme.c[21] = 166
  KUITheme.c[22] = 173
  KUITheme.c[23] = 200
  # success: #A6E3A1
  KUITheme.c[24] = 166
  KUITheme.c[25] = 227
  KUITheme.c[26] = 161
  # danger: #F38BA8
  KUITheme.c[27] = 243
  KUITheme.c[28] = 139
  KUITheme.c[29] = 168
  # corner radius
  KUITheme.c[30] = 8
  # info: #89B4FA
  KUITheme.c[32] = 137
  KUITheme.c[33] = 180
  KUITheme.c[34] = 250
  # warning: #F9E2AF
  KUITheme.c[35] = 249
  KUITheme.c[36] = 226
  KUITheme.c[37] = 175
  # surface2: #45475A
  KUITheme.c[38] = 69
  KUITheme.c[39] = 71
  KUITheme.c[40] = 90
  # accent: #F5C2E7
  KUITheme.c[41] = 245
  KUITheme.c[42] = 194
  KUITheme.c[43] = 231
  return 0
end

# ── Material Light Theme ──

#: () -> Integer
def kui_theme_material
  # bg: #FEFEFE
  KUITheme.c[0] = 254
  KUITheme.c[1] = 254
  KUITheme.c[2] = 254
  # fg: #1C1B1F
  KUITheme.c[3] = 28
  KUITheme.c[4] = 27
  KUITheme.c[5] = 31
  # primary: #6200EE
  KUITheme.c[6] = 98
  KUITheme.c[7] = 0
  KUITheme.c[8] = 238
  # secondary: #03DAC6
  KUITheme.c[9] = 3
  KUITheme.c[10] = 218
  KUITheme.c[11] = 198
  # border: #E0E0E0
  KUITheme.c[12] = 224
  KUITheme.c[13] = 224
  KUITheme.c[14] = 224
  # hover: #E0E0E0
  KUITheme.c[15] = 224
  KUITheme.c[16] = 224
  KUITheme.c[17] = 224
  # surface: #FFFFFF
  KUITheme.c[18] = 255
  KUITheme.c[19] = 255
  KUITheme.c[20] = 255
  # muted: #757575
  KUITheme.c[21] = 117
  KUITheme.c[22] = 117
  KUITheme.c[23] = 117
  # success: #4CAF50
  KUITheme.c[24] = 76
  KUITheme.c[25] = 175
  KUITheme.c[26] = 80
  # danger: #F44336
  KUITheme.c[27] = 244
  KUITheme.c[28] = 67
  KUITheme.c[29] = 54
  # corner radius
  KUITheme.c[30] = 4
  # info: #2196F3
  KUITheme.c[32] = 33
  KUITheme.c[33] = 150
  KUITheme.c[34] = 243
  # warning: #FF9800
  KUITheme.c[35] = 255
  KUITheme.c[36] = 152
  KUITheme.c[37] = 0
  # surface2: #F5F5F5
  KUITheme.c[38] = 245
  KUITheme.c[39] = 245
  KUITheme.c[40] = 245
  # accent: #6200EE
  KUITheme.c[41] = 98
  KUITheme.c[42] = 0
  KUITheme.c[43] = 238
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
