# API Reference

## A. Castella UI

Castella is a reactive GUI framework for Konpeito's JVM backend. It uses JWM + Skija for cross-platform rendering and provides a component model with observable state management.

### A1. Getting Started Pattern

Every Castella app follows this structure:

```ruby
class MyApp < Component
  def initialize
    super
    @count = state(0)     # reactive state
  end

  def view
    Column(
      Text("Hello"),
      Button("Click").on_click { @count += 1 }
    )
  end
end

$theme = theme_tokyo_night
frame = JWMFrame.new("My App", 800, 600)
app = App.new(frame, MyApp.new)
app.run
```

**Key concepts:**
- Subclass `Component` and override `view()` to return a widget tree.
- Call `state(initial_value)` to create reactive state. When state changes, `view()` is re-called automatically.
- Set `$theme` to a theme object before creating the frame.
- `JWMFrame` creates the native window. `App` connects the window to your root component.

**DSL alternative:**

Instead of `Column(...)` constructor calls, use lowercase block functions with keyword arguments:

```ruby
def view
  column(padding: 16.0) do
    text "Hello", font_size: 24.0
    button("Click") { @count += 1 }
  end
end
```

Keyword arguments (`padding:`, `font_size:`, `color:`, etc.) configure layout and styling directly. Style objects via the `s` helper are also supported as the first positional argument.

---

### A2. Layout Widgets

#### Column

Stacks children vertically.

```ruby
# Constructor style
Column(child1, child2, child3)

# DSL style
column(style) { ... }
```

| Method | Description |
|---|---|
| `.spacing(Float)` | Gap between children in pixels |
| `.scrollable` | Enable vertical scrolling |
| `.pin_to_bottom` | Auto-scroll to bottom when content grows |

#### Row

Stacks children horizontally.

```ruby
Row(child1, child2, child3)
row(style) { ... }
```

| Method | Description |
|---|---|
| `.spacing(Float)` | Gap between children in pixels |
| `.scrollable` | Enable horizontal scrolling |
| `.pin_to_end` | Auto-scroll to end when content grows |

#### Container

Wraps a single child with background, border, and padding.

```ruby
Container(child)
container(style) { ... }
```

| Method | Description |
|---|---|
| `.bg_color(Integer)` | Background color (ARGB hex) |
| `.border_color(Integer)` | Border color (ARGB hex) |
| `.border_radius(Float)` | Corner radius in pixels |
| `.padding(top, right, bottom, left)` | Inner padding |

#### Box

Overlay layout — children are stacked at the same position, layered by z-index.

```ruby
Box(child1, child2)
box(style) { ... }
```

#### Spacer

Flexible empty space that expands to fill available room.

```ruby
Spacer()
spacer
```

Use `Spacer()` between widgets to push them apart. For fixed spacing, use `.fixed_width(w)` or `.fixed_height(h)`.

#### Divider

Visual separator line.

```ruby
Divider()
divider
```

| Method | Description |
|---|---|
| `.color(Integer)` | Line color (ARGB hex) |

---

### A3. Display Widgets

#### Text

Displays a single line of text.

```ruby
Text("Hello, world!")
text("Hello, world!", style)
```

| Method | Description |
|---|---|
| `.font_size(Float)` | Font size in pixels |
| `.font_family(String)` | Font family name |
| `.color(Integer)` | Text color (ARGB hex) |
| `.bold` | Bold weight |
| `.italic` | Italic style |
| `.align(Integer)` | Alignment: `TEXT_ALIGN_LEFT` (0), `TEXT_ALIGN_CENTER` (1), `TEXT_ALIGN_RIGHT` (2) |
| `.kind(Integer)` | Semantic color: `KIND_NORMAL` (0), `KIND_INFO` (1), `KIND_SUCCESS` (2), `KIND_WARNING` (3), `KIND_DANGER` (4) |

#### MultilineText

Displays multi-line text with word wrapping.

```ruby
MultilineText("Long text content...")
multiline_text("Long text content...", style)
```

