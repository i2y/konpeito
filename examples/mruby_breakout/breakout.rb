# Breakout — Konpeito + mruby + raylib
#
# Build:
#   konpeito build --target mruby -o examples/mruby_breakout/breakout examples/mruby_breakout/breakout.rb
#
# Controls: Left/Right arrow keys, SPACE to launch ball

module Raylib
  def self.init_window(w, h, title) end
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
  def self.draw_line(x1, y1, x2, y2, color) end
  def self.key_down?(key) end
  def self.key_pressed?(key) end
  def self.color_white() end
  def self.color_black() end
  def self.color_red() end
  def self.color_orange() end
  def self.color_yellow() end
  def self.color_green() end
  def self.color_blue() end
  def self.color_darkgray() end
  def self.color_lightgray() end
  def self.color_raywhite() end
  def self.color_darkblue() end
  def self.color_skyblue() end
  def self.color_purple() end
  def self.color_pink() end
  def self.blocks_init() end
  def self.block_get(row, col) end
  def self.block_set(row, col, val) end
  def self.blocks_remaining() end
end

def main
  # ── Screen ──
  screen_w = 800
  screen_h = 600

  Raylib.init_window(screen_w, screen_h, "Konpeito Breakout")
  Raylib.set_target_fps(60)

  # ── Block grid layout ──
  block_rows = 5
  block_cols = 10
  block_w = 70
  block_h = 20
  block_pad = 4
  block_offset_x = (screen_w - block_cols * (block_w + block_pad)) / 2
  block_offset_y = 60

  # ── Paddle ──
  paddle_w = 100
  paddle_h = 12
  paddle_x = screen_w / 2 - paddle_w / 2
  paddle_y = screen_h - 50
  paddle_speed = 500

  # ── Ball ──
  ball_x = 0.0
  ball_y = 0.0
  ball_r = 6.0
  ball_dx = 0.0
  ball_dy = 0.0
  ball_speed = 300.0
  ball_attached = 1  # 1 = on paddle, 0 = in play

  # ── Game state ──
  lives = 3
  score = 0
  game_over = 0  # 0=playing, 1=lost, 2=won

  # ── Colors ──
  bg_color = Raylib.color_darkblue
  paddle_color = Raylib.color_white
  ball_color = Raylib.color_white
  text_color = Raylib.color_white
  row0_color = Raylib.color_red
  row1_color = Raylib.color_orange
  row2_color = Raylib.color_yellow
  row3_color = Raylib.color_green
  row4_color = Raylib.color_skyblue
  border_color = Raylib.color_lightgray

  # ── Keys ──
  key_left = 263
  key_right = 262
  key_space = 32
  key_r = 82

  # ── Init blocks ──
  Raylib.blocks_init

  # ── Main loop ──
  while Raylib.window_should_close == 0
    dt = Raylib.get_frame_time

    # ── Restart on R ──
    if Raylib.key_pressed?(key_r) != 0
      if game_over != 0
        Raylib.blocks_init
        lives = 3
        score = 0
        game_over = 0
        ball_attached = 1
        paddle_x = screen_w / 2 - paddle_w / 2
        ball_speed = 300.0
      end
    end

    if game_over == 0
      # ── Paddle movement ──
      if Raylib.key_down?(key_left) != 0
        paddle_x = paddle_x - (paddle_speed * dt).to_i
      end
      if Raylib.key_down?(key_right) != 0
        paddle_x = paddle_x + (paddle_speed * dt).to_i
      end
      if paddle_x < 0
        paddle_x = 0
      end
      if paddle_x > screen_w - paddle_w
        paddle_x = screen_w - paddle_w
      end

      # ── Ball launch ──
      if ball_attached != 0
        ball_x = paddle_x.to_f + paddle_w.to_f / 2.0
        ball_y = paddle_y.to_f - ball_r - 1.0
        if Raylib.key_pressed?(key_space) != 0
          ball_attached = 0
          ball_dx = ball_speed * 0.7
          ball_dy = 0.0 - ball_speed
        end
      end

      if ball_attached == 0
        # ── Ball movement ──
        ball_x = ball_x + ball_dx * dt
        ball_y = ball_y + ball_dy * dt

        # ── Wall bounce (left/right) ──
        if ball_x - ball_r < 0.0
          ball_x = ball_r
          ball_dx = 0.0 - ball_dx
        end
        if ball_x + ball_r > screen_w.to_f
          ball_x = screen_w.to_f - ball_r
          ball_dx = 0.0 - ball_dx
        end

        # ── Ceiling bounce ──
        if ball_y - ball_r < 0.0
          ball_y = ball_r
          ball_dy = 0.0 - ball_dy
        end

        # ── Paddle collision ──
        if ball_dy > 0.0
          if ball_y + ball_r >= paddle_y.to_f
            if ball_y + ball_r <= paddle_y.to_f + paddle_h.to_f
              if ball_x >= paddle_x.to_f && ball_x <= (paddle_x + paddle_w).to_f
                # Reflect based on hit position (-1.0 to 1.0 from center)
                hit_pos = (ball_x - paddle_x.to_f - paddle_w.to_f / 2.0) / (paddle_w.to_f / 2.0)
                ball_dx = ball_speed * hit_pos * 0.8
                ball_dy = 0.0 - ball_speed
                ball_y = paddle_y.to_f - ball_r
              end
            end
          end
        end

        # ── Block collision ──
        row = 0
        while row < block_rows
          col = 0
          while col < block_cols
            if Raylib.block_get(row, col) != 0
              bx = block_offset_x + col * (block_w + block_pad)
              by = block_offset_y + row * (block_h + block_pad)

              # AABB collision: ball center vs block rect expanded by ball_r
              if ball_x >= (bx - ball_r).to_f && ball_x <= (bx + block_w).to_f + ball_r
                if ball_y >= (by - ball_r).to_f && ball_y <= (by + block_h).to_f + ball_r
                  # Destroy block
                  Raylib.block_set(row, col, 0)
                  score = score + (block_rows - row) * 10

                  # Determine bounce direction
                  # Check if ball is more to the side or top/bottom
                  overlap_left = ball_x + ball_r - bx.to_f
                  overlap_right = (bx + block_w).to_f + ball_r - ball_x
                  overlap_top = ball_y + ball_r - by.to_f
                  overlap_bottom = (by + block_h).to_f + ball_r - ball_y

                  # Find minimum overlap to decide bounce axis
                  min_overlap = overlap_left
                  if overlap_right < min_overlap
                    min_overlap = overlap_right
                  end
                  if overlap_top < min_overlap
                    min_overlap = overlap_top
                  end
                  if overlap_bottom < min_overlap
                    min_overlap = overlap_bottom
                  end

                  if min_overlap == overlap_left || min_overlap == overlap_right
                    ball_dx = 0.0 - ball_dx
                  end
                  if min_overlap == overlap_top || min_overlap == overlap_bottom
                    ball_dy = 0.0 - ball_dy
                  end
                end
              end
            end
            col = col + 1
          end
          row = row + 1
        end

        # ── Ball fell off screen ──
        if ball_y > screen_h.to_f + 20.0
          lives = lives - 1
          ball_attached = 1
          if lives <= 0
            game_over = 1
          end
        end

        # ── Speed up slightly as blocks are cleared ──
        remaining = Raylib.blocks_remaining
        if remaining == 0
          game_over = 2
        end
        if remaining < 40
          ball_speed = 300.0 + (50 - remaining).to_f * 3.0
        end
      end
    end

    # ══════════ DRAW ══════════
    Raylib.begin_drawing
    Raylib.clear_background(bg_color)

    # ── Draw border ──
    Raylib.draw_line(0, 0, screen_w, 0, border_color)
    Raylib.draw_line(0, 0, 0, screen_h, border_color)
    Raylib.draw_line(screen_w - 1, 0, screen_w - 1, screen_h, border_color)

    # ── Draw blocks ──
    row = 0
    while row < block_rows
      col = 0
      while col < block_cols
        if Raylib.block_get(row, col) != 0
          bx = block_offset_x + col * (block_w + block_pad)
          by = block_offset_y + row * (block_h + block_pad)

          block_color = row0_color
          if row == 1
            block_color = row1_color
          end
          if row == 2
            block_color = row2_color
          end
          if row == 3
            block_color = row3_color
          end
          if row == 4
            block_color = row4_color
          end

          Raylib.draw_rectangle(bx, by, block_w, block_h, block_color)
        end
        col = col + 1
      end
      row = row + 1
    end

    # ── Draw paddle ──
    Raylib.draw_rectangle(paddle_x, paddle_y, paddle_w, paddle_h, paddle_color)

    # ── Draw ball ──
    Raylib.draw_circle(ball_x.to_i, ball_y.to_i, ball_r, ball_color)

    # ── HUD ──
    Raylib.draw_text("Score: #{score}", 10, 10, 20, text_color)
    Raylib.draw_text("Lives: #{lives}", screen_w - 120, 10, 20, text_color)

    if ball_attached != 0
      if game_over == 0
        Raylib.draw_text("SPACE to launch", screen_w / 2 - 90, screen_h / 2, 20, text_color)
      end
    end

    if game_over == 1
      Raylib.draw_text("GAME OVER", screen_w / 2 - 100, screen_h / 2 - 20, 40, Raylib.color_red)
      Raylib.draw_text("Press R to restart", screen_w / 2 - 100, screen_h / 2 + 30, 20, text_color)
    end
    if game_over == 2
      Raylib.draw_text("YOU WIN!", screen_w / 2 - 80, screen_h / 2 - 20, 40, Raylib.color_green)
      Raylib.draw_text("Press R to restart", screen_w / 2 - 100, screen_h / 2 + 30, 20, text_color)
    end

    Raylib.draw_text("Konpeito + mruby + raylib", 10, screen_h - 25, 14, Raylib.color_lightgray)

    Raylib.end_drawing
  end

  Raylib.close_window
end

main
