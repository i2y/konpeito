# Castella UI - MultilineText Demo
#
# Demonstrates the MultilineText widget with:
# - Basic multiline text display
# - Word wrapping
# - Different font sizes
# - Scrollable container
#
# Run: cd examples/castella_ui && bash run.sh multiline_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

SAMPLE_TEXT = "Hello, this is a multiline text widget.\nIt supports multiple lines of text.\nEach line is rendered separately.\n\nYou can leave blank lines too.\nThis is useful for displaying logs,\ncode output, or any text content\nthat spans multiple lines."

LONG_TEXT = "This is a long paragraph of text that demonstrates word wrapping capability. When word wrapping is enabled, the text will automatically break at word boundaries to fit within the available width. This is especially useful for displaying dynamic text content where the exact width is not known in advance. The word wrapping algorithm splits text by spaces and measures each word to determine when to start a new line."

class MultilineDemo < Component
  def view
    Column(
      Text("MultilineText Demo").font_size(20.0).align(TEXT_ALIGN_CENTER),
      Divider(),
      Spacer().fixed_height(8.0),
      Text("Basic multiline:").font_size(12.0).color($theme.text_secondary),
      MultilineText(SAMPLE_TEXT).font_size(14.0).padding(12.0),
      Spacer().fixed_height(16.0),
      Text("With word wrapping:").font_size(12.0).color($theme.text_secondary),
      MultilineText(LONG_TEXT).font_size(14.0).padding(12.0).wrap_text(true),
      Spacer().fixed_height(16.0),
      Text("Large font:").font_size(12.0).color($theme.text_secondary),
      MultilineText("Line one\nLine two\nLine three").font_size(20.0).padding(16.0).line_spacing(8.0),
      Spacer().fixed_height(16.0),
      Text("Colored text:").font_size(12.0).color($theme.text_secondary),
      MultilineText("Success message\nAll tests passed!").font_size(14.0).kind(2).padding(12.0),
      Spacer()
    ).spacing(4.0).scrollable.padding(16.0, 16.0, 16.0, 16.0)
  end
end

frame = JWMFrame.new("MultilineText Demo", 600, 700)
app = App.new(frame, MultilineDemo.new)
app.run