| Method | Description |
|---|---|
| `.font_size(Float)` | Font size |
| `.font_family(String)` | Font family |
| `.color(Integer)` | Text color |
| `.kind(Integer)` | Semantic color |
| `.padding(Float)` | Inner padding |
| `.line_spacing(Float)` | Space between lines |
| `.wrap_text(bool)` | Enable/disable word wrapping |

#### Markdown

Renders Markdown-formatted text.

```ruby
Markdown("# Heading\n\n**Bold** and *italic*")
markdown("# Heading", style)
```

| Method | Description |
|---|---|
| `.font_size(Float)` | Base font size |
| `.enable_mermaid(bool)` | Enable Mermaid diagram rendering |

#### Image

Displays an image from a local file.

```ruby
ImageWidget("path/to/image.png")
image("path/to/image.png", style)
```

| Method | Description |
|---|---|
| `.fit(Integer)` | Fit mode: `IMAGE_FIT_FILL` (0), `IMAGE_FIT_CONTAIN` (1), `IMAGE_FIT_COVER` (2) |

#### NetImage

Downloads and displays an image from a URL.

```ruby
NetImage("https://example.com/image.png")
net_image("https://example.com/image.png", style)
```

| Method | Description |
|---|---|
| `.fit(Integer)` | Fit mode (same as Image) |
| `.placeholder_color(Integer)` | Color shown while loading |

---

### A4. Input Widgets

#### Button

Clickable button with a text label.

```ruby
Button("Click me").on_click { puts "clicked" }
button("Click me", style) { puts "clicked" }
```

| Method | Description |
|---|---|
| `.on_click { }` | Click handler block |
| `.font_size(Float)` | Label font size |
| `.kind(Integer)` | Button style: normal, info, success, warning, danger |
| `.text_color(Integer)` | Label color |
| `.bg(Integer)` | Background color |

#### Input

Single-line text input field. Requires an `InputState` for state management.

```ruby
state = InputState.new("placeholder text")
Input(state).on_change { puts state.value }
input(state, style)
```

| Method | Description |
|---|---|
| `.on_change { }` | Called when text changes |
| `.font_size(Float)` | Font size |

`InputState` methods:

| Method | Description |
|---|---|
| `.value` | Current text content |
| `.set(String)` | Set text programmatically |
| `.get_cursor` | Current cursor position |
| `.select_all` | Select all text |

#### MultilineInput

Multi-line text input with cursor, selection, and IME support. Requires a `MultilineInputState`.

```ruby
state = MultilineInputState.new("initial text")
MultilineInput(state).on_change { puts state.value }
multiline_input(state, style)
```

| Method | Description |
|---|---|
| `.on_change { }` | Called when text changes |
| `.on_key { }` | Called on key events |
| `.font_size(Float)` | Font size |
| `.font_family(String)` | Font family |

`MultilineInputState` methods:

| Method | Description |
|---|---|
| `.value` / `.get_text` | Current text content |
| `.set_text(String)` | Set text programmatically |
| `.get_lines` | Array of text lines |
| `.get_row` / `.get_col` | Cursor position |
| `.select_all` | Select all text |

#### Checkbox

Toggleable checkbox with a text label.

```ruby
Checkbox("Enable feature").checked(true).on_toggle { |checked| puts checked }
checkbox("Enable feature", style)
```

| Method | Description |
|---|---|
| `.checked(bool)` | Set initial checked state |
| `.is_checked` | Get current state |
| `.on_toggle { |bool| }` | Called when toggled |
| `.font_size(Float)` | Label font size |
| `.check_color(Integer)` | Checkmark color |
| `.text_color(Integer)` | Label color |

#### Switch

ON/OFF toggle switch.

```ruby
Switch().with_on(true).on_change { |is_on| puts is_on }
switch_toggle(style)
```

| Method | Description |
|---|---|
| `.with_on(bool)` | Set initial state |
| `.is_on` | Get current state |
| `.on_change { |bool| }` | Called when toggled |

#### Slider

Draggable range input.

```ruby
Slider(0, 100).with_value(50).on_change { |val| puts val }
slider(0, 100, style)
```

| Method | Description |
|---|---|
| `.with_value(Integer)` | Set initial value |
| `.get_value` | Get current value |
| `.on_change { }` | Called when value changes |

