# Calendar - date picker widget
# Features: day/month/year view modes, navigation, selection highlight
# All date computation uses integer arithmetic (no Time/Date classes)

# View mode constants
CAL_DAYS = 0
CAL_MONTHS = 1
CAL_YEARS = 2

# Layout constants
CAL_CELL_SIZE = 36.0
CAL_HEADER_HEIGHT = 40.0
CAL_WEEKDAY_HEIGHT = 24.0
CAL_NAV_BUTTON_W = 36.0

# ===== Date Utility Functions =====

def cal_is_leap(year)
  if year % 400 == 0
    return true
  end
  if year % 100 == 0
    return false
  end
  if year % 4 == 0
    return true
  end
  false
end

def cal_days_in_month(year, month)
  if month == 1
    return 31
  end
  if month == 2
    if cal_is_leap(year)
      return 29
    end
    return 28
  end
  if month == 3
    return 31
  end
  if month == 4
    return 30
  end
  if month == 5
    return 31
  end
  if month == 6
    return 30
  end
  if month == 7
    return 31
  end
  if month == 8
    return 31
  end
  if month == 9
    return 30
  end
  if month == 10
    return 31
  end
  if month == 11
    return 30
  end
  31
end

# Sakamoto's algorithm for day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
def cal_day_of_week(year, month, day)
  # t lookup table
  t0 = 0
  t1 = 3
  t2 = 2
  t3 = 5
  t4 = 0
  t5 = 3
  t6 = 5
  t7 = 1
  t8 = 4
  t9 = 6
  t10 = 2
  t11 = 4
  y = year
  if month < 3
    y = y - 1
  end
  t_val = 0
  if month == 1
    t_val = t0
  elsif month == 2
    t_val = t1
  elsif month == 3
    t_val = t2
  elsif month == 4
    t_val = t3
  elsif month == 5
    t_val = t4
  elsif month == 6
    t_val = t5
  elsif month == 7
    t_val = t6
  elsif month == 8
    t_val = t7
  elsif month == 9
    t_val = t8
  elsif month == 10
    t_val = t9
  elsif month == 11
    t_val = t10
  else
    t_val = t11
  end
  (y + y / 4 - y / 100 + y / 400 + t_val + day) % 7
end

def cal_month_name(month)
  if month == 1
    return "January"
  end
  if month == 2
    return "February"
  end
  if month == 3
    return "March"
  end
  if month == 4
    return "April"
  end
  if month == 5
    return "May"
  end
  if month == 6
    return "June"
  end
  if month == 7
    return "July"
  end
  if month == 8
    return "August"
  end
  if month == 9
    return "September"
  end
  if month == 10
    return "October"
  end
  if month == 11
    return "November"
  end
  "December"
end

def cal_short_month_name(month)
  if month == 1
    return "Jan"
  end
  if month == 2
    return "Feb"
  end
  if month == 3
    return "Mar"
  end
  if month == 4
    return "Apr"
  end
  if month == 5
    return "May"
  end
  if month == 6
    return "Jun"
  end
  if month == 7
    return "Jul"
  end
  if month == 8
    return "Aug"
  end
  if month == 9
    return "Sep"
  end
  if month == 10
    return "Oct"
  end
  if month == 11
    return "Nov"
  end
  "Dec"
end

def cal_int_to_str(n)
  if n == 1
    return "1"
  end
  if n == 2
    return "2"
  end
  if n == 3
    return "3"
  end
  if n == 4
    return "4"
  end
  if n == 5
    return "5"
  end
  if n == 6
    return "6"
  end
  if n == 7
    return "7"
  end
  if n == 8
    return "8"
  end
  if n == 9
    return "9"
  end
  if n == 10
    return "10"
  end
  if n == 11
    return "11"
  end
  if n == 12
    return "12"
  end
  if n == 13
    return "13"
  end
  if n == 14
    return "14"
  end
  if n == 15
    return "15"
  end
  if n == 16
    return "16"
  end
  if n == 17
    return "17"
  end
  if n == 18
    return "18"
  end
  if n == 19
    return "19"
  end
  if n == 20
    return "20"
  end
  if n == 21
    return "21"
  end
  if n == 22
    return "22"
  end
  if n == 23
    return "23"
  end
  if n == 24
    return "24"
  end
  if n == 25
    return "25"
  end
  if n == 26
    return "26"
  end
  if n == 27
    return "27"
  end
  if n == 28
    return "28"
  end
  if n == 29
    return "29"
  end
  if n == 30
    return "30"
  end
  "31"
