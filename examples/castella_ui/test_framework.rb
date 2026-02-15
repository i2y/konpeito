# Test Castella UI framework layer (no JWM required)
require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

class CounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    count = @count
    label = "Count: " + count.value.to_s

    Column(
      Spacer(),
      Text(label).font_size(32.0).color(0xFFC0CAF5),
      Spacer().fixed_height(24.0),
      Row(
        Spacer(),
        Button("  -  ").font_size(24.0),
        Spacer().fixed_width(24.0),
        Button("  +  ").font_size(24.0),
        Spacer()
      ).fixed_height(60.0),
      Spacer()
    )
  end
end

comp = CounterComponent.new
tree = comp.view
puts tree
puts "Framework test OK"
