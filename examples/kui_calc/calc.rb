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

# ── State slot constants ──
INT_PART  = 0   # display integer (absolute)
FRAC_PART = 1   # display fraction (0-99)
FRAC_MODE = 2   # 0=int, 1=dot, 2=1st frac digit, 3=2nd
STORED    = 3   # stored value (x100, signed)
OPERATOR  = 4   # 0=none, 1=+, 2=-, 3=*, 4=/
NEW_INPUT = 5   # 1 = next digit starts fresh
NEGATIVE  = 6   # 1 = display is negative

# ════════════════════════════════════════════
# Fixed-point helpers (x100)
# ════════════════════════════════════════════

#: () -> Integer
def display_to_val
  v = Calc.s[INT_PART] * 100 + Calc.s[FRAC_PART]
  if Calc.s[NEGATIVE] == 1
    v = 0 - v
  end
  return v
end

#: (Integer v) -> Integer
def val_to_display(v)
  if v < 0
    Calc.s[NEGATIVE] = 1
    v = 0 - v
  else
    Calc.s[NEGATIVE] = 0
  end
  Calc.s[INT_PART] = v / 100
  Calc.s[FRAC_PART] = v % 100
  if Calc.s[FRAC_PART] > 0
    Calc.s[FRAC_MODE] = 3
  else
    Calc.s[FRAC_MODE] = 0
  end
  return 0
end

# ════════════════════════════════════════════
# Input handlers
# ════════════════════════════════════════════

#: (Integer n) -> Integer
def press_number(n)
  if Calc.s[NEW_INPUT] == 1
    Calc.s[INT_PART] = 0
    Calc.s[FRAC_PART] = 0
    Calc.s[FRAC_MODE] = 0
    Calc.s[NEW_INPUT] = 0
    Calc.s[NEGATIVE] = 0
  end
  fm = Calc.s[FRAC_MODE]
  if fm == 0
    Calc.s[INT_PART] = Calc.s[INT_PART] * 10 + n
  end
  if fm == 1
    Calc.s[FRAC_PART] = n * 10
    Calc.s[FRAC_MODE] = 2
  end
  if fm == 2
    Calc.s[FRAC_PART] = Calc.s[FRAC_PART] + n
    Calc.s[FRAC_MODE] = 3
  end
  return 0
end

#: () -> Integer
def press_dot
  if Calc.s[NEW_INPUT] == 1
    Calc.s[INT_PART] = 0
    Calc.s[FRAC_PART] = 0
    Calc.s[NEW_INPUT] = 0
    Calc.s[NEGATIVE] = 0
  end
  if Calc.s[FRAC_MODE] == 0
    Calc.s[FRAC_MODE] = 1
  end
  return 0
end

#: () -> Integer
def calc_apply
  op = Calc.s[OPERATOR]
  a = Calc.s[STORED]
  b = display_to_val
  if op == 1
    val_to_display(a + b)
  end
  if op == 2
    val_to_display(a - b)
  end
  if op == 3
    val_to_display(a * b / 100)
  end
  if op == 4
    if b != 0
      val_to_display(a * 100 / b)
    else
      val_to_display(0)
    end
  end
  if op == 0
    val_to_display(b)
  end
  return 0
end

#: (Integer op) -> Integer
def press_operator(op)
  calc_apply
  Calc.s[STORED] = display_to_val
  Calc.s[OPERATOR] = op
  Calc.s[NEW_INPUT] = 1
  return 0
end

#: () -> Integer
def press_equals
  calc_apply
  Calc.s[OPERATOR] = 0
  Calc.s[NEW_INPUT] = 1
  return 0
end

#: () -> Integer
def all_clear
  Calc.s[INT_PART] = 0
  Calc.s[FRAC_PART] = 0
  Calc.s[FRAC_MODE] = 0
  Calc.s[STORED] = 0
  Calc.s[OPERATOR] = 0
  Calc.s[NEW_INPUT] = 0
  Calc.s[NEGATIVE] = 0
  return 0
end

# ════════════════════════════════════════════
# Display rendering
# ════════════════════════════════════════════

#: () -> Integer
def draw_display_value
  if Calc.s[NEGATIVE] == 1
    label "-", size: 40, r: 255, g: 255, b: 255
  end
  label_num Calc.s[INT_PART], size: 40, r: 255, g: 255, b: 255
  if Calc.s[FRAC_MODE] > 0
    label ".", size: 40, r: 255, g: 255, b: 255
    if Calc.s[FRAC_MODE] >= 2
      frac = Calc.s[FRAC_PART]
      if frac < 10
        label "0", size: 40, r: 255, g: 255, b: 255
      end
      label_num frac, size: 40, r: 255, g: 255, b: 255
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
      button "/", style: op do press_operator(4) end
    end

    row gap: 4 do
      button "7", style: btn do press_number(7) end
      button "8", style: btn do press_number(8) end
      button "9", style: btn do press_number(9) end
      button "x", style: op do press_operator(3) end
    end

    row gap: 4 do
      button "4", style: btn do press_number(4) end
      button "5", style: btn do press_number(5) end
      button "6", style: btn do press_number(6) end
      button "-", style: op do press_operator(2) end
    end

    row gap: 4 do
      button "1", style: btn do press_number(1) end
      button "2", style: btn do press_number(2) end
      button "3", style: btn do press_number(3) end
      button "+", style: op do press_operator(1) end
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
