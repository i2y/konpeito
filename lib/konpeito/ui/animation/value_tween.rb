# ValueTween - interpolates between two numeric values over a duration
# Frame-based: call tick(dt) each frame to advance

class ValueTween
  def initialize(from_val, to_val, duration, easing_fn)
    @from_val = from_val
    @to_val = to_val
    @duration = duration      # milliseconds
    @easing_fn = easing_fn    # Symbol: :linear, :ease_in, etc.
    @elapsed = 0.0
    @current = from_val
    @finished = false
  end

  def tick(dt)
    return if @finished
    @elapsed = @elapsed + dt
    if @elapsed >= @duration
      @elapsed = @duration
      @finished = true
    end
    t = @elapsed / @duration
    eased = apply_easing(t)
    @current = @from_val + (@to_val - @from_val) * eased
  end

  def current
    @current
  end

  def finished?
    @finished
  end

  def reset(from_val, to_val)
    @from_val = from_val
    @to_val = to_val
    @elapsed = 0.0
    @current = from_val
    @finished = false
  end

  private

  def apply_easing(t)
    if @easing_fn == :linear
      Easing.linear(t)
    elsif @easing_fn == :ease_in
      Easing.ease_in(t)
    elsif @easing_fn == :ease_out
      Easing.ease_out(t)
    elsif @easing_fn == :ease_in_out
      Easing.ease_in_out(t)
    elsif @easing_fn == :ease_in_cubic
      Easing.ease_in_cubic(t)
    elsif @easing_fn == :ease_out_cubic
      Easing.ease_out_cubic(t)
    elsif @easing_fn == :ease_in_out_cubic
      Easing.ease_in_out_cubic(t)
    elsif @easing_fn == :bounce
      Easing.bounce(t)
    else
      t
    end
  end
end
