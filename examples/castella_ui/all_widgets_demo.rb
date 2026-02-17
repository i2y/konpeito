# Castella UI - All Widgets Demo
#
# Comprehensive showcase of all Castella UI widgets and chart types
# organized into 9 tabbed pages.
#
# Run: cd examples/castella_ui && bash run.sh all_widgets_demo.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

# Constants (AWD_ prefix to avoid name collision)
AWD_MD_TEXT = "# Castella UI\n\nA cross-platform **desktop UI framework** built with Konpeito.\n\n## Features\n\n- Reactive state management\n- Rich widget library\n- Theme support\n\n## Code Example\n\n```ruby\nButton(\"Click me\").on_click { count += 1 }\n```\n\n## Flowchart\n\n```mermaid\ngraph LR\n    A[Ruby Code] --> B(Konpeito Compiler)\n    B --> C[JVM Bytecode]\n    C --> D{JWM + Skija}\n    D --> E[Desktop App]\n```\n\nBuilt with Konpeito + JWM + Skija."

AWD_IMAGE_URL = "https://picsum.photos/id/237/280/180"

def build_sample_tree
  root = TreeNode.new("project", "castella-app")
  src = TreeNode.new("src", "src")
  src.add_child(TreeNode.new("app_rb", "app.rb"))
  src.add_child(TreeNode.new("main_rb", "main.rb"))
  components = TreeNode.new("components", "components")
  components.add_child(TreeNode.new("header", "header.rb"))
  components.add_child(TreeNode.new("sidebar", "sidebar.rb"))
  components.add_child(TreeNode.new("footer", "footer.rb"))
  src.add_child(components)
  root.add_child(src)
  assets = TreeNode.new("assets", "assets")
  assets.add_child(TreeNode.new("styles", "styles.css"))
  assets.add_child(TreeNode.new("logo", "logo.png"))
  root.add_child(assets)
  root.add_child(TreeNode.new("gemfile", "Gemfile"))
  root.add_child(TreeNode.new("readme", "README.md"))
  [root]
end

# Animated bar widget for the Animation tab
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

