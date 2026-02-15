# Castella UI - DSL All Widgets Demo
#
# DSL version of all_widgets_demo.rb.
# Demonstrates the block-based DSL with all widget types.
#
# Run: cd examples/castella_ui && bash run.sh dsl_all_widgets_demo.rb

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

# Constants (DAWD_ prefix to avoid name collision)
DAWD_MD_TEXT = "# Castella UI\n\nA cross-platform **desktop UI framework** built with Konpeito.\n\n## Features\n\n- Reactive state management\n- Rich widget library\n- Theme support\n\n## Code Example\n\n```ruby\nbutton(\"Click me\", nil) { count += 1 }\n```\n\n## Flowchart\n\n```mermaid\ngraph LR\n    A[Ruby Code] --> B(Konpeito Compiler)\n    B --> C[JVM Bytecode]\n    C --> D{JWM + Skija}\n    D --> E[Desktop App]\n```\n\nBuilt with Konpeito + JWM + Skija."

DAWD_IMAGE_URL = "https://picsum.photos/id/237/280/180"

def build_dsl_sample_tree
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
class DslAnimatedBar < Widget
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
    painter.fill_round_rect(0.0, 4.0, @width, 22.0, 4.0, $theme.bg_secondary)
    fill_w = (@anim.value / 100.0) * @width
    if fill_w > @width
      fill_w = @width
    end
    if fill_w > 0.0
      painter.fill_round_rect(0.0, 4.0, fill_w, 22.0, 4.0, @color)
    end
    ascent = painter.get_text_ascent("default", 11.0)
    painter.draw_text(@label, 8.0, 4.0 + 11.0 + ascent / 2.0, "default", 11.0, 0xFFFFFFFF)
    val_text = painter.number_to_string(@anim.value) + "%"
    vw = painter.measure_text_width(val_text, "default", 11.0)
    painter.draw_text(val_text, @width - vw - 8.0, 4.0 + 11.0 + ascent / 2.0, "default", 11.0, 0xFFFFFFFF)
  end
end

