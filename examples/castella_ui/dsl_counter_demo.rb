# Castella UI - DSL Counter Demo
#
# Same counter as framework_counter.rb, but using the block-based DSL.
# Demonstrates:
# - column/row/text/button DSL functions
# - Keyword arguments for styling (padding:, spacing:, font_size:, color:, align:, etc.)
# - button(label) { block } for inline click handlers
# - Reactive State with auto-rebuild
#
# Run: cd examples/castella_ui && bash run.sh dsl_counter_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

# ===== Counter Component =====
# Uses the block-based DSL with keyword arguments.

class DslCounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    column(padding: 16.0, spacing: 8.0) {
      text "Count: #{@count}", font_size: 32.0, color: 0xFFC0CAF5, align: :center
      row(spacing: 8.0) {
        button(" - ") { @count -= 1 }
        button(" + ") { @count += 1 }
      }
    }
  end
end

# ===== Launch =====
frame = JWMFrame.new("Castella DSL Counter", 400, 300)
app = App.new(frame, DslCounterComponent.new)
app.run
