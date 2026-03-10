# Space Invaders — Konpeito + mruby + raylib (module NativeArray version)
# rbs_inline: enabled
#
# No C wrapper file needed — all game state is declared as inline RBS
# module NativeArrays and compiled to LLVM global arrays.
#
# Build:
#   konpeito build --target mruby --inline -o examples/mruby_space_invaders/space_invaders examples/mruby_space_invaders/space_invaders.rb
#
# Controls: Left/Right arrows to move, SPACE to shoot, ESC to quit

# @rbs module Inv
# @rbs   @gs: NativeArray[Integer, 12]
# @rbs   @star_x: NativeArray[Integer, 60]
# @rbs   @star_y: NativeArray[Integer, 60]
# @rbs   @star_s: NativeArray[Integer, 60]
# @rbs   @ex: NativeArray[Integer, 55]
# @rbs   @ey: NativeArray[Integer, 55]
# @rbs   @ea: NativeArray[Integer, 55]
# @rbs   @et: NativeArray[Integer, 55]
# @rbs   @bx: NativeArray[Integer, 5]
# @rbs   @by: NativeArray[Integer, 5]
# @rbs   @ba: NativeArray[Integer, 5]
# @rbs   @ebx: NativeArray[Integer, 8]
# @rbs   @eby: NativeArray[Integer, 8]
# @rbs   @eba: NativeArray[Integer, 8]
# @rbs   @shx: NativeArray[Integer, 60]
# @rbs   @shy: NativeArray[Integer, 60]
# @rbs   @sha: NativeArray[Integer, 60]
# @rbs   @pa: NativeArray[Integer, 600]
# @rbs end

# ── Helpers ──

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

#: (Integer seed) -> Integer
def pseudo_rand(seed)
  seed = seed * 1103515245 + 12345
  seed = seed % 2147483647
  if seed < 0
    seed = seed + 2147483647
  end
  return seed
end

#: (Integer b) -> Integer
def make_gray(b)
  return b * 16777216 + b * 65536 + b * 256 + 255
end

# ── Stars (60, parallax) ──

#: (Integer seed) -> Integer
def init_stars(seed)
  i = 0
  while i < 60
    seed = pseudo_rand(seed)
    Inv.star_x[i] = seed % 800
    seed = pseudo_rand(seed)
    Inv.star_y[i] = seed % 600
    seed = pseudo_rand(seed)
    Inv.star_s[i] = (seed % 3) + 1
    i = i + 1
  end
  return seed
end

#: () -> Integer
def update_stars
  i = 0
  while i < 60
    sy = Inv.star_y[i] + Inv.star_s[i]
    if sy > 600
      sy = 0
    end
    Inv.star_y[i] = sy
    i = i + 1
  end
  return 0
end

#: () -> Integer
def draw_stars
  i = 0
  while i < 60
    s = Inv.star_s[i]
    b = 80 + s * 50
    if b > 255
      b = 255
    end
    Raylib.draw_rectangle(Inv.star_x[i], Inv.star_y[i], s, s, make_gray(b))
    i = i + 1
  end
  return 0
end

# ── Enemies (55 = 5x11) ──

#: () -> Integer
def init_enemies
  idx = 0
  while idx < 55
    row = idx / 11
    col = idx % 11
    Inv.ex[idx] = 120 + col * 36
    Inv.ey[idx] = 60 + row * 28
    Inv.ea[idx] = 1
    if row < 2
      Inv.et[idx] = 0
    else
      if row == 4
        Inv.et[idx] = 2
      else
        Inv.et[idx] = 1
      end
    end
    idx = idx + 1
  end
  return 0
end

#: () -> Integer
def count_alive
  n = 0
  i = 0
  while i < 55
    if Inv.ea[i] == 1
      n = n + 1
    end
    i = i + 1
  end
  return n
end

#: (Integer dir_x, Integer speed) -> Integer
def check_wall_hit(dir_x, speed)
  i = 0
  hit = 0
  while i < 55
    if Inv.ea[i] == 1
      nx = Inv.ex[i] + dir_x * speed
      if nx < 10
        hit = 1
      else
        if nx + 28 > 790
          hit = 1
        end
      end
    end
    i = i + 1
  end
  return hit
end

