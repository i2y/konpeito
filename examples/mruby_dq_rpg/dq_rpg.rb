# Konpeito Quest — Classic JRPG-style 2D RPG Demo
# rbs_inline: enabled
#
# Demonstrates: Scene management, Tilemap, Sprite animation, Turn-based battle,
#               Menu system, NPC dialog, Random encounters, Inventory, Level up
#
# Build:
#   konpeito build --target mruby --inline -o examples/mruby_dq_rpg/dq_rpg examples/mruby_dq_rpg/dq_rpg.rb
#
# Controls: Arrow/WASD — Move, Z/SPACE — Confirm, X — Cancel/Menu

require_relative "./game_framework"

# ── State Modules ──
# All mutable game state stored in fixed-size unboxed i64 arrays (LLVM globals).
# No GC pressure during gameplay.

# @rbs module G
# @rbs   @s: NativeArray[Integer, 64]
# @rbs   @map: NativeArray[Integer, 1200]
# @rbs   @hero: NativeArray[Integer, 32]
# @rbs   @inv: NativeArray[Integer, 40]
# @rbs   @bt: NativeArray[Integer, 48]
# @rbs   @npc: NativeArray[Integer, 160]
# @rbs   @flags: NativeArray[Integer, 32]
# @rbs end

# ── s[] index constants ──
# 0:scene 1:map_id 2:px 3:py 4:dir 5:anim 6:anim_timer 7:cooldown
# 8:cam_x100 9:cam_y100 10:steps 11:gold 12:cursor 13:cursor2
# 14:menu_mode 15:dlg_active 16:dlg_id 17:dlg_line 18:dlg_timer
# 19:enc_steps 20:msg_active 21:msg_timer 22:msg_id 23:title_cur
# 24:shop_cur 25:blink 26:map_w 27:map_h
# 28-31: reserved by game_framework (28:prev_scene 29:rng_seed 30:font_id+1 31:frame_counter)
# 32: Clay font ID
# Scenes: 0=title 1=town 2=overworld 3=cave 4=battle 5=menu 6=shop 7=inn 8=gameover 9=victory

# ── hero[] index constants ──
# 0:lv 1:hp 2:mhp 3:mp 4:mmp 5:atk 6:def 7:agi 8:exp
# 9:weapon 10:armor 11:status(0=ok,1=poison,2=dead)

# ── bt[] index constants ──
# 0:phase 1:en_count 2:e0_type 3:e0_hp 4:e0_alive
# 5:cursor 6:target 7:act_timer 8:msg_timer 9:exp_rew
# 10:gold_rew 11:dmg_show 12:dmg_timer 13:flee_ok
# 14:turn 15:sub_menu 16:hero_def 17:hero_acted
# bt phases: 0=start 1=cmd 2=hero_act 3=enemy_act 4=check 5=victory 6=defeat

# ── npc[] layout (stride=16) ──
# 0:active 1:x 2:y 3:dir 4:type 5:dlg_id

# ── inv[] layout (stride=2) ──
# slot i: inv[i*2]=item_id, inv[i*2+1]=qty
# Items: 0=empty 1=Herb(+30HP) 2=Potion(+60HP) 3=Antidote 4=MagicWater(+20MP)
# Weapons: 5=WoodSword(+5) 6=IronSword(+12) 7=SteelSword(+20)
# Armor: 8=Leather(+5) 9=ChainMail(+12) 10=SteelArmor(+20)
# Key: 11=DragonKey

# ════════════════════════════════════════════════════════════════════
# Section 1: Utility Functions
# ════════════════════════════════════════════════════════════════════

#: (Integer a, Integer b) -> Integer
def max_i(a, b)
  if a > b
    return a
  end
  return b
end

#: (Integer a, Integer b) -> Integer
def min_i(a, b)
  if a < b
    return a
  end
  return b
end

# ════════════════════════════════════════════════════════════════════
# Section 2: Data Tables (Monster, Item, EXP)
# ════════════════════════════════════════════════════════════════════

# Monster stats: 0=Slime 1=Bat 2=Goblin 3=Skeleton 4=Dragon(boss)
#: (Integer t) -> Integer
def mon_hp(t)
  if t == 0
    return 10
  end
  if t == 1
    return 14
  end
  if t == 2
    return 28
  end
  if t == 3
    return 45
  end
  if t == 4
    return 150
  end
  return 10
end

#: (Integer t) -> Integer
def mon_atk(t)
  if t == 0
    return 6
  end
  if t == 1
    return 9
  end
  if t == 2
    return 14
  end
  if t == 3
    return 22
  end
  if t == 4
    return 35
  end
  return 6
end

#: (Integer t) -> Integer
def mon_def(t)
  if t == 0
    return 3
  end
  if t == 1
    return 2
  end
  if t == 2
    return 8
  end
  if t == 3
    return 12
  end
  if t == 4
    return 22
  end
  return 3
end

#: (Integer t) -> Integer
def mon_agi(t)
  if t == 0
    return 4
  end
  if t == 1
    return 10
  end
  if t == 2
    return 6
  end
  if t == 3
    return 7
  end
  if t == 4
    return 12
  end
  return 4
end

#: (Integer t) -> Integer
def mon_exp(t)
  if t == 0
    return 3
  end
  if t == 1
    return 5
  end
  if t == 2
    return 12
  end
  if t == 3
    return 22
  end
  if t == 4
    return 300
  end
  return 3
end

#: (Integer t) -> Integer
def mon_gold(t)
  if t == 0
    return 4
  end
  if t == 1
    return 6
  end
  if t == 2
    return 16
  end
  if t == 3
    return 28
  end
  if t == 4
    return 500
  end
  return 4
end

# Draw monster name
#: (Integer x, Integer y, Integer t, Integer sz, Integer col) -> Integer
def draw_mon_name(x, y, t, sz, col)
  if t == 0
    fw_draw_txt("Slime", x, y, sz, col)
  end
  if t == 1
    fw_draw_txt("Bat", x, y, sz, col)
  end
  if t == 2
    fw_draw_txt("Goblin", x, y, sz, col)
  end
  if t == 3
    fw_draw_txt("Skeleton", x, y, sz, col)
  end
  if t == 4
    fw_draw_txt("Dragon", x, y, sz, col)
  end
  return 0
end

# Draw item name
#: (Integer x, Integer y, Integer id, Integer sz, Integer col) -> Integer
def draw_item_name(x, y, id, sz, col)
  if id == 1
    fw_draw_txt("Herb", x, y, sz, col)
  end
  if id == 2
    fw_draw_txt("Potion", x, y, sz, col)
  end
  if id == 3
    fw_draw_txt("Antidote", x, y, sz, col)
  end
  if id == 4
    fw_draw_txt("Magic Water", x, y, sz, col)
  end
  if id == 5
    fw_draw_txt("Wood Sword", x, y, sz, col)
  end
  if id == 6
    fw_draw_txt("Iron Sword", x, y, sz, col)
  end
  if id == 7
    fw_draw_txt("Steel Sword", x, y, sz, col)
  end
  if id == 8
    fw_draw_txt("Leather", x, y, sz, col)
  end
  if id == 9
    fw_draw_txt("Chain Mail", x, y, sz, col)
  end
  if id == 10
    fw_draw_txt("Steel Armor", x, y, sz, col)
  end
  if id == 11
    fw_draw_txt("Dragon Key", x, y, sz, col)
  end
  return 0
end

# Item price (buy)
#: (Integer id) -> Integer
def item_price(id)
  if id == 1
    return 8
  end
  if id == 2
    return 24
  end
  if id == 3
    return 10
  end
  if id == 4
    return 20
  end
  if id == 5
    return 30
  end
  if id == 6
    return 150
  end
  if id == 7
    return 500
  end
  if id == 8
    return 40
  end
  if id == 9
    return 200
  end
  if id == 10
    return 600
  end
  return 0
end

# Weapon ATK bonus
#: (Integer id) -> Integer
def weapon_atk(id)
  if id == 5
    return 5
  end
  if id == 6
    return 12
  end
  if id == 7
    return 22
  end
  return 0
end

# Armor DEF bonus
#: (Integer id) -> Integer
def armor_def(id)
  if id == 8
    return 5
  end
  if id == 9
    return 12
  end
  if id == 10
    return 22
  end
  return 0
end

# Hero base stats by level
#: (Integer lv) -> Integer
def hero_base_mhp(lv)
  return 25 + lv * 8
end

#: (Integer lv) -> Integer
def hero_base_mmp(lv)
  return lv * 4
end

#: (Integer lv) -> Integer
def hero_base_atk(lv)
  return 4 + lv * 3
end

#: (Integer lv) -> Integer
def hero_base_def(lv)
  return 2 + lv * 2
end

#: (Integer lv) -> Integer
def hero_base_agi(lv)
  return 3 + lv * 2
end

# EXP required to reach level lv
#: (Integer lv) -> Integer
def exp_for_level(lv)
  if lv <= 1
    return 0
  end
  return (lv - 1) * (lv - 1) * 8
end

# Get hero total ATK (base + weapon)
#: () -> Integer
def hero_total_atk
  return G.hero[5] + weapon_atk(G.hero[9])
end

# Get hero total DEF (base + armor)
#: () -> Integer
def hero_total_def
  return G.hero[6] + armor_def(G.hero[10])
end

# ════════════════════════════════════════════════════════════════════
# Section 3: Inventory Management
# ════════════════════════════════════════════════════════════════════

#: (Integer id, Integer qty) -> Integer
def add_item(id, qty)
  # Try to stack with existing
  i = 0
  while i < 20
    if G.inv[i * 2] == id
      G.inv[i * 2 + 1] = G.inv[i * 2 + 1] + qty
      return 1
    end
    i = i + 1
  end
  # Find empty slot
  i = 0
  while i < 20
    if G.inv[i * 2] == 0
      G.inv[i * 2] = id
      G.inv[i * 2 + 1] = qty
      return 1
    end
    i = i + 1
  end
  return 0
end

#: (Integer slot) -> Integer
def remove_item(slot)
  G.inv[slot * 2 + 1] = G.inv[slot * 2 + 1] - 1
  if G.inv[slot * 2 + 1] <= 0
    G.inv[slot * 2] = 0
    G.inv[slot * 2 + 1] = 0
  end
  return 0
end

# Count filled inventory slots
#: () -> Integer
def inv_count
  c = 0
  i = 0
  while i < 20
    if G.inv[i * 2] != 0
      c = c + 1
    end
    i = i + 1
  end
  return c
end

# Get nth non-empty slot index
#: (Integer n) -> Integer
def inv_slot_at(n)
  c = 0
  i = 0
  while i < 20
    if G.inv[i * 2] != 0
      if c == n
        return i
      end
      c = c + 1
    end
    i = i + 1
  end
  return -1
end

# ════════════════════════════════════════════════════════════════════
# Section 4: Tile & Sprite Drawing
# ════════════════════════════════════════════════════════════════════

