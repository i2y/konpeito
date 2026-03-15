# Pomodoro Timer — KUI Utility App
#
# A practical productivity timer with:
#   - Work / Short Break / Long Break phases
#   - Configurable durations (slider)
#   - Session counter with progress steps
#   - Minimal, focused UI
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_pomodoro/pomodoro \
#     examples/kui_pomodoro/pomodoro.rb
#
# rbs_inline: enabled

require "kui_gui"

# @rbs module Pomo
# @rbs   @s: NativeArray[Integer, 16]
# @rbs end
# Pomo.s slots:
#   [0]  = phase (0=idle, 1=work, 2=short break, 3=long break)
#   [1]  = remaining seconds
#   [2]  = last tick frame
#   [3]  = sessions completed
#   [4]  = total sessions target
#   [5]  = work duration (minutes)
#   [6]  = short break duration (minutes)
#   [7]  = long break duration (minutes)
#   [8]  = tab (0=timer, 1=settings)
#   [9]  = paused (0=running, 1=paused)
#   [10] = total work seconds today
#   [11] = auto-start (0=no, 1=yes)

# ═══════════════════════════════════════
# Timer Logic
# ═══════════════════════════════════════

#: () -> Integer
def tick
  phase = Pomo.s[0]
  if phase == 0
    return 0
  end
  if Pomo.s[9] == 1
    return 0
  end
  frame = KUIState.ids[1]
  elapsed = frame - Pomo.s[2]
  if elapsed >= 60
    Pomo.s[2] = frame
    remain = Pomo.s[1]
    if remain > 0
      Pomo.s[1] = remain - 1
      if phase == 1
        Pomo.s[10] = Pomo.s[10] + 1
      end
    end
    if remain <= 1
      # Phase complete
      if phase == 1
        Pomo.s[3] = Pomo.s[3] + 1
        if Pomo.s[3] >= Pomo.s[4]
          Pomo.s[0] = 3
          Pomo.s[1] = Pomo.s[7] * 60
        else
          Pomo.s[0] = 2
          Pomo.s[1] = Pomo.s[6] * 60
        end
      else
        if phase == 3
          Pomo.s[3] = 0
        end
        Pomo.s[0] = 1
        Pomo.s[1] = Pomo.s[5] * 60
      end
      Pomo.s[2] = frame
      if Pomo.s[11] == 0
        Pomo.s[9] = 1
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Timer Tab — split into small functions to avoid large LLVM IR blocks
# ═══════════════════════════════════════

#: () -> Integer
def draw_phase_label
  phase = Pomo.s[0]
  if phase == 0
    label "Ready to Focus", size: 22
  end
  if phase == 1
    label "Working", size: 22, r: 220, g: 120, b: 80
  end
  if phase == 2
    label "Short Break", size: 22, r: 80, g: 200, b: 160
  end
  if phase == 3
    label "Long Break", size: 22, r: 80, g: 160, b: 220
  end
  return 0
end

#: () -> Integer
def draw_time_display
  remain = Pomo.s[1]
  mins = remain / 60
  secs = remain % 60
  hpanel gap: 0 do
    if mins < 10
      label_num 0, size: 48
    end
    label_num mins, size: 48
    label ":", size: 48
    if secs < 10
      label_num 0, size: 48
    end
    label_num secs, size: 48
  end
  return 0
end

#: () -> Integer
def draw_progress
  phase = Pomo.s[0]
  if phase > 0
    total = Pomo.s[5] * 60
    if phase == 2
      total = Pomo.s[6] * 60
    end
    if phase == 3
      total = Pomo.s[7] * 60
    end
    el = total - Pomo.s[1]
    if phase == 1
      progress_bar el, total, 300, 8, r: 220, g: 120, b: 80
    end
    if phase == 2
      progress_bar el, total, 300, 8, r: 80, g: 200, b: 160
    end
    if phase == 3
      progress_bar el, total, 300, 8, r: 80, g: 160, b: 220
    end
  end
  return 0
end

