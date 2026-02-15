# Castella UI - Widgets Demo (NativeFrame / SDL3 + Skia Metal)
#
# Same as widgets_demo.rb but uses NativeFrame instead of JWMFrame.
# Tests Slider, Switch, ProgressBar, RadioButtons
# Run: ruby examples/castella_ui/native_widgets_demo.rb

require_relative "../../lib/konpeito/ui/castella_native"

# Global theme
$theme = Theme.new

class WidgetsDemo < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    Column(
      Text("Slider").font_size(16.0).color(0xFFC0CAF5),
      Slider(0.0, 100.0).with_value(50.0),
      Divider(),
      Text("Switch").font_size(16.0).color(0xFFC0CAF5),
      Switch(),
      Divider(),
      Text("Progress (30%)").font_size(16.0).color(0xFFC0CAF5),
      ProgressBar().with_value(0.3),
      Text("Progress (70%)").font_size(16.0).color(0xFFC0CAF5),
      ProgressBar().with_value(0.7).fill_color(0xFF9ECE6A),
      Divider(),
      Text("RadioButtons").font_size(16.0).color(0xFFC0CAF5),
      RadioButtons(["Option A", "Option B", "Option C"])
    ).scrollable.spacing(12.0)
  end
end

frame = NativeFrame.new("Widgets Demo", 400, 500)
app = App.new(frame, WidgetsDemo.new)
app.run
