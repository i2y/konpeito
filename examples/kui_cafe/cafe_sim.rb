# Konpeito Cafe — Simulation Logic
# rbs_inline: enabled

# ════════════════════════════════════════════
# Pseudo-random (xorshift)
# ════════════════════════════════════════════

#: () -> Integer
def cafe_rand
  s = Cafe.g[9]
  s = s ^ (s * 8192)       # s ^= s << 13 (2^13 = 8192)
  s = s ^ (s / 131072)     # s ^= s >> 17 (2^17 = 131072)
  s = s ^ (s * 32)         # s ^= s << 5  (2^5  = 32)
  if s < 0
    s = 0 - s
  end
  Cafe.g[9] = s
  return s
end

#: (Integer lo, Integer hi) -> Integer
def rand_range(lo, hi)
  r = cafe_rand
  span = hi - lo + 1
  return lo + r % span
end

# ════════════════════════════════════════════
# Count active items / staff
# ════════════════════════════════════════════

#: () -> Integer
def count_active_menu
  n = 0
  i = 0
  while i < 8
    if menu_active(i) == 1
      n = n + 1
    end
    i = i + 1
  end
  return n
end

#: () -> Integer
def count_active_staff
  n = 0
  i = 0
  while i < 4
    if staff_active(i) == 1
      n = n + 1
    end
    i = i + 1
  end
  return n
end

# ════════════════════════════════════════════
# Average staff morale
# ════════════════════════════════════════════

#: () -> Integer
def avg_staff_morale
  total = 0
  cnt = 0
  i = 0
  while i < 4
    if staff_active(i) == 1
      total = total + staff_morale(i)
      cnt = cnt + 1
    end
    i = i + 1
  end
  if cnt == 0
    return 50
  end
  return total / cnt
end

# ════════════════════════════════════════════
# Simulate one day (turn advance)
# ════════════════════════════════════════════

#: () -> Integer
def sim_day
  sim_calc_customers
  sim_orders
  sim_expenses
  sim_satisfaction
  sim_staff_morale
  sim_push_history
  sim_check_gameover
  Cafe.g[0] = Cafe.g[0] + 1  # day++
  Cafe.g[7] = 0               # phase = morning
  sim_pick_news
  return 0
end

# ════════════════════════════════════════════
# Calculate customers
# ════════════════════════════════════════════

#: () -> Integer
def sim_calc_customers
  base = 10
  sat_bonus = Cafe.g[2] / 10
  staff_bonus = count_active_staff * 3
  rnd = rand_range(-3, 3)
  cust = base + sat_bonus + staff_bonus + rnd
  if cust < 1
    cust = 1
  end
  if cust > 60
    cust = 60
  end
  Cafe.g[3] = cust
  return 0
end

# ════════════════════════════════════════════
# Simulate orders and revenue
# ════════════════════════════════════════════

#: () -> Integer
def sim_orders
  cust = Cafe.g[3]
  total_rev = 0
  # Reset orders
  i = 0
  while i < 8
    Cafe.menu[i * 8 + 4] = 0
    i = i + 1
  end
  # Each customer orders one item
  sim_order_loop(cust)
  # Tally revenue
  total_rev = sim_tally_revenue
  Cafe.g[4] = total_rev
  return 0
end

#: (Integer cust) -> Integer
def sim_order_loop(cust)
  c = 0
  while c < cust
    sim_one_order
    c = c + 1
  end
  return 0
end

#: () -> Integer
def sim_one_order
  # Weighted random by popularity
  total_pop = 0
  i = 0
  while i < 8
    if menu_active(i) == 1
      total_pop = total_pop + menu_pop(i)
    end
    i = i + 1
  end
  if total_pop <= 0
    return 0
  end
  pick = rand_range(0, total_pop - 1)
  acc = 0
  j = 0
  while j < 8
    if menu_active(j) == 1
      acc = acc + menu_pop(j)
      if pick < acc
        Cafe.menu[j * 8 + 4] = Cafe.menu[j * 8 + 4] + 1
        return 0
      end
    end
    j = j + 1
  end
  return 0
end

#: () -> Integer
def sim_tally_revenue
  total = 0
  i = 0
  while i < 8
    if menu_active(i) == 1
      orders = menu_orders(i)
      total = total + orders * menu_price(i)
    end
    i = i + 1
  end
  return total
end

# ════════════════════════════════════════════
# Expenses: COGS + staff salary + fixed
# ════════════════════════════════════════════

#: () -> Integer
def sim_expenses
  cogs = sim_calc_cogs
  salaries = sim_calc_salaries
  fixed = 2000  # daily fixed cost (rent etc)
  total = cogs + salaries + fixed
  Cafe.g[5] = total
  Cafe.g[1] = Cafe.g[1] + Cafe.g[4] - total  # cash += revenue - expense
  sim_consume_inventory
  return 0
