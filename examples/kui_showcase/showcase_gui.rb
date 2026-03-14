# KUI Showcase — GUI version
#
# Demonstrates all v0.8.0 KUI widgets in a rich tabbed GUI app:
#   - Tab bar with 4 tabs (Users, Forms, Settings, About)
#   - Table with dynamic rows + modal dialog
#   - Text input, checkbox, radio, toggle
#   - Selectable list, progress bar, spinner
#   - Status bar with left/right segments
#   - Theme switching (dark/light)
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_showcase/showcase_gui \
#     examples/kui_showcase/showcase_gui.rb
#
# Run:
#   ./examples/kui_showcase/showcase_gui
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

# @rbs module App
# @rbs   @s: NativeArray[Integer, 16]
# @rbs end
# App.s slots:
#   [0] = active tab (0=Users, 1=Forms, 2=Settings, 3=About)
#   [1] = list selection (Forms tab)
#   [2] = modal visible
#   [3] = checkbox 1 (notifications)
#   [4] = checkbox 2 (auto-save)
#   [5] = checkbox 3 (analytics)
#   [6] = radio selection (0=small, 1=medium, 2=large)
#   [7] = toggle 1 (dark mode)
#   [8] = toggle 2 (compact mode)
#   [9] = added user count (0-3)
#   [10] = frame counter
#   [11] = theme (0=dark, 1=light)

# Text buffers:
#   buf 0, 1: modal input fields (name, role)
#   buf 2-7: saved user data (3 users x name/role)

# ── Tab 1: Users ──

#: () -> Integer
def draw_users_tab
  tab_content pad: 16, gap: 8 do
    label "User Directory", size: 22, r: 100, g: 200, b: 255

    # Table
    table_header pad: 8 do
      table_cell 60, pad: 8 do
        label "ID", size: 16, r: 255, g: 255, b: 255
      end
      table_cell 180, pad: 8 do
        label "Name", size: 16, r: 255, g: 255, b: 255
      end
      table_cell 140, pad: 8 do
        label "Role", size: 16, r: 255, g: 255, b: 255
      end
      table_cell 100, pad: 8 do
        label "Status", size: 16, r: 255, g: 255, b: 255
      end
    end

    table_row 0 do
      table_cell 60, pad: 8 do
        label_num 1, size: 16
      end
      table_cell 180, pad: 8 do
        label "Alice Johnson", size: 16
      end
      table_cell 140, pad: 8 do
        label "Admin", size: 16
      end
      table_cell 100, pad: 8 do
        label "Active", size: 16, r: 80, g: 200, b: 100
      end
    end

    table_row 1 do
      table_cell 60, pad: 8 do
        label_num 2, size: 16
      end
      table_cell 180, pad: 8 do
        label "Bob Smith", size: 16
      end
      table_cell 140, pad: 8 do
        label "Editor", size: 16
      end
      table_cell 100, pad: 8 do
        label "Active", size: 16, r: 80, g: 200, b: 100
      end
    end

    table_row 2 do
      table_cell 60, pad: 8 do
        label_num 3, size: 16
      end
      table_cell 180, pad: 8 do
        label "Carol White", size: 16
      end
      table_cell 140, pad: 8 do
        label "Viewer", size: 16
      end
      table_cell 100, pad: 8 do
        label "Offline", size: 16, r: 220, g: 80, b: 80
      end
    end

    table_row 3 do
      table_cell 60, pad: 8 do
        label_num 4, size: 16
      end
      table_cell 180, pad: 8 do
        label "Dave Brown", size: 16
      end
      table_cell 140, pad: 8 do
        label "Editor", size: 16
      end
      table_cell 100, pad: 8 do
        label "Active", size: 16, r: 80, g: 200, b: 100
      end
    end

    # Dynamic rows for added users
    if App.s[9] > 0
      table_row 4 do
        table_cell 60, pad: 8 do
          label_num 5, size: 16
        end
        table_cell 180, pad: 8 do
          kui_textbuf_render 2, size: 16
        end
        table_cell 140, pad: 8 do
          kui_textbuf_render 3, size: 16
        end
        table_cell 100, pad: 8 do
          label "Active", size: 16, r: 80, g: 200, b: 100
        end
      end
    end

    if App.s[9] > 1
      table_row 5 do
        table_cell 60, pad: 8 do
          label_num 6, size: 16
        end
        table_cell 180, pad: 8 do
          kui_textbuf_render 4, size: 16
        end
        table_cell 140, pad: 8 do
          kui_textbuf_render 5, size: 16
        end
        table_cell 100, pad: 8 do
          label "Active", size: 16, r: 80, g: 200, b: 100
        end
      end
    end

    if App.s[9] > 2
      table_row 6 do
        table_cell 60, pad: 8 do
          label_num 7, size: 16
        end
        table_cell 180, pad: 8 do
          kui_textbuf_render 6, size: 16
        end
        table_cell 140, pad: 8 do
          kui_textbuf_render 7, size: 16
        end
        table_cell 100, pad: 8 do
          label "Active", size: 16, r: 80, g: 200, b: 100
        end
      end
    end

    spacer

    hpanel gap: 12 do
      spacer
      if App.s[9] < 3
        button " Add User ", size: 16 do
          App.s[2] = 1
        end
      end
      spacer
    end
  end
  return 0
