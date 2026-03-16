# KUI v2 Showcase — New Widgets Demo
#
# Demonstrates all new KUI widgets added in the expansion:
#   Basic: badge, avatar, progress_steps, number_stepper, segmented_control, accordion
#   Forms: dropdown, tooltip, toast, alert/confirm dialog
#   Input: slider, switch, rating, textarea, color_picker, date_picker
#   Layout: grid, zstack, scaffold, wrap_panel
#   Navigation: nav_bar, bottom_nav, drawer, bottom_sheet
#   Data: list_section, sortable_header, timeline, skeleton, carousel_dots
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_showcase/showcase_v2_gui \
#     examples/kui_showcase/showcase_v2_gui.rb
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

# @rbs module App
# @rbs   @s: NativeArray[Integer, 32]
# @rbs end
# App.s slots:
#   [0]  = active tab (0-5)
#   [1]  = stepper value
#   [2]  = slider value
#   [3]  = switch on
#   [4]  = rating value
#   [5]  = accordion 1 open
#   [6]  = accordion 2 open
#   [7]  = dropdown selection (0-3)
#   [8]  = segment selection
#   [9]  = show alert
#   [10] = show confirm
#   [11] = confirm result (0=none, 1=ok, 2=cancel)
#   [12] = textarea active line
#   [13] = color R
#   [14] = color G
#   [15] = color B
#   [16] = date year offset (from 2026)
#   [17] = date month
#   [18] = date day
#   [19] = drawer open
#   [20] = bottom sheet open
#   [21] = carousel page
#   [22] = sort column
#   [23] = sort direction
#   [24] = bottom nav active
#   [25] = progress step

# ═══════════════════════════════════════
# Tab 0: Basic Widgets
# ═══════════════════════════════════════

#: () -> Integer
def draw_basic_tab
  tab_content pad: 16, gap: 12 do
    label "Basic Widgets", size: 22

    # Badge & Avatar row
    hpanel gap: 12 do
      avatar "KU", size: 40
      vpanel gap: 4 do
        hpanel gap: 6 do
          label "KUI Framework", size: 18
          badge "NEW", r: 80, g: 200, b: 100
          badge "v2.0", r: 100, g: 120, b: 220
        end
        label "66 widgets and counting", size: 14, r: 120, g: 120, b: 135
      end
    end

    divider

    # Progress Steps
    label "Progress Steps:", size: 14
    progress_steps App.s[25], 5, size: 16
    hpanel gap: 8 do
      button "< Prev", size: 14 do
        if App.s[25] > 0
          App.s[25] = App.s[25] - 1
        end
      end
      button "Next >", size: 14 do
        if App.s[25] < 5
          App.s[25] = App.s[25] + 1
        end
      end
    end

    divider

    # Number Stepper
    hpanel gap: 12 do
      label "Quantity:", size: 16
      number_stepper App.s[1], 0, 99, size: 16 do |delta|
        App.s[1] = App.s[1] + delta
      end
    end

    divider

    # Segmented Control
    label "View Mode:", size: 14
    segmented_control App.s[8] do
      segment_button "List", 0, App.s[8] do
        App.s[8] = 0
      end
      segment_button "Grid", 1, App.s[8] do
        App.s[8] = 1
      end
      segment_button "Cards", 2, App.s[8] do
        App.s[8] = 2
      end
    end

    divider

    # Accordion
    accordion "About KUI", App.s[5], size: 16 do |action|
      if action == :toggle
        if App.s[5] == 1
          App.s[5] = 0
        else
          App.s[5] = 1
        end
      end
      if action == :content
        label "KUI is a declarative UI DSL for building", size: 14
        label "cross-platform apps (GUI + TUI).", size: 14
      end
    end

    accordion "Technical Details", App.s[6], size: 16 do |action|
      if action == :toggle
        if App.s[6] == 1
          App.s[6] = 0
        else
          App.s[6] = 1
        end
      end
      if action == :content
        label "Backend: Clay + Raylib (GUI)", size: 14
        label "Backend: ClayTUI + termbox2 (TUI)", size: 14
        label "State: GC-free NativeArray", size: 14
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Tab 1: Form Widgets
# ═══════════════════════════════════════