#: (Integer px, Integer py, Integer tile, Integer af, Integer mid) -> Integer
def draw_tile(px, py, tile, af, mid)
  # mid: map_id (0=town, 1=overworld, 2=cave)
  if tile == 0  # Grass
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(34, 139, 34, 255))
  end
  if tile == 1  # Water
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(30, 100, 200, 255))
    if af % 2 == 0
      Raylib.draw_rectangle(px + 4, py + 10, 10, 2, fw_rgba(60, 140, 230, 255))
      Raylib.draw_rectangle(px + 18, py + 20, 8, 2, fw_rgba(60, 140, 230, 255))
    else
      Raylib.draw_rectangle(px + 8, py + 14, 10, 2, fw_rgba(60, 140, 230, 255))
      Raylib.draw_rectangle(px + 14, py + 24, 8, 2, fw_rgba(60, 140, 230, 255))
    end
  end
  if tile == 2  # Tree / Wall
    if mid == 2  # Cave wall
      Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(50, 40, 35, 255))
      Raylib.draw_rectangle(px + 2, py + 2, 4, 4, fw_rgba(65, 55, 45, 255))
      Raylib.draw_rectangle(px + 20, py + 14, 6, 6, fw_rgba(65, 55, 45, 255))
    else
      Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(34, 139, 34, 255))
      Raylib.draw_rectangle(px + 13, py + 16, 6, 14, fw_rgba(101, 67, 33, 255))
      Raylib.draw_circle(px + 16, py + 12, 10.0, fw_rgba(0, 100, 0, 255))
    end
  end
  if tile == 3  # Path
    if mid == 2
      Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(80, 70, 60, 255))
    else
      Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(194, 178, 128, 255))
    end
  end
  if tile == 4  # House
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(34, 139, 34, 255))
    Raylib.draw_rectangle(px + 2, py + 12, 28, 18, fw_rgba(180, 120, 60, 255))
    Raylib.draw_rectangle(px + 2, py + 4, 28, 10, fw_rgba(160, 40, 40, 255))
    Raylib.draw_rectangle(px + 12, py + 20, 8, 10, fw_rgba(80, 50, 20, 255))
  end
  if tile == 5  # Sign / NPC marker
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(194, 178, 128, 255))
  end
  if tile == 6  # Flower
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(34, 139, 34, 255))
    Raylib.draw_circle(px + 10, py + 14, 3.0, fw_rgba(220, 50, 50, 255))
    Raylib.draw_circle(px + 22, py + 20, 3.0, fw_rgba(255, 220, 50, 255))
  end
  if tile == 7  # Rock
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(34, 139, 34, 255))
    Raylib.draw_circle(px + 16, py + 18, 10.0, fw_rgba(130, 130, 130, 255))
    Raylib.draw_circle(px + 14, py + 16, 8.0, fw_rgba(90, 90, 90, 255))
  end
  if tile == 8  # Sand
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(210, 190, 140, 255))
  end
  if tile == 9  # Chest
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(80, 70, 60, 255))
    Raylib.draw_rectangle(px + 8, py + 12, 16, 14, fw_rgba(180, 140, 40, 255))
    Raylib.draw_rectangle(px + 8, py + 12, 16, 3, fw_rgba(200, 160, 60, 255))
    Raylib.draw_rectangle(px + 14, py + 18, 4, 4, fw_rgba(120, 80, 20, 255))
  end
  if tile == 10  # Stairs down
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(80, 70, 60, 255))
    Raylib.draw_rectangle(px + 4, py + 4, 24, 6, fw_rgba(60, 50, 40, 255))
    Raylib.draw_rectangle(px + 8, py + 12, 20, 6, fw_rgba(60, 50, 40, 255))
    Raylib.draw_rectangle(px + 12, py + 20, 16, 6, fw_rgba(60, 50, 40, 255))
  end
  if tile == 11  # Bridge
    Raylib.draw_rectangle(px, py, 32, 32, fw_rgba(30, 100, 200, 255))
    Raylib.draw_rectangle(px + 4, py + 8, 24, 16, fw_rgba(139, 90, 43, 255))
    Raylib.draw_rectangle(px + 6, py + 10, 20, 12, fw_rgba(160, 110, 60, 255))
  end
  return 0
end

# Draw hero sprite — direction-aware rendering
#: (Integer px, Integer py, Integer dir, Integer walk) -> Integer
def draw_hero(px, py, dir, walk)
  c_body = fw_rgba(50, 80, 200, 255)
  c_skin = fw_rgba(255, 200, 150, 255)
  c_hair = fw_rgba(60, 30, 10, 255)
  c_cape = fw_rgba(180, 40, 40, 255)
  c_eye = fw_rgba(30, 30, 30, 255)
  c_boot = fw_rgba(80, 50, 20, 255)

  leg_off = 0
  if walk % 4 == 1
    leg_off = -2
  end
  if walk % 4 == 3
    leg_off = 2
  end

  if dir == 0  # Down — facing camera
    # Cape behind body
    Raylib.draw_rectangle(px + 5, py + 13, 22, 12, c_cape)
    # Body
    Raylib.draw_rectangle(px + 8, py + 11, 16, 17, c_body)
    # Head (skin)
    Raylib.draw_circle(px + 16, py + 8, 8.0, c_skin)
    # Hair on top
    Raylib.draw_rectangle(px + 8, py + 0, 16, 7, c_hair)
    Raylib.draw_circle(px + 16, py + 3, 7.0, c_hair)
    # Face visible — two eyes
    Raylib.draw_rectangle(px + 11, py + 7, 3, 3, c_eye)
    Raylib.draw_rectangle(px + 18, py + 7, 3, 3, c_eye)
    # Mouth hint
    Raylib.draw_rectangle(px + 14, py + 12, 4, 1, fw_rgba(200, 140, 110, 255))
    # Legs
    Raylib.draw_rectangle(px + 10 + leg_off, py + 28, 5, 4, c_boot)
    Raylib.draw_rectangle(px + 17 - leg_off, py + 28, 5, 4, c_boot)
  end

  if dir == 1  # Up — back to camera
    # Body
    Raylib.draw_rectangle(px + 8, py + 11, 16, 17, c_body)
    # Cape visible in front of body
    Raylib.draw_rectangle(px + 5, py + 13, 22, 14, c_cape)
    Raylib.draw_rectangle(px + 7, py + 15, 18, 10, c_cape)
    # Back of head (all hair, no face)
    Raylib.draw_circle(px + 16, py + 8, 8.0, c_hair)
    Raylib.draw_rectangle(px + 8, py + 0, 16, 10, c_hair)
    # Legs
    Raylib.draw_rectangle(px + 10 + leg_off, py + 28, 5, 4, c_boot)
    Raylib.draw_rectangle(px + 17 - leg_off, py + 28, 5, 4, c_boot)
  end

  if dir == 2  # Left — side profile facing left
    # Cape trails to right
    Raylib.draw_rectangle(px + 14, py + 13, 14, 12, c_cape)
    # Body shifted left
    Raylib.draw_rectangle(px + 6, py + 11, 16, 17, c_body)
    # Head shifted left
    Raylib.draw_circle(px + 14, py + 8, 8.0, c_skin)
    # Hair (covers right side of head)
    Raylib.draw_rectangle(px + 14, py + 0, 8, 8, c_hair)
    Raylib.draw_circle(px + 14, py + 3, 7.0, c_hair)
    # One eye on left side
    Raylib.draw_rectangle(px + 9, py + 7, 3, 3, c_eye)
    # Legs
    Raylib.draw_rectangle(px + 8 + leg_off, py + 28, 5, 4, c_boot)
    Raylib.draw_rectangle(px + 15 - leg_off, py + 28, 5, 4, c_boot)
  end

  if dir == 3  # Right — side profile facing right
    # Cape trails to left
    Raylib.draw_rectangle(px + 4, py + 13, 14, 12, c_cape)
    # Body shifted right
    Raylib.draw_rectangle(px + 10, py + 11, 16, 17, c_body)
    # Head shifted right
    Raylib.draw_circle(px + 18, py + 8, 8.0, c_skin)
    # Hair (covers left side of head)
    Raylib.draw_rectangle(px + 10, py + 0, 8, 8, c_hair)
    Raylib.draw_circle(px + 18, py + 3, 7.0, c_hair)
    # One eye on right side
    Raylib.draw_rectangle(px + 20, py + 7, 3, 3, c_eye)
    # Legs
    Raylib.draw_rectangle(px + 12 + leg_off, py + 28, 5, 4, c_boot)
    Raylib.draw_rectangle(px + 19 - leg_off, py + 28, 5, 4, c_boot)
  end

  return 0
end

# Draw NPC sprite
#: (Integer px, Integer py, Integer ntype, Integer dir) -> Integer
def draw_npc(px, py, ntype, dir)
  # 0=villager(green) 1=merchant(orange) 2=innkeeper(purple) 3=elder(gold) 4=guard(gray)
  c_body = fw_rgba(40, 160, 40, 255)
  if ntype == 1
    c_body = fw_rgba(200, 140, 40, 255)
  end
  if ntype == 2
    c_body = fw_rgba(140, 40, 180, 255)
  end
  if ntype == 3
    c_body = fw_rgba(200, 180, 60, 255)
  end
  if ntype == 4
    c_body = fw_rgba(120, 120, 140, 255)
  end

  c_skin = fw_rgba(255, 210, 170, 255)
  c_hair = fw_rgba(80, 50, 20, 255)

  Raylib.draw_rectangle(px + 8, py + 10, 16, 18, c_body)
  Raylib.draw_circle(px + 16, py + 8, 7.0, c_skin)
  Raylib.draw_circle(px + 16, py + 4, 6.0, c_hair)
  Raylib.draw_rectangle(px + 10, py + 28, 5, 4, c_hair)
  Raylib.draw_rectangle(px + 17, py + 28, 5, 4, c_hair)

  if dir == 0
    Raylib.draw_rectangle(px + 13, py + 8, 2, 2, c_hair)
    Raylib.draw_rectangle(px + 17, py + 8, 2, 2, c_hair)
  end
  if dir == 1
    Raylib.draw_rectangle(px + 8, py + 1, 16, 5, c_hair)
  end
  return 0
end

# Draw monster in battle
#: (Integer cx, Integer cy, Integer mtype) -> Integer
def draw_monster(cx, cy, mtype)
  if mtype == 0  # Slime - blue blob
    Raylib.draw_circle(cx, cy, 30.0, fw_rgba(60, 120, 220, 255))
    Raylib.draw_circle(cx, cy - 4, 26.0, fw_rgba(80, 150, 240, 255))
    Raylib.draw_rectangle(cx - 10, cy - 10, 4, 4, fw_rgba(255, 255, 255, 255))
    Raylib.draw_rectangle(cx + 6, cy - 10, 4, 4, fw_rgba(255, 255, 255, 255))
    Raylib.draw_rectangle(cx - 8, cy - 8, 2, 2, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx + 8, cy - 8, 2, 2, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx - 4, cy + 2, 8, 3, fw_rgba(20, 20, 20, 255))
  end
  if mtype == 1  # Bat - brown with wings
    Raylib.draw_rectangle(cx - 6, cy - 4, 12, 12, fw_rgba(100, 60, 30, 255))
    Raylib.draw_rectangle(cx - 30, cy - 10, 24, 14, fw_rgba(80, 50, 25, 255))
    Raylib.draw_rectangle(cx + 6, cy - 10, 24, 14, fw_rgba(80, 50, 25, 255))
    Raylib.draw_rectangle(cx - 4, cy - 2, 2, 2, fw_rgba(255, 50, 50, 255))
    Raylib.draw_rectangle(cx + 2, cy - 2, 2, 2, fw_rgba(255, 50, 50, 255))
    Raylib.draw_rectangle(cx - 2, cy + 4, 4, 3, fw_rgba(255, 255, 255, 255))
  end
  if mtype == 2  # Goblin - green humanoid
    Raylib.draw_rectangle(cx - 12, cy - 8, 24, 30, fw_rgba(60, 140, 40, 255))
    Raylib.draw_circle(cx, cy - 16, 14.0, fw_rgba(70, 160, 50, 255))
    Raylib.draw_rectangle(cx - 8, cy - 20, 4, 4, fw_rgba(255, 255, 255, 255))
    Raylib.draw_rectangle(cx + 4, cy - 20, 4, 4, fw_rgba(255, 255, 255, 255))
    Raylib.draw_rectangle(cx - 6, cy - 18, 2, 2, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx + 6, cy - 18, 2, 2, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx - 4, cy - 10, 8, 3, fw_rgba(20, 20, 20, 255))
    # Club
    Raylib.draw_rectangle(cx + 14, cy - 10, 6, 20, fw_rgba(120, 80, 30, 255))
  end
  if mtype == 3  # Skeleton - white bones
    Raylib.draw_rectangle(cx - 8, cy - 6, 16, 28, fw_rgba(220, 220, 210, 255))
    Raylib.draw_circle(cx, cy - 14, 12.0, fw_rgba(240, 240, 230, 255))
    Raylib.draw_rectangle(cx - 6, cy - 18, 4, 5, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx + 2, cy - 18, 4, 5, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx - 4, cy - 10, 8, 2, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx - 12, cy - 2, 6, 3, fw_rgba(220, 220, 210, 255))
    Raylib.draw_rectangle(cx + 6, cy - 2, 6, 3, fw_rgba(220, 220, 210, 255))
    # Sword
    Raylib.draw_rectangle(cx + 12, cy - 20, 3, 30, fw_rgba(180, 180, 200, 255))
    Raylib.draw_rectangle(cx + 8, cy - 6, 10, 3, fw_rgba(180, 180, 200, 255))
  end
  if mtype == 4  # Dragon - large red beast
    # Body
    Raylib.draw_rectangle(cx - 30, cy - 10, 60, 40, fw_rgba(180, 40, 30, 255))
    Raylib.draw_rectangle(cx - 26, cy - 6, 52, 32, fw_rgba(200, 60, 40, 255))
    # Head
    Raylib.draw_circle(cx, cy - 24, 20.0, fw_rgba(190, 50, 35, 255))
    # Horns
    Raylib.draw_rectangle(cx - 14, cy - 44, 4, 16, fw_rgba(160, 140, 60, 255))
    Raylib.draw_rectangle(cx + 10, cy - 44, 4, 16, fw_rgba(160, 140, 60, 255))
    # Eyes
    Raylib.draw_rectangle(cx - 10, cy - 28, 6, 5, fw_rgba(255, 220, 50, 255))
    Raylib.draw_rectangle(cx + 4, cy - 28, 6, 5, fw_rgba(255, 220, 50, 255))
    Raylib.draw_rectangle(cx - 8, cy - 26, 3, 3, fw_rgba(20, 20, 20, 255))
    Raylib.draw_rectangle(cx + 7, cy - 26, 3, 3, fw_rgba(20, 20, 20, 255))
    # Mouth
    Raylib.draw_rectangle(cx - 8, cy - 16, 16, 4, fw_rgba(120, 20, 20, 255))
    # Wings
    Raylib.draw_rectangle(cx - 50, cy - 30, 24, 30, fw_rgba(170, 35, 25, 255))
    Raylib.draw_rectangle(cx + 26, cy - 30, 24, 30, fw_rgba(170, 35, 25, 255))
    # Belly
    Raylib.draw_rectangle(cx - 16, cy + 6, 32, 16, fw_rgba(220, 180, 100, 255))
  end
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 5: Map Generation
# ════════════════════════════════════════════════════════════════════

