# Game Showcase — "Coin Dash"
#
# Score-attack platformer demonstrating the full RPG framework API:
#   Physics, Particles, Tween/Easing, Screen Shake, FSM, Timer,
#   Parallax, Scene Transitions, Grid Utilities, Debug Overlay,
#   Gamepad Input, Animation, Scene Management, Menu Cursor,
#   Color/Math/Drawing Helpers, Camera2D, Collision Detection
#
# Controls:
#   Arrow keys / WASD  — Move left/right
#   Space / Up / W     — Jump
#   Enter              — Confirm menu
#   Escape             — Quit
#   D key              — Toggle debug overlay
#   Gamepad supported  (D-pad, face buttons)
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -o examples/game_showcase/game_showcase examples/game_showcase/game_showcase.rb
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/game_framework/game_framework"

# @rbs module G
# @rbs   @s: NativeArray[Integer, 64]
# @rbs end
# G.s layout:
# [0-3]   player FSM (state, prev, frames, just_entered)
# [4]     facing (0=right, 1=left)
# [5]     HP
# [6]     score
# [7]     scene
# [8]     menu cursor
# [9]     game timer (frames)
# [10]    debug mode
# [11]    invincibility frames
# [12-13] score tween (current_frame, total_frames)
# [16-19] screen shake (remaining, intensity, offset_x, offset_y)
# [20-23] scene transition (phase, progress, total, next_scene)
# [28-31] framework reserved (prev_scene, seed, font, frame_counter)
# [32]    camera_x
# [34-35] anim counter, anim frame
# [36]    coins collected
# [37]    enemies defeated
# [38]    on_ground
# [39]    combo
# [40]    jump released flag

# @rbs module PX
# @rbs   @s: NativeArray[Integer, 8]
# @rbs end
# Player: [x100, y100, vx100, vy100, w100, h100, _, _]

# @rbs module Plt
# @rbs   @s: NativeArray[Integer, 48]
# @rbs end
# Platforms: 12 * stride 4 [x, y, w, h] in pixels

# @rbs module En
# @rbs   @s: NativeArray[Integer, 48]
# @rbs end
# Enemies: 6 * stride 8 [active, x, y, speed, dir, plat_idx, _, _]

# @rbs module Cn
# @rbs   @s: NativeArray[Integer, 48]
# @rbs end
# Coins: 8 * stride 6 [active, x, y, phase, _, _]

# @rbs module Pt
# @rbs   @s: NativeArray[Integer, 300]
# @rbs end
# Particles: 50 * stride 6 [x, y, vx, vy, life, color]

# @rbs module St
# @rbs   @s: NativeArray[Integer, 90]
# @rbs end
# Stars: 30 * stride 3 [x, y, layer]

# ── Constants ──

SCREEN_W = 800
SCREEN_H = 600
NUM_PLATS = 12
MAX_ENEMIES = 6
MAX_COINS = 8
MAX_PARTS = 50
MAX_STARS = 30
PLAYER_W = 20
PLAYER_H = 28
ENEMY_SZ = 22
COIN_R = 7

GRAV = 45
JUMP_V = -1050
MOVE_V = 350
FRICTION = 85

SCENE_TITLE = 0
SCENE_GAME = 1
SCENE_OVER = 2

ST_IDLE = 0
ST_RUN = 1
ST_JUMP = 2
ST_FALL = 3

# ══════════════════════════════════════════
# Initialization
# ══════════════════════════════════════════