#: () -> Integer
def move_enemies_down
  i = 0
  reached = 0
  while i < 55
    if Inv.ea[i] == 1
      ny = Inv.ey[i] + 16
      Inv.ey[i] = ny
      if ny + 20 > 520
        reached = 1
      end
    end
    i = i + 1
  end
  return reached
end

#: (Integer dir_x, Integer speed) -> Integer
def move_enemies_horiz(dir_x, speed)
  i = 0
  while i < 55
    if Inv.ea[i] == 1
      Inv.ex[i] = Inv.ex[i] + dir_x * speed
    end
    i = i + 1
  end
  return 0
end

#: (Integer dir_x, Integer wave) -> Integer
def update_enemies(dir_x, wave)
  alive_n = count_alive
  speed = 1 + wave + (55 - alive_n) / 10
  hit_wall = check_wall_hit(dir_x, speed)
  reached = 0
  if hit_wall == 1
    dir_x = 0 - dir_x
    reached = move_enemies_down
  else
    move_enemies_horiz(dir_x, speed)
  end
  return dir_x * 1000 + reached
end

#: (Integer frame) -> Integer
def draw_enemies(frame)
  # Colors (RGBA)
  c_type0 = 0x009E2FFF  # green-ish
  c_type1 = 0x66BFFFFF  # light blue
  c_type2 = 0xFFA100FF  # orange
  c_eye   = 0xE62937FF  # red
  c_black = 0x000000FF

  i = 0
  while i < 55
    if Inv.ea[i] == 1
      x = Inv.ex[i]
      y = Inv.ey[i]
      t = Inv.et[i]
      if t == 0
        cx = x + 14
        cy = y + 10
        Raylib.draw_rectangle(cx - 6, cy - 3, 12, 6, c_type0)
        Raylib.draw_rectangle(cx - 3, cy - 6, 6, 12, c_type0)
      else
        if t == 1
          Raylib.draw_rectangle(x + 2, y + 2, 24, 16, c_type1)
          Raylib.draw_rectangle(x + 6, y + 6, 4, 4, c_black)
          Raylib.draw_rectangle(x + 18, y + 6, 4, 4, c_black)
        else
          Raylib.draw_rectangle(x, y + 4, 28, 12, c_type2)
          Raylib.draw_rectangle(x + 4, y, 20, 20, c_type2)
          Raylib.draw_rectangle(x + 6, y + 6, 5, 5, c_eye)
          Raylib.draw_rectangle(x + 17, y + 6, 5, 5, c_eye)
        end
      end
    end
    i = i + 1
  end
  return 0
end

# ── Player bullets (5) ──

#: (Integer px, Integer py) -> Integer
def fire_bullet(px, py)
  i = 0
  while i < 5
    if Inv.ba[i] == 0
      Inv.bx[i] = px + 18
      Inv.by[i] = py - 6
      Inv.ba[i] = 1
      return 1
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def update_bullets
  i = 0
  while i < 5
    if Inv.ba[i] == 1
      ny = Inv.by[i] - 8
      Inv.by[i] = ny
      if ny < -10
        Inv.ba[i] = 0
      end
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def draw_bullets
  c_bullet = 0xFDF900FF
  i = 0
  while i < 5
    if Inv.ba[i] == 1
      Raylib.draw_rectangle(Inv.bx[i], Inv.by[i], 3, 8, c_bullet)
    end
    i = i + 1
  end
  return 0
end

# ── Enemy bullets (8) ──

#: (Integer seed) -> Integer
def enemy_shoot(seed)
  seed = pseudo_rand(seed)
  if seed % 40 != 0
    return seed
  end
  alive_n = count_alive
  if alive_n == 0
    return seed
  end
  seed = pseudo_rand(seed)
  pick = seed % alive_n
  idx = 0
  cnt = 0
  while idx < 55
    if Inv.ea[idx] == 1
      if cnt == pick
        slot = 0
        while slot < 8
          if Inv.eba[slot] == 0
            Inv.ebx[slot] = Inv.ex[idx] + 14
            Inv.eby[slot] = Inv.ey[idx] + 20
            Inv.eba[slot] = 1
            slot = 8
          end
          slot = slot + 1
        end
        idx = 55
      end
      cnt = cnt + 1
    end
    idx = idx + 1
  end
  return seed