class AllWidgetsDemo < Component
  def initialize
    super()
    @counter = state(0)
    # Input states persist across rebuilds
    @input_state = InputState.new("Type something...")
    @mli_state = MultilineInputState.new("Multi-line\ninput here.")
    # Tree state (Tree widget attaches itself as observer internally)
    nodes = build_sample_tree
    @tree_state = TreeState.new(nodes)
    @tree_state.expand("project")
    @tree_state.expand("src")
    # Calendar state (Calendar widget attaches itself as observer internally)
    @cal_state = CalendarState.new(2026, 2, 13)
    # Animation states
    @anim_linear = AnimatedState.new(0.0, 1000.0, :linear)
    @anim_ease_in = AnimatedState.new(0.0, 1000.0, :ease_in)
    @anim_ease_out = AnimatedState.new(0.0, 1000.0, :ease_out)
    @anim_ease_io = AnimatedState.new(0.0, 1000.0, :ease_in_out)
    @anim_cubic_in = AnimatedState.new(0.0, 1000.0, :ease_in_cubic)
    @anim_cubic_out = AnimatedState.new(0.0, 1000.0, :ease_out_cubic)
    @anim_bounce = AnimatedState.new(0.0, 1500.0, :bounce)
    @anim_toggled = false
  end

  # ── Tab 1: Basic ──
  def build_basic_tab
    counter_ref = @counter
    count_text = @counter.value.to_s

    Column(
      Text("Text Styles").font_size(18.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Text("Large heading text").font_size(20.0).color(0xFF7AA2F7),
      Text("Normal body text with default styling").font_size(14.0),
      Text("Small muted text").font_size(11.0).color(0xFF565F89),
      Spacer().fixed_height(8.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Button Kinds").font_size(18.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Row(
        Button("Normal"),
        Spacer().fixed_width(6.0),
        Button("Info").kind(1),
        Spacer().fixed_width(6.0),
        Button("Success").kind(2),
        Spacer().fixed_width(6.0),
        Button("Warning").kind(3),
        Spacer().fixed_width(6.0),
        Button("Danger").kind(4)
      ).fixed_height(36.0),
      Spacer().fixed_height(8.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Counter").font_size(18.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Row(
        Button("-").on_click { counter_ref -= 1 },
        Spacer().fixed_width(8.0),
        Text(count_text).font_size(20.0).color(0xFF9ECE6A).bold.align(TEXT_ALIGN_CENTER),
        Spacer().fixed_width(8.0),
        Button("+").on_click { counter_ref += 1 }
      ).fixed_height(36.0),
      Spacer()
    ).spacing(2.0).scrollable
  end

  # ── Tab 2: Input ──
  def build_input_tab
    Column(
      Text("Single-line Input").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Input.new(@input_state).tab_index(1),
      Spacer().fixed_height(12.0),

      Text("Multi-line Input").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      MultilineInput.new(@mli_state).font_size(14.0).wrap_text(true).fixed_height(100.0).tab_index(2),
      Spacer().fixed_height(12.0),

      Text("Checkbox").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Checkbox("Enable notifications").checked(true),
      Checkbox("Dark mode"),
      Spacer().fixed_height(12.0),

      Text("Radio Buttons").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      RadioButtons(["Small", "Medium", "Large"]),
      Spacer().fixed_height(12.0),

      Text("Switch").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Switch(),
      Spacer().fixed_height(12.0),

      Text("Slider").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Slider(0.0, 100.0).with_value(50.0),
      Spacer().fixed_height(12.0),

      Text("Progress Bar").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      ProgressBar().with_value(0.4),
      Spacer().fixed_height(4.0),
      ProgressBar().with_value(0.75).fill_color(0xFF9ECE6A),
      Spacer()
    ).spacing(2.0).scrollable
  end

  # ── Tab 3: Layout ──
  def build_layout_tab
    Column(
      Text("Row / Column Nesting").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Row(
        Container(
          Column(
            Text("Left Column").font_size(13.0).color(0xFF7AA2F7),
            Text("Item A").font_size(12.0),
            Text("Item B").font_size(12.0),
            Text("Item C").font_size(12.0)
          ).spacing(4.0)
        ),
        Spacer().fixed_width(8.0),
        Container(
          Column(
            Text("Right Column").font_size(13.0).color(0xFF7AA2F7),
            Text("Item X").font_size(12.0),
            Text("Item Y").font_size(12.0),
            Text("Item Z").font_size(12.0)
          ).spacing(4.0)
        )
      ).spacing(8.0).fixed_height(120.0),
      Spacer().fixed_height(12.0),

      Text("Spacer (push apart)").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Container(
        Row(
          Text("Left").font_size(14.0),
          Spacer(),
          Text("Right").font_size(14.0)
        ).fixed_height(30.0)
      ),
      Spacer().fixed_height(12.0),

      Text("Container with border").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Container(
        Column(
          Text("This content is wrapped in a Container.").font_size(13.0),
          Text("Containers add a rounded border and padding.").font_size(13.0).color(0xFF565F89)
        ).spacing(4.0)
      ),
      Spacer()
    ).spacing(2.0).scrollable
  end

  # ── Tab 4: Data ──
  def build_data_tab
    ts = @tree_state
    cs = @cal_state

    col_names = ["Name", "Dept", "Role", "Salary"]
    col_widths = [130.0, 100.0, 130.0, 80.0]
    rows = [
      ["Alice Johnson", "Engineering", "Senior Dev", "95000"],
      ["Bob Smith", "Engineering", "Staff Eng", "120000"],
      ["Carol White", "Design", "Lead Designer", "88000"],
      ["David Brown", "Marketing", "Manager", "82000"],
      ["Eve Davis", "Engineering", "Junior Dev", "65000"],
      ["Frank Wilson", "Sales", "Director", "105000"],
      ["Grace Lee", "Design", "UX Research", "78000"],
      ["Henry Taylor", "Engineering", "DevOps", "92000"],
      ["Iris Chen", "Marketing", "Content Lead", "75000"],
      ["Jack Moore", "Sales", "Account Exec", "70000"]
    ]

    Column(
      Text("DataTable").font_size(16.0).color(0xFFC0CAF5).bold,
      Text("Click headers to sort").font_size(11.0).color(0xFF565F89),
      Spacer().fixed_height(4.0),
      DataTable(col_names, col_widths, rows).fixed_height(280.0),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Tree").font_size(16.0).color(0xFFC0CAF5).bold,
      Text("Click nodes to select, arrows to expand").font_size(11.0).color(0xFF565F89),
      Row(
        Button("Expand All").on_click(-> { ts.expand_all }),
        Spacer().fixed_width(6.0),
        Button("Collapse All").on_click(-> { ts.collapse_all })
      ).fixed_height(36.0),
      Tree(ts),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Calendar").font_size(16.0).color(0xFFC0CAF5).bold,
      Text("Click a date to select").font_size(11.0).color(0xFF565F89),
      Spacer().fixed_height(4.0),
      Row(
        Spacer(),
        Calendar(cs),
        Spacer()
      ).fixed_height(310.0),
      Spacer()
    ).spacing(2.0).scrollable
  end

  # ── Tab 5: Content ──
  def build_content_tab
    modal_body = Column(
      Text("Hello from a Modal!").font_size(16.0).color(0xFFC0CAF5),
      Spacer().fixed_height(8.0),
      Text("Click X or backdrop to close.").font_size(13.0).color(0xFF565F89),
      Spacer().fixed_height(8.0),
      Input("Modal input field...")
    ).spacing(4.0)
    m = Modal(modal_body).title("Sample Dialog").dialog_size(320.0, 200.0)

    main = Column(
      Text("Markdown").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Markdown(AWD_MD_TEXT),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("NetImage (from URL)").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      NetImage(AWD_IMAGE_URL),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Modal Dialog").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Button("Open Modal").on_click { m.open_modal },
      Spacer()
    ).spacing(2.0).scrollable

    Box(main, m)
  end

  # ── Tab 6: Animation ──
  def build_animation_tab
    al = @anim_linear
    ai = @anim_ease_in
    ao = @anim_ease_out
    aio = @anim_ease_io
    aci = @anim_cubic_in
    aco = @anim_cubic_out
    ab = @anim_bounce

    Column(
      Text("Animation").font_size(18.0).color(0xFFC0CAF5).bold.fixed_height(24.0),
      Text("Click the button to animate bars with different easing").font_size(12.0).color(0xFF565F89).fixed_height(16.0),
      Spacer().fixed_height(8.0),
      Button("Animate!").kind(1).fixed_height(36.0).on_click {
        if @anim_toggled
          al.set(0.0)
          ai.set(0.0)
          ao.set(0.0)
          aio.set(0.0)
          aci.set(0.0)
          aco.set(0.0)
          ab.set(0.0)
        else
          al.set(100.0)
          ai.set(100.0)
          ao.set(100.0)
          aio.set(100.0)
          aci.set(100.0)
          aco.set(100.0)
          ab.set(100.0)
        end
        @anim_toggled = !@anim_toggled
      },
      Spacer().fixed_height(12.0),
      AnimatedBar.new(al, "Linear", 0xFF7AA2F7),
      AnimatedBar.new(ai, "Ease In", 0xFF9ECE6A),
      AnimatedBar.new(ao, "Ease Out", 0xFFF7768E),
      AnimatedBar.new(aio, "Ease In/Out", 0xFFE0AF68),
      AnimatedBar.new(aci, "Cubic In", 0xFFBB9AF7),
      AnimatedBar.new(aco, "Cubic Out", 0xFF73DACA),
      AnimatedBar.new(ab, "Bounce", 0xFFFF9E64),
      Spacer()
    ).spacing(8.0)
  end

  # ── Tab 7: Charts 1 ──
  def build_charts1_tab
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    sales = [120.0, 200.0, 150.0, 300.0, 250.0, 180.0]
    costs = [80.0, 120.0, 100.0, 180.0, 160.0, 140.0]

    labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    temp = [5.0, 7.0, 12.0, 18.0, 22.0, 26.0]
    rain = [40.0, 35.0, 45.0, 30.0, 25.0, 20.0]

    Column(
      Text("Bar Chart").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      BarChart(months, [sales, costs], ["Sales", "Costs"])
        .title("Monthly Sales vs Costs")
        .show_values(true)
        .fixed_height(280.0),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Line Chart").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      LineChart(labels, [temp, rain], ["Temperature (C)", "Rainfall (mm)"])
        .title("Weather Trends")
        .fixed_height(280.0),
      Spacer()
    ).spacing(2.0).scrollable
  end

  # ── Tab 8: Charts 2 ──
  def build_charts2_tab
    pie_labels = ["Engineering", "Design", "Marketing", "Sales", "Ops"]
    pie_values = [35.0, 20.0, 18.0, 15.0, 12.0]

    q_labels = ["Q1", "Q2", "Q3", "Q4"]
    revenue = [120.0, 180.0, 150.0, 220.0]
    expenses = [80.0, 100.0, 90.0, 130.0]

    Column(
      Text("Pie Chart").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Row(
        PieChart(pie_labels, pie_values)
          .title("Budget")
          .fixed_height(280.0),
        PieChart(pie_labels, pie_values)
          .title("Donut")
          .donut(true)
          .fixed_height(280.0)
      ).spacing(8.0).fixed_height(300.0),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Area Chart").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      AreaChart(q_labels, [revenue, expenses], ["Revenue", "Expenses"])
        .title("Quarterly Financials")
        .fixed_height(280.0),
      Spacer()
    ).spacing(2.0).scrollable
  end

  # ── Tab 9: Charts 3 ──
  def build_charts3_tab
    sc_x1 = [1.0, 2.5, 3.0, 4.5, 5.0, 6.5, 7.0]
    sc_y1 = [2.0, 4.0, 3.5, 7.0, 5.5, 8.0, 6.0]
    sc_x2 = [1.5, 3.0, 4.0, 5.5, 6.0, 7.5, 8.5]
    sc_y2 = [1.0, 3.0, 2.5, 4.0, 6.0, 5.0, 7.5]

    quarters = ["Q1", "Q2", "Q3", "Q4"]
    prod_a = [30.0, 40.0, 35.0, 50.0]
    prod_b = [20.0, 25.0, 30.0, 35.0]
    prod_c = [15.0, 20.0, 25.0, 20.0]

    hm_x = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    hm_y = ["9am", "12pm", "3pm", "6pm"]
    hm_data = [
      [2.0, 5.0, 8.0, 4.0, 3.0],
      [6.0, 9.0, 7.0, 5.0, 4.0],
      [3.0, 4.0, 6.0, 8.0, 7.0],
      [1.0, 2.0, 3.0, 6.0, 9.0]
    ]

    Column(
      Text("Scatter Chart").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      ScatterChart([sc_x1, sc_x2], [sc_y1, sc_y2], ["Series A", "Series B"])
        .title("Scatter Plot")
        .fixed_height(280.0),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Stacked Bar Chart").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      StackedBarChart(quarters, [prod_a, prod_b, prod_c], ["Product A", "Product B", "Product C"])
        .title("Quarterly Sales (Stacked)")
        .show_values(true)
        .fixed_height(280.0),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Gauge Charts").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      Row(
        GaugeChart(72.0, 0.0, 100.0)
          .title("CPU")
          .unit("%")
          .thresholds([[0.5, 0xFF9ECE6A], [0.75, 0xFFE0AF68], [1.0, 0xFFF7768E]])
          .fixed_height(220.0),
        GaugeChart(3.8, 0.0, 5.0)
          .title("Rating")
          .thresholds([[0.4, 0xFFF7768E], [0.7, 0xFFE0AF68], [1.0, 0xFF9ECE6A]])
          .fixed_height(220.0)
      ).spacing(8.0).fixed_height(230.0),
      Spacer().fixed_height(12.0),
      Divider(),
      Spacer().fixed_height(8.0),

      Text("Heatmap Chart").font_size(16.0).color(0xFFC0CAF5).bold,
      Spacer().fixed_height(4.0),
      HeatmapChart(hm_x, hm_y, hm_data)
        .title("Activity Heatmap")
        .margins(40.0, 60.0, 50.0, 60.0)
        .fixed_height(260.0),
      Spacer()
    ).spacing(2.0).scrollable
  end

  # ── Main View ──
  def view
    tab1 = build_basic_tab
    tab2 = build_input_tab
    tab3 = build_layout_tab
    tab4 = build_data_tab
    tab5 = build_content_tab
    tab6 = build_animation_tab
    tab7 = build_charts1_tab
    tab8 = build_charts2_tab
    tab9 = build_charts3_tab

    labels = ["Basic", "Input", "Layout", "Data", "Content", "Animate", "Charts 1", "Charts 2", "Charts 3"]
    contents = [tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8, tab9]

    Column(
      Tabs(labels, contents)
    )
  end
end

frame = JWMFrame.new("All Widgets Demo", 900, 700)
app = App.new(frame, AllWidgetsDemo.new)
app.run
