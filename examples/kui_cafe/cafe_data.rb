# Konpeito Cafe — Data Setup & Accessors
# rbs_inline: enabled

# ── Cafe.g layout ──
# [0]=day [1]=cash [2]=satisfaction [3]=customers_today
# [4]=revenue_today [5]=expense_today [6]=active_tab [7]=phase
# [8]=toast_type [9]=rng_seed [10]=show_modal [11]=modal_type
# [12]=selected_menu [13]=edit_price [14]=frame_count
# [15]=news_id [16]=game_over

# ── Cafe.menu layout (8 items x 8 slots) ──
# [base+0]=active [base+1]=price(x100) [base+2]=cost(x100)
# [base+3]=popularity [base+4]=orders_today [base+5]=textbuf_id
# [base+6]=category [base+7]=reserved

# ── Cafe.staff layout (4 staff x 8 slots) ──
# [base+0]=active [base+1]=skill [base+2]=salary
# [base+3]=morale [base+4]=textbuf_id [base+5-7]=reserved

# ── Cafe.inv layout (6 materials x 8 slots) ──
# [base+0]=quantity [base+1]=max_quantity [base+2]=unit_price
# [base+3]=daily_usage [base+4]=textbuf_id [base+5-7]=reserved

# ── Cafe.hist layout (7 days) ──
# [0-6]=daily_revenue [7-13]=daily_expense
# [14-20]=daily_customers [21-27]=daily_satisfaction

# ════════════════════════════════════════════
# Menu Helpers
# ════════════════════════════════════════════

#: (Integer id) -> Integer
def menu_base(id)
  return id * 8
end

#: (Integer id) -> Integer
def menu_active(id)
  return Cafe.menu[id * 8]
end

#: (Integer id) -> Integer
def menu_price(id)
  return Cafe.menu[id * 8 + 1]
end

#: (Integer id) -> Integer
def menu_cost(id)
  return Cafe.menu[id * 8 + 2]
end

#: (Integer id) -> Integer
def menu_pop(id)
  return Cafe.menu[id * 8 + 3]
end

#: (Integer id) -> Integer
def menu_orders(id)
  return Cafe.menu[id * 8 + 4]
end

#: (Integer id) -> Integer
def menu_category(id)
  return Cafe.menu[id * 8 + 6]
end

# ════════════════════════════════════════════
# Staff Helpers
# ════════════════════════════════════════════

#: (Integer id) -> Integer
def staff_active(id)
  return Cafe.staff[id * 8]
end

#: (Integer id) -> Integer
def staff_skill(id)
  return Cafe.staff[id * 8 + 1]
end

#: (Integer id) -> Integer
def staff_salary(id)
  return Cafe.staff[id * 8 + 2]
end

#: (Integer id) -> Integer
def staff_morale(id)
  return Cafe.staff[id * 8 + 3]
end

# ════════════════════════════════════════════
# Inventory Helpers
# ════════════════════════════════════════════

#: (Integer id) -> Integer
def inv_qty(id)
  return Cafe.inv[id * 8]
end

#: (Integer id) -> Integer
def inv_max(id)
  return Cafe.inv[id * 8 + 1]
end

#: (Integer id) -> Integer
def inv_price(id)
  return Cafe.inv[id * 8 + 2]
end

# ════════════════════════════════════════════
# Simple max/min
# ════════════════════════════════════════════

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

# ════════════════════════════════════════════
# Initialize all game data
# ════════════════════════════════════════════

#: () -> Integer
def init_game_data
  # Game state
  Cafe.g[0] = 1       # day
  Cafe.g[1] = 500000  # cash = 5000.00 (x100)
  Cafe.g[2] = 70      # satisfaction
  Cafe.g[3] = 0       # customers_today
  Cafe.g[4] = 0       # revenue_today
  Cafe.g[5] = 0       # expense_today
  Cafe.g[6] = 0       # active_tab (Shop)
  Cafe.g[7] = 0       # phase (morning)
  Cafe.g[8] = 0       # toast_type
  Cafe.g[9] = 42      # rng_seed
  Cafe.g[10] = 0      # show_modal
  Cafe.g[11] = 0      # modal_type
  Cafe.g[12] = 0      # selected_menu
  Cafe.g[13] = 450    # edit_price (slider)
  Cafe.g[14] = 0      # frame_count
  Cafe.g[15] = 0      # news_id
  Cafe.g[16] = 0      # game_over

  init_menu_data
  init_staff_data
  init_inv_data
  init_hist_data
  return 0
end

