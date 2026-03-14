# KUI Form Demo — TUI version
#
# Demonstrates new KUI widgets:
#   - Text input (single line)
#   - Checkbox, Radio, Toggle
#   - Selectable list
#   - Spinner
#   - Status bar
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_form_demo/form_demo \
#     examples/kui_form_demo/form_demo.rb
#
# Run:
#   ./examples/kui_form_demo/form_demo
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_tui"

# @rbs module FormState
# @rbs   @s: NativeArray[Integer, 16]
# @rbs end
# FormState.s slots:
#   [0] = checkbox 1 (agree to terms)
#   [1] = checkbox 2 (newsletter)
#   [2] = radio selection (0=beginner, 1=intermediate, 2=advanced)
#   [3] = toggle dark mode
#   [4] = list selection index
#   [5] = submitted flag
#   [6] = name buffer id (0)
#   [7] = email buffer id (1)

#: () -> Integer
def draw
  vpanel pad: 1, gap: 0 do
    header pad: 1 do
      spinner size: 1
      label " Registration Form", size: 1, r: 255, g: 255, b: 255
    end

    vpanel pad: 1, gap: 1 do
      # Name input
      label "Name:", size: 1
      text_input 0, w: 30, size: 1

      # Email input
      label "Email:", size: 1
      text_input 1, w: 30, size: 1

      divider

      # Checkboxes
      label "Options:", size: 1
      checkbox "I agree to the terms", FormState.s[0], size: 1 do
        if FormState.s[0] == 0
          FormState.s[0] = 1
        else
          FormState.s[0] = 0
        end
      end
      checkbox "Subscribe to newsletter", FormState.s[1], size: 1 do
        if FormState.s[1] == 0
          FormState.s[1] = 1
        else
          FormState.s[1] = 0
        end
      end

      divider

      # Radio buttons
      label "Experience level:", size: 1
      radio "Beginner", 0, FormState.s[2], size: 1 do
        FormState.s[2] = 0
      end
      radio "Intermediate", 1, FormState.s[2], size: 1 do
        FormState.s[2] = 1
      end
      radio "Advanced", 2, FormState.s[2], size: 1 do
        FormState.s[2] = 2
      end

      divider

      # Toggle
      toggle "Dark mode", FormState.s[3], size: 1 do
        if FormState.s[3] == 0
          FormState.s[3] = 1
          kui_theme_dark
        else
          FormState.s[3] = 0
          kui_theme_light
        end
      end

      spacer

      # Submit
      hpanel gap: 2 do
        spacer
        button " Submit ", size: 1 do
          FormState.s[5] = 1
        end
        button " Clear ", size: 1 do
          FormState.s[0] = 0
          FormState.s[1] = 0
          FormState.s[2] = 0
          FormState.s[5] = 0
          kui_textbuf_clear 0
          kui_textbuf_clear 1
        end
        spacer
      end

      # Status message
      if FormState.s[5] == 1
        label "Form submitted!", size: 1, r: 80, g: 200, b: 100
      end
    end

    status_bar do
      status_left do
        label "[Tab] Navigate  [Enter] Click  [ESC] Quit", size: 1, r: 120, g: 120, b: 140
      end
      status_right do
        label "KUI Form Demo", size: 1, r: 120, g: 120, b: 140
      end
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("KUI Form Demo", 80, 24)
  kui_theme_dark
  FormState.s[3] = 1

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
