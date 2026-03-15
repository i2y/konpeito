# frozen_string_literal: true

# KUI Markdown Renderer — GFM-level Markdown rendering for KUI
#
# Architecture: 2-layer (parse -> render)
#   md_parse(slot, text)        — parse text into instruction buffer (on change only)
#   md_render(slot, text, size:) — read instructions and emit KUI widgets
#   markdown(text, size:)       — convenience API (slot=0, auto parse+render)
#
# Instruction encoding in KUIMDState.d (NativeArray):
#   Each slot uses offset = slot * 4096
#   Instructions are variable-length integer sequences terminated by 0 (END)
#
# Block types:
#   1=HEADING     [1, level, text_start, text_len]
#   2=PARA_START  [2]
#   3=PARA_END    [3]
#   4=CODE_START  [4, text_start, text_len]
#   5=CODE_END    [5]
#   6=BULLET      [6, indent, text_start, text_len]
#   7=NUMBERED    [7, num, indent, text_start, text_len]
#   8=BQ_START    [8, depth]
#   9=BQ_END      [9]
#  10=HR          [10]
#  11=TBL_START   [11, cols]
#  12=TBL_ROW     [12, cols, s1, l1, s2, l2, ...]
#  13=TBL_END     [13]
#  14=TASK        [14, checked, indent, text_start, text_len]
#  15=IMAGE       [15, alt_start, alt_len]
#
# Inline types (within PARA_START..PARA_END):
#  20=TEXT        [20, start, len]
#  21=BOLD        [21, start, len]
#  22=ITALIC      [22, start, len]
#  23=STRIKE      [23, start, len]
#  24=CODE_INLINE [24, start, len]
#  25=LINK        [25, text_start, text_len, url_start, url_len]
#  26=BOLD_ITALIC [26, start, len]
#
#   0=END         [0]
#
# rbs_inline: enabled

# @rbs module KUIMDState
# @rbs   @d: NativeArray[Integer, 8192]
# @rbs   @m: NativeArray[Integer, 8]
# @rbs end

# KUIMDState.m layout per slot (slot * 4 + offset):
#   [0] = hash_hi (upper bits of text hash)
#   [1] = hash_lo (lower bits of text hash)
#   [2] = instruction count
#   [3] = reserved

# ════════════════════════════════════════════
# Internal: Simple text hash (for change detection)
# ════════════════════════════════════════════

#: (String text) -> Integer
def _md_hash(text)
  h = 5381
  i = 0
  len = text.bytesize
  while i < len
    c = text.getbyte(i)
    h = ((h * 33) + c) % 2147483647
    i = i + 1
  end
  return h
end

# ════════════════════════════════════════════
# Internal: Emit instruction to buffer
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, Integer val) -> Integer
def _md_emit(slot, pos, val)
  off = slot * 4096
  if pos < 4096
    KUIMDState.d[off + pos] = val
  end
  return pos + 1
end

# ════════════════════════════════════════════
# Internal: Check if line is a heading
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_heading_level(text, line_start, line_len)
  level = 0
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 35
      level = level + 1
      i = i + 1
    else
      break
    end
  end
  if level > 0
    if level <= 6
      if i < limit
        c2 = text.getbyte(i)
        if c2 == 32
          return level
        end
      end
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Check if line is HR (---, ***, ___)
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_is_hr(text, line_start, line_len)
  if line_len < 3
    return 0
  end
  c0 = text.getbyte(line_start)
  if c0 == 45 || c0 == 42 || c0 == 95
    count = 0
    i = line_start
    limit = line_start + line_len
    while i < limit
      cc = text.getbyte(i)
      if cc == c0
        count = count + 1
      else
        if cc != 32
          return 0
        end
      end
      i = i + 1
    end
    if count >= 3
      return 1
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Check if line starts a code fence
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_is_code_fence(text, line_start, line_len)
  if line_len < 3
    return 0
  end
  c0 = text.getbyte(line_start)
  c1 = text.getbyte(line_start + 1)
  c2 = text.getbyte(line_start + 2)
  if c0 == 96 && c1 == 96 && c2 == 96
    return 1
  end
  if c0 == 126 && c1 == 126 && c2 == 126
    return 1
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Check bullet list item (- or * or + followed by space)
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_bullet_indent(text, line_start, line_len)
  indent = 0
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 32
      indent = indent + 1
      i = i + 1
    else
      break
    end
  end
  if i < limit
    c = text.getbyte(i)
    if c == 45 || c == 42 || c == 43
      if i + 1 < limit
        c2 = text.getbyte(i + 1)
        if c2 == 32
          return indent + 1
        end
      end
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Content start after bullet marker
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_bullet_content_start(text, line_start, line_len)
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 32
      i = i + 1
    else
      break
    end
  end
  # skip bullet char + space
  return i + 2
end

# ════════════════════════════════════════════
# Internal: Check numbered list item (1. 2. etc)
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_numbered_num(text, line_start, line_len)
  indent = 0
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 32
      indent = indent + 1
      i = i + 1
    else
      break
    end
  end
  num = 0
  while i < limit
    c = text.getbyte(i)
    if c >= 48 && c <= 57
      num = num * 10 + (c - 48)
      i = i + 1
    else
      break
    end
  end
  if num > 0
    if i < limit
      c = text.getbyte(i)
      if c == 46
        if i + 1 < limit
          c2 = text.getbyte(i + 1)
          if c2 == 32
            return num
          end
        end
      end
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Content start after number marker
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_numbered_content_start(text, line_start, line_len)
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 32
      i = i + 1
    else
      break
    end
  end
  # skip digits
  while i < limit
    c = text.getbyte(i)
    if c >= 48 && c <= 57
      i = i + 1
    else
      break
    end
  end
  # skip ". "
  return i + 2
