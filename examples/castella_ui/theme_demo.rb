# Castella UI - Theme Demo
#
# Demonstrates:
# - 4 theme presets (Tokyo Night, Nord, Dracula, Catppuccin)
# - Kind variants (Normal, Info, Success, Warning, Danger)
# - Theme-aware widgets (Button, Text, Input, Checkbox, Container, Divider)
#
# Run: cd examples/castella_ui && bash run.sh theme_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Global theme (default: Tokyo Night)
$theme = Theme.new

# ===== Theme Demo Component =====

class ThemeDemo < Component
  def initialize
    super
    @theme_idx = state(0)
  end

  def theme_display_name(idx)
    names = ["Tokyo Night", "Nord", "Dracula", "Catppuccin"]
    names[idx]
  end

  def view
    idx = @theme_idx.value
    name = theme_display_name(idx)
    idx_ref = @theme_idx

    Column(
      # Header
      Text("Theme: " + name).font_size(20.0).align(TEXT_ALIGN_CENTER),
      Spacer().fixed_height(8.0),

      # Theme switcher buttons
      Row(
        Spacer(),
        Button("Tokyo Night").on_click {
          $theme = theme_tokyo_night
          idx_ref.set(0)
        },
        Spacer().fixed_width(8.0),
        Button("Nord").on_click {
          $theme = theme_nord
          idx_ref.set(1)
        },
        Spacer().fixed_width(8.0),
        Button("Dracula").on_click {
          $theme = theme_dracula
          idx_ref.set(2)
        },
        Spacer().fixed_width(8.0),
        Button("Catppuccin").on_click {
          $theme = theme_catppuccin
          idx_ref.set(3)
        },
        Spacer()
      ).fixed_height(40.0),

      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(12.0),

      # Kind variant buttons
      Text("Button Kinds:").font_size(14.0),
      Spacer().fixed_height(8.0),
      Row(
        Spacer().fixed_width(12.0),
        Button("Normal"),
        Spacer().fixed_width(8.0),
        Button("Info").kind(1),
        Spacer().fixed_width(8.0),
        Button("Success").kind(2),
        Spacer().fixed_width(8.0),
        Button("Warning").kind(3),
        Spacer().fixed_width(8.0),
        Button("Danger").kind(4),
        Spacer()
      ).fixed_height(40.0),

      Spacer().fixed_height(12.0),

      # Kind variant text
      Text("Text Kinds:").font_size(14.0),
      Spacer().fixed_height(8.0),
      Row(
        Spacer().fixed_width(12.0),
        Text("Normal"),
        Spacer().fixed_width(16.0),
        Text("Info").kind(1),
        Spacer().fixed_width(16.0),
        Text("Success").kind(2),
        Spacer().fixed_width(16.0),
        Text("Warning").kind(3),
        Spacer().fixed_width(16.0),
        Text("Danger").kind(4),
        Spacer()
      ).fixed_height(24.0),

      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(12.0),

      # Input and Checkbox in a container
      Text("Form Widgets:").font_size(14.0),
      Spacer().fixed_height(8.0),
      Row(
        Spacer().fixed_width(12.0),
        Container(
          Column(
            Input("Enter your name..."),
            Spacer().fixed_height(8.0),
            Input("Enter your email..."),
            Spacer().fixed_height(8.0),
            Checkbox("Remember me"),
            Spacer().fixed_height(8.0),
            Checkbox("Accept terms").checked(true)
          )
        ),
        Spacer().fixed_width(12.0)
      ),

      Spacer()
    )
  end
end

# ===== Launch =====
frame = JWMFrame.new("Theme Demo", 600, 500)
app = App.new(frame, ThemeDemo.new)
app.run
