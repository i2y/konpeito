# frozen_string_literal: true

# Konpeito RPG Framework - Reusable helpers for 2D games
#
# Usage: place in same directory as game file, then:
#   require_relative "./rpg_framework"
#
# Requires module G with @s: NativeArray[Integer, 32+] declared.
# Framework uses G.s[28..31] for internal state:
#   G.s[28] = previous scene ID (for fw_scene_push/pop)
#   G.s[29] = random seed
#   G.s[30] = font_id + 1 (0 = not loaded, used by fw_draw_txt)
#   G.s[31] = global frame counter (for cursor blink etc.)
#
# Sections 1-10: Raylib drawing helpers (math, color, drawing, input, etc.)
# Section 11: Clay UI helpers (optional, requires Clay module)
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Section 1: Math Helpers
# ════════════════════════════════════════════

#: (Integer v, Integer lo, Integer hi) -> Integer
def fw_clamp(v, lo, hi)
  if v < lo
    return lo
  end
  if v > hi
    return hi
  end
  return v
end

# Pseudo-random number generator (Linear Congruential).
# Advances seed in G.s[29] and returns value in [0, mod).
#: (Integer mod) -> Integer
def fw_rand(mod)
  seed = G.s[29]
  seed = seed * 1103515245 + 12345
  seed = seed % 2147483647
  if seed < 0
    seed = seed + 2147483647
  end
  G.s[29] = seed
  return seed % mod
end

# Smooth camera-style interpolation (step = diff / divisor, min ±1).
#: (Integer current, Integer target, Integer divisor) -> Integer
def fw_lerp(current, target, divisor)
  diff = target - current
  if diff == 0
    return current
  end
  step = diff / divisor
  if step == 0
    if diff > 0
      step = 1
    end
    if diff < 0
      step = 0 - 1
    end
  end
  return current + step
end

# ════════════════════════════════════════════
# Section 2: Color Helper
# ════════════════════════════════════════════

# Encode RGBA color as 32-bit integer.
#: (Integer r, Integer g, Integer b, Integer a) -> Integer
def fw_rgba(r, g, b, a)
  return r * 16777216 + g * 65536 + b * 256 + a
end

# ════════════════════════════════════════════
# Section 3: Drawing Helpers
# ════════════════════════════════════════════

# Draw text with font fallback.
# Font slot stored as (font_id + 1) in G.s[30]. 0 = not loaded.
#: (String text, Integer x, Integer y, Integer sz, Integer col) -> Integer
def fw_draw_txt(text, x, y, sz, col)
  fid = G.s[30]
  if fid > 0
    Raylib.draw_text_ex(fid - 1, text, x * 1.0, y * 1.0, sz * 1.0, 1.0, col)
  else
    Raylib.draw_text(text, x, y, sz, col)
  end
  return 0
end

# Draw single digit (0-9) as text.
#: (Integer x, Integer y, Integer d, Integer sz, Integer col) -> Integer
def fw_draw_d(x, y, d, sz, col)
  if d == 0
    fw_draw_txt("0", x, y, sz, col)
  end
  if d == 1
    fw_draw_txt("1", x, y, sz, col)
  end
  if d == 2
    fw_draw_txt("2", x, y, sz, col)
  end
  if d == 3
    fw_draw_txt("3", x, y, sz, col)
  end
  if d == 4
    fw_draw_txt("4", x, y, sz, col)
  end
  if d == 5
    fw_draw_txt("5", x, y, sz, col)
  end
  if d == 6
    fw_draw_txt("6", x, y, sz, col)
  end
  if d == 7
    fw_draw_txt("7", x, y, sz, col)
  end
  if d == 8
    fw_draw_txt("8", x, y, sz, col)
  end
  if d == 9
    fw_draw_txt("9", x, y, sz, col)
  end
  return 0
end

# Draw integer number (handles negative, up to 5 digits).
#: (Integer x, Integer y, Integer n, Integer sz, Integer col) -> Integer
def fw_draw_num(x, y, n, sz, col)
  sp = sz * 6 / 10
  if n < 0
    fw_draw_txt("-", x, y, sz, col)
    x = x + sp
    n = 0 - n
  end
  if n >= 10000
    fw_draw_d(x, y, n / 10000, sz, col)
    x = x + sp
  end
  if n >= 1000
    fw_draw_d(x, y, (n / 1000) % 10, sz, col)
    x = x + sp
  end
  if n >= 100
    fw_draw_d(x, y, (n / 100) % 10, sz, col)
    x = x + sp
  end
  if n >= 10
    fw_draw_d(x, y, (n / 10) % 10, sz, col)
    x = x + sp
  end
  fw_draw_d(x, y, n % 10, sz, col)
  return 0
