# Mermaid diagram data models
# Direction, shape, line type, arrow type constants and node/edge/subgraph classes

# Direction constants
MERMAID_DIR_TB = 0
MERMAID_DIR_BT = 1
MERMAID_DIR_LR = 2
MERMAID_DIR_RL = 3

# Node shape constants
MERMAID_SHAPE_RECT = 0
MERMAID_SHAPE_ROUNDED = 1
MERMAID_SHAPE_STADIUM = 2
MERMAID_SHAPE_CIRCLE = 3
MERMAID_SHAPE_DIAMOND = 4
MERMAID_SHAPE_HEXAGON = 5
MERMAID_SHAPE_SUBROUTINE = 6

# Line type constants
MERMAID_LINE_SOLID = 0
MERMAID_LINE_DASHED = 1
MERMAID_LINE_THICK = 2

# Arrow type constants
MERMAID_ARROW_ARROW = 0
MERMAID_ARROW_OPEN = 1
MERMAID_ARROW_CIRCLE = 2
MERMAID_ARROW_CROSS = 3

class MermaidNode
  def initialize(id, label, shape)
    @id = id
    @label = label
    @shape = shape
    @x = 0.0
    @y = 0.0
    @width = 0.0
    @height = 0.0
    @layer = 0
  end

  def id
    @id
  end

  def label
    @label
  end

  def label=(v)
    @label = v
  end

  def shape
    @shape
  end

  def shape=(v)
    @shape = v
  end

  def x
    @x
  end

  def x=(v)
    @x = v
  end

  def y
    @y
  end

  def y=(v)
    @y = v
  end

  def width
    @width
  end

  def width=(v)
    @width = v
  end

  def height
    @height
  end

  def height=(v)
    @height = v
  end

  def layer
    @layer
  end

  def layer=(v)
    @layer = v
  end
end

class MermaidEdge
  def initialize(source, target, label, line_type, arrow_type)
    @source = source
    @target = target
    @label = label
    @line_type = line_type
    @arrow_type = arrow_type
  end

  def source
    @source
  end

  def target
    @target
  end

  def label
    @label
  end

  def line_type
    @line_type
  end

  def arrow_type
    @arrow_type
  end
end

class MermaidSubgraph
  def initialize(id, title)
    @id = id
    @title = title
    @node_ids = []
    @x = 0.0
    @y = 0.0
    @width = 0.0
    @height = 0.0
  end

  def id
    @id
  end

  def title
    @title
  end

  def node_ids
    @node_ids
  end

  def x
    @x
  end

  def x=(v)
    @x = v
  end

  def y
    @y
  end

  def y=(v)
    @y = v
  end

  def width
    @width
  end

  def width=(v)
    @width = v
  end

  def height
    @height
  end

  def height=(v)
    @height = v
  end
end

class MermaidDiagram
  def initialize(direction)
    @direction = direction
    @nodes = []
    @edges = []
    @subgraphs = []
    @node_map = {}
  end

  def direction
    @direction
  end

  def nodes
    @nodes
  end

  def edges
    @edges
  end

  def subgraphs
    @subgraphs
  end

  def add_node(node)
    if !@node_map[node.id]
      @nodes.push(node)
      @node_map[node.id] = node
    end
  end

  def get_node(id)
    @node_map[id]
  end

  def add_edge(edge)
    @edges.push(edge)
  end

  def add_subgraph(sg)
    @subgraphs.push(sg)
  end
end