end

#: () -> Integer
def sim_calc_cogs
  total = 0
  i = 0
  while i < 8
    if menu_active(i) == 1
      total = total + menu_orders(i) * menu_cost(i)
    end
    i = i + 1
  end
  return total
end

#: () -> Integer
def sim_calc_salaries
  total = 0
  i = 0
  while i < 4
    if staff_active(i) == 1
      total = total + staff_salary(i)
    end
    i = i + 1
  end
  return total
end

#: () -> Integer
def sim_consume_inventory
  # Coffee items consume beans, milk, sugar
  coffee_orders = menu_orders(0) + menu_orders(1) + menu_orders(2)
  tea_orders = menu_orders(3)
  food_orders = menu_orders(4)
  dessert_orders = menu_orders(5) + menu_orders(6) + menu_orders(7)

  # Beans
  use0 = coffee_orders * 2
  Cafe.inv[3] = use0  # daily_usage
  Cafe.inv[0] = max_i(0, Cafe.inv[0] - use0)

  # Milk
  use1 = coffee_orders + dessert_orders
  Cafe.inv[8 + 3] = use1
  Cafe.inv[8] = max_i(0, Cafe.inv[8] - use1)

  # Sugar
  use2 = coffee_orders + tea_orders + dessert_orders
  Cafe.inv[16 + 3] = use2
  Cafe.inv[16] = max_i(0, Cafe.inv[16] - use2)

  # Tea leaves
  use3 = tea_orders * 2
  Cafe.inv[24 + 3] = use3
  Cafe.inv[24] = max_i(0, Cafe.inv[24] - use3)

  # Flour
  use4 = food_orders * 2 + dessert_orders
  Cafe.inv[32 + 3] = use4
  Cafe.inv[32] = max_i(0, Cafe.inv[32] - use4)

  # Cream
  use5 = dessert_orders * 2 + coffee_orders
  Cafe.inv[40 + 3] = use5
  Cafe.inv[40] = max_i(0, Cafe.inv[40] - use5)

  return 0
end

# ════════════════════════════════════════════
# Satisfaction
# ════════════════════════════════════════════

#: () -> Integer
def sim_satisfaction
  # Quality: average of staff skill
  skill_avg = 0
  cnt = 0
  i = 0
  while i < 4
    if staff_active(i) == 1
      skill_avg = skill_avg + staff_skill(i)
      cnt = cnt + 1
    end
    i = i + 1
  end
  if cnt > 0
    skill_avg = skill_avg / cnt
  end
  # Morale bonus
  morale_avg = avg_staff_morale
  delta = (skill_avg - 50) / 10 + (morale_avg - 50) / 20
  # Inventory penalty: if any material < 10, -5
  inv_pen = sim_inv_penalty
  delta = delta - inv_pen
  sat = Cafe.g[2] + delta
  if sat > 100
    sat = 100
  end
  if sat < 0
    sat = 0
  end
  Cafe.g[2] = sat
  return 0
end

#: () -> Integer
def sim_inv_penalty
  pen = 0
  i = 0
  while i < 6
    if Cafe.inv[i * 8] < 10
      pen = pen + 3
    end
    i = i + 1
  end
  return pen
end

# ════════════════════════════════════════════
# Staff morale drift
# ════════════════════════════════════════════

#: () -> Integer
def sim_staff_morale
  i = 0
  while i < 4
    if staff_active(i) == 1
      m = staff_morale(i)
      drift = rand_range(-3, 3)
      m = m + drift
      if m > 100
        m = 100
      end
      if m < 10
        m = 10
      end
      Cafe.staff[i * 8 + 3] = m
    end
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Push history (shift left, add today)
# ════════════════════════════════════════════

#: () -> Integer
def sim_push_history
  shift_hist(0)   # revenue
  shift_hist(7)   # expense
  shift_hist(14)  # customers
  shift_hist(21)  # satisfaction
  Cafe.hist[6] = Cafe.g[4]   # today's revenue
  Cafe.hist[13] = Cafe.g[5]  # today's expense
  Cafe.hist[20] = Cafe.g[3]  # today's customers
  Cafe.hist[27] = Cafe.g[2]  # today's satisfaction
  return 0
end

#: (Integer base) -> Integer
def shift_hist(base)
  i = 0
  while i < 6
    Cafe.hist[base + i] = Cafe.hist[base + i + 1]
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Game over check
# ════════════════════════════════════════════

#: () -> Integer
def sim_check_gameover
  if Cafe.g[1] < 0
    Cafe.g[16] = 1
  end
  return 0
end

# ════════════════════════════════════════════
# News generation
# ════════════════════════════════════════════

#: () -> Integer
def sim_pick_news
  Cafe.g[15] = rand_range(0, 7)
  return 0
end