end

#: () -> Integer
def update_ebullets
  i = 0
  while i < 8
    if Inv.eba[i] == 1
      ny = Inv.eby[i] + 4
      Inv.eby[i] = ny
      if ny > 610
        Inv.eba[i] = 0
      end
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def draw_ebullets
  c_ebullet = 0xE62937FF
  i = 0
  while i < 8
    if Inv.eba[i] == 1
      Raylib.draw_rectangle(Inv.ebx[i] - 1, Inv.eby[i], 3, 8, c_ebullet)
    end
    i = i + 1
  end
  return 0
end

# ── Particles (100 x 6 fields = 600) ──

#: (Integer seed, Integer cx, Integer cy, Integer color) -> Integer
def spawn_explosion(seed, cx, cy, color)
  seed = pseudo_rand(seed)
  n = 8 + seed % 5
  cnt = 0
  while cnt < n
    slot = 0
    while slot < 100
      base = slot * 6
      if Inv.pa[base + 4] <= 0
        Inv.pa[base + 0] = cx
        Inv.pa[base + 1] = cy
        seed = pseudo_rand(seed)
        Inv.pa[base + 2] = (seed % 9) - 4
        seed = pseudo_rand(seed)
        Inv.pa[base + 3] = (seed % 9) - 4
        seed = pseudo_rand(seed)
        Inv.pa[base + 4] = 15 + seed % 20
        Inv.pa[base + 5] = color
        slot = 100
      end
      slot = slot + 1
    end
    cnt = cnt + 1
  end
  return seed
end

#: () -> Integer
def update_particles
  slot = 0
  while slot < 100
    base = slot * 6
    if Inv.pa[base + 4] > 0
      Inv.pa[base + 0] = Inv.pa[base + 0] + Inv.pa[base + 2]
      Inv.pa[base + 1] = Inv.pa[base + 1] + Inv.pa[base + 3]
      Inv.pa[base + 4] = Inv.pa[base + 4] - 1
    end
    slot = slot + 1
  end
  return 0
end

#: () -> Integer
def draw_particles
  slot = 0
  while slot < 100
    base = slot * 6
    life = Inv.pa[base + 4]
    if life > 0
      sz = 2
      if life > 20
        sz = 4
      else
        if life > 10
          sz = 3
        end
      end
      Raylib.draw_rectangle(Inv.pa[base], Inv.pa[base + 1], sz, sz, Inv.pa[base + 5])
    end
    slot = slot + 1
  end
  return 0
end

# ── Shields (4 x 15 blocks = 60) ──

#: () -> Integer
def init_shields
  idx = 0
  while idx < 60
    sid = idx / 15
    blk = idx % 15
    row = blk / 5
    col = blk % 5
    Inv.shx[idx] = 120 + sid * 160 + col * 8
    Inv.shy[idx] = 480 + row * 8
    Inv.sha[idx] = 1
    idx = idx + 1
  end
  return 0
end

#: () -> Integer
def draw_shields
  c_shield = 0x00E430FF
  i = 0
  while i < 60
    if Inv.sha[i] == 1
      Raylib.draw_rectangle(Inv.shx[i], Inv.shy[i], 8, 8, c_shield)
    end
    i = i + 1
  end
  return 0
end

# ── Collisions ──

#: (Integer bxi, Integer byi) -> Integer
def find_hit_enemy(bxi, byi)
  ei = 0
  while ei < 55
    if Inv.ea[ei] == 1
      if bxi + 3 > Inv.ex[ei]
        if bxi < Inv.ex[ei] + 28
          if byi < Inv.ey[ei] + 20
            if byi + 8 > Inv.ey[ei]
              return ei
            end
          end
        end
      end
    end
    ei = ei + 1
  end
  return -1
end

#: (Integer t) -> Integer
def score_for_type(t)
  if t == 0
    return 30
  end
  if t == 1
    return 20
  end
  return 10
end

#: (Integer t) -> Integer
def color_for_type(t)
  if t == 0
    return 0xFDF900FF
  end
  if t == 1
    return 0x66BFFFFF
  end
  return 0xFFA100FF
end