#: () -> Integer
def init_menu_data
  # Latte: active, price=450, cost=150, pop=85, cat=coffee
  set_menu(0, 1, 450, 150, 85, 0)
  # Cappuccino: price=400, cost=130, pop=72, cat=coffee
  set_menu(1, 1, 400, 130, 72, 0)
  # Espresso: price=350, cost=100, pop=60, cat=coffee
  set_menu(2, 1, 350, 100, 60, 0)
  # Green Tea: price=380, cost=80, pop=55, cat=tea
  set_menu(3, 1, 380, 80, 55, 1)
  # Croissant: price=300, cost=120, pop=65, cat=food
  set_menu(4, 1, 300, 120, 65, 2)
  # Cheesecake: price=500, cost=200, pop=78, cat=dessert
  set_menu(5, 1, 500, 200, 78, 3)
  # Slots 6-7 inactive
  set_menu(6, 0, 0, 0, 0, 0)
  set_menu(7, 0, 0, 0, 0, 0)
  return 0
end

#: (Integer id, Integer active, Integer price, Integer cost, Integer pop, Integer cat) -> Integer
def set_menu(id, active, price, cost, pop, cat)
  b = id * 8
  Cafe.menu[b] = active
  Cafe.menu[b + 1] = price
  Cafe.menu[b + 2] = cost
  Cafe.menu[b + 3] = pop
  Cafe.menu[b + 4] = 0
  Cafe.menu[b + 5] = 16 + id  # textbuf IDs 16-23
  Cafe.menu[b + 6] = cat
  return 0
end

#: () -> Integer
def init_staff_data
  # Yuki: active, skill=80, salary=5000, morale=90
  set_staff(0, 1, 80, 5000, 90)
  # Haru: active, skill=60, salary=4000, morale=75
  set_staff(1, 1, 60, 4000, 75)
  # Slots 2-3 inactive
  set_staff(2, 0, 0, 0, 0)
  set_staff(3, 0, 0, 0, 0)
  return 0
end

#: (Integer id, Integer active, Integer skill, Integer salary, Integer morale) -> Integer
def set_staff(id, active, skill, salary, morale)
  b = id * 8
  Cafe.staff[b] = active
  Cafe.staff[b + 1] = skill
  Cafe.staff[b + 2] = salary
  Cafe.staff[b + 3] = morale
  Cafe.staff[b + 4] = 24 + id  # textbuf IDs 24-27
  return 0
end

#: () -> Integer
def init_inv_data
  # Coffee Beans: qty=80, max=100, unit_price=50
  set_inv(0, 80, 100, 50)
  # Milk: qty=60, max=100, unit_price=30
  set_inv(1, 60, 100, 30)
  # Sugar: qty=40, max=100, unit_price=20
  set_inv(2, 40, 100, 20)
  # Tea Leaves: qty=50, max=100, unit_price=40
  set_inv(3, 50, 100, 40)
  # Flour: qty=45, max=100, unit_price=35
  set_inv(4, 45, 100, 35)
  # Cream: qty=55, max=100, unit_price=45
  set_inv(5, 55, 100, 45)
  return 0
end

#: (Integer id, Integer qty, Integer mx, Integer price) -> Integer
def set_inv(id, qty, mx, price)
  b = id * 8
  Cafe.inv[b] = qty
  Cafe.inv[b + 1] = mx
  Cafe.inv[b + 2] = price
  Cafe.inv[b + 3] = 0
  Cafe.inv[b + 4] = 28 + id  # textbuf IDs 28-31 (only 6 materials, fits)
  return 0
end

#: () -> Integer
def init_hist_data
  i = 0
  while i < 64
    Cafe.hist[i] = 0
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Category name
# ════════════════════════════════════════════

#: (Integer cat) -> String
def cat_name(cat)
  if cat == 0
    return "Coffee"
  end
  if cat == 1
    return "Tea"
  end
  if cat == 2
    return "Food"
  end
  return "Dessert"
end

# ════════════════════════════════════════════
# Inventory name
# ════════════════════════════════════════════

#: (Integer id) -> String
def inv_name(id)
  if id == 0
    return "Coffee Beans"
  end
  if id == 1
    return "Milk"
  end
  if id == 2
    return "Sugar"
  end
  if id == 3
    return "Tea Leaves"
  end
  if id == 4
    return "Flour"
  end
  return "Cream"
end

# ════════════════════════════════════════════
# Menu item name
# ════════════════════════════════════════════

#: (Integer id) -> String
def menu_name(id)
  if id == 0
    return "Latte"
  end
  if id == 1
    return "Cappuccino"
  end
  if id == 2
    return "Espresso"
  end
  if id == 3
    return "Green Tea"
  end
  if id == 4
    return "Croissant"
  end
  if id == 5
    return "Cheesecake"
  end
  if id == 6
    return "Special A"
  end
  return "Special B"
end

# ════════════════════════════════════════════
# Staff name
# ════════════════════════════════════════════

#: (Integer id) -> String
def staff_name(id)
  if id == 0
    return "Yuki"
  end
  if id == 1
    return "Haru"
  end
  if id == 2
    return "Sora"
  end
  return "Rin"
end
