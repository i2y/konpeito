# rbs_inline: enabled

# Castella UI Core - Widget / State / Layout / Component
#
# Port of ~/castella (Python) to Konpeito/JVM.
# Uses JWM + Skija via KUIRuntime for rendering.

# ===== Size Policy Constants =====
FIXED = 0
EXPANDING = 1
CONTENT = 2

# Propagated clear color from Container to child layouts during rendering.
# 0 = not set (use $theme.bg_canvas). Set by Container.redraw, read by Layout.redraw_children.
$__bg_clear_color = 0

# ===== Geometry =====

class Point
  #: (Float x, Float y) -> void
  def initialize(x, y)
    @x = x
    @y = y
  end

  #: () -> Float
  def x
    @x
  end

  #: () -> Float
  def y
    @y
  end

  #: (Float v) -> Float
  def x=(v)
    @x = v
  end

  #: (Float v) -> Float
  def y=(v)
    @y = v
  end
end

class Size
  #: (Float width, Float height) -> void
  def initialize(width, height)
    @width = width
    @height = height
  end

  #: () -> Float
  def width
    @width
  end

  #: () -> Float
  def height
    @height
  end

  #: (Float v) -> Float
  def width=(v)
    @width = v
  end

  #: (Float v) -> Float
  def height=(v)
    @height = v
  end
end

class Rect
  #: (Float x, Float y, Float width, Float height) -> void
  def initialize(x, y, width, height)
    @x = x
    @y = y
    @width = width
    @height = height
  end

  #: () -> Float
  def x
    @x
  end

  #: () -> Float
  def y
    @y
  end

  #: () -> Float
  def width
    @width
  end

  #: () -> Float
  def height
    @height
  end
end

# ===== Mouse Event =====

class MouseEvent
  #: (Point pos, Integer button) -> void
  def initialize(pos, button)
    @pos = pos
    @button = button
  end

  #: () -> Point
  def pos
    @pos
  end

  #: (Point v) -> Point
  def pos=(v)
    @pos = v
  end

  #: () -> Integer
  def button
    @button
  end
end

# ===== Wheel Event =====

class WheelEvent
  #: (Point pos, Float delta_y) -> void
  def initialize(pos, delta_y)
    @pos = pos
    @delta_y = delta_y
  end

  #: () -> Point
  def pos
    @pos
  end

  #: () -> Float
  def delta_y
    @delta_y
  end
end

# ===== Observer/Observable Pattern =====
# Port of ~/castella/castella/core.py ObservableBase/Observer

class ObservableBase
  def initialize
    @observers = []
  end

  #: (untyped observer) -> void
  def attach(observer)
    @observers << observer
    observer.on_attach(self)
  end

  #: (untyped observer) -> void
  def detach(observer)
    i = 0
    while i < @observers.length
      if @observers[i] == observer
        @observers.delete_at(i)
        observer.on_detach(self)
        return
      end
      i = i + 1
    end
  end

  #: () -> void
  def notify_observers
    # Iterate over a copy to avoid issues if observers are modified during notification
    copy = []
    i = 0
    while i < @observers.length
      copy << @observers[i]
      i = i + 1
    end
    i = 0
    while i < copy.length
      # Check observer is still attached before notifying
      j = 0
      still_attached = false
      while j < @observers.length
        if @observers[j] == copy[i]
          still_attached = true
          break
        end
        j = j + 1
      end
      copy[i].on_notify if still_attached
      i = i + 1
    end
  end
end

# ===== State =====
# Port of ~/castella/castella/core.py State[T]

class State < ObservableBase
  #: (untyped value) -> void
  def initialize(value)
    super()
    @value = value
  end

  #: () -> untyped
  def value
    @value
  end

  #: (untyped v) -> void
  def set(v)
    @value = v
    notify_observers
  end

  # In-place mutation operators (for @count += 1 pattern)
  # Ruby has no __iadd__, so += expands to @count = @count.+(1)
  # These mutate the value, notify observers, and return self.
  #: (untyped other) -> State
  def +(other)
    @value = @value + other
    notify_observers
    self
  end

  #: (untyped other) -> State
  def -(other)
    @value = @value - other
    notify_observers
    self
  end

  #: (untyped other) -> State
  def *(other)
    @value = @value * other
    notify_observers
    self
  end

  #: (untyped other) -> State
  def /(other)
    @value = @value / other
    notify_observers
    self
  end

  #: () -> String
  def to_s
    @value.to_s
  end

  #: () -> Integer
  def to_i
    @value.to_i
  end

  #: () -> Float
  def to_f
    @value.to_f
  end
end

# ===== ListState =====
# Port of ~/castella/castella/core.py ListState
# Reactive list that notifies observers on mutation

class ListState < ObservableBase
  #: (Array items) -> void
  def initialize(items)
    super()
    @items = []
    i = 0
    while i < items.length
      @items << items[i]
      i = i + 1
    end
  end

  #: () -> Integer
  def length
    @items.length
  end

  #: (Integer index) -> untyped
  def [](index)
    @items[index]
  end

  #: (Integer index, untyped value) -> untyped
  def []=(index, value)
    @items[index] = value
    notify_observers
  end

  #: (untyped value) -> void
  def push(value)
    @items << value
    notify_observers
  end

  #: () -> untyped
  def pop
    result = @items.pop
    notify_observers
    result
  end

  #: (Integer index) -> untyped
  def delete_at(index)
    result = @items.delete_at(index)
    notify_observers
    result
  end

  #: () -> void
  def clear
    @items = []
    notify_observers
  end

  #: (Array items) -> void
  def set(items)
    @items = []
    i = 0
    while i < items.length
      @items << items[i]
      i = i + 1
    end
    notify_observers
  end

  #: () { (untyped) -> void } -> void
  def each(&block)
    i = 0
    while i < @items.length
      block.call(@items[i])
      i = i + 1
    end
  end