#: () -> Integer
def init_platforms
  # Ground segments
  Plt.s[0] = 0
  Plt.s[1] = 552
  Plt.s[2] = 280
  Plt.s[3] = 48
  Plt.s[4] = 520
  Plt.s[5] = 552
  Plt.s[6] = 280
  Plt.s[7] = 48
  Plt.s[8] = 330
  Plt.s[9] = 572
  Plt.s[10] = 140
  Plt.s[11] = 28
  # Floating platforms
  Plt.s[12] = 80
  Plt.s[13] = 440
  Plt.s[14] = 160
  Plt.s[15] = 16
  Plt.s[16] = 560
  Plt.s[17] = 420
  Plt.s[18] = 160
  Plt.s[19] = 16
  Plt.s[20] = 300
  Plt.s[21] = 360
  Plt.s[22] = 200
  Plt.s[23] = 16
  Plt.s[24] = 40
  Plt.s[25] = 300
  Plt.s[26] = 180
  Plt.s[27] = 16
  Plt.s[28] = 580
  Plt.s[29] = 300
  Plt.s[30] = 180
  Plt.s[31] = 16
  Plt.s[32] = 280
  Plt.s[33] = 220
  Plt.s[34] = 240
  Plt.s[35] = 16
  Plt.s[36] = 60
  Plt.s[37] = 170
  Plt.s[38] = 140
  Plt.s[39] = 16
  Plt.s[40] = 600
  Plt.s[41] = 180
  Plt.s[42] = 140
  Plt.s[43] = 16
  Plt.s[44] = 320
  Plt.s[45] = 100
  Plt.s[46] = 160
  Plt.s[47] = 16
  return 0
end

#: () -> Integer
def init_stars
  i = 0
  while i < MAX_STARS
    b = i * 3
    St.s[b] = fw_rand(SCREEN_W)
    St.s[b + 1] = fw_rand(SCREEN_H)
    St.s[b + 2] = fw_rand(3)
    i = i + 1
  end
  return 0
end

#: () -> Integer
def init_player
  PX.s[0] = 10000
  PX.s[1] = 50000
  PX.s[2] = 0
  PX.s[3] = 0
  PX.s[4] = PLAYER_W * 100
  PX.s[5] = PLAYER_H * 100
  fw_fsm_init(0, ST_IDLE)
  G.s[4] = 0
  G.s[5] = 5
  G.s[38] = 0
  G.s[39] = 0
  G.s[40] = 1
  return 0
end

#: () -> Integer
def init_game
  init_player
  G.s[6] = 0
  G.s[9] = 3600
  G.s[11] = 0
  G.s[36] = 0
  G.s[37] = 0
  i = 0
  while i < MAX_ENEMIES
    En.s[i * 8] = 0
    i = i + 1
  end
  i = 0
  while i < MAX_COINS
    Cn.s[i * 6] = 0
    i = i + 1
  end
  i = 0
  while i < MAX_PARTS
    Pt.s[i * 6 + 4] = 0
    i = i + 1
  end
  spawn_coins(4)
  spawn_enemy
  spawn_enemy
  return 0
end

# ══════════════════════════════════════════
# Particles
# ══════════════════════════════════════════

#: (Integer cx, Integer cy, Integer n, Integer col) -> Integer
def emit_burst(cx, cy, n, col)
  cnt = 0
  while cnt < n
    slot = 0
    while slot < MAX_PARTS
      b = slot * 6
      if Pt.s[b + 4] <= 0
        Pt.s[b] = cx
        Pt.s[b + 1] = cy
        Pt.s[b + 2] = fw_rand(9) - 4
        Pt.s[b + 3] = fw_rand(7) - 5
        Pt.s[b + 4] = 15 + fw_rand(15)
        Pt.s[b + 5] = col
        slot = MAX_PARTS
      end
      slot = slot + 1
    end
    cnt = cnt + 1
  end
  return 0
end

#: () -> Integer
def update_particles
  i = 0
  while i < MAX_PARTS
    b = i * 6
    if Pt.s[b + 4] > 0
      Pt.s[b] = Pt.s[b] + Pt.s[b + 2]
      Pt.s[b + 1] = Pt.s[b + 1] + Pt.s[b + 3]
      Pt.s[b + 3] = Pt.s[b + 3] + 1
      Pt.s[b + 4] = Pt.s[b + 4] - 1
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def draw_particles
  i = 0
  while i < MAX_PARTS
    b = i * 6
    life = Pt.s[b + 4]
    if life > 0
      sz = 2
      if life > 20
        sz = 4
      else
        if life > 10
          sz = 3
        end
      end
      Raylib.draw_rectangle(Pt.s[b], Pt.s[b + 1], sz, sz, Pt.s[b + 5])
    end
    i = i + 1
  end
  return 0
end

# ══════════════════════════════════════════
# Stars (parallax)
# ══════════════════════════════════════════