end

# ════════════════════════════════════════════
# Internal: Numbered list indent
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_numbered_indent(text, line_start, line_len)
  indent = 0
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 32
      indent = indent + 1
      i = i + 1
    else
      break
    end
  end
  return indent
end

# ════════════════════════════════════════════
# Internal: Check blockquote (> prefix)
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_bq_depth(text, line_start, line_len)
  depth = 0
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 62
      depth = depth + 1
      i = i + 1
      if i < limit
        c2 = text.getbyte(i)
        if c2 == 32
          i = i + 1
        end
      end
    else
      if c == 32
        i = i + 1
      else
        break
      end
    end
  end
  return depth
end

# ════════════════════════════════════════════
# Internal: Content start after blockquote markers
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_bq_content_start(text, line_start, line_len)
  i = line_start
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 62
      i = i + 1
      if i < limit
        c2 = text.getbyte(i)
        if c2 == 32
          i = i + 1
        end
      end
    else
      if c == 32
        i = i + 1
      else
        break
      end
    end
  end
  return i
end

# ════════════════════════════════════════════
# Internal: Check task list item (- [ ] or - [x])
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_is_task(text, line_start, line_len)
  bi = _md_bullet_indent(text, line_start, line_len)
  if bi == 0
    return 0
  end
  cs = _md_bullet_content_start(text, line_start, line_len)
  limit = line_start + line_len
  if cs + 2 < limit
    c0 = text.getbyte(cs)
    c1 = text.getbyte(cs + 1)
    c2 = text.getbyte(cs + 2)
    if c0 == 91
      if c2 == 93
        if c1 == 32 || c1 == 120 || c1 == 88
          return 1
        end
      end
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Task checked state (0 or 1)
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_task_checked(text, line_start, line_len)
  cs = _md_bullet_content_start(text, line_start, line_len)
  c1 = text.getbyte(cs + 1)
  if c1 == 120 || c1 == 88
    return 1
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Task content start (after [x] )
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_task_content_start(text, line_start, line_len)
  cs = _md_bullet_content_start(text, line_start, line_len)
  # skip "[ ] " or "[x] "
  return cs + 4
end

# ════════════════════════════════════════════
# Internal: Check if line is a table row
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_is_table_row(text, line_start, line_len)
  if line_len < 3
    return 0
  end
  c0 = text.getbyte(line_start)
  if c0 == 124
    return 1
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Check if table row is separator (|---|---|)
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_is_table_sep(text, line_start, line_len)
  i = line_start
  limit = line_start + line_len
  has_dash = 0
  while i < limit
    c = text.getbyte(i)
    if c == 45
      has_dash = 1
    else
      if c != 124 && c != 32 && c != 58
        return 0
      end
    end
    i = i + 1
  end
  return has_dash
end

# ════════════════════════════════════════════
# Internal: Count table columns
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_table_cols(text, line_start, line_len)
  cols = 0
  i = line_start
  limit = line_start + line_len
  # skip leading |
  if i < limit
    c = text.getbyte(i)
    if c == 124
      i = i + 1
    end
  end
  in_cell = 0
  while i < limit
    c = text.getbyte(i)
    if c == 124
      cols = cols + 1
      in_cell = 0
    else
      in_cell = 1
    end
    i = i + 1
  end
  if in_cell == 1
    cols = cols + 1
  end
  return cols
end

# ════════════════════════════════════════════
# Internal: Check if line starts with ![
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_is_image(text, line_start, line_len)
  if line_len < 4
    return 0
  end
  c0 = text.getbyte(line_start)
  c1 = text.getbyte(line_start + 1)
  if c0 == 33 && c1 == 91
    return 1
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Extract image alt text range
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_image_alt_start(text, line_start, line_len)
  return line_start + 2
end

#: (String text, Integer line_start, Integer line_len) -> Integer
def _md_image_alt_len(text, line_start, line_len)
  i = line_start + 2
  limit = line_start + line_len
  while i < limit
    c = text.getbyte(i)
    if c == 93
      return i - (line_start + 2)
    end
    i = i + 1
  end
  return limit - (line_start + 2)
end

# ════════════════════════════════════════════
# Block Parser — Phase 1 + Phase 3 + Phase 4
# ════════════════════════════════════════════