# Town: 20x15, single screen (640x480)
#: () -> Integer
def generate_town
  G.s[26] = 20
  G.s[27] = 15
  w = 20
  i = 0
  while i < 300
    G.map[i] = 0
    i = i + 1
  end
  # Border trees
  x = 0
  while x < w
    G.map[x] = 2
    G.map[14 * w + x] = 2
    x = x + 1
  end
  y = 0
  while y < 15
    G.map[y * w] = 2
    G.map[y * w + 19] = 2
    y = y + 1
  end
  # Stone paths
  x = 1
  while x < 19
    G.map[7 * w + x] = 3
    x = x + 1
  end
  y = 1
  while y < 14
    G.map[y * w + 10] = 3
    y = y + 1
  end
  # Houses
  G.map[2 * w + 3] = 4
  G.map[2 * w + 4] = 4
  G.map[3 * w + 3] = 4
  G.map[3 * w + 4] = 4
  G.map[2 * w + 15] = 4
  G.map[2 * w + 16] = 4
  G.map[3 * w + 15] = 4
  G.map[3 * w + 16] = 4
  G.map[10 * w + 3] = 4
  G.map[10 * w + 4] = 4
  G.map[11 * w + 3] = 4
  G.map[11 * w + 4] = 4
  # Fountain
  G.map[6 * w + 9] = 1
  G.map[6 * w + 10] = 1
  G.map[6 * w + 11] = 1
  G.map[8 * w + 9] = 1
  G.map[8 * w + 10] = 1
  G.map[8 * w + 11] = 1
  # Flowers
  G.map[5 * w + 6] = 6
  G.map[5 * w + 14] = 6
  G.map[9 * w + 6] = 6
  G.map[9 * w + 14] = 6
  G.map[12 * w + 8] = 6
  G.map[12 * w + 12] = 6
  # Exit south
  G.map[14 * w + 9] = 3
  G.map[14 * w + 10] = 3
  # NPCs: Elder
  G.npc[0] = 1
  G.npc[1] = 9
  G.npc[2] = 5
  G.npc[3] = 0
  G.npc[4] = 3
  G.npc[5] = 0
  # Merchant
  G.npc[16] = 1
  G.npc[17] = 14
  G.npc[18] = 4
  G.npc[19] = 2
  G.npc[20] = 1
  G.npc[21] = 1
  # Innkeeper
  G.npc[32] = 1
  G.npc[33] = 5
  G.npc[34] = 11
  G.npc[35] = 3
  G.npc[36] = 2
  G.npc[37] = 2
  # Guard
  G.npc[48] = 1
  G.npc[49] = 11
  G.npc[50] = 13
  G.npc[51] = 0
  G.npc[52] = 4
  G.npc[53] = 3
  # Villager
  G.npc[64] = 1
  G.npc[65] = 7
  G.npc[66] = 9
  G.npc[67] = 0
  G.npc[68] = 0
  G.npc[69] = 4
  return 0
end

# Overworld: 30x22
#: () -> Integer
def generate_overworld
  G.s[26] = 30
  G.s[27] = 22
  w = 30
  total = 30 * 22
  i = 0
  while i < total
    G.map[i] = 0
    i = i + 1
  end
  # Border
  x = 0
  while x < w
    G.map[x] = 2
    G.map[21 * w + x] = 2
    x = x + 1
  end
  y = 0
  while y < 22
    G.map[y * w] = 2
    G.map[y * w + 29] = 2
    y = y + 1
  end
  # Path: north to south-east
  y = 1
  while y < 14
    G.map[y * w + 15] = 3
    y = y + 1
  end
  x = 15
  while x < 27
    G.map[13 * w + x] = 3
    x = x + 1
  end
  y = 13
  while y < 20
    G.map[y * w + 26] = 3
    y = y + 1
  end
  # Town entrance
  G.map[1 * w + 14] = 3
  G.map[1 * w + 15] = 3
  G.map[1 * w + 16] = 3
  # Cave entrance
  G.map[19 * w + 27] = 10
  G.map[19 * w + 28] = 10
  # Random trees
  G.s[29] = 54321
  i = 0
  while i < 50
    tx = fw_rand(28) + 1
    ty = fw_rand(20) + 1
    if G.map[ty * w + tx] == 0
      G.map[ty * w + tx] = 2
    end
    i = i + 1
  end
  # Random rocks
  G.s[29] = 11111
  i = 0
  while i < 15
    tx = fw_rand(28) + 1
    ty = fw_rand(20) + 1
    if G.map[ty * w + tx] == 0
      G.map[ty * w + tx] = 7
    end
    i = i + 1
  end
  # Flowers
  G.s[29] = 77777
  i = 0
  while i < 20
    tx = fw_rand(28) + 1
    ty = fw_rand(20) + 1
    if G.map[ty * w + tx] == 0
      G.map[ty * w + tx] = 6
    end
    i = i + 1
  end
  # Water lake
  ly = 6
  while ly < 10
    lx = 4
    while lx < 10
      G.map[ly * w + lx] = 1
      lx = lx + 1
    end
    ly = ly + 1
  end
  G.map[8 * w + 5] = 11
  G.map[8 * w + 6] = 11
  # Clear NPCs
  ni = 0
  while ni < 10
    G.npc[ni * 16] = 0
    ni = ni + 1
  end
  return 0
end

# Cave: 20x15
#: () -> Integer
def generate_cave
  G.s[26] = 20
  G.s[27] = 15
  w = 20
  i = 0
  while i < 300
    G.map[i] = 2
    i = i + 1
  end
  # Corridors
  y = 6
  while y < 9
    G.map[y * w + 1] = 3
    G.map[y * w + 2] = 3
    y = y + 1
  end
  x = 2
  while x < 18
    G.map[7 * w + x] = 3
    x = x + 1
  end
  # Side rooms
  y = 3
  while y < 7
    G.map[y * w + 5] = 3
    G.map[y * w + 6] = 3
    y = y + 1
  end
  y = 8
  while y < 12
    G.map[y * w + 10] = 3
    G.map[y * w + 11] = 3
    y = y + 1
  end
  # Boss area
  y = 4
  while y < 11
    G.map[y * w + 16] = 3
    G.map[y * w + 17] = 3
    y = y + 1
  end
  by = 4
  while by < 7
    bx = 14
    while bx < 18
      G.map[by * w + bx] = 3
      bx = bx + 1
    end
    by = by + 1
  end
  # Chests
  G.map[4 * w + 6] = 9
  G.map[10 * w + 11] = 9
  # Stairs (exit)
  G.map[7 * w + 1] = 10
  # Clear NPCs
  ni = 0
  while ni < 10
    G.npc[ni * 16] = 0
    ni = ni + 1
  end
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 6: Collision & Transitions
# ════════════════════════════════════════════════════════════════════

#: (Integer tx, Integer ty) -> Integer
def is_walkable(tx, ty)
  mw = G.s[26]
  mh = G.s[27]
  if tx < 0
    return 0
  end
  if ty < 0
    return 0
  end
  if tx >= mw
    return 0
  end
  if ty >= mh
    return 0
  end
  tile = G.map[ty * mw + tx]
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

#: () -> Integer
def check_transitions
  mid = G.s[1]
  px = G.s[2]
  py = G.s[3]
  if mid == 0
    if py >= 14
      if px >= 9
        if px <= 10
          generate_overworld
          G.s[0] = 2
          G.s[1] = 1
          G.s[2] = 15
          G.s[3] = 2
          G.s[8] = 15 * 3200
          G.s[9] = 2 * 3200
          return 1
        end
      end
    end
  end
  if mid == 1
    if py <= 1
      if px >= 14
        if px <= 16
          generate_town
          G.s[0] = 1
          G.s[1] = 0
          G.s[2] = 10
          G.s[3] = 13
          G.s[8] = 10 * 3200
          G.s[9] = 13 * 3200
          return 1
        end
      end
    end
    tile = G.map[py * 30 + px]
    if tile == 10
      generate_cave
      G.s[0] = 3
      G.s[1] = 2
      G.s[2] = 2
      G.s[3] = 7
      G.s[8] = 2 * 3200
      G.s[9] = 7 * 3200
      return 1
    end
  end
  if mid == 2
    tile = G.map[py * 20 + px]
    if tile == 10
      if px <= 2
        generate_overworld
        G.s[0] = 2
        G.s[1] = 1
        G.s[2] = 25
        G.s[3] = 18
        G.s[8] = 25 * 3200
        G.s[9] = 18 * 3200
        return 1
      end
    end
  end
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 7: Game Initialization
# ════════════════════════════════════════════════════════════════════

#: () -> Integer
def init_hero
  G.hero[0] = 1
  G.hero[1] = 33
  G.hero[2] = 33
  G.hero[3] = 4
  G.hero[4] = 4
  G.hero[5] = 7
  G.hero[6] = 4
  G.hero[7] = 5
  G.hero[8] = 0
  G.hero[9] = 0
  G.hero[10] = 0
  G.hero[11] = 0
  return 0
end

#: () -> Integer
def init_game
  init_hero
  G.s[0] = 1
  G.s[1] = 0
  G.s[2] = 10
  G.s[3] = 8
  G.s[4] = 0
  G.s[5] = 0
  G.s[6] = 0
  G.s[7] = 0
  G.s[8] = 10 * 3200
  G.s[9] = 8 * 3200
  G.s[10] = 0
  G.s[11] = 50
  G.s[15] = 0
  G.s[19] = 8
  G.s[20] = 0
  i = 0
  while i < 40
    G.inv[i] = 0
    i = i + 1
  end
  add_item(1, 3)
  i = 0
  while i < 32
    G.flags[i] = 0
    i = i + 1
  end
  generate_town
  return 0
end

#: () -> Integer
def check_level_up
  lv = G.hero[0]
  if lv >= 10
    return 0
  end
  needed = exp_for_level(lv + 1)
  if G.hero[8] >= needed
    G.hero[0] = lv + 1
    nlv = lv + 1
    G.hero[2] = hero_base_mhp(nlv)
    G.hero[4] = hero_base_mmp(nlv)
    G.hero[5] = hero_base_atk(nlv)
    G.hero[6] = hero_base_def(nlv)
    G.hero[7] = hero_base_agi(nlv)
    G.hero[1] = G.hero[2]
    G.hero[3] = G.hero[4]
    return 1
  end
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 8: Dialog System
# ════════════════════════════════════════════════════════════════════

