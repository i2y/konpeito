# Image widget only - no markdown
require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

class ImageOnlyDemo < Component
  def view
    Column(
      Text("Image Widget Test").font_size(20.0),
      Spacer(0.0, 8.0),
      Image("examples/castella_ui/test_image.png"),
      Spacer(0.0, 8.0),
      Text("Done!")
    ).scrollable
  end
end

frame = JWMFrame.new("Image Only", 500, 400)
app = App.new(frame, ImageOnlyDemo.new)
app.run
