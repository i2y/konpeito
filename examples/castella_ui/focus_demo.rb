# Castella UI - Focus Demo
#
# Tests Tab/Shift+Tab focus navigation between Input fields.
# Run: cd examples/castella_ui && bash run.sh focus_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

class FocusDemo < Component
  def initialize
    super
  end

  def view
    Column(
      Text("Focus Navigation Demo").font_size(18.0).color(0xFFC0CAF5),
      Divider(),
      Text("Press Tab / Shift+Tab to cycle between fields:").font_size(13.0).color(0xFF565F89),
      Spacer().fixed_height(8.0),
      Text("Name:").font_size(14.0).color(0xFFC0CAF5),
      Input("Enter your name").tab_index(1),
      Spacer().fixed_height(4.0),
      Text("Email:").font_size(14.0).color(0xFFC0CAF5),
      Input("Enter your email").tab_index(2),
      Spacer().fixed_height(4.0),
      Text("Message:").font_size(14.0).color(0xFFC0CAF5),
      Input("Type a message").tab_index(3),
      Divider(),
      Text("Click an input, then Tab to move forward, Shift+Tab to go back.").font_size(12.0).color(0xFF565F89)
    ).scrollable.spacing(8.0)
  end
end

frame = JWMFrame.new("Focus Demo", 400, 400)
app = App.new(frame, FocusDemo.new)
app.run