#: (Integer slot, String text) -> Integer
def md_parse(slot, text)
  # Change detection via hash
  h = _md_hash(text)
  moff = slot * 4
  old_h = KUIMDState.m[moff]
  if old_h == h
    return 0
  end
  KUIMDState.m[moff] = h
  KUIMDState.m[moff + 1] = 0

  pos = 0
  tlen = text.bytesize
  line_start = 0
  in_code = 0
  code_start = 0
  in_para = 0
  in_bq = 0
  in_table = 0

  while line_start < tlen
    # find line end
    line_end = line_start
    while line_end < tlen
      lc = text.getbyte(line_end)
      if lc == 10
        break
      end
      line_end = line_end + 1
    end
    line_len = line_end - line_start

    if in_code == 1
      pos = _md_parse_code_line(slot, pos, text, line_start, line_len, code_start)
      if _md_is_code_fence(text, line_start, line_len) == 1
        # emit CODE_START with accumulated content
        pos = _md_emit_code_block(slot, pos, text, code_start, line_start)
        in_code = 0
      end
    else
      pos = _md_parse_block_line(slot, pos, text, line_start, line_len,
                                  in_para, in_bq, in_table)
      # update state from parse result
      result = _md_line_type(text, line_start, line_len, in_para, in_bq, in_table)
      if result == 1
        # code fence start
        in_code = 1
        code_start = line_end + 1
      end
      if result == 2
        in_para = 1
      end
      if result == 3
        in_para = 0
      end
      if result == 4
        in_bq = _md_bq_depth(text, line_start, line_len)
      end
      if result == 5
        in_bq = 0
      end
      if result == 6
        in_table = 1
      end
      if result == 7
        in_table = 0
      end
    end

    line_start = line_end + 1
  end

  # close any open state
  if in_para == 1
    pos = _md_emit(slot, pos, 3) # PARA_END
  end
  if in_bq > 0
    pos = _md_emit(slot, pos, 9) # BQ_END
  end
  if in_table == 1
    pos = _md_emit(slot, pos, 13) # TBL_END
  end

  # END marker
  pos = _md_emit(slot, pos, 0)
  KUIMDState.m[moff + 2] = pos
  return 0
end

# ════════════════════════════════════════════
# Internal: Determine line type for state tracking
# ════════════════════════════════════════════

#: (String text, Integer line_start, Integer line_len, Integer in_para, Integer in_bq, Integer in_table) -> Integer
def _md_line_type(text, line_start, line_len, in_para, in_bq, in_table)
  if line_len == 0
    if in_para == 1
      return 3 # close para
    end
    if in_bq > 0
      return 5 # close bq
    end
    if in_table == 1
      return 7 # close table
    end
    return 0
  end
  if _md_is_code_fence(text, line_start, line_len) == 1
    if in_para == 1
      return 3
    end
    return 1 # code fence
  end
  if _md_heading_level(text, line_start, line_len) > 0
    return 0 # heading is standalone
  end
  if _md_is_hr(text, line_start, line_len) == 1
    return 0 # hr is standalone
  end
  bq_d = _md_bq_depth(text, line_start, line_len)
  if bq_d > 0
    return 4 # blockquote
  end
  if _md_is_table_row(text, line_start, line_len) == 1
    if in_table == 0
      return 6 # table start
    end
    return 0
  end
  if _md_bullet_indent(text, line_start, line_len) > 0
    return 0 # list item
  end
  if _md_numbered_num(text, line_start, line_len) > 0
    return 0 # numbered list
  end
  if _md_is_image(text, line_start, line_len) == 1
    return 0
  end
  # paragraph text
  if in_para == 0
    return 2 # open para
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Parse a single block-level line
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer ls, Integer ll, Integer in_para, Integer in_bq, Integer in_table) -> Integer
def _md_parse_block_line(slot, pos, text, ls, ll, in_para, in_bq, in_table)
  if ll == 0
    # blank line: close open states
    if in_para == 1
      pos = _md_emit(slot, pos, 3) # PARA_END
    end
    if in_bq > 0
      pos = _md_emit(slot, pos, 9) # BQ_END
    end
    if in_table == 1
      pos = _md_emit(slot, pos, 13) # TBL_END
    end
    return pos
  end

  # code fence
  if _md_is_code_fence(text, ls, ll) == 1
    if in_para == 1
      pos = _md_emit(slot, pos, 3) # PARA_END
    end
    return pos # code fence start handled in md_parse
  end

  # heading
  hlevel = _md_heading_level(text, ls, ll)
  if hlevel > 0
    if in_para == 1
      pos = _md_emit(slot, pos, 3)
    end
    ts = ls + hlevel + 1
    tl = ll - hlevel - 1
    pos = _md_emit(slot, pos, 1) # HEADING
    pos = _md_emit(slot, pos, hlevel)
    pos = _md_emit(slot, pos, ts)
    pos = _md_emit(slot, pos, tl)
    return pos
  end

  # HR
  if _md_is_hr(text, ls, ll) == 1
    if in_para == 1
      pos = _md_emit(slot, pos, 3)
    end
    pos = _md_emit(slot, pos, 10) # HR
    return pos
  end

  # image
  if _md_is_image(text, ls, ll) == 1
    if in_para == 1
      pos = _md_emit(slot, pos, 3)
    end
    as = _md_image_alt_start(text, ls, ll)
    al = _md_image_alt_len(text, ls, ll)
    pos = _md_emit(slot, pos, 15) # IMAGE
    pos = _md_emit(slot, pos, as)
    pos = _md_emit(slot, pos, al)
    return pos
  end

  # blockquote
  bq_d = _md_bq_depth(text, ls, ll)
  if bq_d > 0
    if in_bq == 0
      pos = _md_emit(slot, pos, 8) # BQ_START
      pos = _md_emit(slot, pos, bq_d)
    end
    cs = _md_bq_content_start(text, ls, ll)
    cl = ll - (cs - ls)
    if cl > 0
      pos = _md_emit(slot, pos, 20) # TEXT (inline)
      pos = _md_emit(slot, pos, cs)
      pos = _md_emit(slot, pos, cl)
    end
    return pos
  end

  # task list
  if _md_is_task(text, ls, ll) == 1
    if in_para == 1
      pos = _md_emit(slot, pos, 3)
    end
    checked = _md_task_checked(text, ls, ll)
    indent = _md_bullet_indent(text, ls, ll)
    cs = _md_task_content_start(text, ls, ll)
    cl = ll - (cs - ls)
    pos = _md_emit(slot, pos, 14) # TASK
    pos = _md_emit(slot, pos, checked)
    pos = _md_emit(slot, pos, indent)
    pos = _md_emit(slot, pos, cs)
    pos = _md_emit(slot, pos, cl)
    return pos
  end

  # bullet list
  bi = _md_bullet_indent(text, ls, ll)
  if bi > 0
    if in_para == 1
      pos = _md_emit(slot, pos, 3)
    end
    cs = _md_bullet_content_start(text, ls, ll)
    cl = ll - (cs - ls)
    pos = _md_emit(slot, pos, 6) # BULLET
    pos = _md_emit(slot, pos, bi)
    pos = _md_emit(slot, pos, cs)
    pos = _md_emit(slot, pos, cl)
    return pos
  end

  # numbered list
  num = _md_numbered_num(text, ls, ll)
  if num > 0
    if in_para == 1
      pos = _md_emit(slot, pos, 3)
    end
    indent = _md_numbered_indent(text, ls, ll)
    cs = _md_numbered_content_start(text, ls, ll)
    cl = ll - (cs - ls)
    pos = _md_emit(slot, pos, 7) # NUMBERED
    pos = _md_emit(slot, pos, num)
    pos = _md_emit(slot, pos, indent)
    pos = _md_emit(slot, pos, cs)
    pos = _md_emit(slot, pos, cl)
    return pos
  end

  # table row
  if _md_is_table_row(text, ls, ll) == 1
    if in_table == 0
      cols = _md_table_cols(text, ls, ll)
      pos = _md_emit(slot, pos, 11) # TBL_START
      pos = _md_emit(slot, pos, cols)
    end
    # skip separator rows
    if _md_is_table_sep(text, ls, ll) == 1
      return pos
    end
    pos = _md_emit_table_row(slot, pos, text, ls, ll)
    return pos
  end

  # paragraph text — parse inlines
  if in_para == 0
    pos = _md_emit(slot, pos, 2) # PARA_START
  end
  pos = _md_parse_inlines(slot, pos, text, ls, ll)
  return pos
