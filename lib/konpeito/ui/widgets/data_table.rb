# DataTable - sortable, scrollable data table widget
# Features: column headers, sort indicators, row selection, hover highlight,
#           virtual scroll (only visible rows rendered), alternating row colors,
#           column resize by dragging header borders

DT_HEADER_HEIGHT = 32.0
DT_ROW_HEIGHT = 28.0
DT_SCROLLBAR_WIDTH = 8.0
DT_RESIZE_ZONE = 5.0
DT_MIN_COL_WIDTH = 30.0

# Sort direction constants
DT_SORT_NONE = 0
DT_SORT_ASC = 1
DT_SORT_DESC = 2

class DataTable < Widget
  def initialize(col_names, col_widths, rows)
    super()
    @col_names = col_names        # Array of String
    @col_widths = col_widths      # Array of Float
    @rows = rows                  # Array of Array[String]
    @sort_col = -1
    @sort_dir = DT_SORT_NONE
    @sorted_indices = nil
    @selected_row = -1
    @hover_row = -1
    @hover_header = -1
    @scroll_y = 0.0
    @max_scroll = 0.0
    @scrollable_flag = true
    @width_policy = EXPANDING
    @height_policy = EXPANDING
    @font_size = 13.0
    @header_font_size = 13.0
    @num_cols = col_names.length
    @resizing_col = -1
    @resize_start_x = 0.0
    @resize_start_width = 0.0
    @resize_hover_col = -1
    build_sorted_indices
  end

  def font_size(s)
    @font_size = s
    self
  end

  def header_font_size(s)
    @header_font_size = s
    self
  end

  def set_data(col_names, col_widths, rows)
    @col_names = col_names
    @col_widths = col_widths
    @rows = rows
    @sort_col = -1
    @sort_dir = DT_SORT_NONE
    @sorted_indices = nil
    @selected_row = -1
    @scroll_y = 0.0
    @num_cols = col_names.length
    build_sorted_indices
    mark_dirty
    update
  end

  def set_rows(rows)
    @rows = rows
    build_sorted_indices
    if @sort_col >= 0
      apply_sort
    end
    mark_dirty
    update
  end

  def selected_row
    @selected_row
  end

  def get_scrollable
    @scrollable_flag
  end

  def redraw(painter, completely)
    return if @num_cols == 0

    visible_h = @height - DT_HEADER_HEIGHT
    if visible_h < 0.0
      visible_h = 0.0
    end
    compute_scroll(visible_h)

    # Background
    painter.fill_rect(0.0, 0.0, @width, @height, $theme.bg_primary)

    draw_header(painter)
    draw_rows(painter, visible_h)
    draw_scrollbar(painter, visible_h)
  end

  def draw_header(painter)
    bg = $theme.bg_secondary
    header_bg = painter.darken_color(bg, 0.1)
    painter.fill_rect(0.0, 0.0, @width, DT_HEADER_HEIGHT, header_bg)
    draw_header_columns(painter)
    bc = $theme.border
    painter.draw_line(0.0, DT_HEADER_HEIGHT, @width, DT_HEADER_HEIGHT, bc, 1.0)
  end

  def draw_header_columns(painter)
    hx = 0.0
    ci = 0
    while ci < @num_cols
      col_w = @col_widths[ci]
      col_name = @col_names[ci]
      draw_one_header(painter, ci, hx, col_w, col_name)
      hx = hx + col_w
      ci = ci + 1
    end
  end

  def draw_one_header(painter, ci, hx, col_w, col_name)
    if @hover_header == ci
      ac = $theme.accent
      hc = painter.with_alpha(ac, 30)
      painter.fill_rect(hx, 0.0, col_w, DT_HEADER_HEIGHT, hc)
    end

    painter.save
    painter.clip_rect(hx, 0.0, col_w - 2.0, DT_HEADER_HEIGHT)

    ascent = painter.get_text_ascent($theme.font_family, @header_font_size)
    mh = painter.measure_text_height($theme.font_family, @header_font_size)
    ty = (DT_HEADER_HEIGHT - mh) / 2.0 + ascent
    tc = $theme.text_primary
    painter.draw_text(col_name, hx + 8.0, ty, $theme.font_family, @header_font_size, tc)

    if @sort_col == ci
      draw_sort_indicator(painter, col_name, hx, ty)
    end

    painter.restore

    sep_x = hx + col_w - 1.0
    if @resize_hover_col == ci
      ac = $theme.accent
      painter.draw_line(sep_x, 0.0, sep_x, DT_HEADER_HEIGHT, ac, 2.0)
    else
      bc = $theme.border
      painter.draw_line(sep_x, 0.0, sep_x, DT_HEADER_HEIGHT, bc, 1.0)
    end
  end

  def draw_sort_indicator(painter, col_name, hx, ty)
    nw = painter.measure_text_width(col_name, $theme.font_family, @header_font_size)
    ix = hx + 8.0 + nw + 8.0
    ac = $theme.accent
    s = 4.0
    cy = DT_HEADER_HEIGHT / 2.0
    if @sort_dir == DT_SORT_ASC
      # Up arrow
      painter.fill_triangle(ix - s, cy + s / 2.0, ix + s, cy + s / 2.0, ix, cy - s / 2.0, ac)
    else
      # Down arrow
      painter.fill_triangle(ix - s, cy - s / 2.0, ix + s, cy - s / 2.0, ix, cy + s / 2.0, ac)
    end
  end

  def draw_rows(painter, visible_h)
    painter.save
    painter.clip_rect(0.0, DT_HEADER_HEIGHT, @width, visible_h)

    first_row = (@scroll_y / DT_ROW_HEIGHT).to_i
    if first_row < 0
      first_row = 0
    end
    last_row = (((@scroll_y + visible_h) / DT_ROW_HEIGHT) + 1).to_i
    if last_row > @rows.length
      last_row = @rows.length
    end

    ri = first_row
    while ri < last_row
      draw_single_row(painter, ri)
      ri = ri + 1
    end

    painter.restore
  end

  def draw_single_row(painter, ri)
    actual_index = resolve_row_index(ri)
    ri_f = ri * 1.0
    row_y = DT_HEADER_HEIGHT + ri_f * DT_ROW_HEIGHT - @scroll_y

    row_bg = compute_row_bg(painter, ri)
    painter.fill_rect(0.0, row_y, @width, DT_ROW_HEIGHT, row_bg)

    cx = 0.0
    ci = 0
    while ci < @num_cols
      col_w = @col_widths[ci]
      if actual_index < @rows.length
        if ci < @rows[actual_index].length
          cell_text = @rows[actual_index][ci]
          painter.save
          painter.clip_rect(cx, row_y, col_w - 2.0, DT_ROW_HEIGHT)
          ascent = painter.get_text_ascent($theme.font_family, @font_size)
          ty = row_y + (DT_ROW_HEIGHT - painter.measure_text_height($theme.font_family, @font_size)) / 2.0 + ascent
          painter.draw_text(cell_text, cx + 8.0, ty, $theme.font_family, @font_size, $theme.text_primary)
          painter.restore
        end
      end
      cx = cx + col_w
      ci = ci + 1
    end

    row_line_c = painter.with_alpha($theme.border, 40)
    painter.draw_line(0.0, row_y + DT_ROW_HEIGHT, @width, row_y + DT_ROW_HEIGHT, row_line_c, 1.0)
  end

  def draw_scrollbar(painter, visible_h)
    if @max_scroll <= 0.0
      return
    end
    rows_len = @rows.length * 1.0
    content_h = rows_len * DT_ROW_HEIGHT
    sb_x = @width - DT_SCROLLBAR_WIDTH
    sb_ratio = visible_h / content_h
    sb_h = visible_h * sb_ratio
    if sb_h < 20.0
      sb_h = 20.0
    end
    sb_travel = visible_h - sb_h
    sb_pos = 0.0
    if @max_scroll > 0.0
      sb_pos = (@scroll_y / @max_scroll) * sb_travel
    end
    painter.fill_rect(sb_x, DT_HEADER_HEIGHT, DT_SCROLLBAR_WIDTH, visible_h, $theme.scrollbar_bg)
    painter.fill_round_rect(sb_x + 1.0, DT_HEADER_HEIGHT + sb_pos, DT_SCROLLBAR_WIDTH - 2.0, sb_h, 3.0, $theme.scrollbar_fg)
  end

  # --- Event Handlers ---

  def mouse_down(ev)
    mx = ev.pos.x
    my = ev.pos.y
    if my < DT_HEADER_HEIGHT
      border_col = col_border_at_x(mx)
      if border_col >= 0
        @resizing_col = border_col
        @resize_start_x = mx
        @resize_start_width = @col_widths[border_col]
        return
      end
    end
  end

  def mouse_up(ev)
    if @resizing_col >= 0
      @resizing_col = -1
      return
    end

    mx = ev.pos.x
    my = ev.pos.y

    if my < DT_HEADER_HEIGHT
      col = column_at_x(mx)
      if col >= 0
        toggle_sort(col)
      end
      return
    end

    row_idx = row_at_y(my)
    if row_idx >= 0
      if row_idx < @rows.length
        @selected_row = row_idx
        mark_dirty
        update
      end
    end
  end

  def mouse_drag(ev)
    if @resizing_col >= 0
      mx = ev.pos.x
      delta = mx - @resize_start_x
      new_w = @resize_start_width + delta
      if new_w < DT_MIN_COL_WIDTH
        new_w = DT_MIN_COL_WIDTH
      end
      @col_widths[@resizing_col] = new_w
      mark_dirty
      update
    end
  end

  def cursor_pos(ev)
    mx = ev.pos.x
    my = ev.pos.y
    old_hr = @hover_row
    old_hh = @hover_header
    old_rhc = @resize_hover_col

    if my < DT_HEADER_HEIGHT
      @resize_hover_col = col_border_at_x(mx)
      if @resize_hover_col >= 0
        @hover_header = -1
      else
        @hover_header = column_at_x(mx)
      end
      @hover_row = -1
    else
      @hover_header = -1
      @hover_row = row_at_y(my)
      @resize_hover_col = -1
    end

    need_redraw = false
    if @hover_row != old_hr
      need_redraw = true
    end
    if @hover_header != old_hh
      need_redraw = true
    end
    if @resize_hover_col != old_rhc
      need_redraw = true
    end
    if need_redraw
      mark_dirty
      update
    end
  end

  def mouse_out
    changed = false
    if @hover_row != -1
      @hover_row = -1
      changed = true
    end
    if @hover_header != -1
      @hover_header = -1
      changed = true
    end
    if @resize_hover_col != -1
      @resize_hover_col = -1
      changed = true
    end
    if changed
      mark_dirty
      update
    end
  end

  def dispatch_to_scrollable(p, is_direction_x)
    if contain(p)
      [self, p]
    else
      [nil, nil]
    end
  end

  def mouse_wheel(ev)
    @scroll_y = @scroll_y - ev.delta_y * 30.0
    if @scroll_y < 0.0
      @scroll_y = 0.0
    end
    if @scroll_y > @max_scroll
      @scroll_y = @max_scroll
    end
    mark_dirty
    update
  end

  private

  def resolve_row_index(ri)
    if @sorted_indices != nil
      @sorted_indices[ri]
    else
      ri
    end
  end

  def compute_row_bg(painter, ri)
    bg = $theme.bg_primary
    if ri == @selected_row
      ac = $theme.accent
      bg = painter.with_alpha(ac, 50)
    elsif ri == @hover_row
      bg = painter.lighten_color(bg, 0.08)
    elsif ri % 2 != 0
      bg = painter.darken_color(bg, 0.05)
    end
    bg
  end

  def compute_scroll(visible_h)
    rows_len = @rows.length * 1.0
    content_h = rows_len * DT_ROW_HEIGHT
    @max_scroll = content_h - visible_h
    if @max_scroll < 0.0
      @max_scroll = 0.0
    end
    if @scroll_y > @max_scroll
      @scroll_y = @max_scroll
    end
    if @scroll_y < 0.0
      @scroll_y = 0.0
    end
  end

  def total_columns_width
    total = 0.0
    i = 0
    while i < @num_cols
      total = total + @col_widths[i]
      i = i + 1
    end
    total
  end

  def column_at_x(x)
    cx = 0.0
    i = 0
    while i < @num_cols
      col_w = @col_widths[i]
      if x >= cx
        if x < cx + col_w
          return i
        end
      end
      cx = cx + col_w
      i = i + 1
    end
    -1
  end

  def col_border_at_x(x)
    cx = 0.0
    i = 0
    while i < @num_cols
      cx = cx + @col_widths[i]
      diff = x - cx
      if diff < 0.0
        diff = 0.0 - diff
      end
      if diff < DT_RESIZE_ZONE
        return i
      end
      i = i + 1
    end
    -1
  end

  def row_at_y(y)
    if y < DT_HEADER_HEIGHT
      return -1
    end
    row = ((y - DT_HEADER_HEIGHT + @scroll_y) / DT_ROW_HEIGHT).to_i
    if row < 0
      row = -1
    end
    if row >= @rows.length
      row = -1
    end
    row
  end

  def build_sorted_indices
    @sorted_indices = []
    i = 0
    while i < @rows.length
      @sorted_indices << i
      i = i + 1
    end
  end

  def toggle_sort(col)
    if @sort_col == col
      if @sort_dir == DT_SORT_ASC
        @sort_dir = DT_SORT_DESC
      elsif @sort_dir == DT_SORT_DESC
        @sort_dir = DT_SORT_NONE
        @sort_col = -1
        build_sorted_indices
        mark_dirty
        update
        return
      else
        @sort_dir = DT_SORT_ASC
      end
    else
      @sort_col = col
      @sort_dir = DT_SORT_ASC
    end
    apply_sort
    mark_dirty
    update
  end

  def apply_sort
    return if @sort_col < 0
    build_sorted_indices
    col = @sort_col
    dir = @sort_dir

    n = @sorted_indices.length
    i = 1
    while i < n
      key = @sorted_indices[i]
      j = i - 1
      keep_going = true
      while keep_going
        if j < 0
          keep_going = false
        else
          idx_j = @sorted_indices[j]
          # Inline: get cell values directly (no helper method calls)
          val_a = ""
          if idx_j < @rows.length
            row_a = @rows[idx_j]
            if col < row_a.length
              val_a = row_a[col]
            end
          end
          val_b = ""
          if key < @rows.length
            row_b = @rows[key]
            if col < row_b.length
              val_b = row_b[col]
            end
          end
          cmp = (val_a <=> val_b)
          if cmp == nil
            cmp = 0
          end
          should_swap = false
          if dir == DT_SORT_ASC
            if cmp > 0
              should_swap = true
            end
          else
            if cmp < 0
              should_swap = true
            end
          end
          if should_swap
            @sorted_indices[j + 1] = @sorted_indices[j]
            j = j - 1
          else
            keep_going = false
          end
        end
      end
      @sorted_indices[j + 1] = key
      i = i + 1
    end
  end

  def compare_cells_idx(idx_a, idx_b, col, dir)
    cmp_a = get_cell_value(idx_a, col)
    cmp_b = get_cell_value(idx_b, col)

    num_a = try_parse_float(cmp_a)
    num_b = try_parse_float(cmp_b)
    if num_a != nil
      if num_b != nil
        if dir == DT_SORT_ASC
          return num_a > num_b
        else
          return num_a < num_b
        end
      end
    end
    # Use spaceship operator for string comparison (op_lt/op_gt not in RubyDispatch)
    cmp = (cmp_a <=> cmp_b)
    if cmp == nil
      cmp = 0
    end
    if dir == DT_SORT_ASC
      cmp > 0
    else
      cmp < 0
    end
  end

  def get_cell_value(row_idx, col)
    if row_idx < @rows.length
      row = @rows[row_idx]
      if col < row.length
        return row[col]
      end
    end
    ""
  end

  def is_digit(c)
    if c == "0"
      return true
    end
    if c == "1"
      return true
    end
    if c == "2"
      return true
    end
    if c == "3"
      return true
    end
    if c == "4"
      return true
    end
    if c == "5"
      return true
    end
    if c == "6"
      return true
    end
    if c == "7"
      return true
    end
    if c == "8"
      return true
    end
    if c == "9"
      return true
    end
    false
  end

  def try_parse_float(s)
    return nil if s == nil
    return nil if s == ""
    i = 0
    has_dot = false
    if i < s.length
      if s[i] == "-"
        i = i + 1
      end
    end
    return nil if i >= s.length
    while i < s.length
      c = s[i]
      if c == "."
        return nil if has_dot
        has_dot = true
      elsif is_digit(c)
        # valid digit, continue
      else
        return nil
      end
      i = i + 1
    end
    s.to_f
  end
end

# Top-level helper
def DataTable(col_names, col_widths, rows)
  DataTable.new(col_names, col_widths, rows)
end
