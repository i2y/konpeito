# Konpeito Cafe — Menu Tab
# rbs_inline: enabled

# ════════════════════════════════════════════
# Menu Tab Draw
# ════════════════════════════════════════════

#: () -> Integer
def draw_menu_tab
  tab_content pad: 12, gap: 8 do
    draw_menu_table
    draw_menu_editor
  end
  return 0
end

# ════════════════════════════════════════════
# Menu Table
# ════════════════════════════════════════════

#: () -> Integer
def draw_menu_table
  card pad: 10, gap: 4 do
    label "Menu Items", size: 18
    divider

    # Header
    hpanel gap: 0 do
      table_cell 30, pad: 4 do
        label "#", size: 13
      end
      table_cell 100, pad: 4 do
        label "Name", size: 13
      end
      table_cell 70, pad: 4 do
        label "Price", size: 13
      end
      table_cell 70, pad: 4 do
        label "Cost", size: 13
      end
      table_cell 50, pad: 4 do
        label "Pop", size: 13
      end
      table_cell 60, pad: 4 do
        label "Orders", size: 13
      end
      table_cell 70, pad: 4 do
        label "Category", size: 13
      end
    end
    divider

    # Rows
    draw_menu_row(0)
    draw_menu_row(1)
    draw_menu_row(2)
    draw_menu_row(3)
    draw_menu_row(4)
    draw_menu_row(5)
    draw_menu_row(6)
    draw_menu_row(7)
  end
  return 0
end

#: (Integer id) -> Integer
def draw_menu_row(id)
  if menu_active(id) == 0
    return 0
  end
  table_row id, pad: 4 do
    table_cell 30, pad: 4 do
      label_num id + 1, size: 13
    end
    table_cell 100, pad: 4 do
      label menu_name(id), size: 13
    end
    table_cell 70, pad: 4 do
      label_num menu_price(id), size: 13
    end
    table_cell 70, pad: 4 do
      label_num menu_cost(id), size: 13
    end
    table_cell 50, pad: 4 do
      label_num menu_pop(id), size: 13
    end
    table_cell 60, pad: 4 do
      label_num menu_orders(id), size: 13
    end
    table_cell 70, pad: 4 do
      label cat_name(menu_category(id)), size: 13
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Menu Editor (price adjustment)
# ════════════════════════════════════════════

#: () -> Integer
def draw_menu_editor
  card pad: 10, gap: 6 do
    label "Price Adjustment", size: 16
    divider

    # Select menu item
    hpanel gap: 8 do
      label "Item:", size: 14
      draw_menu_select_btns
    end

    sel = Cafe.g[12]
    if menu_active(sel) == 1
      hpanel gap: 8 do
        label "Selected:", size: 14
        label menu_name(sel), size: 14, r: 100, g: 200, b: 255
      end
      # Price slider
      hpanel gap: 8 do
        label "Price:", size: 14
        slider menu_price(sel), 100, 999, w: 200, size: 14 do |nv|
          Cafe.menu[sel * 8 + 1] = nv
        end
        label_num menu_price(sel), size: 14
      end
      # Show profit margin
      hpanel gap: 4 do
        label "Profit:", size: 13, r: 140, g: 140, b: 160
        label_num menu_price(sel) - menu_cost(sel), size: 13, r: 80, g: 200, b: 100
      end
    end

    divider

    # Activate slot 6 or 7
    draw_add_menu_btn
  end
  return 0
end

#: () -> Integer
def draw_menu_select_btns
  i = 0
  while i < 8
    if menu_active(i) == 1
      draw_one_select_btn(i)
    end
    i = i + 1
  end
  return 0
end

#: (Integer i) -> Integer
def draw_one_select_btn(i)
  button menu_name(i), size: 12 do
    Cafe.g[12] = i
  end
  return 0
end

#: () -> Integer
def draw_add_menu_btn
  # Find first inactive slot
  slot = -1
  if menu_active(6) == 0
    slot = 6
  end
  if slot == -1
    if menu_active(7) == 0
      slot = 7
    end
  end
  if slot >= 0
    button "Add New Menu Item", size: 14 do
      set_menu(slot, 1, 400, 150, 50, 0)
      Cafe.g[12] = slot
      kui_show_toast 0, duration: 90, type: KUI_TOAST_SUCCESS
    end
  end
  return 0
end
