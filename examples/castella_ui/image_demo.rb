# Castella UI - Image Widget Demo
#
# Demonstrates the Image widget with:
# - Actual image from file (CONTAIN fit)
# - FILL fit mode
# - Missing image placeholder
# - Image in Markdown
#
# Run: cd examples/castella_ui && bash run.sh image_demo.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

SAMPLE_MD = "## Markdown Section\n\nThis text is rendered with **Markdown**.\n\nDone!"

class ImageDemo < Component
  def view
    Column(
      Text("Image Widget Demo").font_size(20.0),
      Spacer(0.0, 8.0),
      Text("Image widget (CONTAIN):"),
      Image("examples/castella_ui/test_image.png"),
      Spacer(0.0, 8.0),
      Text("Missing image (placeholder):"),
      Image("nonexistent.png"),
      Spacer(0.0, 16.0),
      Divider(),
      Spacer(0.0, 8.0),
      Markdown(SAMPLE_MD)
    ).scrollable
  end
end

frame = JWMFrame.new("Image Demo", 600, 600)
app = App.new(frame, ImageDemo.new)
app.run
