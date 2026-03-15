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
  id = kui_auto_id
  _kui_open_i("_chrt", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, w, 2, h, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  Clay.set_custom(chart_id)
  _kui_close
  return 0
end

#: (Integer chart_id, Integer w, Integer h) -> Integer
def line_chart(chart_id, w, h)
  id = kui_auto_id
  _kui_open_i("_chrt", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, w, 2, h, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  Clay.set_custom(chart_id)
  _kui_close
  return 0
end

#: (Integer chart_id, Integer w, Integer h) -> Integer
def pie_chart(chart_id, w, h)
  id = kui_auto_id
  _kui_open_i("_chrt", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, w, 2, h, 0, 0)
  _kui_set_bg(KUITheme.c[18], KUITheme.c[19], KUITheme.c[20])
  Clay.set_custom(chart_id)
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Chart Render Pass (after Clay.render_raylib)
# ════════════════════════════════════════════

#: (Integer cmd_count) -> Integer
def _kui_render_charts(cmd_count)
  idx = 0
  while idx < cmd_count
    ctype = Clay.cmd_type(idx)
    if ctype == 7
      cid = Clay.cmd_custom_data(idx)
      if cid >= 0
        cx = Clay.cmd_ix(idx)
        cy = Clay.cmd_iy(idx)
        cw = Clay.cmd_iw(idx)
        ch = Clay.cmd_ih(idx)
        _kui_draw_chart(cid, cx, cy, cw, ch)
      end
    end
    idx = idx + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Chart Drawing Dispatch
# ════════════════════════════════════════════

#: (Integer cid, Integer cx, Integer cy, Integer cw, Integer ch) -> Integer
def _kui_draw_chart(cid, cx, cy, cw, ch)
  base = cid * 8
  ct = KUIChartData.m[base]
  if ct == 1
    _kui_draw_bar(cid, cx, cy, cw, ch)
  end
  if ct == 2
    _kui_draw_line_chart(cid, cx, cy, cw, ch)
  end
  if ct == 3
    _kui_draw_pie(cid, cx, cy, cw, ch)
  end
  return 0
end

# ════════════════════════════════════════════
# Bar Chart Renderer
# ════════════════════════════════════════════

#: (Integer cid, Integer cx, Integer cy, Integer cw, Integer ch) -> Integer
def _kui_draw_bar(cid, cx, cy, cw, ch)
  base = cid * 8
  count = KUIChartData.m[base + 1]
  off = KUIChartData.m[base + 2]
  max_val = KUIChartData.m[base + 3]
  coff = KUIChartData.m[base + 5]
  if count <= 0
    return 0
  end
  if max_val <= 0
    max_val = 1
  end
  margin = 30
  gap = 4
  area_w = cw - margin - 10
  area_h = ch - margin - 10
  bar_w = (area_w - gap * (count - 1)) / count
  if bar_w < 2
    bar_w = 2
  end
  ax = cx + margin
  ay = cy + ch - margin
  c_axis = Raylib.color_new(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14], 255)
  Raylib.draw_line(ax, cy + 5, ax, ay, c_axis)
  Raylib.draw_line(ax, ay, cx + cw - 5, ay, c_axis)
  _kui_draw_bars(count, off, coff, max_val, area_h, ax, ay, bar_w, gap)
  return 0
end

#: (Integer count, Integer off, Integer coff, Integer max_val, Integer area_h, Integer ax, Integer ay, Integer bar_w, Integer gap) -> Integer
def _kui_draw_bars(count, off, coff, max_val, area_h, ax, ay, bar_w, gap)
  i = 0
  while i < count
    val = KUIChartData.v[off + i]
    bar_h = val * area_h / max_val
    bx = ax + i * (bar_w + gap)
    by = ay - bar_h
    cr = KUIChartData.v[coff + i * 3]
    cg = KUIChartData.v[coff + i * 3 + 1]
    cb = KUIChartData.v[coff + i * 3 + 2]
    bc = Raylib.color_new(cr, cg, cb, 255)
    Raylib.draw_rectangle(bx, by, bar_w, bar_h, bc)
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Line Chart Renderer
# ════════════════════════════════════════════

#: (Integer cid, Integer cx, Integer cy, Integer cw, Integer ch) -> Integer
def _kui_draw_line_chart(cid, cx, cy, cw, ch)
  base = cid * 8
  count = KUIChartData.m[base + 1]
  off = KUIChartData.m[base + 2]
  max_val = KUIChartData.m[base + 3]
  coff = KUIChartData.m[base + 5]
  if count <= 1
    return 0
  end
  if max_val <= 0
    max_val = 1
  end
  margin = 30
  area_w = cw - margin - 10
  area_h = ch - margin - 10
  ax = cx + margin
  ay = cy + ch - margin
  c_axis = Raylib.color_new(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14], 255)
  Raylib.draw_line(ax, cy + 5, ax, ay, c_axis)
  Raylib.draw_line(ax, ay, cx + cw - 5, ay, c_axis)
  _kui_draw_line_pts(count, off, coff, max_val, area_w, area_h, ax, ay)
  return 0
