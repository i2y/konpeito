# Physics & Effects Demo
#
# Demonstrates game framework features:
#   - Simple physics (gravity, AABB collision)
#   - Particle system
#   - Screen shake
#   - Tween/easing animations
#   - Timer system
#   - FSM (state machine)
#   - Debug overlay
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -o examples/mruby_physics_demo/physics_demo \
#     examples/mruby_physics_demo/physics_demo.rb
#
# Run:
#   ./examples/mruby_physics_demo/physics_demo
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/game_framework/game_framework"

# @rbs module G
# @rbs   @s: NativeArray[Integer, 64]
# @rbs end
# G.s layout:
#   [0-7]   = player physics (x, y, vx, vy, w, h, flags, _)
#   [8-15]  = ground physics (x, y, vx, vy, w, h, flags, _)
#   [16-19] = shake (remaining, intensity, ox, oy)
#   [20-23] = FSM (state, prev, frames, just_entered)
#   [24-25] = tween (frame, total)
#   [26-28] = timer (remaining, interval, active)
#   [29]    = random seed (used by fw_rand)
#   [30]    = font_id+1
#   [31]    = frame counter
#   [32]    = score
#   [33]    = on_ground flag
#   [34]    = particle spawn timer
#   [35]    = show_debug

# @rbs module Particles
# @rbs   @p: NativeArray[Integer, 384]
# @rbs end
# 64 particles x 6 stride = 384
# Each particle: [x, y, vx, vy, life, max_life]

# States
STATE_IDLE   = 0
STATE_JUMP   = 1
STATE_FALL   = 2

SCREEN_W = 800
SCREEN_H = 600
GRAVITY  = 30
JUMP_VEL = -1200
MOVE_SPEED = 500
GROUND_Y = 45000

PARTICLE_COUNT  = 64
PARTICLE_STRIDE = 6

# ── Particle helpers (access Particles.p directly) ──

#: (Integer x100, Integer y100, Integer vx, Integer vy, Integer life) -> Integer
def emit_particle(x100, y100, vx, vy, life)
  i = 0
  while i < PARTICLE_COUNT
    base = i * PARTICLE_STRIDE
    if Particles.p[base + 4] <= 0
      Particles.p[base] = x100
      Particles.p[base + 1] = y100
      Particles.p[base + 2] = vx
      Particles.p[base + 3] = vy
      Particles.p[base + 4] = life
      Particles.p[base + 5] = life
      return i
    end
    i = i + 1
  end
  return 0 - 1
end

#: (Integer gravity100) -> Integer
def update_particles(gravity100)
  i = 0
  while i < PARTICLE_COUNT
    base = i * PARTICLE_STRIDE
    if Particles.p[base + 4] > 0
      Particles.p[base] = Particles.p[base] + Particles.p[base + 2]
      Particles.p[base + 1] = Particles.p[base + 1] + Particles.p[base + 3]
      Particles.p[base + 3] = Particles.p[base + 3] + gravity100
      Particles.p[base + 4] = Particles.p[base + 4] - 1
    end
    i = i + 1
  end
  return 0
end

#: (Integer sz, Integer col) -> Integer
def draw_particles(sz, col)
  i = 0
  while i < PARTICLE_COUNT
    base = i * PARTICLE_STRIDE
    if Particles.p[base + 4] > 0
      dpx = Particles.p[base] / 100
      dpy = Particles.p[base + 1] / 100
      Raylib.draw_rectangle(dpx, dpy, sz, sz, col)
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def count_active_particles
  n = 0
  i = 0
  while i < PARTICLE_COUNT
    base = i * PARTICLE_STRIDE
    if Particles.p[base + 4] > 0
      n = n + 1
    end
    i = i + 1
  end
  return n
end

#: () -> Integer
def init_game
  G.s[29] = 12345
  G.s[32] = 0
  G.s[33] = 0
  G.s[34] = 0
  G.s[35] = 1

  # Player: 100x coords, centered
  G.s[0] = 35000
  G.s[1] = 30000
  G.s[2] = 0
  G.s[3] = 0
  G.s[4] = 3000
  G.s[5] = 4000
  G.s[6] = 1
  G.s[7] = 0

  # Ground
  G.s[8] = 0
  G.s[9] = GROUND_Y
  G.s[10] = 0
  G.s[11] = 0
  G.s[12] = 80000
  G.s[13] = 1500
  G.s[14] = 1
  G.s[15] = 0

  # Init FSM
  fw_fsm_init(20, STATE_IDLE)

  # Init particle spawn timer (every 10 frames)
  G.s[26] = 10
  G.s[27] = 10
  G.s[28] = 1

  return 0
end