end

# ===== ScrollState =====
# Port of ~/castella/castella/core.py ScrollState
# Observable scroll position that persists across view rebuilds

class ScrollState < ObservableBase
  def initialize
    super()
    @x = 0.0
    @y = 0.0
  end

  #: () -> Float
  def x
    @x
  end

  #: (Float v) -> void
  def set_x(v)
    if @x != v
      @x = v
      notify_observers
    end
  end

  #: () -> Float
  def y
    @y
  end

  #: (Float v) -> void
  def set_y(v)
    if @y != v
      @y = v
      notify_observers
    end
  end

  #: (Float x, Float y) -> void
  def set(x, y)
    changed = false
    if @x != x
      @x = x
      changed = true
    end
    if @y != y
      @y = y
      changed = true
    end
    notify_observers if changed
  end
end

# ===== InputState =====
# Port of ~/castella/castella/input.py InputState
# Holds single-line input state (text, cursor, selection, IME preedit).
# Persists across Component rebuilds when stored in Component#initialize.

class InputState
  #: (String placeholder) -> void
  def initialize(placeholder)
    @text = ""
    @placeholder = placeholder
    @cursor = 0
    @selection_start = -1
    @selection_end = -1
    @is_selecting = false
    @preedit_text = ""
    @preedit_cursor = 0
  end

  # --- Getters ---

  #: () -> String
  def value
    @text
  end

  #: () -> Integer
  def get_cursor
    @cursor
  end

  #: () -> String
  def get_placeholder
    @placeholder
  end

  # --- Text operations ---

  #: (String v) -> void
  def set(v)
    @text = v
    @cursor = v.length
  end

  #: (String text) -> void
  def insert(text)
    before = ""
    if @cursor > 0
      before = @text[0, @cursor]
    end
    rest_len = @text.length - @cursor
    after = @text[@cursor, rest_len]
    @text = before + text + after
    @cursor = @cursor + text.length
  end

  #: () -> bool
  def delete_prev
    if @cursor > 0
      before = ""
      if @cursor > 1
        before = @text[0, @cursor - 1]
      end
      rest_len = @text.length - @cursor
      after = @text[@cursor, rest_len]
      @text = before + after
      @cursor = @cursor - 1
      return true
    end
    false
  end

  #: () -> bool
  def delete_next
    if @cursor < @text.length
      before = ""
      if @cursor > 0
        before = @text[0, @cursor]
      end
      rest_start = @cursor + 1
      rest_len = @text.length - rest_start
      after = ""
      if rest_len > 0
        after = @text[rest_start, rest_len]
      end
      @text = before + after
      return true
    end
    false
  end

  # --- Cursor movement ---

  #: () -> bool
  def move_prev
    if @cursor > 0
      @cursor = @cursor - 1
      return true
    end
    false
  end

  #: () -> bool
  def move_next
    if @cursor < @text.length
      @cursor = @cursor + 1
      return true
    end
    false
  end

  #: () -> bool
  def move_home
    if @cursor > 0
      @cursor = 0
      return true
    end
    false
  end

  #: () -> bool
  def move_end
    if @cursor < @text.length
      @cursor = @text.length
      return true
    end
    false
  end

  # --- Selection ---

  #: () -> bool
  def has_selection
    if @selection_start < 0
      return false
    end
    if @selection_end < 0
      return false
    end
    if @selection_start == @selection_end
      return false
    end
    true
  end

  #: () -> Array
  def get_selection_range
    result_s = 0
    result_e = 0
    if has_selection
      s = @selection_start
      e = @selection_end
      if s > e
        result_s = e
        result_e = s
      else
        result_s = s
        result_e = e
      end
    end
    [result_s, result_e]
  end

  #: () -> String
  def get_selected_text
    result = ""
    if has_selection
      range = get_selection_range
      s = range[0]
      e = range[1]
      len = e - s
      result = @text[s, len]
    end
    result
  end

  #: () -> void
  def delete_selection
    if has_selection
      range = get_selection_range
      s = range[0]
      e = range[1]
      before = ""
      if s > 0
        before = @text[0, s]
      end
      rest_start = e
      rest_len = @text.length - e
      after = ""
      if rest_len > 0
        after = @text[rest_start, rest_len]
      end
      @text = before + after
      @cursor = s
      @selection_start = -1
      @selection_end = -1
      @is_selecting = false
    end
  end

  #: () -> void
  def clear_selection
    @selection_start = -1
    @selection_end = -1
    @is_selecting = false
  end

  #: () -> void
  def select_all
    if @text.length > 0
      @selection_start = 0
      @selection_end = @text.length
      @is_selecting = false
    end
  end

  #: (Integer pos) -> void
  def start_selection(pos)
    clear_selection
    @selection_start = pos
    @selection_end = pos
    @is_selecting = true
    @cursor = pos
  end

  #: (Integer pos) -> void
  def update_selection(pos)
    @selection_end = pos
    @cursor = pos
  end

  #: () -> void
  def end_selection
    @is_selecting = false
  end

  #: () -> bool
  def is_selecting
    @is_selecting
  end

  #: (Integer pos) -> void
  def set_cursor_by_click(pos)
    @cursor = pos
  end

  # --- IME ---

  #: () -> bool
  def has_preedit
    @preedit_text.length > 0
  end

  #: () -> String
  def get_display_text
    result = @text
    if has_preedit
      before = ""
      if @cursor > 0
        before = @text[0, @cursor]
      end
      rest_len = @text.length - @cursor
      after = @text[@cursor, rest_len]
      result = before + @preedit_text + after
    end
    result
  end

  #: (String text, Integer cursor) -> void
  def set_preedit(text, cursor)
    @preedit_text = text
    @preedit_cursor = cursor
  end

  #: () -> void
  def clear_preedit
    @preedit_text = ""
    @preedit_cursor = 0
  end

  #: () -> String
  def get_preedit_text
    @preedit_text
  end

  #: () -> Integer
  def get_preedit_cursor
    @preedit_cursor
  end

  # --- Focus lifecycle ---

  #: () -> void
  def start_editing
  end

  #: () -> void
  def finish_editing
    clear_preedit
    clear_selection
  end
