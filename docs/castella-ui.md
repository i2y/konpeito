# Castella UI — Konpeito/JVM Cross-Platform GUI

Based on a port of [Castella for Python](https://github.com/i2y/castella) to Konpeito's JVM backend.
Uses JWM (Java Window Management) + Skija (Skia Java bindings) as the rendering backend.
Leverages Konpeito's RBS-free Java Interop to run UI code written in Ruby on the JVM.

---

## Table of Contents

1. [Current Status](#current-status)
2. [Architecture](#architecture)
3. [KUIRuntime — Java Runtime](#kuiruntime--java-runtime)
4. [Low-Level API](#low-level-api)
5. [Framework Layer](#framework-layer)
6. [Framework Counter Demo](#framework-counter-demo)
7. [Dynamic Dispatch via invokedynamic](#dynamic-dispatch-via-invokedynamic)
8. [Setup and Execution](#setup-and-execution)
9. [Technical Constraints and Workarounds](#technical-constraints-and-workarounds)

---

## Current Status

All layers are complete. The framework layer (Widget/Layout/Component/State) plus
scrolling, additional widgets (Checkbox/Tabs/Modal/MultilineText/Markdown), FocusManager, and the theme system are all implemented.

| Content | Status |
|---------|--------|
| KUIRuntime + hello/counter demo | Complete |
| Widget / State / Component foundation | Complete |
| Column / Row / Box layout | Complete |
| Text / Button / Input / Container / Divider widgets | Complete |
| Theme system (Tokyo Night) | Complete |
| JWMFrame + App integration | Complete |
| Scrolling (wheel connection, scrollbar rendering, ScrollState integration) | Complete |
| Widget expansion (Checkbox, Spacer improvements) | Complete |
| Framework enhancements (FocusManager, Tabs, Modal) | Complete |
| Styling (Kind variants, 4 theme presets, full widget theme support) | Complete |
| Text display expansion (MultilineText, Markdown) | Complete |

---

## Architecture

```
Ruby Source Code (.rb)
        │
   Konpeito Compiler
   (Prism → HM Type Inference → HIR → JVM Generator)
        │
        ▼
   .jar (JVM Bytecode)
        │
   Java 21 Runtime
        │
        ▼
┌─────────────────────┐
│   KUIRuntime.java   │  ← JWM + Skija wrapper
│   (konpeito/ui/)    │
├─────────────────────┤
│  JWM (Windowing)    │  ← Window management, events
├─────────────────────┤
│  Skija (Rendering)  │  ← Skia-based 2D drawing
├─────────────────────┤
│  Metal / D3D / GL   │  ← Platform GPU
└─────────────────────┘
```

**Current structure:**

```
User Ruby Code (Component#view)
        │
        ▼
Widget Tree (Column > Text, Button, ...)
        │
  [Layout Pass — Pure Ruby]
        │
        ▼
Position-Calculated Widgets
        │
  [Paint Pass — KUIRuntime calls (via invokedynamic)]
        │
        ▼
KUIRuntime (Java: JWM + Skija → GPU)

Event Flow:
JWM Event → KUIRuntime → SAM Callback → Ruby
  → Widget Hit Test → on_click block execution
  → State change → notify → Component.view() rebuild
  → requestFrame → Repaint on next frame
```

**Type resolution mechanism:**

Framework layer classes (`lib/konpeito/ui/`) have cases where HM type inference alone cannot
resolve all method types (block parameter types passed through blocks, dynamic widget tree construction, etc.).
Unresolved calls are resolved at runtime via `invokedynamic` + `RubyDispatch`.
This allows the framework to work without having to perfectly declare all types in RBS.

---

## KUIRuntime — Java Runtime

`KUIRuntime.java` is a frame-callback-based JWM + Skija wrapper.
No RBS files required — types are auto-detected through Konpeito's classpath introspection.

### Callback Interfaces

```java
public interface FrameCallback  { void call(); }
public interface MouseCallback  { void call(long type, double x, double y, long button); }
public interface KeyCallback    { void call(long type, long keyCode, long modifiers); }
public interface TextCallback   { void call(String text); }
public interface ScrollCallback { void call(double dx, double dy); }
public interface ResizeCallback { void call(double width, double height); }
```

Each interface is a SAM (Single Abstract Method), so Konpeito's Block-to-SAM conversion
(`invokedynamic` + `LambdaMetafactory`) automatically converts Ruby blocks.

### Drawing Methods

| Method | Description |
|--------|-------------|
| `clear(color)` | Clear the canvas |
| `fillRect(x, y, w, h, color)` | Fill rectangle |
| `strokeRect(x, y, w, h, color, sw)` | Stroke rectangle |
| `fillRoundRect(x, y, w, h, r, color)` | Fill rounded rectangle |
| `strokeRoundRect(x, y, w, h, r, color, sw)` | Stroke rounded rectangle |
| `fillCircle(cx, cy, r, color)` | Fill circle |
| `drawLine(x1, y1, x2, y2, color, w)` | Draw line |
| `drawText(text, x, y, fontFamily, fontSize, color)` | Draw text |

### Canvas State Operations

| Method | Description |
|--------|-------------|
| `save()` / `restore()` | Save/restore canvas state |
| `translate(dx, dy)` | Translate coordinate system |
| `clipRect(x, y, w, h)` | Clipping rectangle (negative width/height clamped to 0) |

### Text Measurement

| Method | Description |
|--------|-------------|
| `measureTextWidth(text, fontFamily, fontSize)` | Text width |
| `measureTextHeight(fontFamily, fontSize)` | Text height |
| `getTextAscent(fontFamily, fontSize)` | Height to baseline |

### Window Operations

| Method | Description |
|--------|-------------|
| `getWidth()` / `getHeight()` | Window size |
| `getScale()` | Display scale |
| `requestFrame()` | Request repaint |
| `run()` | Start event loop |

### Mouse Event `type` Values

| Value | Meaning |
|-------|---------|
| `0` | Mouse move |
| `1` | Button press |
| `2` | Button release |

---

## Low-Level API

An immediate-mode drawing model that directly calls KUIRuntime instance methods.

### Hello World

```ruby
# examples/castella_ui/hello.rb
runtime = Java::Konpeito::Ui::KUIRuntime.new("Hello Castella", 400, 300)

runtime.set_on_frame {
  runtime.clear(0xFF1A1B26)
  runtime.fill_round_rect(50.0, 50.0, 300.0, 60.0, 8.0, 0xFF7AA2F7)
  runtime.draw_text("Hello, Castella!", 100.0, 90.0, "default", 24.0, 0xFFFFFFFF)
}

runtime.run
```

### Counter (with click events)

```ruby
# examples/castella_ui/counter.rb — Low-level API version
runtime = Java::Konpeito::Ui::KUIRuntime.new("Counter", 400, 300)
count = 0

runtime.set_on_frame {
  runtime.clear(0xFF1A1B26)
  runtime.draw_text("Count: " + count.to_s, 140.0, 120.0, "default", 32.0, 0xFFC0CAF5)
  # Button drawing...
}

runtime.set_on_mouse { |type, x, y, button|
  if type == 1
    # Hit test (manual coordinate checking)
  end
}

runtime.run
```

### How Shared Mutable Capture Works

In counter.rb, the `count` variable is accessed from both the `set_on_frame` block (read) and
the `set_on_mouse` block (write). JVM's `invokedynamic` + `LambdaMetafactory` captures variables
by value copy, so normally variables cannot be shared between multiple blocks.

Konpeito solves this problem with a **static field approach**:

1. At compile time, detect variables that are "captured by multiple blocks and modified within a block"
   (`scan_shared_mutable_captures`)
2. Register such variables as `static` fields (`Ljava/lang/Object;`) on the main class
3. On assignment in outer scope: sync via `store` to local slot + `putstatic`
4. On read within block: fetch via `getstatic` + unbox
5. On assignment within block: update via box + `putstatic`

This way, when the count is changed in `set_on_mouse`, it is reflected on the next call of `set_on_frame`.

---

## Framework Layer

Declarative UI following the design of Python Castella.

### Core — Widget / State / Component

**Files:** `lib/konpeito/ui/core.rb` + `core.rbs`

| Class | Role |
|-------|------|
| `Widget` | Base class for all UI elements. Position, size, hit test, dirty flag, RenderNode, lifecycle |
| `Layout` | Widget with children. z-order-based hit testing and draw order |
| `Component` | Declaratively returns a widget tree via the `view()` method. Auto-rebuilds on State changes |
| `State` | Reactive value. `.set(v)` to change + notify all observers |
| `ListState` | Reactive list. Change notifications on push/pop/delete_at |
| `ScrollState` | Reactive scroll position |
| `ObservableBase` | Base class for Observer pattern. attach/detach/notify_observers |
| `Point` / `Size` / `Rect` | Geometry value objects |
| `MouseEvent` | Mouse event (position, button) |

**Size policy constants:**

| Constant | Value | Description |
|----------|-------|-------------|
| `FIXED` | 0 | Fixed size |
| `EXPANDING` | 1 | Distribute remaining space by flex ratio |
| `CONTENT` | 2 | Fit to content size |

**How State `+=` works:**
```ruby
class State
  def +(other)
    @value = @value + other
    notify_observers  # Notify all observers → Component.on_notify → view() rebuild
    self              # Returns self so @count = self → maintains the same State object
  end
end
```

Ruby's `@count += 1` expands to `@count = @count.+(1)`.
Since `State#+` returns `self`, `@count` continues to point to the same State object.

**RenderNode:**

Implemented in `lib/konpeito/ui/render_node.rb`. Handles widget draw caching and z-order management.

| Class | Role |
|-------|------|
| `RenderNodeBase` | Basic render node. Dirty flag (paint/layout) management |
| `LayoutRenderNode` | For Layout. Child z-order sorting, hit test order (reverse z-order) management |

### Layout — Column / Row / Box / Spacer

**Files:** `lib/konpeito/ui/column.rb`, `row.rb`, `box.rb`, `spacer.rb`

| Class | Direction | Role |
|-------|-----------|------|
| `Column` | Vertical | Arranges children vertically. FIXED/CONTENT measured, EXPANDING distributes remaining space by flex ratio |
| `Row` | Horizontal | Horizontal version of Column |
| `Box` | Stacked | Places all children at the same position (overlay) |
| `Spacer` | — | Flexible space. Can be fixed size via `.fixed_width()` / `.fixed_height()` |

**Layout algorithm (Column example):**
1. First pass: Measure FIXED/CONTENT children → calculate remaining space
2. Second pass: Distribute remaining space to EXPANDING children by flex ratio, determine positions for all children

**Top-level helper functions:**
```ruby
Column(child1, child2, ...)   # Syntactic sugar for Column.new + add()
Row(child1, child2, ...)
Spacer()
```

### Basic Widgets

**Files:** `lib/konpeito/ui/widgets/`

| Widget | File | Role |
|--------|------|------|
| `Text` | `text.rb` | Text display. Method chaining with `.font_size()` `.color()` `.align()` `.kind()` |
| `Button` | `button.rb` | Button. Event registration/style setting with `.on_click { ... }` `.kind()`. Hover/press state management |
| `Input` | `input.rb` | Text input. Focus management, cursor, arrow keys/Home/End/Delete, click position detection |
| `Checkbox` | `checkbox.rb` | Checkbox. Toggle event with `.on_toggle { \|checked\| ... }` |
| `Container` | `container.rb` | Wrapper with background color + border + padding + rounded corners |
| `Divider` | `divider.rb` | Horizontal separator line |
| `Tabs` | `tabs.rb` | Tab switching UI. Header rendering + active indicator + content switching |
| `Modal` | `modal.rb` | Overlay dialog. Backdrop + center alignment + close button |
| `MultilineText` | `multiline_text.rb` | Multi-line text display. Word wrap, line spacing, Kind support |
| `Markdown` | `markdown.rb` | Markdown rendering. Headings/bold/italic/code blocks/lists/links/blockquotes/horizontal rules |

**Text widget TextAlign:**

```ruby
# Text alignment constants
TEXT_ALIGN_LEFT = 0     # Left-aligned (default)
TEXT_ALIGN_CENTER = 1   # Center-aligned
TEXT_ALIGN_RIGHT = 2    # Right-aligned

# Usage example
Text("Hello").align(TEXT_ALIGN_CENTER).font_size(24).color(0xFFFFFFFF)
```

**Button event handling:**
```ruby
Button("Click me").on_click { puts "clicked!" }
```
- `mouse_down` sets press state, `mouse_up` executes click callback
- Background color changes on hover (using theme colors)

### Theme System

**File:** `lib/konpeito/ui/theme.rb`

Colors, font sizes, and spacing are managed through a global `$theme` object.
All widgets reference theme tokens for default colors (custom colors can also be set).

**Basic tokens:**

| Token | Description |
|-------|-------------|
| `bg_canvas` | Application-wide background color |
| `bg_primary` | Container/input field background color |
| `bg_secondary` | Secondary background color (hover, etc.) |
| `text_primary` | Main text color |
| `text_secondary` | Secondary text color (placeholders, etc.) |
| `accent` | Accent color (buttons, checkboxes, etc.) |
| `border` / `border_focus` | Border color / focused border color |
| `info` / `success` / `warning` / `error` | Semantic colors |

**Kind variants:**

| Constant | Value | Usage |
|----------|-------|-------|
| `KIND_NORMAL` | 0 | Default style |
| `KIND_INFO` | 1 | Information (blue tones) |
| `KIND_SUCCESS` | 2 | Success (green tones) |
| `KIND_WARNING` | 3 | Warning (yellow tones) |
| `KIND_DANGER` | 4 | Danger (red tones) |

```ruby
Button("Delete").kind(KIND_DANGER)   # Red button
Text("Success!").kind(KIND_SUCCESS)  # Green text
```

**Theme presets:**
- `theme_tokyo_night()` — Tokyo Night dark theme (default)
- `theme_nord()` — Nord theme
- `theme_dracula()` — Dracula theme
- `theme_catppuccin()` — Catppuccin theme

```ruby
$theme = theme_nord()  # Switch theme
```

### JWMFrame + App Integration

**Files:** `lib/konpeito/ui/frame.rb`, `app.rb`

| Class | Role |
|-------|------|
| `JWMFrame` | Wraps KUIRuntime. SAM callback registration, event loop, resize handling |
| `App` | Coordinates root widget resize, drawing, and event dispatch. Update queue management |

**App features:**
- Calls root widget's redraw in the frame callback
- Dispatches mouse events to the widget tree (reverse z-order hit testing)
- `post_update(widget)` adds to update queue, repaint on next frame
- `clear_widget_refs(widget)` cleans references of detached widgets

### Scroll Support

- **Scroll wheel connection**: `ScrollDeltaCallback` (2-parameter SAM interface) to avoid confusion with MouseCallback (4 parameters)
- **Column/Row scrolling**: `.scrollable` method enables scrolling, `mouse_wheel` + `mouse_drag` for scroll operations
- **Scrollbar rendering**: Calculates scrollbar position and size from viewport size and content size

### Widget Expansion

- **Checkbox**: Toggle operation, `.on_toggle { |checked| ... }` callback, hover state
- **Spacer improvement**: `.fixed_width()` / `.fixed_height()` to switch to FIXED mode

### Framework Enhancements

- **FocusManager**: Navigate between focusable widgets (`@focusable = true`) with Tab/Shift+Tab
- **Input enhancements**: Arrow keys (Left/Right), Home/End, Delete key support. Cursor position detection from click position (character width cache approach)
- **Tabs**: Tab header rendering + active tab indicator + content switching. Control with `select_tab(index)`
- **Modal**: Backdrop (semi-transparent overlay) + center-aligned dialog + close button (X) + backdrop click to close

### Styling

- **Kind variants**: `KIND_NORMAL`(0), `KIND_INFO`(1), `KIND_SUCCESS`(2), `KIND_WARNING`(3), `KIND_DANGER`(4)
- **4 theme presets**: Tokyo Night, Nord, Dracula, Catppuccin — all properties set via setter methods
- **Full widget theme support**: Button, Text, Input, Checkbox, Container, Divider, Tabs, Modal fetch colors from `$theme`
- **Button/Text Kind support**: `.kind(KIND_DANGER)` auto-applies kind-specific colors
- **Custom color priority**: Custom colors set via `.bg(c)` / `.color(c)` take precedence over theme

### Text Display Expansion

**MultilineText widget** (`lib/konpeito/ui/widgets/multiline_text.rb`):

- Multi-line text display. Splits lines at `"\n"`, optional word wrap
- Method chaining with `.font_size(s)` `.color(c)` `.padding(p)` `.line_spacing(s)` `.wrap_text(true)` `.kind(k)`
- `measure()` calculates word wrap based on `@width` (no wrap when width is 0)
- Theme support: Kind variants auto-change background and text colors

```ruby
# Basic usage
MultilineText("Line 1\nLine 2\nLine 3").padding(8.0)

# Word wrap enabled
MultilineText("Long paragraph text...").wrap_text(true).padding(12.0)

# Kind variant
MultilineText("Success!").kind(KIND_SUCCESS).padding(8.0)
```

**Markdown widget** (`lib/konpeito/ui/widgets/markdown.rb` + `lib/konpeito/ui/markdown/`):

- Pure Ruby Markdown parser + cursor-based renderer
- Supported syntax: Headings (H1-H6), bold (`**`), italic (`*`), strikethrough (`~~`), inline code, code blocks, ordered/unordered lists, links, blockquotes, horizontal rules
- **Bold**: Faux-bold (double-drawn at x and x+0.5)
- **Italic**: Color differentiation (theme accent color tones)
- **Inline code**: With background + code color
- Designed for use within a scrollable Column

```ruby
# Basic usage (display in a scrollable Column)
Column(
  Markdown("# Title\n\nThis is **bold** and *italic*.\n\n```ruby\nputs 'hello'\n```")
).scrollable
```

**Markdown module structure:**

| File | Role |
|------|------|
| `markdown/ast.rb` | MdNode + type constants (MD_HEADING, MD_PARAGRAPH, etc.) |
| `markdown/parser.rb` | Line-based + character scanning pure Ruby parser |
| `markdown/renderer.rb` | Cursor-based drawing with Painter API + height calculation |
| `markdown/theme.rb` | MarkdownTheme (heading sizes, code colors, quote colors, etc.) |

**Column/Row layout fixes:**
- EXPANDING child height/width clamped to 0 when remaining space is negative (enables scrolling)
- Trailing spacing removed from `@content_height`/`@content_width` (hides scrollbar when all content is visible)

### DSL (Block-based UI Builder)

**File:** `lib/konpeito/ui/dsl.rb`

The DSL provides a concise, block-based syntax for building widget trees.
Container functions (`column`, `row`, `box`, `container`) take a block and auto-manage parent-child relationships via an internal widget stack.

**Keyword argument syntax (recommended):**

```ruby
column(padding: 16.0) {
  text "Count: #{@count}", font_size: 32.0, color: 0xFFC0CAF5, align: :center
  row(spacing: 8.0) {
    button(" - ") { @count -= 1 }
    button(" + ") { @count += 1 }
  }
}
```

**Style object syntax (also supported):**

```ruby
column(s.padding(16.0)) {
  text("Count: #{@count}", s.font_size(32.0).color(0xFFC0CAF5).align(TEXT_ALIGN_CENTER))
  row(s.spacing(8.0)) {
    button(" - ", s.width(80.0)) { @count -= 1 }
  }
}
```

Both syntaxes can be mixed. A Style object can be passed as the first positional argument, and keyword arguments can override or add properties on top.

**Available keyword arguments:**

| Category | Keywords |
|----------|----------|
| Layout | `width:`, `height:`, `padding:`, `flex:`, `fit_content:` |
| Container | `spacing:`, `scrollable:`, `pin_to_bottom:`, `pin_to_end:` |
| Visual | `bg_color:`, `border_color:`, `border_radius:` |
| Expanding | `expanding:`, `expanding_width:`, `expanding_height:` |
| Typography | `font_size:`, `color:`, `text_color:`, `bold:`, `italic:`, `font_family:`, `kind:`, `align:` |

Typography keywords are available on `text`, `button`, `checkbox`, `multiline_text`, `text_input`, and `data_table`.

The `align:` keyword accepts symbols (`:center`, `:left`, `:right`) or numeric constants (`TEXT_ALIGN_CENTER`, etc.).

---

## Framework Counter Demo

A demo integrating all framework features:

```ruby
# examples/castella_ui/framework_counter.rb
$theme = Theme.new

class CounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    count = @count
    label = "Count: " + count.value.to_s

    Column(
      Text(label).font_size(32).color(0xFFC0CAF5).align(TEXT_ALIGN_CENTER),
      Row(
        Button("  -  ").font_size(24).on_click {
          count.set(count.value - 1)
        },
        Button("  +  ").font_size(24).on_click {
          count.set(count.value + 1)
        }
      )
    )
  end
end

frame = JWMFrame.new("Castella Counter", 400, 300)
app = App.new(frame, CounterComponent.new)
app.run
```

**Behavior:**
- `State.set()` changes the count value → `notify_observers` → `Component.on_notify` → `pending_rebuild = true`
- On the next frame, `Component.redraw` re-calls `view()` → builds a new widget tree
- Column/Row layout automatically calculates sizes and positions
- Text is horizontally centered with `TEXT_ALIGN_CENTER`

---

## Dynamic Dispatch via invokedynamic

The framework layer has approximately 186 method calls that HM type inference cannot resolve
(such as parameter types passed through blocks). These are resolved at runtime via `invokedynamic` + `RubyDispatch`.

### RubyDispatch.java

Implemented in `tools/konpeito-asm/src/konpeito/runtime/RubyDispatch.java`.

**3-stage name resolution:**
1. **Exact match**: Reflection search by method name + arity
2. **Ruby name aliases**: Conversion via `RUBY_NAME_ALIASES` map (`op_aref`→`get`, `empty_q`→`isEmpty_`, etc.)
3. **snake_to_camel**: Convert to Java camelCase naming convention, e.g. `clip_rect`→`clipRect`

**Number checkcast:**

The return value of `invokedynamic` is `Object` type, and whether it is `Long` or `Double` is unknown until runtime.
The JVM generator casts all numeric unboxing to `java/lang/Number` and uses `Number.longValue()` / `Number.doubleValue()`.
This allows safe unboxing regardless of whether `Long` or `Double` is returned.

---

## Setup and Execution

### Prerequisites

- Java 21+ (`brew install openjdk@21`)
- Konpeito (this repository)

### Setup

```bash
cd examples/castella_ui
bash setup.sh
```

`setup.sh` does the following:
1. Downloads JWM + Skija JARs from Maven Central
2. Compiles `KUIRuntime.java`

### Running

```bash
# Low-level API demos
bash run.sh hello.rb
bash run.sh counter.rb

# Framework demo (recommended)
bash run.sh framework_counter.rb

# Other demos
bash run.sh focus_demo.rb       # Tab navigation
bash run.sh tabs_demo.rb        # Tab switching UI
bash run.sh modal_demo.rb       # Modal dialog
bash run.sh theme_demo.rb       # Theme switching + Kind variants
```

Internally, the following is executed:
```bash
konpeito build --target jvm \
  --classpath "lib/jwm.jar:lib/skija-shared.jar:lib/skija-platform.jar:lib/types.jar:classes" \
  --run \
  examples/castella_ui/framework_counter.rb
```

### Supported Platforms

| OS | Architecture | Rendering |
|----|-------------|-----------|
| macOS | arm64, x86_64 | Metal |
| Windows | x86_64 | Direct3D 12 |
| Linux | x86_64, arm64 | OpenGL |

---

## File Structure

```
examples/castella_ui/
├── setup.sh                        # JAR download + Java compilation
├── run.sh                          # Konpeito compile & run (with auto-rebuild)
├── hello.rb                        # Hello World demo (low-level API)
├── counter.rb                      # Counter demo (low-level API + events)
├── framework_counter.rb            # Framework counter (declarative UI)
├── focus_demo.rb                   # FocusManager demo (Tab navigation)
├── tabs_demo.rb                    # Tabs widget demo
├── modal_demo.rb                   # Modal dialog demo
├── theme_demo.rb                   # Theme switching demo (4 themes + Kind variants)
├── multiline_demo.rb               # MultilineText demo (word wrap, colored text)
├── markdown_demo.rb                # Markdown demo (headings, bold, code blocks, etc.)
├── src/konpeito/ui/KUIRuntime.java # Java runtime
├── classes/                        # Compiled .class files
└── lib/                            # JWM + Skija JARs
    ├── jwm.jar
    ├── skija-shared.jar
    ├── skija-platform.jar
    └── types.jar

lib/konpeito/ui/
├── core.rb / core.rbs              # Widget, Layout, Component, State, ObservableBase
├── render_node.rb / render_node.rbs # RenderNodeBase, LayoutRenderNode
├── column.rb / column.rbs          # Column layout (scroll support)
├── row.rb / row.rbs                # Row layout (scroll support)
├── box.rb / box.rbs                # Box layout (overlay)
├── spacer.rb / spacer.rbs          # Spacer
├── theme.rb                        # Theme system (Kind, 4 presets)
├── focus_manager.rb                # FocusManager (Tab navigation)
├── frame.rb / frame.rbs            # JWMFrame
├── app.rb / app.rbs                # App (FocusManager integration)
└── widgets/
    ├── text.rb                     # Text widget (TextAlign, Kind support)
    ├── button.rb                   # Button widget (Kind, theme support)
    ├── input.rb                    # Input widget (arrow keys, click position detection)
    ├── checkbox.rb                 # Checkbox widget
    ├── container.rb                # Container widget (theme support)
    ├── divider.rb                  # Divider widget (theme support)
    ├── tabs.rb                     # Tabs widget (tab switching UI)
    ├── modal.rb                    # Modal dialog (overlay)
    ├── multiline_text.rb           # MultilineText (multi-line text, word wrap)
    └── markdown.rb                 # Markdown (parser + renderer integration)
├── markdown/
    ├── ast.rb                      # MdNode + type constants
    ├── parser.rb                   # Pure Ruby Markdown parser
    ├── renderer.rb                 # Cursor-based Markdown renderer
    └── theme.rb                    # Markdown theme (color/size tokens)
```

---

## Technical Constraints and Workarounds

| Constraint | Workaround |
|------------|------------|
| JVM lambdas capture by value | Shared mutable capture → resolved via static field approach |
| Incomplete type inference in framework layer | Unresolved calls resolved at runtime via `invokedynamic` + `RubyDispatch` |
| Ruby `[]` cannot be used as a JVM method name | Converted to `op_aref` by `jvm_method_name()`, remapped to `get` via `RubyDispatch` aliases |
| Java inheritance not available | Java side is a thin wrapper (KUIRuntime) only. Entire Widget hierarchy is in Ruby |
| `while` > `each` on JVM | All child traversal in layout/paint should use `while` loops |
| Runtime reflection not available | Use accessor methods instead of `instance_variable_get` |
| Negative width/height in `clipRect` | Clamped to 0 in KUIRuntime (protection during layout transitions) |
| `Long`/`Double` mixing (via invokedynamic) | Safe unboxing via `Number` checkcast |
| Parameter type inference for Layout#add | HM inference infers the type from the most frequent call → possible `checkcast` failure. Workaround by drawing Widgets directly (Modal, etc.) |
| Self capture in blocks | `self` is captured as Object type and invokevirtual fails. Workaround via local variable |
| Class-level constants (JVM) | May result in `NoSuchFieldError`. Use literal values + comments as alternative |
| SAM interface arity confusion | When different SAMs have the same arity, define a new SAM with different arity to avoid confusion (ScrollDeltaCallback, etc.) |
| Arithmetic operators on State[String] | State `*`/`/` generates bytecode assuming Integer. Limit State to Integer use, use `.set()` for String |