#### RadioButtons

Exclusive selection from a list of options.

```ruby
RadioButtons(["Option A", "Option B", "Option C"])
  .with_selected(0)
  .on_change { |index| puts index }
radio_buttons(["Option A", "Option B"], style)
```

| Method | Description |
|---|---|
| `.with_selected(Integer)` | Set initial selection index |
| `.get_selected` | Get current selection index |
| `.on_change { |Integer| }` | Called when selection changes |

#### ProgressBar

Visual progress indicator (0.0 to 1.0).

```ruby
ProgressBar().with_value(0.75)
progress_bar(style)
```

| Method | Description |
|---|---|
| `.with_value(Float)` | Set progress (0.0 to 1.0) |
| `.set_value(Float)` | Update progress |
| `.get_value` | Get current progress |
| `.fill_color(Integer)` | Bar fill color |

---

### A5. Complex Widgets

#### Tabs

Tabbed container with header buttons that switch between content panels.

```ruby
Tabs(
  ["Tab 1", "Tab 2"],
  [content_widget_1, content_widget_2]
)
tabs(["Tab 1", "Tab 2"], [widget1, widget2], style)
```

| Method | Description |
|---|---|
| `.select_tab(Integer)` | Switch to tab by index |

#### DataTable

Sortable, scrollable table with virtual scrolling for large datasets.

```ruby
DataTable(
  ["Name", "Age", "City"],              # column headers
  [150.0, 60.0, 120.0],                 # column widths
  [                                      # row data
    ["Alice", "30", "Tokyo"],
    ["Bob", "25", "Osaka"]
  ]
)
data_table(columns, widths, rows, style)
```

| Method | Description |
|---|---|
| `.font_size(Float)` | Body font size |
| `.header_font_size(Float)` | Header font size |
| `.set_data(cols, widths, rows)` | Replace all data |
| `.set_rows(rows)` | Replace row data only |
| `.selected_row` | Get selected row index |
| `.on_select { |Integer| }` | Called when a row is selected |
| `.on_sort { |col, dir| }` | Called when a column header is clicked for sorting |

Sort directions: `DT_SORT_NONE` (0), `DT_SORT_ASC` (1), `DT_SORT_DESC` (2).

#### Tree

Hierarchical tree view with expand/collapse.

```ruby
Tree(items)
tree(items, style)
```

| Method | Description |
|---|---|
| `.font_size(Float)` | Font size |
| `.indent_width(Float)` | Indentation per level |
| `.on_select { }` | Called when an item is selected |
| `.on_expand { }` | Called when a node is expanded |
| `.on_collapse { }` | Called when a node is collapsed |

#### Calendar

Date picker with day, month, and year views.

```ruby
Calendar(2026, 2, 15)     # year, month, day
calendar(style)
```

| Method | Description |
|---|---|
| `.with_selected(year, month, day)` | Set selected date |
| `.get_selected_date` | Get `[year, month, day]` array |
| `.set_view_mode(Integer)` | `CAL_DAYS` (0), `CAL_MONTHS` (1), `CAL_YEARS` (2) |
| `.on_change { |y, m, d| }` | Called when date is selected |

#### Modal

Overlay dialog with backdrop.

```ruby
Modal(content_widget).title("Confirm").dialog_size(400.0, 300.0)
modal(content_widget)
```

| Method | Description |
|---|---|
| `.title(String)` | Dialog title |
| `.dialog_size(Float, Float)` | Width and height |
| `.open_modal` | Show the modal |
| `.close_modal` | Hide the modal |
| `.is_open` | Check if modal is visible |

---

### A6. Chart Widgets

All chart widgets are available through DSL functions.

#### Bar Chart

```ruby
bar_chart(
  ["Jan", "Feb", "Mar"],                           # x-axis labels
  [[10.0, 20.0, 15.0], [5.0, 15.0, 25.0]],        # data series
  ["Sales", "Returns"]                              # legend labels
)
```

#### Line Chart

```ruby
line_chart(labels, data_series, legends)
```

#### Area Chart

```ruby
area_chart(labels, data_series, legends)
```

#### Stacked Bar Chart