end

# ===== MultilineInputState =====
# Holds multi-line input state (lines, cursor, selection, scroll, IME preedit).
# Persists across Component rebuilds when stored in Component#initialize.

class MultilineInputState
  #: (String text) -> void
  def initialize(text)
    @lines = [""]
    if text != nil && text.length > 0
      @lines = split_lines(text)
    end
    @row = @lines.length - 1
    @col = @lines[@row].length
    @target_col = -1
    @scroll_y = 0.0
    @manual_scroll = false
    @selection_start = [-1, -1]
    @selection_end = [-1, -1]
    @is_selecting = false
    @preedit_text = ""
    @preedit_cursor = 0
  end

  #: (String text) -> Array
  def split_lines(text)
    result = []
    current = ""
    i = 0
    while i < text.length
      ch = text[i]
      if ch == "\n"
        result << current
        current = ""
      else
        current = current + ch
      end
      i = i + 1
    end
    result << current
    result
  end

  # --- Getters ---

  #: () -> String
  def value
    get_text
  end

  #: () -> String
  def get_text
    result = ""
    i = 0
    while i < @lines.length
      if i > 0
        result = result + "\n"
      end
      result = result + @lines[i]
      i = i + 1
    end
    result
  end

  #: () -> Array
  def get_lines
    @lines
  end

  #: () -> Integer
  def get_row
    @row
  end

  #: () -> Integer
  def get_col
    @col
  end

  #: () -> Integer
  def get_target_col
    @target_col
  end

  #: () -> Float
  def get_scroll_y
    @scroll_y
  end

  #: (Float v) -> void
  def set_scroll_y(v)
    @scroll_y = v
  end

  #: () -> bool
  def is_manual_scroll
    @manual_scroll
  end

  #: (bool v) -> void
  def set_manual_scroll(v)
    @manual_scroll = v
  end

  #: (String t) -> void
  def set_text(t)
    @lines = split_lines(t)
    @row = @lines.length - 1
    @col = @lines[@row].length
    @target_col = -1
  end

  # --- Text operations ---

  #: (String text) -> void
  def insert_char(text)
    line = @lines[@row]
    before = ""
    if @col > 0
      before = line[0, @col]
    end
    after_len = line.length - @col
    after = ""
    if after_len > 0
      after = line[@col, after_len]
    end
    @lines[@row] = before + text + after
    @col = @col + text.length
    @target_col = -1
    @manual_scroll = false
  end

  #: () -> void
  def insert_newline
    line = @lines[@row]
    before = ""
    if @col > 0
      before = line[0, @col]
    end
    after_len = line.length - @col
    after = ""
    if after_len > 0
      after = line[@col, after_len]
    end
    @lines[@row] = before
    insert_line_after_row(@row, after)
    @row = @row + 1
    @col = 0
    @target_col = -1
  end

  #: (Integer row, String line_text) -> void
  def insert_line_after_row(row, line_text)
    new_lines = []
    j = 0
    while j <= row
      new_lines << @lines[j]
      j = j + 1
    end
    new_lines << line_text
    j = row + 1
    while j < @lines.length
      new_lines << @lines[j]
      j = j + 1
    end
    @lines = new_lines
  end

  #: () -> bool
  def delete_prev
    if @col > 0
      line = @lines[@row]
      before = ""
      if @col > 1
        before = line[0, @col - 1]
      end
      after_len = line.length - @col
      after = ""
      if after_len > 0
        after = line[@col, after_len]
      end
      @lines[@row] = before + after
      @col = @col - 1
      @target_col = -1
      return true
    elsif @row > 0
      prev_line = @lines[@row - 1]
      curr_line = @lines[@row]
      @lines[@row - 1] = prev_line + curr_line
      @lines.delete_at(@row)
      @row = @row - 1
      @col = prev_line.length
      @target_col = -1
      return true
    end
    false
  end

  #: () -> bool
  def delete_next
    line = @lines[@row]
    if @col < line.length
      before = ""
      if @col > 0
        before = line[0, @col]
      end
      rest_start = @col + 1
      rest_len = line.length - rest_start
      after = ""
      if rest_len > 0
        after = line[rest_start, rest_len]
      end
      @lines[@row] = before + after
      @target_col = -1
      return true
    elsif @row < @lines.length - 1
      next_line = @lines[@row + 1]
      @lines[@row] = line + next_line
      @lines.delete_at(@row + 1)
      @target_col = -1
      return true
    end
    false
  end

  # --- Cursor movement ---

  #: () -> void
  def move_left
    if @col > 0
      @col = @col - 1
    elsif @row > 0
      @row = @row - 1
      @col = @lines[@row].length
    end
    @target_col = -1
  end

  #: () -> void
  def move_right
    line = @lines[@row]
    if @col < line.length
      @col = @col + 1
    elsif @row < @lines.length - 1
      @row = @row + 1
      @col = 0
    end
    @target_col = -1
  end

  #: () -> bool
  def move_up
    if @row > 0
      if @target_col < 0
        @target_col = @col
      end
      @row = @row - 1
      line_len = @lines[@row].length
      @col = @target_col
      if @col > line_len
        @col = line_len
      end
      return true
    end
    false
  end

  #: () -> bool
  def move_down
    if @row < @lines.length - 1
      if @target_col < 0
        @target_col = @col
      end
      @row = @row + 1
      line_len = @lines[@row].length
      @col = @target_col
      if @col > line_len
        @col = line_len
      end
      return true
    end
    false
  end

  #: () -> bool
  def move_home
    if @col > 0
      @col = 0
      @target_col = -1
      return true
    end
    false
  end

  #: () -> bool
  def move_end
    line_len = @lines[@row].length
    if @col < line_len
      @col = line_len
      @target_col = -1
      return true
    end
    false
  end

  # --- Selection ---

  #: () -> bool
  def has_selection
    if @selection_start[0] < 0
      return false
    end
    if @selection_end[0] < 0
      return false
    end
    if @selection_start[0] == @selection_end[0] && @selection_start[1] == @selection_end[1]
      return false
    end
    true
  end

  #: () -> Array
  def get_selection_range
    result_sr = 0
    result_sc = 0
    result_er = 0
    result_ec = 0
    if has_selection
      sr = @selection_start[0]
      sc = @selection_start[1]
      er = @selection_end[0]
      ec = @selection_end[1]
      if sr > er
        result_sr = er
        result_sc = ec
        result_er = sr
        result_ec = sc
      elsif sr == er && sc > ec
        result_sr = sr
        result_sc = ec
        result_er = er
        result_ec = sc
      else
        result_sr = sr
        result_sc = sc
        result_er = er
        result_ec = ec
      end
    end
    [result_sr, result_sc, result_er, result_ec]
  end

  #: () -> String
  def get_selected_text
    result = ""
    if has_selection
      range = get_selection_range
      sr = range[0]
      sc = range[1]
      er = range[2]
      ec = range[3]
      if sr == er
        line = @lines[sr]
        len = ec - sc
        result = line[sc, len]
      else
        first_line = @lines[sr]
        first_len = first_line.length - sc
        result = first_line[sc, first_len]
        r = sr + 1
        while r < er
          result = result + "\n" + @lines[r]
          r = r + 1
        end
        last_line = @lines[er]
        result = result + "\n" + last_line[0, ec]
      end
    end
    result
  end

  #: () -> void
  def delete_selection
    if !has_selection
      return
    end
    range = get_selection_range
    sr = range[0]
    sc = range[1]
    er = range[2]
    ec = range[3]
    if sr == er
      delete_selection_single_line(sr, sc, ec)
    else
      delete_selection_multi_line(sr, sc, er, ec)
    end
    @row = sr
    @col = sc
    @selection_start = [-1, -1]
    @selection_end = [-1, -1]
    @is_selecting = false
  end

  #: (Integer row, Integer sc, Integer ec) -> void
  def delete_selection_single_line(row, sc, ec)
    line = @lines[row]
    before = ""
    if sc > 0
      before = line[0, sc]
    end
    after_len = line.length - ec
    after = ""
    if after_len > 0
      after = line[ec, after_len]
    end
    @lines[row] = before + after
  end

  #: (Integer sr, Integer sc, Integer er, Integer ec) -> void
  def delete_selection_multi_line(sr, sc, er, ec)
    first_part = ""
    if sc > 0
      first_line = @lines[sr]
      first_part = first_line[0, sc]
    end
    last_line = @lines[er]
    last_part = ""
    after_len = last_line.length - ec
    if after_len > 0
      last_part = last_line[ec, after_len]
    end
    @lines[sr] = first_part + last_part
    count = er - sr
    while count > 0
      @lines.delete_at(sr + 1)
      count = count - 1
    end
  end

  #: () -> void
  def clear_selection
    @selection_start = [-1, -1]
    @selection_end = [-1, -1]
    @is_selecting = false
  end

  #: () -> void
  def select_all
    if @lines.length > 0
      @selection_start = [0, 0]
      last_row = @lines.length - 1
      @selection_end = [last_row, @lines[last_row].length]
      @is_selecting = false
    end
  end

  #: (Integer row, Integer col) -> void
  def start_selection(row, col)
    clear_selection
    @selection_start = [row, col]
    @selection_end = [row, col]
    @is_selecting = true
    @row = row
    @col = col
  end

  #: (Integer row, Integer col) -> void
  def update_selection(row, col)
    @selection_end = [row, col]
    @row = row
    @col = col
  end

  #: () -> void
  def end_selection
    @is_selecting = false
  end

  #: () -> bool
  def is_selecting
    @is_selecting
  end

  # --- IME ---

  #: () -> bool
  def has_preedit
    @preedit_text.length > 0
  end

  #: (String text, Integer cursor) -> void
  def set_preedit(text, cursor)
    @preedit_text = text
    @preedit_cursor = cursor
  end

  #: () -> void
  def clear_preedit
    @preedit_text = ""
    @preedit_cursor = 0
  end

  #: () -> String
  def get_preedit_text
    @preedit_text
  end

  #: () -> Integer
  def get_preedit_cursor
    @preedit_cursor
  end

  # --- Focus lifecycle ---

  #: () -> void
  def finish_editing
    clear_preedit
    clear_selection
  end

  # --- Paste ---

  #: (String text) -> void
  def paste_text(text)
    i = 0
    while i < text.length
      ch = text[i]
      if ch == "\n"
        insert_newline
      else
        paste_single_char(ch)
      end
      i = i + 1
    end
    @target_col = -1
  end

  #: (String ch) -> void
  def paste_single_char(ch)
    line = @lines[@row]
    before = ""
    if @col > 0
      before = line[0, @col]
    end
    after_len = line.length - @col
    after = ""
    if after_len > 0
      after = line[@col, after_len]
    end
    @lines[@row] = before + ch + after
    @col = @col + 1
  end
