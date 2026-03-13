# KUI Dashboard — GUI version
#
# Demonstrates: sidebar, card, progress_bar, menu_item, header/footer,
#               multi-page navigation, theme switching.
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_dashboard/dashboard_gui \
#     examples/kui_dashboard/dashboard_gui.rb
#
# Run:
#   ./examples/kui_dashboard/dashboard_gui
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

# @rbs module DS
# @rbs   @s: NativeArray[Integer, 16]
# @rbs end

# DS.s slots:
#   [0] = page (0=home, 1=stats, 2=settings)
#   [1] = cursor
#   [2] = task_done (simulated completed tasks)
#   [3] = task_total (simulated total tasks)
#   [4] = cpu_usage (0-100)
#   [5] = mem_usage (0-100)
#   [6] = frame_counter
#   [7] = theme (0=dark, 1=light)

#: () -> Integer
def draw_home
  label "Welcome to KUI Dashboard", size: 28

  hpanel gap: 16 do
    card pad: 16, gap: 8 do
      label "Tasks", size: 20, r: 100, g: 200, b: 255
      hpanel gap: 8 do
        label_num DS.s[2], size: 24
        label " / ", size: 24
        label_num DS.s[3], size: 24
      end
      progress_bar DS.s[2], DS.s[3], 180, 12
    end

    card pad: 16, gap: 8 do
      label "CPU Usage", size: 20, r: 255, g: 200, b: 80
      hpanel gap: 4 do
        label_num DS.s[4], size: 24
        label "%", size: 24
      end
      progress_bar DS.s[4], 100, 180, 12, r: 255, g: 180, b: 60
    end

    card pad: 16, gap: 8 do
      label "Memory", size: 20, r: 80, g: 220, b: 120
      hpanel gap: 4 do
        label_num DS.s[5], size: 24
        label "%", size: 24
      end
      progress_bar DS.s[5], 100, 180, 12, r: 80, g: 200, b: 100
    end
  end

  spacer

  card gap: 6 do
    label "Recent Activity", size: 20
    divider
    label "  Build #142 passed", size: 16, r: 80, g: 200, b: 100
    label "  Deploy to staging complete", size: 16, r: 100, g: 180, b: 255
    label "  3 new issues assigned", size: 16, r: 255, g: 200, b: 80
    label "  Code review requested", size: 16
  end
  return 0
end

#: () -> Integer
def draw_stats
  label "Statistics", size: 28

  hpanel gap: 16 do
    vpanel gap: 8 do
      card pad: 16, gap: 6 do
        label "Performance Metrics", size: 20
        divider

        hpanel gap: 8 do
          label "Requests/sec:", size: 16
          label_num 1247, size: 16, r: 80, g: 200, b: 255
        end
        hpanel gap: 8 do
          label "Avg latency:", size: 16
          label_num 42, size: 16, r: 80, g: 200, b: 255
          label "ms", size: 16
        end
        hpanel gap: 8 do
          label "Error rate:", size: 16
          label_num 0, size: 16, r: 80, g: 220, b: 100
          label "%", size: 16
        end
      end
    end

    vpanel gap: 8 do
      card pad: 16, gap: 6 do
        label "System Health", size: 20
        divider

        hpanel gap: 8 do
          label "Uptime:", size: 16
          label_num 99, size: 16, r: 80, g: 220, b: 100
          label "%", size: 16
        end
        hpanel gap: 8 do
          label "Disk:", size: 16
          progress_bar 67, 100, 120, 10, r: 255, g: 180, b: 60
          label_num 67, size: 16
          label "%", size: 16
        end
        hpanel gap: 8 do
          label "Network:", size: 16
          label "OK", size: 16, r: 80, g: 220, b: 100
        end
      end
    end
  end
  return 0
end

#: () -> Integer
def draw_settings
  label "Settings", size: 28

  card pad: 16, gap: 12 do
    label "Theme", size: 20
    divider

    hpanel gap: 12 do
      button " Dark Theme ", size: 16 do
        DS.s[7] = 0
        kui_theme_dark
      end
      button " Light Theme ", size: 16 do
        DS.s[7] = 1
        kui_theme_light
      end
    end
  end

  spacer

  card pad: 16, gap: 8 do
    label "About", size: 20
    divider
    label "KUI Dashboard Demo", size: 16
    label "Built with Konpeito + KUI Framework", size: 14, r: 140, g: 140, b: 160
    label "Backend: Clay + Raylib (GUI)", size: 14, r: 140, g: 140, b: 160
  end
  return 0
end

#: () -> Integer
def draw_page
  page = DS.s[0]
  if page == 0
    draw_home
  end
  if page == 1
    draw_stats
  end
  if page == 2
    draw_settings
  end
  return 0
end

#: () -> Integer
def draw
  hpanel do
    sidebar 220, pad: 12, gap: 4 do
      label "Dashboard", size: 22, r: 100, g: 180, b: 255
      divider
      menu_item "Home", 0, DS.s[0], size: 18
      menu_item "Statistics", 1, DS.s[0], size: 18
      menu_item "Settings", 2, DS.s[0], size: 18
    end

    vpanel pad: 20, gap: 16 do
      draw_page
    end
  end
  return 0
end

#: () -> Integer
def update_sim
  DS.s[6] = DS.s[6] + 1
  # Simulate changing values every 60 frames
  if DS.s[6] % 60 == 0
    DS.s[4] = 30 + (DS.s[6] / 60) % 50
    DS.s[5] = 45 + (DS.s[6] / 120) % 30
    if DS.s[2] < DS.s[3]
      if DS.s[6] % 180 == 0
        DS.s[2] = DS.s[2] + 1
      end
    end
  end

  # Handle menu_item clicks via keyboard
  key = kui_key_pressed
  if key == KUI_KEY_UP
    if DS.s[0] > 0
      DS.s[0] = DS.s[0] - 1
    end
  end
  if key == KUI_KEY_DOWN
    if DS.s[0] < 2
      DS.s[0] = DS.s[0] + 1
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("KUI Dashboard", 900, 600)
  kui_theme_dark
  DS.s[0] = 0
  DS.s[2] = 7
  DS.s[3] = 12
  DS.s[4] = 42
  DS.s[5] = 58
  DS.s[6] = 0
  DS.s[7] = 0

  while kui_running == 1
    kui_begin_frame
    draw
    update_sim
    kui_end_frame
  end

  kui_destroy
  return 0
end

main
