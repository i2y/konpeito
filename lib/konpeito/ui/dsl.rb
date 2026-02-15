# rbs_inline: enabled

# DSL - Block-based UI tree builder (CSS-inspired)
#
# Uses a widget stack to manage implicit parent-child relationships.
# Lowercase DSL functions (column, row, text, etc.) create widgets
# and auto-add them to the current parent in the stack.
#
# Usage (keyword arguments — recommended):
#   column(padding: 16.0) {
#     text "Count: #{@count}", font_size: 32.0, color: 0xFFC0CAF5, align: :center
#     row(spacing: 8.0) {
#       button(" - ", width: 80.0) { @count -= 1 }
#       spacer
#       button(" + ", width: 80.0) { @count += 1 }
#     }
#   }
#
# Usage (Style object — also supported):
#   column(s.spacing(8)) {
#     text("Title", s.font_size(24).color(0xFFC0CAF5).bold)
#     row(s.fixed_height(60)) {
#       button("-", s.width(80)) { @count -= 1 }
#       spacer
#       button("+", s.width(80)) { @count += 1 }
#     }
#   }

# Widget stack for tracking current parent container
DSL_STACK = []

#: (untyped w) -> void
def __dsl_push(w)
  DSL_STACK.push(w)
end

#: () -> untyped
def __dsl_pop
  DSL_STACK.pop
end

# NOTE: __dsl_auto_add accesses DSL_STACK.last directly instead of
# going through a helper function. On JVM, returning a value from a
# helper function that has an if/else with nil loses the object reference
# (phi-node merging issue with nil branch).
#: (untyped w) -> void
def __dsl_auto_add(w)
  len = DSL_STACK.length
  if len > 0
    parent = DSL_STACK.last
    if parent != nil
      parent.add(w)
    end
  end
end

# --- Keyword argument helper ---
# Applies keyword arguments directly to a widget.
# typography: true enables text-related kwargs (font_size, color, bold, etc.)

#: (untyped widget, Hash kwargs, bool typography) -> void
def __apply_kwargs(widget, kwargs, typography)
  # Layout
  widget.fixed_width(kwargs[:width]) if kwargs.key?(:width)
  widget.fixed_height(kwargs[:height]) if kwargs.key?(:height)
  if kwargs.key?(:padding)
    p = kwargs[:padding]
    widget.padding(p, p, p, p)
  end
  widget.flex(kwargs[:flex]) if kwargs.key?(:flex)
  widget.fit_content if kwargs[:fit_content]
  # Container
  widget.spacing(kwargs[:spacing]) if kwargs.key?(:spacing)
  widget.scrollable if kwargs[:scrollable]
  widget.pin_to_bottom if kwargs[:pin_to_bottom]
  widget.pin_to_end if kwargs[:pin_to_end]
  # Visual
  widget.bg_color(kwargs[:bg_color]) if kwargs.key?(:bg_color)
  widget.border_color(kwargs[:border_color]) if kwargs.key?(:border_color)
  widget.border_radius(kwargs[:border_radius]) if kwargs.key?(:border_radius)
  # Expanding
  if kwargs[:expanding]
    widget.set_width_policy(EXPANDING)
    widget.set_height_policy(EXPANDING)
  end
  widget.set_width_policy(EXPANDING) if kwargs[:expanding_width]
  widget.set_height_policy(EXPANDING) if kwargs[:expanding_height]
  # Typography (text/button/checkbox etc.)
  if typography
    widget.font_size(kwargs[:font_size]) if kwargs.key?(:font_size)
    widget.color(kwargs[:color]) if kwargs.key?(:color)
    widget.text_color(kwargs[:text_color]) if kwargs.key?(:text_color)
    widget.bold if kwargs[:bold]
    widget.italic if kwargs[:italic]
    widget.font_family(kwargs[:font_family]) if kwargs.key?(:font_family)
    widget.kind(kwargs[:kind]) if kwargs.key?(:kind)
    if kwargs.key?(:align)
      a = kwargs[:align]
      if a == :center
        widget.align(1)
      elsif a == :right
        widget.align(2)
      elsif a == :left
        widget.align(0)
      else
        widget.align(a)
      end
    end
  end
