# Markdown theme - color and size tokens for markdown rendering
# Integrates with the global $theme

class MarkdownTheme
  def initialize
    # Text colors - derive from global theme
    @text_color = $theme.text_primary
    @heading_color = $theme.accent
    @link_color = $theme.accent
    @code_color = $theme.warning
    @emphasis_color = 0xFF9AA5CE       # Slightly muted blue for italic
    @strikethrough_color = $theme.text_secondary

    # Background colors
    @code_bg_color = $theme.bg_secondary
    @code_inline_bg = $theme.bg_secondary
    @blockquote_bg = $theme.accent

    # Heading sizes
    @h1_size = 28.0
    @h2_size = 24.0
    @h3_size = 20.0
    @h4_size = 18.0
    @h5_size = 16.0
    @h6_size = 14.0
    @base_font_size = 14.0

    # Table colors
    @table_header_bg = $theme.bg_secondary
    @table_border_color = $theme.text_secondary
    @checkbox_checked_color = $theme.success
    @checkbox_unchecked_color = $theme.text_secondary

    # Mermaid colors
    @mermaid_node_fill = 0xFF4A90D9
    @mermaid_node_stroke = 0xFF2C5F8A
    @mermaid_node_text = 0xFFFFFFFF
    @mermaid_edge_color = $theme.text_secondary
    @mermaid_subgraph_bg = 0x20FFFFFF
    @mermaid_subgraph_border = $theme.text_secondary
    @mermaid_font_size = 12.0

    # Spacing
    @paragraph_spacing = 8.0
    @block_spacing = 12.0
    @list_indent = 24.0
    @blockquote_indent = 20.0
  end

  def text_color
    @text_color
  end

  def heading_color
    @heading_color
  end

  def link_color
    @link_color
  end

  def code_color
    @code_color
  end

  def emphasis_color
    @emphasis_color
  end

  def strikethrough_color
    @strikethrough_color
  end

  def code_bg_color
    @code_bg_color
  end

  def code_inline_bg
    @code_inline_bg
  end

  def blockquote_bg
    @blockquote_bg
  end

  def base_font_size
    @base_font_size
  end

  def paragraph_spacing
    @paragraph_spacing
  end

  def block_spacing
    @block_spacing
  end

  def list_indent
    @list_indent
  end

  def blockquote_indent
    @blockquote_indent
  end

  def table_header_bg
    @table_header_bg
  end

  def table_border_color
    @table_border_color
  end

  def checkbox_checked_color
    @checkbox_checked_color
  end

  def checkbox_unchecked_color
    @checkbox_unchecked_color
  end

  def mermaid_node_fill
    @mermaid_node_fill
  end

  def mermaid_node_stroke
    @mermaid_node_stroke
  end

  def mermaid_node_text
    @mermaid_node_text
  end

  def mermaid_edge_color
    @mermaid_edge_color
  end

  def mermaid_subgraph_bg
    @mermaid_subgraph_bg
  end

  def mermaid_subgraph_border
    @mermaid_subgraph_border
  end

  def mermaid_font_size
    @mermaid_font_size
  end

  def heading_size(level)
    if level == 1
      @h1_size
    elsif level == 2
      @h2_size
    elsif level == 3
      @h3_size
    elsif level == 4
      @h4_size
    elsif level == 5
      @h5_size
    else
      @h6_size
    end
  end
end
