# Minimal timer crash test - 10 second timer
# rbs_inline: enabled

require "kui_gui"

# @rbs module P
# @rbs   @s: NativeArray[Integer, 4]
# @rbs end

#: () -> Integer
def tick
  if P.s[0] == 0
    return 0
  end
  frame = KUIState.ids[1]
  elapsed = frame - P.s[2]
  if elapsed >= 60
    P.s[2] = frame
    if P.s[1] > 0
      P.s[1] = P.s[1] - 1
      P.s[3] = P.s[3] + 1
    else
      P.s[0] = 0
    end
  end
  return 0
end

#: () -> Integer
def draw
  tick
  vpanel pad: 16, gap: 8 do
    label "Timer Test", size: 20
    hpanel gap: 0 do
      label_num P.s[1] / 60, size: 36
      label ":", size: 36
      label_num P.s[1] % 60, size: 36
    end
    progress_bar P.s[3], 10, 200, 8
    if P.s[0] == 0
      button "Start 10s", size: 16 do
        P.s[0] = 1
        P.s[1] = 10
        P.s[2] = KUIState.ids[1]
        P.s[3] = 0
      end
    else
      button "Stop", size: 16 do
        P.s[0] = 0
      end
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("Timer Test", 300, 250)
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 20)
  kui_theme_dark
  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end
  kui_destroy
  return 0
end

main
