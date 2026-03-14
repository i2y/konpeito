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

# ════════════════════════════════════════════
# Section 12: Timer System
# ════════════════════════════════════════════
#
# Manages delay/repeat timers using NativeArray slots.
# Timer array layout (stride 3): [remaining, interval, active]
# remaining: frames until trigger (counts down)
# interval:  0 = one-shot, >0 = repeat interval
# active:    1 = running, 0 = inactive

# Set a one-shot timer. Triggers after `frames` game frames.
# arr = NativeArray, base = starting index (stride 3).
#: (Integer base, Integer frames) -> Integer
def fw_timer_set(arr, base, frames)
  arr[base] = frames
  arr[base + 1] = 0
  arr[base + 2] = 1
  return 0
end

# Set a repeating timer. Triggers every `interval` frames.
#: (Integer base, Integer interval) -> Integer
def fw_timer_repeat(arr, base, interval)
  arr[base] = interval
  arr[base + 1] = interval
  arr[base + 2] = 1
  return 0
end

# Tick one timer slot. Returns 1 if timer just triggered this frame.
#: (Integer base) -> Integer
def fw_timer_tick(arr, base)
  if arr[base + 2] == 0
    return 0
  end
  arr[base] = arr[base] - 1
  if arr[base] <= 0
    interval = arr[base + 1]
    if interval > 0
      arr[base] = interval
    else
      arr[base + 2] = 0
    end
    return 1
  end
  return 0
end

# Check if timer is active.
#: (Integer base) -> Integer
def fw_timer_active(arr, base)
  return arr[base + 2]
end

# Cancel a timer.
#: (Integer base) -> Integer
def fw_timer_cancel(arr, base)
  arr[base + 2] = 0
  return 0
end

# ════════════════════════════════════════════
# Section 13: Debug Overlay
# ════════════════════════════════════════════
#
# FPS display and debug info rendering.

# Draw FPS counter at position (x, y).
#: (Integer x, Integer y, Integer sz, Integer col) -> Integer
def fw_draw_fps(x, y, sz, col)
  fps = Raylib.get_fps
  fw_draw_txt("FPS:", x, y, sz, col)
  fw_draw_num(x + sz * 3, y, fps, sz, col)
  return 0
end

# Draw a debug label + value pair.
#: (String label_text, Integer val, Integer x, Integer y, Integer sz, Integer col) -> Integer
def fw_draw_debug_val(label_text, val, x, y, sz, col)
  fw_draw_txt(label_text, x, y, sz, col)
  sp = sz * 6 / 10
  label_w = 10 * sp
  fw_draw_num(x + label_w, y, val, sz, col)
  return 0
end

# Draw collision rectangle outline (debug visualization).
#: (Integer x, Integer y, Integer w, Integer h, Integer col) -> Integer
def fw_draw_collision_rect(x, y, w, h, col)
  Raylib.draw_rectangle_lines(x, y, w, h, col)
  return 0
end

# ════════════════════════════════════════════
# Section 14: Tween / Easing Library
# ════════════════════════════════════════════
#
# All values in 1000x fixed-point.
# t = progress [0, 1000], output = [0, 1000]
#
# Usage: actual = start + (end - start) * fw_ease_XXX(t) / 1000

# Linear (identity).
#: (Integer t) -> Integer
def fw_ease_linear(t)
  return t
end

# Quadratic ease-in: t^2
#: (Integer t) -> Integer
def fw_ease_in_quad(t)
  return t * t / 1000
end

# Quadratic ease-out: 1 - (1-t)^2
#: (Integer t) -> Integer
def fw_ease_out_quad(t)
  inv = 1000 - t
  return 1000 - inv * inv / 1000
end

# Quadratic ease-in-out
#: (Integer t) -> Integer
def fw_ease_in_out_quad(t)
  if t < 500
    return 2 * t * t / 1000
  end
  inv = 1000 - t
  return 1000 - 2 * inv * inv / 1000
end

# Cubic ease-in: t^3
#: (Integer t) -> Integer
def fw_ease_in_cubic(t)
  return t * t / 1000 * t / 1000
end

# Cubic ease-out: 1 - (1-t)^3
#: (Integer t) -> Integer
def fw_ease_out_cubic(t)
  inv = 1000 - t
  return 1000 - inv * inv / 1000 * inv / 1000
