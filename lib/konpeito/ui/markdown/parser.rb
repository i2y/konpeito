# Markdown parser - pure Ruby line-by-line parser
# No regex, no external libraries. Uses start_with?, index, [] only.

class MarkdownParser
  def initialize
    @lines = []
    @pos = 0
  end

  def parse(text)
    @lines = text.split("\n")
    @pos = 0
    doc = MdNode.new(MD_DOCUMENT)
    while @pos < @lines.length
      node = parse_block
      if node
        doc.add_child(node)
      end
    end
    doc
  end

  def parse_block
    if @pos >= @lines.length
      return nil
    end
    line = @lines[@pos]
    stripped = line.strip

    # Blank line
    if stripped.length == 0
      @pos = @pos + 1
      return nil
    end

    # Heading: # ... ######
    if stripped.start_with?("#")
      return parse_heading
    end

    # Horizontal rule: --- or *** or ___
    if is_horizontal_rule(stripped)
      @pos = @pos + 1
      return MdNode.new(MD_HORIZONTAL_RULE)
    end

    # Image on its own line: ![alt](src)
    if stripped.start_with?("![")
      img_node = try_parse_image_line(stripped)
      if img_node
        @pos = @pos + 1
        return img_node
      end
    end

    # Code block: ```
    if stripped.start_with?("```")
      return parse_code_block
    end

    # Blockquote: > text
    if stripped.start_with?("> ") || stripped == ">"
      return parse_blockquote
    end

    # Table: | col | col |
    if stripped.start_with?("|") && is_table_start
      return parse_table
    end

    # Unordered list: - item or * item
    if is_unordered_list_start(stripped)
      return parse_list(false)
    end

    # Ordered list: 1. item
    if is_ordered_list_start(stripped)
      return parse_list(true)
    end

    # Paragraph (default)
    return parse_paragraph
  end

  def parse_heading
    line = @lines[@pos].strip
    @pos = @pos + 1
    level = 0
    i = 0
    while i < line.length && line[i, 1] == "#"
      level = level + 1
      i = i + 1
    end
    if level > 6
      level = 6
    end
    # Skip space after #
    if i < line.length && line[i, 1] == " "
      i = i + 1
    end
    text = ""
    if i < line.length
      text = line[i, line.length - i]
    end
    node = MdNode.new(MD_HEADING)
    node.level = level
    inline_nodes = parse_inline(text)
    ci = 0
    while ci < inline_nodes.length
      node.add_child(inline_nodes[ci])
      ci = ci + 1
    end
    node
  end

  def parse_code_block
    first_line = @lines[@pos].strip
    @pos = @pos + 1
    # Extract language from ```lang
    lang = ""
    if first_line.length > 3
      lang = first_line[3, first_line.length - 3].strip
    end
    content_parts = []
    while @pos < @lines.length
      line = @lines[@pos]
      if line.strip.start_with?("```")
        @pos = @pos + 1
        break
      end
      content_parts.push(line)
      @pos = @pos + 1
    end
    if lang == "mermaid"
      node = MdNode.new(MD_MERMAID)
      node.content = content_parts.join("\n")
      return node
    end
    node = MdNode.new(MD_CODE_BLOCK)
    node.language = lang
    node.content = content_parts.join("\n")
    node
  end

  def parse_blockquote
    collected = []
    while @pos < @lines.length
      line = @lines[@pos]
      stripped = line.strip
      if stripped.start_with?("> ")
        collected.push(stripped[2, stripped.length - 2])
        @pos = @pos + 1
      elsif stripped == ">"
        collected.push("")
        @pos = @pos + 1
      else
        break
      end
    end
    # Recursively parse the collected content
    inner_text = collected.join("\n")
    inner_parser = MarkdownParser.new
    inner_doc = inner_parser.parse(inner_text)
    node = MdNode.new(MD_BLOCKQUOTE)
    ci = 0
    while ci < inner_doc.children.length
      node.add_child(inner_doc.children[ci])
      ci = ci + 1
    end
    node
  end

  def parse_list(ordered)
    node = MdNode.new(MD_LIST)
    node.ordered = ordered
    if ordered
      # Extract start number
      line = @lines[@pos].strip
      num_str = ""
      ni = 0
      while ni < line.length && is_digit(line[ni, 1])
        num_str = num_str + line[ni, 1]
        ni = ni + 1
      end
      if num_str.length > 0
        node.start_num = num_str.to_i
      end
    end
    counter = node.start_num
    while @pos < @lines.length
      line = @lines[@pos].strip
      if line.length == 0
        # Blank line might end the list or separate items
        @pos = @pos + 1
        # Check if next line continues the list
        if @pos < @lines.length
          next_line = @lines[@pos].strip
          if ordered && is_ordered_list_start(next_line)
            next
          elsif !ordered && is_unordered_list_start(next_line)
            next
          else
            break
          end
        else
          break
        end
      elsif ordered && is_ordered_list_start(line)
        item = parse_list_item_ordered
        node.add_child(item)
        counter = counter + 1
      elsif !ordered && is_unordered_list_start(line)
        item = parse_list_item_unordered
        node.add_child(item)
      else
        break
      end
    end
    node
  end

  def parse_list_item_unordered
    line = @lines[@pos].strip
    @pos = @pos + 1
    # Strip "- " or "* "
    text = line[2, line.length - 2]
    item = MdNode.new(MD_LIST_ITEM)

    # Check for task list: [ ] or [x] or [X]
    if text.length >= 4 && text[0, 4] == "[ ] "
      item.checked = 0
      text = text[4, text.length - 4]
    elsif text.length >= 4 && (text[0, 4] == "[x] " || text[0, 4] == "[X] ")
      item.checked = 1
      text = text[4, text.length - 4]
    end

    # Parse inline content as a paragraph
    para = MdNode.new(MD_PARAGRAPH)
    inline_nodes = parse_inline(text)
    ci = 0
    while ci < inline_nodes.length
      para.add_child(inline_nodes[ci])
      ci = ci + 1
    end
    item.add_child(para)

    # Check for nested sub-list (indented lines)
    parse_nested_list(item)

    item
  end

  def parse_list_item_ordered
    line = @lines[@pos].strip
    @pos = @pos + 1
    # Find ". " after digits
    di = 0
    while di < line.length && is_digit(line[di, 1])
      di = di + 1
    end
    # Skip ". "
    if di < line.length && line[di, 1] == "."
      di = di + 1
    end
    if di < line.length && line[di, 1] == " "
      di = di + 1
    end
    text = ""
    if di < line.length
      text = line[di, line.length - di]
    end
    item = MdNode.new(MD_LIST_ITEM)
    para = MdNode.new(MD_PARAGRAPH)
    inline_nodes = parse_inline(text)
    ci = 0
    while ci < inline_nodes.length
      para.add_child(inline_nodes[ci])
      ci = ci + 1
    end
    item.add_child(para)

    # Check for nested sub-list (indented lines)
    parse_nested_list(item)

    item
  end

  def parse_paragraph
    parts = []
    while @pos < @lines.length
      line = @lines[@pos]
      stripped = line.strip
      if stripped.length == 0
        break
      end
      if stripped.start_with?("#") || stripped.start_with?("```") || stripped.start_with?("> ") || stripped == ">"
        break
      end
      if stripped.start_with?("|") && is_table_start
        break
      end
      if is_horizontal_rule(stripped)
        break
      end
      if is_unordered_list_start(stripped) || is_ordered_list_start(stripped)
        break
      end
      if stripped.start_with?("![")
        break
      end
      parts.push(stripped)
      @pos = @pos + 1
    end
    text = parts.join(" ")
    node = MdNode.new(MD_PARAGRAPH)
    inline_nodes = parse_inline(text)
    ci = 0
    while ci < inline_nodes.length
      node.add_child(inline_nodes[ci])
      ci = ci + 1
    end
    node
  end

  # --- Inline parsing ---

  def parse_inline(text)
    nodes = []
    buf = ""
    i = 0
    while i < text.length
      ch = text[i, 1]

      if ch == "*"
        # Check ** (bold) or * (italic)
        if i + 1 < text.length && text[i + 1, 1] == "*"
          # Bold **...**
          flush_buf(buf, nodes)
          buf = ""
          close_idx = find_marker(text, i + 2, "**")
          if close_idx >= 0
            inner = text[i + 2, close_idx - (i + 2)]
            node = MdNode.new(MD_STRONG)
            inner_nodes = parse_inline(inner)
            ni = 0
            while ni < inner_nodes.length
              node.add_child(inner_nodes[ni])
              ni = ni + 1
            end
            nodes.push(node)
            i = close_idx + 2
          else
            buf = buf + "**"
            i = i + 2
          end
        else
          # Italic *...*
          flush_buf(buf, nodes)
          buf = ""
          close_idx = find_single_star(text, i + 1)
          if close_idx >= 0
            inner = text[i + 1, close_idx - (i + 1)]
            node = MdNode.new(MD_EMPHASIS)
            inner_nodes = parse_inline(inner)
            ni = 0
            while ni < inner_nodes.length
              node.add_child(inner_nodes[ni])
              ni = ni + 1
            end
            nodes.push(node)
            i = close_idx + 1
          else
            buf = buf + "*"
            i = i + 1
          end
        end

      elsif ch == "~"
        # Strikethrough ~~...~~
        if i + 1 < text.length && text[i + 1, 1] == "~"
          flush_buf(buf, nodes)
          buf = ""
          close_idx = find_marker(text, i + 2, "~~")
          if close_idx >= 0
            inner = text[i + 2, close_idx - (i + 2)]
            node = MdNode.new(MD_STRIKETHROUGH)
            inner_nodes = parse_inline(inner)
            ni = 0
            while ni < inner_nodes.length
              node.add_child(inner_nodes[ni])
              ni = ni + 1
            end
            nodes.push(node)
            i = close_idx + 2
          else
            buf = buf + "~~"
            i = i + 2
          end
        else
          buf = buf + "~"
          i = i + 1
        end

      elsif ch == "`"
        # Inline code `...`
        flush_buf(buf, nodes)
        buf = ""
        close_idx = find_char(text, i + 1, "`")
        if close_idx >= 0
          code_text = text[i + 1, close_idx - (i + 1)]
          node = MdNode.new(MD_CODE_INLINE)
          node.content = code_text
          nodes.push(node)
          i = close_idx + 1
        else
          buf = buf + "`"
          i = i + 1
        end

      elsif ch == "["
        # Link [text](url)
        flush_buf(buf, nodes)
        buf = ""
        bracket_close = find_char(text, i + 1, "]")
        if bracket_close >= 0 && bracket_close + 1 < text.length && text[bracket_close + 1, 1] == "("
          paren_close = find_char(text, bracket_close + 2, ")")
          if paren_close >= 0
            link_text = text[i + 1, bracket_close - (i + 1)]
            link_url = text[bracket_close + 2, paren_close - (bracket_close + 2)]
            node = MdNode.new(MD_LINK)
            node.href = link_url
            inner_nodes = parse_inline(link_text)
            ni = 0
            while ni < inner_nodes.length
              node.add_child(inner_nodes[ni])
              ni = ni + 1
            end
            nodes.push(node)
            i = paren_close + 1
          else
            buf = buf + "["
            i = i + 1
          end
        else
          buf = buf + "["
          i = i + 1
        end

      else
        buf = buf + ch
        i = i + 1
      end
    end
    flush_buf(buf, nodes)
    nodes
  end

  # --- Helpers ---

  def flush_buf(buf, nodes)
    if buf.length > 0
      node = MdNode.new(MD_TEXT)
      node.content = buf
      nodes.push(node)
    end
  end

  def find_marker(text, start, marker)
    # Find the position of marker string starting from start
    mlen = marker.length
    i = start
    while i <= text.length - mlen
      if text[i, mlen] == marker
        return i
      end
      i = i + 1
    end
    -1
  end

  def find_single_star(text, start)
    # Find closing * that is not part of **
    i = start
    while i < text.length
      if text[i, 1] == "*"
        # Make sure it's not **
        if i + 1 < text.length && text[i + 1, 1] == "*"
          i = i + 2
        else
          return i
        end
      else
        i = i + 1
      end
    end
    -1
  end

  def find_char(text, start, ch)
    i = start
    while i < text.length
      if text[i, 1] == ch
        return i
      end
      i = i + 1
    end
    -1
  end

  def is_horizontal_rule(line)
    if line.length < 3
      return false
    end
    # Check if line is all dashes, all asterisks, or all underscores (with optional spaces)
    ch = ""
    count = 0
    i = 0
    while i < line.length
      c = line[i, 1]
      if c == " "
        i = i + 1
        next
      end
      if ch == ""
        if c == "-" || c == "*" || c == "_"
          ch = c
          count = 1
        else
          return false
        end
      elsif c == ch
        count = count + 1
      else
        return false
      end
      i = i + 1
    end
    count >= 3
  end

  def is_unordered_list_start(line)
    if line.length >= 2
      if (line[0, 1] == "-" || line[0, 1] == "*") && line[1, 1] == " "
        return true
      end
    end
    false
  end

  def is_ordered_list_start(line)
    # Check if line starts with digits followed by ". "
    i = 0
    while i < line.length && is_digit(line[i, 1])
      i = i + 1
    end
    if i > 0 && i + 1 < line.length && line[i, 1] == "." && line[i + 1, 1] == " "
      return true
    end
    false
  end

  def try_parse_image_line(line)
    # Parse ![alt](src) as a block-level image
    # Returns MD_PARAGRAPH containing MD_IMAGE node, or nil
    if !line.start_with?("![")
      return nil
    end
    bracket_close = find_char(line, 2, "]")
    if bracket_close < 0
      return nil
    end
    if bracket_close + 1 >= line.length || line[bracket_close + 1, 1] != "("
      return nil
    end
    paren_close = find_char(line, bracket_close + 2, ")")
    if paren_close < 0
      return nil
    end
    alt_text = line[2, bracket_close - 2]
    img_src = line[bracket_close + 2, paren_close - (bracket_close + 2)]
    img_node = MdNode.new(MD_IMAGE)
    img_node.content = alt_text
    img_node.href = img_src
    img_node
  end

  def is_digit(ch)
    ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" || ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9"
  end

  # --- Table parsing ---

  def is_table_start
    # Check if current line + next line form a table (header + separator)
    if @pos + 1 >= @lines.length
      return false
    end
    next_line = @lines[@pos + 1].strip
    if next_line.length < 3
      return false
    end
    # Separator must start with | and contain ---
    if !next_line.start_with?("|")
      return false
    end
    # Quick check: separator contains at least one ---
    has_dash = false
    i = 0
    while i < next_line.length
      if next_line[i, 1] == "-"
        has_dash = true
        break
      end
      i = i + 1
    end
    has_dash
  end

  def parse_table
    table = MdNode.new(MD_TABLE)

    # Parse header row
    header_cells = split_table_row(@lines[@pos].strip)
    @pos = @pos + 1

    # Parse separator row for alignment
    alignments = parse_table_separator(@lines[@pos].strip)
    @pos = @pos + 1

    # Build header row node
    header_row = MdNode.new(MD_TABLE_ROW)
    header_row.is_header = true
    ci = 0
    while ci < header_cells.length
      cell = MdNode.new(MD_TABLE_CELL)
      cell.is_header = true
      if alignments && ci < alignments.length
        cell.align = alignments[ci]
      end
      inline_nodes = parse_inline(header_cells[ci])
      ni = 0
      while ni < inline_nodes.length
        cell.add_child(inline_nodes[ni])
        ni = ni + 1
      end
      header_row.add_child(cell)
      ci = ci + 1
    end
    table.add_child(header_row)

    # Parse data rows
    while @pos < @lines.length
      line = @lines[@pos].strip
      if line.length == 0 || !line.start_with?("|")
        break
      end
      data_cells = split_table_row(line)
      row = MdNode.new(MD_TABLE_ROW)
      di = 0
      while di < data_cells.length
        cell = MdNode.new(MD_TABLE_CELL)
        if alignments && di < alignments.length
          cell.align = alignments[di]
        end
        inline_nodes = parse_inline(data_cells[di])
        ni = 0
        while ni < inline_nodes.length
          cell.add_child(inline_nodes[ni])
          ni = ni + 1
        end
        row.add_child(cell)
        di = di + 1
      end
      table.add_child(row)
      @pos = @pos + 1
    end

    table
  end

  def split_table_row(line)
    # Strip leading and trailing |
    inner = ""
    start = 0
    if line.length > 0 && line[0, 1] == "|"
      start = 1
    end
    stop = line.length
    if stop > 0 && line[stop - 1, 1] == "|"
      stop = stop - 1
    end
    if start < stop
      inner = line[start, stop - start]
    end

    # Split by | character
    cells = []
    buf = ""
    i = 0
    while i < inner.length
      ch = inner[i, 1]
      if ch == "|"
        cells.push(buf.strip)
        buf = ""
      else
        buf = buf + ch
      end
      i = i + 1
    end
    cells.push(buf.strip)
    cells
  end

  def parse_table_separator(line)
    cells = split_table_row(line)
    alignments = []
    ci = 0
    while ci < cells.length
      cell = cells[ci]
      # Check alignment markers
      left_colon = cell.length > 0 && cell[0, 1] == ":"
      right_colon = cell.length > 0 && cell[cell.length - 1, 1] == ":"
      if left_colon && right_colon
        alignments.push(1)   # center
      elsif right_colon
        alignments.push(2)   # right
      else
        alignments.push(0)   # left (default)
      end
      ci = ci + 1
    end
    alignments
  end

  # --- Nested list parsing ---

  def count_leading_spaces(line)
    count = 0
    i = 0
    while i < line.length
      if line[i, 1] == " "
        count = count + 1
      else
        break
      end
      i = i + 1
    end
    count
  end

  def parse_nested_list(item)
    # Peek at next lines: if indented 2+ spaces with list marker, parse as sub-list
    sub_lines = collect_indented_lines
    if sub_lines.length == 0
      return
    end

    # Parse sub-lines as a new document, extract list nodes
    sub_parser = MarkdownParser.new
    sub_doc = sub_parser.parse(sub_lines.join("\n"))
    ci = 0
    while ci < sub_doc.children.length
      child = sub_doc.children[ci]
      if child.type == MD_LIST
        item.add_child(child)
      end
      ci = ci + 1
    end
  end

  def collect_indented_lines
    result = []
    if @pos >= @lines.length
      return result
    end
    first_line = @lines[@pos]
    first_spaces = count_leading_spaces(first_line)
    if first_spaces < 2
      return result
    end

    # Check first line is a list start after stripping indent
    first_stripped = first_line.strip
    if !is_unordered_list_start(first_stripped) && !is_ordered_list_start(first_stripped)
      return result
    end

    # Collect lines with sufficient indentation (use strip to remove indent)
    while @pos < @lines.length
      line = @lines[@pos]
      stripped = line.strip
      if stripped.length == 0
        break
      end
      spaces = count_leading_spaces(line)
      if spaces < first_spaces
        break
      end
      result.push(stripped)
      @pos = @pos + 1
    end
    result
  end
end
