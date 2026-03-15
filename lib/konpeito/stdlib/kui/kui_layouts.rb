# frozen_string_literal: true

# KUI Layout Widgets — grid, wrap_panel, zstack, scaffold, aspect_panel, scroll_h
#
# rbs_inline: enabled

# ════════════════════════════════════════════
# Grid Layout
# ════════════════════════════════════════════

# Grid row — horizontal row of grid items.
#: (Integer gap) -> Integer
def grid_row(gap: 0)
  id = kui_auto_id
  _kui_open_i("_gr", id)
  _kui_layout(0, 0, 0, 0, 0, gap, 1, 0, 0, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# Grid item — fixed-width cell based on column count and span.
# w: total container width, cols: number of columns, span: columns this item spans.
#: (Integer w, Integer cols, Integer span, Integer gap) -> Integer
def grid_item(w, cols, span: 1, gap: 0)
  id = kui_auto_id
  total_gap = (cols - 1) * gap
  cell_w = (w - total_gap) * span / cols
  _kui_open_i("_gi", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, cell_w, 0, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# ZStack (Overlay)
# ════════════════════════════════════════════

# ZStack — overlay children on top of each other.
# First child is the base layer. Subsequent children use zstack_layer.
#: () -> Integer
def zstack
  id = kui_auto_id
  _kui_open_i("_zs", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0)
  yield
  _kui_close
  return 0
end

# Z-layer within a zstack — floats above the base.
#: (Integer z) -> Integer
def zstack_layer(z: 1)
  id = kui_auto_id
  _kui_open_i("_zsl", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0)
  _kui_floating(0, 0, z)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Scaffold / Page Template
# ════════════════════════════════════════════

# Standard page scaffold — optional header + body.
# Yields :header for header content, :body for main content.
#: (String title, Integer size) -> Integer
def scaffold(title: "", size: 20)
  vpanel pad: 0, gap: 0 do
    if title != ""
      header pad: 12 do
        label title, size: size, r: 255, g: 255, b: 255
        spacer
        yield(:header)
      end
    end
    yield(:body)
  end
  return 0
end

# ════════════════════════════════════════════
# Aspect Ratio Panel
# ════════════════════════════════════════════

# Fixed aspect ratio container.
# w: width, ratio_h: height per 100 width units (e.g., 75 for 4:3, 56 for 16:9).
#: (Integer w, Integer ratio_h) -> Integer
def aspect_panel(w, ratio_h)
  h = w * ratio_h / 100
  id = kui_auto_id
  _kui_open_i("_asp", id)
  _kui_layout(1, 0, 0, 0, 0, 0, 2, w, 2, h, 0, 0)
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Horizontal Scroll Panel
# ════════════════════════════════════════════

# Horizontally scrollable panel.
#: (Integer pad, Integer gap) -> Integer
def scroll_h_panel(pad: 0, gap: 0)
  id = kui_auto_id
  _kui_open_i("_shp", id)
  _kui_layout(0, pad, pad, pad, pad, gap, 1, 0, 0, 0, 0, 0)
  _kui_scroll_h
  yield
  _kui_close
  return 0
end

# ════════════════════════════════════════════
# Wrap Panel (Flow Layout)
# ════════════════════════════════════════════

# Wrap panel — items flow left-to-right and wrap to next line.
# Since Clay doesn't support flex-wrap natively, this uses
# manual row breaking based on item_w and container_w.
# User yields items; items_per_row is computed automatically.
# items_per_row: how many items fit per row.
#: (Integer container_w, Integer item_w, Integer gap) -> Integer
def wrap_panel(container_w, item_w, gap: 0)
  items_per_row = (container_w + gap) / (item_w + gap)
  if items_per_row < 1
    items_per_row = 1
  end
  id = kui_auto_id
  _kui_open_i("_wp", id)
  _kui_layout(1, 0, 0, 0, 0, gap, 1, 0, 0, 0, 0, 0)
  yield(items_per_row)
  _kui_close
  return 0
end

# Single row inside a wrap_panel.
#: (Integer gap) -> Integer
def wrap_row(gap: 0)
  id = kui_auto_id
  _kui_open_i("_wr", id)
  _kui_layout(0, 0, 0, 0, 0, gap, 1, 0, 0, 0, 0, 0)
  yield
  _kui_close
  return 0
end
