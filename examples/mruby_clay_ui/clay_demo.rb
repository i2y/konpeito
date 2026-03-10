# Clay UI Demo — Sidebar + Main Content layout
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -o examples/mruby_clay_ui/clay_demo \
#     examples/mruby_clay_ui/clay_demo.rb
#
# Run:
#   ./examples/mruby_clay_ui/clay_demo

# Layout constants
SIDEBAR_WIDTH = 250.0
WINDOW_W = 800
WINDOW_H = 600

# Sizing type constants
FIT = 0
GROW = 1
FIXED = 2

# Direction constants
LEFT_TO_RIGHT = 0
TOP_TO_BOTTOM = 1

# Alignment constants
ALIGN_LEFT = 0
ALIGN_CENTER = 2
ALIGN_TOP = 0
ALIGN_CENTER_Y = 2

# Font IDs
FONT_BODY = 0
FONT_HEADING = 1

def main
  # Initialize raylib window (resizable + HiDPI)
  Raylib.set_config_flags(Raylib.flag_window_resizable)
  Raylib.init_window(WINDOW_W, WINDOW_H, "Clay UI Demo")
  Raylib.set_target_fps(60)

  # Initialize Clay layout engine
  Clay.init(800.0, 600.0)

  # Load fonts — use system Arial on macOS
  font_body = Clay.load_font("/System/Library/Fonts/Supplemental/Arial.ttf", 32)
  font_heading = Clay.load_font("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 64)
  Clay.set_measure_text_raylib

  while Raylib.window_should_close == 0
    # Update Clay dimensions on window resize
    w = Raylib.get_screen_width
    h = Raylib.get_screen_height
    Clay.set_dimensions(w * 1.0, h * 1.0)

    # Update pointer state
    mx = Raylib.get_mouse_x
    my = Raylib.get_mouse_y
    mouse_down = Raylib.mouse_button_down?(Raylib.mouse_left)
    Clay.set_pointer(mx * 1.0, my * 1.0, mouse_down)

    # Build layout
    Clay.begin_layout

    # Root container (horizontal, fill screen)
    Clay.open("root")
    Clay.layout(LEFT_TO_RIGHT, 0, 0, 0, 0, 0, GROW, 0.0, GROW, 0.0, ALIGN_LEFT, ALIGN_TOP)
    Clay.bg(245.0, 245.0, 245.0, 255.0, 0.0)

      # Sidebar (fixed width, vertical layout)
      Clay.open("sidebar")
      Clay.layout(TOP_TO_BOTTOM, 16, 16, 16, 16, 8, FIXED, SIDEBAR_WIDTH, GROW, 0.0, ALIGN_LEFT, ALIGN_TOP)
      Clay.bg(224.0, 215.0, 210.0, 255.0, 8.0)

        # Sidebar title
        Clay.text("Navigation", font_heading, 24, 80.0, 80.0, 80.0, 255.0, 0)

        # Menu items
        Clay.open("menu1")
        Clay.layout(LEFT_TO_RIGHT, 12, 12, 8, 8, 0, GROW, 0.0, FIT, 0.0, ALIGN_LEFT, ALIGN_CENTER_Y)
        Clay.bg(255.0, 255.0, 255.0, 255.0, 4.0)
          Clay.text("Home", font_body, 16, 60.0, 60.0, 60.0, 255.0, 0)
        Clay.close

        Clay.open("menu2")
        Clay.layout(LEFT_TO_RIGHT, 12, 12, 8, 8, 0, GROW, 0.0, FIT, 0.0, ALIGN_LEFT, ALIGN_CENTER_Y)
        Clay.bg(255.0, 255.0, 255.0, 255.0, 4.0)
          Clay.text("About", font_body, 16, 60.0, 60.0, 60.0, 255.0, 0)
        Clay.close

        Clay.open("menu3")
        Clay.layout(LEFT_TO_RIGHT, 12, 12, 8, 8, 0, GROW, 0.0, FIT, 0.0, ALIGN_LEFT, ALIGN_CENTER_Y)
        Clay.bg(255.0, 255.0, 255.0, 255.0, 4.0)
          Clay.text("Contact", font_body, 16, 60.0, 60.0, 60.0, 255.0, 0)
        Clay.close

      Clay.close  # sidebar

      # Main content (flexible width, vertical layout)
      Clay.open("main")
      Clay.layout(TOP_TO_BOTTOM, 24, 24, 24, 24, 16, GROW, 0.0, GROW, 0.0, ALIGN_LEFT, ALIGN_TOP)
      Clay.bg(255.0, 255.0, 255.0, 255.0, 0.0)

        # Header
        Clay.text("Welcome to Clay UI", font_heading, 32, 40.0, 40.0, 40.0, 255.0, 0)

        # Description
        Clay.text("This is a demo of Clay UI layout engine integrated with Konpeito and Raylib.", font_body, 16, 100.0, 100.0, 100.0, 255.0, 0)

        # Card row
        Clay.open("cards")
        Clay.layout(LEFT_TO_RIGHT, 0, 0, 0, 0, 16, GROW, 0.0, FIT, 0.0, ALIGN_LEFT, ALIGN_TOP)

          # Card 1
          Clay.open("card1")
          Clay.layout(TOP_TO_BOTTOM, 16, 16, 16, 16, 8, GROW, 0.0, FIT, 0.0, ALIGN_LEFT, ALIGN_TOP)
          Clay.bg(240.0, 248.0, 255.0, 255.0, 8.0)
          Clay.border(200.0, 220.0, 240.0, 255.0, 1, 1, 1, 1, 8.0)
            Clay.text("Performance", font_heading, 20, 50.0, 50.0, 50.0, 255.0, 0)
            Clay.text("Up to 5000x faster than Ruby for typed numeric loops.", font_body, 14, 80.0, 80.0, 80.0, 255.0, 0)
          Clay.close

          # Card 2
          Clay.open("card2")
          Clay.layout(TOP_TO_BOTTOM, 16, 16, 16, 16, 8, GROW, 0.0, FIT, 0.0, ALIGN_LEFT, ALIGN_TOP)
          Clay.bg(255.0, 245.0, 238.0, 255.0, 8.0)
          Clay.border(240.0, 220.0, 200.0, 255.0, 1, 1, 1, 1, 8.0)
            Clay.text("Type Safety", font_heading, 20, 50.0, 50.0, 50.0, 255.0, 0)
            Clay.text("HM type inference with optional RBS annotations.", font_body, 14, 80.0, 80.0, 80.0, 255.0, 0)
          Clay.close

          # Card 3
          Clay.open("card3")
          Clay.layout(TOP_TO_BOTTOM, 16, 16, 16, 16, 8, GROW, 0.0, FIT, 0.0, ALIGN_LEFT, ALIGN_TOP)
          Clay.bg(245.0, 255.0, 245.0, 255.0, 8.0)
          Clay.border(200.0, 240.0, 200.0, 255.0, 1, 1, 1, 1, 8.0)
            Clay.text("Standalone", font_heading, 20, 50.0, 50.0, 50.0, 255.0, 0)
            Clay.text("Compile to standalone executables with mruby.", font_body, 14, 80.0, 80.0, 80.0, 255.0, 0)
          Clay.close

        Clay.close  # cards

      Clay.close  # main

    Clay.close  # root

    Clay.end_layout

    # Render
    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_raywhite)
    Clay.render_raylib
    Raylib.end_drawing
  end

  Clay.destroy
  Raylib.close_window
end

main
