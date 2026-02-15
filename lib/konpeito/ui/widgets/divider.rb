# Divider widget - horizontal line separator
# Port of Castella Divider

class Divider < Widget
  def initialize
    super
    @color_val = 0
    @custom_color = false
    @width_policy = EXPANDING
    @height_policy = FIXED
    @height = 1.0
  end

  def color(c)
    @color_val = c
    @custom_color = true
    self
  end

  def redraw(painter, completely)
    c = @custom_color ? @color_val : $theme.border
    painter.draw_line(0.0, 0.0, @width, 0.0, c, 1.0)
  end
end

# Top-level helper
def Divider()
  Divider.new
end
