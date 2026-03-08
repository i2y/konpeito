# Raylib demo using Konpeito stdlib — no custom C wrapper needed!
#
# Build & run:
#   konpeito run --target mruby examples/mruby_stdlib_demo/demo.rb
#
# Or build only:
#   konpeito build --target mruby -o demo examples/mruby_stdlib_demo/demo.rb

module Raylib
  # Stubs provided by konpeito stdlib — see lib/konpeito/stdlib/raylib/
end

def main
  screen_w = 800
  screen_h = 450

  Raylib.init_window(screen_w, screen_h, "Konpeito Raylib Stdlib Demo")
  Raylib.set_target_fps(60)

  # Ball
  ball_x = 400.0
  ball_y = 225.0
  ball_r = 20.0
  ball_dx = 200.0
  ball_dy = 150.0

  # Colors
  bg = Raylib.color_darkblue
  ball_color = Raylib.color_red
  text_color = Raylib.color_white
  border_color = Raylib.color_lightgray

  while Raylib.window_should_close == 0
    dt = Raylib.get_frame_time

    # Move ball
    ball_x = ball_x + ball_dx * dt
    ball_y = ball_y + ball_dy * dt

    # Bounce off walls
    if ball_x - ball_r < 0.0
      ball_x = ball_r
      ball_dx = 0.0 - ball_dx
    end
    if ball_x + ball_r > screen_w.to_f
      ball_x = screen_w.to_f - ball_r
      ball_dx = 0.0 - ball_dx
    end
    if ball_y - ball_r < 0.0
      ball_y = ball_r
      ball_dy = 0.0 - ball_dy
    end
    if ball_y + ball_r > screen_h.to_f
      ball_y = screen_h.to_f - ball_r
      ball_dy = 0.0 - ball_dy
    end

    # Speed up/down with arrow keys
    if Raylib.key_down?(Raylib.key_up) != 0
      ball_dx = ball_dx * 1.02
      ball_dy = ball_dy * 1.02
    end
    if Raylib.key_down?(Raylib.key_down) != 0
      ball_dx = ball_dx * 0.98
      ball_dy = ball_dy * 0.98
    end

    # Draw
    Raylib.begin_drawing
    Raylib.clear_background(bg)

    # Border
    Raylib.draw_rectangle_lines(0, 0, screen_w, screen_h, border_color)

    # Ball
    Raylib.draw_circle(ball_x.to_i, ball_y.to_i, ball_r, ball_color)

    # HUD
    Raylib.draw_text("Bouncing Ball — Konpeito stdlib", 10, 10, 20, text_color)
    Raylib.draw_text("UP/DOWN: speed   ESC: quit", 10, screen_h - 30, 16, Raylib.color_lightgray)

    fps = Raylib.get_fps
    Raylib.draw_text("FPS: #{fps}", screen_w - 100, 10, 16, Raylib.color_green)

    Raylib.end_drawing
  end

  Raylib.close_window
end

main
