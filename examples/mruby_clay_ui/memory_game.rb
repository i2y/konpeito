# Memory Match (神経衰弱) — Clay UI + Raylib game
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -o examples/mruby_clay_ui/memory_game \
#     examples/mruby_clay_ui/memory_game.rb
#
# Run:
#   ./examples/mruby_clay_ui/memory_game

WINDOW_W = 800
WINDOW_H = 600

# Sizing
FIT = 0
GROW = 1
FIXED = 2

# Direction
LTR = 0
TTB = 1

# Align
AL_LEFT = 0
AL_CENTER = 2
AL_TOP = 0
AL_CENTER_Y = 2

def init_game
  # Card values: 6 pairs (1-6)
  i = 0
  while i < 6
    G.cards[i * 2] = i + 1
    G.cards[i * 2 + 1] = i + 1
    i = i + 1
  end

  # All face-down
  i = 0
  while i < 12
    G.state[i] = 0
    i = i + 1
  end

  G.pick1[0] = -1
  G.pick2[0] = -1
  G.turns[0] = 0
  G.matched[0] = 0
  G.timer[0] = 0

  # Card colors (R, G, B) for values 1-6
  # 1: Red
  G.colors[0] = 220.0
  G.colors[1] = 60.0
  G.colors[2] = 60.0
  # 2: Blue
  G.colors[3] = 60.0
  G.colors[4] = 120.0
  G.colors[5] = 220.0
  # 3: Green
  G.colors[6] = 60.0
  G.colors[7] = 180.0
  G.colors[8] = 80.0
  # 4: Orange
  G.colors[9] = 240.0
  G.colors[10] = 160.0
  G.colors[11] = 40.0
  # 5: Purple
  G.colors[12] = 160.0
  G.colors[13] = 60.0
  G.colors[14] = 200.0
  # 6: Teal
  G.colors[15] = 40.0
  G.colors[16] = 180.0
  G.colors[17] = 190.0

  shuffle_cards
end

def shuffle_cards
  # Fisher-Yates shuffle
  i = 11
  while i > 0
    j = Raylib.get_random_value(0, i)
    tmp = G.cards[i]
    G.cards[i] = G.cards[j]
    G.cards[j] = tmp
    i = i - 1
  end
end

def update_game(dt)
  # If two cards revealed, wait then check
  if G.pick1[0] >= 0
    if G.pick2[0] >= 0
      # Increase timer (dt is in seconds, store as ms integer)
      G.timer[0] = G.timer[0] + (dt * 1000.0).to_i

      if G.timer[0] > 800
        p1 = G.pick1[0]
        p2 = G.pick2[0]

        if G.cards[p1] == G.cards[p2]
          # Match!
          G.state[p1] = 2
          G.state[p2] = 2
          G.matched[0] = G.matched[0] + 1
        else
          # No match — flip back
          G.state[p1] = 0
          G.state[p2] = 0
        end

        G.pick1[0] = -1
        G.pick2[0] = -1
        G.timer[0] = 0
      end
    end
  end
end

def handle_click
  # Ignore clicks while waiting for timer
  if G.pick2[0] >= 0
    return
  end

  i = 0
  while i < 12
    if Clay.pointer_over_i("card", i) == 1
      # Only pick face-down cards
      if G.state[i] == 0
        if G.pick1[0] < 0
          # First pick
          G.pick1[0] = i
          G.state[i] = 1
          G.turns[0] = G.turns[0] + 1
        else
          # Second pick (must be different card)
          if G.pick1[0] != i
            G.pick2[0] = i
            G.state[i] = 1
          end
        end
      end
    end
    i = i + 1
  end
end

