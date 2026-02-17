# Markdown widget - renders markdown text
# Combines MarkdownParser + MarkdownRenderer

class Markdown < Widget
  def initialize(text)
    super()
    @source = text
    @md_theme = MarkdownTheme.new
    @parser = MarkdownParser.new
    @renderer = MarkdownRenderer.new(@md_theme)
    @ast = nil
    @content_height = 0.0
    @padding_val = 12.0
  end

  def padding(p)
    @padding_val = p
    self
  end

  def set_text(t)
    @source = t
    @ast = nil
    mark_dirty
  end

  def get_text
    @source
  end

  def measure(painter)
    ensure_parsed
    h = @renderer.measure_height(painter, @ast, @width, @padding_val)
    Size.new(@width, h)
  end

  def redraw(painter, completely)
    ensure_parsed
    # Background
    painter.fill_rect(0.0, 0.0, @width, @height, $theme.bg_canvas)
    # Render markdown
    @content_height = @renderer.render(painter, @ast, @width, @padding_val)
  end

  def ensure_parsed
    if @ast == nil
      @ast = @parser.parse(@source)
    end
  end
end

# Top-level helper
def Markdown(text)
  Markdown.new(text)
end
