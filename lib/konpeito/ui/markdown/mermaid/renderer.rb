# Mermaid diagram renderer - draws flowcharts using KUIRuntime primitives
# Handles node shapes, edge lines with arrows, labels, and subgraphs

class MermaidRenderer
  def initialize(theme)
    @theme = theme
    @font_family = $theme.font_family
    @font_size = 12.0
  end

  def render(painter, diagram, x, y, width)
    # Layout the diagram
    layout = MermaidLayout.new
    layout.layout(diagram, width, 20.0)

    # Calculate total dimensions
    total_height = layout.calculate_height(diagram)
    total_width = layout.calculate_width(diagram)

    # Draw background
    painter.fill_round_rect(x, y, width, total_height, 6.0, @theme.code_bg_color)

    # Draw subgraphs first (behind nodes)
    si = 0
    while si < diagram.subgraphs.length
      draw_subgraph(painter, diagram.subgraphs[si], x, y)
      si = si + 1
    end

    # Draw edges
    ei = 0
    while ei < diagram.edges.length
      draw_edge(painter, diagram, diagram.edges[ei], x, y)
      ei = ei + 1
    end

    # Draw nodes on top
    ni = 0
    while ni < diagram.nodes.length
      draw_node(painter, diagram.nodes[ni], x, y)
      ni = ni + 1
    end

    total_height
  end

  # --- Node drawing ---

  def draw_node(painter, node, ox, oy)
    nx = ox + node.x
    ny = oy + node.y
    w = node.width
    h = node.height
    fill = @theme.mermaid_node_fill
    stroke = @theme.mermaid_node_stroke
    text_color = @theme.mermaid_node_text

    shape = node.shape

    if shape == MERMAID_SHAPE_ROUNDED
      painter.fill_round_rect(nx, ny, w, h, 10.0, fill)
      painter.stroke_round_rect(nx, ny, w, h, 10.0, stroke, 1.5)
    elsif shape == MERMAID_SHAPE_STADIUM
      r = h / 2.0
      painter.fill_round_rect(nx, ny, w, h, r, fill)
      painter.stroke_round_rect(nx, ny, w, h, r, stroke, 1.5)
    elsif shape == MERMAID_SHAPE_CIRCLE
      cx = nx + w / 2.0
      cy = ny + h / 2.0
      r = w / 2.0
      painter.fill_circle(cx, cy, r, fill)
      # Stroke circle via round rect with full radius
      painter.stroke_round_rect(nx, ny, w, h, r, stroke, 1.5)
    elsif shape == MERMAID_SHAPE_DIAMOND
      draw_diamond(painter, nx, ny, w, h, fill, stroke)
    elsif shape == MERMAID_SHAPE_HEXAGON
      draw_hexagon(painter, nx, ny, w, h, fill, stroke)
    elsif shape == MERMAID_SHAPE_SUBROUTINE
      painter.fill_rect(nx, ny, w, h, fill)
      painter.stroke_rect(nx, ny, w, h, stroke, 1.5)
      # Inner vertical lines for subroutine
      inset = 8.0
      painter.draw_line(nx + inset, ny, nx + inset, ny + h, stroke, 1.5)
      painter.draw_line(nx + w - inset, ny, nx + w - inset, ny + h, stroke, 1.5)
    else
      # RECT (default)
      painter.fill_rect(nx, ny, w, h, fill)
      painter.stroke_rect(nx, ny, w, h, stroke, 1.5)
    end

    # Draw label centered
    label = node.label
    text_w = painter.measure_text_width(label, @font_family, @font_size)
    ascent = painter.get_text_ascent(@font_family, @font_size)
    tx = nx + (w - text_w) / 2.0
    ty = ny + (h + ascent) / 2.0
    painter.draw_text(label, tx, ty, @font_family, @font_size, text_color)
  end

  def draw_diamond(painter, x, y, w, h, fill, stroke)
    cx = x + w / 2.0
    cy = y + h / 2.0

    # Fill diamond using horizontal strips for proper shape
    strips = 20
    strip_h = h / 20.0
    si = 0
    while si < strips
      sy = y + si * strip_h
      # Distance from vertical center
      dist = sy + strip_h / 2.0 - cy
      if dist < 0.0
        dist = 0.0 - dist
      end
      ratio = dist / (h / 2.0)
      if ratio > 1.0
        ratio = 1.0
      end
      sw = w * (1.0 - ratio)
      sx = cx - sw / 2.0
      painter.fill_rect(sx, sy, sw, strip_h + 1.0, fill)
      si = si + 1
    end

    # Draw diamond outline
    painter.draw_line(cx, y, x + w, cy, stroke, 1.5)
    painter.draw_line(x + w, cy, cx, y + h, stroke, 1.5)
    painter.draw_line(cx, y + h, x, cy, stroke, 1.5)
    painter.draw_line(x, cy, cx, y, stroke, 1.5)
  end

  def draw_hexagon(painter, x, y, w, h, fill, stroke)
    inset = w * 0.15
    # Approximate hexagon with a rounded rect
    painter.fill_round_rect(x, y, w, h, 4.0, fill)

    # Draw hexagon outline (6 lines)
    painter.draw_line(x + inset, y, x + w - inset, y, stroke, 1.5)
    painter.draw_line(x + w - inset, y, x + w, y + h / 2.0, stroke, 1.5)
    painter.draw_line(x + w, y + h / 2.0, x + w - inset, y + h, stroke, 1.5)
    painter.draw_line(x + w - inset, y + h, x + inset, y + h, stroke, 1.5)
    painter.draw_line(x + inset, y + h, x, y + h / 2.0, stroke, 1.5)
    painter.draw_line(x, y + h / 2.0, x + inset, y, stroke, 1.5)
  end

  # --- Edge drawing ---

  def draw_edge(painter, diagram, edge, ox, oy)
    src = diagram.get_node(edge.source)
    tgt = diagram.get_node(edge.target)
    if !src || !tgt
      return
    end

    color = @theme.mermaid_edge_color

    # Calculate connection points (center of node edges)
    src_cx = ox + src.x + src.width / 2.0
    src_cy = oy + src.y + src.height / 2.0
    tgt_cx = ox + tgt.x + tgt.width / 2.0
    tgt_cy = oy + tgt.y + tgt.height / 2.0

    # Determine which edges to connect from
    horizontal = diagram.direction == MERMAID_DIR_LR || diagram.direction == MERMAID_DIR_RL

    if horizontal
      # Connect left/right edges
      if src_cx < tgt_cx
        x1 = ox + src.x + src.width
        x2 = ox + tgt.x
      else
        x1 = ox + src.x
        x2 = ox + tgt.x + tgt.width
      end
      y1 = src_cy
      y2 = tgt_cy
    else
      # Connect top/bottom edges
      if src_cy < tgt_cy
        y1 = oy + src.y + src.height
        y2 = oy + tgt.y
      else
        y1 = oy + src.y
        y2 = oy + tgt.y + tgt.height
      end
      x1 = src_cx
      x2 = tgt_cx
    end

    # Draw line based on line type
    stroke_w = 1.5
    if edge.line_type == MERMAID_LINE_THICK
      stroke_w = 3.0
    end

    if edge.line_type == MERMAID_LINE_DASHED
      draw_dashed_line(painter, x1, y1, x2, y2, color, stroke_w)
    else
      painter.draw_line(x1, y1, x2, y2, color, stroke_w)
    end

    # Draw arrow at target
    if edge.arrow_type == MERMAID_ARROW_ARROW
      draw_arrowhead(painter, x1, y1, x2, y2, color)
    elsif edge.arrow_type == MERMAID_ARROW_CIRCLE
      painter.fill_circle(x2, y2, 4.0, color)
    elsif edge.arrow_type == MERMAID_ARROW_CROSS
      draw_cross(painter, x2, y2, color)
    end

    # Draw edge label
    if edge.label.length > 0
      mid_x = (x1 + x2) / 2.0
      mid_y = (y1 + y2) / 2.0
      label_w = painter.measure_text_width(edge.label, @font_family, @font_size)
      ascent = painter.get_text_ascent(@font_family, @font_size)

      # Background for label
      label_pad = 4.0
      painter.fill_round_rect(mid_x - label_w / 2.0 - label_pad, mid_y - ascent / 2.0 - label_pad,
                               label_w + label_pad * 2.0, ascent + label_pad * 2.0,
                               3.0, @theme.code_bg_color)
      painter.draw_text(edge.label, mid_x - label_w / 2.0, mid_y + ascent / 2.0,
                        @font_family, @font_size, @theme.text_color)
    end
  end

  def approx_sqrt(val)
    # Newton's method sqrt approximation
    if val <= 0.0
      return 0.0
    end
    guess = val / 2.0
    if guess < 1.0
      guess = 1.0
    end
    iter = 0
    while iter < 10
      guess = (guess + val / guess) / 2.0
      iter = iter + 1
    end
    guess
  end

  def draw_dashed_line(painter, x1, y1, x2, y2, color, stroke_w)
    # Draw as series of short segments
    dx = x2 - x1
    dy = y2 - y1
    length = approx_sqrt(dx * dx + dy * dy)
    if length < 1.0
      return
    end

    dash_len = 8.0
    gap_len = 4.0
    segment = dash_len + gap_len

    nx = dx / length
    ny = dy / length

    dist = 0.0
    while dist < length
      seg_start_x = x1 + nx * dist
      seg_start_y = y1 + ny * dist
      seg_end = dist + dash_len
      if seg_end > length
        seg_end = length
      end
      seg_end_x = x1 + nx * seg_end
      seg_end_y = y1 + ny * seg_end
      painter.draw_line(seg_start_x, seg_start_y, seg_end_x, seg_end_y, color, stroke_w)
      dist = dist + segment
    end
  end

  def draw_arrowhead(painter, x1, y1, x2, y2, color)
    # Draw a small triangle at (x2, y2) pointing away from (x1, y1)
    dx = x2 - x1
    dy = y2 - y1
    length = approx_sqrt(dx * dx + dy * dy)
    if length < 1.0
      return
    end

    arrow_size = 8.0
    nx = dx / length
    ny = dy / length

    # Arrow base center
    base_x = x2 - nx * arrow_size
    base_y = y2 - ny * arrow_size

    # Perpendicular
    px = 0.0 - ny
    py = nx

    # Three points of triangle
    half = arrow_size * 0.5
    p1x = base_x + px * half
    p1y = base_y + py * half
    p2x = base_x - px * half
    p2y = base_y - py * half

    # Draw as three lines forming a filled triangle
    painter.draw_line(x2, y2, p1x, p1y, color, 1.5)
    painter.draw_line(x2, y2, p2x, p2y, color, 1.5)
    painter.draw_line(p1x, p1y, p2x, p2y, color, 1.5)
  end

  def draw_cross(painter, x, y, color)
    size = 5.0
    painter.draw_line(x - size, y - size, x + size, y + size, color, 1.5)
    painter.draw_line(x - size, y + size, x + size, y - size, color, 1.5)
  end

  # --- Subgraph drawing ---

  def draw_subgraph(painter, sg, ox, oy)
    sx = ox + sg.x
    sy = oy + sg.y
    w = sg.width
    h = sg.height

    # Background
    painter.fill_round_rect(sx, sy, w, h, 6.0, @theme.mermaid_subgraph_bg)
    # Border
    painter.stroke_round_rect(sx, sy, w, h, 6.0, @theme.mermaid_subgraph_border, 1.0)

    # Title
    if sg.title.length > 0
      ascent = painter.get_text_ascent(@font_family, @font_size)
      painter.draw_text(sg.title, sx + 8.0, sy + ascent + 4.0,
                        @font_family, @font_size, @theme.text_color)
    end
  end
end