end

# --- Style helper ---

#: () -> Style
def s
  Style.new
end

# --- Container DSL functions ---

#: (Style? base_style, **untyped kwargs) -> Column
def column(base_style = nil, **kwargs)
  col = Column.new
  if base_style != nil
    base_style.apply(col)
  end
  __apply_kwargs(col, kwargs, false) if kwargs.length > 0
  __dsl_push(col)
  yield
  __dsl_pop
  __dsl_auto_add(col)
  col
end

#: (Style? base_style, **untyped kwargs) -> Row
def row(base_style = nil, **kwargs)
  r = Row.new
  if base_style != nil
    base_style.apply(r)
  end
  __apply_kwargs(r, kwargs, false) if kwargs.length > 0
  __dsl_push(r)
  yield
  __dsl_pop
  __dsl_auto_add(r)
  r
end

#: (Style? base_style, **untyped kwargs) -> Box
def box(base_style = nil, **kwargs)
  b = Box.new
  if base_style != nil
    base_style.apply(b)
  end
  __apply_kwargs(b, kwargs, false) if kwargs.length > 0
  __dsl_push(b)
  yield
  __dsl_pop
  __dsl_auto_add(b)
  b
end

#: (Style? base_style, **untyped kwargs) -> Container
def container(base_style = nil, **kwargs)
  c = Container.new(nil)
  if base_style != nil
    base_style.apply_layout(c)
    base_style.apply_visual(c)
  end
  __apply_kwargs(c, kwargs, false) if kwargs.length > 0
  __dsl_push(c)
  yield
  __dsl_pop
  __dsl_auto_add(c)
  c
end

# --- Leaf DSL functions ---

#: (String content, Style? base_style, **untyped kwargs) -> Text
def text(content, base_style = nil, **kwargs)
  w = Text.new(content)
  if base_style != nil
    base_style.apply(w)
    base_style.apply_typography(w)
  end
  __apply_kwargs(w, kwargs, true) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (String label, Style? base_style, **untyped kwargs) -> Button
def button(label, base_style = nil, **kwargs)
  w = Button.new(label)
  if base_style != nil
    base_style.apply(w)
    base_style.apply_typography(w)
  end
  __apply_kwargs(w, kwargs, true) if kwargs.length > 0
  if block_given?
    w.on_click { yield }
  end
  __dsl_auto_add(w)
  w
end

#: () -> Spacer
def spacer
  w = Spacer.new
  __dsl_auto_add(w)
  w
end

#: () -> Divider
def divider
  w = Divider.new
  __dsl_auto_add(w)
  w
end

#: (String label, Style? base_style, **untyped kwargs) -> Checkbox
def checkbox(label, base_style = nil, **kwargs)
  w = Checkbox.new(label)
  if base_style != nil
    base_style.apply(w)
    base_style.apply_typography(w)
  end
  __apply_kwargs(w, kwargs, true) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (Array options, Style? base_style, **untyped kwargs) -> RadioButtons
def radio_buttons(options, base_style = nil, **kwargs)
  w = RadioButtons.new(options)
  if base_style != nil
    base_style.apply(w)
  end
  __apply_kwargs(w, kwargs, false) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (Float min_val, Float max_val, Style? base_style, **untyped kwargs) -> Slider
def slider(min_val, max_val, base_style = nil, **kwargs)
  w = Slider.new(min_val, max_val)
  if base_style != nil
    base_style.apply(w)
  end
  __apply_kwargs(w, kwargs, false) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (String path, Style? base_style, **untyped kwargs) -> ImageWidget
def image(path, base_style = nil, **kwargs)
  w = ImageWidget.new(path)
  if base_style != nil
    base_style.apply(w)
  end
  __apply_kwargs(w, kwargs, false) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (String url, Style? base_style, **untyped kwargs) -> NetImageWidget
def net_image(url, base_style = nil, **kwargs)
  w = NetImageWidget.new(url)
  if base_style != nil
    base_style.apply(w)
  end
  __apply_kwargs(w, kwargs, false) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (String content, Style? base_style, **untyped kwargs) -> MultilineText
