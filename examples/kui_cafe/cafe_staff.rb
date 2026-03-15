# Konpeito Cafe — Staff Tab
# rbs_inline: enabled

# ════════════════════════════════════════════
# Staff Tab Draw
# ════════════════════════════════════════════

#: () -> Integer
def draw_staff_tab
  tab_content pad: 12, gap: 8 do
    draw_staff_table
    draw_hire_section
  end
  return 0
end

# ════════════════════════════════════════════
# Staff Table
# ════════════════════════════════════════════

#: () -> Integer
def draw_staff_table
  card pad: 10, gap: 4 do
    label "Staff", size: 18
    divider

    # Header
    hpanel gap: 0 do
      table_cell 80, pad: 4 do
        label "Name", size: 13
      end
      table_cell 100, pad: 4 do
        label "Skill", size: 13
      end
      table_cell 100, pad: 4 do
        label "Morale", size: 13
      end
      table_cell 80, pad: 4 do
        label "Salary", size: 13
      end
    end
    divider

    draw_staff_row(0)
    draw_staff_row(1)
    draw_staff_row(2)
    draw_staff_row(3)
  end
  return 0
end

#: (Integer id) -> Integer
def draw_staff_row(id)
  if staff_active(id) == 0
    return 0
  end
  table_row id, pad: 4 do
    table_cell 80, pad: 4 do
      label staff_name(id), size: 13
    end
    table_cell 100, pad: 4 do
      progress_bar staff_skill(id), 100, 60, 8
      label_num staff_skill(id), size: 12
    end
    table_cell 100, pad: 4 do
      progress_bar staff_morale(id), 100, 60, 8, r: 80, g: 200, b: 100
      label_num staff_morale(id), size: 12
    end
    table_cell 80, pad: 4 do
      label_num staff_salary(id), size: 13
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Salary Adjustment
# ════════════════════════════════════════════

#: () -> Integer
def draw_hire_section
  card pad: 10, gap: 6 do
    label "Management", size: 16
    divider

    # Salary sliders for active staff
    draw_salary_adj(0)
    draw_salary_adj(1)
    draw_salary_adj(2)
    draw_salary_adj(3)

    divider

    # Hire button
    draw_hire_btn
  end
  return 0
end

#: (Integer id) -> Integer
def draw_salary_adj(id)
  if staff_active(id) == 0
    return 0
  end
  hpanel gap: 8 do
    fixed_panel 60, 16 do
      label staff_name(id), size: 13
    end
    label "Salary:", size: 13
    slider staff_salary(id), 2000, 8000, w: 150, size: 13 do |nv|
      Cafe.staff[id * 8 + 2] = nv
    end
    label_num staff_salary(id), size: 13
  end
  return 0
end

#: () -> Integer
def draw_hire_btn
  # Find first inactive slot
  slot = find_hire_slot
  if slot >= 0
    hpanel gap: 8 do
      label "Hire:", size: 14
      label staff_name(slot), size: 14
      label "(Skill:", size: 13, r: 140, g: 140, b: 160
      hire_skill = 40 + slot * 10
      label_num hire_skill, size: 13, r: 140, g: 140, b: 160
      label ")", size: 13, r: 140, g: 140, b: 160
      button "Hire", size: 14 do
        Cafe.g[10] = 1   # show modal
        Cafe.g[11] = slot # store which staff to hire
      end
    end
  else
    label "All positions filled!", size: 14, r: 140, g: 140, b: 160
  end
  return 0
end

#: () -> Integer
def find_hire_slot
  i = 0
  while i < 4
    if staff_active(i) == 0
      return i
    end
    i = i + 1
  end
  return -1
end

# ════════════════════════════════════════════
# Hire Confirmation Modal
# ════════════════════════════════════════════

#: () -> Integer
def draw_hire_modal
  if Cafe.g[10] == 1
    slot = Cafe.g[11]
    confirm_dialog "Hire Staff?", "Hire a new staff member?", w: 380, h: 180 do |action|
      if action == :confirm
        hire_skill = 40 + slot * 10
        set_staff(slot, 1, hire_skill, 4000, 70)
        Cafe.g[10] = 0
        kui_show_toast 0, duration: 90, type: KUI_TOAST_SUCCESS
      end
      if action == :cancel
        Cafe.g[10] = 0
      end
    end
  end
  return 0
end
