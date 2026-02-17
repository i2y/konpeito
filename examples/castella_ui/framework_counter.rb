# Castella UI - Framework Counter Demo
#
# This demo exercises the full framework layer:
# - Component + State (reactive UI with auto-rebuild on state change)
# - Column / Row layout with flexible sizing
# - Button widget with hover and click handling
# - Text widget with dynamic content
# - Observer/Observable pattern (State notifies Component)
# - Widget lifecycle (dirty tracking, z-order rendering)
#
# Run: cd examples/castella_ui && bash run.sh framework_counter.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

# ===== Counter Component =====
# Demonstrates: Component, State, view() rebuild, Button events
#
# When the user clicks + or -, State is mutated via += / -=.
# State.notify() triggers Component.on_notify() which sets pending_rebuild.
# On next redraw, Component detaches old view and calls view() again.

class CounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    label = "Count: " + @count.value.to_s

    Column(
      Text(label).font_size(32).color(0xFFC0CAF5).align(TEXT_ALIGN_CENTER),
      Row(
        Button("  -  ").font_size(24).on_click {
          @count -= 1
        },
        Button("  +  ").font_size(24).on_click {
          @count += 1
        }
      )
    )
  end
end

# ===== Launch =====
frame = JWMFrame.new("Castella Counter", 400, 300)
app = App.new(frame, CounterComponent.new)
app.run