#: (Integer id, Integer line) -> Integer
def draw_dialog_text(id, line)
  cx = 56
  cy1 = 370
  cy2 = 394
  cw = Raylib.color_white
  cg = Raylib.color_lightgray
  if id == 0
    if line == 0
      fw_draw_txt("Welcome, brave hero!", cx, cy1, 18, cw)
      fw_draw_txt("A dragon threatens our land.", cx, cy2, 16, cg)
    end
    if line == 1
      fw_draw_txt("Head east through the field", cx, cy1, 18, cw)
      fw_draw_txt("to the cave. Defeat it!", cx, cy2, 16, cg)
    end
  end
  if id == 1
    if line == 0
      fw_draw_txt("Welcome to my shop!", cx, cy1, 18, cw)
      fw_draw_txt("[Enter] Browse wares.", cx, cy2, 16, cg)
    end
  end
  if id == 2
    if line == 0
      fw_draw_txt("Rest for 10 gold?", cx, cy1, 18, cw)
      fw_draw_txt("[Enter] Rest and heal.", cx, cy2, 16, cg)
    end
  end
  if id == 3
    if line == 0
      fw_draw_txt("The cave lies east beyond", cx, cy1, 18, cw)
      fw_draw_txt("the field. Be careful!", cx, cy2, 16, cg)
    end
  end
  if id == 4
    if line == 0
      fw_draw_txt("Monsters appear more often", cx, cy1, 18, cw)
      fw_draw_txt("lately... Stay safe!", cx, cy2, 16, cg)
    end
  end
  if id == 10
    if line == 0
      fw_draw_txt("Found a Herb!", cx, cy1, 18, Raylib.color_gold)
    end
  end
  if id == 11
    if line == 0
      fw_draw_txt("Found an Iron Sword!", cx, cy1, 18, Raylib.color_gold)
    end
  end
  if id == 20
    if line == 0
      fw_draw_txt("Have a good rest...", cx, cy1, 18, cw)
      fw_draw_txt("HP and MP fully restored!", cx, cy2, 16, Raylib.color_lime)
    end
  end
  if id == 21
    if line == 0
      fw_draw_txt("Not enough gold.", cx, cy1, 18, cw)
    end
  end
  if id == 30
    if line == 0
      fw_draw_txt("The dragon has been slain!", cx, cy1, 18, Raylib.color_gold)
      fw_draw_txt("Peace returns to the land!", cx, cy2, 16, cw)
    end
  end
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 9: Field Scene (Input & Update)
# ════════════════════════════════════════════════════════════════════

#: (Integer tx, Integer ty) -> Integer
def find_npc_at(tx, ty)
  ni = 0
  while ni < 10
    base = ni * 16
    if G.npc[base] == 1
      if G.npc[base + 1] == tx
        if G.npc[base + 2] == ty
          return ni
        end
      end
    end
    ni = ni + 1
  end
  return -1
end

# Start random encounter
#: () -> Integer
def start_battle
  G.s[28] = G.s[0]
  G.s[0] = 4
  G.bt[0] = 0  # phase=start
  G.bt[1] = 1  # 1 enemy
  # Pick enemy type based on map
  mid = G.s[1]
  G.s[29] = G.s[10] * 13 + G.s[2] * 7
  etype = 0
  if mid == 1  # overworld
    roll = fw_rand(100)
    if roll < 50
      etype = 0  # Slime
    end
    if roll >= 50
      if roll < 80
        etype = 1  # Bat
      else
        etype = 2  # Goblin
      end
    end
  end
  if mid == 2  # cave
    roll = fw_rand(100)
    if roll < 30
      etype = 2  # Goblin
    end
    if roll >= 30
      if roll < 70
        etype = 3  # Skeleton
      else
        etype = 2  # Goblin
      end
    end
  end
  G.bt[2] = etype
  G.bt[3] = mon_hp(etype)
  G.bt[4] = 1  # alive
  G.bt[5] = 0  # cursor
  G.bt[7] = 0  # act_timer
  G.bt[8] = 60 # msg_timer (show "appeared" msg)
  G.bt[9] = mon_exp(etype)
  G.bt[10] = mon_gold(etype)
  G.bt[11] = 0  # dmg_show
  G.bt[12] = 0  # dmg_timer
  G.bt[13] = 0  # flee
  G.bt[14] = 0  # turn
  G.bt[15] = 0  # sub_menu
  G.bt[16] = 0  # hero_def
  G.bt[17] = 0  # hero_acted
  return 0
end

# Start boss battle
#: () -> Integer
def start_boss_battle
  G.s[28] = G.s[0]
  G.s[0] = 4
  G.bt[0] = 0
  G.bt[1] = 1
  G.bt[2] = 4  # Dragon
  G.bt[3] = mon_hp(4)
  G.bt[4] = 1
  G.bt[5] = 0
  G.bt[7] = 0
  G.bt[8] = 60
  G.bt[9] = mon_exp(4)
  G.bt[10] = mon_gold(4)
  G.bt[11] = 0
  G.bt[12] = 0
  G.bt[13] = 0
  G.bt[14] = 0
  G.bt[15] = 0
  G.bt[16] = 0
  G.bt[17] = 0
  return 0
end

#: () -> Integer
def update_field
  if G.s[15] == 1
    if Raylib.key_pressed?(Raylib.key_enter) != 0
      dlg_id = G.s[16]
      dlg_line = G.s[17]
      if dlg_id == 1
        G.s[15] = 0
        G.s[28] = G.s[0]
        G.s[0] = 6
        G.s[24] = 0
        return 0
      end
      if dlg_id == 2
        if G.s[11] >= 10
          G.s[11] = G.s[11] - 10
          G.hero[1] = G.hero[2]
          G.hero[3] = G.hero[4]
          G.s[16] = 20
          G.s[17] = 0
        else
          G.s[16] = 21
          G.s[17] = 0
        end
        return 0
      end
      if dlg_id == 20
        G.s[15] = 0
        return 0
      end
      if dlg_id == 21
        G.s[15] = 0
        return 0
      end
      if dlg_id == 10
        G.s[15] = 0
        return 0
      end
      if dlg_id == 11
        G.s[15] = 0
        return 0
      end
      if dlg_id == 30
        G.s[15] = 0
        G.s[0] = 9
        return 0
      end
      if dlg_id == 0
        if dlg_line < 1
          G.s[17] = dlg_line + 1
          return 0
        end
      end
      G.s[15] = 0
      return 0
    end
    if Raylib.key_pressed?(Raylib.key_space) != 0
      G.s[15] = 0
      return 0
    end
    return 0
  end

  if Raylib.key_pressed?(Raylib.key_x) != 0
    G.s[28] = G.s[0]
    G.s[0] = 5
    G.s[12] = 0
    G.s[14] = 0
    return 0
  end

  if G.s[7] > 0
    G.s[7] = G.s[7] - 1
  else
    dx = 0
    dy = 0
    if Raylib.key_down?(Raylib.key_up) != 0
      dy = -1
      G.s[4] = 1
    end
    if Raylib.key_down?(Raylib.key_down) != 0
      dy = 1
      G.s[4] = 0
    end
    if Raylib.key_down?(Raylib.key_left) != 0
      dx = -1
      G.s[4] = 2
    end
    if Raylib.key_down?(Raylib.key_right) != 0
      dx = 1
      G.s[4] = 3
    end
    if Raylib.key_down?(Raylib.key_w) != 0
      dy = -1
      G.s[4] = 1
    end
    if Raylib.key_down?(Raylib.key_s) != 0
      dy = 1
      G.s[4] = 0
    end
    if Raylib.key_down?(Raylib.key_a) != 0
      dx = -1
      G.s[4] = 2
    end
    if Raylib.key_down?(Raylib.key_d) != 0
      dx = 1
      G.s[4] = 3
    end

    moved = 0
    if dx != 0
      nx = G.s[2] + dx
      npc_hit = find_npc_at(nx, G.s[3])
      if npc_hit < 0
        if is_walkable(nx, G.s[3]) != 0
          G.s[2] = nx
          G.s[5] = G.s[5] + 1
          G.s[10] = G.s[10] + 1
          G.s[7] = 6
          moved = 1
        end
      end
    end
    if dy != 0
      if moved == 0
        ny = G.s[3] + dy
        npc_hit = find_npc_at(G.s[2], ny)
        if npc_hit < 0
          if is_walkable(G.s[2], ny) != 0
            G.s[3] = ny
            G.s[5] = G.s[5] + 1
            G.s[10] = G.s[10] + 1
            G.s[7] = 6
            moved = 1
          end
        end
      end
    end

    if moved != 0
      mw = G.s[26]
      tile = G.map[G.s[3] * mw + G.s[2]]
      if tile == 9
        G.map[G.s[3] * mw + G.s[2]] = 3
        if G.flags[10] == 0
          add_item(1, 2)
          G.flags[10] = 1
          G.s[15] = 1
          G.s[16] = 10
          G.s[17] = 0
        else
          if G.flags[11] == 0
            add_item(6, 1)
            G.flags[11] = 1
            G.s[15] = 1
            G.s[16] = 11
            G.s[17] = 0
          end
        end
      end
      check_transitions
    end

    if Raylib.key_pressed?(Raylib.key_enter) != 0
      fx = G.s[2]
      fy = G.s[3]
      dir = G.s[4]
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
      npc_id = find_npc_at(fx, fy)
      if npc_id >= 0
        base = npc_id * 16
        G.s[15] = 1
        G.s[16] = G.npc[base + 5]
        G.s[17] = 0
      end
    end

    if moved != 0
      scene = G.s[0]
      mid = G.s[1]
      if scene >= 2
        if scene <= 3
          G.s[19] = G.s[19] - 1
          if G.s[19] <= 0
            G.s[29] = G.s[10] * 7 + G.s[2] * 13 + G.s[3] * 31
            roll = fw_rand(100)
            rate = 22
            if mid == 2
              rate = 30
            end
            if roll < rate
              start_battle
              G.s[19] = 6 + fw_rand(8)
              return 0
            end
            G.s[19] = 4 + fw_rand(6)
          end
        end
      end
    end
  end

  if G.s[1] == 2
    if G.s[2] >= 15
      if G.s[3] <= 5
        if G.flags[0] == 0
          G.flags[0] = 1
          start_boss_battle
          return 0
        end
      end
    end
  end

  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 10: Battle Scene
# ════════════════════════════════════════════════════════════════════

