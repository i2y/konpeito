# rbs_inline: enabled
require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

# @rbs module AppState
# @rbs   @s: NativeArray[Integer, 4]
# @rbs end

#: () -> Integer
def draw
  vpanel pad: 16 do
    label "Hello KUI", size: 24
  end
  return 0
end

#: () -> Integer
def main
  kui_init("Minimal", 400, 300)
  kui_theme_dark
  AppState.s[0] = 0

  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end

  kui_destroy
  return 0
end

main
