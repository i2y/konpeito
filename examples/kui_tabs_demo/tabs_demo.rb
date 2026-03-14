# KUI Tabs & Table Demo — TUI version
#
# Demonstrates:
#   - Tab bar with content switching
#   - Table with header and alternating rows
#   - Modal dialog
#   - Selectable list
#   - Status bar with segments
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_tabs_demo/tabs_demo \
#     examples/kui_tabs_demo/tabs_demo.rb
#
# Run:
#   ./examples/kui_tabs_demo/tabs_demo
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_tui"

# @rbs module TabState
# @rbs   @s: NativeArray[Integer, 16]
# @rbs end
# TabState.s slots:
#   [0] = active tab (0=Users, 1=Settings, 2=About)
#   [1] = list selection
#   [2] = modal visible
#   [3] = setting 1 toggle
#   [4] = setting 2 toggle
#   [5] = added user count (0-3, uses text buf pairs 2-7)

#: () -> Integer
def draw_users_tab
  tab_content pad: 1, gap: 0 do
    label "User Directory", size: 1

    # Table
    table_header pad: 1 do
      table_cell 4, pad: 1 do
        label "ID", size: 1, r: 255, g: 255, b: 255
      end
      table_cell 15, pad: 1 do
        label "Name", size: 1, r: 255, g: 255, b: 255
      end
      table_cell 10, pad: 1 do
        label "Role", size: 1, r: 255, g: 255, b: 255
      end
      table_cell 8, pad: 1 do
        label "Status", size: 1, r: 255, g: 255, b: 255
      end
    end

    table_row 0 do
      table_cell 4, pad: 1 do
        label_num 1, size: 1
      end
      table_cell 15, pad: 1 do
        label "Alice Johnson", size: 1
      end
      table_cell 10, pad: 1 do
        label "Admin", size: 1
      end
      table_cell 8, pad: 1 do
        label "Active", size: 1, r: 80, g: 200, b: 100
      end
    end

    table_row 1 do
      table_cell 4, pad: 1 do
        label_num 2, size: 1
      end
      table_cell 15, pad: 1 do
        label "Bob Smith", size: 1
      end
      table_cell 10, pad: 1 do
        label "Editor", size: 1
      end
      table_cell 8, pad: 1 do
        label "Active", size: 1, r: 80, g: 200, b: 100
      end
    end

    table_row 2 do
      table_cell 4, pad: 1 do
        label_num 3, size: 1
      end
      table_cell 15, pad: 1 do
        label "Carol White", size: 1
      end
      table_cell 10, pad: 1 do
        label "Viewer", size: 1
      end
      table_cell 8, pad: 1 do
        label "Offline", size: 1, r: 220, g: 80, b: 80
      end
    end

    table_row 3 do
      table_cell 4, pad: 1 do
        label_num 4, size: 1
      end
      table_cell 15, pad: 1 do
        label "Dave Brown", size: 1
      end
      table_cell 10, pad: 1 do
        label "Editor", size: 1
      end
      table_cell 8, pad: 1 do
        label "Active", size: 1, r: 80, g: 200, b: 100
      end
    end

    # Dynamic rows for added users
    if TabState.s[5] > 0
      table_row 4 do
        table_cell 4, pad: 1 do
          label_num 5, size: 1
        end
        table_cell 15, pad: 1 do
          kui_textbuf_render 2, size: 1
        end
        table_cell 10, pad: 1 do
          kui_textbuf_render 3, size: 1
        end
        table_cell 8, pad: 1 do
          label "Active", size: 1, r: 80, g: 200, b: 100
        end
      end
    end

    if TabState.s[5] > 1
      table_row 5 do
        table_cell 4, pad: 1 do
          label_num 6, size: 1
        end
        table_cell 15, pad: 1 do
          kui_textbuf_render 4, size: 1
        end
        table_cell 10, pad: 1 do
          kui_textbuf_render 5, size: 1
        end
        table_cell 8, pad: 1 do
          label "Active", size: 1, r: 80, g: 200, b: 100
        end
      end
    end

    if TabState.s[5] > 2
      table_row 6 do
        table_cell 4, pad: 1 do
          label_num 7, size: 1
        end
        table_cell 15, pad: 1 do
          kui_textbuf_render 6, size: 1
        end
        table_cell 10, pad: 1 do
          kui_textbuf_render 7, size: 1
        end
        table_cell 8, pad: 1 do
          label "Active", size: 1, r: 80, g: 200, b: 100
        end
      end
    end

    spacer

    hpanel gap: 2 do
      spacer
      if TabState.s[5] < 3
        button " Add User ", size: 1 do
          TabState.s[2] = 1
        end
      end
      spacer
    end
  end
  return 0
