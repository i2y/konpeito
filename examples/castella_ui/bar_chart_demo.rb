# Castella UI - Bar Chart Demo
#
# Run: cd examples/castella_ui && bash run.sh bar_chart_demo.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

class BarChartDemo < Component
  def view
    categories = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    sales = [120.0, 200.0, 150.0, 300.0, 250.0, 180.0]
    costs = [80.0, 120.0, 100.0, 180.0, 160.0, 140.0]

    Column(
      Text("Bar Chart Demo").font_size(20.0).color(0xFFC0CAF5),
      Divider(),
      BarChart(categories, [sales, costs], ["Sales", "Costs"])
        .title("Monthly Performance")
        .show_values(true)
        .fixed_height(350.0),
      Divider(),
      BarChart(categories, [sales], ["Revenue"])
        .title("Single Series")
        .fixed_height(250.0)
    ).spacing(12.0).scrollable
  end
end

frame = JWMFrame.new("Bar Chart Demo", 700, 700)
app = App.new(frame, BarChartDemo.new)
app.run