#: () -> Integer
def do_bullet_collisions
  bi = 0
  hits = 0
  while bi < 5
    if Inv.ba[bi] == 1
      ei = find_hit_enemy(Inv.bx[bi], Inv.by[bi])
      if ei >= 0
        Inv.ea[ei] = 0
        Inv.ba[bi] = 0
        hits = hits + 1
        Inv.gs[3] = Inv.gs[3] + score_for_type(Inv.et[ei])
        new_seed = spawn_explosion(Inv.gs[10], Inv.ex[ei] + 14, Inv.ey[ei] + 10, color_for_type(Inv.et[ei]))
        Inv.gs[10] = new_seed
      end
    end
    bi = bi + 1
  end
  combo = Inv.gs[5]
  if hits > 0
    combo = combo + hits
  else
    if combo > 0
      combo = combo - 1
    end
  end
  Inv.gs[5] = combo
  return 0
end

#: (Integer px, Integer py) -> Integer
def collide_ebullets_player(px, py)
  i = 0
  while i < 8
    if Inv.eba[i] == 1
      if Inv.ebx[i] + 1 > px
        if Inv.ebx[i] - 1 < px + 40
          if Inv.eby[i] + 8 > py
            if Inv.eby[i] < py + 16
              Inv.eba[i] = 0
              return 1
            end
          end
        end
      end
    end
    i = i + 1
  end
  return 0
end

#: () -> Integer
def collide_player_bullets_shields
  bi = 0
  while bi < 5
    if Inv.ba[bi] == 1
      si = 0
      while si < 60
        if Inv.sha[si] == 1
          if Inv.bx[bi] + 3 > Inv.shx[si]
            if Inv.bx[bi] < Inv.shx[si] + 8
              if Inv.by[bi] < Inv.shy[si] + 8
                if Inv.by[bi] + 8 > Inv.shy[si]
                  Inv.sha[si] = 0
                  Inv.ba[bi] = 0
                  si = 60
                end
              end
            end
          end
        end
        si = si + 1
      end
    end
    bi = bi + 1
  end
  return 0
end

#: () -> Integer
def collide_enemy_bullets_shields
  bi = 0
  while bi < 8
    if Inv.eba[bi] == 1
      si = 0
      while si < 60
        if Inv.sha[si] == 1
          if Inv.ebx[bi] + 3 > Inv.shx[si]
            if Inv.ebx[bi] < Inv.shx[si] + 8
              if Inv.eby[bi] < Inv.shy[si] + 8
                if Inv.eby[bi] + 8 > Inv.shy[si]
                  Inv.sha[si] = 0
                  Inv.eba[bi] = 0
                  si = 60
                end
              end
            end
          end
        end
        si = si + 1
      end
    end
    bi = bi + 1
  end
  return 0
end

# ── Drawing helpers ──

#: (Integer px, Integer py) -> Integer
def draw_player(px, py)
  c_ship  = 0x00E430FF
  c_ship2 = 0x009E2FFF
  c_eng   = 0xFFA100FF
  Raylib.draw_rectangle(px + 4, py + 4, 32, 12, c_ship)
  Raylib.draw_rectangle(px + 17, py, 6, 8, c_ship2)
  Raylib.draw_rectangle(px, py + 8, 6, 8, c_ship)
  Raylib.draw_rectangle(px + 34, py + 8, 6, 8, c_ship)
  Raylib.draw_rectangle(px + 18, py + 16, 4, 3, c_eng)
  return 0
end

#: (Integer score, Integer lives, Integer wave, Integer combo) -> Integer
def draw_hud(score, lives, wave, combo)
  c_text  = 0xC8C8C8FF
  c_score = 0xFFCB00FF
  c_wave  = 0x66BFFFFF
  c_combo_text = 0xFDF900FF
  c_combo_bar  = 0xFFA100FF

  Raylib.draw_text("SCORE", 10, 10, 16, c_text)
  bw = score / 10
  if bw > 300
    bw = 300
  end
  Raylib.draw_rectangle(80, 12, bw, 12, c_score)
  i = 0
  while i < lives
    lx = 770 - i * 25
    Raylib.draw_rectangle(lx, 12, 12, 8, 0x00E430FF)
    i = i + 1
  end
  Raylib.draw_text("WAVE", 370, 10, 16, c_text)
  ww = wave * 8
  if ww > 80
    ww = 80
  end
  Raylib.draw_rectangle(420, 14, ww, 8, c_wave)
  if combo > 1
    Raylib.draw_text("COMBO", 10, 30, 14, c_combo_text)
    cw = combo * 6
    if cw > 120
      cw = 120
    end
    Raylib.draw_rectangle(70, 33, cw, 6, c_combo_bar)
  end
  return 0