end

#: () -> Integer
def draw_settings_tab
  tab_content pad: 1, gap: 1 do
    label "Application Settings", size: 1

    divider

    toggle "Enable notifications", TabState.s[3], size: 1 do
      if TabState.s[3] == 0
        TabState.s[3] = 1
      else
        TabState.s[3] = 0
      end
    end

    toggle "Auto-save", TabState.s[4], size: 1 do
      if TabState.s[4] == 0
        TabState.s[4] = 1
      else
        TabState.s[4] = 0
      end
    end

    divider

    label "Theme:", size: 1
    selectable_list TabState.s[1], 2 do
      list_item "Dark Theme", 0, TabState.s[1], size: 1 do
        TabState.s[1] = 0
      end
      list_item "Light Theme", 1, TabState.s[1], size: 1 do
        TabState.s[1] = 1
      end
    end

    spacer

    hpanel gap: 1 do
      spacer
      button " Apply ", size: 1 do
        if TabState.s[1] == 0
          kui_theme_dark
        else
          kui_theme_light
        end
      end
      spacer
    end
  end
  return 0
end

#: () -> Integer
def draw_about_tab
  tab_content pad: 1, gap: 1 do
    card pad: 2, gap: 1 do
      label "KUI Framework", size: 1, r: 100, g: 200, b: 255
      divider
      label "Version: 0.7.1", size: 1
      label "A declarative UI DSL for", size: 1
      label "GUI and TUI applications.", size: 1

      spacer

      hpanel gap: 1 do
        label "Widgets: ", size: 1, r: 120, g: 120, b: 140
        label_num 15, size: 1, r: 100, g: 200, b: 255
      end
      hpanel gap: 1 do
        label "Layouts: ", size: 1, r: 120, g: 120, b: 140
        label_num 6, size: 1, r: 100, g: 200, b: 255
      end

      spacer

      progress_bar 75, 100, 30, 1, r: 80, g: 200, b: 100
      label "Feature completeness: 75%", size: 1, r: 120, g: 120, b: 140
    end
  end
  return 0
end

#: () -> Integer
def draw
  vpanel pad: 0, gap: 0 do
    # Tab bar
    tab_bar TabState.s[0] do
      tab_button " Users ", 0, TabState.s[0], size: 1 do
        TabState.s[0] = 0
      end
      tab_button " Settings ", 1, TabState.s[0], size: 1 do
        TabState.s[0] = 1
      end
      tab_button " About ", 2, TabState.s[0], size: 1 do
        TabState.s[0] = 2
      end
    end

    divider

    # Tab content
    if TabState.s[0] == 0
      draw_users_tab
    end
    if TabState.s[0] == 1
      draw_settings_tab
    end
    if TabState.s[0] == 2
      draw_about_tab
    end

    # Modal (add user)
    if TabState.s[2] == 1
      modal 40, 12 do
        label "Add New User", size: 1, r: 100, g: 200, b: 255
        divider
        label "Name:", size: 1
        text_input 0, w: 25, size: 1
        label "Role:", size: 1
        text_input 1, w: 25, size: 1

        spacer

        hpanel gap: 2 do
          spacer
          button " Save ", size: 1 do
            # Copy input buffers (0,1) to storage slot based on count
            dst_name = 2 + TabState.s[5] * 2
            dst_role = 3 + TabState.s[5] * 2
            kui_textbuf_copy dst_name, 0
            kui_textbuf_copy dst_role, 1
            TabState.s[5] = TabState.s[5] + 1
            kui_textbuf_clear 0
            kui_textbuf_clear 1
            TabState.s[2] = 0
          end
          button " Cancel ", size: 1 do
            TabState.s[2] = 0
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
        label "[Tab] Navigate  [Enter] Select  [ESC] Quit", size: 1, r: 120, g: 120, b: 140
      end
      status_right do
        spinner size: 1
        label " Ready", size: 1, r: 80, g: 200, b: 100
      end
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("KUI Tabs Demo", 80, 24)
  kui_theme_dark
  TabState.s[3] = 1
  TabState.s[4] = 1

  while kui_running == 1
    kui_begin_frame
    draw
    _kui_update_focus
    kui_end_frame
  end

  kui_destroy
  return 0
end

main