end

# ===== Widget =====
# Port of ~/castella/castella/core.py Widget
# Now with RenderNode, lifecycle hooks, z-order, dirty tracking

class Widget
  def initialize
    @x = 0.0
    @y = 0.0
    @width = 0.0
    @height = 0.0
    @visible = true
    @dirty = true
    @parent = nil
    @width_policy = EXPANDING
    @height_policy = EXPANDING
    @flex = 1
    @z_index = 1
    @tab_index = 0
    @focusable = false
    @mounted = false
    @cached = false
    @depth = 0
    @enable_to_detach = true
    @render_node = nil
    @observables = []
    @pad_top = 0.0
    @pad_right = 0.0
    @pad_bottom = 0.0
    @pad_left = 0.0
  end

  # --- Size Policy / Style (method chaining) ---

  #: (Float w) -> Widget
  def fixed_width(w)
    @width_policy = FIXED
    @width = w
    self
  end

  #: (Float h) -> Widget
  def fixed_height(h)
    @height_policy = FIXED
    @height = h
    self
  end

  #: (Float w, Float h) -> Widget
  def fixed_size(w, h)
    fixed_width(w)
    fixed_height(h)
  end

  #: () -> Widget
  def fit_content
    @width_policy = CONTENT
    @height_policy = CONTENT
    self
  end

  #: (Integer f) -> Widget
  def flex(f)
    @flex = f
    self
  end

  #: (Integer p) -> Widget
  def set_width_policy(p)
    @width_policy = p
    self
  end

  #: (Integer p) -> Widget
  def set_height_policy(p)
    @height_policy = p
    self
  end

  #: (Float t, Float r, Float b, Float l) -> Widget
  def padding(t, r, b, l)
    @pad_top = t
    @pad_right = r
    @pad_bottom = b
    @pad_left = l
    self
  end

  #: (Integer z) -> Widget
  def z_index(z)
    @z_index = z
    # Invalidate parent's z-order cache
    if @parent != nil
      rn = @parent.get_render_node
      if rn != nil
        rn.invalidate_z_order
      end
    end
    self
  end

  #: () -> Integer
  def get_z_index
    @z_index
  end

  #: (Integer value) -> Widget
  def tab_index(value)
    @tab_index = value
    self
  end

  #: () -> Integer
  def get_tab_index
    @tab_index
  end

  #: (bool value) -> Widget
  def focusable(value)
    @focusable = value
    self
  end

  #: () -> bool
  def is_focusable
    @focusable
  end

  # --- Children (overridden by Layout) ---

  #: () -> Array
  def get_children
    []
  end

  # --- Layout Protocol ---

  #: (untyped painter) -> Size
  def measure(painter)
    Size.new(@width, @height)
  end

  #: (untyped painter) -> void
  def relocate(painter)
  end

  #: (untyped painter, bool completely) -> void
  def redraw(painter, completely)
  end

  # --- Position / Size ---

  #: () -> Point
  def get_pos
    Point.new(@x, @y)
  end

  #: () -> Size
  def get_size
    Size.new(@width, @height)
  end

  #: () -> Float
  def get_x
    @x
  end

  #: () -> Float
  def get_y
    @y
  end

  #: () -> Float
  def get_width
    @width
  end

  #: () -> Float
  def get_height
    @height
  end

  #: () -> Integer
  def get_width_policy
    @width_policy
  end

  #: () -> Integer
  def get_height_policy
    @height_policy
  end

  #: () -> Integer
  def get_flex
    @flex
  end

  #: (Point p) -> Widget
  def move(p)
    new_x = p.x
    new_y = p.y
    if new_x != @x || new_y != @y
      @x = new_x
      @y = new_y
      mark_layout_dirty
    end
    self
  end

  #: (Float x, Float y) -> Widget
  def move_xy(x, y)
    if x != @x || y != @y
      @x = x
      @y = y
      mark_layout_dirty
    end
    self
  end

  #: (Size s) -> Widget
  def resize(s)
    new_w = s.width
    new_h = s.height
    if new_w != @width || new_h != @height
      @width = new_w
      @height = new_h
      mark_layout_dirty
    end
    self
  end

  #: (Float w, Float h) -> Widget
  def resize_wh(w, h)
    if w != @width || h != @height
      @width = w
      @height = h
      mark_layout_dirty
    end
    self
  end

  # --- Parent / Tree ---

  #: (untyped p) -> void
  def set_parent(p)
    do_mount(p)
  end

  #: () -> untyped
  def get_parent
    @parent
  end

  #: () -> Integer
  def get_depth
    @depth
  end

  # --- RenderNode ---

  #: () -> untyped
  def get_render_node
    @render_node
  end

  #: () -> untyped
  def ensure_render_node
    if @render_node == nil
      @render_node = create_render_node
    end
    @render_node
  end

  #: () -> RenderNodeBase
  def create_render_node
    RenderNodeBase.new(self)
  end

  # --- Dirty Tracking ---
  # Delegated to RenderNode when available, with fallback to @dirty flag

  #: () -> bool
  def is_dirty
    if @render_node != nil
      return @render_node.is_paint_dirty
    end
    @dirty
  end

  #: () -> bool
  def is_layout_dirty
    if @render_node != nil
      return @render_node.is_layout_dirty
    end
    @dirty
  end

  #: () -> bool
  def is_subtree_dirty
    if @render_node != nil
      return @render_node.is_subtree_dirty
    end
    false
  end

  #: (bool flag) -> void
  def set_dirty(flag)
    @dirty = flag
    if @render_node != nil
      if flag
        @render_node.mark_paint_dirty
      else
        @render_node.clear_dirty
      end
    end
  end

  #: () -> void
  def mark_dirty
    @dirty = true
    if @render_node != nil
      @render_node.mark_paint_dirty
    end
    propagate_subtree_dirty
  end

  #: () -> void
  def mark_layout_dirty
    @dirty = true
    if @render_node != nil
      @render_node.mark_layout_dirty
    end
    propagate_subtree_dirty
  end

  #: () -> void
  def mark_paint_dirty
    @dirty = true
    if @render_node != nil
      @render_node.mark_paint_dirty
    end
    propagate_subtree_dirty
  end

  # Propagate subtree_dirty up the parent chain
  #: () -> void
  def propagate_subtree_dirty
    p = @parent
    while p != nil
      rn = p.get_render_node
      if rn != nil
        break if rn.is_subtree_dirty
        rn.mark_subtree_dirty
      end
      p = p.get_parent
    end
  end

  # --- Lifecycle ---

  #: () -> void
  def on_mount
  end

  #: () -> void
  def on_unmount
  end

  #: (untyped parent) -> void
  def do_mount(parent)
    if !@mounted
      @mounted = true
      @parent = parent
      @depth = parent != nil ? parent.get_depth + 1 : 0
      on_mount
    else
      # Already mounted - update parent (for cached widgets being re-parented)
      @parent = parent
      @depth = parent != nil ? parent.get_depth + 1 : 0
    end
  end

  #: () -> void
  def do_unmount
    # Skip unmount for cached widgets (they're being reused)
    if @cached
      return
    end
    if @mounted
      on_unmount
      @mounted = false
    end
  end

  #: () -> bool
  def is_mounted
    @mounted
  end

  #: () -> void
  def freeze_widget
    @enable_to_detach = false
  end

  # --- Observer Protocol ---

  #: (untyped o) -> void
  def on_attach(o)
    @observables << o
  end

  #: (untyped o) -> void
  def on_detach(o)
    i = 0
    while i < @observables.length
      if @observables[i] == o
        @observables.delete_at(i)
        return
      end
      i = i + 1
    end
  end

  #: () -> void
  def on_notify
    mark_paint_dirty
  end

  # --- Detach ---
  # Port of ~/castella/castella/core.py Widget.detach

  #: () -> void
  def detach
    do_unmount
    if @enable_to_detach
      # Detach from all observables (copy list for safe iteration)
      copy = []
      i = 0
      while i < @observables.length
        copy << @observables[i]
        i = i + 1
      end
      i = 0
      while i < copy.length
        copy[i].detach(self)
        i = i + 1
      end
    end
    # Clear App-level references to prevent ghost redraws
    app = App.current
    if app != nil
      app.clear_widget_refs(self)
    end
  end

  #: (untyped state) -> void
  def model(state)
    # Detach from old state if any
    if @observables.length > 0
      copy = []
      i = 0
      while i < @observables.length
        copy << @observables[i]
        i = i + 1
      end
      i = 0
      while i < copy.length
        copy[i].detach(self)
        i = i + 1
      end
    end
    state.attach(self)
  end

  # --- Hit Test ---

  #: (Point p) -> bool
  def contain(p)
    p.x >= @x && p.x < @x + @width && p.y >= @y && p.y < @y + @height
  end

  #: (Point p) -> Array
  def dispatch(p)
    if contain(p)
      local_p = Point.new(p.x - @x, p.y - @y)
      [self, local_p]
    else
      [nil, nil]
    end
  end

  #: (Point p, bool is_direction_x) -> Array
  def dispatch_to_scrollable(p, is_direction_x)
    [nil, nil]
  end

  #: () -> bool
  def is_scrollable
    false
  end

  # --- Events ---

  #: (MouseEvent ev) -> void
  def mouse_down(ev)
  end

  #: (MouseEvent ev) -> void
  def mouse_up(ev)
  end

  #: (MouseEvent ev) -> void
  def mouse_drag(ev)
  end

  #: () -> void
  def mouse_over
  end

  #: () -> void
  def mouse_out
  end

  #: (WheelEvent ev) -> void
  def mouse_wheel(ev)
  end

  #: (MouseEvent ev) -> void
  def cursor_pos(ev)
  end

  #: (String text) -> void
  def input_char(text)
  end

  #: (Integer key_code, Integer modifiers) -> void
  def input_key(key_code, modifiers)
  end

  #: (String text, Integer sel_start, Integer sel_end) -> void
  def ime_preedit(text, sel_start, sel_end)
  end

  # Text state for focus preservation across Component rebuilds
  # Override in Input/MultilineInput
  #: () -> String
  def get_text
    ""
  end

  #: (String t) -> void
  def set_text(t)
  end

  # Restore text without triggering update/requestFrame
  #: (String t) -> void
  def restore_text(t)
    set_text(t)
  end

  #: () -> void
  def focused
  end

  # Restore focus state without triggering update/requestFrame
  # Used during Component rebuild to avoid infinite rendering loop
  #: () -> void
  def restore_focus
    focused
  end

  #: () -> void
  def unfocused
  end

  # --- Update ---
  # Walk up the tree to find scrollable/component parent for targeted update

  #: () -> void
  def update
    parent = @parent
    root = nil
    while parent != nil
      if parent.is_scrollable
        root = parent
      end
      parent = parent.get_parent
    end

    app = App.current
    if app == nil
      return
    end

    if root == nil
      app.post_update(self)
    else
      app.post_update(root)
    end
  end