end

# 3-layer RPG window (border + dark bg + inner bg).
#: (Integer x, Integer y, Integer w, Integer h) -> Integer
def fw_draw_window(x, y, w, h)
  c_border = fw_rgba(200, 180, 100, 255)
  c_bg = fw_rgba(16, 16, 64, 230)
  c_inner = fw_rgba(40, 40, 100, 200)
  Raylib.draw_rectangle(x, y, w, h, c_border)
  Raylib.draw_rectangle(x + 2, y + 2, w - 4, h - 4, c_bg)
  Raylib.draw_rectangle(x + 4, y + 4, w - 8, h - 8, c_inner)
  return 0
end

# Simple window with custom colors (border + fill).
#: (Integer x, Integer y, Integer w, Integer h, Integer bg_col, Integer border_col) -> Integer
def fw_draw_box(x, y, w, h, bg_col, border_col)
  Raylib.draw_rectangle(x, y, w, h, bg_col)
  Raylib.draw_rectangle_lines(x, y, w, h, border_col)
  return 0
end

# HP/MP bar with background.
#: (Integer x, Integer y, Integer w, Integer h, Integer val, Integer mx, Integer fill_col) -> Integer
def fw_draw_bar(x, y, w, h, val, mx, fill_col)
  c_bg = fw_rgba(40, 40, 40, 255)
  Raylib.draw_rectangle(x, y, w, h, c_bg)
  if mx > 0
    bw = val * w / mx
    if bw < 0
      bw = 0
    end
    if bw > w
      bw = w
    end
    if bw > 0
      Raylib.draw_rectangle(x, y, bw, h, fill_col)
    end
  end
  return 0
end

# Blinking ">" cursor.
#: (Integer x, Integer y, Integer sz, Integer col) -> Integer
def fw_draw_cursor(x, y, sz, col)
  blink = (G.s[31] / 20) % 2
  if blink == 0
    fw_draw_txt(">", x, y, sz, col)
  end
  return 0
end

# Draw a tile from a tileset (grid layout: cols tiles per row).
#: (Integer tex_id, Integer tile_id, Integer cols, Integer src_sz, Integer dst_sz, Integer dx, Integer dy) -> Integer
def fw_draw_tile(tex_id, tile_id, cols, src_sz, dst_sz, dx, dy)
  src_x = (tile_id % cols) * src_sz
  src_y = (tile_id / cols) * src_sz
  Raylib.draw_texture_pro(tex_id,
    src_x * 1.0, src_y * 1.0, src_sz * 1.0, src_sz * 1.0,
    dx * 1.0, dy * 1.0, dst_sz * 1.0, dst_sz * 1.0,
    0.0, 0.0, 0.0, Raylib.color_white)
  return 0
end

# Draw a sprite frame from a horizontal spritesheet.
#: (Integer tex_id, Integer frame, Integer src_w, Integer src_h, Integer dx, Integer dy, Integer dst_w, Integer dst_h) -> Integer
def fw_draw_sprite(tex_id, frame, src_w, src_h, dx, dy, dst_w, dst_h)
  Raylib.draw_texture_pro(tex_id,
    (frame * src_w) * 1.0, 0.0, src_w * 1.0, src_h * 1.0,
    dx * 1.0, dy * 1.0, dst_w * 1.0, dst_h * 1.0,
    0.0, 0.0, 0.0, Raylib.color_white)
  return 0
end

# Draw a sprite frame from a grid spritesheet (row x col).
#: (Integer tex_id, Integer row, Integer col, Integer src_w, Integer src_h, Integer dx, Integer dy, Integer dst_w, Integer dst_h) -> Integer
def fw_draw_sprite_grid(tex_id, row, col, src_w, src_h, dx, dy, dst_w, dst_h)
  Raylib.draw_texture_pro(tex_id,
    (col * src_w) * 1.0, (row * src_h) * 1.0, src_w * 1.0, src_h * 1.0,
    dx * 1.0, dy * 1.0, dst_w * 1.0, dst_h * 1.0,
    0.0, 0.0, 0.0, Raylib.color_white)
  return 0
end

# ════════════════════════════════════════════
# Section 4: Input Helpers
# ════════════════════════════════════════════