```ruby
stacked_bar_chart(labels, data_series, legends)
```

#### Pie Chart

```ruby
pie_chart(
  ["Ruby", "Python", "Go"],     # labels
  [45.0, 30.0, 25.0]            # values
)
```

#### Scatter Chart

```ruby
scatter_chart(
  [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]],    # x data per series
  [[10.0, 20.0, 30.0], [15.0, 25.0, 35.0]], # y data per series
  ["Series A", "Series B"]                   # legend labels
)
```

#### Gauge Chart

```ruby
gauge_chart(75.0, 0.0, 100.0)   # value, min, max
```

#### Heatmap Chart

```ruby
heatmap_chart(
  ["Mon", "Tue", "Wed"],                   # x labels
  ["Morning", "Afternoon"],                # y labels
  [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]     # data grid
)
```

---

### A7. Style System

Styles configure layout and appearance. Create a style with `s` (DSL helper) or `Style.new`, then chain methods:

```ruby
my_style = s.font_size(18.0).bold.color(0xFFC0CAF5).padding(8.0)
```

Styles are composable:

```ruby
base = s.font_size(14.0).color(0xFFC0CAF5)
header = base + s.bold.font_size(24.0)      # combines both
```

#### Layout properties

| Method | Description |
|---|---|
| `.width(Float)` / `.fixed_width(Float)` | Fixed width in pixels |
| `.height(Float)` / `.fixed_height(Float)` | Fixed height in pixels |
| `.size(Float, Float)` | Fixed width and height |
| `.expanding` | Expand to fill available space (both axes) |
| `.expanding_width` | Expand horizontally only |
| `.expanding_height` | Expand vertically only |
| `.flex(Integer)` | Flex factor for proportional sizing |
| `.fit_content` | Size to content |
| `.padding(Float)` | Uniform padding on all sides |
| `.spacing(Float)` | Gap between children (Column/Row) |

#### Visual properties

| Method | Description |
|---|---|
| `.bg_color(Integer)` | Background color (ARGB hex) |
| `.border_color(Integer)` | Border color (ARGB hex) |
| `.border_radius(Float)` | Corner radius |

#### Typography properties

| Method | Description |
|---|---|
| `.font_size(Float)` | Font size in pixels |
| `.font_family(String)` | Font family name |
| `.color(Integer)` / `.text_color(Integer)` | Text color (ARGB hex) |
| `.bold` | Bold weight |
| `.italic` | Italic style |
| `.align(Integer)` | Text alignment (0=left, 1=center, 2=right) |
| `.kind(Integer)` | Semantic color (0=normal, 1=info, 2=success, 3=warning, 4=danger) |

#### Scroll properties

| Method | Description |
|---|---|
| `.scrollable` | Enable scrolling |
| `.pin_to_bottom` | Auto-scroll to bottom (Column) |
| `.pin_to_end` | Auto-scroll to end (Row) |

#### Color format

Colors use ARGB hex format: `0xAARRGGBB`

```ruby
0xFFFFFFFF    # white, fully opaque
0xFF000000    # black, fully opaque
0x80FF0000    # red, 50% transparent
0xFFC0CAF5    # Tokyo Night text color
```

---

### A8. State Management

#### State

Observable value holder. When mutated, all observing components re-render.

```ruby
@count = state(0)           # create in Component#initialize
@count.value                # read: 0
@count.set(5)               # write: triggers re-render
@count += 1                 # shorthand for set(value + 1)
@count -= 1                 # shorthand for set(value - 1)
```

#### ListState

Observable array for dynamic lists.

```ruby
@items = ListState.new(["Apple", "Banana"])

@items.length               # 2
@items[0]                   # "Apple"
@items[1] = "Cherry"        # replace element
@items.push("Date")         # append
@items.pop                  # remove last
@items.delete_at(0)         # remove at index
@items.clear                # remove all
@items.set(["X", "Y"])      # replace entire list
@items.each { |item| ... }  # iterate
```

#### ScrollState

Observable scroll position.

```ruby
@scroll = ScrollState.new

@scroll.x                   # horizontal offset
@scroll.y                   # vertical offset
@scroll.set_x(100.0)
@scroll.set_y(200.0)
@scroll.set(100.0, 200.0)
```

