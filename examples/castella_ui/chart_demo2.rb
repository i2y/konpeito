# Castella UI - Chart Gallery 2
#
# Demonstrates: ScatterChart, AreaChart, StackedBarChart, GaugeChart, HeatmapChart
# Run: cd examples/castella_ui && bash run.sh chart_demo2.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

class ChartDemo2 < Component
  def view
    # Scatter data
    sc_x1 = [1.0, 2.5, 3.0, 4.5, 5.0, 6.5, 7.0, 8.0]
    sc_y1 = [2.0, 4.0, 3.5, 7.0, 5.5, 8.0, 6.0, 9.0]
    sc_x2 = [1.5, 3.0, 4.0, 5.5, 6.0, 7.5, 8.5, 9.0]
    sc_y2 = [1.0, 3.0, 2.5, 4.0, 6.0, 5.0, 7.5, 8.5]

    # Area data
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    revenue = [120.0, 180.0, 150.0, 220.0, 280.0, 250.0]
    expenses = [80.0, 100.0, 90.0, 130.0, 150.0, 140.0]

    # Stacked bar data
    quarters = ["Q1", "Q2", "Q3", "Q4"]
    product_a = [30.0, 40.0, 35.0, 50.0]
    product_b = [20.0, 25.0, 30.0, 35.0]
    product_c = [15.0, 20.0, 25.0, 20.0]

    # Heatmap data (5x5)
    hm_x = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    hm_y = ["9am", "12pm", "3pm", "6pm"]
    hm_data = [
      [2.0, 5.0, 8.0, 4.0, 3.0],
      [6.0, 9.0, 7.0, 5.0, 4.0],
      [3.0, 4.0, 6.0, 8.0, 7.0],
      [1.0, 2.0, 3.0, 6.0, 9.0]
    ]

    Column(
      Text("Chart Gallery 2").font_size(22.0).color(0xFFC0CAF5).bold,
      Divider(),

      # Scatter Chart
      ScatterChart([sc_x1, sc_x2], [sc_y1, sc_y2], ["Series A", "Series B"])
        .title("Scatter Plot")
        .fixed_height(300.0),
      Divider(),

      # Area Chart
      AreaChart(months, [revenue, expenses], ["Revenue", "Expenses"])
        .title("Revenue vs Expenses")
        .fixed_height(300.0),
      Divider(),

      # Stacked Bar Chart
      StackedBarChart(quarters, [product_a, product_b, product_c], ["Product A", "Product B", "Product C"])
        .title("Quarterly Sales (Stacked)")
        .show_values(true)
        .fixed_height(300.0),
      Divider(),

      # Gauge Charts
      Row(
        GaugeChart(72.0, 0.0, 100.0)
          .title("CPU Usage")
          .unit("%")
          .thresholds([[0.5, 0xFF9ECE6A], [0.75, 0xFFE0AF68], [1.0, 0xFFF7768E]])
          .fixed_height(250.0),
        GaugeChart(3.8, 0.0, 5.0)
          .title("Rating")
          .thresholds([[0.4, 0xFFF7768E], [0.7, 0xFFE0AF68], [1.0, 0xFF9ECE6A]])
          .fixed_height(250.0)
      ).spacing(8.0).fixed_height(260.0),
      Divider(),

      # Heatmap
      HeatmapChart(hm_x, hm_y, hm_data)
        .title("Activity Heatmap")
        .margins(40.0, 60.0, 50.0, 60.0)
        .fixed_height(280.0)
    ).spacing(12.0).scrollable
  end
end

frame = JWMFrame.new("Chart Gallery 2", 800, 900)
app = App.new(frame, ChartDemo2.new)
app.run
