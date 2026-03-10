# RPG Tilemap Demo — Konpeito + mruby + raylib
# rbs_inline: enabled
#
# Demonstrates: Tilemap, Camera scrolling, Player movement, Signs, HUD
# All drawing is inlined in the main loop (no helper function calls for draw)
# to work around a known mruby backend inliner issue with parameter passing.
#
# Build:
#   konpeito build --target mruby --inline -o examples/mruby_rpg_demo/rpg_demo examples/mruby_rpg_demo/rpg_demo.rb
#
# Controls: Arrow keys / WASD — Move, SPACE — Interact, ESC — Quit

# @rbs module World
# @rbs   @tilemap: NativeArray[Integer, 1600]
# @rbs   @gs: NativeArray[Integer, 20]
# @rbs end

# gs: 0=px, 1=py, 2=dir, 3=anim, 4=anim_timer, 5=cooldown,
#     6=msg_timer, 7=cam_x*100, 8=cam_y*100, 9=state, 10=msg_id, 11=steps

# ── Color helpers (integer math, no cfunc call) ──

#: (Integer r, Integer g, Integer b, Integer a) -> Integer
def rgba(r, g, b, a)
  r * 16777216 + g * 65536 + b * 256 + a
end

# ── Pseudo-random ──

#: (Integer seed) -> Integer
def prand(seed)
  seed = seed * 1103515245 + 12345
  seed = seed % 2147483647
  if seed < 0
    seed = seed + 2147483647
  end
  return seed
end

# ── Map Generation ──

#: () -> Integer
def generate_map
  # Fill grass (0)
  i = 0
  while i < 1600
    World.tilemap[i] = 0
    i = i + 1
  end

  # Paths (horizontal + vertical cross)
  x = 0
  while x < 40
    World.tilemap[20 * 40 + x] = 3
    World.tilemap[21 * 40 + x] = 3
    x = x + 1
  end
  y = 0
  while y < 40
    World.tilemap[y * 40 + 20] = 3
    World.tilemap[y * 40 + 21] = 3
    y = y + 1
  end

  # Water (lake top-right)
  wy = 3
  while wy < 10
    wx = 28
    while wx < 38
      World.tilemap[wy * 40 + wx] = 1
      wx = wx + 1
    end
    wy = wy + 1
  end

  # Trees
  seed = 12345
  i = 0
  while i < 80
    seed = prand(seed)
    tx = seed % 40
    seed = prand(seed)
    ty = seed % 40
    if World.tilemap[ty * 40 + tx] == 0
      World.tilemap[ty * 40 + tx] = 2
    end
    i = i + 1
  end

  # Houses
  World.tilemap[18 * 40 + 10] = 4
  World.tilemap[18 * 40 + 14] = 4
  World.tilemap[18 * 40 + 24] = 4

  # Signs
  World.tilemap[20 * 40 + 12] = 5
  World.tilemap[20 * 40 + 26] = 5
  World.tilemap[22 * 40 + 20] = 5

  # Flowers
  seed = 777
  i = 0
  while i < 40
    seed = prand(seed)
    fx = seed % 40
    seed = prand(seed)
    fy = seed % 40
    if World.tilemap[fy * 40 + fx] == 0
      World.tilemap[fy * 40 + fx] = 6
    end
    i = i + 1
  end

  # Rocks
  seed = 999
  i = 0
  while i < 25
    seed = prand(seed)
    rx = seed % 40
    seed = prand(seed)
    ry = seed % 40
    if World.tilemap[ry * 40 + rx] == 0
      World.tilemap[ry * 40 + rx] = 7
    end
    i = i + 1
  end

  # Clear spawn
  World.tilemap[20 * 40 + 20] = 3
  World.tilemap[20 * 40 + 19] = 3
  World.tilemap[19 * 40 + 20] = 3
  World.tilemap[21 * 40 + 20] = 3
  return 0
end

# ── Collision ──