def draw_card(i, font_body)
  card_val = G.cards[i]
  card_state = G.state[i]

  Clay.open_i("card", i)
  Clay.layout(TTB, 4, 4, 4, 4, 4, FIXED, 120.0, FIXED, 100.0, AL_CENTER, AL_CENTER_Y)

  if card_state == 0
    # Face-down: dark gray
    Clay.bg(80.0, 80.0, 100.0, 255.0, 12.0)
    Clay.border(60.0, 60.0, 80.0, 255.0, 2, 2, 2, 2, 12.0)
    Clay.text("?", font_body, 36, 200.0, 200.0, 220.0, 255.0, 0)
  else
    # Face-up or matched: show color
    ci = (card_val - 1) * 3
    cr = G.colors[ci]
    cg = G.colors[ci + 1]
    cb = G.colors[ci + 2]

    if card_state == 2
      # Matched: slightly transparent
      Clay.bg(cr, cg, cb, 160.0, 12.0)
      Clay.border(cr, cg, cb, 200.0, 2, 2, 2, 2, 12.0)
    else
      # Face-up: full color
      Clay.bg(cr, cg, cb, 255.0, 12.0)
      Clay.border(255.0, 255.0, 255.0, 200.0, 2, 2, 2, 2, 12.0)
    end

    # Show card value number
    if card_val == 1
      Clay.text("1", font_body, 36, 255.0, 255.0, 255.0, 255.0, 0)
    end
    if card_val == 2
      Clay.text("2", font_body, 36, 255.0, 255.0, 255.0, 255.0, 0)
    end
    if card_val == 3
      Clay.text("3", font_body, 36, 255.0, 255.0, 255.0, 255.0, 0)
    end
    if card_val == 4
      Clay.text("4", font_body, 36, 255.0, 255.0, 255.0, 255.0, 0)
    end
    if card_val == 5
      Clay.text("5", font_body, 36, 255.0, 255.0, 255.0, 255.0, 0)
    end
    if card_val == 6
      Clay.text("6", font_body, 36, 255.0, 255.0, 255.0, 255.0, 0)
    end
  end

  Clay.close
end

