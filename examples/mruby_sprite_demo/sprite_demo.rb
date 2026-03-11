# rbs_inline: enabled
require_relative "./rpg_framework"

# ═══════════════════════════════════════════════════════════════
# Konpeito Sprite Demo (using RPG Framework)
# Demonstrates: texture loading, spritesheet animation,
#   tilemap rendering, smooth character movement, chest interaction
# ═══════════════════════════════════════════════════════════════

# @rbs module G
# @rbs   @map: NativeArray[Integer, 300]
# @rbs   @s: NativeArray[Integer, 32]
# @rbs   @obj: NativeArray[Integer, 80]
# @rbs end

# ── G.s layout ──
# [0] tileset tex  [1] hero tex  [2] slime tex  [3] chest tex
# [4] anim_counter [5] anim_frame (0-3)
# [10] hero px  [11] hero py  [12] hero dir (0=down 1=up 2=left 3=right)
# [13] target px  [14] target py  [15] moving (0/1)
# [17] msg_timer  [18] msg_id
# [30] font_id + 1 (used by fw_draw_txt)
# [31] frame counter (used by fw_tick)

# ── G.obj layout: 10 objects × 8 fields ──
# off=i*8: [0]type(0=none 1=slime 2=chest) [1]tile_x [2]tile_y [3]state

# Tile types: 0=grass 1=water 2=sand 3=stone 4=tree 5=wall 6=path 7=flower

# ════════════════════════════════════════════
# Section 1: Map Initialization
# ════════════════════════════════════════════

#: () -> Integer
def init_map
  i = 0
  while i < 300
    G.map[i] = 0
    i = i + 1
  end

  # Water border
  x = 0
  while x < 20
    G.map[x] = 1
    G.map[14 * 20 + x] = 1
    x = x + 1
  end
  y = 0
  while y < 15
    G.map[y * 20] = 1
    G.map[y * 20 + 19] = 1
    y = y + 1
  end

  # Horizontal path (row 7)
  x = 1
  while x < 19
    G.map[7 * 20 + x] = 6
    x = x + 1
  end

  # Vertical path (column 10)
  y = 2
  while y < 13
    G.map[y * 20 + 10] = 6
    y = y + 1
  end

  # Trees (forest top-left)
  G.map[2 * 20 + 2] = 4
  G.map[2 * 20 + 3] = 4
  G.map[2 * 20 + 4] = 4
  G.map[3 * 20 + 2] = 4
  G.map[3 * 20 + 3] = 4
  G.map[3 * 20 + 4] = 4
  G.map[4 * 20 + 2] = 4
  G.map[4 * 20 + 3] = 4

  # Trees (bottom-left)
  G.map[10 * 20 + 2] = 4
  G.map[10 * 20 + 3] = 4
  G.map[11 * 20 + 2] = 4
  G.map[11 * 20 + 3] = 4
  G.map[11 * 20 + 4] = 4
  G.map[12 * 20 + 2] = 4
  G.map[12 * 20 + 3] = 4

  # Stone ruin (top-right)
  G.map[2 * 20 + 14] = 5
  G.map[2 * 20 + 15] = 5
  G.map[2 * 20 + 16] = 5
  G.map[2 * 20 + 17] = 5
  G.map[3 * 20 + 14] = 5
  G.map[3 * 20 + 17] = 5
  G.map[4 * 20 + 14] = 5
  G.map[4 * 20 + 15] = 3
  G.map[4 * 20 + 16] = 3
  G.map[4 * 20 + 17] = 5

  # Sand beach (bottom-right)
  G.map[10 * 20 + 15] = 2
  G.map[10 * 20 + 16] = 2
  G.map[10 * 20 + 17] = 2
  G.map[11 * 20 + 14] = 2
  G.map[11 * 20 + 15] = 2
  G.map[11 * 20 + 16] = 2
  G.map[11 * 20 + 17] = 2
  G.map[11 * 20 + 18] = 2
  G.map[12 * 20 + 15] = 2
  G.map[12 * 20 + 16] = 2
  G.map[12 * 20 + 17] = 2
  G.map[12 * 20 + 18] = 2

  # Flowers
  G.map[5 * 20 + 5] = 7
  G.map[5 * 20 + 6] = 7
  G.map[6 * 20 + 3] = 7
  G.map[8 * 20 + 15] = 7
  G.map[9 * 20 + 5] = 7
  G.map[9 * 20 + 17] = 7

  # Small pond
  G.map[9 * 20 + 13] = 1
  G.map[9 * 20 + 14] = 1
  G.map[10 * 20 + 13] = 1
  G.map[10 * 20 + 14] = 1

  return 0