end

# Cubic ease-in-out
#: (Integer t) -> Integer
def fw_ease_in_out_cubic(t)
  if t < 500
    return 4 * t * t / 1000 * t / 1000
  end
  inv = 1000 - t
  return 1000 - 4 * inv * inv / 1000 * inv / 1000
end

# Bounce ease-out (approximation using piecewise quadratic)
#: (Integer t) -> Integer
def fw_ease_out_bounce(t)
  if t < 363
    return 7563 * t / 1000 * t / 1000000
  end
  if t < 727
    t2 = t - 545
    return 7563 * t2 / 1000 * t2 / 1000000 + 750
  end
  if t < 909
    t2 = t - 818
    return 7563 * t2 / 1000 * t2 / 1000000 + 937
  end
  t2 = t - 955
  return 7563 * t2 / 1000 * t2 / 1000000 + 984
end

# Bounce ease-in
#: (Integer t) -> Integer
def fw_ease_in_bounce(t)
  return 1000 - fw_ease_out_bounce(1000 - t)
end

# Elastic ease-out (simplified approximation)
#: (Integer t) -> Integer
def fw_ease_out_elastic(t)
  if t == 0
    return 0
  end
  if t >= 1000
    return 1000
  end
  # Simplified: overshoot + decay
  progress = t * t / 1000
  overshoot = 0
  if t > 600
    overshoot = (t - 600) * 80 / 400
    if t > 800
      overshoot = 80 - (t - 800) * 80 / 200
    end
  end
  result = progress + overshoot
  if result > 1000
    result = 1000
  end
  return result
end

# Apply tween: interpolate from start to end using easing progress t [0, 1000].
# Returns interpolated value.
#: (Integer start_val, Integer end_val, Integer eased_t) -> Integer
def fw_tween(start_val, end_val, eased_t)
  return start_val + (end_val - start_val) * eased_t / 1000
end

# Advance a tween slot. Returns progress [0, 1000].
# Uses 2 consecutive G.s[] slots: [current_frame, total_frames].
#: (Integer base_idx) -> Integer
def fw_tween_advance(base_idx)
  frame = G.s[base_idx]
  total = G.s[base_idx + 1]
  if total <= 0
    return 1000
  end
  if frame < total
    G.s[base_idx] = frame + 1
  end
  return G.s[base_idx] * 1000 / total
end

# Start a tween. Set frame=0, total=duration.
#: (Integer base_idx, Integer duration_frames) -> Integer
def fw_tween_start(base_idx, duration_frames)
  G.s[base_idx] = 0
  G.s[base_idx + 1] = duration_frames
  return 0
end

# Check if tween is complete.
#: (Integer base_idx) -> Integer
def fw_tween_done(base_idx)
  if G.s[base_idx] >= G.s[base_idx + 1]
    return 1
  end
  return 0
end

# ════════════════════════════════════════════
# Section 15: Screen Shake
# ════════════════════════════════════════════
#
# Camera2D random offset. Uses G.s[] slots:
# base_idx: [shake_remaining, shake_intensity, offset_x, offset_y]

# Start screen shake. duration = frames, intensity = max pixel offset.
#: (Integer base_idx, Integer duration, Integer intensity) -> Integer
def fw_shake_start(base_idx, duration, intensity)
  G.s[base_idx] = duration
  G.s[base_idx + 1] = intensity
  G.s[base_idx + 2] = 0
  G.s[base_idx + 3] = 0
  return 0
end

# Update shake (call once per frame). Sets offset_x/offset_y in slots.
#: (Integer base_idx) -> Integer
def fw_shake_update(base_idx)
  remaining = G.s[base_idx]
  if remaining <= 0
    G.s[base_idx + 2] = 0
    G.s[base_idx + 3] = 0
    return 0
  end
  intensity = G.s[base_idx + 1]
  # Decay intensity as remaining decreases
  current_intensity = intensity * remaining / G.s[base_idx]
  if current_intensity < 1
    current_intensity = 1
  end
  G.s[base_idx + 2] = fw_rand(current_intensity * 2 + 1) - current_intensity
  G.s[base_idx + 3] = fw_rand(current_intensity * 2 + 1) - current_intensity
  G.s[base_idx] = remaining - 1
  return 0
