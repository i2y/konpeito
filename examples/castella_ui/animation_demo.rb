# Castella UI - Animation Demo
#
# Demonstrates the animation system with various easing functions
# Run: cd examples/castella_ui && bash run.sh animation_demo.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

# A simple animated bar that shows animation value
class AnimatedBar < Widget
  def initialize(anim_state, label, color)
    super()
    @anim = anim_state
    @label = label
    @color = color
    @width_policy = EXPANDING
    @height_policy = FIXED
    @height = 30.0
    @anim.attach(self)
  end

  def on_attach(observable)
  end

  def on_detach(observable)
  end

  def on_notify
    mark_dirty
    update
  end

  def redraw(painter, completely)
    # Background track
    painter.fill_round_rect(0.0, 4.0, @width, 22.0, 4.0, $theme.bg_secondary)
    # Animated fill
    fill_w = (@anim.value / 100.0) * @width
    if fill_w > @width
      fill_w = @width
    end
    if fill_w > 0.0
      painter.fill_round_rect(0.0, 4.0, fill_w, 22.0, 4.0, @color)
    end
    # Label
    ascent = painter.get_text_ascent("default", 11.0)
    painter.draw_text(@label, 8.0, 4.0 + 11.0 + ascent / 2.0, "default", 11.0, 0xFFFFFFFF)
    # Value
    val_text = painter.number_to_string(@anim.value) + "%"
    vw = painter.measure_text_width(val_text, "default", 11.0)
    painter.draw_text(val_text, @width - vw - 8.0, 4.0 + 11.0 + ascent / 2.0, "default", 11.0, 0xFFFFFFFF)
  end
end

class AnimationDemo < Component
  def initialize
    super
    @linear = AnimatedState.new(0.0, 1000.0, :linear)
    @ease_in = AnimatedState.new(0.0, 1000.0, :ease_in)
    @ease_out = AnimatedState.new(0.0, 1000.0, :ease_out)
    @ease_in_out = AnimatedState.new(0.0, 1000.0, :ease_in_out)
    @cubic_in = AnimatedState.new(0.0, 1000.0, :ease_in_cubic)
    @cubic_out = AnimatedState.new(0.0, 1000.0, :ease_out_cubic)
    @bounce_anim = AnimatedState.new(0.0, 1500.0, :bounce)
    @toggled = false
  end

  def view
    Column(
      Text("Animation Demo").font_size(20.0).color(0xFFC0CAF5).bold,
      Text("Click the button to animate all bars").font_size(12.0).color($theme.text_secondary),
      Divider(),
      Button("Animate!").on_click {
        if @toggled
          @linear.set(0.0)
          @ease_in.set(0.0)
          @ease_out.set(0.0)
          @ease_in_out.set(0.0)
          @cubic_in.set(0.0)
          @cubic_out.set(0.0)
          @bounce_anim.set(0.0)
        else
          @linear.set(100.0)
          @ease_in.set(100.0)
          @ease_out.set(100.0)
          @ease_in_out.set(100.0)
          @cubic_in.set(100.0)
          @cubic_out.set(100.0)
          @bounce_anim.set(100.0)
        end
        @toggled = !@toggled
      },
      Spacer().fixed_height(12.0),
      AnimatedBar.new(@linear, "Linear", 0xFF7AA2F7),
      AnimatedBar.new(@ease_in, "Ease In", 0xFF9ECE6A),
      AnimatedBar.new(@ease_out, "Ease Out", 0xFFF7768E),
      AnimatedBar.new(@ease_in_out, "Ease In/Out", 0xFFE0AF68),
      AnimatedBar.new(@cubic_in, "Cubic In", 0xFFBB9AF7),
      AnimatedBar.new(@cubic_out, "Cubic Out", 0xFF73DACA),
      AnimatedBar.new(@bounce_anim, "Bounce", 0xFFFF9E64)
    ).spacing(8.0)
  end
end

frame = JWMFrame.new("Animation Demo", 600, 500)
app = App.new(frame, AnimationDemo.new)
app.run
