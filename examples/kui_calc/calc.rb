# KUI Calculator — Castella-UI style
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_calc/calc \
#     examples/kui_calc/calc.rb
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

# ── Operator constants ──
OP_NONE = 0
OP_ADD  = 1
OP_SUB  = 2
OP_MUL  = 3
OP_DIV  = 4

# ── Frac mode constants ──
FRAC_INT   = 0  # integer input
FRAC_DOT   = 1  # dot pressed, no digit yet
FRAC_ONE   = 2  # 1st decimal digit entered
FRAC_TWO   = 3  # 2nd decimal digit entered

# ── Global state ──
$int_part  = 0
$frac_part = 0
$frac_mode = FRAC_INT
$stored    = 0
$operator  = OP_NONE
$new_input = 0
$negative  = 0

# ════════════════════════════════════════════
# Fixed-point helpers (x100)
# ════════════════════════════════════════════

#: () -> Integer
def display_to_val
  v = $int_part * 100 + $frac_part
  if $negative == 1
    v = 0 - v
  end
  return v
end

#: (Integer v) -> Integer
def val_to_display(v)
  if v < 0
    $negative = 1
    v = 0 - v
  else
    $negative = 0
  end
  $int_part = v / 100
  $frac_part = v % 100
  if $frac_part > 0
    $frac_mode = FRAC_TWO
  else
    $frac_mode = FRAC_INT
  end
  return 0
end

# ════════════════════════════════════════════
# Input handlers
# ════════════════════════════════════════════

#: () -> Integer
def reset_if_new_input
  if $new_input == 1
    $int_part = 0
    $frac_part = 0
    $frac_mode = FRAC_INT
    $new_input = 0
    $negative = 0
  end
  return 0
end

#: (Integer n) -> Integer
def press_number(n)
  reset_if_new_input
  case $frac_mode
  when FRAC_INT
    $int_part = $int_part * 10 + n
  when FRAC_DOT
    $frac_part = n * 10
    $frac_mode = FRAC_ONE
  when FRAC_ONE
    $frac_part = $frac_part + n
    $frac_mode = FRAC_TWO
  end
  return 0
end

#: () -> Integer
def press_dot
  reset_if_new_input
  if $frac_mode == FRAC_INT
    $frac_mode = FRAC_DOT
  end
  return 0
end

#: () -> Integer
def calc_apply
  a = $stored
  b = display_to_val
  case $operator
  when OP_ADD
    val_to_display(a + b)
  when OP_SUB
    val_to_display(a - b)
  when OP_MUL
    val_to_display(a * b / 100)
  when OP_DIV
    if b != 0
      val_to_display(a * 100 / b)
    else
      val_to_display(0)
    end
  else
    val_to_display(b)
  end
  return 0
end

#: (Integer op) -> Integer
def press_operator(op)
  calc_apply
  $stored = display_to_val
  $operator = op
  $new_input = 1
  return 0
end

#: () -> Integer
def press_equals
  calc_apply
  $operator = OP_NONE
  $new_input = 1
  return 0
end

#: () -> Integer
def all_clear
  $int_part = 0
  $frac_part = 0
  $frac_mode = FRAC_INT
  $stored = 0
  $operator = OP_NONE
  $new_input = 0
  $negative = 0
  return 0
end

# ════════════════════════════════════════════
# Display rendering
# ════════════════════════════════════════════

#: () -> Integer
def draw_display_value
  if $negative == 1
    label "-", size: 40, r: 255, g: 255, b: 255
  end
  label_num $int_part, size: 40, r: 255, g: 255, b: 255
  if $frac_mode > FRAC_INT
    label ".", size: 40, r: 255, g: 255, b: 255
    if $frac_mode >= FRAC_ONE
      if $frac_part < 10
        label "0", size: 40, r: 255, g: 255, b: 255
      end
      label_num $frac_part, size: 40, r: 255, g: 255, b: 255
    end
  end
  return 0
end

# ════════════════════════════════════════════
# View
# ════════════════════════════════════════════

#: () -> Integer
def draw
  # Styles
  btn  = kui_style(size: 32, flex: 25)
  op   = kui_style_merge(btn, kui_style(kind: KUI_KIND_WARNING))
  ac   = kui_style_merge(btn, kui_style(kind: KUI_KIND_DANGER, flex: 75))
  eq   = kui_style_merge(btn, kui_style(kind: KUI_KIND_SUCCESS))
  wide = kui_style_merge(btn, kui_style(flex: 50))

  vpanel pad: 4, gap: 4 do
    # Display
    pct_panel 100, pad: 12 do
      kui_bg_surface2
      spacer
      hpanel gap: 0 do
        spacer
        draw_display_value
      end
      spacer
    end

    row gap: 4 do
      button "AC", style: ac do all_clear end
      button "/", style: op do press_operator(OP_DIV) end
    end

    row gap: 4 do
      button "7", style: btn do press_number(7) end
      button "8", style: btn do press_number(8) end
      button "9", style: btn do press_number(9) end
      button "x", style: op do press_operator(OP_MUL) end
    end

    row gap: 4 do
      button "4", style: btn do press_number(4) end
      button "5", style: btn do press_number(5) end
      button "6", style: btn do press_number(6) end
      button "-", style: op do press_operator(OP_SUB) end
    end

    row gap: 4 do
      button "1", style: btn do press_number(1) end
      button "2", style: btn do press_number(2) end
      button "3", style: btn do press_number(3) end
      button "+", style: op do press_operator(OP_ADD) end
    end

    row gap: 4 do
      button "0", style: wide do press_number(0) end
      button ".", style: btn do press_dot end
      button "=", style: eq do press_equals end
    end
  end
  return 0
end

# ════════════════════════════════════════════
# Main
# ════════════════════════════════════════════

#: () -> Integer
def main
  all_clear
  kui_init("Calculator", 320, 480)
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 48)
  kui_theme_dark
  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end
  kui_destroy
  return 0
end

main
