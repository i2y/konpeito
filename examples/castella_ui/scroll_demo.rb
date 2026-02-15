# Castella UI - Scroll Demo
#
# Tests scroll wheel functionality with a long list of items.
# Run: cd examples/castella_ui && bash run.sh scroll_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

class ScrollDemo < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    col = Column.new.scrollable.spacing(4.0)

    # Add many items to create scrollable content
    i = 0
    while i < 30
      label = "Item " + i.to_s + " (count: " + @count.value.to_s + ")"
      col.add(
        Row(
          Text(label).font_size(16.0).color(0xFFC0CAF5),
          Spacer(),
          Button(" + ").on_click { @count += 1 }
        ).fixed_height(40.0)
      )
      i = i + 1
    end

    col
  end
end

frame = JWMFrame.new("Scroll Demo", 400, 600)
app = App.new(frame, ScrollDemo.new)
app.run
