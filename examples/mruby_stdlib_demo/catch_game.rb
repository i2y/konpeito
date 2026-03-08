# Catch Game — stdlib Raylib only, no custom C wrapper
#
# Falling objects to catch with a paddle. Arrow keys to move.
#
# Build & run:
#   konpeito run --target mruby examples/mruby_stdlib_demo/catch_game.rb

module Raylib
end

def main
  screen_w = 600
  screen_h = 400

  Raylib.init_window(screen_w, screen_h, "Catch Game — Konpeito stdlib")
  Raylib.set_target_fps(60)

  # Paddle
  paddle_w = 80
  paddle_h = 14
  paddle_x = screen_w / 2 - paddle_w / 2
  paddle_y = screen_h - 40
  paddle_speed = 400

  # Falling object
  obj_x = Raylib.get_random_value(30, screen_w - 30)
  obj_y = 0
  obj_size = 16
  obj_speed = 150.0

  # Game state
  score = 0
  misses = 0
  max_misses = 5
  game_over = 0

  # Colors
  bg_color = Raylib.color_black
  paddle_color = Raylib.color_skyblue
  obj_color = Raylib.color_gold
  text_color = Raylib.color_white
  miss_color = Raylib.color_red
  win_color = Raylib.color_green

  while Raylib.window_should_close == 0
    dt = Raylib.get_frame_time

    if game_over == 0
      # Paddle input
      if Raylib.key_down?(Raylib.key_left) != 0
        paddle_x = paddle_x - (paddle_speed * dt).to_i
      end
      if Raylib.key_down?(Raylib.key_right) != 0
        paddle_x = paddle_x + (paddle_speed * dt).to_i
      end
      if paddle_x < 0
        paddle_x = 0
      end
      if paddle_x > screen_w - paddle_w
        paddle_x = screen_w - paddle_w
      end

      # Move falling object
      obj_y = obj_y + (obj_speed * dt).to_i

      # Check catch
      if obj_y + obj_size >= paddle_y
        if obj_x + obj_size >= paddle_x && obj_x <= paddle_x + paddle_w
          # Caught!
          score = score + 1
          obj_x = Raylib.get_random_value(30, screen_w - 30)
          obj_y = 0
          # Speed up
          obj_speed = obj_speed + 10.0
        end
      end

      # Check miss
      if obj_y > screen_h
        misses = misses + 1
        obj_x = Raylib.get_random_value(30, screen_w - 30)
        obj_y = 0
        if misses >= max_misses
          game_over = 1
        end
      end
    end

    # Restart
    if game_over != 0
      if Raylib.key_pressed?(Raylib.key_r) != 0
        score = 0
        misses = 0
        game_over = 0
        obj_speed = 150.0
        obj_x = Raylib.get_random_value(30, screen_w - 30)
        obj_y = 0
        paddle_x = screen_w / 2 - paddle_w / 2
      end
    end

    # ── Draw ──
    Raylib.begin_drawing
    Raylib.clear_background(bg_color)

    # Paddle
    Raylib.draw_rectangle(paddle_x, paddle_y, paddle_w, paddle_h, paddle_color)

    # Falling object
    if game_over == 0
      Raylib.draw_rectangle(obj_x, obj_y, obj_size, obj_size, obj_color)
    end

    # Score & misses
    Raylib.draw_text("Score: #{score}", 10, 10, 20, text_color)
    lives_left = max_misses - misses
    Raylib.draw_text("Lives: #{lives_left}", screen_w - 120, 10, 20, text_color)

    # Miss indicators
    i = 0
    while i < misses
      Raylib.draw_rectangle(screen_w - 120 + i * 18, 35, 12, 12, miss_color)
      i = i + 1
    end

    if game_over != 0
      Raylib.draw_text("GAME OVER", screen_w / 2 - 100, screen_h / 2 - 20, 40, miss_color)
      Raylib.draw_text("Score: #{score}", screen_w / 2 - 60, screen_h / 2 + 30, 24, text_color)
      Raylib.draw_text("Press R to restart", screen_w / 2 - 90, screen_h / 2 + 65, 18, Raylib.color_lightgray)
    end

    fps = Raylib.get_fps
    Raylib.draw_text("FPS: #{fps}", 10, screen_h - 25, 14, Raylib.color_darkgray)
    Raylib.draw_text("Konpeito stdlib raylib", screen_w - 200, screen_h - 25, 14, Raylib.color_darkgray)

    Raylib.end_drawing
  end

  Raylib.close_window
end

main