#: () -> Integer
def update_stars
  i = 0
  while i < MAX_STARS
    b = i * 3
    spd = St.s[b + 2] + 1
    St.s[b + 1] = St.s[b + 1] + spd
    if St.s[b + 1] > SCREEN_H
      St.s[b + 1] = 0
      St.s[b] = fw_rand(SCREEN_W)
    end
    i = i + 1
  end
  return 0
end

#: (Integer cam_x) -> Integer
def draw_stars(cam_x)
  i = 0
  while i < MAX_STARS
    b = i * 3
    layer = St.s[b + 2]
    px = St.s[b] - fw_parallax(cam_x, 10 + layer * 25)
    if px < 0
      px = px + SCREEN_W
    end
    if px >= SCREEN_W
      px = px - SCREEN_W
    end
    brt = 100 + layer * 70
    if brt > 255
      brt = 255
    end
    sz = layer + 1
    Raylib.draw_rectangle(px, St.s[b + 1], sz, sz, fw_rgba(brt, brt, brt + 20, 255))
    i = i + 1
  end
  return 0
end

# ══════════════════════════════════════════
# Enemies
# ══════════════════════════════════════════

#: () -> Integer
def spawn_enemy
  i = 0
  while i < MAX_ENEMIES
    b = i * 8
    if En.s[b] == 0
      plat = 3 + fw_rand(NUM_PLATS - 3)
      pb = plat * 4
      pw = Plt.s[pb + 2]
      margin = pw - ENEMY_SZ
      if margin < 1
        margin = 1
      end
      En.s[b] = 1
      En.s[b + 1] = Plt.s[pb] + fw_rand(margin)
      En.s[b + 2] = Plt.s[pb + 1] - ENEMY_SZ
      En.s[b + 3] = 1
      En.s[b + 4] = fw_rand(2)
      En.s[b + 5] = plat
      return 1
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def update_enemies
  i = 0
  while i < MAX_ENEMIES
    b = i * 8
    if En.s[b] == 1
      plat = En.s[b + 5]
      pb = plat * 4
      plat_x = Plt.s[pb]
      plat_w = Plt.s[pb + 2]
      if En.s[b + 4] == 0
        En.s[b + 1] = En.s[b + 1] + En.s[b + 3]
      else
        En.s[b + 1] = En.s[b + 1] - En.s[b + 3]
      end
      if En.s[b + 1] <= plat_x
        En.s[b + 1] = plat_x
        En.s[b + 4] = 0
      end
      if En.s[b + 1] + ENEMY_SZ >= plat_x + plat_w
        En.s[b + 1] = plat_x + plat_w - ENEMY_SZ
        En.s[b + 4] = 1
      end
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def draw_enemies
  frame = G.s[31]
  i = 0
  while i < MAX_ENEMIES
    b = i * 8
    if En.s[b] == 1
      ex = En.s[b + 1]
      ey = En.s[b + 2]
      c_body = fw_rgba(220, 60, 60, 255)
      c_eye = fw_rgba(255, 255, 255, 255)
      Raylib.draw_rectangle(ex + 2, ey, ENEMY_SZ - 4, ENEMY_SZ, c_body)
      Raylib.draw_rectangle(ex, ey + 4, ENEMY_SZ, ENEMY_SZ - 8, c_body)
      eo = 0
      if (frame / 30) % 2 == 0
        eo = 1
      end
      Raylib.draw_rectangle(ex + 4, ey + 5 + eo, 4, 4, c_eye)
      Raylib.draw_rectangle(ex + 14, ey + 5 + eo, 4, 4, c_eye)
      if G.s[10] == 1
        fw_draw_collision_rect(ex, ey, ENEMY_SZ, ENEMY_SZ, Raylib.color_red)
      end
    end
    i = i + 1
  end
  return 0
end

# ══════════════════════════════════════════
# Coins
# ══════════════════════════════════════════

