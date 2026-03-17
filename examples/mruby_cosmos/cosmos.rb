# Konpeito Cosmos — Demoscene Visual Showcase
#
# A real-time graphics demo showcasing the Konpeito mruby backend with raylib.
# Features: starfield, particle ring, glowing nebula, rotating wireframes,
# expanding pulse rings, aurora borealis wave, and animated title.
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -o examples/mruby_cosmos/cosmos examples/mruby_cosmos/cosmos.rb
#
# Run:
#   ./examples/mruby_cosmos/cosmos
#
# rbs_inline: enabled

module Raylib
end

SCREEN_W = 1280
SCREEN_H = 720
CX = 640
CY = 320

STAR_COUNT  = 100
STAR_STRIDE = 3

ORBIT_COUNT  = 64
ORBIT_STRIDE = 3

AURORA_COLS = 80

# @rbs module SinTab
# @rbs   @s: NativeArray[Integer, 256]
# @rbs end

# @rbs module Stars
# @rbs   @s: NativeArray[Integer, 300]
# @rbs end

# @rbs module Orbit
# @rbs   @s: NativeArray[Integer, 192]
# @rbs end

# @rbs module G
# @rbs   @s: NativeArray[Integer, 32]
# @rbs end
# G.s layout:
#   [0] = frame counter
#   [1] = random seed

# ════════════════════════════════════════════
# Sine table (256 entries, values * 1000)
# ════════════════════════════════════════════

#: (Integer idx) -> Integer
def sin1k(idx)
  i = idx % 256
  if i < 0
    i = i + 256
  end
  return SinTab.s[i]
end

#: (Integer idx) -> Integer
def cos1k(idx)
  return sin1k(idx + 64)
end

#: () -> Integer
def init_sin_tab
  SinTab.s[0] = 0
  SinTab.s[1] = 25
  SinTab.s[2] = 49
  SinTab.s[3] = 74
  SinTab.s[4] = 98
  SinTab.s[5] = 122
  SinTab.s[6] = 147
  SinTab.s[7] = 171
  SinTab.s[8] = 195
  SinTab.s[9] = 219
  SinTab.s[10] = 243
  SinTab.s[11] = 267
  SinTab.s[12] = 290
  SinTab.s[13] = 314
  SinTab.s[14] = 337
  SinTab.s[15] = 360
  SinTab.s[16] = 383
  SinTab.s[17] = 405
  SinTab.s[18] = 428
  SinTab.s[19] = 450
  SinTab.s[20] = 471
  SinTab.s[21] = 493
  SinTab.s[22] = 514
  SinTab.s[23] = 535
  SinTab.s[24] = 556
  SinTab.s[25] = 576
  SinTab.s[26] = 596
  SinTab.s[27] = 615
  SinTab.s[28] = 634
  SinTab.s[29] = 653
  SinTab.s[30] = 672
  SinTab.s[31] = 690
  SinTab.s[32] = 707
  SinTab.s[33] = 724
  SinTab.s[34] = 741
  SinTab.s[35] = 757
  SinTab.s[36] = 773
  SinTab.s[37] = 788
  SinTab.s[38] = 803
  SinTab.s[39] = 818
  SinTab.s[40] = 831
  SinTab.s[41] = 845
  SinTab.s[42] = 858
  SinTab.s[43] = 870
  SinTab.s[44] = 882
  SinTab.s[45] = 893
  SinTab.s[46] = 904
  SinTab.s[47] = 914
  SinTab.s[48] = 924
  SinTab.s[49] = 933
  SinTab.s[50] = 942
  SinTab.s[51] = 950
  SinTab.s[52] = 957
  SinTab.s[53] = 964
  SinTab.s[54] = 970
  SinTab.s[55] = 976
  SinTab.s[56] = 981
  SinTab.s[57] = 985
  SinTab.s[58] = 989
  SinTab.s[59] = 992
  SinTab.s[60] = 995
  SinTab.s[61] = 997
  SinTab.s[62] = 999
  SinTab.s[63] = 1000
  SinTab.s[64] = 1000
  # Second quadrant: mirror
  i = 0
  while i <= 63
    SinTab.s[64 + i] = SinTab.s[64 - i]
    i = i + 1
  end
  # sin(180) = 0
  SinTab.s[128] = 0
  # Third and fourth quadrants: negate
  i = 1
  while i <= 127
    SinTab.s[128 + i] = 0 - SinTab.s[i]
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Utilities
# ════════════════════════════════════════════

#: (Integer mod) -> Integer
def rng(mod)
  s = G.s[1]
  s = s * 1103515245 + 12345
  s = s % 2147483647
  if s < 0
    s = s + 2147483647
  end
  G.s[1] = s
  return s % mod