class DslAllWidgetsDemo < Component
  def initialize
    super()
    @counter = state(0)
    @input_state = InputState.new("Type something...")
    @mli_state = MultilineInputState.new("Multi-line\ninput here.")
    nodes = build_dsl_sample_tree
    @tree_state = TreeState.new(nodes)
    @tree_state.expand("project")
    @tree_state.expand("src")
    @cal_state = CalendarState.new(2026, 2, 13)
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

    # Reusable text styles
    section_title = s.font_size(18.0).color(0xFFC0CAF5).bold

    column(s.spacing(2.0)) {
      text("Text Styles", section_title)
      spacer.fixed_height(4.0)
      text("Large heading text", s.font_size(20.0).color(0xFF7AA2F7))
      text("Normal body text with default styling", s.font_size(14.0))
      text("Small muted text", s.font_size(11.0).color(0xFF565F89))
      spacer.fixed_height(8.0)
      divider
      spacer.fixed_height(8.0)

      text("Button Kinds", section_title)
      spacer.fixed_height(4.0)
      row(nil) {
        button("Normal", nil)
        spacer.fixed_width(6.0)
        button("Info", s.kind(1))
        spacer.fixed_width(6.0)
        button("Success", s.kind(2))
        spacer.fixed_width(6.0)
        button("Warning", s.kind(3))
        spacer.fixed_width(6.0)
        button("Danger", s.kind(4))
        spacer
      }.fixed_height(36.0)
      spacer.fixed_height(8.0)
      divider
      spacer.fixed_height(8.0)

      text("Counter", section_title)
      spacer.fixed_height(4.0)
      row(nil) {
        button("-", nil).on_click { counter_ref -= 1 }
        spacer.fixed_width(8.0)
        column(s.width(40.0)) {
          spacer
          text(count_text, s.font_size(20.0).color(0xFF9ECE6A).bold)
          spacer
        }
        spacer.fixed_width(8.0)
        button("+", s.kind(1)).on_click { counter_ref += 1 }
        spacer
      }.fixed_height(36.0)
      spacer
    }.scrollable
  end

  # ── Tab 2: Input ──
  def build_input_tab
    is = @input_state
    ms = @mli_state

    section_title = s.font_size(16.0).color(0xFFC0CAF5).bold

    column(s.spacing(2.0)) {
      text("Single-line Input", section_title)
      spacer.fixed_height(4.0)
      text_input(is, nil).tab_index(1)
      spacer.fixed_height(12.0)

      text("Multi-line Input", section_title)
      spacer.fixed_height(4.0)
      multiline_input(ms, nil).font_size(14).wrap_text(true).fixed_height(100.0).tab_index(2)
      spacer.fixed_height(12.0)

      text("Checkbox", section_title)
      spacer.fixed_height(4.0)
      checkbox("Enable notifications", nil).checked(true)
      checkbox("Dark mode", nil)
      spacer.fixed_height(12.0)

      text("Radio Buttons", section_title)
      spacer.fixed_height(4.0)
      radio_buttons(["Small", "Medium", "Large"], nil)
      spacer.fixed_height(12.0)

      text("Switch", section_title)
      spacer.fixed_height(4.0)
      switch_toggle
      spacer.fixed_height(12.0)

      text("Slider", section_title)
      spacer.fixed_height(4.0)
      slider(0.0, 100.0, nil).with_value(50.0)
      spacer.fixed_height(12.0)

      text("Progress Bar", section_title)
      spacer.fixed_height(4.0)
      progress_bar.with_value(0.4)
      spacer.fixed_height(4.0)
      progress_bar.with_value(0.75).fill_color(0xFF9ECE6A)
      spacer
    }.scrollable
  end

  # ── Tab 3: Layout ──
  def build_layout_tab
    section_title = s.font_size(16.0).color(0xFFC0CAF5).bold

    column(s.spacing(2.0)) {
      text("Row / Column Nesting", section_title)
      spacer.fixed_height(4.0)
      row(s.spacing(8.0).height(120.0)) {
        container(nil) {
          column(s.spacing(4.0)) {
            text("Left Column", s.font_size(13.0).color(0xFF7AA2F7))
            text("Item A", s.font_size(12.0))
            text("Item B", s.font_size(12.0))
            text("Item C", s.font_size(12.0))
          }
        }
        spacer.fixed_width(8.0)
        container(nil) {
          column(s.spacing(4.0)) {
            text("Right Column", s.font_size(13.0).color(0xFF7AA2F7))
            text("Item X", s.font_size(12.0))
            text("Item Y", s.font_size(12.0))
            text("Item Z", s.font_size(12.0))
          }
        }
      }
      spacer.fixed_height(12.0)

      text("Spacer (push apart)", section_title)
      spacer.fixed_height(4.0)
      container(nil) {
        row(s.height(30.0)) {
          text("Left", s.font_size(14.0))
          spacer
          text("Right", s.font_size(14.0))
        }
      }
      spacer.fixed_height(12.0)

      text("Container with border", section_title)
      spacer.fixed_height(4.0)
      container(nil) {
        column(s.spacing(4.0)) {
          text("This content is wrapped in a Container.", s.font_size(13.0))
          text("Containers add a rounded border and padding.", s.font_size(13.0).color(0xFF565F89))
        }
      }
      spacer
    }.scrollable
  end

  # ── Tab 4: Data ──
  def build_data_tab
    ts = @tree_state
    cs = @cal_state

    section_title = s.font_size(16.0).color(0xFFC0CAF5).bold
    muted = s.font_size(11.0).color(0xFF565F89)

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

    column(s.spacing(2.0)) {
      text("DataTable", section_title)
      text("Click headers to sort", muted)
      spacer.fixed_height(4.0)
      data_table(col_names, col_widths, rows, nil).fixed_height(280.0)
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Tree", section_title)
      text("Click nodes to select, arrows to expand", muted)
      row(s.height(36.0)) {
        button("Expand All", nil).on_click(-> { ts.expand_all })
        spacer.fixed_width(6.0)
        button("Collapse All", nil).on_click(-> { ts.collapse_all })
        spacer
      }
      tree(ts)
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Calendar", section_title)
      text("Click a date to select", muted)
      spacer.fixed_height(4.0)
      row(s.height(310.0)) {
        spacer
        calendar(cs)
        spacer
      }
      spacer
    }.scrollable
  end

  # ── Tab 5: Content ──
  def build_content_tab
    section_title = s.font_size(16.0).color(0xFFC0CAF5).bold

    modal_body = column(nil) {
      text("Hello from a Modal!", section_title)
      spacer.fixed_height(8.0)
      text("Click X or backdrop to close.", s.font_size(13.0).color(0xFF565F89))
      spacer.fixed_height(8.0)
      text_input(InputState.new("Modal input field..."), nil)
    }.spacing(4.0)
    m = Modal.new(modal_body).title("Sample Dialog").dialog_size(320, 200)

    main = column(s.spacing(2.0)) {
      text("Markdown", section_title)
      spacer.fixed_height(4.0)
      markdown_text(DAWD_MD_TEXT, nil)
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("NetImage (from URL)", section_title)
      spacer.fixed_height(4.0)
      net_image(DAWD_IMAGE_URL, nil)
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Modal Dialog", section_title)
      spacer.fixed_height(4.0)
      button("Open Modal", nil).on_click { m.open_modal }
      spacer
    }.scrollable

    box(nil) {
      embed(main)
      embed(m)
    }
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

    column(s.spacing(8.0)) {
      text("Animation", s.font_size(18.0).color(0xFFC0CAF5).bold)
      text("Click the button to animate bars with different easing", s.font_size(12.0).color(0xFF565F89))
      spacer.fixed_height(8.0)
      button("Animate!", s.kind(1)).on_click {
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
      }
      spacer.fixed_height(12.0)
      embed(DslAnimatedBar.new(al, "Linear", 0xFF7AA2F7))
      embed(DslAnimatedBar.new(ai, "Ease In", 0xFF9ECE6A))
      embed(DslAnimatedBar.new(ao, "Ease Out", 0xFFF7768E))
      embed(DslAnimatedBar.new(aio, "Ease In/Out", 0xFFE0AF68))
      embed(DslAnimatedBar.new(aci, "Cubic In", 0xFFBB9AF7))
      embed(DslAnimatedBar.new(aco, "Cubic Out", 0xFF73DACA))
      embed(DslAnimatedBar.new(ab, "Bounce", 0xFFFF9E64))
      spacer
    }
  end

  # ── Tab 7: Charts 1 ──
  def build_charts1_tab
    section_title = s.font_size(16.0).color(0xFFC0CAF5).bold

    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    sales = [120.0, 200.0, 150.0, 300.0, 250.0, 180.0]
    costs = [80.0, 120.0, 100.0, 180.0, 160.0, 140.0]

    labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    temp = [5.0, 7.0, 12.0, 18.0, 22.0, 26.0]
    rain = [40.0, 35.0, 45.0, 30.0, 25.0, 20.0]

    column(s.spacing(2.0)) {
      text("Bar Chart", section_title)
      spacer.fixed_height(4.0)
      bar_chart(months, [sales, costs], ["Sales", "Costs"])
        .title("Monthly Sales vs Costs")
        .show_values(true)
        .fixed_height(280.0)
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Line Chart", section_title)
      spacer.fixed_height(4.0)
      line_chart(labels, [temp, rain], ["Temperature (C)", "Rainfall (mm)"])
        .title("Weather Trends")
        .fixed_height(280.0)
      spacer
    }.scrollable
  end

  # ── Tab 8: Charts 2 ──
  def build_charts2_tab
    section_title = s.font_size(16.0).color(0xFFC0CAF5).bold

    pie_labels = ["Engineering", "Design", "Marketing", "Sales", "Ops"]
    pie_values = [35.0, 20.0, 18.0, 15.0, 12.0]

    q_labels = ["Q1", "Q2", "Q3", "Q4"]
    revenue = [120.0, 180.0, 150.0, 220.0]
    expenses = [80.0, 100.0, 90.0, 130.0]

    column(s.spacing(2.0)) {
      text("Pie Chart", section_title)
      spacer.fixed_height(4.0)
      row(s.spacing(8.0).height(300.0)) {
        pie_chart(pie_labels, pie_values)
          .title("Budget")
          .fixed_height(280.0)
        pie_chart(pie_labels, pie_values)
          .title("Donut")
          .donut(true)
          .fixed_height(280.0)
      }
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Area Chart", section_title)
      spacer.fixed_height(4.0)
      area_chart(q_labels, [revenue, expenses], ["Revenue", "Expenses"])
        .title("Quarterly Financials")
        .fixed_height(280.0)
      spacer
    }.scrollable
  end

  # ── Tab 9: Charts 3 ──
  def build_charts3_tab
    section_title = s.font_size(16.0).color(0xFFC0CAF5).bold

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

    column(s.spacing(2.0)) {
      text("Scatter Chart", section_title)
      spacer.fixed_height(4.0)
      scatter_chart([sc_x1, sc_x2], [sc_y1, sc_y2], ["Series A", "Series B"])
        .title("Scatter Plot")
        .fixed_height(280.0)
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Stacked Bar Chart", section_title)
      spacer.fixed_height(4.0)
      stacked_bar_chart(quarters, [prod_a, prod_b, prod_c], ["Product A", "Product B", "Product C"])
        .title("Quarterly Sales (Stacked)")
        .show_values(true)
        .fixed_height(280.0)
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Gauge Charts", section_title)
      spacer.fixed_height(4.0)
      row(s.spacing(8.0).height(230.0)) {
        gauge_chart(72.0, 0.0, 100.0)
          .title("CPU")
          .unit("%")
          .thresholds([[0.5, 0xFF9ECE6A], [0.75, 0xFFE0AF68], [1.0, 0xFFF7768E]])
          .fixed_height(220.0)
        gauge_chart(3.8, 0.0, 5.0)
          .title("Rating")
          .thresholds([[0.4, 0xFFF7768E], [0.7, 0xFFE0AF68], [1.0, 0xFF9ECE6A]])
          .fixed_height(220.0)
      }
      spacer.fixed_height(12.0)
      divider
      spacer.fixed_height(8.0)

      text("Heatmap Chart", section_title)
      spacer.fixed_height(4.0)
      heatmap_chart(hm_x, hm_y, hm_data)
        .title("Activity Heatmap")
        .margins(40, 60, 50, 60)
        .fixed_height(260.0)
      spacer
    }.scrollable
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

    column(nil) {
      tabs(labels, contents)
    }
  end
end

frame = JWMFrame.new("DSL All Widgets Demo", 900, 700)
app = App.new(frame, DslAllWidgetsDemo.new)
app.run
