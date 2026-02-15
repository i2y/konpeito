# Tree - expandable tree view widget with virtual scroll
# Features: expand/collapse, selection, hover highlight, icons,
#           virtual scroll (only visible rows rendered)

TREE_ROW_HEIGHT = 26.0
TREE_INDENT = 20.0
TREE_ICON_SIZE = 16.0
TREE_TOGGLE_SIZE = 16.0
TREE_SCROLLBAR_WIDTH = 8.0

# TreeNode - data model for tree items
class TreeNode
  def initialize(id, label)
    @id = id
    @label = label
    @children = []
    @icon = nil
    @data = nil
  end

  def id
    @id
  end

  def label
    @label
  end

  def children
    @children
  end

  def icon
    @icon
  end

  def data
    @data
  end

  def set_icon(i)
    @icon = i
    self
  end

  def set_data(d)
    @data = d
    self
  end

  def add_child(child)
    @children << child
    self
  end

  def has_children
    @children.length > 0
  end
end

# TreeState - reactive state for tree
class TreeState < ObservableBase
  def initialize(nodes)
    super()
    @nodes = nodes               # Array of TreeNode (root nodes)
    @expanded_ids = []            # Array of expanded node IDs
    @selected_id = "none"
  end

  def nodes
    @nodes
  end

  def selected_id
    @selected_id
  end

  def is_expanded(id)
    i = 0
    while i < @expanded_ids.length
      if @expanded_ids[i] == id
        return true
      end
      i = i + 1
    end
    false
  end

  def toggle_expanded(id)
    if is_expanded(id)
      collapse(id)
    else
      expand(id)
    end
  end

  def expand(id)
    if is_expanded(id)
      return
    end
    @expanded_ids << id
    notify_observers
  end

  def collapse(id)
    new_ids = []
    i = 0
    while i < @expanded_ids.length
      if @expanded_ids[i] != id
        new_ids << @expanded_ids[i]
      end
      i = i + 1
    end
    @expanded_ids = new_ids
    notify_observers
  end

  def expand_all
    collect_all_ids(@nodes)
    notify_observers
  end

  def collapse_all
    @expanded_ids = []
    notify_observers
  end

  def select(id)
    @selected_id = id
    notify_observers
  end

  def set_nodes(n)
    @nodes = n
    @expanded_ids = []
    @selected_id = "none"
    notify_observers
  end

  private

  def collect_all_ids(nodes)
    i = 0
    while i < nodes.length
      node = nodes[i]
      if node.has_children
        @expanded_ids << node.id
        collect_all_ids(node.children)
      end
      i = i + 1
    end
  end
end