end

#: (Integer v, Integer lo, Integer hi) -> Integer
def clamp(v, lo, hi)
  if v < lo
    return lo
  end
  if v > hi
    return hi
  end
  return v
end

# Hue (0..255) to RGBA color
#: (Integer hue, Integer alpha) -> Integer
def hue_color(hue, alpha)
  h = hue % 256
  if h < 0
    h = h + 256
  end
  if h < 43
    r = 255
    g = h * 6
    b = 0
  else
    if h < 86
      r = 255 - (h - 43) * 6
      g = 255
      b = 0
    else
      if h < 128
        r = 0
        g = 255
        b = (h - 86) * 6
      else
        if h < 170
          r = 0
          g = 255 - (h - 128) * 6
          b = 255
        else
          if h < 213
            r = (h - 170) * 6
            g = 0
            b = 255
          else
            r = 255
            g = 0
            b = 255 - (h - 213) * 6
          end
        end
      end
    end
  end
  r = clamp(r, 0, 255)
  g = clamp(g, 0, 255)
  b = clamp(b, 0, 255)
  return Raylib.color_new(r, g, b, alpha)
end

# ════════════════════════════════════════════
# Initialization
# ════════════════════════════════════════════

#: () -> Integer
def init_stars
  i = 0
  while i < STAR_COUNT
    base = i * STAR_STRIDE
    Stars.s[base] = rng(SCREEN_W)
    Stars.s[base + 1] = rng(SCREEN_H)
    Stars.s[base + 2] = rng(3) + 1
    i = i + 1
  end
  return 0
end

#: () -> Integer
def init_orbit
  i = 0
  while i < ORBIT_COUNT
    base = i * ORBIT_STRIDE
    Orbit.s[base] = i * 256 / ORBIT_COUNT
    Orbit.s[base + 1] = rng(50) - 25
    Orbit.s[base + 2] = rng(256)
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Drawing layers
# ════════════════════════════════════════════

#: (Integer frame) -> Integer
def draw_background(frame)
  # Subtle color shift in background
  r = 5 + sin1k(frame) * 3 / 1000
  g = 5 + cos1k(frame) * 2 / 1000
  b = 20 + sin1k(frame * 2) * 8 / 1000
  Raylib.draw_rectangle_gradient_v(0, 0, SCREEN_W, SCREEN_H,
    Raylib.color_new(r + 3, g + 3, b + 10, 255),
    Raylib.color_new(r, g, b - 10, 255))
  return 0
end

#: (Integer frame) -> Integer
def draw_stars(frame)
  i = 0
  while i < STAR_COUNT
    base = i * STAR_STRIDE
    x = Stars.s[base]
    y = Stars.s[base + 1]
    layer = Stars.s[base + 2]

    # Parallax scroll downward
    y = y + layer
    if y >= SCREEN_H
      y = 0
      Stars.s[base] = rng(SCREEN_W)
    end
    Stars.s[base + 1] = y

    # Twinkling brightness
    bright_idx = (frame * 3 + i * 37) % 256
    bright = 140 + sin1k(bright_idx) * 115 / 1000
    tint_b = clamp(bright + 40, 0, 255)

    # Size by layer (near stars bigger)
    sz = 4 - layer
    Raylib.draw_rectangle(x, y, sz, sz,
      Raylib.color_new(bright, bright, tint_b, 255))

    # Bright stars get a small cross flare
    if layer == 1
      flare_alpha = clamp(bright - 160, 0, 95)
      if flare_alpha > 0
        fc = Raylib.color_new(200, 200, 255, flare_alpha)
        Raylib.draw_line(x - 4, y + 1, x + 7, y + 1, fc)
        Raylib.draw_line(x + 1, y - 4, x + 1, y + 7, fc)
      end
    end

    i = i + 1
  end
  return 0
end