end

# ════════════════════════════════════════════
# Section 2: Object Initialization
# ════════════════════════════════════════════

#: () -> Integer
def init_objects
  i = 0
  while i < 80
    G.obj[i] = 0
    i = i + 1
  end

  # Slime at (6, 5)
  G.obj[0] = 1
  G.obj[1] = 6
  G.obj[2] = 5
  G.obj[3] = 1

  # Slime at (14, 9)
  G.obj[8] = 1
  G.obj[9] = 14
  G.obj[10] = 9
  G.obj[11] = 1

  # Slime at (8, 11)
  G.obj[16] = 1
  G.obj[17] = 8
  G.obj[18] = 11
  G.obj[19] = 1

  # Chest at (15, 3) inside ruin
  G.obj[24] = 2
  G.obj[25] = 15
  G.obj[26] = 3
  G.obj[27] = 0

  # Chest at (4, 12) near trees
  G.obj[32] = 2
  G.obj[33] = 4
  G.obj[34] = 12
  G.obj[35] = 0

  return 0
end

# ════════════════════════════════════════════
# Section 3: Collision
# ════════════════════════════════════════════

#: (Integer tx, Integer ty) -> Integer
def can_walk(tx, ty)
  if tx < 1
    return 0
  end
  if ty < 1
    return 0
  end
  if tx > 18
    return 0
  end
  if ty > 13
    return 0
  end
  tile = G.map[ty * 20 + tx]
  if tile == 1
    return 0
  end
  if tile == 4
    return 0
  end
  if tile == 5
    return 0
  end
  return 1
end

# ════════════════════════════════════════════
# Section 4: Update (uses framework helpers)
# ════════════════════════════════════════════

#: () -> Integer
def update_game
  fw_tick
  fw_animate(4, 5, 4, 10)

  # Message timer
  if G.s[17] > 0
    G.s[17] = G.s[17] - 1
  end

  # Hero movement (manual: G.s[12]=direction sits between px/py and target)
  if G.s[15] == 1
    px = G.s[10]
    py = G.s[11]
    tx = G.s[13]
    ty = G.s[14]
    spd = 4

    if px < tx
      px = px + spd
      if px > tx
        px = tx
      end
    end
    if px > tx
      px = px - spd
      if px < tx
        px = tx
      end
    end
    if py < ty
      py = py + spd
      if py > ty
        py = ty
      end
    end
    if py > ty
      py = py - spd
      if py < ty
        py = ty
      end
    end

    G.s[10] = px
    G.s[11] = py

    if px == tx
      if py == ty
        G.s[15] = 0
      end
    end
  else
    # Check direction input (uses framework helper)
    dir = fw_get_direction
    cx = G.s[10] / 32
    cy = G.s[11] / 32

    if dir == 0
      G.s[12] = 0
      if can_walk(cx, cy + 1) == 1
        G.s[13] = cx * 32
        G.s[14] = (cy + 1) * 32
        G.s[15] = 1
      end
    end
    if dir == 1
      G.s[12] = 1
      if can_walk(cx, cy - 1) == 1
        G.s[13] = cx * 32
        G.s[14] = (cy - 1) * 32
        G.s[15] = 1
      end
    end
    if dir == 2
      G.s[12] = 2
      if can_walk(cx - 1, cy) == 1
        G.s[13] = (cx - 1) * 32
        G.s[14] = cy * 32
        G.s[15] = 1
      end
    end
    if dir == 3
      G.s[12] = 3
      if can_walk(cx + 1, cy) == 1
        G.s[13] = (cx + 1) * 32
        G.s[14] = cy * 32
        G.s[15] = 1
      end
    end

    # Interact with Enter (uses framework helper)
    if fw_confirm_pressed != 0
      fx = cx
      fy = cy
      d = G.s[12]
      if d == 0
        fy = cy + 1
      end
      if d == 1
        fy = cy - 1
      end
      if d == 2
        fx = cx - 1
      end
      if d == 3
        fx = cx + 1
      end

      i = 0
      while i < 10
        off = i * 8
        otype = G.obj[off]
        if otype == 2
          ox = G.obj[off + 1]
          oy = G.obj[off + 2]
          if ox == fx
            if oy == fy
              if G.obj[off + 3] == 0
                G.obj[off + 3] = 1
                G.s[17] = 120
                G.s[18] = 1
              end
            end
          end
        end
        i = i + 1
      end
    end
  end

  return 0