end

# ════════════════════════════════════════════
# Internal: No-op for code lines during accumulation
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer ls, Integer ll, Integer code_start) -> Integer
def _md_parse_code_line(slot, pos, text, ls, ll, code_start)
  return pos
end

# ════════════════════════════════════════════
# Internal: Emit accumulated code block
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer code_start, Integer fence_start) -> Integer
def _md_emit_code_block(slot, pos, text, code_start, fence_start)
  # trim trailing newline from code content
  code_len = fence_start - code_start
  if code_len > 0
    last_c = text.getbyte(code_start + code_len - 1)
    if last_c == 10
      code_len = code_len - 1
    end
  end
  if code_len < 0
    code_len = 0
  end
  pos = _md_emit(slot, pos, 4) # CODE_START
  pos = _md_emit(slot, pos, code_start)
  pos = _md_emit(slot, pos, code_len)
  pos = _md_emit(slot, pos, 5) # CODE_END
  return pos
end

# ════════════════════════════════════════════
# Internal: Emit table row cells
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer ls, Integer ll) -> Integer
def _md_emit_table_row(slot, pos, text, ls, ll)
  cols = _md_table_cols(text, ls, ll)
  pos = _md_emit(slot, pos, 12) # TBL_ROW
  pos = _md_emit(slot, pos, cols)

  i = ls
  limit = ls + ll
  # skip leading |
  if i < limit
    c = text.getbyte(i)
    if c == 124
      i = i + 1
    end
  end

  col = 0
  while col < cols
    # skip whitespace
    while i < limit
      c = text.getbyte(i)
      if c == 32
        i = i + 1
      else
        break
      end
    end
    cell_start = i
    # find | or end
    while i < limit
      c = text.getbyte(i)
      if c == 124
        break
      end
      i = i + 1
    end
    cell_end = i
    # trim trailing spaces
    while cell_end > cell_start
      c = text.getbyte(cell_end - 1)
      if c == 32
        cell_end = cell_end - 1
      else
        break
      end
    end
    pos = _md_emit(slot, pos, cell_start)
    pos = _md_emit(slot, pos, cell_end - cell_start)
    # skip |
    if i < limit
      i = i + 1
    end
    col = col + 1
  end
  return pos
end