#: (Integer n) -> Integer
def spawn_coins(n)
  cnt = 0
  while cnt < n
    i = 0
    while i < MAX_COINS
      b = i * 6
      if Cn.s[b] == 0
        plat = 3 + fw_rand(NUM_PLATS - 3)
        pb = plat * 4
        margin = Plt.s[pb + 2] - 16
        if margin < 1
          margin = 1
        end
        Cn.s[b] = 1
        Cn.s[b + 1] = Plt.s[pb] + fw_rand(margin) + 8
        Cn.s[b + 2] = Plt.s[pb + 1] - 20
        Cn.s[b + 3] = fw_rand(60)
        i = MAX_COINS
      end
      i = i + 1
    end
    cnt = cnt + 1
  end
  return 0
end

#: () -> Integer
def draw_coins
  frame = G.s[31]
  i = 0
  while i < MAX_COINS
    b = i * 6
    if Cn.s[b] == 1
      cx = Cn.s[b + 1]
      cy = Cn.s[b + 2]
      pulse_t = ((frame + Cn.s[b + 3]) * 15) % 1000
      pulse = fw_ease_out_quad(pulse_t)
      r = COIN_R + pulse / 500
      Raylib.draw_circle(cx, cy, r * 1.0, fw_rgba(255, 200, 0, 255))
      Raylib.draw_circle(cx, cy, (r - 3) * 1.0, fw_rgba(255, 255, 100, 255))
    end
    i = i + 1
  end
  return 0
end

# ══════════════════════════════════════════
# Player
# ══════════════════════════════════════════

#: () -> Integer
def player_hit
  if G.s[11] > 0
    return 0
  end
  G.s[5] = G.s[5] - 1
  G.s[11] = 90
  G.s[39] = 0
  fw_shake_start(16, 10, 5)
  px = PX.s[0] / 100 + PLAYER_W / 2
  py = PX.s[1] / 100 + PLAYER_H / 2
  emit_burst(px, py, 12, fw_rgba(255, 100, 100, 255))
  if G.s[5] <= 0
    fw_transition_start(20, SCENE_OVER, 45)
  end
  return 0
end

#: () -> Integer
def check_platform_collision
  px = PX.s[0] / 100
  py = PX.s[1] / 100
  vy = PX.s[3]
  i = 0
  while i < NUM_PLATS
    b = i * 4
    bx = Plt.s[b]
    by = Plt.s[b + 1]
    bw = Plt.s[b + 2]
    bh = Plt.s[b + 3]
    if Raylib.check_collision_recs(px * 1.0, py * 1.0, PLAYER_W * 1.0, PLAYER_H * 1.0, bx * 1.0, by * 1.0, bw * 1.0, bh * 1.0) == 1
      pb = py + PLAYER_H
      if vy >= 0
        if pb > by
          if pb < by + bh + 18
            PX.s[1] = (by - PLAYER_H) * 100
            PX.s[3] = 0
            G.s[38] = 1
          end
        end
      else
        if py < by + bh
          if py + 4 > by
            PX.s[1] = (by + bh) * 100
            PX.s[3] = 0
          end
        end
      end
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def update_player
  dir = fw_input_direction(0)
  if dir == 2
    PX.s[2] = 0 - MOVE_V
    G.s[4] = 1
  else
    if dir == 3
      PX.s[2] = MOVE_V
      G.s[4] = 0
    else
      vx = PX.s[2]
      PX.s[2] = vx * FRICTION / 100
    end
  end
  # Jump
  jk = 0
  if Raylib.key_down?(Raylib.key_space) == 1
    jk = 1
  end
  if Raylib.key_down?(Raylib.key_up) == 1
    jk = 1
  end
  if Raylib.key_down?(Raylib.key_w) == 1
    jk = 1
  end
  if jk == 0
    G.s[40] = 1
  end
  if G.s[38] == 1
    if jk == 1
      if G.s[40] == 1
        PX.s[3] = JUMP_V
        G.s[38] = 0
        G.s[40] = 0
        px = PX.s[0] / 100 + PLAYER_W / 2
        py = PX.s[1] / 100 + PLAYER_H
        emit_burst(px, py, 6, fw_rgba(180, 200, 255, 255))
        fw_shake_start(16, 3, 2)
      end
    end
  end
  # Gravity + move
  PX.s[3] = PX.s[3] + GRAV
  PX.s[0] = PX.s[0] + PX.s[2]
  PX.s[1] = PX.s[1] + PX.s[3]
  # Platform collision
  G.s[38] = 0
  check_platform_collision
  # Screen bounds
  if PX.s[0] < 0
    PX.s[0] = 0
    PX.s[2] = 0
  end
  max_x = (SCREEN_W - PLAYER_W) * 100
  if PX.s[0] > max_x
    PX.s[0] = max_x
    PX.s[2] = 0
  end
  # Fall off
  if PX.s[1] > SCREEN_H * 100
    player_hit
    PX.s[0] = 10000
    PX.s[1] = 50000
    PX.s[2] = 0
    PX.s[3] = 0
  end
  # FSM
  if G.s[38] == 1
    vxa = PX.s[2]
    if vxa < 0
      vxa = 0 - vxa
    end
    if vxa > 30
      fw_fsm_set(0, ST_RUN)
    else
      fw_fsm_set(0, ST_IDLE)
    end
  else
    if PX.s[3] < 0
      fw_fsm_set(0, ST_JUMP)
    else
      fw_fsm_set(0, ST_FALL)
    end
  end
  fw_fsm_tick(0)
  if G.s[11] > 0
    G.s[11] = G.s[11] - 1
  end
  fw_animate(34, 35, 4, 10)
  return 0
