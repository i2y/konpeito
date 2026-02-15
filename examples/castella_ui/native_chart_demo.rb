# Castella UI - Chart Demo (NativeFrame / SDL3 + Skia Metal)
#
# Same as chart_demo.rb but uses NativeFrame instead of JWMFrame.
# Demonstrates all chart types: BarChart, LineChart, PieChart
# Run: ruby examples/castella_ui/native_chart_demo.rb

require_relative "../../lib/konpeito/ui/castella_native"

$theme = Theme.new

class ChartDemo < Component
  def view
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    sales = [120.0, 200.0, 150.0, 300.0, 250.0, 180.0]
    costs = [80.0, 120.0, 100.0, 180.0, 160.0, 140.0]

    labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    temp = [5.0, 7.0, 12.0, 18.0, 22.0, 26.0]
    rain = [40.0, 35.0, 45.0, 30.0, 25.0, 20.0]

    pie_labels = ["Engineering", "Design", "Marketing", "Sales", "Operations"]
    pie_values = [35.0, 20.0, 18.0, 15.0, 12.0]

    Column(
      Text("Chart Gallery").font_size(22.0).color(0xFFC0CAF5).bold,
      Divider(),

      # Bar Chart
      BarChart(months, [sales, costs], ["Sales", "Costs"])
        .title("Monthly Sales vs Costs")
        .show_values(true)
        .fixed_height(300.0),
      Divider(),

      # Line Chart
      LineChart(labels, [temp, rain], ["Temperature (C)", "Rainfall (mm)"])
        .title("Weather Trends")
        .fixed_height(300.0),
      Divider(),

      # Pie Chart
      Row(
        PieChart(pie_labels, pie_values)
          .title("Department Budget")
          .fixed_height(300.0),
        PieChart(pie_labels, pie_values)
          .title("Donut View")
          .donut(true)
          .fixed_height(300.0)
      ).spacing(8.0).fixed_height(320.0)
    ).spacing(12.0).scrollable
  end
end

frame = NativeFrame.new("Chart Demo", 800, 800)
app = App.new(frame, ChartDemo.new)
app.run
