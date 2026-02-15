# Castella UI - NetImage Widget Demo
#
# Demonstrates loading images from URLs
#
# Run: cd examples/castella_ui && bash run.sh net_image_demo.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

IMG_URL = "https://picsum.photos/id/237/300/200"

class NetImageDemo < Component
  def view
    Column(
      Text("NetImage Widget Demo").font_size(20.0),
      Spacer(0.0, 8.0),
      Text("Image from URL (CONTAIN):"),
      NetImage(IMG_URL),
      Spacer(0.0, 8.0),
      Text("Invalid URL (placeholder):"),
      NetImage("https://invalid.example.com/no.png"),
      Spacer(0.0, 16.0),
      Text("Local image for comparison:"),
      Image("examples/castella_ui/test_image.png")
    ).scrollable
  end
end

frame = JWMFrame.new("NetImage Demo", 600, 600)
app = App.new(frame, NetImageDemo.new)
app.run