end

# Convert year (integer) to string for display
# Simple lookup for common years, digit construction for others
def cal_year_to_str(year)
  # Common decade prefix
  prefix = ""
  remainder = year
  if year >= 2000
    if year < 2100
      prefix = "20"
      remainder = year - 2000
    end
  end
  if prefix == ""
    if year >= 1900
      if year < 2000
        prefix = "19"
        remainder = year - 1900
      end
    end
  end
  if prefix == ""
    return "????"
  end
  # Convert 0-99 to two-digit string
  tens = remainder / 10
  ones = remainder % 10
  tens_s = cal_digit_str(tens)
  ones_s = cal_digit_str(ones)
  prefix + tens_s + ones_s
end

def cal_digit_str(d)
  if d == 0
    return "0"
  end
  if d == 1
    return "1"
  end
  if d == 2
    return "2"
  end
  if d == 3
    return "3"
  end
  if d == 4
    return "4"
  end
  if d == 5
    return "5"
  end
  if d == 6
    return "6"
  end
  if d == 7
    return "7"
  end
  if d == 8
    return "8"
  end
  "9"
end

# JVM-safe float to int conversion (truncation)
# Avoids .to_i which is not available on JVM
def cal_floor(f)
  i = 0
  if f < 0.0
    return 0
  end
  while i * 1.0 <= f
    i = i + 1
  end
  i - 1
end

# ===== CalendarState =====

class CalendarState < ObservableBase
  def initialize(year, month, day)
    super()
    @sel_year = year
    @sel_month = month
    @sel_day = day
    @view_year = year
    @view_month = month
    @view_mode = CAL_DAYS
    @on_change_cb = nil
  end

  def sel_year
    @sel_year
  end

  def sel_month
    @sel_month
  end

  def sel_day
    @sel_day
  end

  def view_year
    @view_year
  end

  def view_month
    @view_month
  end

  def view_mode
    @view_mode
  end

  def prev_month
    @view_month = @view_month - 1
    if @view_month < 1
      @view_month = 12
      @view_year = @view_year - 1
    end
    notify_observers
  end

  def next_month
    @view_month = @view_month + 1
    if @view_month > 12
      @view_month = 1
      @view_year = @view_year + 1
    end
    notify_observers
  end

  def prev_year
    @view_year = @view_year - 1
    notify_observers
  end

  def next_year
    @view_year = @view_year + 1
    notify_observers
  end

  def prev_year_page
    @view_year = @view_year - 20
    notify_observers
  end

  def next_year_page
    @view_year = @view_year + 20
    notify_observers
  end

  def select_date(year, month, day)
    @sel_year = year
    @sel_month = month
    @sel_day = day
    @view_year = year
    @view_month = month
    @view_mode = CAL_DAYS
    if @on_change_cb != nil
      @on_change_cb.call(year, month, day)
    end
    notify_observers
  end

  def select_month(month)
    @view_month = month
    @view_mode = CAL_DAYS
    notify_observers
  end

  def select_year(year)
    @view_year = year
    @view_mode = CAL_MONTHS
    notify_observers
  end

  def set_view_mode(mode)
    @view_mode = mode
    notify_observers
  end

  def formatted_date
    m = @sel_month
    d = @sel_day
    mname = cal_month_name(m)
    dstr = cal_int_to_str(d)
    mname + " " + dstr
  end

  # ===== Wrapper methods for JVM type safety =====
  # These methods access @view_year/@view_month etc. as fields (properly typed as :i64)
  # instead of passing them as method call results (which are Object on JVM)

  def days_in_current_month
    cal_days_in_month(@view_year, @view_month)
  end

  def first_weekday
    cal_day_of_week(@view_year, @view_month, 1)
  end

  def header_text
    mn = cal_month_name(@view_month)
    yr_str = cal_year_to_str(@view_year)
    mn + " " + yr_str
  end

  def is_current_day(day)
    if day != @sel_day
      return false
    end
    if @view_month != @sel_month
      return false
    end
    if @view_year != @sel_year
      return false
    end
    true
  end

  def year_label(y)
    # y comes via RubyDispatch so it's already a valid Integer
    # But on JVM, invokestatic cal_year_to_str expects long
    # For CalendarState's own use, we use view_year_label below
    cal_year_to_str(y)
  end

  def view_year_label
    cal_year_to_str(@view_year)
  end

  def year_range_text
    start_y = @view_year - (@view_year % 20)
    end_y = start_y + 19
    sy_str = cal_year_to_str(start_y)
    ey_str = cal_year_to_str(end_y)
    sy_str + " - " + ey_str
  end

  def year_range_start
    @view_year - (@view_year % 20)
  end

  def is_year_selected(year)
    year == @sel_year
  end

  def is_month_selected(month)
    month == @sel_month
  end

  def year_at_offset(i)
    start = @view_year - (@view_year % 20)
    start + i
  end

  def on_change(cb)
    @on_change_cb = cb
    self
  end

  def try_select_cell(row, col)
    first_dow = first_weekday
    cell_idx = row * 7 + col
    day = cell_idx - first_dow + 1
    days = days_in_current_month
    if day >= 1
      if day <= days
        select_date(@view_year, @view_month, day)
      end
    end
  end