end

# ════════════════════════════════════════════
# Section 5: Draw (uses framework helpers)
# ════════════════════════════════════════════

#: () -> Integer
def draw_game
  Raylib.begin_drawing
  Raylib.clear_background(Raylib.color_black)

  # Tilemap (uses framework tile drawing)
  y = 0
  while y < 15
    x = 0
    while x < 20
      tile = G.map[y * 20 + x]
      fw_draw_tile(G.s[0], tile, 8, 16, 32, x * 32, y * 32)
      x = x + 1
    end
    y = y + 1
  end

  # Objects (slimes & chests)
  aframe = G.s[5]
  i = 0
  while i < 10
    off = i * 8
    otype = G.obj[off]
    if otype == 1
      if G.obj[off + 3] == 1
        ox = G.obj[off + 1] * 32
        oy = G.obj[off + 2] * 32
        fw_draw_sprite(G.s[2], aframe, 16, 16, ox, oy, 32, 32)
      end
    end
    if otype == 2
      ox = G.obj[off + 1] * 32
      oy = G.obj[off + 2] * 32
      cstate = G.obj[off + 3]
      fw_draw_sprite(G.s[3], cstate, 16, 16, ox, oy, 32, 32)
    end
    i = i + 1
  end

  # Hero (uses framework grid sprite drawing)
  hdir = G.s[12]
  hframe = 0
  if G.s[15] == 1
    dx = G.s[10] - G.s[13]
    dy = G.s[11] - G.s[14]
    if dx < 0
      dx = 0 - dx
    end
    if dy < 0
      dy = 0 - dy
    end
    dist = dx + dy
    hframe = (dist / 8) % 4
  end
  fw_draw_sprite_grid(G.s[1], hdir, hframe, 16, 16, G.s[10], G.s[11], 32, 32)

  # HUD bar
  Raylib.draw_rectangle(0, 448, 640, 32, Raylib.color_black)
  fw_draw_txt("Arrow/WASD: Move   Enter: Open Chests", 8, 454, 16, Raylib.color_lightgray)

  # Message popup (uses framework window drawing)
  if G.s[17] > 0
    fw_draw_window(170, 200, 300, 60, Raylib.color_black, Raylib.color_gold)
    if G.s[18] == 1
      fw_draw_txt("Opened the chest!", 210, 218, 20, Raylib.color_gold)
    end
  end

  fw_draw_txt("Sprite Demo", 250, 454, 16, Raylib.color_darkgray)

  Raylib.end_drawing
  return 0
end

# ════════════════════════════════════════════
# Section 6: Main
# ════════════════════════════════════════════

#: () -> Integer
def main
  Raylib.set_config_flags(Raylib.flag_msaa_4x_hint)
  Raylib.init_window(640, 480, "Konpeito Sprite Demo")
  Raylib.set_target_fps(60)

  # Load font (store as font_id+1 in G.s[30] for fw_draw_txt)
  G.s[30] = Raylib.load_font_ex("/System/Library/Fonts/Supplemental/Verdana.ttf", 32) + 1

  # Load textures
  G.s[0] = Raylib.load_texture("examples/mruby_sprite_demo/assets/tileset.png")
  G.s[1] = Raylib.load_texture("examples/mruby_sprite_demo/assets/hero.png")
  G.s[2] = Raylib.load_texture("examples/mruby_sprite_demo/assets/slime.png")
  G.s[3] = Raylib.load_texture("examples/mruby_sprite_demo/assets/chest.png")

  init_map
  init_objects

  # Hero start at path intersection (tile 10, 7)
  G.s[10] = 10 * 32
  G.s[11] = 7 * 32
  G.s[12] = 0
  G.s[13] = G.s[10]
  G.s[14] = G.s[11]

  while Raylib.window_should_close == 0
    update_game
    draw_game
  end

  Raylib.unload_texture(G.s[0])
  Raylib.unload_texture(G.s[1])
  Raylib.unload_texture(G.s[2])
  Raylib.unload_texture(G.s[3])
  Raylib.close_window
  return 0
end

main
