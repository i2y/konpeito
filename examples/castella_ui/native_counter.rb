# Castella UI - Counter Demo (NativeFrame / SDL3 + Skia Metal)
#
# Same as framework_counter.rb but uses NativeFrame instead of JWMFrame.
# Run: ruby examples/castella_ui/native_counter.rb

require_relative "../../lib/konpeito/ui/castella_native"

# Global theme
$theme = Theme.new

# ===== Counter Component =====
class CounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    label = "Count: " + @count.value.to_s

    Column(
      Spacer(),
      Text(label).font_size(32).color(0xFFC0CAF5).align(TEXT_ALIGN_CENTER),
      Spacer().fixed_height(24.0),
      Row(
        Spacer(),
        Button("  -  ").font_size(24).on_click {
          @count -= 1
        },
        Spacer().fixed_width(24.0),
        Button("  +  ").font_size(24).on_click {
          @count += 1
        },
        Spacer()
      ).fixed_height(60.0),
      Spacer()
    )
  end
end

# ===== Launch =====
frame = NativeFrame.new("Castella Counter", 400, 300)
app = App.new(frame, CounterComponent.new)
app.run
