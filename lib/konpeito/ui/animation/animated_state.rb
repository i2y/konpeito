# AnimatedState - observable value that transitions smoothly
# Inherits from ObservableBase so Components can subscribe

class AnimatedState < ObservableBase
  def initialize(initial_value, duration, easing_fn)
    super()
    @value = initial_value
    @target = initial_value
    @duration = duration        # milliseconds
    @easing_fn = easing_fn      # Symbol
    @tween = nil
    @animating = false
  end

  def value
    @value
  end

  def target
    @target
  end

  def animating?
    @animating
  end

  # Set a new target — begins animation from current value
  def set(new_target)
    if new_target == @target && !@animating
      return
    end
    @target = new_target
    @tween = ValueTween.new(@value, @target, @duration, @easing_fn)
    @animating = true
    # Register with App's animation loop
    app = App.current
    if app != nil
      app.register_animation(self)
    end
  end

  # Immediately jump to a value (no animation)
  def set_immediate(new_value)
    @value = new_value
    @target = new_value
    @tween = nil
    @animating = false
    notify_observers
  end

  # Call each frame with delta time in ms
  def tick(dt)
    return false if !@animating || @tween == nil
    @tween.tick(dt)
    @value = @tween.current
    if @tween.finished?
      @value = @target
      @animating = false
      @tween = nil
    end
    notify_observers
    @animating
  end

  def duration
    @duration
  end

  def duration=(d)
    @duration = d
  end

  def easing_fn
    @easing_fn
  end

  def easing_fn=(e)
    @easing_fn = e
  end
end
