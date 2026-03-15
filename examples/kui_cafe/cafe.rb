# Konpeito Cafe — Coffee Shop Management Simulation
#
# A turn-based business sim built entirely with KUI DSL (20+ widgets).
# Manage menus, staff, inventory, and finances to grow your cafe.
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_cafe/cafe \
#     examples/kui_cafe/cafe.rb
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"
require_relative "cafe_data"
require_relative "cafe_sim"
require_relative "cafe_shop"
require_relative "cafe_menu"
require_relative "cafe_staff"
require_relative "cafe_finance"

# ════════════════════════════════════════════
# Toast Messages
# ════════════════════════════════════════════

#: () -> Integer
def draw_toasts
  toast_stack do
    toast 0, "Success!", size: 13
    toast 1, "Not enough cash!", size: 13
    toast 2, "Day complete. Check your results!", size: 13
  end
  return 0
end

# ════════════════════════════════════════════
# Game Over Screen
# ════════════════════════════════════════════

#: () -> Integer
def draw_gameover
  cpanel do
    vpanel pad: 40, gap: 16 do
      label "GAME OVER", size: 32, r: 255, g: 80, b: 80
      label "Your cafe went bankrupt!", size: 18
      divider
      hpanel gap: 8 do
        label "Survived:", size: 16
        label_num Cafe.g[0] - 1, size: 16
        label "days", size: 16
      end
      button "Restart", size: 18 do
        init_game_data
      end
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Title Bar
# ════════════════════════════════════════════

#: () -> Integer
def draw_title_bar
  header pad: 8 do
    hpanel gap: 12 do
      label "Konpeito Cafe", size: 20
      spacer
      hpanel gap: 4 do
        label "Day", size: 14
        label_num Cafe.g[0], size: 14
      end
      divider
      hpanel gap: 4 do
        label "Cash:", size: 14
        label_num Cafe.g[1] / 100, size: 14, r: 80, g: 200, b: 100
      end
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Tab Bar
# ════════════════════════════════════════════

#: () -> Integer
def draw_tabs
  tab_bar Cafe.g[6] do
    tab_button "Shop", 0, Cafe.g[6] do
      Cafe.g[6] = 0
    end
    tab_button "Menu", 1, Cafe.g[6] do
      Cafe.g[6] = 1
    end
    tab_button "Staff", 2, Cafe.g[6] do
      Cafe.g[6] = 2
    end
    tab_button "Finance", 3, Cafe.g[6] do
      Cafe.g[6] = 3
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Tab Content Dispatch
# ════════════════════════════════════════════

#: () -> Integer
def draw_tab_content
  t = Cafe.g[6]
  if t == 0
    draw_shop_tab
  end
  if t == 1
    draw_menu_tab
  end
  if t == 2
    draw_staff_tab
  end
  if t == 3
    draw_finance_tab
  end
  return 0
end

# ════════════════════════════════════════════
# Theme based on phase
# ════════════════════════════════════════════

#: () -> Integer
def update_theme
  phase = Cafe.g[7]
  if phase == 0
    kui_theme_light
  else
    kui_theme_dark
  end
  return 0
end

# ════════════════════════════════════════════
# Main Draw
# ════════════════════════════════════════════

#: () -> Integer
def draw
  if Cafe.g[16] == 1
    draw_gameover
    return 0
  end

  vpanel pad: 0, gap: 0 do
    draw_title_bar
    draw_tabs
    scroll_panel pad: 0, gap: 0 do
      draw_tab_content
    end
    # Status bar
    status_bar do
      status_left do
        phase = Cafe.g[7]
        if phase == 0
          badge "Morning", r: 255, g: 200, b: 80
        end
        if phase == 1
          badge "Open", r: 80, g: 200, b: 100
        end
        if phase == 2
          badge "Closed", r: 200, g: 80, b: 80
        end
      end
      status_center do
        label "Konpeito Cafe", size: 11
      end
      status_right do
        hpanel gap: 4 do
          label "Sat:", size: 11
          label_num Cafe.g[2], size: 11
          label "%", size: 11
        end
      end
    end
  end

  # Overlays (rendered outside layout)
  draw_toasts
  draw_hire_modal
  return 0
end

# ════════════════════════════════════════════
# Main Loop
# ════════════════════════════════════════════

#: () -> Integer
def main
  init_game_data

  kui_init("Konpeito Cafe", 850, 650)
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 20)
  kui_theme_light

  while kui_running == 1
    kui_begin_frame
    update_theme
    update_charts
    draw
    kui_end_frame
    Cafe.g[14] = Cafe.g[14] + 1
  end

  kui_destroy
  return 0
end

main
