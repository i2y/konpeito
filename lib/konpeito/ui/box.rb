# rbs_inline: enabled

# Box layout - overlay/stack of children (all at same position)
# Port of Castella Box

class Box < Layout
  def initialize
    super
  end

  #: (untyped painter) -> void
  def relocate_children(painter)
    i = 0
    while i < @children.length
      c = @children[i]
      if c.get_width_policy == EXPANDING
        c.resize_wh(@width, c.get_height)
      end
      if c.get_height_policy == EXPANDING
        c.resize_wh(c.get_width, @height)
      end
      c.move_xy(@x, @y)
      i = i + 1
    end
  end
end

# Top-level helper
#: (*untyped children) -> Box
def Box(*children)
  box = Box.new
  i = 0
  while i < children.length
    box.add(children[i])
    i = i + 1
  end
  box
end