def draw_ui(font_body, font_heading)
  Clay.begin_layout

  # Root container (vertical, fill screen)
  Clay.open("root")
  Clay.layout(TTB, 16, 16, 16, 16, 12, GROW, 0.0, GROW, 0.0, AL_CENTER, AL_TOP)
  Clay.bg(30.0, 30.0, 45.0, 255.0, 0.0)

    # Title bar
    Clay.open("header")
    Clay.layout(LTR, 16, 16, 8, 8, 0, GROW, 0.0, FIT, 0.0, AL_CENTER, AL_CENTER_Y)
      Clay.text("Memory Match", font_heading, 28, 255.0, 255.0, 255.0, 255.0, 0)
    Clay.close

    # Stats bar
    Clay.open("stats")
    Clay.layout(LTR, 16, 16, 8, 8, 24, GROW, 0.0, FIT, 0.0, AL_CENTER, AL_CENTER_Y)

      Clay.open("turns_box")
      Clay.layout(LTR, 12, 12, 6, 6, 8, FIT, 0.0, FIT, 0.0, AL_LEFT, AL_CENTER_Y)
      Clay.bg(50.0, 50.0, 70.0, 255.0, 6.0)
        Clay.text("Turns:", font_body, 18, 180.0, 180.0, 200.0, 255.0, 0)
        turns = G.turns[0]
        if turns == 0
          Clay.text("0", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
        end
        if turns > 0
          if turns < 10
            if turns == 1
              Clay.text("1", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 2
              Clay.text("2", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 3
              Clay.text("3", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 4
              Clay.text("4", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 5
              Clay.text("5", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 6
              Clay.text("6", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 7
              Clay.text("7", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 8
              Clay.text("8", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
            if turns == 9
              Clay.text("9", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
            end
          else
            Clay.text("10+", font_body, 18, 255.0, 255.0, 100.0, 255.0, 0)
          end
        end
      Clay.close

      Clay.open("matches_box")
      Clay.layout(LTR, 12, 12, 6, 6, 8, FIT, 0.0, FIT, 0.0, AL_LEFT, AL_CENTER_Y)
      Clay.bg(50.0, 50.0, 70.0, 255.0, 6.0)
        Clay.text("Matched:", font_body, 18, 180.0, 180.0, 200.0, 255.0, 0)
        matched = G.matched[0]
        if matched == 0
          Clay.text("0/6", font_body, 18, 100.0, 255.0, 100.0, 255.0, 0)
        end
        if matched == 1
          Clay.text("1/6", font_body, 18, 100.0, 255.0, 100.0, 255.0, 0)
        end
        if matched == 2
          Clay.text("2/6", font_body, 18, 100.0, 255.0, 100.0, 255.0, 0)
        end
        if matched == 3
          Clay.text("3/6", font_body, 18, 100.0, 255.0, 100.0, 255.0, 0)
        end
        if matched == 4
          Clay.text("4/6", font_body, 18, 100.0, 255.0, 100.0, 255.0, 0)
        end
        if matched == 5
          Clay.text("5/6", font_body, 18, 100.0, 255.0, 100.0, 255.0, 0)
        end
        if matched == 6
          Clay.text("6/6", font_body, 18, 100.0, 255.0, 100.0, 255.0, 0)
        end
      Clay.close

    Clay.close  # stats

    # Card grid: 3 rows x 4 columns
    Clay.open("grid")
    Clay.layout(TTB, 8, 8, 8, 8, 8, GROW, 0.0, GROW, 0.0, AL_CENTER, AL_CENTER_Y)

      # Row 1 (cards 0-3)
      Clay.open("row1")
      Clay.layout(LTR, 0, 0, 0, 0, 8, FIT, 0.0, FIT, 0.0, AL_CENTER, AL_CENTER_Y)
        draw_card(0, font_body)
        draw_card(1, font_body)
        draw_card(2, font_body)
        draw_card(3, font_body)
      Clay.close

      # Row 2 (cards 4-7)
      Clay.open("row2")
      Clay.layout(LTR, 0, 0, 0, 0, 8, FIT, 0.0, FIT, 0.0, AL_CENTER, AL_CENTER_Y)
        draw_card(4, font_body)
        draw_card(5, font_body)
        draw_card(6, font_body)
        draw_card(7, font_body)
      Clay.close

      # Row 3 (cards 8-11)
      Clay.open("row3")
      Clay.layout(LTR, 0, 0, 0, 0, 8, FIT, 0.0, FIT, 0.0, AL_CENTER, AL_CENTER_Y)
        draw_card(8, font_body)
        draw_card(9, font_body)
        draw_card(10, font_body)
        draw_card(11, font_body)
      Clay.close

    Clay.close  # grid

    # Win message or restart hint
    Clay.open("footer")
    Clay.layout(LTR, 16, 16, 8, 8, 0, GROW, 0.0, FIT, 0.0, AL_CENTER, AL_CENTER_Y)
      if G.matched[0] == 6
        Clay.text("You Won! Press R to play again", font_heading, 24, 100.0, 255.0, 100.0, 255.0, 0)
      else
        Clay.text("Click cards to find matching pairs. Press R to restart.", font_body, 14, 140.0, 140.0, 160.0, 255.0, 0)
      end
    Clay.close

  Clay.close  # root

  Clay.end_layout
end

def main
  Raylib.set_config_flags(Raylib.flag_window_resizable)
  Raylib.init_window(WINDOW_W, WINDOW_H, "Memory Match")
  Raylib.set_target_fps(60)

  Clay.init(800.0, 600.0)

  font_body = Clay.load_font("/System/Library/Fonts/Supplemental/Arial.ttf", 32)
  font_heading = Clay.load_font("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 64)
  Clay.set_measure_text_raylib

  init_game

  while Raylib.window_should_close == 0
    dt = Raylib.get_frame_time

    # Update Clay dimensions
    w = Raylib.get_screen_width
    h = Raylib.get_screen_height
    Clay.set_dimensions(w * 1.0, h * 1.0)

    # Pointer state
    mx = Raylib.get_mouse_x
    my = Raylib.get_mouse_y
    mouse_down = Raylib.mouse_button_down?(Raylib.mouse_left)
    Clay.set_pointer(mx * 1.0, my * 1.0, mouse_down)

    # Handle click (on press)
    if Raylib.mouse_button_pressed?(Raylib.mouse_left) == 1
      handle_click
    end

    # Restart
    if Raylib.key_pressed?(Raylib.key_r) == 1
      init_game
    end

    # Update game logic
    update_game(dt)

    # Build and render layout
    draw_ui(font_body, font_heading)

    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)
    Clay.render_raylib
    Raylib.end_drawing
  end

  Clay.destroy
  Raylib.close_window
end

main