end

# ===== Calendar Widget =====

class Calendar < Widget
  def initialize(state)
    super()
    @state = state
    @hover_cell = -1
    @width_policy = FIXED
    @height_policy = FIXED
    @width = 7.0 * CAL_CELL_SIZE + 16.0
    @height = CAL_HEADER_HEIGHT + CAL_WEEKDAY_HEIGHT + 6.0 * CAL_CELL_SIZE + 8.0
    @state.attach(self)
  end

  def on_attach(observable)
  end

  def on_detach(observable)
  end

  def on_notify
    mark_dirty
    update
  end

  def redraw(painter, completely)
    # Background
    bg = $theme.bg_secondary
    painter.fill_round_rect(0.0, 0.0, @width, @height, 8.0, bg)
    # Border
    bc = $theme.border
    painter.stroke_rect(0.0, 0.0, @width, @height, bc, 1.0)

    draw_cal_header(painter)

    mode = @state.view_mode
    if mode == CAL_DAYS
      draw_days_view(painter)
    elsif mode == CAL_MONTHS
      draw_months_view(painter)
    else
      draw_years_view(painter)
    end
  end

  def draw_cal_header(painter)
    # Navigation: < [Title] >
    tc = $theme.text_primary
    ac = $theme.accent
    ascent = painter.get_text_ascent($theme.font_family, 14.0)
    mh = painter.measure_text_height($theme.font_family, 14.0)
    ty = (CAL_HEADER_HEIGHT - mh) / 2.0 + ascent

    # Left arrow
    left_c = tc
    if @hover_cell == -2
      left_c = ac
    end
    painter.draw_text("<", 12.0, ty, $theme.font_family, 14.0, left_c)

    # Right arrow
    right_c = tc
    if @hover_cell == -3
      right_c = ac
    end
    rw = painter.measure_text_width(">", $theme.font_family, 14.0)
    painter.draw_text(">", @width - 12.0 - rw, ty, $theme.font_family, 14.0, right_c)

    # Title (clickable to change view mode)
    title = cal_header_title
    title_c = ac
    tw = painter.measure_text_width(title, $theme.font_family, 14.0)
    tx = (@width - tw) / 2.0
    painter.draw_text(title, tx, ty, $theme.font_family, 14.0, title_c)
  end

  def cal_header_title
    mode = @state.view_mode
    if mode == CAL_DAYS
      return @state.header_text
    end
    if mode == CAL_MONTHS
      return @state.view_year_label
    end
    @state.year_range_text
  end

  # ===== DAYS VIEW =====

  def draw_days_view(painter)
    draw_weekday_headers(painter)
    draw_day_cells(painter)
  end

  def draw_weekday_headers(painter)
    headers = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    lc = $theme.text_secondary
    ascent = painter.get_text_ascent($theme.font_family, 11.0)
    base_y = CAL_HEADER_HEIGHT + ascent + 4.0
    i = 0
    while i < 7
      label = headers[i]
      lw = painter.measure_text_width(label, $theme.font_family, 11.0)
      cx = 8.0 + i * 1.0 * CAL_CELL_SIZE + CAL_CELL_SIZE / 2.0 - lw / 2.0
      painter.draw_text(label, cx, base_y, $theme.font_family, 11.0, lc)
      i = i + 1
    end
  end

  def draw_day_cells(painter)
    days = @state.days_in_current_month
    first_dow = @state.first_weekday
    base_y = CAL_HEADER_HEIGHT + CAL_WEEKDAY_HEIGHT
    # Draw 6 rows x 7 cols grid, only draw valid days
    draw_day_row(painter, 0, first_dow, days, base_y)
    draw_day_row(painter, 1, first_dow, days, base_y)
    draw_day_row(painter, 2, first_dow, days, base_y)
    draw_day_row(painter, 3, first_dow, days, base_y)
    draw_day_row(painter, 4, first_dow, days, base_y)
    draw_day_row(painter, 5, first_dow, days, base_y)
  end

  def draw_day_row(painter, row, first_dow, days, base_y)
    col = 0
    while col < 7
      cell_idx = row * 7 + col
      day = cell_idx - first_dow + 1
      if day >= 1
        if day <= days
          cx = 8.0 + col * 1.0 * CAL_CELL_SIZE
          cy = base_y + row * 1.0 * CAL_CELL_SIZE
          draw_day_bg(painter, day, cell_idx, cx, cy)
          draw_day_label(painter, day, cx, cy)
        end
      end
      col = col + 1
    end
  end

  def draw_day_bg(painter, day, cell_idx, cx, cy)
    sel = is_day_selected(day)
    circle_r = CAL_CELL_SIZE / 2.0 - 2.0
    circle_cx = cx + CAL_CELL_SIZE / 2.0
    circle_cy = cy + CAL_CELL_SIZE / 2.0
    if sel
      painter.fill_circle(circle_cx, circle_cy, circle_r, $theme.accent)
    elsif @hover_cell == cell_idx
      hc = painter.with_alpha($theme.accent, 40)
      painter.fill_circle(circle_cx, circle_cy, circle_r, hc)
    end
  end

  def is_day_selected(day)
    @state.is_current_day(day)
  end

  def draw_day_label(painter, day, cx, cy)
    ascent = painter.get_text_ascent($theme.font_family, 13.0)
    mh = painter.measure_text_height($theme.font_family, 13.0)
    label = painter.number_to_string(day * 1.0)
    lw = painter.measure_text_width(label, $theme.font_family, 13.0)
    lx = cx + CAL_CELL_SIZE / 2.0 - lw / 2.0
    ly = cy + (CAL_CELL_SIZE - mh) / 2.0 + ascent
    tc = $theme.text_primary
    if is_day_selected(day)
      tc = 4294967295
    end
    painter.draw_text(label, lx, ly, $theme.font_family, 13.0, tc)
  end

  # ===== MONTHS VIEW =====

  def draw_months_view(painter)
    ascent = painter.get_text_ascent($theme.font_family, 13.0)
    mh = painter.measure_text_height($theme.font_family, 13.0)
    base_y = CAL_HEADER_HEIGHT + 8.0
    cell_w = (@width - 16.0) / 3.0
    cell_h = (@height - CAL_HEADER_HEIGHT - 16.0) / 4.0

    m = 1
    while m <= 12
      row = (m - 1) / 3
      col = (m - 1) % 3
      cx = 8.0 + col * 1.0 * cell_w
      cy = base_y + row * 1.0 * cell_h

      is_sel = @state.is_month_selected(m)
      cell_idx = 100 + m
      is_hover = (@hover_cell == cell_idx)

      if is_sel
        painter.fill_round_rect(cx + 2.0, cy + 2.0, cell_w - 4.0, cell_h - 4.0, 6.0, $theme.accent)
      elsif is_hover
        hc = painter.with_alpha($theme.accent, 40)
        painter.fill_round_rect(cx + 2.0, cy + 2.0, cell_w - 4.0, cell_h - 4.0, 6.0, hc)
      end

      label = cal_short_month_name(m)
      lw = painter.measure_text_width(label, $theme.font_family, 13.0)
      lx = cx + cell_w / 2.0 - lw / 2.0
      ly = cy + cell_h / 2.0 - mh / 2.0 + ascent

      tc = $theme.text_primary
      if is_sel
        tc = 4294967295
      end
      painter.draw_text(label, lx, ly, $theme.font_family, 13.0, tc)
      m = m + 1
    end
  end

  # ===== YEARS VIEW =====

  def draw_years_view(painter)
    ascent = painter.get_text_ascent($theme.font_family, 12.0)
    mh = painter.measure_text_height($theme.font_family, 12.0)
    base_y = CAL_HEADER_HEIGHT + 8.0
    cell_w = (@width - 16.0) / 4.0
    cell_h = (@height - CAL_HEADER_HEIGHT - 16.0) / 5.0

    i = 0
    while i < 20
      year = @state.year_at_offset(i)
      row = i / 4
      col = i % 4
      cx = 8.0 + col * 1.0 * cell_w
      cy = base_y + row * 1.0 * cell_h

      is_sel = @state.is_year_selected(year)
      cell_idx = 200 + i
      is_hover = (@hover_cell == cell_idx)

      if is_sel
        painter.fill_round_rect(cx + 2.0, cy + 2.0, cell_w - 4.0, cell_h - 4.0, 6.0, $theme.accent)
      elsif is_hover
        hc = painter.with_alpha($theme.accent, 40)
        painter.fill_round_rect(cx + 2.0, cy + 2.0, cell_w - 4.0, cell_h - 4.0, 6.0, hc)
      end

      label = painter.number_to_string(year * 1.0)
      lw = painter.measure_text_width(label, $theme.font_family, 12.0)
      lx = cx + cell_w / 2.0 - lw / 2.0
      ly = cy + cell_h / 2.0 - mh / 2.0 + ascent

      tc = $theme.text_primary
      if is_sel
        tc = 4294967295
      end
      painter.draw_text(label, lx, ly, $theme.font_family, 12.0, tc)
      i = i + 1
    end
  end

  # ===== EVENT HANDLERS =====

  def mouse_up(ev)
    mx = ev.pos.x
    my = ev.pos.y

    # Header navigation
    if my < CAL_HEADER_HEIGHT
      handle_header_click(mx)
      return
    end

    mode = @state.view_mode
    if mode == CAL_DAYS
      handle_day_click(mx, my)
    elsif mode == CAL_MONTHS
      handle_month_click(mx, my)
    else
      handle_year_click(mx, my)
    end
  end

  def handle_header_click(mx)
    # Left arrow
    if mx < CAL_NAV_BUTTON_W
      mode = @state.view_mode
      if mode == CAL_DAYS
        @state.prev_month
      elsif mode == CAL_MONTHS
        @state.prev_year
      else
        @state.prev_year_page
      end
      return
    end
    # Right arrow
    if mx > @width - CAL_NAV_BUTTON_W
      mode = @state.view_mode
      if mode == CAL_DAYS
        @state.next_month
      elsif mode == CAL_MONTHS
        @state.next_year
      else
        @state.next_year_page
      end
      return
    end
    # Title click -> cycle view mode
    mode = @state.view_mode
    if mode == CAL_DAYS
      @state.set_view_mode(CAL_MONTHS)
    elsif mode == CAL_MONTHS
      @state.set_view_mode(CAL_YEARS)
    end
  end

  def handle_day_click(mx, my)
    base_y = CAL_HEADER_HEIGHT + CAL_WEEKDAY_HEIGHT
    if my >= base_y
      handle_day_click_inner(mx, my, base_y)
    end
  end

  def handle_day_click_inner(mx, my, base_y)
    col = cal_floor((mx - 8.0) / CAL_CELL_SIZE)
    row = cal_floor((my - base_y) / CAL_CELL_SIZE)
    if col >= 0
      if col <= 6
        if row >= 0
          if row <= 5
            try_select_day(row, col)
          end
        end
      end
    end
  end

  def try_select_day(row, col)
    @state.try_select_cell(row, col)
  end

  def handle_month_click(mx, my)
    base_y = CAL_HEADER_HEIGHT + 8.0
    cell_w = (@width - 16.0) / 3.0
    cell_h = (@height - CAL_HEADER_HEIGHT - 16.0) / 4.0
    col = cal_floor((mx - 8.0) / cell_w)
    row = cal_floor((my - base_y) / cell_h)
    if col >= 0
      if col <= 2
        if row >= 0
          if row <= 3
            month = row * 3 + col + 1
            @state.select_month(month)
          end
        end
      end
    end
  end

  def handle_year_click(mx, my)
    base_y = CAL_HEADER_HEIGHT + 8.0
    cell_w = (@width - 16.0) / 4.0
    cell_h = (@height - CAL_HEADER_HEIGHT - 16.0) / 5.0
    col = cal_floor((mx - 8.0) / cell_w)
    row = cal_floor((my - base_y) / cell_h)
    if col >= 0
      if col <= 3
        if row >= 0
          if row <= 4
            i = row * 4 + col
            year = @state.year_at_offset(i)
            @state.select_year(year)
          end
        end
      end
    end
  end

  def cursor_pos(ev)
    mx = ev.pos.x
    my = ev.pos.y
    old_hover = @hover_cell
    @hover_cell = compute_hover_cell(mx, my)
    if @hover_cell != old_hover
      mark_dirty
      update
    end
  end

  def compute_hover_cell(mx, my)
    if my < CAL_HEADER_HEIGHT
      return compute_header_hover(mx)
    end
    mode = @state.view_mode
    if mode == CAL_DAYS
      return compute_day_hover(mx, my)
    end
    if mode == CAL_MONTHS
      return compute_month_hover(mx, my)
    end
    compute_year_hover(mx, my)
  end

  def compute_header_hover(mx)
    if mx < CAL_NAV_BUTTON_W
      return -2
    end
    if mx > @width - CAL_NAV_BUTTON_W
      return -3
    end
    -4
  end

  def compute_day_hover(mx, my)
    base_y = CAL_HEADER_HEIGHT + CAL_WEEKDAY_HEIGHT
    if my < base_y
      return -1
    end
    col = cal_floor((mx - 8.0) / CAL_CELL_SIZE)
    row = cal_floor((my - base_y) / CAL_CELL_SIZE)
    if col >= 0
      if col < 7
        if row >= 0
          if row < 6
            return row * 7 + col
          end
        end
      end
    end
    -1
  end

  def compute_month_hover(mx, my)
    base_y = CAL_HEADER_HEIGHT + 8.0
    cell_w = (@width - 16.0) / 3.0
    cell_h = (@height - CAL_HEADER_HEIGHT - 16.0) / 4.0
    col = cal_floor((mx - 8.0) / cell_w)
    row = cal_floor((my - base_y) / cell_h)
    if col >= 0
      if col < 3
        if row >= 0
          if row < 4
            return 100 + row * 3 + col + 1
          end
        end
      end
    end
    -1
  end

  def compute_year_hover(mx, my)
    base_y = CAL_HEADER_HEIGHT + 8.0
    cell_w = (@width - 16.0) / 4.0
    cell_h = (@height - CAL_HEADER_HEIGHT - 16.0) / 5.0
    col = cal_floor((mx - 8.0) / cell_w)
    row = cal_floor((my - base_y) / cell_h)
    if col >= 0
      if col < 4
        if row >= 0
          if row < 5
            return 200 + row * 4 + col
          end
        end
      end
    end
    -1
  end

  def mouse_out
    if @hover_cell != -1
      @hover_cell = -1
      mark_dirty
      update
    end
  end
end

# Top-level helper
def Calendar(state)
  Calendar.new(state)
end
