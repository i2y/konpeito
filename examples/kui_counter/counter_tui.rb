# KUI Counter — TUI version (ClayTUI + termbox2)
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_counter/counter_tui \
#     examples/kui_counter/counter_tui.rb
#
# Run:
#   ./examples/kui_counter/counter_tui
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_tui"

# @rbs module AppState
# @rbs   @s: NativeArray[Integer, 4]
# @rbs end

#: () -> Integer
def draw
  vpanel pad: 2, gap: 1 do
    header pad: 1 do
      label "Counter App", size: 1, r: 255, g: 255, b: 255
    end

    spacer

    cpanel gap: 1 do
      label "Current Count:", size: 1

      hpanel gap: 1 do
        spacer
        label_num AppState.s[0], size: 1, r: 100, g: 200, b: 255
        spacer
      end
    end

    spacer

    hpanel gap: 2 do
      spacer
      button " - ", size: 1 do
        AppState.s[0] = AppState.s[0] - 1
      end
      button " 0 ", size: 1 do
        AppState.s[0] = 0
      end
      button " + ", size: 1 do
        AppState.s[0] = AppState.s[0] + 1
      end
      spacer
    end

    spacer

    divider

    footer do
      label "KUI Framework Demo  [Tab] Navigate  [Enter] Click  [ESC] Quit", size: 1, r: 120, g: 120, b: 140
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("KUI Counter", 80, 24)
  kui_theme_dark
  AppState.s[0] = 0

  while kui_running == 1
    kui_begin_frame
    draw
    _kui_update_focus
    kui_end_frame
  end

  kui_destroy
  return 0
end

main