#: () -> Integer
def draw_forms_tab
  tab_content pad: 16, gap: 12 do
    label "Form Widgets", size: 22

    # Slider
    hpanel gap: 8 do
      label "Volume:", size: 16
      slider App.s[2], 0, 100, w: 200, size: 14 do |nv|
        App.s[2] = nv
      end
      label_num App.s[2], size: 14
    end

    divider

    # Switch
    switch "Dark Mode", App.s[3], size: 16 do
      if App.s[3] == 1
        App.s[3] = 0
      else
        App.s[3] = 1
      end
    end

    divider

    # Rating
    hpanel gap: 8 do
      label "Rating:", size: 16
      rating App.s[4], 5, size: 20 do |nv|
        App.s[4] = nv
      end
    end

    divider

    # Search Bar
    label "Search:", size: 14
    result = search_bar(0, w: 300, size: 16)
    if result == KUI_KEY_ENTER
      kui_show_toast 0, duration: 120, type: KUI_TOAST_SUCCESS
    end

    divider

    # Textarea
    label "Notes:", size: 14
    textarea 8, App.s[12], lines: 3, w: 300, size: 14 do |new_line|
      App.s[12] = new_line
    end

    divider

    # Date Picker
    hpanel gap: 8 do
      label "Date:", size: 16
      date_picker 2026 + App.s[16], App.s[17] + 1, App.s[18] + 1 do |comp, delta|
        if comp == 0
          App.s[16] = App.s[16] + delta
        end
        if comp == 1
          nv = App.s[17] + delta
          if nv >= 0
            if nv < 12
              App.s[17] = nv
            end
          end
        end
        if comp == 2
          nv = App.s[18] + delta
          if nv >= 0
            if nv < 31
              App.s[18] = nv
            end
          end
        end
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Tab 2: Overlay Widgets
# ═══════════════════════════════════════

#: () -> Integer
def draw_overlay_tab
  tab_content pad: 16, gap: 12 do
    label "Overlay Widgets", size: 22

    # Dropdown
    hpanel gap: 8 do
      label "Theme:", size: 16
      sel = App.s[7]
      names = "Default"
      if sel == 1
        names = "Ocean"
      end
      if sel == 2
        names = "Forest"
      end
      if sel == 3
        names = "Sunset"
      end
      dropdown names, size: 16 do
        dropdown_item "Default" do
          App.s[7] = 0
        end
        dropdown_item "Ocean" do
          App.s[7] = 1
        end
        dropdown_item "Forest" do
          App.s[7] = 2
        end
        dropdown_item "Sunset" do
          App.s[7] = 3
        end
      end
    end

    divider

    # Tooltip
    with_tooltip "This button shows an info toast", size: 12 do
      button "Show Info Toast", size: 16 do
        kui_show_toast 0, duration: 120, type: KUI_TOAST_INFO
      end
    end

    with_tooltip "This button shows a success toast", size: 12 do
      button "Show Success Toast", size: 16 do
        kui_show_toast 1, duration: 120, type: KUI_TOAST_SUCCESS
      end
    end

    with_tooltip "This button shows a warning toast", size: 12 do
      button "Show Warning Toast", size: 16 do
        kui_show_toast 2, duration: 120, type: KUI_TOAST_WARNING
      end
    end

    divider

    # Toast render area
    toast 0, "Information: operation completed.", size: 14
    toast 1, "Success: data saved!", size: 14
    toast 2, "Warning: disk space low.", size: 14

    divider

    # Alert / Confirm buttons
    hpanel gap: 8 do
      button "Alert Dialog", size: 16 do
        App.s[9] = 1
      end
      button "Confirm Dialog", size: 16 do
        App.s[10] = 1
      end
    end

    r = App.s[11]
    if r == 1
      label "Result: Confirmed!", size: 14, r: 80, g: 200, b: 100
    end
    if r == 2
      label "Result: Cancelled.", size: 14, r: 220, g: 80, b: 80
    end
  end

  # Dialogs (rendered outside tab_content for floating)
  if App.s[9] == 1
    alert_dialog "Alert", "This is an alert message!", w: 380, h: 180 do
      App.s[9] = 0
    end
  end

  if App.s[10] == 1
    confirm_dialog "Confirm", "Are you sure?", w: 380, h: 180 do |action|
      if action == :confirm
        App.s[10] = 0
        App.s[11] = 1
      end
      if action == :cancel
        App.s[10] = 0
        App.s[11] = 2
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Tab 3: Data Display
# ═══════════════════════════════════════