#: (Integer tx, Integer ty) -> Integer
def is_walkable(tx, ty)
  if tx < 0
    return 0
  end
  if ty < 0
    return 0
  end
  if tx >= 40
    return 0
  end
  if ty >= 40
    return 0
  end
  tile = World.tilemap[ty * 40 + tx]
  if tile == 1
    return 0
  end
  if tile == 2
    return 0
  end
  if tile == 4
    return 0
  end
  if tile == 7
    return 0
  end
  return 1
end

# ── Camera lerp ──

#: (Integer current, Integer target) -> Integer
def lerp_cam(current, target)
  diff = target - current
  step = diff / 8
  if step == 0
    if diff > 0
      step = 1
    end
    if diff < 0
      step = -1
    end
  end
  return current + step
end

# ── Main ──

#: () -> Integer
def main
  Raylib.init_window(640, 480, "Konpeito RPG Demo")
  Raylib.set_target_fps(60)

  generate_map

  # Init player
  World.gs[0] = 20
  World.gs[1] = 20
  World.gs[2] = 0
  World.gs[3] = 0
  World.gs[5] = 0
  World.gs[6] = 0
  World.gs[7] = 20 * 32 * 100
  World.gs[8] = 20 * 32 * 100
  World.gs[9] = 0
  World.gs[10] = 0
  World.gs[11] = 0

  # Precompute colors (integer RGBA)
  c_grass     = rgba(34, 139, 34, 255)
  c_grass2    = rgba(50, 160, 50, 255)
  c_water     = rgba(30, 100, 200, 255)
  c_water2    = rgba(60, 140, 230, 255)
  c_trunk     = rgba(101, 67, 33, 255)
  c_leaves    = rgba(0, 100, 0, 255)
  c_path      = rgba(194, 178, 128, 255)
  c_wall      = rgba(180, 120, 60, 255)
  c_roof      = rgba(160, 40, 40, 255)
  c_signpost  = rgba(139, 90, 43, 255)
  c_signboard = rgba(210, 180, 120, 255)
  c_flowerr   = rgba(220, 50, 50, 255)
  c_flowery   = rgba(255, 220, 50, 255)
  c_rock      = rgba(130, 130, 130, 255)
  c_rock2     = rgba(90, 90, 90, 255)
  c_body      = rgba(50, 80, 200, 255)
  c_skin      = rgba(255, 200, 150, 255)
  c_hair      = rgba(60, 30, 10, 255)
  c_hud       = rgba(0, 0, 0, 180)
  c_msgbg     = rgba(20, 20, 60, 230)
  c_msgbdr    = rgba(200, 180, 100, 255)

  anim_counter = 0
  anim_frame = 0

  while Raylib.window_should_close == 0
    # ── Input ──
    if World.gs[9] == 1
      # Message mode
      if Raylib.key_pressed?(Raylib.key_space) != 0
        World.gs[9] = 0
      end
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        World.gs[9] = 0
      end
    else
      if World.gs[5] > 0
        World.gs[5] = World.gs[5] - 1
      else
        dx = 0
        dy = 0
        if Raylib.key_down?(Raylib.key_up) != 0
          dy = -1
          World.gs[2] = 1
        end
        if Raylib.key_down?(Raylib.key_down) != 0
          dy = 1
          World.gs[2] = 0
        end
        if Raylib.key_down?(Raylib.key_left) != 0
          dx = -1
          World.gs[2] = 2
        end
        if Raylib.key_down?(Raylib.key_right) != 0
          dx = 1
          World.gs[2] = 3
        end
        if Raylib.key_down?(Raylib.key_w) != 0
          dy = -1
          World.gs[2] = 1
        end
        if Raylib.key_down?(Raylib.key_s) != 0
          dy = 1
          World.gs[2] = 0
        end
        if Raylib.key_down?(Raylib.key_a) != 0
          dx = -1
          World.gs[2] = 2
        end
        if Raylib.key_down?(Raylib.key_d) != 0
          dx = 1
          World.gs[2] = 3
        end

        if dx != 0
          nx = World.gs[0] + dx
          if is_walkable(nx, World.gs[1]) != 0
            World.gs[0] = nx
            World.gs[3] = World.gs[3] + 1
            World.gs[11] = World.gs[11] + 1
            World.gs[5] = 6
          end
        end
        if dy != 0
          ny = World.gs[1] + dy
          if is_walkable(World.gs[0], ny) != 0
            World.gs[1] = ny
            World.gs[3] = World.gs[3] + 1
            World.gs[11] = World.gs[11] + 1
            World.gs[5] = 6
          end
        end

        # Interact
        if Raylib.key_pressed?(Raylib.key_space) != 0
          fx = World.gs[0]
          fy = World.gs[1]
          dir = World.gs[2]
          if dir == 0
            fy = fy + 1
          end
          if dir == 1
            fy = fy - 1
          end
          if dir == 2
            fx = fx - 1
          end
          if dir == 3
            fx = fx + 1
          end
          if fx >= 0
            if fy >= 0
              if fx < 40
                if fy < 40
                  ft = World.tilemap[fy * 40 + fx]
                  if ft == 5
                    World.gs[9] = 1
                    if fx == 12
                      World.gs[10] = 0
                    end
                    if fx == 26
                      World.gs[10] = 1
                    end
                    if fy == 22
                      World.gs[10] = 2
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    # ── Animation ──
    anim_counter = anim_counter + 1
    if anim_counter > 15
      anim_frame = anim_frame + 1
      anim_counter = 0
    end

    # ── Camera ──
    target_cx = World.gs[0] * 3200
    target_cy = World.gs[1] * 3200
    World.gs[7] = lerp_cam(World.gs[7], target_cx)
    World.gs[8] = lerp_cam(World.gs[8], target_cy)
    cam_x = World.gs[7] / 100
    cam_y = World.gs[8] / 100

    scroll_x = 320 - cam_x
    scroll_y = 240 - cam_y

    # ── Drawing ──
    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)

    # Visible tile range
    start_tx = (cam_x - 320) / 32 - 1
    start_ty = (cam_y - 240) / 32 - 1
    end_tx = (cam_x + 320) / 32 + 2
    end_ty = (cam_y + 240) / 32 + 2
    if start_tx < 0
      start_tx = 0
    end
    if start_ty < 0
      start_ty = 0
    end
    if end_tx > 40
      end_tx = 40
    end
    if end_ty > 40
      end_ty = 40
    end

    # Draw tiles (all inline)
    ty = start_ty
    while ty < end_ty
      tx = start_tx
      while tx < end_tx
        tile = World.tilemap[ty * 40 + tx]
        px = tx * 32 + scroll_x
        py = ty * 32 + scroll_y

        if tile == 0
          Raylib.draw_rectangle(px, py, 32, 32, c_grass)
          if (tx + ty) % 2 == 0
            Raylib.draw_rectangle(px + 12, py + 8, 2, 6, c_grass2)
          end
        end
        if tile == 1
          Raylib.draw_rectangle(px, py, 32, 32, c_water)
          if anim_frame % 2 == 0
            Raylib.draw_rectangle(px + 4, py + 10, 10, 2, c_water2)
            Raylib.draw_rectangle(px + 18, py + 20, 8, 2, c_water2)
          else
            Raylib.draw_rectangle(px + 8, py + 14, 10, 2, c_water2)
            Raylib.draw_rectangle(px + 14, py + 24, 8, 2, c_water2)
          end
        end
        if tile == 2
          Raylib.draw_rectangle(px, py, 32, 32, c_grass)
          Raylib.draw_rectangle(px + 13, py + 16, 6, 14, c_trunk)
          Raylib.draw_circle(px + 16, py + 12, 10.0, c_leaves)
        end
        if tile == 3
          Raylib.draw_rectangle(px, py, 32, 32, c_path)
        end
        if tile == 4
          Raylib.draw_rectangle(px, py, 32, 32, c_grass)
          Raylib.draw_rectangle(px + 2, py + 12, 28, 18, c_wall)
          Raylib.draw_rectangle(px + 2, py + 4, 28, 10, c_roof)
          Raylib.draw_rectangle(px + 12, py + 20, 8, 10, c_trunk)
        end
        if tile == 5
          Raylib.draw_rectangle(px, py, 32, 32, c_grass)
          Raylib.draw_rectangle(px + 14, py + 16, 4, 14, c_signpost)
          Raylib.draw_rectangle(px + 6, py + 8, 20, 12, c_signboard)
          Raylib.draw_rectangle(px + 8, py + 12, 16, 2, c_signpost)
        end
        if tile == 6
          Raylib.draw_rectangle(px, py, 32, 32, c_grass)
          if (tx + ty) % 2 == 0
            Raylib.draw_circle(px + 10, py + 14, 3.0, c_flowerr)
            Raylib.draw_circle(px + 22, py + 20, 3.0, c_flowery)
          else
            Raylib.draw_circle(px + 14, py + 10, 3.0, c_flowery)
            Raylib.draw_circle(px + 20, py + 24, 3.0, c_flowerr)
          end
        end
        if tile == 7
          Raylib.draw_rectangle(px, py, 32, 32, c_grass)
          Raylib.draw_circle(px + 16, py + 18, 10.0, c_rock)
          Raylib.draw_circle(px + 14, py + 16, 8.0, c_rock2)
        end

        tx = tx + 1
      end
      ty = ty + 1
    end

    # ── Player ──
    ppx = World.gs[0] * 32 + scroll_x
    ppy = World.gs[1] * 32 + scroll_y
    pdir = World.gs[2]
    pwalk = World.gs[3] % 4

    Raylib.draw_rectangle(ppx + 8, ppy + 10, 16, 18, c_body)
    Raylib.draw_circle(ppx + 16, ppy + 8, 7.0, c_skin)
    Raylib.draw_circle(ppx + 16, ppy + 5, 7.0, c_hair)

    if pdir == 0
      Raylib.draw_rectangle(ppx + 13, ppy + 8, 2, 2, c_hair)
      Raylib.draw_rectangle(ppx + 17, ppy + 8, 2, 2, c_hair)
    end
    if pdir == 1
      Raylib.draw_rectangle(ppx + 8, ppy + 2, 16, 6, c_hair)
    end
    if pdir == 2
      Raylib.draw_rectangle(ppx + 11, ppy + 7, 2, 2, c_hair)
    end
    if pdir == 3
      Raylib.draw_rectangle(ppx + 19, ppy + 7, 2, 2, c_hair)
    end

    if pwalk == 0
      Raylib.draw_rectangle(ppx + 10, ppy + 28, 5, 4, c_hair)
      Raylib.draw_rectangle(ppx + 17, ppy + 28, 5, 4, c_hair)
    end
    if pwalk == 1
      Raylib.draw_rectangle(ppx + 9, ppy + 28, 5, 4, c_hair)
      Raylib.draw_rectangle(ppx + 18, ppy + 28, 5, 4, c_hair)
    end
    if pwalk == 2
      Raylib.draw_rectangle(ppx + 10, ppy + 28, 5, 4, c_hair)
      Raylib.draw_rectangle(ppx + 17, ppy + 28, 5, 4, c_hair)
    end
    if pwalk == 3
      Raylib.draw_rectangle(ppx + 11, ppy + 28, 5, 4, c_hair)
      Raylib.draw_rectangle(ppx + 16, ppy + 28, 5, 4, c_hair)
    end

    # ── HUD ──
    Raylib.draw_rectangle(0, 0, 640, 32, c_hud)
    Raylib.draw_text("Konpeito RPG Demo", 8, 6, 20, Raylib.color_gold)

    steps = World.gs[11]
    Raylib.draw_text("Steps:", 500, 8, 16, Raylib.color_lightgray)
    # Digit display
    d3 = steps / 100
    d2 = (steps % 100) / 10
    d1 = steps % 10
    xp = 570
    if d3 > 0
      Raylib.draw_text("1", xp, 8, 16, Raylib.color_white) if d3 == 1
      Raylib.draw_text("2", xp, 8, 16, Raylib.color_white) if d3 == 2
      Raylib.draw_text("3", xp, 8, 16, Raylib.color_white) if d3 == 3
      Raylib.draw_text("4", xp, 8, 16, Raylib.color_white) if d3 == 4
      Raylib.draw_text("5", xp, 8, 16, Raylib.color_white) if d3 == 5
      Raylib.draw_text("6", xp, 8, 16, Raylib.color_white) if d3 == 6
      Raylib.draw_text("7", xp, 8, 16, Raylib.color_white) if d3 == 7
      Raylib.draw_text("8", xp, 8, 16, Raylib.color_white) if d3 == 8
      Raylib.draw_text("9", xp, 8, 16, Raylib.color_white) if d3 == 9
      xp = xp + 10
    end
    if d3 > 0
      Raylib.draw_text("0", xp, 8, 16, Raylib.color_white) if d2 == 0
    end
    if d2 > 0
      Raylib.draw_text("1", xp, 8, 16, Raylib.color_white) if d2 == 1
      Raylib.draw_text("2", xp, 8, 16, Raylib.color_white) if d2 == 2
      Raylib.draw_text("3", xp, 8, 16, Raylib.color_white) if d2 == 3
      Raylib.draw_text("4", xp, 8, 16, Raylib.color_white) if d2 == 4
      Raylib.draw_text("5", xp, 8, 16, Raylib.color_white) if d2 == 5
      Raylib.draw_text("6", xp, 8, 16, Raylib.color_white) if d2 == 6
      Raylib.draw_text("7", xp, 8, 16, Raylib.color_white) if d2 == 7
      Raylib.draw_text("8", xp, 8, 16, Raylib.color_white) if d2 == 8
      Raylib.draw_text("9", xp, 8, 16, Raylib.color_white) if d2 == 9
      xp = xp + 10
    end
    Raylib.draw_text("0", xp, 8, 16, Raylib.color_white) if d1 == 0
    Raylib.draw_text("1", xp, 8, 16, Raylib.color_white) if d1 == 1
    Raylib.draw_text("2", xp, 8, 16, Raylib.color_white) if d1 == 2
    Raylib.draw_text("3", xp, 8, 16, Raylib.color_white) if d1 == 3
    Raylib.draw_text("4", xp, 8, 16, Raylib.color_white) if d1 == 4
    Raylib.draw_text("5", xp, 8, 16, Raylib.color_white) if d1 == 5
    Raylib.draw_text("6", xp, 8, 16, Raylib.color_white) if d1 == 6
    Raylib.draw_text("7", xp, 8, 16, Raylib.color_white) if d1 == 7
    Raylib.draw_text("8", xp, 8, 16, Raylib.color_white) if d1 == 8
    Raylib.draw_text("9", xp, 8, 16, Raylib.color_white) if d1 == 9

    Raylib.draw_text("[SPACE] Interact", 8, 462, 14, Raylib.color_gray)

    # ── Message Box ──
    if World.gs[9] == 1
      Raylib.draw_rectangle(38, 348, 564, 104, c_msgbdr)
      Raylib.draw_rectangle(40, 350, 560, 100, c_msgbg)
      mid = World.gs[10]
      if mid == 0
        Raylib.draw_text("Welcome to Konpeito Village!", 56, 366, 20, Raylib.color_white)
        Raylib.draw_text("A peaceful place for Ruby devs.", 56, 394, 16, Raylib.color_lightgray)
      end
      if mid == 1
        Raylib.draw_text("Lake Prism ahead!", 56, 366, 20, Raylib.color_skyblue)
        Raylib.draw_text("Watch out, the water is deep.", 56, 394, 16, Raylib.color_lightgray)
      end
      if mid == 2
        Raylib.draw_text("Crossroads of Crystal Path.", 56, 366, 20, Raylib.color_gold)
        Raylib.draw_text("North: Forest  South: Plains", 56, 394, 16, Raylib.color_lightgray)
      end
      Raylib.draw_text("[SPACE] close", 460, 430, 14, Raylib.color_gray)
    end

    Raylib.end_drawing
  end

  Raylib.close_window
  return 0
end

main
