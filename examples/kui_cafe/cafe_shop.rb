# Konpeito Cafe — Shop Tab (Main Screen)
# rbs_inline: enabled

# ════════════════════════════════════════════
# News Markdown
# ════════════════════════════════════════════

#: () -> String
def news_text
  day = Cafe.g[0]
  nid = Cafe.g[15]
  if nid == 0
    return "A regular customer brought friends today!"
  end
  if nid == 1
    return "The weather is great. More people are walking by."
  end
  if nid == 2
    return "A food blogger visited and took photos."
  end
  if nid == 3
    return "Supplier announced a price increase next month."
  end
  if nid == 4
    return "A competitor opened nearby. Stay competitive!"
  end
  if nid == 5
    return "Local festival is happening. Expect more customers!"
  end
  if nid == 6
    return "Staff training improved service quality."
  end
  return "A quiet day. Perfect for planning ahead."
end

# ════════════════════════════════════════════
# Shop Tab Draw
# ════════════════════════════════════════════

#: () -> Integer
def draw_shop_tab
  tab_content pad: 12, gap: 8 do
    draw_shop_news
    draw_shop_status
    draw_shop_inventory
    draw_shop_actions
  end
  return 0
end

#: () -> Integer
def draw_shop_news
  card pad: 10, gap: 4 do
    label "Today's News", size: 18
    divider
    label news_text, size: 14
  end
  return 0
end

#: () -> Integer
def draw_shop_status
  hpanel gap: 12 do
    # Status badge
    phase = Cafe.g[7]
    if phase == 1
      badge "OPEN", r: 80, g: 200, b: 100
    else
      badge "CLOSED", r: 200, g: 80, b: 80
    end

    # Satisfaction
    vpanel gap: 2 do
      label "Satisfaction", size: 12
      progress_bar Cafe.g[2], 100, 120, 10
    end

    # Customers
    hpanel gap: 4 do
      label "Guests:", size: 14
      label_num Cafe.g[3], size: 14
    end

    # Revenue
    hpanel gap: 4 do
      label "Revenue:", size: 14
      label_num Cafe.g[4] / 100, size: 14
    end
  end
  return 0
end

#: () -> Integer
def draw_shop_inventory
  card pad: 10, gap: 4 do
    label "Inventory", size: 16
    divider
    draw_inv_row(0)
    draw_inv_row(1)
    draw_inv_row(2)
    draw_inv_row(3)
    draw_inv_row(4)
    draw_inv_row(5)
  end
  return 0
end

#: (Integer id) -> Integer
def draw_inv_row(id)
  hpanel gap: 8 do
    fixed_panel 100, 16 do
      label inv_name(id), size: 13
    end
    progress_bar inv_qty(id), inv_max(id), 100, 10
    hpanel gap: 4 do
      label_num inv_qty(id), size: 13
      label "/", size: 13
      label_num inv_max(id), size: 13
    end
    button "Buy", size: 12 do
      buy_material(id)
    end
  end
  return 0
end

#: (Integer id) -> Integer
def buy_material(id)
  b = id * 8
  cost = Cafe.inv[b + 2] * 20  # buy 20 units
  if Cafe.g[1] >= cost
    Cafe.g[1] = Cafe.g[1] - cost
    qty = Cafe.inv[b] + 20
    mx = Cafe.inv[b + 1]
    if qty > mx
      qty = mx
    end
    Cafe.inv[b] = qty
    kui_show_toast 0, duration: 90, type: KUI_TOAST_SUCCESS
  else
    kui_show_toast 1, duration: 90, type: KUI_TOAST_DANGER
  end
  return 0
end

#: () -> Integer
def draw_shop_actions
  hpanel gap: 12 do
    spacer
    # Cash display
    hpanel gap: 4 do
      label "Cash:", size: 16
      label_num Cafe.g[1] / 100, size: 16, r: 80, g: 200, b: 100
    end
    spacer
    button ">> Next Day", size: 16 do
      if Cafe.g[16] == 0
        Cafe.g[7] = 1  # phase = open
        sim_day
        Cafe.g[7] = 2  # phase = closed
        # Show toast
        kui_show_toast 2, duration: 120, type: KUI_TOAST_INFO
      end
    end
  end
  return 0
end