end

#: () -> Integer
def draw_player
  px = PX.s[0] / 100
  py = PX.s[1] / 100
  if G.s[11] > 0
    if (G.s[31] % 4) < 2
      return 0
    end
  end
  state = fw_fsm_state(0)
  c_body = fw_rgba(70, 130, 230, 255)
  if state == ST_JUMP
    c_body = fw_rgba(100, 180, 255, 255)
  end
  if state == ST_FALL
    c_body = fw_rgba(50, 100, 200, 255)
  end
  c_eye = fw_rgba(255, 255, 255, 255)
  c_dark = fw_rgba(40, 80, 180, 255)
  # Body
  Raylib.draw_rectangle(px + 2, py, PLAYER_W - 4, PLAYER_H, c_body)
  Raylib.draw_rectangle(px, py + 4, PLAYER_W, PLAYER_H - 8, c_body)
  # Eyes
  ey = py + 8
  if state == ST_JUMP
    ey = py + 6
  end
  if state == ST_FALL
    ey = py + 10
  end
  if G.s[4] == 0
    Raylib.draw_rectangle(px + 11, ey, 3, 3, c_eye)
    Raylib.draw_rectangle(px + 16, ey, 3, 3, c_eye)
  else
    Raylib.draw_rectangle(px + 1, ey, 3, 3, c_eye)
    Raylib.draw_rectangle(px + 6, ey, 3, 3, c_eye)
  end
  # Feet animation
  if state == ST_RUN
    af = G.s[35]
    if af % 2 == 0
      Raylib.draw_rectangle(px + 2, py + PLAYER_H - 2, 6, 2, c_dark)
      Raylib.draw_rectangle(px + 12, py + PLAYER_H, 6, 2, c_dark)
    else
      Raylib.draw_rectangle(px + 2, py + PLAYER_H, 6, 2, c_dark)
      Raylib.draw_rectangle(px + 12, py + PLAYER_H - 2, 6, 2, c_dark)
    end
  end
  if G.s[10] == 1
    fw_draw_collision_rect(px, py, PLAYER_W, PLAYER_H, Raylib.color_green)
  end
  return 0
end

# ══════════════════════════════════════════
# Collision
# ══════════════════════════════════════════