# ════════════════════════════════════════════
# Inline Parser — Phase 2
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer start, Integer len) -> Integer
def _md_parse_inlines(slot, pos, text, start, len)
  i = start
  limit = start + len
  seg_start = i

  while i < limit
    c = text.getbyte(i)

    # backtick — inline code
    if c == 96
      if i > seg_start
        pos = _md_emit(slot, pos, 20) # TEXT
        pos = _md_emit(slot, pos, seg_start)
        pos = _md_emit(slot, pos, i - seg_start)
      end
      pos = _md_parse_inline_code(slot, pos, text, i, limit)
      i = _md_skip_inline_code(text, i, limit)
      seg_start = i
    # ** or *
    else
      if c == 42
        if i > seg_start
          pos = _md_emit(slot, pos, 20) # TEXT
          pos = _md_emit(slot, pos, seg_start)
          pos = _md_emit(slot, pos, i - seg_start)
        end
        pos = _md_parse_inline_star(slot, pos, text, i, limit)
        i = _md_skip_inline_star(text, i, limit)
        seg_start = i
      # ~~
      else
        if c == 126
          if i + 1 < limit
            c2 = text.getbyte(i + 1)
            if c2 == 126
              if i > seg_start
                pos = _md_emit(slot, pos, 20)
                pos = _md_emit(slot, pos, seg_start)
                pos = _md_emit(slot, pos, i - seg_start)
              end
              pos = _md_parse_inline_strike(slot, pos, text, i, limit)
              i = _md_skip_inline_strike(text, i, limit)
              seg_start = i
            else
              i = i + 1
            end
          else
            i = i + 1
          end
        # [text](url)
        else
          if c == 91
            if i > seg_start
              pos = _md_emit(slot, pos, 20)
              pos = _md_emit(slot, pos, seg_start)
              pos = _md_emit(slot, pos, i - seg_start)
            end
            link_end = _md_skip_inline_link(text, i, limit)
            if link_end > i
              pos = _md_parse_inline_link(slot, pos, text, i, limit)
              i = link_end
            else
              i = i + 1
            end
            seg_start = i
          else
            i = i + 1
          end
        end
      end
    end
  end

  # remaining text
  if seg_start < limit
    pos = _md_emit(slot, pos, 20) # TEXT
    pos = _md_emit(slot, pos, seg_start)
    pos = _md_emit(slot, pos, limit - seg_start)
  end
  return pos
end

# ════════════════════════════════════════════
# Internal: Parse inline code `...`
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer i, Integer limit) -> Integer
def _md_parse_inline_code(slot, pos, text, i, limit)
  cs = i + 1
  j = cs
  while j < limit
    c = text.getbyte(j)
    if c == 96
      pos = _md_emit(slot, pos, 24) # CODE_INLINE
      pos = _md_emit(slot, pos, cs)
      pos = _md_emit(slot, pos, j - cs)
      return pos
    end
    j = j + 1
  end
  # no closing backtick — emit as text
  pos = _md_emit(slot, pos, 20)
  pos = _md_emit(slot, pos, i)
  pos = _md_emit(slot, pos, 1)
  return pos
end

#: (String text, Integer i, Integer limit) -> Integer
def _md_skip_inline_code(text, i, limit)
  j = i + 1
  while j < limit
    c = text.getbyte(j)
    if c == 96
      return j + 1
    end
    j = j + 1
  end
  return i + 1
end

# ════════════════════════════════════════════
# Internal: Parse ***bold italic***, **bold**, *italic*
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer i, Integer limit) -> Integer
def _md_parse_inline_star(slot, pos, text, i, limit)
  # check *** (bold italic)
  if i + 2 < limit
    c1 = text.getbyte(i + 1)
    c2 = text.getbyte(i + 2)
    if c1 == 42 && c2 == 42
      cs = i + 3
      j = cs
      while j + 2 < limit
        d0 = text.getbyte(j)
        d1 = text.getbyte(j + 1)
        d2 = text.getbyte(j + 2)
        if d0 == 42 && d1 == 42 && d2 == 42
          pos = _md_emit(slot, pos, 26) # BOLD_ITALIC
          pos = _md_emit(slot, pos, cs)
          pos = _md_emit(slot, pos, j - cs)
          return pos
        end
        j = j + 1
      end
    end
  end
  # check ** (bold)
  if i + 1 < limit
    c1 = text.getbyte(i + 1)
    if c1 == 42
      cs = i + 2
      j = cs
      while j + 1 < limit
        d0 = text.getbyte(j)
        d1 = text.getbyte(j + 1)
        if d0 == 42 && d1 == 42
          pos = _md_emit(slot, pos, 21) # BOLD
          pos = _md_emit(slot, pos, cs)
          pos = _md_emit(slot, pos, j - cs)
          return pos
        end
        j = j + 1
      end
    end
  end
  # single * (italic)
  cs = i + 1
  j = cs
  while j < limit
    c = text.getbyte(j)
    if c == 42
      pos = _md_emit(slot, pos, 22) # ITALIC
      pos = _md_emit(slot, pos, cs)
      pos = _md_emit(slot, pos, j - cs)
      return pos
    end
    j = j + 1
  end
  # no closing — emit as text
  pos = _md_emit(slot, pos, 20)
  pos = _md_emit(slot, pos, i)
  pos = _md_emit(slot, pos, 1)
  return pos
end

#: (String text, Integer i, Integer limit) -> Integer
def _md_skip_inline_star(text, i, limit)
  # check ***
  if i + 2 < limit
    c1 = text.getbyte(i + 1)
    c2 = text.getbyte(i + 2)
    if c1 == 42 && c2 == 42
      j = i + 3
      while j + 2 < limit
        d0 = text.getbyte(j)
        d1 = text.getbyte(j + 1)
        d2 = text.getbyte(j + 2)
        if d0 == 42 && d1 == 42 && d2 == 42
          return j + 3
        end
        j = j + 1
      end
    end
  end
  # check **
  if i + 1 < limit
    c1 = text.getbyte(i + 1)
    if c1 == 42
      j = i + 2
      while j + 1 < limit
        d0 = text.getbyte(j)
        d1 = text.getbyte(j + 1)
        if d0 == 42 && d1 == 42
          return j + 2
        end
        j = j + 1
      end
    end
  end
  # single *
  j = i + 1
  while j < limit
    c = text.getbyte(j)
    if c == 42
      return j + 1
    end
    j = j + 1
  end
  return i + 1
end