#: () -> Integer
def update_battle
  phase = G.bt[0]

  # Phase 0: "Enemy appeared!" message
  if phase == 0
    G.bt[8] = G.bt[8] - 1
    if G.bt[8] <= 0
      G.bt[0] = 1  # → command select
      G.bt[5] = 0
      G.bt[15] = 0
    end
    return 0
  end

  # Phase 1: Command select
  if phase == 1
    if G.bt[15] == 0  # Main commands
      if Raylib.key_pressed?(Raylib.key_up) != 0
        G.bt[5] = G.bt[5] - 1
        if G.bt[5] < 0
          G.bt[5] = 3
        end
      end
      if Raylib.key_pressed?(Raylib.key_down) != 0
        G.bt[5] = G.bt[5] + 1
        if G.bt[5] > 3
          G.bt[5] = 0
        end
      end
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        cmd = G.bt[5]
        if cmd == 0  # Attack
          G.bt[0] = 2
          G.bt[7] = 30
          G.bt[16] = 0
          G.bt[17] = 0
        end
        if cmd == 1  # Heal spell
          if G.hero[3] >= 4
            G.hero[3] = G.hero[3] - 4
            heal = 20 + G.hero[0] * 5
            G.hero[1] = G.hero[1] + heal
            if G.hero[1] > G.hero[2]
              G.hero[1] = G.hero[2]
            end
            G.bt[11] = heal
            G.bt[12] = 40
            G.bt[0] = 3
            G.bt[7] = 50
            G.bt[17] = 1
          end
        end
        if cmd == 2  # Item sub-menu
          G.bt[15] = 1
          G.bt[5] = 0
        end
        if cmd == 3  # Flee
          G.s[29] = G.s[10] * 17 + G.bt[3]
          hero_agi = G.hero[7]
          en_agi = mon_agi(G.bt[2])
          flee_chance = 50
          if hero_agi > en_agi
            flee_chance = 75
          end
          if fw_rand(100) < flee_chance
            G.bt[13] = 1
            G.bt[0] = 5  # victory (flee)
            G.bt[8] = 40
          else
            G.bt[0] = 3  # enemy turn (flee failed)
            G.bt[7] = 30
            G.bt[17] = 1
          end
        end
      end
      if Raylib.key_pressed?(Raylib.key_space) != 0
        if G.bt[5] == 0
          G.bt[0] = 2
          G.bt[7] = 30
          G.bt[16] = 0
          G.bt[17] = 0
        end
      end
    end
    if G.bt[15] == 1  # Item sub-menu
      ic = inv_count
      if ic == 0
        G.bt[15] = 0
        return 0
      end
      if Raylib.key_pressed?(Raylib.key_up) != 0
        G.bt[5] = G.bt[5] - 1
        if G.bt[5] < 0
          G.bt[5] = ic - 1
        end
      end
      if Raylib.key_pressed?(Raylib.key_down) != 0
        G.bt[5] = G.bt[5] + 1
        if G.bt[5] >= ic
          G.bt[5] = 0
        end
      end
      if Raylib.key_pressed?(Raylib.key_x) != 0
        G.bt[15] = 0
        G.bt[5] = 2
      end
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        slot = inv_slot_at(G.bt[5])
        if slot >= 0
          iid = G.inv[slot * 2]
          if iid == 1  # Herb
            remove_item(slot)
            heal = 30
            G.hero[1] = G.hero[1] + heal
            if G.hero[1] > G.hero[2]
              G.hero[1] = G.hero[2]
            end
            G.bt[11] = heal
            G.bt[12] = 40
            G.bt[15] = 0
            G.bt[0] = 3
            G.bt[7] = 50
            G.bt[17] = 1
          end
          if iid == 2  # Potion
            remove_item(slot)
            heal = 60
            G.hero[1] = G.hero[1] + heal
            if G.hero[1] > G.hero[2]
              G.hero[1] = G.hero[2]
            end
            G.bt[11] = heal
            G.bt[12] = 40
            G.bt[15] = 0
            G.bt[0] = 3
            G.bt[7] = 50
            G.bt[17] = 1
          end
          if iid == 4  # Magic Water
            remove_item(slot)
            G.hero[3] = G.hero[3] + 20
            if G.hero[3] > G.hero[4]
              G.hero[3] = G.hero[4]
            end
            G.bt[15] = 0
            G.bt[0] = 3
            G.bt[7] = 50
            G.bt[17] = 1
          end
        end
      end
    end
    return 0
  end

  # Phase 2: Hero attack animation
  if phase == 2
    G.bt[7] = G.bt[7] - 1
    if G.bt[7] <= 0
      if G.bt[17] == 0
        # Calculate damage
        G.s[29] = G.s[10] * 23 + G.bt[3] * 7
        atk = hero_total_atk
        edef = mon_def(G.bt[2])
        dmg = fw_calc_damage(atk, edef)
        G.bt[3] = G.bt[3] - dmg
        G.bt[11] = dmg
        G.bt[12] = 30
        G.bt[17] = 1
        G.bt[7] = 40

        if G.bt[3] <= 0
          G.bt[3] = 0
          G.bt[4] = 0
        end
      else
        # Check if enemy dead
        if G.bt[4] == 0
          G.bt[0] = 5  # victory
          G.bt[8] = 60
        else
          G.bt[0] = 3  # enemy turn
          G.bt[7] = 30
        end
      end
    end
    return 0
  end

  # Phase 3: Enemy attack
  if phase == 3
    G.bt[7] = G.bt[7] - 1
    if G.bt[7] <= 0
      if G.bt[17] == 1
        G.s[29] = G.s[10] * 31 + G.bt[3] * 11
        eatk = mon_atk(G.bt[2])
        hdef = hero_total_def
        dmg = fw_calc_damage(eatk, hdef)
        if G.bt[16] == 1  # defending
          dmg = dmg / 2
          if dmg < 1
            dmg = 1
          end
        end
        G.hero[1] = G.hero[1] - dmg
        G.bt[11] = dmg
        G.bt[12] = 30
        G.bt[17] = 2
        G.bt[7] = 40

        if G.hero[1] <= 0
          G.hero[1] = 0
        end
      else
        if G.hero[1] <= 0
          G.bt[0] = 6  # defeat
          G.bt[8] = 60
        else
          G.bt[0] = 1  # back to command
          G.bt[5] = 0
          G.bt[15] = 0
          G.bt[16] = 0
          G.bt[17] = 0
        end
      end
    end
    return 0
  end

  # Phase 5: Victory
  if phase == 5
    G.bt[8] = G.bt[8] - 1
    if G.bt[8] <= 0
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        if G.bt[13] == 0  # Not fled
          G.hero[8] = G.hero[8] + G.bt[9]
          G.s[11] = G.s[11] + G.bt[10]
          check_level_up
          # Boss defeated → ending
          if G.bt[2] == 4
            G.s[0] = G.s[28]
            G.s[15] = 1
            G.s[16] = 30
            G.s[17] = 0
            return 0
          end
        end
        G.s[0] = G.s[28]
        return 0
      end
      if Raylib.key_pressed?(Raylib.key_space) != 0
        if G.bt[13] == 0
          G.hero[8] = G.hero[8] + G.bt[9]
          G.s[11] = G.s[11] + G.bt[10]
          check_level_up
          if G.bt[2] == 4
            G.s[0] = G.s[28]
            G.s[15] = 1
            G.s[16] = 30
            G.s[17] = 0
            return 0
          end
        end
        G.s[0] = G.s[28]
        return 0
      end
    end
    return 0
  end

  # Phase 6: Defeat
  if phase == 6
    G.bt[8] = G.bt[8] - 1
    if G.bt[8] <= 0
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        G.s[0] = 8  # game over
        return 0
      end
      if Raylib.key_pressed?(Raylib.key_space) != 0
        G.s[0] = 8
        return 0
      end
    end
    return 0
  end

  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 11: Menu Scene
# ════════════════════════════════════════════════════════════════════

#: () -> Integer
def update_menu
  mode = G.s[14]

  if mode == 0  # Main menu
    if Raylib.key_pressed?(Raylib.key_up) != 0
      G.s[12] = G.s[12] - 1
      if G.s[12] < 0
        G.s[12] = 2
      end
    end
    if Raylib.key_pressed?(Raylib.key_down) != 0
      G.s[12] = G.s[12] + 1
      if G.s[12] > 2
        G.s[12] = 0
      end
    end
    if Raylib.key_pressed?(Raylib.key_enter) != 0
      if G.s[12] == 0  # Status
        G.s[14] = 1
      end
      if G.s[12] == 1  # Items
        G.s[14] = 2
        G.s[13] = 0
      end
      if G.s[12] == 2  # Close
        G.s[0] = G.s[28]
      end
    end
    if Raylib.key_pressed?(Raylib.key_x) != 0
      G.s[0] = G.s[28]
    end
  end

  if mode == 1  # Status view
    if Raylib.key_pressed?(Raylib.key_enter) != 0
      G.s[14] = 0
    end
    if Raylib.key_pressed?(Raylib.key_x) != 0
      G.s[14] = 0
    end
  end

  if mode == 2  # Items
    ic = inv_count
    if Raylib.key_pressed?(Raylib.key_up) != 0
      G.s[13] = G.s[13] - 1
      if G.s[13] < 0
        if ic > 0
          G.s[13] = ic - 1
        else
          G.s[13] = 0
        end
      end
    end
    if Raylib.key_pressed?(Raylib.key_down) != 0
      G.s[13] = G.s[13] + 1
      if G.s[13] >= ic
        G.s[13] = 0
      end
    end
    if Raylib.key_pressed?(Raylib.key_enter) != 0
      if ic > 0
        slot = inv_slot_at(G.s[13])
        if slot >= 0
          iid = G.inv[slot * 2]
          if iid == 1  # Herb
            if G.hero[1] < G.hero[2]
              remove_item(slot)
              G.hero[1] = G.hero[1] + 30
              if G.hero[1] > G.hero[2]
                G.hero[1] = G.hero[2]
              end
            end
          end
          if iid == 2  # Potion
            if G.hero[1] < G.hero[2]
              remove_item(slot)
              G.hero[1] = G.hero[1] + 60
              if G.hero[1] > G.hero[2]
                G.hero[1] = G.hero[2]
              end
            end
          end
          if iid == 4  # Magic Water
            if G.hero[3] < G.hero[4]
              remove_item(slot)
              G.hero[3] = G.hero[3] + 20
              if G.hero[3] > G.hero[4]
                G.hero[3] = G.hero[4]
              end
            end
          end
          # Equip weapon
          if iid >= 5
            if iid <= 7
              old = G.hero[9]
              G.hero[9] = iid
              remove_item(slot)
              if old > 0
                add_item(old, 1)
              end
            end
          end
          # Equip armor
          if iid >= 8
            if iid <= 10
              old = G.hero[10]
              G.hero[10] = iid
              remove_item(slot)
              if old > 0
                add_item(old, 1)
              end
            end
          end
        end
      end
    end
    if Raylib.key_pressed?(Raylib.key_x) != 0
      G.s[14] = 0
    end
  end

  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 12: Shop Scene
# ════════════════════════════════════════════════════════════════════

# Shop sells: Herb(1), Potion(2), Magic Water(4), Wood Sword(5), Iron Sword(6),
#             Leather(8), Chain Mail(9)
#: (Integer idx) -> Integer
def shop_item_id(idx)
  if idx == 0
    return 1
  end
  if idx == 1
    return 2
  end
  if idx == 2
    return 4
  end
  if idx == 3
    return 5
  end
  if idx == 4
    return 6
  end
  if idx == 5
    return 8
  end
  if idx == 6
    return 9
  end
  return 0
end

#: () -> Integer
def update_shop
  if Raylib.key_pressed?(Raylib.key_up) != 0
    G.s[24] = G.s[24] - 1
    if G.s[24] < 0
      G.s[24] = 7  # 7 items + exit
    end
  end
  if Raylib.key_pressed?(Raylib.key_down) != 0
    G.s[24] = G.s[24] + 1
    if G.s[24] > 7
      G.s[24] = 0
    end
  end
  if Raylib.key_pressed?(Raylib.key_enter) != 0
    if G.s[24] == 7  # Exit
      G.s[0] = G.s[28]
      return 0
    end
    iid = shop_item_id(G.s[24])
    if iid > 0
      price = item_price(iid)
      if G.s[11] >= price
        G.s[11] = G.s[11] - price
        add_item(iid, 1)
      end
    end
  end
  if Raylib.key_pressed?(Raylib.key_x) != 0
    G.s[0] = G.s[28]
  end
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 13: Drawing — Field
# ════════════════════════════════════════════════════════════════════

#: (Integer anim_frame) -> Integer
def draw_field(anim_frame)
  mw = G.s[26]
  mh = G.s[27]
  mid = G.s[1]

  # Camera
  target_cx = G.s[2] * 3200
  target_cy = G.s[3] * 3200
  G.s[8] = fw_lerp(G.s[8], target_cx, 6)
  G.s[9] = fw_lerp(G.s[9], target_cy, 6)
  cam_x = G.s[8] / 100
  cam_y = G.s[9] / 100
  scroll_x = 320 - cam_x
  scroll_y = 240 - cam_y

  # Draw visible tiles
  start_tx = (cam_x - 340) / 32 - 1
  start_ty = (cam_y - 260) / 32 - 1
  end_tx = (cam_x + 340) / 32 + 2
  end_ty = (cam_y + 260) / 32 + 2
  if start_tx < 0
    start_tx = 0
  end
  if start_ty < 0
    start_ty = 0
  end
  if end_tx > mw
    end_tx = mw
  end
  if end_ty > mh
    end_ty = mh
  end

  ty = start_ty
  while ty < end_ty
    tx = start_tx
    while tx < end_tx
      tile = G.map[ty * mw + tx]
      ppx = tx * 32 + scroll_x
      ppy = ty * 32 + scroll_y
      draw_tile(ppx, ppy, tile, anim_frame, mid)
      tx = tx + 1
    end
    ty = ty + 1
  end

  # Draw NPCs
  ni = 0
  while ni < 10
    base = ni * 16
    if G.npc[base] == 1
      nx = G.npc[base + 1]
      ny = G.npc[base + 2]
      npx = nx * 32 + scroll_x
      npy = ny * 32 + scroll_y
      draw_npc(npx, npy, G.npc[base + 4], G.npc[base + 3])
    end
    ni = ni + 1
  end

  # Draw hero
  hpx = G.s[2] * 32 + scroll_x
  hpy = G.s[3] * 32 + scroll_y
  draw_hero(hpx, hpy, G.s[4], G.s[5] % 4)

  # HUD bar
  Raylib.draw_rectangle(0, 0, 640, 36, fw_rgba(0, 0, 0, 180))
  fw_draw_txt("HP:", 8, 8, 16, Raylib.color_white)
  fw_draw_num(38, 8, G.hero[1], 16, Raylib.color_lime)
  fw_draw_txt("/", 80, 8, 16, Raylib.color_gray)
  fw_draw_num(92, 8, G.hero[2], 16, Raylib.color_white)
  fw_draw_txt("MP:", 150, 8, 16, Raylib.color_white)
  fw_draw_num(180, 8, G.hero[3], 16, Raylib.color_skyblue)
  fw_draw_txt("/", 210, 8, 16, Raylib.color_gray)
  fw_draw_num(222, 8, G.hero[4], 16, Raylib.color_white)
  fw_draw_txt("LV:", 300, 8, 16, Raylib.color_white)
  fw_draw_num(332, 8, G.hero[0], 16, Raylib.color_gold)
  fw_draw_txt("G:", 400, 8, 16, Raylib.color_white)
  fw_draw_num(424, 8, G.s[11], 16, Raylib.color_gold)

  # Map name
  if mid == 0
    fw_draw_txt("Village", 550, 8, 16, Raylib.color_lightgray)
  end
  if mid == 1
    fw_draw_txt("Field", 560, 8, 16, Raylib.color_lightgray)
  end
  if mid == 2
    fw_draw_txt("Cave", 568, 8, 16, Raylib.color_lightgray)
  end

  # Dialog box
  if G.s[15] == 1
    fw_draw_window(36, 350, 568, 110)
    draw_dialog_text(G.s[16], G.s[17])
    fw_draw_txt("[Enter]", 530, 436, 14, Raylib.color_gray)
  end

  # Controls hint
  if G.s[15] == 0
    fw_draw_txt("[Enter]Talk  [X]Menu", 8, 462, 14, Raylib.color_gray)
  end

  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 14: Drawing — Battle