end

# ── State functions ──

#: (Integer frame) -> Integer
def do_title(frame)
  update_stars
  Raylib.begin_drawing
  Raylib.clear_background(0x000000FF)
  draw_stars

  c_title = 0x00E430FF
  c_sub   = 0x505050FF
  c_flash = 0xFDF900FF
  c_text  = 0xC8C8C8FF

  Raylib.draw_text("KONPEITO INVADERS", 220, 150, 40, c_title)
  Raylib.draw_text("AOT Compiled with mruby + raylib", 220, 210, 20, c_sub)
  if (frame / 30) % 2 == 0
    Raylib.draw_text("PRESS ENTER TO START", 270, 350, 24, c_flash)
  end
  Raylib.draw_rectangle(300, 280, 12, 6, 0x009E2FFF)
  Raylib.draw_rectangle(303, 277, 6, 12, 0x009E2FFF)
  Raylib.draw_text("= 30 pts", 320, 278, 16, c_text)
  Raylib.draw_rectangle(300, 310, 20, 14, 0x66BFFFFF)
  Raylib.draw_text("= 20 pts", 330, 308, 16, c_text)
  Raylib.draw_rectangle(300, 340, 24, 14, 0xFFA100FF)
  Raylib.draw_text("= 10 pts", 335, 338, 16, c_text)
  Raylib.draw_text("Arrows: Move  |  Space: Shoot  |  ESC: Quit", 160, 500, 16, c_sub)
  Raylib.end_drawing
  return 0
end

#: (Integer score, Integer wave) -> Integer
def do_gameover(score, wave)
  update_stars
  update_particles
  Raylib.begin_drawing
  Raylib.clear_background(0x000000FF)
  draw_stars
  draw_particles

  c_go    = 0xE62937FF
  c_text  = 0xC8C8C8FF
  c_score = 0xFFCB00FF
  c_bar   = 0xFDF900FF

  Raylib.draw_text("GAME OVER", 290, 200, 40, c_go)
  Raylib.draw_text("PRESS R TO RESTART", 280, 350, 24, c_text)
  Raylib.draw_text("FINAL SCORE", 330, 280, 20, c_score)
  bw = score / 50
  if bw > 400
    bw = 400
  end
  Raylib.draw_rectangle(200, 310, bw, 16, c_bar)
  Raylib.end_drawing
  return 0
end

# ── Game management ──

#: () -> Integer
def reset_game
  Inv.gs[0] = 1
  Inv.gs[1] = 380
  Inv.gs[2] = 3
  Inv.gs[3] = 0
  Inv.gs[4] = 1
  Inv.gs[5] = 0
  Inv.gs[6] = 1
  Inv.gs[7] = 0
  Inv.gs[8] = 60
  Inv.gs[11] = 0
  init_enemies
  init_shields
  i = 0
  while i < 5
    Inv.ba[i] = 0
    i = i + 1
  end
  i = 0
  while i < 8
    Inv.eba[i] = 0
    i = i + 1
  end
  return 0
end

#: () -> Integer
def play_input
  px = Inv.gs[1]
  if Raylib.key_down?(263) != 0
    px = px - 5
  end
  if Raylib.key_down?(262) != 0
    px = px + 5
  end
  Inv.gs[1] = clamp(px, 5, 755)
  cd = Inv.gs[7]
  if cd > 0
    cd = cd - 1
  end
  if Raylib.key_pressed?(32) != 0
    if cd == 0
      fire_bullet(Inv.gs[1], 550)
      cd = 10
    end
  end
  Inv.gs[7] = cd
  return 0
end

#: () -> Integer
def play_collisions
  do_bullet_collisions
  collide_player_bullets_shields
  collide_enemy_bullets_shields
  return 0
end