end

# Get shake X offset.
#: (Integer base_idx) -> Integer
def fw_shake_x(base_idx)
  return G.s[base_idx + 2]
end

# Get shake Y offset.
#: (Integer base_idx) -> Integer
def fw_shake_y(base_idx)
  return G.s[base_idx + 3]
end

# Check if shake is active.
#: (Integer base_idx) -> Integer
def fw_shake_active(base_idx)
  if G.s[base_idx] > 0
    return 1
  end
  return 0
end

# ════════════════════════════════════════════
# Section 16: Scene Transition Effects
# ════════════════════════════════════════════
#
# Fade/slide transitions using tween system.
# Uses G.s[] slots: [phase, progress, total_frames, next_scene]
# phase: 0=idle, 1=fading out, 2=fading in

# Start a scene transition.
#: (Integer base_idx, Integer next_scene, Integer duration) -> Integer
def fw_transition_start(base_idx, next_scene, duration)
  G.s[base_idx] = 1
  G.s[base_idx + 1] = 0
  G.s[base_idx + 2] = duration
  G.s[base_idx + 3] = next_scene
  return 0
end

# Update transition (call once per frame).
# Returns: 0=idle, 1=fading out, 2=scene switch point, 3=fading in
#: (Integer base_idx) -> Integer
def fw_transition_update(base_idx)
  phase = G.s[base_idx]
  if phase == 0
    return 0
  end
  total = G.s[base_idx + 2]
  G.s[base_idx + 1] = G.s[base_idx + 1] + 1
  progress = G.s[base_idx + 1]
  if phase == 1
    if progress >= total
      G.s[base_idx] = 3
      G.s[base_idx + 1] = 0
      return 2
    end
    return 1
  end
  if phase == 3
    if progress >= total
      G.s[base_idx] = 0
      G.s[base_idx + 1] = 0
      return 0
    end
    return 3
  end
  return 0
end

# Get transition alpha (0-255) for fade overlay.
#: (Integer base_idx) -> Integer
def fw_transition_alpha(base_idx)
  phase = G.s[base_idx]
  if phase == 0
    return 0
  end
  progress = G.s[base_idx + 1]
  total = G.s[base_idx + 2]
  if total <= 0
    return 0
  end
  if phase == 1
    return progress * 255 / total
  end
  if phase == 3
    return 255 - progress * 255 / total
  end
  return 0
end

# Get the next scene ID stored in the transition.
#: (Integer base_idx) -> Integer
def fw_transition_next_scene(base_idx)
  return G.s[base_idx + 3]
end

# Draw fade overlay (full-screen black rectangle with alpha).
#: (Integer alpha, Integer w, Integer h) -> Integer
def fw_draw_fade(alpha, w, h)
  if alpha > 0
    col = fw_rgba(0, 0, 0, alpha)
    Raylib.draw_rectangle(0, 0, w, h, col)
  end
  return 0
end

# ════════════════════════════════════════════
# Section 17: Simple Physics
# ════════════════════════════════════════════
#
# AABB collision, velocity, gravity.
# All values in 100x fixed-point (1 pixel = 100 units).
# Entity layout (stride 8): [x, y, vx, vy, w, h, flags, _reserved]

# Initialize a physics entity.
#: (Integer base, Integer x100, Integer y100, Integer w100, Integer h100) -> Integer
def fw_phys_init(arr, base, x100, y100, w100, h100)
  arr[base] = x100
  arr[base + 1] = y100
  arr[base + 2] = 0
  arr[base + 3] = 0
  arr[base + 4] = w100
  arr[base + 5] = h100
  arr[base + 6] = 1
  arr[base + 7] = 0
  return 0
end

# Apply velocity to position.
#: (Integer base) -> Integer
def fw_phys_move(arr, base)
  arr[base] = arr[base] + arr[base + 2]
  arr[base + 1] = arr[base + 1] + arr[base + 3]
  return 0
end

# Apply gravity (add to vy).
#: (Integer base, Integer gravity100) -> Integer
def fw_phys_gravity(arr, base, gravity100)
  arr[base + 3] = arr[base + 3] + gravity100
  return 0
end