#: () -> Integer
def draw_data_tab
  tab_content pad: 16, gap: 12 do
    label "Data Display", size: 22

    # Sortable Table
    hpanel gap: 0 do
      sortable_header "Name", 120, 0, App.s[22], App.s[23], size: 14 do
        if App.s[22] == 0
          if App.s[23] == 0
            App.s[23] = 1
          else
            App.s[23] = 0
          end
        else
          App.s[22] = 0
          App.s[23] = 0
        end
      end
      sortable_header "Score", 80, 1, App.s[22], App.s[23], size: 14 do
        if App.s[22] == 1
          if App.s[23] == 0
            App.s[23] = 1
          else
            App.s[23] = 0
          end
        else
          App.s[22] = 1
          App.s[23] = 0
        end
      end
      sortable_header "Status", 100, 2, App.s[22], App.s[23], size: 14 do
        if App.s[22] == 2
          if App.s[23] == 0
            App.s[23] = 1
          else
            App.s[23] = 0
          end
        else
          App.s[22] = 2
          App.s[23] = 0
        end
      end
    end

    divider

    # Grouped list with sections
    list_section "Active Users"
    list_item "Alice", 0, -1, size: 14 do end
    list_item "Bob", 1, -1, size: 14 do end
    list_section "Inactive Users"
    list_item "Charlie", 2, -1, size: 14 do end

    divider

    # Carousel dots
    hpanel gap: 8 do
      label "Page:", size: 14
      carousel_dots App.s[21], 4, size: 16
    end
    hpanel gap: 8 do
      button "<", size: 14 do
        if App.s[21] > 0
          App.s[21] = App.s[21] - 1
        end
      end
      button ">", size: 14 do
        if App.s[21] < 3
          App.s[21] = App.s[21] + 1
        end
      end
    end

    divider

    # Circular progress
    hpanel gap: 12 do
      label "Upload:", size: 14
      circular_progress 73, 100, size: 16
      label "Download:", size: 14
      circular_progress 45, 100, size: 16
    end

    divider

    # Skeleton loading
    label "Loading...", size: 14
    hpanel gap: 8 do
      skeleton 120, 16
      skeleton 200, 16
      skeleton 80, 16
    end
    skeleton 300, 12
  end
  return 0
end

# ═══════════════════════════════════════
# Tab 4: Timeline
# ═══════════════════════════════════════

#: () -> Integer
def draw_timeline_tab
  tab_content pad: 16, gap: 4 do
    label "Project Timeline", size: 22

    timeline_item "Project kickoff", 1, size: 16
    timeline_connector
    timeline_item "Design phase complete", 1, size: 16
    timeline_connector
    timeline_item "Phase 1: Infrastructure", 1, size: 16
    timeline_connector
    timeline_item "Phase 2: Overlay widgets", 1, size: 16
    timeline_connector
    timeline_item "Phase 3: Form widgets", 1, size: 16
    timeline_connector
    timeline_item "Phase 4: Layout widgets", 0, size: 16
    timeline_connector
    timeline_item "Phase 5: Navigation", 0, size: 16
    timeline_connector
    timeline_item "Phase 6: Data display", 0, size: 16

    divider

    # Color picker
    label "Theme Color Picker:", size: 16
    color_picker App.s[13], App.s[14], App.s[15], w: 250 do |comp, nv|
      if comp == 0
        App.s[13] = nv
      end
      if comp == 1
        App.s[14] = nv
      end
      if comp == 2
        App.s[15] = nv
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Tab 5: Layout
# ═══════════════════════════════════════