end

# ── Tab 2: Forms ──

#: () -> Integer
def draw_forms_tab
  tab_content pad: 16, gap: 8 do
    label "Form Controls", size: 22, r: 100, g: 200, b: 255

    divider

    # Search field
    label "Search:", size: 18
    text_input 7, w: 300, size: 16

    divider

    # Checkboxes
    label "Options:", size: 18
    checkbox "Enable notifications", App.s[3], size: 16 do
      if App.s[3] == 0
        App.s[3] = 1
      else
        App.s[3] = 0
      end
    end
    checkbox "Auto-save documents", App.s[4], size: 16 do
      if App.s[4] == 0
        App.s[4] = 1
      else
        App.s[4] = 0
      end
    end
    checkbox "Send analytics", App.s[5], size: 16 do
      if App.s[5] == 0
        App.s[5] = 1
      else
        App.s[5] = 0
      end
    end

    divider

    # Radio buttons
    label "Font size:", size: 18
    radio "Small (12pt)", 0, App.s[6], size: 16 do
      App.s[6] = 0
    end
    radio "Medium (16pt)", 1, App.s[6], size: 16 do
      App.s[6] = 1
    end
    radio "Large (20pt)", 2, App.s[6], size: 16 do
      App.s[6] = 2
    end

    divider

    # Toggles
    toggle "Compact mode", App.s[8], size: 16 do
      if App.s[8] == 0
        App.s[8] = 1
      else
        App.s[8] = 0
      end
    end

    divider

    # Progress bar linked to checkbox count
    checked_count = App.s[3] + App.s[4] + App.s[5]
    hpanel gap: 8 do
      label "Completion:", size: 16
      progress_bar checked_count, 3, 200, 14, r: 80, g: 200, b: 100
      label_num checked_count, size: 16
      label "/3", size: 16
    end

    divider

    # Selectable list
    label "Language:", size: 18
    selectable_list App.s[1], 4 do
      list_item "Ruby", 0, App.s[1], size: 16 do
        App.s[1] = 0
      end
      list_item "Python", 1, App.s[1], size: 16 do
        App.s[1] = 1
      end
      list_item "Rust", 2, App.s[1], size: 16 do
        App.s[1] = 2
      end
      list_item "Go", 3, App.s[1], size: 16 do
        App.s[1] = 3
      end
    end
  end
  return 0
end

# ── Tab 3: Settings ──

#: () -> Integer
def draw_settings_tab
  tab_content pad: 16, gap: 10 do
    label "Settings", size: 22, r: 100, g: 200, b: 255

    card pad: 16, gap: 12 do
      label "Theme", size: 20
      divider

      hpanel gap: 12 do
        button " Dark Theme ", size: 16 do
          App.s[7] = 1
          App.s[11] = 0
          kui_theme_dark
        end
        button " Light Theme ", size: 16 do
          App.s[7] = 0
          App.s[11] = 1
          kui_theme_light
        end
      end

      toggle "Dark mode", App.s[7], size: 16 do
        if App.s[7] == 0
          App.s[7] = 1
          App.s[11] = 0
          kui_theme_dark
        else
          App.s[7] = 0
          App.s[11] = 1
          kui_theme_light
        end
      end
    end

    card pad: 16, gap: 10 do
      label "Preferences", size: 20
      divider

      toggle "Enable notifications", App.s[3], size: 16 do
        if App.s[3] == 0
          App.s[3] = 1
        else
          App.s[3] = 0
        end
      end

      toggle "Auto-save", App.s[4], size: 16 do
        if App.s[4] == 0
          App.s[4] = 1
        else
          App.s[4] = 0
        end
      end
    end
  end
  return 0