# Apply friction (multiply velocity by factor/100).
# factor=90 means 90% of velocity retained each frame.
#: (Integer base, Integer factor) -> Integer
def fw_phys_friction(arr, base, factor)
  arr[base + 2] = arr[base + 2] * factor / 100
  arr[base + 3] = arr[base + 3] * factor / 100
  return 0
end

# AABB collision check between two entities. Returns 1 if overlapping.
#: (Integer base_a, Integer base_b) -> Integer
def fw_phys_aabb(arr, base_a, base_b)
  ax = arr[base_a]
  ay = arr[base_a + 1]
  aw = arr[base_a + 4]
  ah = arr[base_a + 5]
  bx = arr[base_b]
  by = arr[base_b + 1]
  bw = arr[base_b + 4]
  bh = arr[base_b + 5]
  if ax + aw <= bx
    return 0
  end
  if bx + bw <= ax
    return 0
  end
  if ay + ah <= by
    return 0
  end
  if by + bh <= ay
    return 0
  end
  return 1
end

# Clamp entity position within bounds.
#: (Integer base, Integer min_x, Integer min_y, Integer max_x, Integer max_y) -> Integer
def fw_phys_clamp_pos(arr, base, min_x, min_y, max_x, max_y)
  w = arr[base + 4]
  h = arr[base + 5]
  if arr[base] < min_x
    arr[base] = min_x
    arr[base + 2] = 0
  end
  if arr[base] + w > max_x
    arr[base] = max_x - w
    arr[base + 2] = 0
  end
  if arr[base + 1] < min_y
    arr[base + 1] = min_y
    arr[base + 3] = 0
  end
  if arr[base + 1] + h > max_y
    arr[base + 1] = max_y - h
    arr[base + 3] = 0
  end
  return 0
end

# Get pixel X from 100x fixed-point.
#: (Integer base) -> Integer
def fw_phys_px(arr, base)
  return arr[base] / 100
end

# Get pixel Y from 100x fixed-point.
#: (Integer base) -> Integer
def fw_phys_py(arr, base)
  return arr[base + 1] / 100
end

# ════════════════════════════════════════════
# Section 18: Particle System
# ════════════════════════════════════════════
#
# NativeArray pool with stride 6: [x, y, vx, vy, life, max_life]
# All positions in 100x fixed-point.

# Emit a particle at given position with velocity.
# Scans pool for inactive slot (life <= 0). Returns slot index or -1.
#: (Integer count, Integer stride, Integer x100, Integer y100, Integer vx, Integer vy, Integer life) -> Integer
def fw_particle_emit(arr, count, stride, x100, y100, vx, vy, life)
  i = 0
  while i < count
    base = i * stride
    if arr[base + 4] <= 0
      arr[base] = x100
      arr[base + 1] = y100
      arr[base + 2] = vx
      arr[base + 3] = vy
      arr[base + 4] = life
      arr[base + 5] = life
      return i
    end
    i = i + 1
  end
  return 0 - 1
end

# Update all particles: apply velocity, gravity, decrement life.
#: (Integer count, Integer stride, Integer gravity100) -> Integer
def fw_particle_update(arr, count, stride, gravity100)
  i = 0
  while i < count
    base = i * stride
    if arr[base + 4] > 0
      arr[base] = arr[base] + arr[base + 2]
      arr[base + 1] = arr[base + 1] + arr[base + 3]
      arr[base + 3] = arr[base + 3] + gravity100
      arr[base + 4] = arr[base + 4] - 1
    end
    i = i + 1
  end
  return 0
end

# Draw all active particles as small rectangles.
#: (Integer count, Integer stride, Integer sz, Integer col) -> Integer
def fw_particle_draw(arr, count, stride, sz, col)
  i = 0
  while i < count
    base = i * stride
    if arr[base + 4] > 0
      px = arr[base] / 100
      py = arr[base + 1] / 100
      Raylib.draw_rectangle(px, py, sz, sz, col)
    end
    i = i + 1
  end
  return 0
end

# Count active particles.
#: (Integer count, Integer stride) -> Integer
def fw_particle_active_count(arr, count, stride)
  n = 0
  i = 0
  while i < count
    base = i * stride
    if arr[base + 4] > 0
      n = n + 1
    end
    i = i + 1
  end
  return n
end

# ════════════════════════════════════════════
# Section 19: Grid / Tile Utilities
# ════════════════════════════════════════════