# Get directional input: 0=down, 1=up, 2=left, 3=right, -1=none.
# Supports arrow keys and WASD.
#: () -> Integer
def fw_get_direction
  if Raylib.key_down?(Raylib.key_down) != 0
    return 0
  end
  if Raylib.key_down?(Raylib.key_s) != 0
    return 0
  end
  if Raylib.key_down?(Raylib.key_up) != 0
    return 1
  end
  if Raylib.key_down?(Raylib.key_w) != 0
    return 1
  end
  if Raylib.key_down?(Raylib.key_left) != 0
    return 2
  end
  if Raylib.key_down?(Raylib.key_a) != 0
    return 2
  end
  if Raylib.key_down?(Raylib.key_right) != 0
    return 3
  end
  if Raylib.key_down?(Raylib.key_d) != 0
    return 3
  end
  return 0 - 1
end

# Check if confirm button pressed (Enter/Space). Returns 1 or 0.
#: () -> Integer
def fw_confirm_pressed
  if Raylib.key_pressed?(Raylib.key_enter) != 0
    return 1
  end
  if Raylib.key_pressed?(Raylib.key_space) != 0
    return 1
  end
  return 0
end

# Check if cancel button pressed (Escape/X). Returns 1 or 0.
#: () -> Integer
def fw_cancel_pressed
  if Raylib.key_pressed?(Raylib.key_escape) != 0
    return 1
  end
  if Raylib.key_pressed?(Raylib.key_x) != 0
    return 1
  end
  return 0
end

# ════════════════════════════════════════════
# Section 5: Menu Cursor Helper
# ════════════════════════════════════════════

# Handle vertical cursor movement with wrapping. Returns new position.
#: (Integer cursor_val, Integer count) -> Integer
def fw_menu_cursor(cursor_val, count)
  if Raylib.key_pressed?(Raylib.key_up) != 0
    cursor_val = cursor_val - 1
    if cursor_val < 0
      cursor_val = count - 1
    end
  end
  if Raylib.key_pressed?(Raylib.key_down) != 0
    cursor_val = cursor_val + 1
    if cursor_val >= count
      cursor_val = 0
    end
  end
  return cursor_val
end

# ════════════════════════════════════════════
# Section 6: Animation Helper
# ════════════════════════════════════════════

# Advance frame animation (call once per game frame).
# counter_idx, frame_idx = G.s[] slot indices.
# Returns current animation frame.
#: (Integer counter_idx, Integer frame_idx, Integer max_frames, Integer speed) -> Integer
def fw_animate(counter_idx, frame_idx, max_frames, speed)
  G.s[counter_idx] = G.s[counter_idx] + 1
  if G.s[counter_idx] >= speed
    G.s[frame_idx] = (G.s[frame_idx] + 1) % max_frames
    G.s[counter_idx] = 0
  end
  return G.s[frame_idx]
end

# ════════════════════════════════════════════
# Section 7: Scene Management
# ════════════════════════════════════════════

# Uses G.s[28] for previous scene.
# Scene IDs are user-defined integers.

# Push scene: saves prev in G.s[28], sets new scene in the given slot.
#: (Integer scene_slot, Integer new_scene) -> Integer
def fw_scene_push(scene_slot, new_scene)
  G.s[28] = G.s[scene_slot]
  G.s[scene_slot] = new_scene
  return 0
end

# Pop scene: restores prev from G.s[28].
#: (Integer scene_slot) -> Integer
def fw_scene_pop(scene_slot)
  G.s[scene_slot] = G.s[28]
  return 0
end

# ════════════════════════════════════════════
# Section 8: Smooth Movement Helper
# ════════════════════════════════════════════

# Smooth pixel-based movement.
# Uses 4 consecutive G.s[] slots: [px, py, target_x, target_y].
# Returns 1 if still moving, 0 if arrived.
#: (Integer base_idx, Integer speed) -> Integer
def fw_smooth_move(base_idx, speed)
  px = G.s[base_idx]
  py = G.s[base_idx + 1]
  tx = G.s[base_idx + 2]
  ty = G.s[base_idx + 3]

  if px < tx
    px = px + speed
    if px > tx
      px = tx
    end
  end
  if px > tx
    px = px - speed
    if px < tx
      px = tx
    end
  end
  if py < ty
    py = py + speed
    if py > ty
      py = ty
    end
  end
  if py > ty
    py = py - speed
    if py < ty
      py = ty
    end
  end

  G.s[base_idx] = px
  G.s[base_idx + 1] = py

  if px == tx
    if py == ty
      return 0
    end
  end
  return 1
end

# ════════════════════════════════════════════
# Section 9: Battle Helpers
# ════════════════════════════════════════════