#: (Integer frame) -> Integer
def draw_wireframe_geometry(frame)
  # Rotating triangle
  angle_t = frame * 2
  rt = 220 + sin1k(frame) * 20 / 1000
  j = 0
  while j < 3
    a1 = angle_t + j * 85
    a2 = angle_t + (j + 1) * 85
    x1 = CX + cos1k(a1) * rt / 1000
    y1 = CY + sin1k(a1) * rt / 1000
    x2 = CX + cos1k(a2) * rt / 1000
    y2 = CY + sin1k(a2) * rt / 1000
    alpha_t = 30 + sin1k(frame * 3) * 20 / 1000
    Raylib.draw_line_ex(x1, y1, x2, y2, 1.5,
      Raylib.color_new(80, 120, 255, alpha_t))
    j = j + 1
  end

  # Counter-rotating hexagon
  angle_h = 256 - frame
  rh = 260 + cos1k(frame) * 25 / 1000
  k = 0
  while k < 6
    a1 = angle_h + k * 43
    a2 = angle_h + (k + 1) * 43
    x1 = CX + cos1k(a1) * rh / 1000
    y1 = CY + sin1k(a1) * rh / 1000
    x2 = CX + cos1k(a2) * rh / 1000
    y2 = CY + sin1k(a2) * rh / 1000
    alpha_h = 25 + cos1k(frame * 2) * 15 / 1000
    Raylib.draw_line_ex(x1, y1, x2, y2, 1.0,
      Raylib.color_new(200, 80, 255, alpha_h))
    k = k + 1
  end

  # Inner rotating pentagon
  angle_p = frame * 3
  rp = 140 + sin1k(frame * 2) * 15 / 1000
  m = 0
  while m < 5
    a1 = angle_p + m * 51
    a2 = angle_p + (m + 1) * 51
    x1 = CX + cos1k(a1) * rp / 1000
    y1 = CY + sin1k(a1) * rp / 1000
    x2 = CX + cos1k(a2) * rp / 1000
    y2 = CY + sin1k(a2) * rp / 1000
    Raylib.draw_line_ex(x1, y1, x2, y2, 1.0,
      Raylib.color_new(100, 255, 180, 20))
    m = m + 1
  end

  return 0
end

#: (Integer frame) -> Integer
def draw_pulse_rings(frame)
  ring = 0
  while ring < 5
    phase = (frame * 2 + ring * 36) % 180
    radius = phase * 3
    alpha = 150 - phase
    if alpha < 0
      alpha = 0
    end
    if alpha > 0
      Raylib.draw_circle_lines(CX, CY, radius * 1.0,
        Raylib.color_new(100, 140, 255, alpha))
    end
    ring = ring + 1
  end
  return 0
end

#: (Integer frame) -> Integer
def draw_orbit_ring(frame)
  i = 0
  while i < ORBIT_COUNT
    base = i * ORBIT_STRIDE
    angle = Orbit.s[base]
    radius_offset = Orbit.s[base + 1]
    hue_shift = Orbit.s[base + 2]

    # Variable speed: inner particles orbit faster
    speed = 2
    if radius_offset > 10
      speed = 1
    end
    if radius_offset < -10
      speed = 3
    end
    angle = (angle + speed) % 256
    Orbit.s[base] = angle

    # Elliptical orbit for 3D perspective
    base_r = 200
    r = base_r + radius_offset
    px = CX + cos1k(angle) * r / 1000
    py = CY + sin1k(angle) * r * 55 / (1000 * 100)

    # Depth-based sizing: particles in front (sin > 0) are bigger
    depth = sin1k(angle)
    sz = 3
    if depth > 500
      sz = 5
    end
    if depth > 800
      sz = 6
    end
    if depth < -500
      sz = 2
    end

    # Color cycling with depth-based brightness
    hue = (frame + hue_shift) % 256
    bright = 160 + depth * 80 / 1000
    bright = clamp(bright, 80, 240)

    col = hue_color(hue, bright)
    glow_col = hue_color(hue, bright / 4)

    # Glow + core
    Raylib.draw_circle(px, py, (sz * 3) * 1.0, glow_col)
    Raylib.draw_circle(px, py, sz * 1.0, col)

    i = i + 1
  end
  return 0
end

#: (Integer frame) -> Integer
def draw_central_orb(frame)
  pulse = sin1k(frame * 2) * 12 / 1000
  pulse2 = cos1k(frame * 3) * 8 / 1000

  # Outer glow layers
  Raylib.draw_circle(CX, CY, (130 + pulse) * 1.0,
    Raylib.color_new(60, 30, 140, 6))
  Raylib.draw_circle(CX, CY, (110 + pulse) * 1.0,
    Raylib.color_new(80, 50, 180, 10))
  Raylib.draw_circle(CX, CY, (90 + pulse) * 1.0,
    Raylib.color_new(100, 70, 200, 16))
  Raylib.draw_circle(CX, CY, (70 + pulse) * 1.0,
    Raylib.color_new(130, 100, 230, 25))
  Raylib.draw_circle(CX, CY, (50 + pulse2) * 1.0,
    Raylib.color_new(160, 140, 245, 45))
  Raylib.draw_circle(CX, CY, (35 + pulse2) * 1.0,
    Raylib.color_new(190, 175, 255, 80))
  Raylib.draw_circle(CX, CY, (22 + pulse / 2) * 1.0,
    Raylib.color_new(215, 205, 255, 140))
  Raylib.draw_circle(CX, CY, (12 + pulse / 3) * 1.0,
    Raylib.color_new(240, 235, 255, 220))
  # Bright core
  Raylib.draw_circle(CX, CY, 6.0,
    Raylib.color_new(255, 252, 255, 255))

  return 0