# Convert grid position to pixel position.
#: (Integer grid_pos, Integer tile_size) -> Integer
def fw_grid_to_px(grid_pos, tile_size)
  return grid_pos * tile_size
end

# Convert pixel position to grid position.
#: (Integer px, Integer tile_size) -> Integer
def fw_px_to_grid(px, tile_size)
  if tile_size <= 0
    return 0
  end
  return px / tile_size
end

# Get array index from grid (x, y) coordinates. row-major layout.
#: (Integer gx, Integer gy, Integer cols) -> Integer
def fw_grid_index(gx, gy, cols)
  return gy * cols + gx
end

# Check if grid position is within bounds.
#: (Integer gx, Integer gy, Integer cols, Integer rows) -> Integer
def fw_grid_in_bounds(gx, gy, cols, rows)
  if gx < 0
    return 0
  end
  if gy < 0
    return 0
  end
  if gx >= cols
    return 0
  end
  if gy >= rows
    return 0
  end
  return 1
end

# Check walkability at grid position. 0 = walkable tile.
#: (Integer gx, Integer gy, Integer cols, Integer rows) -> Integer
def fw_grid_walkable(map_arr, gx, gy, cols, rows)
  if fw_grid_in_bounds(gx, gy, cols, rows) == 0
    return 0
  end
  idx = gy * cols + gx
  if map_arr[idx] == 0
    return 1
  end
  return 0
end

# Manhattan distance between two grid points.
#: (Integer x1, Integer y1, Integer x2, Integer y2) -> Integer
def fw_manhattan(x1, y1, x2, y2)
  dx = x2 - x1
  if dx < 0
    dx = 0 - dx
  end
  dy = y2 - y1
  if dy < 0
    dy = 0 - dy
  end
  return dx + dy
end

# Chebyshev distance (max of dx, dy). Used for 8-directional movement.
#: (Integer x1, Integer y1, Integer x2, Integer y2) -> Integer
def fw_chebyshev(x1, y1, x2, y2)
  dx = x2 - x1
  if dx < 0
    dx = 0 - dx
  end
  dy = y2 - y1
  if dy < 0
    dy = 0 - dy
  end
  if dx > dy
    return dx
  end
  return dy
end

# ════════════════════════════════════════════
# Section 20: Object Pool
# ════════════════════════════════════════════
#
# Generic object pool using NativeArray with configurable stride.
# Slot 0 of each entry = active flag (1=active, 0=free).

# Allocate a slot from pool. Returns base index or -1 if full.
#: (Integer count, Integer stride) -> Integer
def fw_pool_alloc(arr, count, stride)
  i = 0
  while i < count
    base = i * stride
    if arr[base] == 0
      arr[base] = 1
      return base
    end
    i = i + 1
  end
  return 0 - 1
end

# Free a pool slot.
#: (Integer base) -> Integer
def fw_pool_free(arr, base)
  arr[base] = 0
  return 0
end

# Check if slot is active.
#: (Integer base) -> Integer
def fw_pool_active(arr, base)
  return arr[base]
end

# Count active slots in pool.
#: (Integer count, Integer stride) -> Integer
def fw_pool_count(arr, count, stride)
  n = 0
  i = 0
  while i < count
    base = i * stride
    if arr[base] == 1
      n = n + 1
    end
    i = i + 1
  end
  return n
end

# ════════════════════════════════════════════
# Section 21: FSM — Finite State Machine (G10)
# ════════════════════════════════════════════
#
# State management using G.s[] slots:
# base_idx: [current_state, prev_state, frames_in_state, just_entered]

# Initialize FSM with starting state.
#: (Integer base_idx, Integer initial_state) -> Integer
def fw_fsm_init(base_idx, initial_state)
  G.s[base_idx] = initial_state
  G.s[base_idx + 1] = initial_state
  G.s[base_idx + 2] = 0
  G.s[base_idx + 3] = 1
  return 0
end

# Transition to a new state.
#: (Integer base_idx, Integer new_state) -> Integer
def fw_fsm_set(base_idx, new_state)
  current = G.s[base_idx]
  if current != new_state
    G.s[base_idx + 1] = current
    G.s[base_idx] = new_state
    G.s[base_idx + 2] = 0
    G.s[base_idx + 3] = 1
  end
  return 0
