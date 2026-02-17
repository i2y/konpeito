# NetImage widget - displays an image from a network URL
# Port of Castella NetImage

class NetImageWidget < Widget
  def initialize(url)
    super()
    @url = url
    @image_id = 0
    @img_width = 0.0
    @img_height = 0.0
    @fit_mode = IMAGE_FIT_CONTAIN
  end

  def fit(mode)
    @fit_mode = mode
    self
  end

  def set_url(url)
    @url = url
    @image_id = 0
    @img_width = 0.0
    @img_height = 0.0
    mark_dirty
  end

  def load_if_needed(painter)
    if @image_id == 0
      @image_id = painter.load_net_image(@url)
      if @image_id != 0
        @img_width = painter.get_image_width(@image_id) * 1.0
        @img_height = painter.get_image_height(@image_id) * 1.0
      end
    end
  end

  def measure(painter)
    load_if_needed(painter)
    if @image_id != 0
      Size.new(@img_width, @img_height)
    else
      Size.new(100.0, 100.0)
    end
  end

  def redraw(painter, completely)
    load_if_needed(painter)
    if @image_id == 0
      # Draw placeholder while loading or on error
      painter.fill_round_rect(0.0, 0.0, @width, @height, 4.0, 0x40FFFFFF)
      painter.stroke_round_rect(0.0, 0.0, @width, @height, 4.0, 0x80FFFFFF, 1.0)
      return
    end

    if @fit_mode == IMAGE_FIT_FILL
      painter.draw_image(@image_id, 0.0, 0.0, @width, @height)
    elsif @fit_mode == IMAGE_FIT_CONTAIN
      draw_fitted(painter, true)
    else
      draw_fitted(painter, false)
    end
  end

  def draw_fitted(painter, contain)
    if @img_width < 1.0 || @img_height < 1.0 || @width < 1.0 || @height < 1.0
      return
    end
    img_aspect = @img_width / @img_height
    widget_aspect = @width / @height

    if contain
      if img_aspect > widget_aspect
        new_w = @width
        new_h = @width / img_aspect
      else
        new_h = @height
        new_w = @height * img_aspect
      end
    else
      if img_aspect > widget_aspect
        new_h = @height
        new_w = @height * img_aspect
      else
        new_w = @width
        new_h = @width / img_aspect
      end
    end

    dx = (@width - new_w) / 2.0
    dy = (@height - new_h) / 2.0
    painter.draw_image(@image_id, dx, dy, new_w, new_h)
  end
end

# Top-level helper
def NetImage(url)
  NetImageWidget.new(url)
end
