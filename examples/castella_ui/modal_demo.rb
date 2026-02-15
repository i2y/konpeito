# Castella UI - Modal Demo
#
# Tests modal dialog overlay with backdrop.
# Run: cd examples/castella_ui && bash run.sh modal_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

class ModalDemo < Component
  def initialize
    super
  end

  def view
    # Modal content
    modal_body = Column(
      Text("This is a modal dialog!").font_size(14.0).color(0xFFC0CAF5),
      Spacer().fixed_height(8.0),
      Text("Click the X or backdrop to close.").font_size(13.0).color(0xFF565F89),
      Spacer().fixed_height(12.0),
      Input("Type something here...")
    ).spacing(4.0)

    m = Modal(modal_body).title("My Dialog").dialog_size(350.0, 220.0)

    # Main content — capture modal into local var to avoid self-capture in block
    main = Column(
      Text("Modal Demo").font_size(18.0).color(0xFFC0CAF5),
      Divider(),
      Text("Click the button to open a modal dialog.").font_size(14.0).color(0xFF9AA5CE),
      Spacer().fixed_height(12.0),
      Button("Open Modal").on_click { m.open_modal },
      Spacer().fixed_height(8.0),
      Text("The modal overlays on top of this content.").font_size(13.0).color(0xFF565F89),
      Text("You can close it by clicking the X or the dark backdrop.").font_size(13.0).color(0xFF565F89)
    ).spacing(8.0)

    # Box layers: main content (z=0) + modal overlay (z=98)
    Box(main, m)
  end
end

frame = JWMFrame.new("Modal Demo", 500, 400)
app = App.new(frame, ModalDemo.new)
app.run