#: () -> Integer
def draw_controls
  phase = Pomo.s[0]
  hpanel gap: 12 do
    if phase == 0
      button "  Start  ", size: 18 do
        Pomo.s[0] = 1
        Pomo.s[1] = Pomo.s[5] * 60
        Pomo.s[2] = KUIState.ids[1]
        Pomo.s[9] = 0
      end
    else
      if Pomo.s[9] == 1
        button " Resume ", size: 18 do
          Pomo.s[9] = 0
          Pomo.s[2] = KUIState.ids[1]
        end
      else
        button "  Pause  ", size: 18 do
          Pomo.s[9] = 1
        end
      end
      button "  Stop  ", size: 18 do
        Pomo.s[0] = 0
      end
      button "  Skip  ", size: 18 do
        Pomo.s[1] = 1
      end
    end
  end
  return 0
end

#: () -> Integer
def draw_timer_tab
  vpanel pad: 24, gap: 16 do
    draw_phase_label
    draw_time_display
    draw_progress
    draw_controls
    divider
    hpanel gap: 8 do
      label "Sessions:", size: 14
      progress_steps Pomo.s[3], Pomo.s[4], size: 14
    end
    card pad: 12, gap: 4 do
      hpanel gap: 8 do
        label "Total focus time:", size: 14
        label_num Pomo.s[10] / 60, size: 14
        label "min", size: 14
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Settings Tab
# ═══════════════════════════════════════

#: () -> Integer
def draw_settings_tab
  vpanel pad: 24, gap: 12 do
    label "Settings", size: 22

    card pad: 16, gap: 10 do
      hpanel gap: 8 do
        label "Work:", size: 16
        slider Pomo.s[5], 5, 60, w: 180, size: 14 do |nv|
          Pomo.s[5] = nv
        end
        label_num Pomo.s[5], size: 16
        label "min", size: 14
      end

      hpanel gap: 8 do
        label "Short break:", size: 16
        slider Pomo.s[6], 1, 15, w: 180, size: 14 do |nv|
          Pomo.s[6] = nv
        end
        label_num Pomo.s[6], size: 16
        label "min", size: 14
      end

      hpanel gap: 8 do
        label "Long break:", size: 16
        slider Pomo.s[7], 5, 30, w: 180, size: 14 do |nv|
          Pomo.s[7] = nv
        end
        label_num Pomo.s[7], size: 16
        label "min", size: 14
      end

      divider

      hpanel gap: 8 do
        label "Sessions before long break:", size: 16
        number_stepper Pomo.s[4], 2, 8, size: 16 do |delta|
          Pomo.s[4] = Pomo.s[4] + delta
        end
      end

      divider

      switch "Auto-start next phase", Pomo.s[11], size: 16 do
        if Pomo.s[11] == 1
          Pomo.s[11] = 0
        else
          Pomo.s[11] = 1
        end
      end
    end

    spacer

    cpanel do
      button " Reset Progress ", size: 14 do
        Pomo.s[0] = 0
        Pomo.s[1] = 0
        Pomo.s[3] = 0
        Pomo.s[10] = 0
        Pomo.s[9] = 0
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Main Draw + Status Bar
# ═══════════════════════════════════════

#: () -> Integer
def draw_status
  phase = Pomo.s[0]
  if phase == 0
    label "Idle", size: 12
  end
  if phase == 1
    if Pomo.s[9] == 1
      label "Work (Paused)", size: 12
    else
      label "Working...", size: 12
    end
  end
  if phase == 2
    label "Short Break", size: 12
  end
  if phase == 3
    label "Long Break", size: 12
  end
  return 0
end

#: () -> Integer
def draw
  tick
  vpanel pad: 0, gap: 0 do
    tab_bar Pomo.s[8] do
      tab_button "Timer", 0, Pomo.s[8] do
        Pomo.s[8] = 0
      end
      tab_button "Settings", 1, Pomo.s[8] do
        Pomo.s[8] = 1
      end
    end

    if Pomo.s[8] == 0
      draw_timer_tab
    end
    if Pomo.s[8] == 1
      draw_settings_tab
    end

    status_bar do
      status_left do
        draw_status
      end
      status_right do
        hpanel gap: 4 do
          label_num Pomo.s[3], size: 12
          label "/", size: 12
          label_num Pomo.s[4], size: 12
        end
      end
    end
  end
  return 0
end

#: () -> Integer
def main
  Pomo.s[4] = 4
  Pomo.s[5] = 25
  Pomo.s[6] = 5
  Pomo.s[7] = 15

  kui_init("Pomodoro Timer", 480, 520)
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 20)
  kui_theme_dark
  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end
  kui_destroy
  return 0
end

main
