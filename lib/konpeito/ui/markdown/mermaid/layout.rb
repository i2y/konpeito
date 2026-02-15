# Mermaid flowchart layout - BFS layered graph layout
# Assigns x, y, width, height to all nodes and subgraphs
# Avoids complex data structures (no Hash) for JVM compatibility

class MermaidLayout
  def layout(diagram, max_width, padding)
    if diagram.nodes.length == 0
      return
    end

    assign_layers(diagram)
    calculate_node_sizes(diagram)

    horizontal = diagram.direction == MERMAID_DIR_LR || diagram.direction == MERMAID_DIR_RL
    if horizontal
      position_horizontal(diagram, padding)
    else
      position_vertical(diagram, padding, max_width)
    end

    position_subgraphs(diagram)
  end

  def assign_layers(diagram)
    # Simple BFS layering using node.layer field
    # First, set all layers to -1 (unvisited)
    i = 0
    while i < diagram.nodes.length
      diagram.nodes[i].layer = -1
      i = i + 1
    end

    # Find root nodes (not a target of any edge)
    i = 0
    while i < diagram.nodes.length
      n = diagram.nodes[i]
      is_root = true
      ei = 0
      while ei < diagram.edges.length
        if diagram.edges[ei].target == n.id
          is_root = false
          break
        end
        ei = ei + 1
      end
      if is_root
        n.layer = 0
      end
      i = i + 1
    end

    # If no roots, set first node as root
    has_root = false
    i = 0
    while i < diagram.nodes.length
      if diagram.nodes[i].layer == 0
        has_root = true
        break
      end
      i = i + 1
    end
    if !has_root && diagram.nodes.length > 0
      diagram.nodes[0].layer = 0
    end

    # BFS: propagate layers from roots to children
    # Only assign to unvisited nodes (layer < 0) to handle cycles gracefully
    changed = true
    max_iters = diagram.nodes.length
    iter = 0
    while changed && iter < max_iters
      changed = false
      ei = 0
      while ei < diagram.edges.length
        edge = diagram.edges[ei]
        src = diagram.get_node(edge.source)
        tgt = diagram.get_node(edge.target)
        if src && tgt && src.layer >= 0 && tgt.layer < 0
          tgt.layer = src.layer + 1
          changed = true
        end
        ei = ei + 1
      end
      iter = iter + 1
    end

    # Set any remaining unvisited nodes to layer 0
    i = 0
    while i < diagram.nodes.length
      if diagram.nodes[i].layer < 0
        diagram.nodes[i].layer = 0
      end
      i = i + 1
    end
  end

  def calculate_node_sizes(diagram)
    char_width = 8.0
    min_width = 100.0
    node_height = 40.0

    i = 0
    while i < diagram.nodes.length
      n = diagram.nodes[i]
      label_w = n.label.length * char_width + 24.0
      if label_w < min_width
        label_w = min_width
      end
      n.width = label_w
      n.height = node_height

      if n.shape == MERMAID_SHAPE_CIRCLE
        max_dim = n.width
        if n.height > max_dim
          max_dim = n.height
        end
        n.width = max_dim
        n.height = max_dim
      elsif n.shape == MERMAID_SHAPE_DIAMOND
        n.width = n.width + 20.0
        n.height = n.width * 0.6
      end
      i = i + 1
    end
  end

  def max_layer(diagram)
    mx = 0
    i = 0
    while i < diagram.nodes.length
      if diagram.nodes[i].layer > mx
        mx = diagram.nodes[i].layer
      end
      i = i + 1
    end
    mx
  end

  def position_vertical(diagram, padding, max_width)
    h_spacing = 40.0
    v_spacing = 60.0
    ml = max_layer(diagram)
    reverse = diagram.direction == MERMAID_DIR_BT

    # First pass: find max total width across all layers
    max_w = find_max_layer_width(diagram, ml, h_spacing)
    if max_w < 1.0
      max_w = max_width
    end

    # Second pass: position nodes
    y_offset = padding
    layer = 0
    while layer <= ml
      actual = layer
      if reverse
        actual = ml - layer
      end
      position_layer_vertical(diagram, actual, y_offset, padding, max_w, h_spacing)
      tallest = layer_max_height(diagram, actual)
      y_offset = y_offset + tallest + v_spacing
      layer = layer + 1
    end
  end

  def find_max_layer_width(diagram, ml, spacing)
    max_w = 0.0
    layer = 0
    while layer <= ml
      w = compute_layer_width(diagram, layer, spacing)
      if w > max_w
        max_w = w
      end
      layer = layer + 1
    end
    max_w
  end

  def compute_layer_width(diagram, layer, spacing)
    total = 0.0
    count = 0
    i = 0
    while i < diagram.nodes.length
      if diagram.nodes[i].layer == layer
        total = total + diagram.nodes[i].width
        count = count + 1
      end
      i = i + 1
    end
    if count > 1
      total = total + (count - 1) * spacing
    end
    total
  end

  def position_layer_vertical(diagram, layer, y, padding, max_w, spacing)
    lw = compute_layer_width(diagram, layer, spacing)
    start_x = padding + (max_w - lw) / 2.0
    x = start_x
    i = 0
    while i < diagram.nodes.length
      n = diagram.nodes[i]
      if n.layer == layer
        n.x = x
        n.y = y
        x = x + n.width + spacing
      end
      i = i + 1
    end
  end

  def layer_max_height(diagram, layer)
    mx = 0.0
    i = 0
    while i < diagram.nodes.length
      if diagram.nodes[i].layer == layer && diagram.nodes[i].height > mx
        mx = diagram.nodes[i].height
      end
      i = i + 1
    end
    mx
  end

  def position_horizontal(diagram, padding)
    h_spacing = 40.0
    v_spacing = 60.0
    ml = max_layer(diagram)
    reverse = diagram.direction == MERMAID_DIR_RL

    # Find max total height across all layers
    max_h = find_max_layer_height(diagram, ml, h_spacing)

    # Position nodes
    x_offset = padding
    layer = 0
    while layer <= ml
      actual = layer
      if reverse
        actual = ml - layer
      end
      position_layer_horizontal(diagram, actual, x_offset, padding, max_h, h_spacing)
      widest = layer_max_width(diagram, actual)
      x_offset = x_offset + widest + v_spacing
      layer = layer + 1
    end
  end

  def find_max_layer_height(diagram, ml, spacing)
    max_h = 0.0
    layer = 0
    while layer <= ml
      h = compute_layer_height(diagram, layer, spacing)
      if h > max_h
        max_h = h
      end
      layer = layer + 1
    end
    max_h
  end

  def compute_layer_height(diagram, layer, spacing)
    total = 0.0
    count = 0
    i = 0
    while i < diagram.nodes.length
      if diagram.nodes[i].layer == layer
        total = total + diagram.nodes[i].height
        count = count + 1
      end
      i = i + 1
    end
    if count > 1
      total = total + (count - 1) * spacing
    end
    total
  end

  def position_layer_horizontal(diagram, layer, x, padding, max_h, spacing)
    lh = compute_layer_height(diagram, layer, spacing)
    start_y = padding + (max_h - lh) / 2.0
    y = start_y
    i = 0
    while i < diagram.nodes.length
      n = diagram.nodes[i]
      if n.layer == layer
        n.x = x
        n.y = y
        y = y + n.height + spacing
      end
      i = i + 1
    end
  end

  def layer_max_width(diagram, layer)
    mx = 0.0
    i = 0
    while i < diagram.nodes.length
      if diagram.nodes[i].layer == layer && diagram.nodes[i].width > mx
        mx = diagram.nodes[i].width
      end
      i = i + 1
    end
    mx
  end

  def position_subgraphs(diagram)
    sg_padding = 15.0
    title_height = 20.0

    si = 0
    while si < diagram.subgraphs.length
      sg = diagram.subgraphs[si]
      if sg.node_ids.length > 0
        compute_subgraph_bounds(diagram, sg, sg_padding, title_height)
      end
      si = si + 1
    end
  end

  def compute_subgraph_bounds(diagram, sg, sg_padding, title_height)
    min_x = 99999.0
    min_y = 99999.0
    max_x = 0.0
    max_y = 0.0

    ni = 0
    while ni < sg.node_ids.length
      node = diagram.get_node(sg.node_ids[ni])
      if node
        if node.x < min_x
          min_x = node.x
        end
        if node.y < min_y
          min_y = node.y
        end
        right = node.x + node.width
        if right > max_x
          max_x = right
        end
        bottom = node.y + node.height
        if bottom > max_y
          max_y = bottom
        end
      end
      ni = ni + 1
    end

    sg.x = min_x - sg_padding
    sg.y = min_y - sg_padding - title_height
    sg.width = (max_x - min_x) + sg_padding * 2.0
    sg.height = (max_y - min_y) + sg_padding * 2.0 + title_height
  end

  def calculate_height(diagram)
    max_y = 0.0
    i = 0
    while i < diagram.nodes.length
      bottom = diagram.nodes[i].y + diagram.nodes[i].height
      if bottom > max_y
        max_y = bottom
      end
      i = i + 1
    end
    i = 0
    while i < diagram.subgraphs.length
      bottom = diagram.subgraphs[i].y + diagram.subgraphs[i].height
      if bottom > max_y
        max_y = bottom
      end
      i = i + 1
    end
    max_y + 20.0
  end

  def calculate_width(diagram)
    max_x = 0.0
    i = 0
    while i < diagram.nodes.length
      right = diagram.nodes[i].x + diagram.nodes[i].width
      if right > max_x
        max_x = right
      end
      i = i + 1
    end
    max_x + 20.0
  end
end
