# Castella UI - Calculator Demo (DSL style)
#
# Port of Python Castella's examples/calc.py using block-based DSL.
# Demonstrates:
# - Nested column/row layout
# - Button kinds (DANGER, WARNING, SUCCESS, INFO)
# - flex: for variable-width buttons
# - Reactive State with string display
#
# Run: cd examples/castella_ui && bash run.sh calc.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

class Calc < Component
  def initialize
    super
    @display = state("0")
    @lhs = 0.0
    @current_op = ""
    @is_refresh = true
  end

  # --- Calculator logic ---

  def press_number(label)
    if @display.value == "0" || @is_refresh
      @display.set(label)
    else
      @display.set(@display.value + label)
    end
    @is_refresh = false
  end

  def press_dot
    if @is_refresh
      @display.set("0.")
      @is_refresh = false
      return
    end
    if !@display.value.include?(".")
      @display.set(@display.value + ".")
    end
  end

  def all_clear
    @display.set("0")
    @lhs = 0.0
    @current_op = ""
    @is_refresh = true
  end

  def do_calc(lhs, op, rhs)
    if op == "+"
      lhs + rhs
    elsif op == "-"
      lhs - rhs
    elsif op == "\u00D7"
      lhs * rhs
    elsif op == "\u00F7"
      if rhs == 0.0
        0.0
      else
        lhs / rhs
      end
    else
      rhs
    end
  end

  def format_result(val)
    if val == val.to_i.to_f
      val.to_i.to_s
    else
      val.to_s
    end
  end

  def press_operator(new_op)
    rhs = @display.value.to_f
    if @current_op != ""
      result = do_calc(@lhs, @current_op, rhs)
      @display.set(format_result(result))
      @lhs = result
    else
      @lhs = rhs
    end
    if new_op == "="
      @current_op = ""
    else
      @current_op = new_op
    end
    @is_refresh = true
  end

  # --- View ---

  def view
    # Shared styles
    grid = Style.new.spacing(4.0)
    btn = Style.new.font_size(32.0)
    op = btn + Style.new.kind(KIND_WARNING)
    ac = btn + Style.new.kind(KIND_DANGER).flex(3)
    eq = btn + Style.new.kind(KIND_SUCCESS)
    wide = btn + Style.new.flex(2)

    column(spacing: 4.0, padding: 4.0) {
      text @display.value, font_size: 48.0, align: :right, kind: KIND_INFO, height: 72.0

      row(grid) {
        button("AC", ac) { all_clear }
        button("\u00F7", op) { press_operator("\u00F7") }
      }
      row(grid) {
        button("7", btn) { press_number("7") }
        button("8", btn) { press_number("8") }
        button("9", btn) { press_number("9") }
        button("\u00D7", op) { press_operator("\u00D7") }
      }
      row(grid) {
        button("4", btn) { press_number("4") }
        button("5", btn) { press_number("5") }
        button("6", btn) { press_number("6") }
        button("-", op) { press_operator("-") }
      }
      row(grid) {
        button("1", btn) { press_number("1") }
        button("2", btn) { press_number("2") }
        button("3", btn) { press_number("3") }
        button("+", op) { press_operator("+") }
      }
      row(grid) {
        button("0", wide) { press_number("0") }
        button(".", btn) { press_dot }
        button("=", eq) { press_operator("=") }
      }
    }
  end
end

# ===== Launch =====
frame = JWMFrame.new("Castella Calculator", 320, 480)
app = App.new(frame, Calc.new)
app.run
