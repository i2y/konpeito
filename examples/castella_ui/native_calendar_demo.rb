# Castella UI - Calendar Widget Demo (NativeFrame / SDL3 + Skia Metal)
#
# Same as calendar_demo.rb but uses NativeFrame instead of JWMFrame.
# Demonstrates: Calendar with day/month/year views, date selection
# Run: ruby examples/castella_ui/native_calendar_demo.rb

require_relative "../../lib/konpeito/ui/castella_native"

$theme = Theme.new

class CalendarDemo < Component
  def initialize
    super()
    @cal_state = CalendarState.new(2026, 2, 15)
    @date_label = State.new("February 15")
    @cal_state.attach(self)
  end

  def on_attach(observable)
  end

  def on_detach(observable)
  end

  def on_notify
    label = @cal_state.formatted_date
    @date_label.set(label)
    @pending_rebuild = true
    mark_paint_dirty
    a = App.current
    if a != nil
      a.post_update(self)
    end
  end

  def view
    cs = @cal_state
    Column(
      Text("Calendar Demo").font_size(22.0).color(0xFFC0CAF5).bold,
      Divider(),
      Row(
        Text("Selected: ").font_size(14.0),
        Text(@date_label.value).font_size(14.0).color(0xFF7AA2F7)
      ).spacing(4.0).fixed_height(28.0),
      Spacer().fixed_height(8.0),
      Row(
        Spacer(),
        Calendar(cs),
        Spacer()
      ).fixed_height(310.0),
      Spacer()
    ).spacing(8.0)
  end
end

frame = NativeFrame.new("Calendar Demo", 500, 480)
app = App.new(frame, CalendarDemo.new)
app.run
