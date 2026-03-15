# Konpeito Cafe — Finance Tab
# rbs_inline: enabled

# ════════════════════════════════════════════
# Finance Tab Draw
# ════════════════════════════════════════════

#: () -> Integer
def draw_finance_tab
  tab_content pad: 12, gap: 8 do
    draw_finance_charts
    draw_finance_summary
  end
  return 0
end

# ════════════════════════════════════════════
# Charts
# ════════════════════════════════════════════

#: () -> Integer
def draw_finance_charts
  hpanel gap: 12 do
    # Revenue line chart (chart 0)
    card pad: 8, gap: 4 do
      label "Revenue (7 days)", size: 14
      line_chart 0, 250, 150
    end
    # Category pie chart (chart 1)
    card pad: 8, gap: 4 do
      label "Sales Breakdown", size: 14
      pie_chart 1, 150, 150
    end
  end

  # Revenue vs Expense bar chart (chart 2)
  card pad: 8, gap: 4 do
    label "Revenue vs Expense", size: 14
    bar_chart 2, 400, 130
  end
  return 0
end

# ════════════════════════════════════════════
# Update chart data (called each frame)
# ════════════════════════════════════════════

#: () -> Integer
def update_charts
  update_line_chart
  update_pie_chart
  update_bar_chart
  return 0
end

#: () -> Integer
def update_line_chart
  # Chart 0: line chart of daily revenue
  max_rev = 1
  i = 0
  while i < 7
    v = Cafe.hist[i] / 100  # scale down for display
    if v > max_rev
      max_rev = v
    end
    i = i + 1
  end
  kui_chart_init(0, 2, 7, max_rev)
  kui_chart_color(0, 0, 100, 180, 255)
  i = 0
  while i < 7
    kui_chart_set(0, i, Cafe.hist[i] / 100)
    i = i + 1
  end
  return 0
end

#: () -> Integer
def update_pie_chart
  # Chart 1: pie chart of category sales
  # Sum orders by category
  coffee_total = 0
  tea_total = 0
  food_total = 0
  dessert_total = 0
  i = 0
  while i < 8
    if menu_active(i) == 1
      cat = menu_category(i)
      orders = menu_orders(i)
      if cat == 0
        coffee_total = coffee_total + orders
      end
      if cat == 1
        tea_total = tea_total + orders
      end
      if cat == 2
        food_total = food_total + orders
      end
      if cat == 3
        dessert_total = dessert_total + orders
      end
    end
    i = i + 1
  end
  # Ensure at least 1 for display
  if coffee_total + tea_total + food_total + dessert_total == 0
    coffee_total = 1
    tea_total = 1
    food_total = 1
    dessert_total = 1
  end
  kui_chart_init(1, 3, 4, 100)
  kui_chart_set(1, 0, coffee_total)
  kui_chart_set(1, 1, tea_total)
  kui_chart_set(1, 2, food_total)
  kui_chart_set(1, 3, dessert_total)
  kui_chart_color(1, 0, 139, 90, 43)    # Coffee: brown
  kui_chart_color(1, 1, 80, 180, 80)    # Tea: green
  kui_chart_color(1, 2, 220, 180, 80)   # Food: gold
  kui_chart_color(1, 3, 220, 100, 150)  # Dessert: pink
  return 0
end

#: () -> Integer
def update_bar_chart
  # Chart 2: bar chart revenue vs expense (last 7 days interleaved)
  # We use 14 bars: revenue[0..6], expense[0..6] interleaved as pairs
  max_val = 1
  i = 0
  while i < 7
    rv = Cafe.hist[i] / 100
    ev = Cafe.hist[7 + i] / 100
    if rv > max_val
      max_val = rv
    end
    if ev > max_val
      max_val = ev
    end
    i = i + 1
  end
  kui_chart_init(2, 1, 14, max_val)
  i = 0
  while i < 7
    kui_chart_set(2, i * 2, Cafe.hist[i] / 100)
    kui_chart_set(2, i * 2 + 1, Cafe.hist[7 + i] / 100)
    kui_chart_color(2, i * 2, 80, 180, 255)      # Revenue: blue
    kui_chart_color(2, i * 2 + 1, 255, 100, 100)  # Expense: red
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Financial Summary
# ════════════════════════════════════════════

#: () -> Integer
def draw_finance_summary
  card pad: 10, gap: 6 do
    label "Financial Summary", size: 16
    divider

    hpanel gap: 16 do
      vpanel gap: 4 do
        label "Cash", size: 13, r: 140, g: 140, b: 160
        label_num Cafe.g[1] / 100, size: 20, r: 80, g: 200, b: 100
      end
      vpanel gap: 4 do
        label "Today Revenue", size: 13, r: 140, g: 140, b: 160
        label_num Cafe.g[4] / 100, size: 20, r: 100, g: 180, b: 255
      end
      vpanel gap: 4 do
        label "Today Expense", size: 13, r: 140, g: 140, b: 160
        label_num Cafe.g[5] / 100, size: 20, r: 255, g: 100, b: 100
      end
      vpanel gap: 4 do
        label "Profit", size: 13, r: 140, g: 140, b: 160
        profit = (Cafe.g[4] - Cafe.g[5]) / 100
        label_num profit, size: 20
      end
    end

    divider

    # Legend for bar chart
    hpanel gap: 12 do
      badge "Revenue", r: 80, g: 180, b: 255
      badge "Expense", r: 255, g: 100, b: 100
    end

    # Pie legend
    hpanel gap: 8 do
      badge "Coffee", r: 139, g: 90, b: 43
      badge "Tea", r: 80, g: 180, b: 80
      badge "Food", r: 220, g: 180, b: 80
      badge "Dessert", r: 220, g: 100, b: 150
    end
  end
  return 0
end