def multiline_text(content, base_style = nil, **kwargs)
  w = MultilineText.new(content)
  if base_style != nil
    base_style.apply(w)
    base_style.apply_typography(w)
  end
  __apply_kwargs(w, kwargs, true) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (String content, Style? base_style, **untyped kwargs) -> Markdown
def markdown_text(content, base_style = nil, **kwargs)
  w = Markdown.new(content)
  if base_style != nil
    base_style.apply(w)
  end
  __apply_kwargs(w, kwargs, false) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (InputState state, Style? base_style, **untyped kwargs) -> Input
def text_input(state, base_style = nil, **kwargs)
  w = Input.new(state)
  if base_style != nil
    base_style.apply(w)
    base_style.apply_typography(w)
  end
  __apply_kwargs(w, kwargs, true) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (MultilineInputState state, Style? base_style, **untyped kwargs) -> MultilineInput
def multiline_input(state, base_style = nil, **kwargs)
  w = MultilineInput.new(state)
  if base_style != nil
    base_style.apply(w)
  end
  __apply_kwargs(w, kwargs, false) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: (Array cols, Array widths, Array rows, Style? base_style, **untyped kwargs) -> DataTable
def data_table(cols, widths, rows, base_style = nil, **kwargs)
  w = DataTable.new(cols, widths, rows)
  if base_style != nil
    base_style.apply(w)
    base_style.apply_typography(w)
  end
  __apply_kwargs(w, kwargs, true) if kwargs.length > 0
  __dsl_auto_add(w)
  w
end

#: () -> Switch
def switch_toggle
  w = Switch.new
  __dsl_auto_add(w)
  w
end

#: () -> ProgressBar
def progress_bar
  w = ProgressBar.new
  __dsl_auto_add(w)
  w
end

# --- Complex widget DSL functions ---

#: (Array labels, Array contents) -> Tabs
def tabs(labels, contents)
  w = Tabs.new(labels, contents)
  __dsl_auto_add(w)
  w
end

#: (untyped state) -> Tree
def tree(state)
  w = Tree.new(state)
  __dsl_auto_add(w)
  w
end

#: (untyped state) -> Calendar
def calendar(state)
  w = Calendar.new(state)
  __dsl_auto_add(w)
  w
end

#: (untyped body) -> Modal
def modal(body)
  w = Modal.new(body)
  __dsl_auto_add(w)
  w
end

# --- Chart DSL functions ---

#: (Array labels, Array data, Array legends) -> BarChart
def bar_chart(labels, data, legends)
  w = BarChart.new(labels, data, legends)
  __dsl_auto_add(w)
  w
end

#: (Array labels, Array data, Array legends) -> LineChart
def line_chart(labels, data, legends)
  w = LineChart.new(labels, data, legends)
  __dsl_auto_add(w)
  w
end

#: (Array labels, Array values) -> PieChart
def pie_chart(labels, values)
  w = PieChart.new(labels, values)
  __dsl_auto_add(w)
  w
end

#: (Array x_data, Array y_data, Array legends) -> ScatterChart
def scatter_chart(x_data, y_data, legends)
  w = ScatterChart.new(x_data, y_data, legends)
  __dsl_auto_add(w)
  w
end

#: (Array labels, Array data, Array legends) -> AreaChart
def area_chart(labels, data, legends)
  w = AreaChart.new(labels, data, legends)
  __dsl_auto_add(w)
  w
end

#: (Array labels, Array data, Array legends) -> StackedBarChart
def stacked_bar_chart(labels, data, legends)
  w = StackedBarChart.new(labels, data, legends)
  __dsl_auto_add(w)
  w
end

#: (Float value, Float min_val, Float max_val) -> GaugeChart
def gauge_chart(value, min_val, max_val)
  w = GaugeChart.new(value, min_val, max_val)
  __dsl_auto_add(w)
  w
end

#: (Array x_labels, Array y_labels, Array data) -> HeatmapChart
def heatmap_chart(x_labels, y_labels, data)
  w = HeatmapChart.new(x_labels, y_labels, data)
  __dsl_auto_add(w)
  w
end

# --- Generic embed function ---
# Use this to add any pre-created widget to the current DSL parent.
#: (untyped w) -> untyped
def embed(w)
  __dsl_auto_add(w)
  w
end