# ════════════════════════════════════════════
# Internal: Parse ~~strikethrough~~
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer i, Integer limit) -> Integer
def _md_parse_inline_strike(slot, pos, text, i, limit)
  cs = i + 2
  j = cs
  while j + 1 < limit
    d0 = text.getbyte(j)
    d1 = text.getbyte(j + 1)
    if d0 == 126 && d1 == 126
      pos = _md_emit(slot, pos, 23) # STRIKE
      pos = _md_emit(slot, pos, cs)
      pos = _md_emit(slot, pos, j - cs)
      return pos
    end
    j = j + 1
  end
  pos = _md_emit(slot, pos, 20)
  pos = _md_emit(slot, pos, i)
  pos = _md_emit(slot, pos, 2)
  return pos
end

#: (String text, Integer i, Integer limit) -> Integer
def _md_skip_inline_strike(text, i, limit)
  j = i + 2
  while j + 1 < limit
    d0 = text.getbyte(j)
    d1 = text.getbyte(j + 1)
    if d0 == 126 && d1 == 126
      return j + 2
    end
    j = j + 1
  end
  return i + 2
end

# ════════════════════════════════════════════
# Internal: Parse [text](url)
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer i, Integer limit) -> Integer
def _md_parse_inline_link(slot, pos, text, i, limit)
  # find ]
  ts = i + 1
  j = ts
  te = 0
  while j < limit
    c = text.getbyte(j)
    if c == 93
      te = j
      break
    end
    j = j + 1
  end
  if te == 0
    return pos
  end
  # expect (
  if te + 1 < limit
    c = text.getbyte(te + 1)
    if c == 40
      us = te + 2
      k = us
      while k < limit
        c2 = text.getbyte(k)
        if c2 == 41
          pos = _md_emit(slot, pos, 25) # LINK
          pos = _md_emit(slot, pos, ts)
          pos = _md_emit(slot, pos, te - ts)
          pos = _md_emit(slot, pos, us)
          pos = _md_emit(slot, pos, k - us)
          return pos
        end
        k = k + 1
      end
    end
  end
  return pos
end

#: (String text, Integer i, Integer limit) -> Integer
def _md_skip_inline_link(text, i, limit)
  # find ]
  j = i + 1
  te = 0
  while j < limit
    c = text.getbyte(j)
    if c == 93
      te = j
      break
    end
    j = j + 1
  end
  if te == 0
    return i
  end
  # expect (
  if te + 1 < limit
    c = text.getbyte(te + 1)
    if c == 40
      k = te + 2
      while k < limit
        c2 = text.getbyte(k)
        if c2 == 41
          return k + 1
        end
        k = k + 1
      end
    end
  end
  return i
end

# ════════════════════════════════════════════
# Renderer — Reads instructions, emits KUI widgets
# ════════════════════════════════════════════

#: (Integer slot, String text, Integer size) -> Integer
def md_render(slot, text, size: 16)
  off = slot * 4096
  pos = 0
  op = KUIMDState.d[off]

  while op != 0
    old_pos = pos

    if op == 1
      pos = _md_render_heading(slot, pos, text, size)
    end
    if op == 2
      pos = _md_render_para_start(slot, pos)
    end
    if op == 3
      pos = _md_render_para_end(slot, pos)
    end
    if op == 4
      pos = _md_render_code(slot, pos, text, size)
    end
    if op == 6
      pos = _md_render_bullet(slot, pos, text, size)
    end
    if op == 7
      pos = _md_render_numbered(slot, pos, text, size)
    end
    if op == 8
      pos = _md_render_bq_start(slot, pos, text, size)
    end
    if op == 9
      pos = _md_render_bq_end(slot, pos)
    end
    if op == 10
      pos = _md_render_hr(slot, pos)
    end
    if op == 11
      pos = _md_render_table_start(slot, pos)
    end
    if op == 12
      pos = _md_render_table_row_emit(slot, pos, text, size)
    end
    if op == 13
      pos = _md_render_table_end(slot, pos)
    end
    if op == 14
      pos = _md_render_task(slot, pos, text, size)
    end
    if op == 15
      pos = _md_render_image(slot, pos, text, size)
    end
    # inline types within para
    if op >= 20
      pos = _md_render_inline(slot, pos, text, size)
    end

    # safety: skip if pos didn't advance (unknown op)
    if pos == old_pos
      pos = pos + 1
    end
    op = KUIMDState.d[off + pos]
  end
  return 0
end

