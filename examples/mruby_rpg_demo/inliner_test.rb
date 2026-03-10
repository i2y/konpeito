# Minimal test for inliner CFuncCall fix
# rbs_inline: enabled
#
# Build:
#   konpeito build --target mruby --inline -o examples/mruby_rpg_demo/inliner_test examples/mruby_rpg_demo/inliner_test.rb

#: (Integer x, Integer y, Integer w, Integer h, Integer color) -> Integer
def draw_rect(x, y, w, h, color)
  Raylib.draw_rectangle(x, y, w, h, color)
  return 0
end

#: () -> Integer
def main
  Raylib.init_window(640, 480, "Inliner CFuncCall Test")
  Raylib.set_target_fps(60)

  while Raylib.window_should_close == 0
    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)

    # Call helper function that passes params to @cfunc
    ty = 0
    while ty < 15
      tx = 0
      while tx < 20
        draw_rect(tx * 32, ty * 32, 31, 31, Raylib.color_green)
        tx = tx + 1
      end
      ty = ty + 1
    end

    Raylib.draw_text("If green grid visible = FIX WORKS", 10, 10, 20, Raylib.color_white)
    Raylib.end_drawing
  end

  Raylib.close_window
  return 0
end

main