# ════════════════════════════════════════════════════════════════════

#: () -> Integer
def draw_battle
  phase = G.bt[0]
  etype = G.bt[2]

  # Background gradient (dark)
  Raylib.draw_rectangle(0, 0, 640, 240, fw_rgba(10, 10, 30, 255))
  Raylib.draw_rectangle(0, 240, 640, 8, fw_rgba(40, 60, 40, 255))

  # Ground
  Raylib.draw_rectangle(0, 248, 640, 232, fw_rgba(30, 50, 30, 255))

  # Draw monster
  if G.bt[4] == 1
    draw_monster(320, 140, etype)
  end

  # Damage display
  if G.bt[12] > 0
    G.bt[12] = G.bt[12] - 1
    dy = 120
    if G.bt[17] == 1  # Enemy took damage
      fw_draw_num(290, dy, G.bt[11], 24, Raylib.color_white)
    end
    if G.bt[17] == 2  # Hero took damage
      fw_draw_num(50, 360, G.bt[11], 24, Raylib.color_red)
    end
    if G.bt[0] == 3
      if G.bt[17] == 0  # Heal display
        fw_draw_num(50, 360, G.bt[11], 24, Raylib.color_lime)
      end
    end
  end

  # Hero status window
  fw_draw_window(10, 260, 200, 80)
  fw_draw_txt("Hero", 24, 270, 18, Raylib.color_white)
  fw_draw_txt("HP:", 24, 294, 16, Raylib.color_white)
  fw_draw_num(60, 294, G.hero[1], 16, Raylib.color_lime)
  fw_draw_txt("/", 104, 294, 16, Raylib.color_gray)
  fw_draw_num(116, 294, G.hero[2], 16, Raylib.color_white)
  fw_draw_txt("MP:", 24, 316, 16, Raylib.color_white)
  fw_draw_num(60, 316, G.hero[3], 16, Raylib.color_skyblue)
  fw_draw_txt("/", 104, 316, 16, Raylib.color_gray)
  fw_draw_num(116, 316, G.hero[4], 16, Raylib.color_white)

  # Phase-specific UI
  if phase == 0  # "appeared" message
    fw_draw_window(160, 380, 320, 50)
    draw_mon_name(180, 392, etype, 20, Raylib.color_white)
    fw_draw_txt("appeared!", 300, 396, 18, Raylib.color_white)
  end

  if phase == 1  # Command select
    if G.bt[15] == 0
      fw_draw_window(430, 260, 180, 120)
      fw_draw_txt("Attack", 466, 274, 18, Raylib.color_white)
      fw_draw_txt("Heal", 466, 298, 18, Raylib.color_white)
      fw_draw_txt("Item", 466, 322, 18, Raylib.color_white)
      fw_draw_txt("Flee", 466, 346, 18, Raylib.color_white)
      fw_draw_txt(">", 446, 274 + G.bt[5] * 24, 18, Raylib.color_gold)

      # MP cost hint
      if G.bt[5] == 1
        fw_draw_txt("4 MP", 550, 298, 14, Raylib.color_skyblue)
      end
    end
    if G.bt[15] == 1  # Item sub-menu
      ic = inv_count
      fw_draw_window(220, 260, 200, 120)
      fw_draw_txt("Items", 240, 268, 16, Raylib.color_gold)
      idx = 0
      while idx < ic
        if idx < 4
          slot = inv_slot_at(idx)
          if slot >= 0
            iid = G.inv[slot * 2]
            draw_item_name(256, 290 + idx * 22, iid, 16, Raylib.color_white)
            fw_draw_txt("x", 370, 290 + idx * 22, 14, Raylib.color_gray)
            fw_draw_num(382, 290 + idx * 22, G.inv[slot * 2 + 1], 14, Raylib.color_white)
          end
        end
        idx = idx + 1
      end
      if ic > 0
        fw_draw_txt(">", 236, 290 + G.bt[5] * 22, 16, Raylib.color_gold)
      else
        fw_draw_txt("No items", 256, 290, 16, Raylib.color_gray)
      end
    end
  end

  if phase == 2  # Hero attacking
    fw_draw_window(160, 380, 320, 50)
    fw_draw_txt("Hero attacks!", 180, 396, 18, Raylib.color_white)
  end

  if phase == 3  # Enemy attacking
    fw_draw_window(160, 380, 320, 50)
    draw_mon_name(180, 392, etype, 18, Raylib.color_white)
    fw_draw_txt("attacks!", 300, 396, 18, Raylib.color_white)
  end

  if phase == 5  # Victory
    fw_draw_window(120, 300, 400, 120)
    if G.bt[13] == 1
      fw_draw_txt("Escaped successfully!", 160, 320, 20, Raylib.color_white)
    else
      fw_draw_txt("Victory!", 260, 310, 24, Raylib.color_gold)
      fw_draw_txt("EXP:", 160, 340, 18, Raylib.color_white)
      fw_draw_num(216, 340, G.bt[9], 18, Raylib.color_lime)
      fw_draw_txt("Gold:", 320, 340, 18, Raylib.color_white)
      fw_draw_num(380, 340, G.bt[10], 18, Raylib.color_gold)
    end
    if G.bt[8] <= 0
      fw_draw_txt("[Enter] Continue", 240, 390, 16, Raylib.color_gray)
    end
  end

  if phase == 6  # Defeat
    fw_draw_window(160, 300, 320, 80)
    fw_draw_txt("You have been defeated...", 190, 326, 20, Raylib.color_red)
    if G.bt[8] <= 0
      fw_draw_txt("[Enter] Continue", 240, 360, 16, Raylib.color_gray)
    end
  end

  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 15: Drawing — Menu
# ════════════════════════════════════════════════════════════════════

#: () -> Integer
def draw_menu
  Raylib.draw_rectangle(0, 0, 640, 480, fw_rgba(0, 0, 0, 160))

  mode = G.s[14]

  # Left: menu options
  fw_draw_window(40, 40, 160, 120)
  fw_draw_txt("Status", 80, 58, 18, Raylib.color_white)
  fw_draw_txt("Items", 80, 84, 18, Raylib.color_white)
  fw_draw_txt("Close", 80, 110, 18, Raylib.color_white)
  if mode == 0
    fw_draw_txt(">", 58, 58 + G.s[12] * 26, 18, Raylib.color_gold)
  end

  if mode == 1  # Status
    fw_draw_window(220, 40, 380, 280)
    fw_draw_txt("Hero", 250, 56, 24, Raylib.color_gold)
    fw_draw_txt("Level:", 250, 92, 18, Raylib.color_white)
    fw_draw_num(340, 92, G.hero[0], 18, Raylib.color_gold)

    fw_draw_txt("HP:", 250, 120, 18, Raylib.color_white)
    fw_draw_num(300, 120, G.hero[1], 18, Raylib.color_lime)
    fw_draw_txt("/", 350, 120, 18, Raylib.color_gray)
    fw_draw_num(368, 120, G.hero[2], 18, Raylib.color_white)

    fw_draw_txt("MP:", 250, 148, 18, Raylib.color_white)
    fw_draw_num(300, 148, G.hero[3], 18, Raylib.color_skyblue)
    fw_draw_txt("/", 350, 148, 18, Raylib.color_gray)
    fw_draw_num(368, 148, G.hero[4], 18, Raylib.color_white)

    fw_draw_txt("ATK:", 250, 180, 18, Raylib.color_white)
    fw_draw_num(310, 180, hero_total_atk, 18, Raylib.color_orange)
    fw_draw_txt("DEF:", 400, 180, 18, Raylib.color_white)
    fw_draw_num(460, 180, hero_total_def, 18, Raylib.color_orange)

    fw_draw_txt("AGI:", 250, 208, 18, Raylib.color_white)
    fw_draw_num(310, 208, G.hero[7], 18, Raylib.color_orange)

    fw_draw_txt("EXP:", 250, 240, 18, Raylib.color_white)
    fw_draw_num(310, 240, G.hero[8], 18, Raylib.color_white)
    fw_draw_txt("Next:", 400, 240, 18, Raylib.color_white)
    next_exp = exp_for_level(G.hero[0] + 1) - G.hero[8]
    if next_exp < 0
      next_exp = 0
    end
    fw_draw_num(460, 240, next_exp, 18, Raylib.color_white)

    # Equipment
    fw_draw_txt("Weapon:", 250, 272, 16, Raylib.color_gray)
    if G.hero[9] > 0
      draw_item_name(340, 272, G.hero[9], 16, Raylib.color_white)
    else
      fw_draw_txt("(none)", 340, 272, 16, Raylib.color_darkgray)
    end
    fw_draw_txt("Armor:", 250, 294, 16, Raylib.color_gray)
    if G.hero[10] > 0
      draw_item_name(340, 294, G.hero[10], 16, Raylib.color_white)
    else
      fw_draw_txt("(none)", 340, 294, 16, Raylib.color_darkgray)
    end
    fw_draw_txt("[Z/X] Back", 430, 56, 14, Raylib.color_gray)
  end

  if mode == 2  # Items
    fw_draw_window(220, 40, 380, 300)
    fw_draw_txt("Items", 250, 56, 20, Raylib.color_gold)
    ic = inv_count
    idx = 0
    while idx < ic
      if idx < 10
        slot = inv_slot_at(idx)
        if slot >= 0
          iid = G.inv[slot * 2]
          draw_item_name(270, 86 + idx * 24, iid, 16, Raylib.color_white)
          fw_draw_txt("x", 440, 86 + idx * 24, 14, Raylib.color_gray)
          fw_draw_num(454, 86 + idx * 24, G.inv[slot * 2 + 1], 14, Raylib.color_white)
        end
      end
      idx = idx + 1
    end
    if ic == 0
      fw_draw_txt("No items", 270, 86, 16, Raylib.color_darkgray)
    else
      fw_draw_txt(">", 250, 86 + G.s[13] * 24, 16, Raylib.color_gold)
    end
    fw_draw_txt("[Enter]Use [X]Back", 400, 56, 14, Raylib.color_gray)
  end

  # Gold display
  fw_draw_window(40, 180, 160, 40)
  fw_draw_txt("Gold:", 58, 192, 16, Raylib.color_white)
  fw_draw_num(110, 192, G.s[11], 16, Raylib.color_gold)

  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 16: Drawing — Shop
# ════════════════════════════════════════════════════════════════════

#: () -> Integer
def draw_shop
  Raylib.draw_rectangle(0, 0, 640, 480, fw_rgba(0, 0, 0, 180))

  fw_draw_window(100, 30, 440, 400)
  fw_draw_txt("Shop", 280, 48, 24, Raylib.color_gold)

  # Gold
  fw_draw_txt("Gold:", 360, 48, 16, Raylib.color_white)
  fw_draw_num(416, 48, G.s[11], 16, Raylib.color_gold)

  # Items list
  idx = 0
  while idx < 7
    iid = shop_item_id(idx)
    iy = 82 + idx * 36
    draw_item_name(160, iy, iid, 18, Raylib.color_white)
    fw_draw_num(380, iy, item_price(iid), 16, Raylib.color_gold)
    fw_draw_txt("G", 430, iy + 2, 14, Raylib.color_gray)
    idx = idx + 1
  end
  # Exit option
  fw_draw_txt("Exit", 160, 82 + 7 * 36, 18, Raylib.color_white)

  # Cursor
  fw_draw_txt(">", 134, 82 + G.s[24] * 36, 18, Raylib.color_gold)

  fw_draw_txt("[Enter]Buy [X]Exit", 220, 408, 16, Raylib.color_gray)
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 17: Title / GameOver / Victory Screens
# ════════════════════════════════════════════════════════════════════

