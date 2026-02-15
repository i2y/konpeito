# Castella UI - DataTable Demo
#
# Run: cd examples/castella_ui && bash run.sh data_table_demo.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

class DataTableDemo < Component
  def view
    col_names = ["Name", "Department", "Role", "Salary", "Years"]
    col_widths = [150.0, 120.0, 140.0, 100.0, 80.0]

    rows = [
      ["Alice Johnson", "Engineering", "Senior Developer", "95000", "8"],
      ["Bob Smith", "Engineering", "Staff Engineer", "120000", "12"],
      ["Carol White", "Design", "Lead Designer", "88000", "6"],
      ["David Brown", "Marketing", "Marketing Manager", "82000", "5"],
      ["Eve Davis", "Engineering", "Junior Developer", "65000", "2"],
      ["Frank Wilson", "Sales", "Sales Director", "105000", "10"],
      ["Grace Lee", "Design", "UX Researcher", "78000", "4"],
      ["Henry Taylor", "Engineering", "DevOps Engineer", "92000", "7"],
      ["Iris Chen", "Marketing", "Content Lead", "75000", "3"],
      ["Jack Moore", "Sales", "Account Executive", "70000", "2"],
      ["Karen Park", "Engineering", "Frontend Lead", "98000", "9"],
      ["Leo Kim", "Design", "Visual Designer", "72000", "3"],
      ["Mia Zhang", "Engineering", "Backend Developer", "85000", "5"],
      ["Noah Patel", "Sales", "Sales Manager", "90000", "7"],
      ["Olivia Jones", "Marketing", "Brand Strategist", "80000", "4"],
      ["Peter Wang", "Engineering", "ML Engineer", "110000", "6"],
      ["Quinn Adams", "Design", "Design Systems", "85000", "5"],
      ["Rachel Green", "Engineering", "SRE", "95000", "8"],
      ["Sam Turner", "Sales", "Enterprise Sales", "100000", "9"],
      ["Tina Roberts", "Marketing", "Growth Hacker", "78000", "3"]
    ]

    Column(
      Text("DataTable Demo").font_size(20.0).color(0xFFC0CAF5),
      Text("Click headers to sort. Click rows to select.").font_size(12.0).color($theme.text_secondary),
      Divider(),
      DataTable(col_names, col_widths, rows).fixed_height(500.0)
    ).spacing(8.0)
  end
end

frame = JWMFrame.new("DataTable Demo", 700, 600)
app = App.new(frame, DataTableDemo.new)
app.run