#### InputState

State for single-line text input widgets. See [Input widget](#input) for details.

```ruby
@input = InputState.new("placeholder")
@input.value                # current text
@input.set("new text")      # set text programmatically
```

#### MultilineInputState

State for multi-line text input widgets. See [MultilineInput widget](#multilineinput) for details.

```ruby
@editor = MultilineInputState.new("initial text")
@editor.value               # current text
@editor.set_text("new")     # set text programmatically
```

---

### A9. Themes

Set `$theme` before creating the frame:

```ruby
$theme = theme_tokyo_night    # dark theme (default)
$theme = theme_light          # light theme
$theme = theme_nord           # Nord palette
$theme = theme_dracula        # Dracula palette
$theme = theme_catppuccin     # Catppuccin palette
```

#### Theme properties

Use theme colors in styles for consistent theming:

```ruby
text "Hello", color: $theme.text_primary
container(bg_color: $theme.bg_secondary) { ... }
button("OK", kind: KIND_SUCCESS)
```

| Property | Description |
|---|---|
| `.bg_canvas` | Main canvas background |
| `.bg_primary` | Primary surface background |
| `.bg_secondary` | Secondary surface background |
| `.bg_overlay` | Overlay/modal background |
| `.text_primary` | Primary text color |
| `.text_secondary` | Secondary/muted text color |
| `.accent` | Accent/highlight color |
| `.info` | Info semantic color |
| `.error` | Error semantic color |
| `.success` | Success semantic color |
| `.warning` | Warning semantic color |
| `.border` | Default border color |
| `.border_focus` | Focused element border color |
| `.font_family` | Default font family name |
| `.font_size_sm` / `.font_size_md` / `.font_size_lg` / `.font_size_xl` | Font size presets |
| `.spacing_xs` / `.spacing_sm` / `.spacing_md` / `.spacing_lg` | Spacing presets |
| `.border_radius` | Default corner radius |
| `.scrollbar_bg` / `.scrollbar_fg` | Scrollbar colors |
| `.bg_selected` | Selected item background |

---

### A10. Event Handling

Widgets support event callbacks via chainable methods:

```ruby
Button("Click").on_click { puts "clicked" }
Checkbox("Toggle").on_toggle { |checked| puts checked }
Slider(0, 100).on_change { |value| puts value }
Input(state).on_change { puts state.value }
```

For low-level event handling, override methods on your Component or custom Widget subclass:

| Method | Description |
|---|---|
| `mouse_down(MouseEvent)` | Mouse button pressed |
| `mouse_up(MouseEvent)` | Mouse button released |
| `mouse_drag(MouseEvent)` | Mouse moved while button held |
| `mouse_over` | Mouse entered widget bounds |
| `mouse_out` | Mouse left widget bounds |
| `mouse_wheel(WheelEvent)` | Scroll wheel event |
| `input_char(String)` | Character typed |
| `input_key(key_code, modifiers)` | Key pressed |
| `focused` | Widget received focus |
| `unfocused` | Widget lost focus |

---

### A11. Common Widget Methods

All widgets inherit these methods from the base `Widget` class:

| Method | Description |
|---|---|
| `.fixed_width(Float)` | Set fixed width |
| `.fixed_height(Float)` | Set fixed height |
| `.fixed_size(Float, Float)` | Set fixed width and height |
| `.fit_content` | Size to content |
| `.flex(Integer)` | Flex factor |
| `.padding(top, right, bottom, left)` | Inner padding |
| `.z_index(Integer)` | Z-order for overlapping widgets |
| `.tab_index(Integer)` | Tab navigation order |
| `.focusable(bool)` | Whether widget can receive focus |

---

## B. Native Data Structures (LLVM Backend)

These types provide high-performance data handling by bypassing Ruby's object model. They are available when compiling with the LLVM/native backend.

### B1. NativeArray[T]

Contiguous unboxed array. Element types: `Integer`, `Float`, or `NativeClass`.

```rbs
class NativeArray[T]
  def self.new: (Integer size) -> NativeArray[T]
  def []: (Integer index) -> T
  def []=: (Integer index, T value) -> T
  def length: () -> Integer
end
```

```ruby
arr = NativeArray.new(1000)
arr[0] = 3.14
arr[0]              # => 3.14 (unboxed double)
arr.length          # => 1000
```

Supports negative indexing: `arr[-1]` is the last element.

**Enumerable methods:** `each`, `map`, `select`, `reject`, `reduce`, `find`, `any?`, `all?`, `none?`, `sum`, `min`, `max`.

### B2. NativeHash[K,V]

Open-addressing hash map with linear probing.

**Key types:** `String`, `Symbol`, `Integer`
**Value types:** `Integer`, `Float`, `Bool`, `String`, `Object`, `Array`, `Hash`, `NativeClass`

```rbs
class NativeHash[K, V]
  def self.new: () -> NativeHash[K, V]
  def []: (K key) -> V
  def []=: (K key, V value) -> V
  def size: () -> Integer
  def has_key?: (K key) -> bool
  def delete: (K key) -> V
  def keys: () -> Array
  def values: () -> Array
  def clear: () -> NativeHash[K, V]
end
```

```ruby
h = NativeHash.new
h[1] = 100
h[2] = 200
h.has_key?(1)       # => true
h.size              # => 2
h.delete(1)
```

Auto-resizes at 75% load factor.

### B3. NativeClass

Classes with RBS field definitions are automatically compiled as native structs (no annotation needed).

**Supported field types:**
- Unboxed: `Integer` (i64), `Float` (double), `Bool` (i8)
- VALUE (GC-managed): `String`, `Array`, `Hash`, `Object`

```rbs
class Point
  @x: Float
  @y: Float
  def self.new: () -> Point
  def x: () -> Float
  def x=: (Float value) -> Float
  def y: () -> Float
  def y=: (Float value) -> Float
end
```

```ruby
p = Point.new
p.x = 3.0
p.y = 4.0
p.x * p.x + p.y * p.y   # => 25.0 (unboxed arithmetic)
```

### B4. StaticArray[T,N]

Fixed-size array allocated on the stack (no heap allocation, no GC pressure).

```rbs
class StaticArray4Float
  def self.new: () -> StaticArray4Float
  def self.new: (Float value) -> StaticArray4Float
  def []: (Integer index) -> Float
  def []=: (Integer index, Float value) -> Float
  def size: () -> Integer
end
```

Name encodes type and size: `StaticArray4Float`, `StaticArray16Int`, etc.

```ruby
arr = StaticArray4Float.new(0.0)
arr[0] = 1.0
arr[1] = 2.0
arr.size             # => 4 (compile-time constant)
```

### B5. Slice[T]

Bounds-checked pointer view with sub-slicing (zero-copy).

```rbs
class SliceInt64
  def self.new: (Integer size) -> SliceInt64
  def self.empty: () -> SliceInt64
  def []: (Integer index) -> Integer
  def []=: (Integer index, Integer value) -> Integer
  def []: (Integer start, Integer count) -> SliceInt64
  def size: () -> Integer
  def copy_from: (SliceInt64 source) -> SliceInt64
  def fill: (Integer value) -> SliceInt64
end
```

```ruby
s = SliceInt64.new(10)
s[3] = 42
window = s[3, 4]    # zero-copy sub-slice of 4 elements starting at index 3
window[0]            # => 42 (same memory as s[3])
```

### B6. ByteBuffer / StringBuffer / ByteSlice

Buffer types for I/O operations.

**ByteBuffer** — growable byte array:

```ruby
buf = ByteBuffer.new(1024)
buf << 65                    # append byte
buf.write("hello")           # append string bytes
buf.index_of(104)            # find byte (memchr)
buf.to_s                     # convert to Ruby String
```

**StringBuffer** — efficient string concatenation:

```ruby
buf = StringBuffer.new(256)
buf << "Hello, "
buf << "world!"
buf.to_s                     # => "Hello, world!"
```

**ByteSlice** — zero-copy view into a ByteBuffer:

```ruby
slice = buf.slice(0, 5)
slice[0]                     # first byte
slice.length
slice.to_s                   # => "Hello"
```

### B7. NativeString

UTF-8 string with byte-level and character-level operations.

```ruby
ns = NativeString.from("Hello, world!")
ns.byte_length               # => 13
ns.byte_at(0)                # => 72 (ASCII 'H')
ns.byte_index_of(32)         # => 5 (first space)
ns.byte_slice(0, 5).to_s     # => "Hello" (zero-copy)

ns.char_length               # => 13
ns.char_at(0)                # => "H"
ns.ascii_only?               # => true
ns.starts_with?("Hello")     # => true
ns.to_s                      # => Ruby String
```

### B8. @struct (Value Types)

Value types are passed by value (copied) rather than by reference. Best for small structs (2-4 fields).

```rbs
# @struct
class Point
  @x: Float
  @y: Float
  def self.new: () -> Point
  def x: () -> Float
  def y: () -> Float
end
```

**Constraints:** Only primitive fields (Integer, Float, Bool). No VALUE fields (String, Array, etc.). Maximum 128 bytes.

---

## C. Standard Library

### C1. KonpeitoJSON

JSON parsing and generation powered by yyjson.

```ruby
# Parse JSON string
data = KonpeitoJSON.parse('{"name": "Alice", "age": 30}')

# Generate JSON string
json = KonpeitoJSON.generate(data)

# Pretty-print with indentation
json = KonpeitoJSON.generate_pretty(data, 2)

# Parse with options
data = KonpeitoJSON.parse(text, KonpeitoJSON::ALLOW_COMMENTS | KonpeitoJSON::ALLOW_TRAILING_COMMAS)
```

| Method | Description |
|---|---|
| `parse(String) -> untyped` | Parse JSON string |
| `parse(String, Integer) -> untyped` | Parse with flags |
| `generate(untyped) -> String` | Serialize to compact JSON |
| `generate_pretty(untyped, Integer) -> String` | Serialize with indentation |

**Parse flags:**

| Constant | Description |
|---|---|
| `ALLOW_COMMENTS` | Allow `//` and `/* */` comments |
| `ALLOW_TRAILING_COMMAS` | Allow trailing commas in arrays/objects |
| `ALLOW_INF_NAN` | Allow `Infinity` and `NaN` values |

### C2. KonpeitoHTTP

HTTP client powered by libcurl.

```ruby
# Simple GET (returns body string)
body = KonpeitoHTTP.get("https://example.com")

# Simple POST
body = KonpeitoHTTP.post("https://example.com/api", '{"key": "value"}')

# GET with full response
resp = KonpeitoHTTP.get_response("https://example.com")
resp[:status]      # => 200
resp[:body]        # => "..."
resp[:headers]     # => { "content-type" => "text/html", ... }

# POST with full response and content type
resp = KonpeitoHTTP.post_response("https://example.com/api", body, "application/json")

# Custom request
resp = KonpeitoHTTP.request("PUT", "https://example.com/api/1", body, {
  "Authorization" => "Bearer token",
  "Content-Type" => "application/json"
})
```

| Method | Description |
|---|---|
| `get(String) -> String` | GET request, returns body |
| `post(String, String) -> String` | POST request, returns body |
| `get_response(String) -> Hash` | GET with status/headers/body |
| `post_response(String, String, String?) -> Hash` | POST with response details |
| `request(String, String, String?, Hash?) -> Hash` | Custom method/headers |

Features: automatic redirect following, 30-second timeout. Falls back to Ruby's `net/http` if libcurl is unavailable.

### C3. KonpeitoCrypto

Cryptographic operations powered by OpenSSL.

```ruby
# Hash functions (hex output)
KonpeitoCrypto.sha256("hello")             # => "2cf24dba..."
KonpeitoCrypto.sha512("hello")             # => "9b71d224..."

# Binary output
KonpeitoCrypto.sha256_binary("hello")      # => binary string

# HMAC
KonpeitoCrypto.hmac_sha256("secret", "message")
KonpeitoCrypto.hmac_sha512("secret", "message")

# Random bytes
KonpeitoCrypto.random_bytes(32)            # => 32 random bytes
KonpeitoCrypto.random_hex(16)              # => 32-char hex string

# Timing-safe comparison
KonpeitoCrypto.secure_compare(a, b)        # => true/false
```

| Method | Description |
|---|---|
| `sha256(String) -> String` | SHA-256 hash (hex) |
| `sha512(String) -> String` | SHA-512 hash (hex) |
| `sha256_binary(String) -> String` | SHA-256 hash (binary) |
| `sha512_binary(String) -> String` | SHA-512 hash (binary) |
| `hmac_sha256(String, String) -> String` | HMAC-SHA256 (hex) |
| `hmac_sha512(String, String) -> String` | HMAC-SHA512 (hex) |
| `hmac_sha256_binary(String, String) -> String` | HMAC-SHA256 (binary) |
| `hmac_sha512_binary(String, String) -> String` | HMAC-SHA512 (binary) |
| `random_bytes(Integer) -> String` | Cryptographic random bytes |
| `random_hex(Integer) -> String` | Cryptographic random hex string |
| `secure_compare(String, String) -> bool` | Timing-safe string comparison |

Falls back to Ruby's `OpenSSL` gem if the native library is unavailable.

### C4. KonpeitoCompression

Compression and decompression powered by zlib.

```ruby
# Gzip (RFC 1952)
compressed = KonpeitoCompression.gzip("hello world")
original = KonpeitoCompression.gunzip(compressed)

# Raw deflate (RFC 1951)
compressed = KonpeitoCompression.deflate("hello world")
compressed = KonpeitoCompression.deflate("hello world", KonpeitoCompression::BEST_COMPRESSION)
original = KonpeitoCompression.inflate(compressed)

# Zlib format (RFC 1950)
compressed = KonpeitoCompression.zlib_compress("hello world")
original = KonpeitoCompression.zlib_decompress(compressed)
original = KonpeitoCompression.zlib_decompress(compressed, 1048576)   # max output size
```

| Method | Description |
|---|---|
| `gzip(String) -> String` | Gzip compress |
| `gunzip(String) -> String` | Gzip decompress |
| `deflate(String, Integer?) -> String` | Raw deflate compress |
| `inflate(String) -> String` | Raw deflate decompress |
| `zlib_compress(String) -> String` | Zlib format compress |
| `zlib_decompress(String, Integer?) -> String` | Zlib format decompress |

**Compression level constants:**

| Constant | Value | Description |
|---|---|---|
| `BEST_SPEED` | 1 | Fastest compression |
| `BEST_COMPRESSION` | 9 | Smallest output |
| `DEFAULT_COMPRESSION` | -1 | Default balance |

Falls back to Ruby's `Zlib` module if the native library is unavailable.

---

## D. Annotations Quick Reference

Konpeito uses RBS annotations (`%a{...}`) to control native code generation.

| Annotation | Target | Description |
|---|---|---|
| `%a{native}` | class | Compile as native struct (default for classes with RBS fields) |
| `%a{native: vtable}` | class | Native struct with vtable for dynamic dispatch |
| `%a{boxed}` | class | Use Ruby VALUE type (for CRuby interop) |
| `%a{struct}` | class | Value type (stack-allocated, passed by value) |
| `%a{extern}` | class | Wrapper for external C struct |
| `%a{simd}` | class | SIMD vectorization (all Float fields, 2/3/4/8/16 fields) |
| `%a{ffi: "lib"}` | module/class | Link external C library |
| `%a{cfunc}` | method | Call C function directly (method name = function name) |
| `%a{cfunc: "name"}` | method | Call C function directly (explicit function name) |
| `%a{jvm_static}` | method | Generate as JVM static method |

### Example

```rbs
%a{ffi: "libm"}
module MathLib
  %a{cfunc}
  def self.sin: (Float) -> Float

  %a{cfunc: "sqrt"}
  def self.square_root: (Float) -> Float
end
```

```ruby
module MathLib
  def self.sin(x) = nil
  def self.square_root(x) = nil
end

MathLib.sin(3.14159 / 2)      # => 1.0 (direct C call)
MathLib.square_root(16.0)     # => 4.0 (direct C call)
```
