# Simple Pong-style game using raylib + Konpeito mruby backend
#
# Build:
#   cd examples/mruby_raylib
#   konpeito build --target mruby -o game game.rb
#
# (The build command is wrapped by the Makefile below)

module Raylib
  def self.init_window(width, height, title) end
  def self.close_window() end
  def self.window_should_close() end
  def self.set_target_fps(fps) end
  def self.get_frame_time() end
  def self.begin_drawing() end
  def self.end_drawing() end
  def self.clear_background(color) end
  def self.draw_rectangle(x, y, w, h, color) end
  def self.draw_circle(cx, cy, r, color) end
  def self.draw_text(text, x, y, size, color) end
  def self.key_down?(key) end
  def self.key_pressed?(key) end
  def self.color_raywhite() end
  def self.color_black() end
  def self.color_red() end
  def self.color_green() end
  def self.color_blue() end
  def self.color_darkgray() end
  def self.color_lightgray() end
end

def main
  screen_w = 800
  screen_h = 450

  Raylib.init_window(screen_w, screen_h, "Konpeito Pong")
  Raylib.set_target_fps(60)

  # Paddle
  paddle_w = 100
  paddle_h = 15
  paddle_x = screen_w / 2 - paddle_w / 2
  paddle_y = screen_h - 40
  paddle_speed = 400

  # Ball
  ball_x = 400.0
  ball_y = 225.0
  ball_r = 8.0
  ball_dx = 200.0
  ball_dy = -200.0

  # Score
  score = 0

  # Colors
  bg_color = Raylib.color_raywhite
  paddle_color = Raylib.color_darkgray
  ball_color = Raylib.color_red
  text_color = Raylib.color_black

  # Key codes
  key_left = 263
  key_right = 262

  # window_should_close / key_down? return Integer (0 or 1)
  # Ruby treats 0 as truthy, so use == 0 / != 0 comparisons
  while Raylib.window_should_close == 0
    dt = Raylib.get_frame_time

    # Move paddle
    if Raylib.key_down?(key_left) != 0
      paddle_x = paddle_x - (paddle_speed * dt).to_i
    end
    if Raylib.key_down?(key_right) != 0
      paddle_x = paddle_x + (paddle_speed * dt).to_i
    end

    # Clamp paddle
    if paddle_x < 0
      paddle_x = 0
    end
    if paddle_x > screen_w - paddle_w
      paddle_x = screen_w - paddle_w
    end

    # Move ball
    ball_x = ball_x + ball_dx * dt
    ball_y = ball_y + ball_dy * dt

    # Wall bounce (left/right)
    if ball_x < ball_r
      ball_x = ball_r
      ball_dx = 0.0 - ball_dx
    end
    if ball_x > screen_w.to_f - ball_r
      ball_x = screen_w.to_f - ball_r
      ball_dx = 0.0 - ball_dx
    end

    # Ceiling bounce
    if ball_y < ball_r
      ball_y = ball_r
      ball_dy = 0.0 - ball_dy
    end

    # Paddle collision
    if ball_y + ball_r >= paddle_y.to_f
      if ball_x >= paddle_x.to_f && ball_x <= (paddle_x + paddle_w).to_f
        ball_y = paddle_y.to_f - ball_r
        ball_dy = 0.0 - ball_dy
        score = score + 1
      end
    end

    # Ball fell below screen — reset
    if ball_y > screen_h.to_f + 50.0
      ball_x = 400.0
      ball_y = 225.0
      ball_dy = -200.0
      score = 0
    end

    # Draw
    Raylib.begin_drawing
    Raylib.clear_background(bg_color)

    Raylib.draw_rectangle(paddle_x, paddle_y, paddle_w, paddle_h, paddle_color)
    Raylib.draw_circle(ball_x.to_i, ball_y.to_i, ball_r, ball_color)
    Raylib.draw_text("Score: #{score}", 10, 10, 20, text_color)
    Raylib.draw_text("Konpeito + mruby + raylib", 10, screen_h - 25, 16, Raylib.color_lightgray)

    Raylib.end_drawing
  end

  Raylib.close_window
end

main