# Tree widget - custom drawing with virtual scroll
class Tree < Widget
  def initialize(state)
    super()
    @state = state
    @scroll_y = 0.0
    @max_scroll = 0.0
    @scrollable_flag = true
    @hover_row = -1
    @visible_nodes = []     # Flat list of [node, depth] pairs for rendering
    @width_policy = EXPANDING
    @height_policy = EXPANDING
    @state.attach(self)
  end

  def on_attach(observable)
  end

  def on_detach(observable)
  end

  def on_notify
    rebuild_visible
    mark_dirty
    update
  end

  def get_scrollable
    @scrollable_flag
  end

  def rebuild_visible
    @visible_nodes = []
    collect_visible(@state.nodes, 0)
  end

  def collect_visible(nodes, depth)
    i = 0
    while i < nodes.length
      node = nodes[i]
      @visible_nodes << [node, depth]
      if node.has_children
        if @state.is_expanded(node.id)
          collect_visible(node.children, depth + 1)
        end
      end
      i = i + 1
    end
  end

  def redraw(painter, completely)
    rebuild_visible
    visible_h = @height
    compute_tree_scroll(visible_h)

    # Background
    painter.fill_rect(0.0, 0.0, @width, @height, $theme.bg_primary)

    # Clip and draw visible rows
    painter.save
    painter.clip_rect(0.0, 0.0, @width, @height)

    first_row = tree_float_to_row(@scroll_y / TREE_ROW_HEIGHT)
    if first_row < 0
      first_row = 0
    end
    last_row = tree_float_to_row((@scroll_y + visible_h) / TREE_ROW_HEIGHT) + 1
    if last_row > @visible_nodes.length
      last_row = @visible_nodes.length
    end

    ri = first_row
    while ri < last_row
      draw_tree_row(painter, ri)
      ri = ri + 1
    end

    painter.restore

    # Scrollbar
    draw_tree_scrollbar(painter, visible_h)
  end

  def draw_tree_row(painter, ri)
    entry = @visible_nodes[ri]
    node = entry[0]
    depth = entry[1]
    ri_f = ri * 1.0
    row_y = ri_f * TREE_ROW_HEIGHT - @scroll_y

    # Background: selection > hover > alternating
    bg = compute_tree_row_bg(painter, ri, node)
    painter.fill_rect(0.0, row_y, @width, TREE_ROW_HEIGHT, bg)

    # Indent
    indent = depth * 1.0 * TREE_INDENT + 8.0

    # Toggle icon (expand/collapse arrow)
    if node.has_children
      draw_toggle(painter, indent, row_y, node)
    end

    # Label
    label_x = indent + TREE_TOGGLE_SIZE + 4.0
    ascent = painter.get_text_ascent($theme.font_family, 13.0)
    mh = painter.measure_text_height($theme.font_family, 13.0)
    label_y = row_y + (TREE_ROW_HEIGHT - mh) / 2.0 + ascent
    tc = $theme.text_primary
    painter.draw_text(node.label, label_x, label_y, $theme.font_family, 13.0, tc)

    # Bottom border
    bc = painter.with_alpha($theme.border, 30)
    painter.draw_line(0.0, row_y + TREE_ROW_HEIGHT, @width, row_y + TREE_ROW_HEIGHT, bc, 1.0)
  end

  def draw_toggle(painter, indent, row_y, node)
    # Draw a small triangle: > for collapsed, v for expanded
    tx = indent + TREE_TOGGLE_SIZE / 2.0
    ty = row_y + TREE_ROW_HEIGHT / 2.0
    tc = $theme.text_secondary
    s = 5.0
    if @state.is_expanded(node.id)
      # Down arrow (v)
      painter.fill_triangle(tx - s, ty - s / 2.0,
                            tx + s, ty - s / 2.0,
                            tx, ty + s / 2.0, tc)
    else
      # Right arrow (>)
      painter.fill_triangle(tx - s / 2.0, ty - s,
                            tx + s / 2.0, ty,
                            tx - s / 2.0, ty + s, tc)
    end
  end

  def compute_tree_row_bg(painter, ri, node)
    bg = $theme.bg_primary
    if node.id == @state.selected_id
      ac = $theme.accent
      bg = painter.with_alpha(ac, 50)
    elsif ri == @hover_row
      bg = painter.lighten_color(bg, 0.08)
    end
    bg
  end

  def draw_tree_scrollbar(painter, visible_h)
    if @max_scroll <= 0.0
      return
    end
    vn_len = @visible_nodes.length * 1.0
    content_h = vn_len * TREE_ROW_HEIGHT
    sb_x = @width - TREE_SCROLLBAR_WIDTH
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
    painter.fill_rect(sb_x, 0.0, TREE_SCROLLBAR_WIDTH, visible_h, $theme.scrollbar_bg)
    painter.fill_round_rect(sb_x + 1.0, sb_pos, TREE_SCROLLBAR_WIDTH - 2.0, sb_h, 3.0, $theme.scrollbar_fg)
  end

  # --- Event Handlers ---

  def mouse_up(ev)
    mx = ev.pos.x
    my = ev.pos.y
    row_idx = tree_row_at_y(my)
    if row_idx < 0
      return
    end
    if row_idx >= @visible_nodes.length
      return
    end
    entry = @visible_nodes[row_idx]
    node = entry[0]
    depth = entry[1]
    indent = depth * 1.0 * TREE_INDENT + 8.0
    toggle_end = indent + TREE_TOGGLE_SIZE
    if mx < toggle_end
      if node.has_children
        @state.toggle_expanded(node.id)
        return
      end
    end
    @state.select(node.id)
  end

  def cursor_pos(ev)
    my = ev.pos.y
    old_hr = @hover_row
    @hover_row = tree_row_at_y(my)
    if @hover_row != old_hr
      mark_dirty
      update
    end
  end

  def mouse_out
    if @hover_row != -1
      @hover_row = -1
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

  def compute_tree_scroll(visible_h)
    vn_len = @visible_nodes.length * 1.0
    content_h = vn_len * TREE_ROW_HEIGHT
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

  def tree_row_at_y(y)
    row = tree_float_to_row((y + @scroll_y) / TREE_ROW_HEIGHT)
    if row < 0
      row = -1
    end
    if row >= @visible_nodes.length
      row = -1
    end
    row
  end

  def tree_float_to_row(f)
    # Convert float to integer row index without .to_i (JVM limitation)
    r = 0
    while r * 1.0 + 1.0 <= f
      r = r + 1
    end
    r
  end
end

# Top-level helper
def Tree(state)
  Tree.new(state)
end