#: (Integer blink) -> Integer
def draw_title(blink)
  Raylib.draw_rectangle(0, 0, 640, 480, fw_rgba(10, 10, 40, 255))

  # Decorative border
  Raylib.draw_rectangle(60, 80, 520, 4, fw_rgba(200, 180, 100, 255))
  Raylib.draw_rectangle(60, 280, 520, 4, fw_rgba(200, 180, 100, 255))
  Raylib.draw_rectangle(60, 80, 4, 204, fw_rgba(200, 180, 100, 255))
  Raylib.draw_rectangle(576, 80, 4, 204, fw_rgba(200, 180, 100, 255))

  # Title
  fw_draw_txt("KONPEITO QUEST", 160, 120, 40, Raylib.color_gold)
  fw_draw_txt("~ Dragon's Cave ~", 210, 180, 24, Raylib.color_lightgray)

  # Dragon silhouette
  Raylib.draw_circle(320, 230, 20.0, fw_rgba(140, 30, 30, 120))
  Raylib.draw_rectangle(304, 216, 4, 10, fw_rgba(160, 140, 60, 100))
  Raylib.draw_rectangle(328, 216, 4, 10, fw_rgba(160, 140, 60, 100))

  if blink % 60 < 40
    fw_draw_txt("Press Enter to Start", 230, 350, 22, Raylib.color_white)
  end

  fw_draw_txt("Arrow/WASD:Move  Enter:Confirm  X:Menu", 140, 420, 16, Raylib.color_gray)
  fw_draw_txt("Konpeito + mruby + raylib", 200, 450, 14, Raylib.color_darkgray)
  return 0
end

#: () -> Integer
def draw_gameover
  Raylib.draw_rectangle(0, 0, 640, 480, fw_rgba(20, 0, 0, 255))
  fw_draw_txt("GAME OVER", 200, 180, 40, Raylib.color_red)
  fw_draw_txt("The hero has fallen...", 210, 240, 20, Raylib.color_lightgray)
  fw_draw_txt("Press Enter to return to title", 210, 340, 18, Raylib.color_gray)
  return 0
end

#: () -> Integer
def draw_victory_screen
  Raylib.draw_rectangle(0, 0, 640, 480, fw_rgba(10, 10, 50, 255))

  # Stars
  Raylib.draw_circle(100, 80, 2.0, Raylib.color_white)
  Raylib.draw_circle(250, 50, 2.0, Raylib.color_white)
  Raylib.draw_circle(400, 70, 2.0, Raylib.color_white)
  Raylib.draw_circle(520, 40, 2.0, Raylib.color_white)
  Raylib.draw_circle(150, 120, 1.0, Raylib.color_white)
  Raylib.draw_circle(450, 110, 1.0, Raylib.color_white)

  fw_draw_window(100, 100, 440, 280)
  fw_draw_txt("CONGRATULATIONS!", 170, 130, 32, Raylib.color_gold)
  fw_draw_txt("You defeated the Dragon and", 160, 190, 20, Raylib.color_white)
  fw_draw_txt("saved the village!", 210, 220, 20, Raylib.color_white)

  fw_draw_txt("Final Level:", 180, 270, 18, Raylib.color_white)
  fw_draw_num(320, 270, G.hero[0], 18, Raylib.color_gold)
  fw_draw_txt("Total Steps:", 180, 298, 18, Raylib.color_white)
  fw_draw_num(320, 298, G.s[10], 18, Raylib.color_gold)
  fw_draw_txt("Gold:", 180, 326, 18, Raylib.color_white)
  fw_draw_num(320, 326, G.s[11], 18, Raylib.color_gold)

  fw_draw_txt("Thanks for playing!", 220, 400, 20, Raylib.color_lightgray)
  fw_draw_txt("Press Enter to return to title", 210, 440, 16, Raylib.color_gray)
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 18: Clay UI Drawing
# ════════════════════════════════════════════════════════════════════

# Draw monster name as Clay text
#: (Integer t, Integer cfont, Integer sz) -> Integer
def clay_mon_name(t, cfont, sz)
  if t == 0
    fw_clay_text("Slime", cfont, sz)
  end
  if t == 1
    fw_clay_text("Bat", cfont, sz)
  end
  if t == 2
    fw_clay_text("Goblin", cfont, sz)
  end
  if t == 3
    fw_clay_text("Skeleton", cfont, sz)
  end
  if t == 4
    fw_clay_text("Dragon", cfont, sz)
  end
  return 0
end

# Draw item name as Clay text
#: (Integer id, Integer cfont, Integer sz) -> Integer
def clay_item_name(id, cfont, sz)
  if id == 1
    fw_clay_text("Herb", cfont, sz)
  end
  if id == 2
    fw_clay_text("Potion", cfont, sz)
  end
  if id == 3
    fw_clay_text("Antidote", cfont, sz)
  end
  if id == 4
    fw_clay_text("Magic Water", cfont, sz)
  end
  if id == 5
    fw_clay_text("Wood Sword", cfont, sz)
  end
  if id == 6
    fw_clay_text("Iron Sword", cfont, sz)
  end
  if id == 7
    fw_clay_text("Steel Sword", cfont, sz)
  end
  if id == 8
    fw_clay_text("Leather", cfont, sz)
  end
  if id == 9
    fw_clay_text("Chain Mail", cfont, sz)
  end
  if id == 10
    fw_clay_text("Steel Armor", cfont, sz)
  end
  if id == 11
    fw_clay_text("Dragon Key", cfont, sz)
  end
  return 0
end

# Draw item name as Clay text with color
#: (Integer id, Integer cfont, Integer sz, Integer r, Integer g, Integer b) -> Integer
def clay_item_name_c(id, cfont, sz, r, g, b)
  if id == 1
    fw_clay_text_color("Herb", cfont, sz, r, g, b)
  end
  if id == 2
    fw_clay_text_color("Potion", cfont, sz, r, g, b)
  end
  if id == 3
    fw_clay_text_color("Antidote", cfont, sz, r, g, b)
  end
  if id == 4
    fw_clay_text_color("Magic Water", cfont, sz, r, g, b)
  end
  if id == 5
    fw_clay_text_color("Wood Sword", cfont, sz, r, g, b)
  end
  if id == 6
    fw_clay_text_color("Iron Sword", cfont, sz, r, g, b)
  end
  if id == 7
    fw_clay_text_color("Steel Sword", cfont, sz, r, g, b)
  end
  if id == 8
    fw_clay_text_color("Leather", cfont, sz, r, g, b)
  end
  if id == 9
    fw_clay_text_color("Chain Mail", cfont, sz, r, g, b)
  end
  if id == 10
    fw_clay_text_color("Steel Armor", cfont, sz, r, g, b)
  end
  if id == 11
    fw_clay_text_color("Dragon Key", cfont, sz, r, g, b)
  end
  return 0
end

# Battle background (Raylib only - monster, ground, damage numbers)
#: () -> Integer
def draw_battle_bg
  etype = G.bt[2]

  # Background gradient
  Raylib.draw_rectangle(0, 0, 640, 240, fw_rgba(10, 10, 30, 255))
  Raylib.draw_rectangle(0, 240, 640, 8, fw_rgba(40, 60, 40, 255))
  Raylib.draw_rectangle(0, 248, 640, 232, fw_rgba(30, 50, 30, 255))

  # Monster
  if G.bt[4] == 1
    draw_monster(320, 140, etype)
  end

  # Damage numbers (drawn with Raylib for pixel positioning)
  if G.bt[12] > 0
    G.bt[12] = G.bt[12] - 1
    if G.bt[17] == 1
      fw_draw_num(290, 120, G.bt[11], 24, Raylib.color_white)
    end
    if G.bt[17] == 2
      fw_draw_num(50, 360, G.bt[11], 24, Raylib.color_red)
    end
    if G.bt[0] == 3
      if G.bt[17] == 0
        fw_draw_num(50, 360, G.bt[11], 24, Raylib.color_lime)
      end
    end
  end

  return 0
end

# Battle UI overlay (Clay)
#: () -> Integer
def draw_battle_clay
  phase = G.bt[0]
  etype = G.bt[2]
  cfont = G.s[32]

  fw_clay_frame_begin

  # Root: full screen vertical
  fw_clay_vbox("bt_root", 8, 8)

    # Top spacer (monster area drawn by Raylib behind)
    fw_clay_spacer("bt_top")

    # Bottom HUD: hero status + commands
    fw_clay_hbox("bt_bot", 0, 8)

      # Hero status panel
      fw_clay_rpg_window("bt_hero", 200, 80, 8)
        fw_clay_text("Hero", cfont, 18)
        # HP row
        fw_clay_hbox("bt_hpr", 0, 4)
          fw_clay_text_color("HP:", cfont, 14, 200, 200, 200)
          fw_clay_num(0, G.hero[1], cfont, 14, 50, 255, 50)
          fw_clay_text_color("/", cfont, 14, 140, 140, 140)
          fw_clay_num(1, G.hero[2], cfont, 14, 255, 255, 255)
          fw_clay_bar("bt_hb", 0, G.hero[1], G.hero[2], 60, 10, 50, 200, 50)
        Clay.close
        # MP row
        fw_clay_hbox("bt_mpr", 0, 4)
          fw_clay_text_color("MP:", cfont, 14, 200, 200, 200)
          fw_clay_num(2, G.hero[3], cfont, 14, 100, 180, 255)
          fw_clay_text_color("/", cfont, 14, 140, 140, 140)
          fw_clay_num(3, G.hero[4], cfont, 14, 255, 255, 255)
          fw_clay_bar("bt_mb", 1, G.hero[3], G.hero[4], 60, 10, 80, 140, 255)
        Clay.close
      Clay.close

      # Spacer between hero and commands
      fw_clay_spacer("bt_mid")

      # Phase 1: Command menu
      if phase == 1
        if G.bt[15] == 0
          fw_clay_rpg_window("bt_cmd", 170, 120, 8)
            fw_clay_menu_item("bt_ci", 0, "Attack", G.bt[5], cfont, 18)
            fw_clay_menu_item("bt_ci", 1, "Heal", G.bt[5], cfont, 18)
            fw_clay_menu_item("bt_ci", 2, "Item", G.bt[5], cfont, 18)
            fw_clay_menu_item("bt_ci", 3, "Flee", G.bt[5], cfont, 18)
            # MP cost hint
            if G.bt[5] == 1
              fw_clay_text_color("  4 MP", cfont, 12, 100, 180, 255)
            end
          Clay.close
        end
        if G.bt[15] == 1
          # Item sub-menu
          ic = inv_count
          fw_clay_rpg_window("bt_itm", 200, 130, 8)
            fw_clay_text_color("Items", cfont, 16, 255, 215, 0)
            idx = 0
            while idx < ic
              if idx < 4
                slot = inv_slot_at(idx)
                if slot >= 0
                  iid = G.inv[slot * 2]
                  Clay.open_i("bt_ii", idx)
                  Clay.layout(0, 4, 4, 2, 2, 4, 1, 0.0, 0, 0.0, 0, 2)
                  if G.bt[5] == idx
                    Clay.bg(60.0, 60.0, 120.0, 200.0, 4.0)
                    fw_clay_text_color(">", cfont, 16, 255, 255, 100)
                  end
                  clay_item_name(iid, cfont, 16)
                  fw_clay_text_color(" x", cfont, 14, 140, 140, 140)
                  fw_clay_num(10 + idx, G.inv[slot * 2 + 1], cfont, 14, 255, 255, 255)
                  Clay.close
                end
              end
              idx = idx + 1
            end
            if ic == 0
              fw_clay_text_color("No items", cfont, 16, 140, 140, 140)
            end
          Clay.close
        end
      end

    Clay.close # bt_bot

    # Message window (phases 0, 2, 3, 5, 6)
    if phase == 0
      fw_clay_hbox_center("bt_msg", 12, 4)
        fw_clay_rpg_bg
        clay_mon_name(etype, cfont, 20)
        fw_clay_text(" appeared!", cfont, 18)
      Clay.close
    end

    if phase == 2
      fw_clay_hbox_center("bt_msg", 12, 0)
        fw_clay_rpg_bg
        fw_clay_text("Hero attacks!", cfont, 18)
      Clay.close
    end

    if phase == 3
      fw_clay_hbox_center("bt_msg", 12, 4)
        fw_clay_rpg_bg
        clay_mon_name(etype, cfont, 18)
        fw_clay_text(" attacks!", cfont, 18)
      Clay.close
    end

    if phase == 5
      fw_clay_rpg_window("bt_vic", 400, 120, 12)
        Clay.layout(1, 12, 12, 12, 12, 6, 2, 400.0, 2, 120.0, 2, 0)
        if G.bt[13] == 1
          fw_clay_text("Escaped successfully!", cfont, 20)
        else
          fw_clay_text_color("Victory!", cfont, 24, 255, 215, 0)
          fw_clay_hbox("bt_rew", 0, 12)
            fw_clay_text("EXP:", cfont, 16)
            fw_clay_num(20, G.bt[9], cfont, 16, 50, 255, 50)
            fw_clay_text("Gold:", cfont, 16)
            fw_clay_num(21, G.bt[10], cfont, 16, 255, 215, 0)
          Clay.close
        end
        if G.bt[8] <= 0
          fw_clay_text_color("[Enter] Continue", cfont, 14, 140, 140, 140)
        end
      Clay.close
    end

    if phase == 6
      fw_clay_rpg_window("bt_def", 340, 80, 12)
        Clay.layout(1, 12, 12, 12, 12, 6, 2, 340.0, 2, 80.0, 2, 2)
        fw_clay_text_color("You have been defeated...", cfont, 20, 255, 60, 60)
        if G.bt[8] <= 0
          fw_clay_text_color("[Enter] Continue", cfont, 14, 140, 140, 140)
        end
      Clay.close
    end

  Clay.close # bt_root

  fw_clay_frame_end
  return 0