end

# ===== Layout =====
# Port of ~/castella/castella/core.py Layout
# Now with LayoutRenderNode, z-order dispatch, child lifecycle

class Layout < Widget
  def initialize
    super
    @children = []
    # Visual properties (background, border)
    @bg_color_val = 0
    @border_color_val = 0
    @custom_bg = false
    @custom_border = false
    @border_radius_val = 0.0
    @border_width_val = 1.0
    @bg_clear_color = nil
  end

  # --- Visual Properties (method chaining) ---

  #: (Integer c) -> Layout
  def bg_color(c)
    @bg_color_val = c
    @custom_bg = true
    self
  end

  #: (Integer c) -> Layout
  def border_color(c)
    @border_color_val = c
    @custom_border = true
    self
  end

  #: (Float r) -> Layout
  def border_radius(r)
    @border_radius_val = r
    self
  end

  #: (Float w) -> Layout
  def border_width(w)
    @border_width_val = w
    self
  end

  # Draw background and border if visual properties are set.
  #: (untyped painter) -> void
  def draw_visual_background(painter)
    if @custom_bg
      painter.fill_round_rect(0.0, 0.0, @width, @height, @border_radius_val, @bg_color_val)
      @bg_clear_color = @bg_color_val
    end
  end

  #: () -> Array
  def get_children
    @children
  end

  #: () -> LayoutRenderNode
  def create_render_node
    LayoutRenderNode.new(self)
  end

  #: (untyped w) -> Layout
  def add(w)
    # Remove from old parent if needed
    old_parent = w.get_parent
    if old_parent != nil && old_parent != self
      old_parent.remove_child_widget(w)
    end

    @children << w
    w.set_parent(self)

    # Sync with render node for z-order caching
    rn = ensure_render_node
    rn.add_child(w)
    self
  end

  #: (untyped w) -> void
  def remove_child_widget(w)
    i = 0
    while i < @children.length
      if @children[i] == w
        @children.delete_at(i)
        break
      end
      i = i + 1
    end
    rn = get_render_node
    if rn != nil
      rn.remove_child(w)
    end
  end

  #: (untyped w) -> void
  def remove(w)
    remove_child_widget(w)
    w.do_unmount
  end

  #: () -> void
  def clear_children
    @children = []
    rn = get_render_node
    if rn != nil
      rn.clear_children
    end
  end

  #: () -> void
  def detach
    super
    if @enable_to_detach
      i = 0
      while i < @children.length
        @children[i].detach
        i = i + 1
      end
    end
  end

  # --- Hit Test with z-order ---
  # Port of ~/castella/castella/core.py Layout.dispatch

  #: (Point p) -> Array
  def dispatch(p)
    if contain(p)
      # Use z-order: higher z-index receives events first
      rn = ensure_render_node
      hit_order = rn.iter_hit_test_order
      i = 0
      while i < hit_order.length
        result = hit_order[i].dispatch(p)
        target = result[0]
        adjusted = result[1]
        if target != nil
          return [target, adjusted]
        end
        i = i + 1
      end
      local_p = Point.new(p.x - @x, p.y - @y)
      [self, local_p]
    else
      [nil, nil]
    end
  end

  #: (Point p, bool is_direction_x) -> Array
  def dispatch_to_scrollable(p, is_direction_x)
    if contain(p)
      rn = ensure_render_node
      hit_order = rn.iter_hit_test_order
      i = 0
      while i < hit_order.length
        result = hit_order[i].dispatch_to_scrollable(p, is_direction_x)
        target = result[0]
        adjusted = result[1]
        if target != nil
          return [target, adjusted]
        end
        i = i + 1
      end
      if has_scrollbar(is_direction_x)
        return [self, p]
      end
      [nil, nil]
    else
      [nil, nil]
    end
  end

  #: (bool is_direction_x) -> bool
  def has_scrollbar(is_direction_x)
    false
  end

  # --- Redraw with z-order ---
  # Port of ~/castella/castella/core.py Layout.redraw
  # Separated into _relocate_children and _redraw_children

  #: (untyped painter, bool completely) -> void
  def redraw(painter, completely)
    relocate_children(painter)
    redraw_children(painter, completely)
  end

  #: (untyped painter) -> void
  def relocate_children(painter)
    # Subclasses override this (Column, Row, Box)
    relocate(painter)
  end

  #: (untyped painter, bool completely) -> void
  def redraw_children(painter, completely)
    # Determine effective clear color with 3-level fallback:
    # own @bg_clear_color > propagated $__bg_clear_color > $theme.bg_canvas
    has_own_bg = false
    if @bg_clear_color != nil
      has_own_bg = true
    end
    has_parent_bg = false
    if !has_own_bg && $__bg_clear_color != 0
      has_parent_bg = true
    end
    effective_clear = 0
    if has_own_bg
      effective_clear = @bg_clear_color
    else
      if has_parent_bg
        effective_clear = $__bg_clear_color
      else
        effective_clear = $theme.bg_canvas
      end
    end
    # When this layout itself is dirty (scroll, resize, etc.), force full child repaint.
    # This is in redraw_children (not redraw) because Column/Row override redraw without calling super.
    if is_dirty
      completely = true
      painter.fill_rect(0.0, 0.0, @width, @height, effective_clear)
    end
    # Use z-order: lower z-index drawn first (background to foreground)
    rn = ensure_render_node
    paint_order = rn.iter_paint_order
    i = 0
    while i < paint_order.length
      c = paint_order[i]
      if completely || c.is_dirty || c.is_subtree_dirty
        painter.save
        painter.translate(c.get_x - @x, c.get_y - @y)
        painter.clip_rect(0.0, 0.0, c.get_width, c.get_height)
        # Clear dirty widget's area before redrawing (off-screen surface retains old pixels)
        if !completely && c.is_dirty
          painter.fill_rect(0.0, 0.0, c.get_width, c.get_height, effective_clear)
        end
        c.redraw(painter, completely)
        painter.restore
        c.set_dirty(false)
      end
      i = i + 1
    end
  end
