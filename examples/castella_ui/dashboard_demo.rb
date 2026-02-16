require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

class Dashboard < Component
  def initialize
    super
  end

  def view
    table_headers = ["Customer", "Product", "Amount", "Status"]
    table_widths = [120.0, 130.0, 80.0, 80.0]
    table_rows = [
      ["Alice Chen", "Pro Plan", "$299", "Paid"],
      ["Bob Smith", "Team Plan", "$599", "Paid"],
      ["Carol Wu", "Enterprise", "$1,200", "Pending"],
      ["Dan Lee", "Pro Plan", "$299", "Paid"],
      ["Eve Park", "Team Plan", "$599", "Refund"],
      ["Frank Kim", "Pro Plan", "$299", "Paid"],
      ["Grace Li", "Enterprise", "$1,200", "Pending"],
      ["Hank Jo", "Team Plan", "$599", "Paid"]
    ]
    column(padding: 20.0, spacing: 16.0) {
      # Header
      row(spacing: 12.0) {
        text("Analytics Dashboard", font_size: 26.0, color: $theme.text_primary, bold: true)
        spacer
        button("Refresh", width: 90.0) {}
      }.fixed_height(40.0)

      # KPI Cards
      row(spacing: 12.0) {
        kpi_card("Revenue", "$48,250", "+12.5%", $theme.accent)
        kpi_card("Users", "3,842", "+8.1%", $theme.success)
        kpi_card("Orders", "1,205", "-2.3%", $theme.error)
        kpi_card("Conversion", "4.6%", "+0.8%", $theme.warning)
      }

      # Charts row
      row(spacing: 12.0) {
        container(bg_color: $theme.bg_primary, border_radius: 10.0, padding: 14.0, expanding_width: true) {
          bar_chart(
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun"],
            [[32.0, 45.0, 28.0, 52.0, 41.0, 58.0], [20.0, 30.0, 22.0, 38.0, 35.0, 42.0]],
            ["Revenue", "Costs"]
          ).title("Monthly Overview").fixed_height(220.0)
        }

        container(bg_color: $theme.bg_primary, border_radius: 10.0, padding: 14.0, width: 280.0) {
          pie_chart(
            ["Desktop", "Mobile", "Tablet", "Other"],
            [45.0, 32.0, 18.0, 5.0]
          ).title("Traffic Source").fixed_height(220.0)
        }
      }

      # Bottom row
      row(spacing: 12.0) {
        container(bg_color: $theme.bg_primary, border_radius: 10.0, padding: 14.0, expanding_width: true) {
          line_chart(
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
            [[120.0, 180.0, 150.0, 210.0, 190.0, 240.0, 220.0]],
            ["Active Users"]
          ).title("Weekly Activity").fixed_height(200.0)
        }

        container(bg_color: $theme.bg_primary, border_radius: 10.0, padding: 14.0, expanding_width: true) {
          column {
            text("Recent Orders", font_size: 15.0, color: $theme.accent, bold: true)
            spacer.fixed_height(8.0)
            data_table(table_headers, table_widths, table_rows).fixed_height(200.0)
          }
        }
      }
    }
  end

  def kpi_card(label, value, change, color)
    container(bg_color: $theme.bg_primary, border_radius: 10.0, padding: 16.0, expanding_width: true) {
      column(spacing: 6.0) {
        text(label, font_size: 12.0, color: $theme.text_secondary)
        text(value, font_size: 24.0, color: $theme.text_primary, bold: true)
        text(change, font_size: 13.0, color: color)
      }
    }
  end
end

frame = JWMFrame.new("Analytics Dashboard", 1100, 750)
app = App.new(frame, Dashboard.new)
app.run