#: () -> Integer
def check_enemy_collision
  px = PX.s[0] / 100
  py = PX.s[1] / 100
  vy = PX.s[3]
  i = 0
  while i < MAX_ENEMIES
    b = i * 8
    if En.s[b] == 1
      ex = En.s[b + 1]
      ey = En.s[b + 2]
      if Raylib.check_collision_recs(px * 1.0, py * 1.0, PLAYER_W * 1.0, PLAYER_H * 1.0, ex * 1.0, ey * 1.0, ENEMY_SZ * 1.0, ENEMY_SZ * 1.0) == 1
        if vy > 0
          if py + PLAYER_H < ey + ENEMY_SZ / 2
            En.s[b] = 0
            PX.s[3] = JUMP_V / 2
            G.s[37] = G.s[37] + 1
            G.s[39] = G.s[39] + 1
            bonus = 100 + G.s[39] * 50
            G.s[6] = G.s[6] + bonus
            fw_tween_start(12, 20)
            fw_shake_start(16, 6, 4)
            emit_burst(ex + ENEMY_SZ / 2, ey + ENEMY_SZ / 2, 14, fw_rgba(255, 200, 50, 255))
            spawn_enemy
            return 0
          end
        end
        player_hit
      end
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def check_coin_collision
  px = PX.s[0] / 100
  py = PX.s[1] / 100
  pcx = px + PLAYER_W / 2
  pcy = py + PLAYER_H / 2
  i = 0
  while i < MAX_COINS
    b = i * 6
    if Cn.s[b] == 1
      cx = Cn.s[b + 1]
      cy = Cn.s[b + 2]
      dist = fw_manhattan(pcx, pcy, cx, cy)
      if dist < COIN_R * 3
        Cn.s[b] = 0
        G.s[36] = G.s[36] + 1
        G.s[6] = G.s[6] + 50
        fw_tween_start(12, 15)
        emit_burst(cx, cy, 8, fw_rgba(255, 255, 0, 255))
        spawn_coins(1)
      end
    end
    i = i + 1
  end
  return 0
end

# ══════════════════════════════════════════
# Drawing Helpers
# ══════════════════════════════════════════

#: () -> Integer
def draw_platforms
  i = 0
  while i < NUM_PLATS
    b = i * 4
    x = Plt.s[b]
    y = Plt.s[b + 1]
    w = Plt.s[b + 2]
    h = Plt.s[b + 3]
    if i < 3
      Raylib.draw_rectangle(x, y, w, h, fw_rgba(80, 60, 40, 255))
      Raylib.draw_rectangle(x, y, w, 4, fw_rgba(60, 140, 50, 255))
    else
      Raylib.draw_rectangle(x, y, w, h, fw_rgba(120, 100, 80, 255))
      Raylib.draw_rectangle(x, y, w, 3, fw_rgba(90, 170, 70, 255))
    end
    if G.s[10] == 1
      fw_draw_collision_rect(x, y, w, h, fw_rgba(255, 255, 0, 80))
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def draw_hud
  c_text = fw_rgba(200, 200, 200, 255)
  # HP bar
  hp_col = fw_rgba(80, 220, 80, 255)
  if G.s[5] <= 1
    hp_col = fw_rgba(220, 60, 60, 255)
  end
  fw_draw_txt("HP", 10, 10, 16, c_text)
  fw_draw_bar(35, 12, 100, 12, G.s[5], 5, hp_col)
  # Score
  fw_draw_txt("SCORE", 10, 30, 16, c_text)
  fw_draw_num(70, 30, G.s[6], 16, fw_rgba(255, 220, 50, 255))
  # Score popup tween
  prog = fw_tween_advance(12)
  if prog > 0
    if prog < 1000
      eased = fw_ease_out_cubic(prog)
      popup_y = fw_tween(30, 10, eased)
      al = fw_tween(255, 0, eased)
      al = fw_clamp(al, 0, 255)
      fw_draw_txt("+", 130, popup_y, 14, fw_rgba(255, 255, 100, al))
    end
  end
  # Timer
  secs = G.s[9] / 60
  c_timer = fw_rgba(200, 200, 255, 255)
  if secs < 10
    c_timer = fw_rgba(255, 100, 100, 255)
  end
  fw_draw_txt("TIME", 370, 10, 16, c_text)
  fw_draw_num(420, 10, secs, 20, c_timer)
  # Coins + KO
  fw_draw_txt("COINS", 620, 10, 16, c_text)
  fw_draw_num(690, 10, G.s[36], 16, fw_rgba(255, 200, 0, 255))
  fw_draw_txt("KO", 640, 30, 16, c_text)
  fw_draw_num(670, 30, G.s[37], 16, fw_rgba(255, 100, 100, 255))
  # Combo
  if G.s[39] > 1
    c_combo = fw_rgba(255, 200, 50, 255)
    fw_draw_txt("COMBO x", 300, 570, 20, c_combo)
    fw_draw_num(410, 570, G.s[39], 20, c_combo)
  end
  # Debug overlay
  if G.s[10] == 1
    fw_draw_fps(10, 560, 14, fw_rgba(0, 255, 0, 255))
    fw_draw_debug_val("VX", PX.s[2], 100, 560, 14, fw_rgba(0, 255, 0, 255))
    fw_draw_debug_val("VY", PX.s[3], 200, 560, 14, fw_rgba(0, 255, 0, 255))
    fw_draw_debug_val("FSM", fw_fsm_state(0), 340, 560, 14, fw_rgba(0, 255, 0, 255))
    fw_draw_debug_val("GND", G.s[38], 460, 560, 14, fw_rgba(0, 255, 0, 255))
  end
  return 0
