# KUI Counter — GUI version (Clay + Raylib)
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_counter/counter_gui \
#     examples/kui_counter/counter_gui.rb
#
# Run:
#   ./examples/kui_counter/counter_gui
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

# @rbs module AppState
# @rbs   @s: NativeArray[Integer, 4]
# @rbs end

#: () -> Integer
def draw
  vpanel pad: 24, gap: 16 do
    header pad: 12 do
      label "Counter App", size: 28, r: 255, g: 255, b: 255
    end

    spacer

    cpanel gap: 8 do
      label "Current Count:", size: 20

      hpanel gap: 4 do
        spacer
        label_num AppState.s[0], size: 36, r: 100, g: 200, b: 255
        spacer
      end
    end

    spacer

    hpanel gap: 12 do
      spacer
      button "  -  ", size: 20 do
        AppState.s[0] = AppState.s[0] - 1
      end
      button " Reset ", size: 20 do
        AppState.s[0] = 0
      end
      button "  +  ", size: 20 do
        AppState.s[0] = AppState.s[0] + 1
      end
      spacer
    end

    spacer

    divider

    footer do
      label "KUI Framework Demo", size: 14, r: 120, g: 120, b: 140
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("KUI Counter", 450, 350)
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