end

# ── Tab 4: About ──

#: () -> Integer
def draw_about_tab
  tab_content pad: 16, gap: 10 do
    card pad: 20, gap: 10 do
      label "KUI Framework", size: 24, r: 100, g: 200, b: 255
      divider
      label "Version: 0.8.0", size: 18
      label "A declarative UI DSL for building", size: 16
      label "GUI and TUI applications with", size: 16
      label "a single codebase.", size: 16

      spacer

      hpanel gap: 8 do
        label "Widgets: ", size: 16, r: 120, g: 120, b: 140
        label_num 25, size: 16, r: 100, g: 200, b: 255
      end
      hpanel gap: 8 do
        label "Layouts: ", size: 16, r: 120, g: 120, b: 140
        label_num 6, size: 16, r: 100, g: 200, b: 255
      end
      hpanel gap: 8 do
        label "Backends: ", size: 16, r: 120, g: 120, b: 140
        label_num 2, size: 16, r: 100, g: 200, b: 255
      end

      spacer

      progress_bar 90, 100, 240, 14, r: 80, g: 200, b: 100
      label "Feature completeness: 90%", size: 14, r: 120, g: 120, b: 140
    end

    card pad: 20, gap: 8 do
      label "New in v0.8.0", size: 20, r: 80, g: 200, b: 100
      divider
      label "  Text input with cursor editing", size: 16
      label "  Checkbox, radio, toggle widgets", size: 16
      label "  Tab bar with content switching", size: 16
      label "  Table with header and data rows", size: 16
      label "  Modal dialog overlays", size: 16
      label "  Selectable list with highlight", size: 16
      label "  Spinner animation", size: 16
      label "  Status bar with segments", size: 16
      label "  Focus system (Tab key navigation)", size: 16
    end
  end
  return 0
end

# ── Main Draw ──

#: () -> Integer
def draw
  vpanel pad: 0, gap: 0 do
    # Header
    header pad: 12 do
      label "KUI Showcase", size: 22, r: 255, g: 255, b: 255
      spacer
      spinner size: 18
    end

    # Tab bar
    tab_bar App.s[0] do
      tab_button " Users ", 0, App.s[0], size: 16 do
        App.s[0] = 0
      end
      tab_button " Forms ", 1, App.s[0], size: 16 do
        App.s[0] = 1
      end
      tab_button " Settings ", 2, App.s[0], size: 16 do
        App.s[0] = 2
      end
      tab_button " About ", 3, App.s[0], size: 16 do
        App.s[0] = 3
      end
    end

    divider

    # Tab content
    if App.s[0] == 0
      draw_users_tab
    end
    if App.s[0] == 1
      draw_forms_tab
    end
    if App.s[0] == 2
      draw_settings_tab
    end
    if App.s[0] == 3
      draw_about_tab
    end

    # Modal (add user)
    if App.s[2] == 1
      modal 400, 300, pad: 16, gap: 8 do
        label "Add New User", size: 20, r: 100, g: 200, b: 255
        divider
        label "Name:", size: 16
        text_input 0, w: 300, size: 16
        label "Role:", size: 16
        text_input 1, w: 300, size: 16

        spacer

        hpanel gap: 12 do
          spacer
          button " Save ", size: 16 do
            dst_name = 2 + App.s[9] * 2
            dst_role = 3 + App.s[9] * 2
            kui_textbuf_copy dst_name, 0
            kui_textbuf_copy dst_role, 1
            App.s[9] = App.s[9] + 1
            kui_textbuf_clear 0
            kui_textbuf_clear 1
            App.s[2] = 0
          end
          button " Cancel ", size: 16 do
            App.s[2] = 0
            kui_textbuf_clear 0
            kui_textbuf_clear 1
          end
          spacer
        end
      end
    end

    # Status bar
    status_bar do
      status_left do
        label "KUI Showcase v0.8.0", size: 14, r: 120, g: 120, b: 140
      end
      status_right do
        spinner size: 14
        label " Ready", size: 14, r: 80, g: 200, b: 100
      end
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("KUI Showcase", 900, 650)
  kui_theme_dark
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 20)
  App.s[7] = 1
  App.s[6] = 1

  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end

  kui_destroy
  return 0
end

main
