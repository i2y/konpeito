# frozen_string_literal: true

# KUI Charts & Data Table — bar, line, pie charts + paginated data table
#
# Charts are drawn directly via Raylib primitives at known fixed positions.
# Each chart records its position in KUIChartData.m during layout, then
# draws after Clay rendering using those saved coordinates.
#
# rbs_inline: enabled

# @rbs module KUIChartData
# @rbs   @v: NativeArray[Integer, 2048]
# @rbs   @m: NativeArray[Integer, 64]
# @rbs end

# KUIChartData.m layout per chart (8 slots, max 8 charts):
#   [base+0] = chart_type (1=bar, 2=line, 3=pie)
#   [base+1] = data_count
#   [base+2] = data_offset (index into v)
#   [base+3] = max_value (for scaling)
#   [base+4] = min_value
#   [base+5] = color_offset (index into v for R,G,B triples)
#   [base+6] = width (pixels)
#   [base+7] = height (pixels)

# @rbs module KUITableState
# @rbs   @s: NativeArray[Integer, 32]
# @rbs end

# KUITableState.s layout per table (8 slots, max 4 tables):
#   [base+0] = current_page
#   [base+1] = page_size
#   [base+2] = total_rows
#   [base+3] = sort_column
#   [base+4] = sort_direction (0=asc, 1=desc)
#   [base+5] = reserved
#   [base+6] = reserved
#   [base+7] = reserved

# ════════════════════════════════════════════
# Chart Data API
# ════════════════════════════════════════════

#: (Integer chart_id, Integer chart_type, Integer count, Integer max_val) -> Integer
def kui_chart_init(chart_id, chart_type, count, max_val)
  base = chart_id * 8
  KUIChartData.m[base] = chart_type
  KUIChartData.m[base + 1] = count
  KUIChartData.m[base + 2] = chart_id * 256
  KUIChartData.m[base + 3] = max_val
  KUIChartData.m[base + 4] = 0
  KUIChartData.m[base + 5] = chart_id * 256 + 128
  return 0
end

#: (Integer chart_id, Integer index, Integer value) -> Integer
def kui_chart_set(chart_id, index, value)
  off = KUIChartData.m[chart_id * 8 + 2]
  KUIChartData.v[off + index] = value
  return 0
end

#: (Integer chart_id, Integer index, Integer r, Integer g, Integer b) -> Integer
def kui_chart_color(chart_id, index, r, g, b)
  coff = KUIChartData.m[chart_id * 8 + 5]
  KUIChartData.v[coff + index * 3] = r
  KUIChartData.v[coff + index * 3 + 1] = g
  KUIChartData.v[coff + index * 3 + 2] = b
  return 0
end

# ════════════════════════════════════════════
# Chart Placeholders (layout phase)
# ════════════════════════════════════════════

#: (Integer chart_id, Integer w, Integer h) -> Integer
def bar_chart(chart_id, w, h)
  base = chart_id * 8
  KUIChartData.m[base + 6] = w
  KUIChartData.m[base + 7] = h
  fixed_panel(w, h) do
    # empty — drawn in post-render pass
  end
  return 0
end

#: (Integer chart_id, Integer w, Integer h) -> Integer
def line_chart(chart_id, w, h)
  base = chart_id * 8
  KUIChartData.m[base + 6] = w
  KUIChartData.m[base + 7] = h
  fixed_panel(w, h) do
    # empty
  end
  return 0
end

#: (Integer chart_id, Integer w, Integer h) -> Integer
def pie_chart(chart_id, w, h)
  base = chart_id * 8
  KUIChartData.m[base + 6] = w
  KUIChartData.m[base + 7] = h
  fixed_panel(w, h) do
    # empty
  end
  return 0
end

# ════════════════════════════════════════════
# Chart Render (no-op for now, see Phase 2 below)
# ════════════════════════════════════════════

#: (Integer cmd_count) -> Integer
def _kui_render_charts(cmd_count)
  return 0
end

# ════════════════════════════════════════════
# Data Table Widget
# ════════════════════════════════════════════

#: (Integer table_id, Integer total_rows, Integer page_size) -> Integer
def data_table(table_id, total_rows, page_size: 10)
  base = table_id * 8
  KUITableState.s[base + 1] = page_size
  KUITableState.s[base + 2] = total_rows
  vpanel gap: 0 do
    yield
    _data_table_pagination(table_id)
  end
  return 0
end

#: (Integer table_id) -> Integer
def data_table_page(table_id)
  return KUITableState.s[table_id * 8]
end

#: (Integer table_id) -> Integer
def data_table_page_size(table_id)
  return KUITableState.s[table_id * 8 + 1]
end

#: (Integer table_id) -> Integer
def data_table_sort_col(table_id)
  return KUITableState.s[table_id * 8 + 3]
end

#: (Integer table_id) -> Integer
def data_table_sort_dir(table_id)
  return KUITableState.s[table_id * 8 + 4]
end

#: (Integer table_id, Integer col) -> Integer
def data_table_toggle_sort(table_id, col)
  base = table_id * 8
  if KUITableState.s[base + 3] == col
    d = KUITableState.s[base + 4]
    if d == 0
      KUITableState.s[base + 4] = 1
    else
      KUITableState.s[base + 4] = 0
    end
  else
    KUITableState.s[base + 3] = col
    KUITableState.s[base + 4] = 0
  end
  KUITableState.s[base] = 0
  return 0
end

# ════════════════════════════════════════════
# Data Table Pagination
# ════════════════════════════════════════════

#: (Integer table_id) -> Integer
def _data_table_pagination(table_id)
  base = table_id * 8
  page = KUITableState.s[base]
  ps = KUITableState.s[base + 1]
  total = KUITableState.s[base + 2]
  if ps <= 0
    ps = 10
  end
  tp = (total + ps - 1) / ps
  if tp < 1
    tp = 1
  end
  hpanel gap: 8 do
    spacer
    _dt_prev_btn(base, page)
    hpanel gap: 2 do
      label_num page + 1, size: 14
      label " / ", size: 14
      label_num tp, size: 14
    end
    _dt_next_btn(base, page, tp)
    spacer
  end
  return 0
end

#: (Integer base, Integer page) -> Integer
def _dt_prev_btn(base, page)
  button " < ", size: 14 do
    KUITableState.s[base] = page - 1
  end
  return 0
end

#: (Integer base, Integer page, Integer tp) -> Integer
def _dt_next_btn(base, page, tp)
  button " > ", size: 14 do
    KUITableState.s[base] = page + 1
  end
  return 0
end