# Calculate damage: ATK - DEF/2 +/- variance. Minimum 1.
# Uses fw_rand() internally.
#: (Integer atk, Integer def_val) -> Integer
def fw_calc_damage(atk, def_val)
  base = atk - def_val / 2
  if base < 1
    base = 1
  end
  variance = fw_rand(5) - 2
  dmg = base + variance
  if dmg < 1
    dmg = 1
  end
  return dmg
end

# ════════════════════════════════════════════
# Section 10: Framework Tick
# ════════════════════════════════════════════

# Update framework counters (call at start of each frame).
#: () -> Integer
def fw_tick
  G.s[31] = G.s[31] + 1
  return 0
end

# ════════════════════════════════════════════
# Section 11: Clay UI Helpers
# ════════════════════════════════════════════
#
# Optional Clay UI integration for Flexbox-style layouts.
# Requires Clay module (auto-detected when referenced).
#
# Sizing: FIT=0, GROW=1, FIXED=2, PERCENT=3
# Direction: LEFT_TO_RIGHT=0, TOP_TO_BOTTOM=1
# Alignment: LEFT/TOP=0, RIGHT/BOTTOM=1, CENTER=2

# Per-frame Clay setup: update dimensions, pointer, and begin layout.
# Call once per frame before building UI. Pair with fw_clay_frame_end.
#: () -> Integer
def fw_clay_frame_begin
  w = Raylib.get_screen_width
  h = Raylib.get_screen_height
  Clay.set_dimensions(w * 1.0, h * 1.0)
  mx = Raylib.get_mouse_x
  my = Raylib.get_mouse_y
  md = Raylib.mouse_button_down?(Raylib.mouse_left)
  Clay.set_pointer(mx * 1.0, my * 1.0, md)
  Clay.begin_layout
  return 0
end

# End Clay layout and render all commands via raylib.
# Call once per frame after building UI (between begin/end_drawing).
#: () -> Integer
def fw_clay_frame_end
  Clay.end_layout
  Clay.render_raylib
  return 0
end

# Open a vertical container (GROW width, GROW height).
# Caller must call Clay.close when done adding children.
#: (String id, Integer pad, Integer gap) -> Integer
def fw_clay_vbox(id, pad, gap)
  Clay.open(id)
  Clay.layout(1, pad, pad, pad, pad, gap, 1, 0.0, 1, 0.0, 0, 0)
  return 0
end

# Open a horizontal container (GROW width, FIT height).
# Caller must call Clay.close when done adding children.
#: (String id, Integer pad, Integer gap) -> Integer
def fw_clay_hbox(id, pad, gap)
  Clay.open(id)
  Clay.layout(0, pad, pad, pad, pad, gap, 1, 0.0, 0, 0.0, 0, 0)
  return 0
end

# Open a centered horizontal container (GROW width, FIT height, center-aligned).
#: (String id, Integer pad, Integer gap) -> Integer
def fw_clay_hbox_center(id, pad, gap)
  Clay.open(id)
  Clay.layout(0, pad, pad, pad, pad, gap, 1, 0.0, 0, 0.0, 2, 2)
  return 0
end

# Open a fixed-size vertical container.
# Caller must call Clay.close when done adding children.
#: (String id, Integer w, Integer h, Integer pad) -> Integer
def fw_clay_fixed_box(id, w, h, pad)
  Clay.open(id)
  Clay.layout(1, pad, pad, pad, pad, 4, 2, w * 1.0, 2, h * 1.0, 0, 0)
  return 0
end

# Apply RPG-style background and border to the current element.
# Dark blue background with gold border (matches fw_draw_window colors).
# Call after Clay.open and Clay.layout, before adding children.
#: () -> Integer
def fw_clay_rpg_bg
  Clay.bg(16.0, 16.0, 64.0, 230.0, 4.0)
  Clay.border(200.0, 180.0, 100.0, 255.0, 2, 2, 2, 2, 4.0)
  return 0
end

# Open an RPG-style window: fixed-size vertical container with
# dark blue background and gold border.
# Caller must call Clay.close when done adding children.
#: (String id, Integer w, Integer h, Integer pad) -> Integer
def fw_clay_rpg_window(id, w, h, pad)
  Clay.open(id)
  Clay.layout(1, pad, pad, pad, pad, 4, 2, w * 1.0, 2, h * 1.0, 0, 0)
  Clay.bg(16.0, 16.0, 64.0, 230.0, 4.0)
  Clay.border(200.0, 180.0, 100.0, 255.0, 2, 2, 2, 2, 4.0)
  return 0
end

# White text element.
#: (String text, Integer font_id, Integer sz) -> Integer
def fw_clay_text(text, font_id, sz)
  Clay.text(text, font_id, sz, 255.0, 255.0, 255.0, 255.0, 0)
  return 0
