# Markdown AST node types and node class
# Used by MarkdownParser and MarkdownRenderer

# Node type constants
MD_DOCUMENT = 0
MD_HEADING = 1
MD_PARAGRAPH = 2
MD_TEXT = 3
MD_STRONG = 4
MD_EMPHASIS = 5
MD_CODE_INLINE = 6
MD_CODE_BLOCK = 7
MD_BLOCKQUOTE = 8
MD_LIST = 9
MD_LIST_ITEM = 10
MD_LINK = 11
MD_HORIZONTAL_RULE = 12
MD_SOFT_BREAK = 13
MD_STRIKETHROUGH = 14
MD_TABLE = 15
MD_TABLE_ROW = 16
MD_TABLE_CELL = 17
MD_IMAGE = 18
MD_MERMAID = 19

class MdNode
  def initialize(type)
    @type = type
    @children = []
    @content = ""
    @level = 0
    @language = ""
    @href = ""
    @ordered = false
    @start_num = 1
    @checked = -1
    @align = 0
    @is_header = false
  end

  def type
    @type
  end

  def children
    @children
  end

  def content
    @content
  end

  def content=(v)
    @content = v
  end

  def level
    @level
  end

  def level=(v)
    @level = v
  end

  def language
    @language
  end

  def language=(v)
    @language = v
  end

  def href
    @href
  end

  def href=(v)
    @href = v
  end

  def ordered
    @ordered
  end

  def ordered=(v)
    @ordered = v
  end

  def start_num
    @start_num
  end

  def start_num=(v)
    @start_num = v
  end

  def checked
    @checked
  end

  def checked=(v)
    @checked = v
  end

  def align
    @align
  end

  def align=(v)
    @align = v
  end

  def is_header
    @is_header
  end

  def is_header=(v)
    @is_header = v
  end

  def add_child(node)
    @children.push(node)
  end
end