# ════════════════════════════════════════════
# Internal: Render heading
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_heading(slot, pos, text, size)
  off = slot * 4096
  level = KUIMDState.d[off + pos + 1]
  ts = KUIMDState.d[off + pos + 2]
  tl = KUIMDState.d[off + pos + 3]
  content = text.byteslice(ts, tl)

  hsz = _md_heading_size(level, size)

  id = kui_auto_id
  _kui_open_i("_mdh", id)
  _kui_layout(1, 0, 0, 4, 4, 2, 1, 0, 0, 0, 0, 0)
  _kui_text_color(content, hsz, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
  _kui_close

  # H1 and H2 get a divider
  if level <= 2
    divider
  end

  return pos + 4
end

# ════════════════════════════════════════════
# Internal: Heading font size calculation
# ════════════════════════════════════════════

#: (Integer level, Integer size) -> Integer
def _md_heading_size(level, size)
  if level == 1
    return size * 2
  end
  if level == 2
    return size * 7 / 4
  end
  if level == 3
    return size * 3 / 2
  end
  if level == 4
    return size * 5 / 4
  end
  if level == 5
    return size
  end
  # level 6
  return size * 7 / 8
end

# ════════════════════════════════════════════
# Internal: Render para start (open hpanel for inlines)
# ════════════════════════════════════════════

#: (Integer slot, Integer pos) -> Integer
def _md_render_para_start(slot, pos)
  off = slot * 4096
  id = kui_auto_id
  _kui_open_i("_mdp", id)
  _kui_layout(0, 0, 0, 2, 2, 0, 1, 0, 0, 0, 0, 0)
  return pos + 1
end

# ════════════════════════════════════════════
# Internal: Render para end (close hpanel)
# ════════════════════════════════════════════

#: (Integer slot, Integer pos) -> Integer
def _md_render_para_end(slot, pos)
  _kui_close
  return pos + 1
end

# ════════════════════════════════════════════
# Internal: Render code block
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_code(slot, pos, text, size)
  off = slot * 4096
  cs = KUIMDState.d[off + pos + 1]
  cl = KUIMDState.d[off + pos + 2]
  content = text.byteslice(cs, cl)
  code_size = size - 2
  if code_size < 10
    code_size = 10
  end

  id = kui_auto_id
  _kui_open_i("_mdc", id)
  _kui_layout(1, 8, 8, 6, 6, 0, 1, 0, 0, 0, 0, 0)
  _kui_set_bg(KUITheme.c[38], KUITheme.c[39], KUITheme.c[40])
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
  _kui_text_color(content, code_size, KUITheme.c[32], KUITheme.c[33], KUITheme.c[34])
  _kui_close

  return pos + 4 # skip CODE_START(4) + start + len + CODE_END(5)
end

# ════════════════════════════════════════════
# Internal: Render bullet list item
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_bullet(slot, pos, text, size)
  off = slot * 4096
  indent = KUIMDState.d[off + pos + 1]
  ts = KUIMDState.d[off + pos + 2]
  tl = KUIMDState.d[off + pos + 3]
  content = text.byteslice(ts, tl)

  pad_left = indent * 12

  id = kui_auto_id
  _kui_open_i("_mdb", id)
  _kui_layout(0, pad_left, 0, 1, 1, 4, 1, 0, 0, 0, 0, 0)
  _kui_text_color("*", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  _kui_text(content, size)
  _kui_close

  return pos + 4
end

# ════════════════════════════════════════════
# Internal: Render numbered list item
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_numbered(slot, pos, text, size)
  off = slot * 4096
  num = KUIMDState.d[off + pos + 1]
  indent = KUIMDState.d[off + pos + 2]
  ts = KUIMDState.d[off + pos + 3]
  tl = KUIMDState.d[off + pos + 4]
  content = text.byteslice(ts, tl)

  pad_left = indent * 12

  id = kui_auto_id
  _kui_open_i("_mdn", id)
  _kui_layout(0, pad_left, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0)
  _kui_draw_num(num, size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  _kui_text_color(". ", size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  _kui_text(content, size)
  _kui_close

  return pos + 5
end

# ════════════════════════════════════════════
# Internal: Render blockquote start
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_bq_start(slot, pos, text, size)
  off = slot * 4096
  depth = KUIMDState.d[off + pos + 1]
  pad_left = depth * 8

  id = kui_auto_id
  _kui_open_i("_mdq", id)
  _kui_layout(0, pad_left, 0, 4, 4, 0, 1, 0, 0, 0, 0, 0)

  # left border bar
  id2 = kui_auto_id
  _kui_open_i("_mdql", id2)
  _kui_layout(0, 0, 0, 0, 0, 0, 2, 3, 1, 0, 0, 0)
  _kui_set_bg(KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
  _kui_close

  # content area
  id3 = kui_auto_id
  _kui_open_i("_mdqc", id3)
  _kui_layout(1, 8, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0)

  return pos + 2
end

# ════════════════════════════════════════════
# Internal: Render blockquote end
# ════════════════════════════════════════════

#: (Integer slot, Integer pos) -> Integer
def _md_render_bq_end(slot, pos)
  _kui_close # content area
  _kui_close # outer hpanel
  return pos + 1
end

# ════════════════════════════════════════════
# Internal: Render HR
# ════════════════════════════════════════════

#: (Integer slot, Integer pos) -> Integer
def _md_render_hr(slot, pos)
  divider
  return pos + 1
end

# ════════════════════════════════════════════
# Internal: Render table start
# ════════════════════════════════════════════

#: (Integer slot, Integer pos) -> Integer
def _md_render_table_start(slot, pos)
  off = slot * 4096
  # cols at pos+1, but we don't need it here
  return pos + 2
end

# ════════════════════════════════════════════
# Internal: Render table row
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_table_row_emit(slot, pos, text, size)
  off = slot * 4096
  cols = KUIMDState.d[off + pos + 1]

  id = kui_auto_id
  _kui_open_i("_mdt", id)
  _kui_layout(0, 2, 2, 2, 2, 0, 1, 0, 0, 0, 0, 2)
  _kui_set_border(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])

  ci = 0
  dp = pos + 2
  while ci < cols
    cs = KUIMDState.d[off + dp]
    cl = KUIMDState.d[off + dp + 1]
    cell_text = text.byteslice(cs, cl)

    id2 = kui_auto_id
    _kui_open_i("_mdtc", id2)
    _kui_layout(0, 6, 6, 2, 2, 0, 1, 0, 0, 0, 0, 2)
    _kui_text(cell_text, size)
    _kui_close

    if ci + 1 < cols
      # cell separator
      id3 = kui_auto_id
      _kui_open_i("_mdts", id3)
      _kui_layout(0, 0, 0, 0, 0, 0, 2, 1, 1, 0, 0, 0)
      _kui_set_bg(KUITheme.c[12], KUITheme.c[13], KUITheme.c[14])
      _kui_close
    end

    dp = dp + 2
    ci = ci + 1
  end

  _kui_close
  return dp
end

# ════════════════════════════════════════════
# Internal: Render table end
# ════════════════════════════════════════════

#: (Integer slot, Integer pos) -> Integer
def _md_render_table_end(slot, pos)
  return pos + 1
end

# ════════════════════════════════════════════
# Internal: Render task list item
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_task(slot, pos, text, size)
  off = slot * 4096
  checked = KUIMDState.d[off + pos + 1]
  indent = KUIMDState.d[off + pos + 2]
  ts = KUIMDState.d[off + pos + 3]
  tl = KUIMDState.d[off + pos + 4]
  content = text.byteslice(ts, tl)

  pad_left = indent * 12

  id = kui_auto_id
  _kui_open_i("_mdtk", id)
  _kui_layout(0, pad_left, 0, 1, 1, 4, 1, 0, 0, 0, 0, 0)
  if checked == 1
    _kui_text_color("[x]", size, KUITheme.c[24], KUITheme.c[25], KUITheme.c[26])
    _kui_text_color(" ", size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
    _kui_text_color(content, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
  else
    _kui_text_color("[ ]", size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
    _kui_text_color(" ", size, KUITheme.c[3], KUITheme.c[4], KUITheme.c[5])
    _kui_text(content, size)
  end
  _kui_close

  return pos + 5
end

# ════════════════════════════════════════════
# Internal: Render image placeholder
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_image(slot, pos, text, size)
  off = slot * 4096
  as = KUIMDState.d[off + pos + 1]
  al = KUIMDState.d[off + pos + 2]
  alt = text.byteslice(as, al)

  badge(alt, size: size - 2,
    r: KUITheme.c[32], g: KUITheme.c[33], b: KUITheme.c[34])

  return pos + 3
end

# ════════════════════════════════════════════
# Internal: Render inline element
# ════════════════════════════════════════════

#: (Integer slot, Integer pos, String text, Integer size) -> Integer
def _md_render_inline(slot, pos, text, size)
  off = slot * 4096
  op = KUIMDState.d[off + pos]

  if op == 20
    # TEXT — theme fg
    ts = KUIMDState.d[off + pos + 1]
    tl = KUIMDState.d[off + pos + 2]
    content = text.byteslice(ts, tl)
    _kui_text(content, size)
    return pos + 3
  end

  if op == 21
    # BOLD — bright white (dark) / black (light)
    ts = KUIMDState.d[off + pos + 1]
    tl = KUIMDState.d[off + pos + 2]
    content = text.byteslice(ts, tl)
    _kui_text_color(content, size, 255, 255, 255)
    return pos + 3
  end

  if op == 22
    # ITALIC — muted color
    ts = KUIMDState.d[off + pos + 1]
    tl = KUIMDState.d[off + pos + 2]
    content = text.byteslice(ts, tl)
    _kui_text_color(content, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
    return pos + 3
  end

  if op == 23
    # STRIKE — muted with ~~ decoration
    ts = KUIMDState.d[off + pos + 1]
    tl = KUIMDState.d[off + pos + 2]
    content = text.byteslice(ts, tl)
    _kui_text_color(content, size, KUITheme.c[21], KUITheme.c[22], KUITheme.c[23])
    return pos + 3
  end

  if op == 24
    # CODE_INLINE — surface2 bg + info color text
    ts = KUIMDState.d[off + pos + 1]
    tl = KUIMDState.d[off + pos + 2]
    content = text.byteslice(ts, tl)
    id = kui_auto_id
    _kui_open_i("_mdic", id)
    _kui_layout(0, 4, 4, 1, 1, 0, 0, 0, 0, 0, 0, 2)
    _kui_set_bg(KUITheme.c[38], KUITheme.c[39], KUITheme.c[40])
    _kui_text_color(content, size - 1, KUITheme.c[32], KUITheme.c[33], KUITheme.c[34])
    _kui_close
    return pos + 3
  end

  if op == 25
    # LINK — primary color (text only, url not rendered)
    ts = KUIMDState.d[off + pos + 1]
    tl = KUIMDState.d[off + pos + 2]
    content = text.byteslice(ts, tl)
    _kui_text_color(content, size, KUITheme.c[6], KUITheme.c[7], KUITheme.c[8])
    return pos + 5
  end

  if op == 26
    # BOLD_ITALIC — secondary color
    ts = KUIMDState.d[off + pos + 1]
    tl = KUIMDState.d[off + pos + 2]
    content = text.byteslice(ts, tl)
    _kui_text_color(content, size, KUITheme.c[9], KUITheme.c[10], KUITheme.c[11])
    return pos + 3
  end

  # unknown inline — skip 3
  return pos + 3
end

# ════════════════════════════════════════════
# Public API — Convenience
# ════════════════════════════════════════════

# Render Markdown text. Parses on change, renders every frame.
#: (String text, Integer size) -> Integer
def markdown(text, size: 16)
  md_parse(0, text)
  md_render(0, text, size: size)
  return 0
end
