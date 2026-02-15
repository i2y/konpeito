# Markdown renderer - cursor-based rendering using KUIRuntime painter API
# Walks the MdNode AST and emits drawing commands

class MarkdownRenderer
  def initialize(theme)
    @theme = theme
    @cursor_x = 0.0
    @cursor_y = 0.0
    @list_depth = 0
    @list_counters = []
    @font_family = $theme.font_family
  end

  def render(painter, ast, width, padding)
    @cursor_x = padding
    @cursor_y = padding
    @list_depth = 0
    @list_counters = []
    content_width = width - padding * 2.0
    if content_width < 1.0
      content_width = 1.0
    end
    i = 0
    while i < ast.children.length
      render_node(painter, ast.children[i], content_width)
      i = i + 1
    end
    @cursor_y + padding
  end

  def measure_height(painter, ast, width, padding)
    total = padding * 2.0
    content_width = width - padding * 2.0
    if content_width < 1.0
      content_width = 1.0
    end
    i = 0
    while i < ast.children.length
      total = total + estimate_node_height(painter, ast.children[i], content_width)
      i = i + 1
    end
    total
  end

  def render_node(painter, node, width)
    t = node.type
    if t == MD_HEADING
      render_heading(painter, node, width)
    elsif t == MD_PARAGRAPH
      render_paragraph(painter, node, width)
    elsif t == MD_CODE_BLOCK
      render_code_block(painter, node, width)
    elsif t == MD_BLOCKQUOTE
      render_blockquote(painter, node, width)
    elsif t == MD_LIST
      render_list(painter, node, width)
    elsif t == MD_TABLE
      render_table(painter, node, width)
    elsif t == MD_HORIZONTAL_RULE
      render_hr(painter, width)
    elsif t == MD_IMAGE
      render_image(painter, node, width)
    elsif t == MD_MERMAID
      render_mermaid(painter, node, width)
    end
  end

  # --- Heading ---
  def render_heading(painter, node, width)
    font_size = @theme.heading_size(node.level)
    @cursor_y = @cursor_y + @theme.block_spacing

    text = extract_text(node.children)
    ascent = painter.get_text_ascent(@font_family, font_size)
    color = @theme.heading_color

    # Faux bold: draw twice with 0.5px offset
    painter.draw_text(text, @cursor_x, @cursor_y + ascent, @font_family, font_size, color)
    painter.draw_text(text, @cursor_x + 0.5, @cursor_y + ascent, @font_family, font_size, color)

    @cursor_y = @cursor_y + font_size * 1.5
  end

  # --- Paragraph ---
  def render_paragraph(painter, node, width)
    segments = collect_segments(node.children, false, false, false, false, "")
    font_size = @theme.base_font_size
    line_height = font_size * 1.5
    ascent = painter.get_text_ascent(@font_family, font_size)

    indent = @list_depth * @theme.list_indent
    x = @cursor_x + indent
    available_width = width - indent
    start_x = x

    si = 0
    while si < segments.length
      seg = segments[si]
      seg_text = seg[0]
      seg_bold = seg[1]
      seg_italic = seg[2]
      seg_strike = seg[3]
      seg_code = seg[4]
      seg_href = seg[5]

      # Determine color
      if seg_href.length > 0
        color = @theme.link_color
      elsif seg_code
        color = @theme.code_color
      elsif seg_italic
        color = @theme.emphasis_color
      elsif seg_strike
        color = @theme.strikethrough_color
      else
        color = @theme.text_color
      end

      # Split segment text by words for wrapping
      words = seg_text.split(" ")
      wi = 0
      while wi < words.length
        word = words[wi]
        if wi > 0
          word = " " + word
        end
        word_w = painter.measure_text_width(word, @font_family, font_size)

        # Check if word fits on current line
        if x + word_w > @cursor_x + available_width && x > start_x
          # Wrap to next line
          @cursor_y = @cursor_y + line_height
          x = start_x
          # Trim leading space after wrap
          if word.start_with?(" ")
            word = word[1, word.length - 1]
            word_w = painter.measure_text_width(word, @font_family, font_size)
          end
        end

        # Draw inline code background
        if seg_code
          code_pad = 3.0
          painter.fill_round_rect(x - code_pad, @cursor_y, word_w + code_pad * 2.0, font_size * 1.2, 3.0, @theme.code_inline_bg)
        end

        # Draw text
        painter.draw_text(word, x, @cursor_y + ascent, @font_family, font_size, color)

        # Faux bold
        if seg_bold
          painter.draw_text(word, x + 0.5, @cursor_y + ascent, @font_family, font_size, color)
        end

        # Strikethrough line
        if seg_strike
          strike_y = @cursor_y + font_size * 0.55
          painter.draw_line(x, strike_y, x + word_w, strike_y, color, 1.0)
        end

        # Link underline
        if seg_href.length > 0
          underline_y = @cursor_y + ascent + 2.0
          painter.fill_rect(x, underline_y, word_w, 1.0, color)
        end

        x = x + word_w
        wi = wi + 1
      end

      si = si + 1
    end

    @cursor_y = @cursor_y + line_height + @theme.paragraph_spacing
  end

  # --- Code block ---
  def render_code_block(painter, node, width)
    font_size = @theme.base_font_size
    line_height = font_size + 4.0
    code_padding = 8.0

    lines = node.content.split("\n")
    block_height = lines.length * line_height + code_padding * 2.0

    # Background
    painter.fill_round_rect(@cursor_x, @cursor_y, width, block_height, 4.0, @theme.code_bg_color)

    # Lines
    ascent = painter.get_text_ascent(@font_family, font_size)
    y = @cursor_y + code_padding + ascent
    li = 0
    while li < lines.length
      painter.draw_text(lines[li], @cursor_x + code_padding, y, @font_family, font_size, @theme.code_color)
      y = y + line_height
      li = li + 1
    end

    @cursor_y = @cursor_y + block_height + @theme.block_spacing
  end

  # --- Blockquote ---
  def render_blockquote(painter, node, width)
    indent = @theme.blockquote_indent
    bar_width = 4.0
    start_y = @cursor_y

    @cursor_x = @cursor_x + indent
    ci = 0
    while ci < node.children.length
      render_node(painter, node.children[ci], width - indent)
      ci = ci + 1
    end
    @cursor_x = @cursor_x - indent

    # Draw left bar
    bar_height = @cursor_y - start_y
    if bar_height > 0.0
      painter.fill_rect(@cursor_x, start_y, bar_width, bar_height, @theme.blockquote_bg)
    end
  end

  # --- List ---
  def render_list(painter, node, width)
    @list_depth = @list_depth + 1
    counter = node.start_num
    if node.ordered
      @list_counters.push(counter)
    end

    ci = 0
    while ci < node.children.length
      child = node.children[ci]
      if child.type == MD_LIST_ITEM
        render_list_item(painter, child, width, node.ordered)
        if node.ordered
          counter = counter + 1
          if @list_counters.length > 0
            @list_counters[@list_counters.length - 1] = counter
          end
        end
      end
      ci = ci + 1
    end

    if node.ordered && @list_counters.length > 0
      @list_counters.pop
    end
    @list_depth = @list_depth - 1
  end

  def render_list_item(painter, node, width, ordered)
    indent = @list_depth * @theme.list_indent
    font_size = @theme.base_font_size
    ascent = painter.get_text_ascent(@font_family, font_size)
    color = @theme.text_color

    marker_x = @cursor_x + indent - 16.0
    marker_y = @cursor_y + ascent

    if node.checked >= 0
      # Task list item: draw checkbox
      box_size = font_size * 0.75
      box_x = marker_x
      box_y = @cursor_y + (font_size * 1.5 - box_size) / 2.0
      if node.checked == 1
        # Filled checkbox
        painter.fill_rect(box_x, box_y, box_size, box_size, @theme.checkbox_checked_color)
        # Draw checkmark as text
        painter.draw_text("v", box_x + 1.0, box_y + box_size - 2.0, @font_family, font_size * 0.65, 0xFFFFFFFF)
      else
        # Empty checkbox outline (draw 4 sides)
        painter.fill_rect(box_x, box_y, box_size, 1.0, @theme.checkbox_unchecked_color)
        painter.fill_rect(box_x, box_y + box_size - 1.0, box_size, 1.0, @theme.checkbox_unchecked_color)
        painter.fill_rect(box_x, box_y, 1.0, box_size, @theme.checkbox_unchecked_color)
        painter.fill_rect(box_x + box_size - 1.0, box_y, 1.0, box_size, @theme.checkbox_unchecked_color)
      end
    elsif ordered
      counter = 1
      if @list_counters.length > 0
        counter = @list_counters[@list_counters.length - 1]
      end
      marker = counter.to_s + "."
      painter.draw_text(marker, marker_x, marker_y, @font_family, font_size, color)
    else
      painter.draw_text("*", marker_x + 4.0, marker_y, @font_family, font_size, color)
    end

    # Render item children
    ci = 0
    while ci < node.children.length
      render_node(painter, node.children[ci], width)
      ci = ci + 1
    end
  end

  # --- Horizontal rule ---
  def render_hr(painter, width)
    @cursor_y = @cursor_y + @theme.block_spacing / 2.0
    painter.fill_rect(@cursor_x, @cursor_y, width, 1.0, @theme.text_color)
    @cursor_y = @cursor_y + @theme.block_spacing / 2.0 + 1.0
  end

  # --- Table ---
  def render_table(painter, node, width)
    font_size = @theme.base_font_size
    ascent = painter.get_text_ascent(@font_family, font_size)
    cell_pad = 8.0
    row_height = font_size * 1.5 + cell_pad * 2.0

    # Count columns from header row
    num_cols = 0
    if node.children.length > 0
      num_cols = node.children[0].children.length
    end
    if num_cols == 0
      return
    end

    # Measure phase: compute max cell text width per column
    col_widths = []
    ci = 0
    while ci < num_cols
      col_widths.push(0.0)
      ci = ci + 1
    end

    ri = 0
    while ri < node.children.length
      row = node.children[ri]
      ci = 0
      while ci < row.children.length && ci < num_cols
        cell = row.children[ci]
        text = extract_text(cell.children)
        text_w = painter.measure_text_width(text, @font_family, font_size)
        cell_w = text_w + cell_pad * 2.0
        if cell_w > col_widths[ci]
          col_widths[ci] = cell_w
        end
        ci = ci + 1
      end
      ri = ri + 1
    end

    # Distribute widths: scale to fit available width
    total_w = 0.0
    ci = 0
    while ci < num_cols
      total_w = total_w + col_widths[ci]
      ci = ci + 1
    end

    if total_w < width && total_w > 0.0
      # Scale up proportionally
      scale = width / total_w
      ci = 0
      while ci < num_cols
        col_widths[ci] = col_widths[ci] * scale
        ci = ci + 1
      end
    elsif total_w > width && total_w > 0.0
      # Scale down proportionally
      scale = width / total_w
      ci = 0
      while ci < num_cols
        col_widths[ci] = col_widths[ci] * scale
        ci = ci + 1
      end
    end

    table_x = @cursor_x
    table_width = 0.0
    ci = 0
    while ci < num_cols
      table_width = table_width + col_widths[ci]
      ci = ci + 1
    end

    @cursor_y = @cursor_y + @theme.block_spacing / 2.0

    # Draw rows
    ri = 0
    while ri < node.children.length
      row = node.children[ri]
      row_y = @cursor_y

      # Header row background
      if row.is_header
        painter.fill_rect(table_x, row_y, table_width, row_height, @theme.table_header_bg)
      end

      # Draw cells
      cell_x = table_x
      ci = 0
      while ci < row.children.length && ci < num_cols
        cell = row.children[ci]
        text = extract_text(cell.children)
        text_w = painter.measure_text_width(text, @font_family, font_size)
        col_w = col_widths[ci]

        # Compute text x position based on alignment
        align = cell.align
        if align == 1
          # Center
          tx = cell_x + (col_w - text_w) / 2.0
        elsif align == 2
          # Right
          tx = cell_x + col_w - text_w - cell_pad
        else
          # Left
          tx = cell_x + cell_pad
        end

        text_y = row_y + cell_pad + ascent
        color = @theme.text_color

        painter.draw_text(text, tx, text_y, @font_family, font_size, color)
        # Faux bold for header
        if row.is_header
          painter.draw_text(text, tx + 0.5, text_y, @font_family, font_size, color)
        end

        cell_x = cell_x + col_w
        ci = ci + 1
      end

      # Draw horizontal line below row
      painter.fill_rect(table_x, row_y + row_height, table_width, 1.0, @theme.table_border_color)

      @cursor_y = @cursor_y + row_height + 1.0
      ri = ri + 1
    end

    # Draw vertical column separator lines
    line_x = table_x
    table_top = @cursor_y - (node.children.length * (row_height + 1.0))
    table_bottom = @cursor_y
    ci = 0
    while ci < num_cols + 1
      painter.fill_rect(line_x, table_top, 1.0, table_bottom - table_top, @theme.table_border_color)
      if ci < num_cols
        line_x = line_x + col_widths[ci]
      end
      ci = ci + 1
    end

    @cursor_y = @cursor_y + @theme.block_spacing / 2.0
  end

  # --- Image ---
  def render_image(painter, node, width)
    # Load image (Java side caches by path hash)
    img_id = painter.load_image(node.href)
    if img_id == 0
      render_image_placeholder(painter, node, width)
      return
    end
    # Get natural dimensions
    img_w = painter.get_image_width(img_id) * 1.0
    img_h = painter.get_image_height(img_id) * 1.0
    if img_w < 1.0 || img_h < 1.0
      render_image_placeholder(painter, node, width)
      return
    end
    # Scale to fit width (maintain aspect ratio)
    if img_w > width
      scale = width / img_w
      img_w = width
      img_h = img_h * scale
    end
    painter.draw_image(img_id, @cursor_x, @cursor_y, img_w, img_h)
    @cursor_y = @cursor_y + img_h + @theme.block_spacing
  end

  def render_image_placeholder(painter, node, width)
    # Draw a placeholder box with alt text
    box_h = 60.0
    font_size = @theme.base_font_size
    ascent = painter.get_text_ascent(@font_family, font_size)

    painter.fill_round_rect(@cursor_x, @cursor_y, width, box_h, 4.0, @theme.code_bg_color)
    painter.stroke_round_rect(@cursor_x, @cursor_y, width, box_h, 4.0, @theme.table_border_color, 1.0)

    # Icon placeholder text
    icon_text = "[Image]"
    if node.content.length > 0
      icon_text = "[" + node.content + "]"
    end
    text_w = painter.measure_text_width(icon_text, @font_family, font_size)
    tx = @cursor_x + (width - text_w) / 2.0
    ty = @cursor_y + (box_h + ascent) / 2.0
    painter.draw_text(icon_text, tx, ty, @font_family, font_size, @theme.strikethrough_color)

    @cursor_y = @cursor_y + box_h + @theme.block_spacing
  end

  # --- Mermaid ---
  def render_mermaid(painter, node, width)
    mermaid_parser = MermaidParser.new
    diagram = mermaid_parser.parse(node.content)
    mermaid_renderer = MermaidRenderer.new(@theme)
    height = mermaid_renderer.render(painter, diagram, @cursor_x, @cursor_y, width)
    @cursor_y = @cursor_y + height + @theme.block_spacing
  end

  # --- Segment collection ---

  def collect_segments(nodes, bold, italic, strikethrough, code, href)
    segments = []
    i = 0
    while i < nodes.length
      node = nodes[i]
      t = node.type
      if t == MD_TEXT
        segments.push([node.content, bold, italic, strikethrough, code, href])
      elsif t == MD_STRONG
        inner = collect_segments(node.children, true, italic, strikethrough, code, href)
        si = 0
        while si < inner.length
          segments.push(inner[si])
          si = si + 1
        end
      elsif t == MD_EMPHASIS
        inner = collect_segments(node.children, bold, true, strikethrough, code, href)
        si = 0
        while si < inner.length
          segments.push(inner[si])
          si = si + 1
        end
      elsif t == MD_STRIKETHROUGH
        inner = collect_segments(node.children, bold, italic, true, code, href)
        si = 0
        while si < inner.length
          segments.push(inner[si])
          si = si + 1
        end
      elsif t == MD_CODE_INLINE
        segments.push([node.content, bold, italic, strikethrough, true, href])
      elsif t == MD_LINK
        inner = collect_segments(node.children, bold, italic, strikethrough, code, node.href)
        si = 0
        while si < inner.length
          segments.push(inner[si])
          si = si + 1
        end
      elsif t == MD_SOFT_BREAK
        segments.push([" ", bold, italic, strikethrough, code, href])
      end
      i = i + 1
    end
    segments
  end

  # --- Height estimation ---

  def estimate_node_height(painter, node, width)
    t = node.type
    if t == MD_HEADING
      font_size = @theme.heading_size(node.level)
      font_size * 1.5 + @theme.block_spacing
    elsif t == MD_PARAGRAPH
      text = extract_text(node.children)
      font_size = @theme.base_font_size
      text_w = painter.measure_text_width(text, @font_family, font_size)
      safe_width = width
      if safe_width < 1.0
        safe_width = 1.0
      end
      lines = (text_w / safe_width).to_i + 1
      if lines < 1
        lines = 1
      end
      lines * font_size * 1.5 + @theme.paragraph_spacing
    elsif t == MD_CODE_BLOCK
      line_count = node.content.split("\n").length
      line_count * (@theme.base_font_size + 4.0) + 16.0 + @theme.block_spacing
    elsif t == MD_BLOCKQUOTE
      h = 0.0
      ci = 0
      while ci < node.children.length
        child_width = width - @theme.blockquote_indent
        if child_width < 1.0
          child_width = 1.0
        end
        h = h + estimate_node_height(painter, node.children[ci], child_width)
        ci = ci + 1
      end
      h
    elsif t == MD_LIST
      h = 0.0
      ci = 0
      while ci < node.children.length
        h = h + estimate_node_height(painter, node.children[ci], width)
        ci = ci + 1
      end
      h
    elsif t == MD_LIST_ITEM
      h = 0.0
      ci = 0
      while ci < node.children.length
        h = h + estimate_node_height(painter, node.children[ci], width)
        ci = ci + 1
      end
      h
    elsif t == MD_TABLE
      cell_pad = 8.0
      row_h = @theme.base_font_size * 1.5 + cell_pad * 2.0 + 1.0
      num_rows = node.children.length
      num_rows * row_h + @theme.block_spacing
    elsif t == MD_HORIZONTAL_RULE
      @theme.block_spacing + 1.0
    elsif t == MD_IMAGE
      200.0 + @theme.block_spacing
    elsif t == MD_MERMAID
      300.0 + @theme.block_spacing
    else
      @theme.base_font_size * 1.5
    end
  end

  # --- Helpers ---

  def extract_text(nodes)
    parts = []
    i = 0
    while i < nodes.length
      node = nodes[i]
      if node.type == MD_TEXT
        parts.push(node.content)
      elsif node.type == MD_CODE_INLINE
        parts.push(node.content)
      else
        parts.push(extract_text(node.children))
      end
      i = i + 1
    end
    parts.join("")
  end
end