#: () -> Integer
def play_damage
  inv = Inv.gs[8]
  if inv > 0
    Inv.gs[8] = inv - 1
    return 0
  end
  hit = collide_ebullets_player(Inv.gs[1], 550)
  if hit == 1
    Inv.gs[2] = Inv.gs[2] - 1
    Inv.gs[8] = 90
    Inv.gs[11] = 15
    new_seed = spawn_explosion(Inv.gs[10], Inv.gs[1] + 20, 558, 0xE62937FF)
    Inv.gs[10] = new_seed
  end
  return 0
end

#: () -> Integer
def play_check_death
  if Inv.gs[2] <= 0
    Inv.gs[0] = 2
    new_seed = spawn_explosion(Inv.gs[10], Inv.gs[1] + 20, 550, 0xE62937FF)
    Inv.gs[10] = new_seed
  end
  return 0
end

#: () -> Integer
def play_check_wave
  if count_alive == 0
    Inv.gs[4] = Inv.gs[4] + 1
    init_enemies
    init_shields
    Inv.gs[6] = 1
    i = 0
    while i < 5
      Inv.ba[i] = 0
      i = i + 1
    end
    i = 0
    while i < 8
      Inv.eba[i] = 0
      i = i + 1
    end
    new_seed = spawn_explosion(Inv.gs[10], 400, 300, 0xFFCB00FF)
    Inv.gs[10] = new_seed
  end
  return 0
end

#: () -> Integer
def play_shake
  shk = Inv.gs[11]
  if shk <= 0
    return 500500
  end
  Inv.gs[11] = shk - 1
  seed = pseudo_rand(Inv.gs[10])
  sox = (seed % 7) - 3
  seed = pseudo_rand(seed)
  soy = (seed % 7) - 3
  Inv.gs[10] = seed
  return (sox + 500) * 1000 + (soy + 500)
end

#: () -> Integer
def do_play
  play_input

  update_bullets
  update_ebullets
  update_stars
  update_particles

  result = update_enemies(Inv.gs[6], Inv.gs[4])
  Inv.gs[6] = result / 1000
  if result % 1000 == 1
    Inv.gs[2] = 0
  end

  Inv.gs[10] = enemy_shoot(Inv.gs[10])

  play_collisions
  play_damage
  play_check_death
  play_check_wave

  shake = play_shake
  sox = shake / 1000 - 500
  soy = shake % 1000 - 500

  frame = Inv.gs[9]
  Raylib.begin_drawing
  Raylib.clear_background(0x000000FF)
  draw_stars
  draw_enemies(frame)
  draw_shields
  draw_bullets
  draw_ebullets
  draw_particles

  inv = Inv.gs[8]
  if inv == 0
    draw_player(Inv.gs[1] + sox, 550 + soy)
  else
    if (frame % 4) < 2
      draw_player(Inv.gs[1] + sox, 550 + soy)
    end
  end

  draw_hud(Inv.gs[3], Inv.gs[2], Inv.gs[4], Inv.gs[5])
  Raylib.draw_line(0, 470, 800, 470, 0x505050FF)
  Raylib.end_drawing
  return 0
end

# ── Main ──

#: () -> Integer
def main
  Raylib.init_window(800, 600, "Konpeito Invaders - AOT Compiled mruby + raylib")
  Raylib.set_target_fps(60)

  Inv.gs[0] = 0
  Inv.gs[1] = 380
  Inv.gs[2] = 3
  Inv.gs[3] = 0
  Inv.gs[4] = 1
  Inv.gs[5] = 0
  Inv.gs[6] = 1
  Inv.gs[7] = 0
  Inv.gs[8] = 0
  Inv.gs[9] = 0
  Inv.gs[10] = 42
  Inv.gs[11] = 0

  seed = init_stars(42)
  Inv.gs[10] = seed
  init_enemies
  init_shields

  while Raylib.window_should_close == 0
    Inv.gs[9] = Inv.gs[9] + 1

    state = Inv.gs[0]
    if state == 0
      if Raylib.key_pressed?(257) != 0
        Inv.gs[0] = 1
      end
      do_title(Inv.gs[9])
    else
      if state == 1
        do_play
      else
        if Raylib.key_pressed?(82) != 0
          reset_game
        end
        do_gameover(Inv.gs[3], Inv.gs[4])
      end
    end
  end

  Raylib.close_window
  return 0
end

main
