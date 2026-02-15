# rbs_inline: enabled

# RenderNode system - layout/paint dirty tracking and z-order caching
# Port of ~/castella/castella/render/node.py and layout_node.py

# Base render node with fine-grained dirty tracking
class RenderNodeBase
  #: (untyped widget) -> void
  def initialize(widget)
    @widget = widget
    @layout_dirty = true
    @paint_dirty = true
    @subtree_dirty = false
    @measured_size = nil
  end

  #: () -> untyped
  def get_widget
    @widget
  end

  # ===== Dirty Tracking =====

  #: () -> bool
  def is_layout_dirty
    @layout_dirty
  end

  #: () -> bool
  def is_paint_dirty
    @paint_dirty
  end

  #: () -> void
  def mark_layout_dirty
    @layout_dirty = true
    @paint_dirty = true
    @measured_size = nil
  end

  #: () -> void
  def mark_paint_dirty
    @paint_dirty = true
  end

  #: () -> bool
  def is_subtree_dirty
    @subtree_dirty
  end

  #: () -> void
  def mark_subtree_dirty
    @subtree_dirty = true
  end

  #: () -> void
  def clear_dirty
    @layout_dirty = false
    @paint_dirty = false
    @subtree_dirty = false
  end

  # ===== Layout =====

  #: (untyped painter) -> Size
  def cached_measure(painter)
    if @measured_size == nil || @layout_dirty
      @measured_size = @widget.measure(painter)
    end
    @measured_size
  end

  # ===== Hit Testing =====

  #: (Point point) -> bool
  def hit_test(point)
    @widget.contain(point)
  end
end

# Layout render node with z-order caching and child management
class LayoutRenderNode < RenderNodeBase
  #: (untyped widget) -> void
  def initialize(widget)
    super(widget)
    @children = []
    @sorted_children = nil
    @z_order_dirty = true
  end

  # ===== Child Management =====

  #: (untyped child) -> void
  def add_child(child)
    @children << child
    @z_order_dirty = true
    mark_layout_dirty
  end

  #: (untyped child) -> void
  def remove_child(child)
    i = 0
    while i < @children.length
      if @children[i] == child
        @children.delete_at(i)
        @z_order_dirty = true
        mark_layout_dirty
        return
      end
      i = i + 1
    end
  end

  #: () -> void
  def clear_children
    @children = []
    @sorted_children = nil
    @z_order_dirty = true
    mark_layout_dirty
  end

  #: () -> Integer
  def child_count
    @children.length
  end

  #: () -> Array
  def get_children
    @children
  end

  # ===== Z-Order Management =====

  #: () -> void
  def invalidate_z_order
    @z_order_dirty = true
    @sorted_children = nil
  end

  #: () -> Array
  def get_sorted_children
    if @z_order_dirty || @sorted_children == nil
      # Copy children list
      @sorted_children = []
      i = 0
      while i < @children.length
        @sorted_children << @children[i]
        i = i + 1
      end
      # Sort by z_index (bubble sort - children count is typically small)
      changed = true
      while changed
        changed = false
        j = 0
        while j < @sorted_children.length - 1
          if @sorted_children[j].get_z_index > @sorted_children[j + 1].get_z_index
            tmp = @sorted_children[j]
            @sorted_children[j] = @sorted_children[j + 1]
            @sorted_children[j + 1] = tmp
            changed = true
          end
          j = j + 1
        end
      end
      @z_order_dirty = false
    end
    @sorted_children
  end

  # Paint order: lower z-index first (background to foreground)
  #: () -> Array
  def iter_paint_order
    get_sorted_children
  end

  # Hit test order: higher z-index first (foreground to background)
  #: () -> Array
  def iter_hit_test_order
    sorted = get_sorted_children
    result = []
    i = sorted.length - 1
    while i >= 0
      result << sorted[i]
      i = i - 1
    end
    result
  end

  # ===== Dirty Propagation =====

  #: () -> bool
  def is_any_child_dirty
    i = 0
    while i < @children.length
      if @children[i].is_dirty
        return true
      end
      i = i + 1
    end
    false
  end
end

# Scrollable layout render node with viewport culling
class ScrollableLayoutRenderNode < LayoutRenderNode
  #: (untyped widget) -> void
  def initialize(widget)
    super(widget)
    @scroll_x = 0.0
    @scroll_y = 0.0
    @viewport_width = 0.0
    @viewport_height = 0.0
    @viewport_set = false
  end

  #: () -> Float
  def get_scroll_x
    @scroll_x
  end

  #: (Float v) -> void
  def set_scroll_x(v)
    if @scroll_x != v
      @scroll_x = v
      mark_paint_dirty
    end
  end

  #: () -> Float
  def get_scroll_y
    @scroll_y
  end

  #: (Float v) -> void
  def set_scroll_y(v)
    if @scroll_y != v
      @scroll_y = v
      mark_paint_dirty
    end
  end

  #: (Float w, Float h) -> void
  def set_viewport_size(w, h)
    @viewport_width = w
    @viewport_height = h
    @viewport_set = true
  end

  #: (untyped child) -> bool
  def is_child_visible(child)
    if !@viewport_set
      return true
    end
    cx = child.get_x - @scroll_x
    cy = child.get_y - @scroll_y
    cw = child.get_width
    ch = child.get_height
    !(cx + cw < 0.0 || cx > @viewport_width || cy + ch < 0.0 || cy > @viewport_height)
  end
end
