# KUI Dashboard Demo — Charts + Data Table
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

#: () -> Integer
def setup_bar
  kui_chart_init(0, 1, 5, 100)
  kui_chart_set(0, 0, 75)
  kui_chart_set(0, 1, 50)
  kui_chart_set(0, 2, 90)
  kui_chart_set(0, 3, 60)
  kui_chart_set(0, 4, 85)
  kui_chart_color(0, 0, 100, 120, 220)
  kui_chart_color(0, 1, 80, 200, 180)
  kui_chart_color(0, 2, 100, 120, 220)
  kui_chart_color(0, 3, 80, 200, 180)
  kui_chart_color(0, 4, 100, 120, 220)
  return 0
end

#: () -> Integer
def setup_line
  kui_chart_init(1, 2, 7, 100)
  kui_chart_set(1, 0, 30)
  kui_chart_set(1, 1, 45)
  kui_chart_set(1, 2, 35)
  kui_chart_set(1, 3, 60)
  kui_chart_set(1, 4, 55)
  kui_chart_set(1, 5, 80)
  kui_chart_set(1, 6, 70)
  kui_chart_color(1, 0, 80, 200, 100)
  return 0
end

#: () -> Integer
def setup_pie
  kui_chart_init(2, 3, 4, 100)
  kui_chart_set(2, 0, 45)
  kui_chart_set(2, 1, 25)
  kui_chart_set(2, 2, 20)
  kui_chart_set(2, 3, 10)
  kui_chart_color(2, 0, 100, 120, 220)
  kui_chart_color(2, 1, 80, 200, 180)
  kui_chart_color(2, 2, 160, 100, 220)
  kui_chart_color(2, 3, 230, 160, 50)
  return 0
end

#: () -> Integer
def draw_charts
  hpanel gap: 8 do
    vpanel gap: 4 do
      label "Sales", size: 14
      bar_chart(0, 240, 170)
    end
    vpanel gap: 4 do
      label "Trend", size: 14
      line_chart(1, 240, 170)
    end
    vpanel gap: 4 do
      label "Share", size: 14
      pie_chart(2, 170, 170)
    end
  end
  return 0
end

#: () -> Integer
def draw_hdr
  table_header do
    table_cell(50) do
      label "#", size: 14, r: 255, g: 255, b: 255
    end
    table_cell(120) do
      label "Name", size: 14, r: 255, g: 255, b: 255
    end
    table_cell(80) do
      label "Status", size: 14, r: 255, g: 255, b: 255
    end
    table_cell(80) do
      label "Value", size: 14, r: 255, g: 255, b: 255
    end
  end
  return 0
end

#: (Integer row, String name, Integer val) -> Integer
def draw_r(row, name, val)
  table_row(row) do
    table_cell(50) do
      label_num row + 1, size: 14
    end
    table_cell(120) do
      label name, size: 14
    end
    table_cell(80) do
      if row % 2 == 0
        label "Active", size: 14, r: 80, g: 200, b: 100
      else
        label "Pending", size: 14, r: 230, g: 160, b: 50
      end
    end
    table_cell(80) do
      label_num val, size: 14
    end
  end
  return 0
end

#: () -> Integer
def draw_rows
  p = data_table_page(0)
  s = p * 3
  draw_r(s, "Alpha", 123)
  if s + 1 < 6
    draw_r(s + 1, "Beta", 246)
  end
  if s + 2 < 6
    draw_r(s + 2, "Gamma", 369)
  end
  return 0
end

#: () -> Integer
def draw
  scroll_panel(pad: 12, gap: 8) do
    label "Dashboard", size: 24
    divider
    draw_charts
    divider
    label "Data Table", size: 18
    data_table(0, 6, page_size: 3) do
      draw_hdr
      draw_rows
    end
  end
  return 0
end

#: () -> Integer
def main
  kui_init("Dashboard", 800, 650)
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 20)
  kui_theme_dark
  setup_bar
  setup_line
  setup_pie

  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end

  kui_destroy
  return 0
end

main