end

#: (Integer frame) -> Integer
def draw_aurora(frame)
  col_w = SCREEN_W / AURORA_COLS + 1
  i = 0
  while i < AURORA_COLS
    # Multi-frequency sine for organic wave shape
    h1 = sin1k(i * 8 + frame * 2) * 35 / 1000
    h2 = sin1k(i * 5 + frame * 3 + 80) * 25 / 1000
    h3 = sin1k(i * 13 + frame) * 15 / 1000
    height = 55 + h1 + h2 + h3

    x = i * col_w
    y = SCREEN_H - height

    # Color from position + time (slow drift)
    hue = (i * 3 + frame / 2) % 256
    top_alpha = 100 + sin1k(i * 7 + frame * 4) * 40 / 1000
    top_alpha = clamp(top_alpha, 40, 140)

    Raylib.draw_rectangle_gradient_v(x, y, col_w, height,
      hue_color(hue, top_alpha),
      hue_color(hue + 30, 0))

    i = i + 1
  end
  return 0
end

#: (Integer frame) -> Integer
def draw_scanlines(frame)
  # Subtle CRT-style scanlines for retro feel
  y = 0
  while y < SCREEN_H
    Raylib.draw_line(0, y, SCREEN_W, y,
      Raylib.color_new(0, 0, 0, 12))
    y = y + 3
  end
  return 0
end

#: (Integer frame) -> Integer
def draw_title(frame)
  # Pulsating alpha
  alpha = 200 + sin1k(frame) * 55 / 1000
  alpha = clamp(alpha, 100, 255)

  text = "KONPEITO"
  tw = Raylib.measure_text(text, 64)
  tx = CX - tw / 2
  ty = SCREEN_H - 180

  # Shadow glow
  Raylib.draw_text(text, tx + 2, ty + 2, 64,
    Raylib.color_new(80, 50, 180, alpha / 4))
  Raylib.draw_text(text, tx - 1, ty - 1, 64,
    Raylib.color_new(120, 90, 220, alpha / 3))
  # Main text
  Raylib.draw_text(text, tx, ty, 64,
    Raylib.color_new(220, 210, 255, alpha))

  # Subtitle
  sub = "Compiled Ruby   |   mruby + LLVM + raylib"
  sw = Raylib.measure_text(sub, 16)
  sub_alpha = 140 + sin1k(frame + 50) * 60 / 1000
  sub_alpha = clamp(sub_alpha, 80, 200)
  Raylib.draw_text(sub, CX - sw / 2, ty + 75, 16,
    Raylib.color_new(140, 130, 180, sub_alpha))

  return 0
end

#: (Integer frame) -> Integer
def draw_fps_counter(frame)
  fps = Raylib.get_fps
  # Build FPS string manually
  Raylib.draw_text("FPS:", SCREEN_W - 100, 10, 14,
    Raylib.color_new(100, 100, 120, 180))
  # Convert fps to string via draw at offset
  # We use the particle count trick: draw a number
  if fps >= 100
    d2 = fps / 100
    d1 = (fps / 10) % 10
    d0 = fps % 10
    Raylib.draw_text("0", SCREEN_W - 56 + d2 * 0, 10, 14,
      Raylib.color_new(100, 100, 120, 180))
  end
  return 0
end

# ════════════════════════════════════════════
# Main
# ════════════════════════════════════════════

#: () -> Integer
def main
  Raylib.set_config_flags(Raylib.flag_msaa_4x_hint)
  Raylib.init_window(SCREEN_W, SCREEN_H, "Konpeito Cosmos")
  Raylib.set_target_fps(60)

  G.s[0] = 0
  G.s[1] = 77777

  init_sin_tab
  init_stars
  init_orbit

  while Raylib.window_should_close == 0
    frame = G.s[0]
    G.s[0] = frame + 1

    Raylib.begin_drawing

    draw_background(frame)
    draw_stars(frame)
    draw_wireframe_geometry(frame)
    draw_pulse_rings(frame)
    draw_orbit_ring(frame)
    draw_central_orb(frame)
    draw_aurora(frame)
    draw_scanlines(frame)
    draw_title(frame)

    Raylib.end_drawing
  end

  Raylib.close_window
  return 0
end

main