end

# Menu UI overlay (Clay)
#: () -> Integer
def draw_menu_clay
  cfont = G.s[32]
  mode = G.s[14]

  fw_clay_frame_begin

  # Root: full screen with dark overlay
  fw_clay_hbox("mn_root", 16, 16)
    Clay.bg(0.0, 0.0, 0.0, 160.0, 0.0)

    # Left panel: menu choices
    fw_clay_rpg_window("mn_left", 160, 140, 12)
      fw_clay_menu_item("mn_mi", 0, "Status", G.s[12], cfont, 18)
      fw_clay_menu_item("mn_mi", 1, "Items", G.s[12], cfont, 18)
      fw_clay_menu_item("mn_mi", 2, "Close", G.s[12], cfont, 18)
      # Gold display
      fw_clay_hbox("mn_gld", 8, 4)
        fw_clay_text_color("Gold:", cfont, 14, 200, 200, 200)
        fw_clay_num(30, G.s[11], cfont, 14, 255, 215, 0)
      Clay.close
    Clay.close

    # Right panel: Status or Items
    if mode == 1
      fw_clay_rpg_window("mn_stat", 380, 280, 12)
        fw_clay_text_color("Hero", cfont, 24, 255, 215, 0)
        # Level
        fw_clay_hbox("mn_lv", 0, 4)
          fw_clay_text("Level:", cfont, 16)
          fw_clay_num(40, G.hero[0], cfont, 16, 255, 215, 0)
        Clay.close
        # HP
        fw_clay_hbox("mn_hp", 0, 4)
          fw_clay_text_color("HP:", cfont, 16, 200, 200, 200)
          fw_clay_num(41, G.hero[1], cfont, 16, 50, 255, 50)
          fw_clay_text_color("/", cfont, 16, 140, 140, 140)
          fw_clay_num(42, G.hero[2], cfont, 16, 255, 255, 255)
          fw_clay_bar("mn_hb", 2, G.hero[1], G.hero[2], 100, 12, 50, 200, 50)
        Clay.close
        # MP
        fw_clay_hbox("mn_mp", 0, 4)
          fw_clay_text_color("MP:", cfont, 16, 200, 200, 200)
          fw_clay_num(43, G.hero[3], cfont, 16, 100, 180, 255)
          fw_clay_text_color("/", cfont, 16, 140, 140, 140)
          fw_clay_num(44, G.hero[4], cfont, 16, 255, 255, 255)
          fw_clay_bar("mn_mb", 3, G.hero[3], G.hero[4], 100, 12, 80, 140, 255)
        Clay.close
        # ATK / DEF
        fw_clay_hbox("mn_ad", 0, 16)
          fw_clay_text("ATK:", cfont, 16)
          fw_clay_num(45, hero_total_atk, cfont, 16, 255, 165, 0)
          fw_clay_text("DEF:", cfont, 16)
          fw_clay_num(46, hero_total_def, cfont, 16, 255, 165, 0)
        Clay.close
        # AGI
        fw_clay_hbox("mn_ag", 0, 4)
          fw_clay_text("AGI:", cfont, 16)
          fw_clay_num(47, G.hero[7], cfont, 16, 255, 165, 0)
        Clay.close
        # EXP
        fw_clay_hbox("mn_xp", 0, 16)
          fw_clay_text("EXP:", cfont, 16)
          fw_clay_num(48, G.hero[8], cfont, 16, 255, 255, 255)
          fw_clay_text("Next:", cfont, 16)
          next_exp = exp_for_level(G.hero[0] + 1) - G.hero[8]
          if next_exp < 0
            next_exp = 0
          end
          fw_clay_num(49, next_exp, cfont, 16, 255, 255, 255)
        Clay.close
        # Equipment
        fw_clay_hbox("mn_weq", 0, 4)
          fw_clay_text_color("Weapon:", cfont, 14, 140, 140, 140)
          if G.hero[9] > 0
            clay_item_name_c(G.hero[9], cfont, 14, 255, 255, 255)
          else
            fw_clay_text_color("(none)", cfont, 14, 80, 80, 80)
          end
        Clay.close
        fw_clay_hbox("mn_aeq", 0, 4)
          fw_clay_text_color("Armor:", cfont, 14, 140, 140, 140)
          if G.hero[10] > 0
            clay_item_name_c(G.hero[10], cfont, 14, 255, 255, 255)
          else
            fw_clay_text_color("(none)", cfont, 14, 80, 80, 80)
          end
        Clay.close
      Clay.close
    end

    if mode == 2
      fw_clay_rpg_window("mn_items", 380, 310, 12)
        fw_clay_hbox("mn_ith", 0, 8)
          fw_clay_text_color("Items", cfont, 20, 255, 215, 0)
          fw_clay_spacer("mn_its")
          fw_clay_text_color("[Enter]Use [X]Back", cfont, 12, 140, 140, 140)
        Clay.close
        ic = inv_count
        idx = 0
        while idx < ic
          if idx < 10
            slot = inv_slot_at(idx)
            if slot >= 0
              iid = G.inv[slot * 2]
              Clay.open_i("mn_ii", idx)
              Clay.layout(0, 4, 4, 2, 2, 4, 1, 0.0, 0, 0.0, 0, 2)
              if G.s[13] == idx
                Clay.bg(60.0, 60.0, 120.0, 200.0, 4.0)
                fw_clay_text_color(">", cfont, 16, 255, 255, 100)
              end
              clay_item_name(iid, cfont, 16)
              fw_clay_text_color(" x", cfont, 14, 140, 140, 140)
              fw_clay_num(50 + idx, G.inv[slot * 2 + 1], cfont, 14, 255, 255, 255)
              Clay.close
            end
          end
          idx = idx + 1
        end
        if ic == 0
          fw_clay_text_color("No items", cfont, 16, 80, 80, 80)
        end
      Clay.close
    end

    if mode == 0
      # Hint area when no sub-menu open
      fw_clay_spacer("mn_sp")
    end

  Clay.close # mn_root

  fw_clay_frame_end
  return 0
end

# Shop UI overlay (Clay)
#: () -> Integer
def draw_shop_clay
  cfont = G.s[32]

  fw_clay_frame_begin

  # Root: full screen with dark overlay, centered
  fw_clay_vbox("sh_root", 0, 0)
    Clay.bg(0.0, 0.0, 0.0, 180.0, 0.0)

    fw_clay_spacer("sh_top")

    fw_clay_hbox_center("sh_mid", 0, 0)
      fw_clay_spacer("sh_l")

      fw_clay_rpg_window("sh_win", 440, 380, 16)
        # Title + Gold
        fw_clay_hbox("sh_hdr", 0, 16)
          fw_clay_text_color("Shop", cfont, 24, 255, 215, 0)
          fw_clay_spacer("sh_hs")
          fw_clay_text_color("Gold:", cfont, 16, 200, 200, 200)
          fw_clay_num(70, G.s[11], cfont, 16, 255, 215, 0)
        Clay.close

        # Shop items
        idx = 0
        while idx < 7
          iid = shop_item_id(idx)
          Clay.open_i("sh_si", idx)
          Clay.layout(0, 8, 8, 4, 4, 8, 1, 0.0, 0, 0.0, 0, 2)
          if G.s[24] == idx
            Clay.bg(60.0, 60.0, 120.0, 200.0, 4.0)
            fw_clay_text_color(">", cfont, 18, 255, 255, 100)
          end
          clay_item_name(iid, cfont, 18)
          fw_clay_spacer("_ss")
          fw_clay_num(71 + idx, item_price(iid), cfont, 16, 255, 215, 0)
          fw_clay_text_color(" G", cfont, 14, 140, 140, 140)
          Clay.close
          idx = idx + 1
        end

        # Exit option
        Clay.open_i("sh_si", 7)
        Clay.layout(0, 8, 8, 4, 4, 8, 1, 0.0, 0, 0.0, 0, 2)
        if G.s[24] == 7
          Clay.bg(60.0, 60.0, 120.0, 200.0, 4.0)
          fw_clay_text_color(">", cfont, 18, 255, 255, 100)
        end
        fw_clay_text("Exit", cfont, 18)
        Clay.close

        fw_clay_text_color("[Enter]Buy [X]Exit", cfont, 14, 140, 140, 140)
      Clay.close

      fw_clay_spacer("sh_r")
    Clay.close

    fw_clay_spacer("sh_bot")

  Clay.close # sh_root

  fw_clay_frame_end
  return 0
end

# ════════════════════════════════════════════════════════════════════
# Section 19: Main Game Loop
# ════════════════════════════════════════════════════════════════════

#: () -> Integer
def main
  Raylib.set_config_flags(Raylib.flag_msaa_4x_hint)
  Raylib.init_window(640, 480, "Konpeito Quest")
  Raylib.set_target_fps(60)

  # Load font (Verdana for clean readable text)
  G.s[30] = Raylib.load_font_ex("/System/Library/Fonts/Supplemental/Verdana.ttf", 32) + 1

  # Initialize Clay UI
  Clay.init(640.0, 480.0)
  G.s[32] = Clay.load_font("/System/Library/Fonts/Supplemental/Verdana.ttf", 32)
  Clay.set_measure_text_raylib

  G.s[0] = 0  # Start at title
  G.s[25] = 0  # blink timer
  anim_counter = 0
  anim_frame = 0

  while Raylib.window_should_close == 0
    fw_tick
    scene = G.s[0]
    G.s[25] = G.s[25] + 1

    # Animation timer
    anim_counter = anim_counter + 1
    if anim_counter > 15
      anim_frame = anim_frame + 1
      anim_counter = 0
    end

    # ── Update ──
    if scene == 0  # Title
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        init_game
      end
      if Raylib.key_pressed?(Raylib.key_space) != 0
        init_game
      end
    end
    if scene == 1
      update_field
    end
    if scene == 2
      update_field
    end
    if scene == 3
      update_field
    end
    if scene == 4
      update_battle
    end
    if scene == 5
      update_menu
    end
    if scene == 6
      update_shop
    end
    if scene == 8  # Game Over
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        G.s[0] = 0
      end
      if Raylib.key_pressed?(Raylib.key_space) != 0
        G.s[0] = 0
      end
    end
    if scene == 9  # Victory
      if Raylib.key_pressed?(Raylib.key_enter) != 0
        G.s[0] = 0
      end
      if Raylib.key_pressed?(Raylib.key_space) != 0
        G.s[0] = 0
      end
    end

    # ── Draw ──
    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)

    scene = G.s[0]
    if scene == 0
      draw_title(G.s[25])
    end
    if scene == 1
      draw_field(anim_frame)
    end
    if scene == 2
      draw_field(anim_frame)
    end
    if scene == 3
      draw_field(anim_frame)
    end
    if scene == 4
      draw_battle_bg
      draw_battle_clay
    end
    if scene == 5
      draw_field(anim_frame)
      draw_menu_clay
    end
    if scene == 6
      draw_field(anim_frame)
      draw_shop_clay
    end
    if scene == 8
      draw_gameover
    end
    if scene == 9
      draw_victory_screen
    end

    Raylib.end_drawing
  end

  Clay.destroy
  Raylib.close_window
  return 0
end

main