end

# ══════════════════════════════════════════
# Scenes
# ══════════════════════════════════════════

#: () -> Integer
def scene_title_update
  update_stars
  G.s[8] = fw_menu_cursor(G.s[8], 2)
  if fw_confirm_pressed == 1
    cursor = G.s[8]
    if cursor == 0
      init_game
      fw_transition_start(20, SCENE_GAME, 30)
    else
      return -1
    end
  end
  return 0
end

#: () -> Integer
def scene_title_draw
  Raylib.clear_background(fw_rgba(15, 8, 30, 255))
  draw_stars(0)
  c_title = fw_rgba(255, 220, 50, 255)
  c_sub = fw_rgba(120, 120, 140, 255)
  c_menu = fw_rgba(200, 200, 200, 255)
  Raylib.draw_text("COIN DASH", 250, 150, 60, c_title)
  Raylib.draw_text("Game API Showcase", 290, 220, 20, c_sub)
  # Decorative bouncing coin
  frame = G.s[31]
  bt = (frame * 8) % 1000
  bounce = fw_ease_out_bounce(bt)
  cy = 310 - bounce / 20
  Raylib.draw_circle(400, cy, 16.0, fw_rgba(255, 200, 0, 255))
  Raylib.draw_circle(400, cy, 12.0, fw_rgba(255, 255, 100, 255))
  # Menu
  cursor = G.s[8]
  fw_draw_cursor(280, 370 + cursor * 40, 16, c_title)
  Raylib.draw_text("START GAME", 310, 370, 24, c_menu)
  Raylib.draw_text("QUIT", 310, 410, 24, c_menu)
  Raylib.draw_text("Arrows/WASD: Move  Space/Up: Jump  D: Debug", 130, 520, 16, c_sub)
  Raylib.draw_text("Gamepad supported", 310, 550, 16, c_sub)
  return 0
end

#: () -> Integer
def scene_game_update
  G.s[9] = G.s[9] - 1
  if G.s[9] <= 0
    G.s[9] = 0
    fw_transition_start(20, SCENE_OVER, 45)
  end
  # Periodic spawns
  frame = G.s[31]
  if frame % 180 == 0
    if frame > 60
      spawn_enemy
    end
  end
  if frame % 300 == 0
    spawn_coins(1)
  end
  update_player
  update_enemies
  update_particles
  update_stars
  check_enemy_collision
  check_coin_collision
  fw_shake_update(16)
  # Debug toggle
  if Raylib.key_pressed?(Raylib.key_d) == 1
    if G.s[10] == 0
      G.s[10] = 1
    else
      G.s[10] = 0
    end
  end
  # Camera
  target_x = PX.s[0] / 100 - SCREEN_W / 2 + PLAYER_W / 2
  G.s[32] = fw_lerp(G.s[32], target_x, 8)
  return 0
end

#: () -> Integer
def scene_game_draw
  sox = fw_shake_x(16)
  soy = fw_shake_y(16)
  cam_x = fw_clamp(G.s[32], 0, 0)
  # Background
  Raylib.draw_rectangle_gradient_v(0, 0, SCREEN_W, SCREEN_H,
    fw_rgba(15, 8, 30, 255), fw_rgba(30, 20, 50, 255))
  draw_stars(cam_x)
  # Camera
  ox = (SCREEN_W / 2 + sox) * 1.0
  oy = (SCREEN_H / 2 + soy) * 1.0
  tx = (SCREEN_W / 2 + cam_x) * 1.0
  ty = (SCREEN_H / 2) * 1.0
  Raylib.begin_mode_2d(ox, oy, tx, ty, 0.0, 1.0)
  draw_platforms
  draw_coins
  draw_enemies
  draw_player
  draw_particles
  Raylib.end_mode_2d
  # HUD (screen space)
  draw_hud
  return 0
