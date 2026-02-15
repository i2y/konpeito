# Castella UI - Input + MultilineInput Demo with IME Support
#
# Tests:
# - Single-line Input with IME, selection, clipboard
# - MultilineInput with IME, selection, clipboard, word wrap, scrolling
# - InputState / MultilineInputState persist across Component rebuilds
# Run: cd examples/castella_ui && bash run.sh input_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

class InputDemo < Component
  def initialize
    super
    @status = state("")
    # InputState / MultilineInputState persist across Component rebuilds.
    # When @status.set() triggers a rebuild, the Input/MultilineInput widgets
    # are destroyed and recreated, but the state objects survive in @input1_state etc.
    @input1_state = InputState.new("Type here (Tab to next)...")
    @input2_state = InputState.new("Second field...")
    @mli1_state = MultilineInputState.new("Type multiple lines here.\nPress Enter for new lines.\nTry Japanese input (IME)!")
    @mli2_state = MultilineInputState.new("No word wrap mode.\nLong lines will extend beyond the visible area without breaking.")
  end

  def view
    Column(
      Text("Input & MultilineInput Demo").font_size(18.0).color(0xFFC0CAF5),
      Text("IME, Selection, Clipboard (Cmd+C/V/X/A) supported").font_size(12.0).color(0xFF565F89),
      Divider(),

      Text("Single-line Input:").font_size(14.0).color(0xFFC0CAF5),
      Input.new(@input1_state).tab_index(1).on_change { |text|
        @status.set("Input: " + text)
      },
      Spacer().fixed_height(4.0),

      Text("Another Input:").font_size(14.0).color(0xFFC0CAF5),
      Input.new(@input2_state).tab_index(2),
      Spacer().fixed_height(8.0),

      Divider(),
      Text("MultilineInput (word wrap):").font_size(14.0).color(0xFFC0CAF5),
      MultilineInput.new(@mli1_state).font_size(14.0).wrap_text(true).fixed_height(150.0).tab_index(3).on_change { |text|
        lines = 1
        i = 0
        while i < text.length
          if text[i] == "\n"
            lines = lines + 1
          end
          i = i + 1
        end
        @status.set("Lines: " + lines.to_s)
      },

      Spacer().fixed_height(8.0),
      Divider(),
      Text("MultilineInput (no wrap):").font_size(14.0).color(0xFFC0CAF5),
      MultilineInput.new(@mli2_state).font_size(14.0).wrap_text(false).fixed_height(100.0).tab_index(4),

      Spacer().fixed_height(8.0),
      Divider(),
      Text(@status.value).font_size(12.0).color(0xFF9ECE6A)
    ).scrollable.spacing(6.0).padding(16.0, 16.0, 16.0, 16.0)
  end
end

frame = JWMFrame.new("Input Demo", 500, 600)
app = App.new(frame, InputDemo.new)
app.run
