# Mermaid flowchart parser - character-by-character, no regex
# Parses graph TD/LR/BT/RL with nodes, edges, subgraphs

class MermaidParser
  def parse(content)
    @lines = content.split("\n")
    @pos = 0
    @nodes = {}
    @subgraph_stack = []
    parse_flowchart
  end

  def parse_flowchart
    if @pos >= @lines.length
      return MermaidDiagram.new(MERMAID_DIR_TB)
    end

    # Parse first line for direction
    first_line = @lines[@pos].strip
    direction = parse_direction(first_line)
    @pos = @pos + 1

    diagram = MermaidDiagram.new(direction)

    while @pos < @lines.length
      line = @lines[@pos]
      stripped = line.strip
      @pos = @pos + 1

      # Skip blank lines and comments
      if stripped.length == 0
        next
      end
      if stripped.start_with?("%%")
        next
      end

      # Check for subgraph
      if stripped.start_with?("subgraph ")
        title = stripped[9, stripped.length - 9].strip
        sg_id = "sg_" + @subgraph_stack.length.to_s
        sg = MermaidSubgraph.new(sg_id, title)
        @subgraph_stack.push(sg)
        next
      end
      if stripped == "subgraph"
        sg = MermaidSubgraph.new("sg_" + @subgraph_stack.length.to_s, "")
        @subgraph_stack.push(sg)
        next
      end

      # Check for end (closes subgraph)
      if stripped == "end"
        if @subgraph_stack.length > 0
          sg = @subgraph_stack.pop
          diagram.add_subgraph(sg)
        end
        next
      end

      # Try to parse edge
      edge_result = try_parse_edge(stripped)
      if edge_result
        src_id = edge_result[0]
        src_label = edge_result[1]
        src_shape = edge_result[2]
        tgt_id = edge_result[3]
        tgt_label = edge_result[4]
        tgt_shape = edge_result[5]
        edge_label = edge_result[6]
        line_type = edge_result[7]
        arrow_type = edge_result[8]

        # Ensure source node exists
        ensure_node(diagram, src_id, src_label, src_shape)
        # Ensure target node exists
        ensure_node(diagram, tgt_id, tgt_label, tgt_shape)

        # Track subgraph membership
        if @subgraph_stack.length > 0
          current_sg = @subgraph_stack[@subgraph_stack.length - 1]
          if !current_sg.node_ids.include?(src_id)
            current_sg.node_ids.push(src_id)
          end
          if !current_sg.node_ids.include?(tgt_id)
            current_sg.node_ids.push(tgt_id)
          end
        end

        edge = MermaidEdge.new(src_id, tgt_id, edge_label, line_type, arrow_type)
        diagram.add_edge(edge)
        next
      end

      # Try to parse standalone node definition
      node_def = try_parse_node_def(stripped)
      if node_def
        n_id = node_def[0]
        n_label = node_def[1]
        n_shape = node_def[2]
        ensure_node(diagram, n_id, n_label, n_shape)
        if @subgraph_stack.length > 0
          current_sg = @subgraph_stack[@subgraph_stack.length - 1]
          if !current_sg.node_ids.include?(n_id)
            current_sg.node_ids.push(n_id)
          end
        end
      end
    end

    # Close any unclosed subgraphs
    while @subgraph_stack.length > 0
      sg = @subgraph_stack.pop
      diagram.add_subgraph(sg)
    end

    diagram
  end

  def parse_direction(line)
    # Look for direction after "graph" or "flowchart"
    rest = ""
    if line.start_with?("graph ")
      rest = line[6, line.length - 6].strip
    elsif line.start_with?("flowchart ")
      rest = line[10, line.length - 10].strip
    elsif line.start_with?("graph")
      return MERMAID_DIR_TB
    elsif line.start_with?("flowchart")
      return MERMAID_DIR_TB
    else
      return MERMAID_DIR_TB
    end

    if rest == "BT"
      MERMAID_DIR_BT
    elsif rest == "LR"
      MERMAID_DIR_LR
    elsif rest == "RL"
      MERMAID_DIR_RL
    else
      MERMAID_DIR_TB
    end
  end

  def ensure_node(diagram, id, label, shape)
    existing = diagram.get_node(id)
    if existing
      # Update label/shape if we now have better info
      if label.length > 0 && existing.label == existing.id
        existing.label = label
      end
      if shape != MERMAID_SHAPE_RECT && existing.shape == MERMAID_SHAPE_RECT
        existing.shape = shape
      end
      return
    end
    lbl = label
    if lbl.length == 0
      lbl = id
    end
    node = MermaidNode.new(id, lbl, shape)
    diagram.add_node(node)
    @nodes[id] = node
  end

  # --- Edge parsing ---

  def try_parse_edge(line)
    # Find arrow pattern in line
    # Returns [src_id, src_label, src_shape, tgt_id, tgt_label, tgt_shape, edge_label, line_type, arrow_type] or nil

    # Scan for source node (ID + optional shape)
    i = 0
    # Skip leading whitespace
    while i < line.length && line[i, 1] == " "
      i = i + 1
    end

    src_start = i
    # Scan ID characters
    while i < line.length && is_id_char(line[i, 1])
      i = i + 1
    end
    if i == src_start
      return nil
    end
    src_id = line[src_start, i - src_start]

    # Try to parse source node shape
    src_shape_result = try_parse_shape(line, i)
    src_label = ""
    src_shape = MERMAID_SHAPE_RECT
    if src_shape_result
      src_label = src_shape_result[0]
      src_shape = src_shape_result[1]
      i = src_shape_result[2]
    end

    # Skip whitespace
    while i < line.length && line[i, 1] == " "
      i = i + 1
    end

    # Try to find arrow
    arrow_result = try_parse_arrow(line, i)
    if !arrow_result
      return nil
    end
    arrow_len = arrow_result[0]
    line_type = arrow_result[1]
    arrow_type = arrow_result[2]
    i = i + arrow_len

    # Check for |label| after arrow
    edge_label = ""
    # Skip whitespace
    while i < line.length && line[i, 1] == " "
      i = i + 1
    end
    if i < line.length && line[i, 1] == "|"
      label_result = parse_pipe_label(line, i)
      if label_result
        edge_label = label_result[0]
        i = label_result[1]
      end
    end

    # Skip whitespace
    while i < line.length && line[i, 1] == " "
      i = i + 1
    end

    # Parse target node
    tgt_start = i
    while i < line.length && is_id_char(line[i, 1])
      i = i + 1
    end
    if i == tgt_start
      return nil
    end
    tgt_id = line[tgt_start, i - tgt_start]

    # Try to parse target node shape
    tgt_shape_result = try_parse_shape(line, i)
    tgt_label = ""
    tgt_shape = MERMAID_SHAPE_RECT
    if tgt_shape_result
      tgt_label = tgt_shape_result[0]
      tgt_shape = tgt_shape_result[1]
      i = tgt_shape_result[2]
    end

    [src_id, src_label, src_shape, tgt_id, tgt_label, tgt_shape, edge_label, line_type, arrow_type]
  end

  def try_parse_arrow(line, pos)
    # Returns [length, line_type, arrow_type] or nil
    if pos >= line.length
      return nil
    end

    ch = line[pos, 1]

    if ch == "="
      # === or ==>
      if pos + 2 < line.length && line[pos + 1, 1] == "=" && line[pos + 2, 1] == "="
        if pos + 3 < line.length && line[pos + 3, 1] == ">"
          return [4, MERMAID_LINE_THICK, MERMAID_ARROW_ARROW]
        end
        return [3, MERMAID_LINE_THICK, MERMAID_ARROW_OPEN]
      elsif pos + 1 < line.length && line[pos + 1, 1] == "="
        if pos + 2 < line.length && line[pos + 2, 1] == ">"
          return [3, MERMAID_LINE_THICK, MERMAID_ARROW_ARROW]
        end
      end
      return nil
    end

    if ch == "-"
      # Check -.- or -.-> (dashed)
      if pos + 1 < line.length && line[pos + 1, 1] == "."
        # Dashed line: scan for end
        j = pos + 2
        while j < line.length && line[j, 1] == "-"
          j = j + 1
        end
        if j < line.length && line[j, 1] == ">"
          return [j - pos + 1, MERMAID_LINE_DASHED, MERMAID_ARROW_ARROW]
        end
        if j < line.length && line[j, 1] == "."
          # -.- pattern
          return [j - pos + 1, MERMAID_LINE_DASHED, MERMAID_ARROW_OPEN]
        end
        # -.-> check
        if j > pos + 2
          return [j - pos, MERMAID_LINE_DASHED, MERMAID_ARROW_OPEN]
        end
        return nil
      end

      # Count consecutive dashes
      j = pos
      while j < line.length && line[j, 1] == "-"
        j = j + 1
      end
      dash_count = j - pos
      if dash_count < 2
        return nil
      end

      # Check what follows the dashes
      if j < line.length
        next_ch = line[j, 1]
        if next_ch == ">"
          return [j - pos + 1, MERMAID_LINE_SOLID, MERMAID_ARROW_ARROW]
        elsif next_ch == "o"
          return [j - pos + 1, MERMAID_LINE_SOLID, MERMAID_ARROW_CIRCLE]
        elsif next_ch == "x"
          return [j - pos + 1, MERMAID_LINE_SOLID, MERMAID_ARROW_CROSS]
        end
      end

      # Just dashes (open/no arrow)
      if dash_count >= 3
        return [dash_count, MERMAID_LINE_SOLID, MERMAID_ARROW_OPEN]
      end

      return nil
    end

    nil
  end

  def parse_pipe_label(line, pos)
    # Parse |label| starting at pos where line[pos]=='|'
    # Returns [label, end_pos] or nil
    if pos >= line.length || line[pos, 1] != "|"
      return nil
    end
    close = pos + 1
    while close < line.length && line[close, 1] != "|"
      close = close + 1
    end
    if close >= line.length
      return nil
    end
    label = line[pos + 1, close - pos - 1].strip
    [label, close + 1]
  end

  # --- Node shape parsing ---

  def try_parse_shape(line, pos)
    # Returns [label, shape, end_pos] or nil
    if pos >= line.length
      return nil
    end

    ch = line[pos, 1]

    if ch == "["
      # [[ → SUBROUTINE or [ → RECT
      if pos + 1 < line.length && line[pos + 1, 1] == "["
        # Subroutine [[label]]
        close = find_double_close(line, pos + 2, "]")
        if close >= 0
          label = line[pos + 2, close - pos - 2]
          return [label, MERMAID_SHAPE_SUBROUTINE, close + 2]
        end
      end
      # Rect [label]
      close = find_close_char(line, pos + 1, "]")
      if close >= 0
        label = line[pos + 1, close - pos - 1]
        return [label, MERMAID_SHAPE_RECT, close + 1]
      end

    elsif ch == "("
      if pos + 1 < line.length && line[pos + 1, 1] == "["
        # Stadium ([label])
        close = find_close_pair(line, pos + 2, "])")
        if close >= 0
          label = line[pos + 2, close - pos - 2]
          return [label, MERMAID_SHAPE_STADIUM, close + 2]
        end
      elsif pos + 1 < line.length && line[pos + 1, 1] == "("
        # Circle ((label))
        close = find_double_close(line, pos + 2, ")")
        if close >= 0
          label = line[pos + 2, close - pos - 2]
          return [label, MERMAID_SHAPE_CIRCLE, close + 2]
        end
      end
      # Rounded (label)
      close = find_close_char(line, pos + 1, ")")
      if close >= 0
        label = line[pos + 1, close - pos - 1]
        return [label, MERMAID_SHAPE_ROUNDED, close + 1]
      end

    elsif ch == "{"
      if pos + 1 < line.length && line[pos + 1, 1] == "{"
        # Hexagon {{label}}
        close = find_double_close(line, pos + 2, "}")
        if close >= 0
          label = line[pos + 2, close - pos - 2]
          return [label, MERMAID_SHAPE_HEXAGON, close + 2]
        end
      end
      # Diamond {label}
      close = find_close_char(line, pos + 1, "}")
      if close >= 0
        label = line[pos + 1, close - pos - 1]
        return [label, MERMAID_SHAPE_DIAMOND, close + 1]
      end
    end

    nil
  end

  def try_parse_node_def(line)
    # Parse standalone node definition: ID[label] or ID(label) etc.
    # Returns [id, label, shape] or nil
    i = 0
    while i < line.length && line[i, 1] == " "
      i = i + 1
    end

    start = i
    while i < line.length && is_id_char(line[i, 1])
      i = i + 1
    end
    if i == start
      return nil
    end
    id = line[start, i - start]

    shape_result = try_parse_shape(line, i)
    if shape_result
      return [id, shape_result[0], shape_result[1]]
    end

    nil
  end

  # --- Helper methods ---

  def is_id_char(ch)
    # Alphanumeric or underscore
    if ch == "_"
      return true
    end
    if is_alpha(ch)
      return true
    end
    if is_digit_char(ch)
      return true
    end
    false
  end

  def is_alpha(ch)
    ch == "a" || ch == "b" || ch == "c" || ch == "d" || ch == "e" ||
    ch == "f" || ch == "g" || ch == "h" || ch == "i" || ch == "j" ||
    ch == "k" || ch == "l" || ch == "m" || ch == "n" || ch == "o" ||
    ch == "p" || ch == "q" || ch == "r" || ch == "s" || ch == "t" ||
    ch == "u" || ch == "v" || ch == "w" || ch == "x" || ch == "y" ||
    ch == "z" ||
    ch == "A" || ch == "B" || ch == "C" || ch == "D" || ch == "E" ||
    ch == "F" || ch == "G" || ch == "H" || ch == "I" || ch == "J" ||
    ch == "K" || ch == "L" || ch == "M" || ch == "N" || ch == "O" ||
    ch == "P" || ch == "Q" || ch == "R" || ch == "S" || ch == "T" ||
    ch == "U" || ch == "V" || ch == "W" || ch == "X" || ch == "Y" ||
    ch == "Z"
  end

  def is_digit_char(ch)
    ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" ||
    ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9"
  end

  def find_close_char(line, start, ch)
    i = start
    while i < line.length
      if line[i, 1] == ch
        return i
      end
      i = i + 1
    end
    -1
  end

  def find_double_close(line, start, ch)
    # Find ]] or )) or }}
    i = start
    while i + 1 < line.length
      if line[i, 1] == ch && line[i + 1, 1] == ch
        return i
      end
      i = i + 1
    end
    -1
  end

  def find_close_pair(line, start, pair)
    # Find ]) for stadium shapes
    c1 = pair[0, 1]
    c2 = pair[1, 1]
    i = start
    while i + 1 < line.length
      if line[i, 1] == c1 && line[i + 1, 1] == c2
        return i
      end
      i = i + 1
    end
    -1
  end
end