end

#: () -> Integer
def scene_over_update
  update_stars
  update_particles
  G.s[8] = fw_menu_cursor(G.s[8], 2)
  if fw_confirm_pressed == 1
    cursor = G.s[8]
    if cursor == 0
      init_game
      fw_transition_start(20, SCENE_GAME, 30)
    else
      fw_transition_start(20, SCENE_TITLE, 30)
    end
  end
  return 0
end

#: () -> Integer
def scene_over_draw
  Raylib.clear_background(fw_rgba(10, 5, 20, 255))
  draw_stars(0)
  draw_particles
  c_text = fw_rgba(200, 200, 200, 255)
  c_score = fw_rgba(255, 220, 50, 255)
  if G.s[5] <= 0
    Raylib.draw_text("GAME OVER", 270, 120, 50, fw_rgba(255, 80, 80, 255))
  else
    Raylib.draw_text("TIME UP!", 285, 120, 50, c_score)
  end
  # Stats
  Raylib.draw_text("FINAL SCORE", 310, 210, 24, c_text)
  fw_draw_num(340, 250, G.s[6], 32, c_score)
  # Score bar (eased width)
  bar_w = fw_clamp(G.s[6] / 5, 0, 400)
  fw_draw_bar(200, 300, 400, 16, bar_w, 400, c_score)
  # Detail stats
  fw_draw_txt("Coins:", 280, 340, 20, c_text)
  fw_draw_num(380, 340, G.s[36], 20, fw_rgba(255, 200, 0, 255))
  fw_draw_txt("Enemies:", 280, 370, 20, c_text)
  fw_draw_num(400, 370, G.s[37], 20, fw_rgba(255, 100, 100, 255))
  # Damage calc display (showcase fw_calc_damage)
  dmg = fw_calc_damage(G.s[37] * 10, 5)
  fw_draw_txt("Power:", 280, 400, 20, c_text)
  fw_draw_num(380, 400, dmg, 20, fw_rgba(200, 100, 255, 255))
  # Menu
  cursor = G.s[8]
  fw_draw_cursor(280, 450 + cursor * 40, 16, c_score)
  Raylib.draw_text("RETRY", 310, 450, 24, c_text)
  Raylib.draw_text("TITLE", 310, 490, 24, c_text)
  return 0
end

# ══════════════════════════════════════════
# Main Loop
# ══════════════════════════════════════════

#: () -> Integer
def main
  Raylib.init_window(SCREEN_W, SCREEN_H, "Coin Dash - Konpeito Game Showcase")
  Raylib.set_target_fps(60)
  G.s[7] = SCENE_TITLE
  G.s[8] = 0
  G.s[29] = 42
  G.s[10] = 0
  init_platforms
  init_stars

  while Raylib.window_should_close == 0
    fw_tick
    # Transition
    trans = fw_transition_update(20)
    if trans == 2
      G.s[7] = fw_transition_next_scene(20)
      G.s[8] = 0
    end
    # Update
    scene = G.s[7]
    result = 0
    if scene == SCENE_TITLE
      result = scene_title_update
    end
    if scene == SCENE_GAME
      scene_game_update
    end
    if scene == SCENE_OVER
      scene_over_update
    end
    # Draw
    Raylib.begin_drawing
    if scene == SCENE_TITLE
      scene_title_draw
    end
    if scene == SCENE_GAME
      scene_game_draw
    end
    if scene == SCENE_OVER
      scene_over_draw
    end
    # Transition fade overlay
    alpha = fw_transition_alpha(20)
    if alpha > 0
      fw_draw_fade(alpha, SCREEN_W, SCREEN_H)
    end
    Raylib.end_drawing
    # Quit
    if result == -1
      Raylib.close_window
      return 0
    end
    if fw_cancel_pressed == 1
      if scene == SCENE_TITLE
        Raylib.close_window
        return 0
      end
    end
  end

  Raylib.close_window
  return 0
end

main