end

# ===== Component =====
# Port of ~/castella/castella/core.py Component
# Now with pending_rebuild flag and proper detach on rebuild

class Component < Layout
  def initialize
    super
    @width_policy = EXPANDING
    @height_policy = EXPANDING
    @child = nil
    @pending_rebuild = false
  end

  # Helper: create State + auto-attach
  #: (untyped initial) -> State
  def state(initial)
    s = State.new(initial)
    s.attach(self)
    s
  end

  # Subclass overrides: returns widget tree
  #: () -> untyped
  def view
    nil
  end

  # State change notification -> schedule rebuild
  #: () -> void
  def on_notify
    @pending_rebuild = true
    mark_paint_dirty
    app = App.current
    if app != nil
      app.post_update(self)
    end
  end

  #: (untyped painter, bool completely) -> void
  def redraw(painter, completely)
    # Handle pending rebuild
    if @pending_rebuild
      @pending_rebuild = false
      # Save focused widget's tab_index
      saved_focus_tab = -1
      app = App.current
      if app != nil
        focused = app.get_focused
        if focused != nil
          saved_focus_tab = focused.get_tab_index
        end
      end

      # Destroy old tree, build new tree
      if @child != nil
        remove(@child)
        @child.detach
        @child = nil
      end
      @child = view
      if @child != nil
        add(@child)
        completely = true
      end

      # Restore focus (text restoration not needed — InputState persists)
      if saved_focus_tab > 0 && app != nil
        focus_target = find_focusable_by_tab_index(@child, saved_focus_tab)
        if focus_target != nil
          app.set_focused(focus_target)
          focus_target.restore_focus
        end
      end
    end

    # Build view if needed
    if @child == nil
      @child = view
      if @child != nil
        add(@child)
        completely = true
      end
    end

    # Relocate + redraw
    if @children.length > 0
      relocate_children(painter)
      redraw_children(painter, completely)
    end
  end

  # Resize and position child to fill this Component (matching Python Castella)
  #: (untyped painter) -> void
  def relocate_children(painter)
    if @children.length > 0
      c = @children[0]
      c.resize_wh(@width, @height)
      c.move_xy(@x, @y)
    end
  end

  #: (untyped widget, Integer tab_index) -> untyped
  def find_focusable_by_tab_index(widget, tab_index)
    return nil if widget == nil
    if widget.is_focusable && widget.get_tab_index == tab_index
      return widget
    end
    children = widget.get_children
    i = 0
    while i < children.length
      result = find_focusable_by_tab_index(children[i], tab_index)
      if result != nil
        return result
      end
      i = i + 1
    end
    nil
  end

  #: (untyped painter) -> Size
  def measure(painter)
    if @child == nil
      Size.new(0.0, 0.0)
    else
      @child.measure(painter)
    end
  end
end

# ===== StatefulComponent =====
# Shorthand: Component that auto-attaches to a State

class StatefulComponent < Component
  #: (State state) -> void
  def initialize(state)
    super()
    model(state)
  end
end