end

# Update FSM (call once per frame). Increments frame counter.
#: (Integer base_idx) -> Integer
def fw_fsm_tick(base_idx)
  G.s[base_idx + 2] = G.s[base_idx + 2] + 1
  G.s[base_idx + 3] = 0
  return 0
end

# Get current state.
#: (Integer base_idx) -> Integer
def fw_fsm_state(base_idx)
  return G.s[base_idx]
end

# Get previous state.
#: (Integer base_idx) -> Integer
def fw_fsm_prev(base_idx)
  return G.s[base_idx + 1]
end

# Get frames spent in current state.
#: (Integer base_idx) -> Integer
def fw_fsm_frames(base_idx)
  return G.s[base_idx + 2]
end

# Check if just entered current state (1 on first frame only).
#: (Integer base_idx) -> Integer
def fw_fsm_just_entered(base_idx)
  return G.s[base_idx + 3]
end

# ════════════════════════════════════════════
# Section 22: Parallax Scrolling (G11)
# ════════════════════════════════════════════

# Calculate parallax offset for a layer.
# camera_x = camera position, factor = speed factor (100 = same speed, 50 = half).
#: (Integer camera_x, Integer factor) -> Integer
def fw_parallax(camera_x, factor)
  return camera_x * factor / 100
end

# ════════════════════════════════════════════
# Section 23: Save / Load (G12)
# ════════════════════════════════════════════
#
# NativeArray serialization to/from text file.
# Format: one integer per line.
# Requires KonpeitoShell module (auto-detected).

# Save NativeArray range to file (start inclusive, count = number of slots).
#: (String path, Integer start, Integer count) -> Integer
def fw_save(arr, path, start, count)
  content = ""
  i = 0
  while i < count
    val = arr[start + i]
    content = content + val.to_s + "\n"
    i = i + 1
  end
  KonpeitoShell.write_file(path, content)
  return 0
end

# ════════════════════════════════════════════
# Section 24: Gamepad Abstraction (G13)
# ════════════════════════════════════════════
#
# Unified input: keyboard + gamepad. Returns direction or button state.

# Check if gamepad is connected.
#: (Integer pad_id) -> Integer
def fw_gamepad_available(pad_id)
  return Raylib.gamepad_available?(pad_id)
end

# Get unified direction input from keyboard OR gamepad.
# Returns: 0=down, 1=up, 2=left, 3=right, -1=none
#: (Integer pad_id) -> Integer
def fw_input_direction(pad_id)
  # Keyboard first
  dir = fw_get_direction
  if dir >= 0
    return dir
  end
  # Gamepad D-pad
  if Raylib.gamepad_available?(pad_id) == 1
    if Raylib.gamepad_button_down?(pad_id, 2) == 1
      return 2
    end
    if Raylib.gamepad_button_down?(pad_id, 3) == 1
      return 3
    end
    if Raylib.gamepad_button_down?(pad_id, 1) == 1
      return 0
    end
    if Raylib.gamepad_button_down?(pad_id, 4) == 1
      return 1
    end
    # Left stick with deadzone (30%)
    axis_x = Raylib.gamepad_axis_value(pad_id, 0)
    axis_y = Raylib.gamepad_axis_value(pad_id, 1)
    if axis_x < -30
      return 2
    end
    if axis_x > 30
      return 3
    end
    if axis_y > 30
      return 0
    end
    if axis_y < -30
      return 1
    end
  end
  return 0 - 1
end

# Check unified confirm button (keyboard Enter/Space OR gamepad A).
#: (Integer pad_id) -> Integer
def fw_input_confirm(pad_id)
  if fw_confirm_pressed == 1
    return 1
  end
  if Raylib.gamepad_available?(pad_id) == 1
    if Raylib.gamepad_button_pressed?(pad_id, 7) == 1
      return 1
    end
  end
  return 0
end

# Check unified cancel button (keyboard Escape/X OR gamepad B).
#: (Integer pad_id) -> Integer
def fw_input_cancel(pad_id)
  if fw_cancel_pressed == 1
    return 1
  end
  if Raylib.gamepad_available?(pad_id) == 1
    if Raylib.gamepad_button_pressed?(pad_id, 8) == 1
      return 1
    end
  end
  return 0
end
