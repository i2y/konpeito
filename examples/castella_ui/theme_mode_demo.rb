# Castella UI - Theme Mode & Font Demo
#
# Demonstrates:
# - Dark/Light mode auto-detection (isDarkMode)
# - Theme switching: Tokyo Night, Tokyo Night Light, Material, Nord, Dracula, Catppuccin
# - Font family switching ($theme.font_family)
# - DataTable sort indicators (graphical triangles)
#
# Run: cd examples/castella_ui && bash run.sh theme_mode_demo.rb

require_relative "../../lib/konpeito/ui/castella"

# Auto-detect dark/light mode
$theme = Theme.new

class ThemeModeDemo < Component
  def initialize
    super
    @theme_idx = state(0)
    @font_idx = state(0)
  end

  def theme_display_name(idx)
    if idx == 1
      "Tokyo Night Light"
    elsif idx == 2
      "Material Light"
    elsif idx == 3
      "Nord"
    elsif idx == 4
      "Dracula"
    elsif idx == 5
      "Catppuccin"
    else
      "Tokyo Night"
    end
  end

  def font_display_name(idx)
    if idx == 1
      "Helvetica Neue"
    elsif idx == 2
      "Menlo"
    elsif idx == 3
      "Georgia"
    else
      "System Default"
    end
  end

  def view
    tidx = @theme_idx.value
    fidx = @font_idx.value
    tname = theme_display_name(tidx)
    fname = font_display_name(fidx)
    t_ref = @theme_idx
    f_ref = @font_idx

    # DataTable sample
    col_names = ["Name", "Language", "Stars", "License"]
    col_widths = [140.0, 100.0, 80.0, 100.0]
    rows = [
      ["Konpeito", "Ruby", "1200", "MIT"],
      ["Crystal", "Crystal", "18500", "Apache-2.0"],
      ["Sorbet", "Ruby", "3500", "Apache-2.0"],
      ["mruby", "C", "5200", "MIT"],
      ["TruffleRuby", "Java", "3000", "GPL-2.0"],
      ["JRuby", "Java", "3700", "EPL-2.0"]
    ]

    Column(
      # Title section
      Text("Theme & Font Demo").font_size(20.0).align(TEXT_ALIGN_CENTER),
      Text("Current: " + tname + " / " + fname).font_size(12.0).align(TEXT_ALIGN_CENTER),
      Spacer().fixed_height(8.0),

      # Dark themes row
      Text("Dark Themes:").font_size(13.0),
      Spacer().fixed_height(4.0),
      Row(
        Spacer().fixed_width(8.0),
        Button("Tokyo Night").on_click {
          $theme = theme_tokyo_night
          apply_font(fidx)
          t_ref.set(0)
        },
        Spacer().fixed_width(6.0),
        Button("Nord").on_click {
          $theme = theme_nord
          apply_font(fidx)
          t_ref.set(3)
        },
        Spacer().fixed_width(6.0),
        Button("Dracula").on_click {
          $theme = theme_dracula
          apply_font(fidx)
          t_ref.set(4)
        },
        Spacer().fixed_width(6.0),
        Button("Catppuccin").on_click {
          $theme = theme_catppuccin
          apply_font(fidx)
          t_ref.set(5)
        }
      ).fixed_height(36.0),

      Spacer().fixed_height(6.0),

      # Light themes row
      Text("Light Themes:").font_size(13.0),
      Spacer().fixed_height(4.0),
      Row(
        Spacer().fixed_width(8.0),
        Button("Tokyo Night Light").on_click {
          $theme = theme_light
          apply_font(fidx)
          t_ref.set(1)
        },
        Spacer().fixed_width(6.0),
        Button("Material Light").on_click {
          $theme = material_theme
          apply_font(fidx)
          t_ref.set(2)
        }
      ).fixed_height(36.0),

      Spacer().fixed_height(8.0),
      Divider(),
      Spacer().fixed_height(8.0),

      # Font switcher
      Text("Font Family:").font_size(13.0),
      Spacer().fixed_height(4.0),
      Row(
        Spacer().fixed_width(8.0),
        Button("System Default").on_click {
          $theme.font_family = "default"
          f_ref.set(0)
        },
        Spacer().fixed_width(6.0),
        Button("Helvetica Neue").on_click {
          $theme.font_family = "Helvetica Neue"
          f_ref.set(1)
        },
        Spacer().fixed_width(6.0),
        Button("Menlo").on_click {
          $theme.font_family = "Menlo"
          f_ref.set(2)
        },
        Spacer().fixed_width(6.0),
        Button("Georgia").on_click {
          $theme.font_family = "Georgia"
          f_ref.set(3)
        }
      ).fixed_height(36.0),

      Spacer().fixed_height(8.0),
      Divider(),
      Spacer().fixed_height(8.0),

      # Sample widgets
      Text("Sample Widgets:").font_size(14.0),
      Spacer().fixed_height(4.0),

      Row(
        Spacer().fixed_width(8.0),
        Container(
          Column(
            Row(
              Button("Normal"),
              Spacer().fixed_width(6.0),
              Button("Info").kind(1),
              Spacer().fixed_width(6.0),
              Button("Success").kind(2),
              Spacer().fixed_width(6.0),
              Button("Warning").kind(3),
              Spacer().fixed_width(6.0),
              Button("Danger").kind(4)
            ).fixed_height(36.0),
            Spacer().fixed_height(8.0),
            Input("Type something here..."),
            Spacer().fixed_height(8.0),
            Checkbox("Enable dark mode auto-detection").checked(true),
            Spacer().fixed_height(4.0),
            Checkbox("Use custom font family")
          )
        ),
        Spacer().fixed_width(8.0)
      ),

      Spacer().fixed_height(8.0),

      # DataTable (tests sort icon triangles)
      Text("DataTable (click headers to sort):").font_size(13.0),
      Spacer().fixed_height(4.0),
      DataTable(col_names, col_widths, rows).fixed_height(200.0),

      Spacer()
    ).scrollable.spacing(2.0)
  end
end

def apply_font(fidx)
  if fidx == 1
    $theme.font_family = "Helvetica Neue"
  elsif fidx == 2
    $theme.font_family = "Menlo"
  elsif fidx == 3
    $theme.font_family = "Georgia"
  else
    $theme.font_family = "default"
  end
end

# Auto-detect dark/light mode at startup
frame = JWMFrame.new("Theme & Font Demo", 700, 650)
if frame.is_dark_mode
  $theme = Theme.new
else
  $theme = theme_light
end

app = App.new(frame, ThemeModeDemo.new)
app.run