#: () -> Integer
def draw_layout_tab
  tab_content pad: 16, gap: 12 do
    label "Layout Widgets", size: 22

    # Grid
    label "Grid (3 columns):", size: 14
    grid_row gap: 8 do
      grid_item 480, 3, gap: 8 do
        card pad: 8 do
          avatar "A", size: 28, r: 220, g: 80, b: 80
          label "Card 1", size: 14
        end
      end
      grid_item 480, 3, gap: 8 do
        card pad: 8 do
          avatar "B", size: 28, r: 80, g: 200, b: 100
          label "Card 2", size: 14
        end
      end
      grid_item 480, 3, gap: 8 do
        card pad: 8 do
          avatar "C", size: 28, r: 100, g: 120, b: 220
          label "Card 3", size: 14
        end
      end
    end

    divider

    # Aspect ratio panel
    label "Aspect Panel (16:9):", size: 14
    aspect_panel 320, 56 do
      _kui_set_bg(KUITheme.c[38], KUITheme.c[39], KUITheme.c[40])
      cpanel do
        label "16:9 Content Area", size: 16
      end
    end

    divider

    # ZStack
    label "ZStack (overlay):", size: 14
    zstack do
      fixed_panel 200, 60 do
        _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
        label "Base Layer", size: 16
      end
      zstack_layer z: 10 do
        badge "Overlay Badge"
      end
    end

    divider

    # Bottom sheet / drawer buttons
    hpanel gap: 8 do
      button "Toggle Drawer", size: 14 do
        if App.s[19] == 1
          App.s[19] = 0
        else
          App.s[19] = 1
        end
      end
      button "Toggle Bottom Sheet", size: 14 do
        if App.s[20] == 1
          App.s[20] = 0
        else
          App.s[20] = 1
        end
      end
    end
  end
  return 0
end

# ═══════════════════════════════════════
# Main
# ═══════════════════════════════════════

#: () -> Integer
def draw
  vpanel pad: 0, gap: 0 do
    # Tab bar
    tab_bar App.s[0] do
      tab_button "Basic", 0, App.s[0] do
        App.s[0] = 0
      end
      tab_button "Forms", 1, App.s[0] do
        App.s[0] = 1
      end
      tab_button "Overlay", 2, App.s[0] do
        App.s[0] = 2
      end
      tab_button "Data", 3, App.s[0] do
        App.s[0] = 3
      end
      tab_button "Timeline", 4, App.s[0] do
        App.s[0] = 4
      end
      tab_button "Layout", 5, App.s[0] do
        App.s[0] = 5
      end
    end

    # Main content area with optional drawer
    hpanel gap: 0 do
      # Drawer
      drawer App.s[19], w: 160, pad: 8, gap: 4 do
        label "Drawer Menu", size: 16
        divider
        list_item "Home", 0, -1, size: 14 do end
        list_item "Settings", 1, -1, size: 14 do end
        list_item "Help", 2, -1, size: 14 do end
      end

      # Tab content
      vpanel gap: 0 do
        t = App.s[0]
        if t == 0
          draw_basic_tab
        end
        if t == 1
          draw_forms_tab
        end
        if t == 2
          draw_overlay_tab
        end
        if t == 3
          draw_data_tab
        end
        if t == 4
          draw_timeline_tab
        end
        if t == 5
          draw_layout_tab
        end

        # Bottom sheet
        bottom_sheet App.s[20], h: 120, pad: 12, gap: 4 do
          label "Bottom Sheet", size: 16
          divider
          label "Slide-up content panel", size: 14
          button "Close", size: 14 do
            App.s[20] = 0
          end
        end
      end
    end

    # Status bar
    status_bar do
      status_left do
        label "KUI v2 Showcase", size: 12
      end
      status_center do
        spinner size: 12
      end
      status_right do
        badge "66 widgets"
      end
    end
  end
  return 0
end

#: () -> Integer
def main
  # Init default values
  App.s[1] = 5
  App.s[2] = 50
  App.s[4] = 3
  App.s[13] = 100
  App.s[14] = 120
  App.s[15] = 220
  App.s[17] = 2
  App.s[18] = 14
  App.s[25] = 2

  kui_init("KUI v2 Widget Showcase", 800, 650)
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
