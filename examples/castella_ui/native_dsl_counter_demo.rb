# Castella UI - DSL Counter Demo (NativeFrame / SDL3 + Skia Metal)
#
# Same as dsl_counter_demo.rb but uses NativeFrame instead of JWMFrame.
# Run: ruby examples/castella_ui/native_dsl_counter_demo.rb

require_relative "../../lib/konpeito/ui/castella_native"

# Global theme
$theme = Theme.new

class DslCounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    column(padding: 16.0) {
      spacer
      text "Count: #{@count}", font_size: 32.0, color: 0xFFC0CAF5, align: :center
      spacer.fixed_height(24.0)
      row(spacing: 8.0) {
        spacer
        button(" - ", width: 80.0) { @count -= 1 }
        spacer.fixed_width(24.0)
        button(" + ", width: 80.0) { @count += 1 }
        spacer
      }
      spacer
    }
  end
end

frame = NativeFrame.new("Castella DSL Counter", 400, 300)
app = App.new(frame, DslCounterComponent.new)
app.run