end

#: (Integer count, Integer off, Integer coff, Integer max_val, Integer area_w, Integer area_h, Integer ax, Integer ay) -> Integer
def _kui_draw_line_pts(count, off, coff, max_val, area_w, area_h, ax, ay)
  step = area_w / (count - 1)
  cr = KUIChartData.v[coff]
  cg = KUIChartData.v[coff + 1]
  cb = KUIChartData.v[coff + 2]
  lc = Raylib.color_new(cr, cg, cb, 255)
  i = 0
  prev_x = 0
  prev_y = 0
  while i < count
    val = KUIChartData.v[off + i]
    px = ax + i * step
    py = ay - val * area_h / max_val
    if i > 0
      Raylib.draw_line(prev_x, prev_y, px, py, lc)
    end
    Raylib.draw_circle(px, py, 4.0, lc)
    prev_x = px
    prev_y = py
    i = i + 1
  end
  return 0
end

# ════════════════════════════════════════════
# Pie Chart Renderer
# ════════════════════════════════════════════

#: (Integer cid, Integer cx, Integer cy, Integer cw, Integer ch) -> Integer
def _kui_draw_pie(cid, cx, cy, cw, ch)
  base = cid * 8
  count = KUIChartData.m[base + 1]
  off = KUIChartData.m[base + 2]
  coff = KUIChartData.m[base + 5]
  if count <= 0
    return 0
  end
  total = 0
  i = 0
  while i < count
    total = total + KUIChartData.v[off + i]
    i = i + 1
  end
  if total <= 0
    return 0
  end
  radius = cw / 2
  if ch / 2 < radius
    radius = ch / 2
  end
  radius = radius - 10
  pcx = cx + cw / 2
  pcy = cy + ch / 2
  _kui_draw_pie_sectors(count, off, coff, total, pcx, pcy, radius)
  return 0
end

#: (Integer count, Integer off, Integer coff, Integer total, Integer pcx, Integer pcy, Integer radius) -> Integer
def _kui_draw_pie_sectors(count, off, coff, total, pcx, pcy, radius)
  angle = 0
  i = 0
  while i < count
    val = KUIChartData.v[off + i]
    sweep = val * 360 / total
    cr = KUIChartData.v[coff + i * 3]
    cg = KUIChartData.v[coff + i * 3 + 1]
    cb = KUIChartData.v[coff + i * 3 + 2]
    sc = Raylib.color_new(cr, cg, cb, 255)
    Raylib.draw_circle_sector(pcx, pcy, radius * 1.0, angle * 1.0, (angle + sweep) * 1.0, 36, sc)
    angle = angle + sweep
    i = i + 1
  end
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