#: () -> Integer
def update_game
  fw_tick

  # ── Input ──
  # Horizontal movement
  if Raylib.key_down?(Raylib.key_left) != 0
    G.s[2] = 0 - MOVE_SPEED
  else
    if Raylib.key_down?(Raylib.key_right) != 0
      G.s[2] = MOVE_SPEED
    else
      G.s[2] = 0
    end
  end

  # Jump
  if Raylib.key_pressed?(Raylib.key_space) != 0
    if G.s[33] == 1
      G.s[3] = JUMP_VEL
      G.s[33] = 0
      fw_fsm_set(20, STATE_JUMP)
      fw_shake_start(16, 5, 3)
    end
  end

  # Toggle debug
  if Raylib.key_pressed?(Raylib.key_d) != 0
    if G.s[35] == 0
      G.s[35] = 1
    else
      G.s[35] = 0
    end
  end

  # ── Physics ──
  # Apply gravity to player vy
  G.s[3] = G.s[3] + GRAVITY
  # Apply velocity to player position
  G.s[0] = G.s[0] + G.s[2]
  G.s[1] = G.s[1] + G.s[3]

  # Ground collision (inline AABB)
  if G.s[1] + G.s[5] > GROUND_Y
    # Push player above ground
    G.s[1] = GROUND_Y - G.s[5]
    G.s[3] = 0
    if G.s[33] == 0
      G.s[33] = 1
      fw_fsm_set(20, STATE_IDLE)
      # Landing particles
      lpx = G.s[0] + 1500
      lpy = G.s[1] + G.s[5]
      li = 0
      while li < 8
        lvx = fw_rand(600) - 300
        lvy = 0 - fw_rand(400) - 100
        emit_particle(lpx, lpy, lvx, lvy, 20)
        li = li + 1
      end
      if fw_shake_active(16) == 0
        fw_shake_start(16, 8, 4)
      end
    end
  else
    G.s[33] = 0
    if G.s[3] > 0
      fw_fsm_set(20, STATE_FALL)
    end
  end

  # Clamp to screen
  if G.s[0] < 0
    G.s[0] = 0
  end
  if G.s[0] + G.s[4] > 80000
    G.s[0] = 80000 - G.s[4]
  end

  # ── FSM tick ──
  fw_fsm_tick(20)

  # ── Screen shake ──
  fw_shake_update(16)

  # ── Particles ──
  update_particles(15)

  # Trail particles while moving (inline timer tick)
  timer_triggered = 0
  if G.s[28] == 1
    G.s[26] = G.s[26] - 1
    if G.s[26] <= 0
      interval = G.s[27]
      if interval > 0
        G.s[26] = interval
      else
        G.s[28] = 0
      end
      timer_triggered = 1
    end
  end

  if timer_triggered == 1
    if G.s[2] != 0
      tpx = G.s[0] + 1500
      tpy = G.s[1] + 3500
      tvx = 0 - G.s[2] / 4
      tvy = 0 - fw_rand(200)
      emit_particle(tpx, tpy, tvx, tvy, 15)
      G.s[32] = G.s[32] + 1
    end
  end

  return 0
end

#: () -> Integer
def draw_game
  Raylib.begin_drawing
  Raylib.clear_background(fw_rgba(30, 30, 46, 255))

  # Apply shake offset
  ox = fw_shake_x(16)
  oy = fw_shake_y(16)

  # Draw ground
  gx = G.s[8] / 100 + ox
  gy = G.s[9] / 100 + oy
  Raylib.draw_rectangle(gx, gy, 800, 15, fw_rgba(80, 80, 120, 255))

  # Draw particles
  col_trail = fw_rgba(100, 180, 255, 200)
  draw_particles(3, col_trail)

  # Draw player
  px = G.s[0] / 100 + ox
  py = G.s[1] / 100 + oy
  state = fw_fsm_state(20)
  if state == STATE_IDLE
    Raylib.draw_rectangle(px, py, 30, 40, fw_rgba(100, 200, 255, 255))
  end
  if state == STATE_JUMP
    Raylib.draw_rectangle(px, py, 30, 35, fw_rgba(255, 200, 100, 255))
  end
  if state == STATE_FALL
    Raylib.draw_rectangle(px, py, 30, 45, fw_rgba(255, 100, 100, 255))
  end

  # Draw HUD
  col_text = fw_rgba(240, 240, 245, 255)
  fw_draw_txt("Score:", 20, 20, 20, col_text)
  fw_draw_num(100, 20, G.s[32], 20, col_text)

  # State label
  if state == STATE_IDLE
    fw_draw_txt("IDLE", 20, 50, 16, fw_rgba(100, 200, 100, 255))
  end
  if state == STATE_JUMP
    fw_draw_txt("JUMP", 20, 50, 16, fw_rgba(255, 200, 100, 255))
  end
  if state == STATE_FALL
    fw_draw_txt("FALL", 20, 50, 16, fw_rgba(255, 100, 100, 255))
  end

  # Debug overlay
  if G.s[35] == 1
    fw_draw_fps(SCREEN_W - 120, 10, 16, col_text)
    fw_draw_debug_val("Particles:", count_active_particles, SCREEN_W - 200, 30, 14, col_text)
    fw_draw_debug_val("Shake:", fw_shake_active(16), SCREEN_W - 200, 48, 14, col_text)
    fw_draw_debug_val("FSM frames:", fw_fsm_frames(20), SCREEN_W - 200, 66, 14, col_text)
    fw_draw_debug_val("On ground:", G.s[33], SCREEN_W - 200, 84, 14, col_text)

    # Collision rects
    fw_draw_collision_rect(px, py, 30, 40, fw_rgba(0, 255, 0, 128))
    fw_draw_collision_rect(gx, gy, 800, 15, fw_rgba(255, 0, 0, 128))
  end

  # Instructions
  fw_draw_txt("[Arrow] Move  [Space] Jump  [D] Debug  [ESC] Quit", 150, SCREEN_H - 30, 14, fw_rgba(120, 120, 140, 255))

  Raylib.end_drawing
  return 0
end

#: () -> Integer
def main
  Raylib.init_window(SCREEN_W, SCREEN_H, "Physics & Effects Demo")
  Raylib.set_target_fps(60)

  init_game

  while Raylib.window_should_close == 0
    update_game
    draw_game
  end

  Raylib.close_window
  return 0
end

main