end

# Colored text element (RGB 0-255).
#: (String text, Integer font_id, Integer sz, Integer r, Integer g, Integer b) -> Integer
def fw_clay_text_color(text, font_id, sz, r, g, b)
  Clay.text(text, font_id, sz, r * 1.0, g * 1.0, b * 1.0, 255.0, 0)
  return 0
end

# HP/MP bar as a self-contained Clay element.
# Opens and closes its own container. idx must be unique per bar.
#: (String id, Integer idx, Integer val, Integer mx, Integer w, Integer h, Integer r, Integer g, Integer b) -> Integer
def fw_clay_bar(id, idx, val, mx, w, h, r, g, b)
  Clay.open_i(id, idx)
  Clay.layout(0, 0, 0, 0, 0, 0, 2, w * 1.0, 2, h * 1.0, 0, 0)
  Clay.bg(40.0, 40.0, 40.0, 255.0, 2.0)

  if mx > 0
    fill_w = val * w / mx
    if fill_w < 0
      fill_w = 0
    end
    if fill_w > w
      fill_w = w
    end
    if fill_w > 0
      Clay.open_i("_bfl", idx)
      Clay.layout(0, 0, 0, 0, 0, 0, 2, fill_w * 1.0, 2, h * 1.0, 0, 0)
      Clay.bg(r * 1.0, g * 1.0, b * 1.0, 255.0, 2.0)
      Clay.close
    end
  end

  Clay.close
  return 0
end

# Menu item with cursor highlight.
# Shows ">" prefix and highlight background when cursor == idx.
# Uses open_i for unique element IDs.
#: (String id, Integer idx, String text, Integer cursor, Integer font_id, Integer sz) -> Integer
def fw_clay_menu_item(id, idx, text, cursor, font_id, sz)
  Clay.open_i(id, idx)
  Clay.layout(0, 8, 8, 4, 4, 4, 1, 0.0, 0, 0.0, 0, 2)

  if cursor == idx
    Clay.bg(60.0, 60.0, 120.0, 200.0, 4.0)
    Clay.text(">", font_id, sz, 255.0, 255.0, 100.0, 255.0, 0)
  end

  Clay.text(text, font_id, sz, 255.0, 255.0, 255.0, 255.0, 0)
  Clay.close
  return 0
end

# Draw single digit (0-9) as Clay text element.
#: (Integer d, Integer font_id, Integer sz, Integer r, Integer g, Integer b) -> Integer
def fw_clay_draw_d(d, font_id, sz, r, g, b)
  rf = r * 1.0
  gf = g * 1.0
  bf = b * 1.0
  if d == 0
    Clay.text("0", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 1
    Clay.text("1", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 2
    Clay.text("2", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 3
    Clay.text("3", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 4
    Clay.text("4", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 5
    Clay.text("5", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 6
    Clay.text("6", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 7
    Clay.text("7", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 8
    Clay.text("8", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  if d == 9
    Clay.text("9", font_id, sz, rf, gf, bf, 255.0, 0)
  end
  return 0
end

# Draw integer number as Clay text elements (up to 5 digits).
# Opens its own zero-gap container. idx must be unique per call in same parent.
#: (Integer idx, Integer n, Integer font_id, Integer sz, Integer r, Integer g, Integer b) -> Integer
def fw_clay_num(idx, n, font_id, sz, r, g, b)
  Clay.open_i("_n", idx)
  Clay.layout(0, 0, 0, 0, 0, 0, 0, 0.0, 0, 0.0, 0, 0)
  if n < 0
    Clay.text("-", font_id, sz, r * 1.0, g * 1.0, b * 1.0, 255.0, 0)
    n = 0 - n
  end
  if n >= 10000
    fw_clay_draw_d(n / 10000, font_id, sz, r, g, b)
  end
  if n >= 1000
    fw_clay_draw_d((n / 1000) % 10, font_id, sz, r, g, b)
  end
  if n >= 100
    fw_clay_draw_d((n / 100) % 10, font_id, sz, r, g, b)
  end
  if n >= 10
    fw_clay_draw_d((n / 10) % 10, font_id, sz, r, g, b)
  end
  fw_clay_draw_d(n % 10, font_id, sz, r, g, b)
  Clay.close
  return 0
end

# Spacer element that fills available space (GROW width, GROW height).
#: (String id) -> Integer
def fw_clay_spacer(id)
  Clay.open(id)
  Clay.layout(0, 0, 0, 0, 0, 0, 1, 0.0, 1, 0.0, 0, 0)
  Clay.close
  return 0
end
