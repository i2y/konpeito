---
layout: default
title: Getting Started
nav_order: 2
---

# Getting Started with Konpeito

## What is Konpeito?

Konpeito is an ahead-of-time (AOT) compiler for Ruby. It takes ordinary Ruby source files and compiles them to CRuby C extensions, standalone JVM JARs, or mruby standalone executables — no runtime interpreter overhead. Types are inferred automatically via Hindley-Milner inference; RBS annotations are optional for extra precision.

## Installation

### Prerequisites

| Dependency | Version | Required for |
|---|---|---|
| Ruby | 4.0+ | Always |
| LLVM | 20 | CRuby native backend, mruby backend |
| Java | 21+ | JVM backend only |
| mruby | 3.x | mruby backend only |

See the [README](https://github.com/i2y/konpeito/blob/main/README.md) for platform-specific LLVM installation instructions.

### Install Konpeito

```bash
gem install konpeito
```

### Verify your environment

```bash
konpeito doctor
```

This checks that Ruby, LLVM, and the compiler toolchain are correctly installed. You should see green checkmarks for each dependency.

## Hello World (CRuby Extension)

Create a file called `hello.rb`:

```ruby
# hello.rb
puts "Hello from Konpeito!"
```

Compile and run it:

```bash
konpeito run hello.rb
```

Expected output (first run):

```
     Compiling hello.rb (native)
      Finished in 0.5s -> .konpeito_cache/run/.../hello.bundle (48 KB)
       Running .konpeito_cache/run/.../hello.bundle
Hello from Konpeito!
```

Run the same command again without changes — compilation is skipped:

```
        Cached hello.rb
       Running .konpeito_cache/run/.../hello.bundle
Hello from Konpeito!
```

This compiles your Ruby code into a CRuby C extension (`.bundle` on macOS, `.so` on Linux), caches it in `.konpeito_cache/run/`, and runs it. The extension plugs directly into CRuby, so it can interoperate with any existing Ruby code and gems. On subsequent runs, if no source or RBS files have changed, the cached artifact is reused without recompilation.

Use `--no-cache` to force a rebuild, or `--clean-run-cache` to wipe the cache.

To compile without running:

```bash
konpeito build hello.rb
```

Use it from any Ruby script:

```ruby
require_relative "hello"
```

### Using with RBS types

When you want explicit types — for documentation, optimization, or to resolve ambiguity — use inline RBS annotations:

```ruby
# rbs_inline: enabled

#: (Integer, Integer) -> Integer
def add(a, b)
  a + b    # compiles to native i64 add instruction
end

puts add(3, 4)
```

Compile with the `--inline` flag:

```bash
konpeito build --inline math.rb
```

You can also write type definitions in separate `.rbs` files:

```rbs
# sig/math.rbs
module TopLevel
  def add: (Integer a, Integer b) -> Integer
end
```

```bash
konpeito build --rbs sig/math.rbs math.rb
```

Types are always optional — the compiler works without them. Adding types unlocks deeper optimizations like unboxed arithmetic (native CPU instructions instead of Ruby method dispatch).

## Your First Project

Konpeito can scaffold a new project for you:

```bash
konpeito init my_app
cd my_app
```

This creates the following structure:

```
my_app/
  konpeito.toml       # project configuration
  src/
    main.rb           # entry point
  test/
    main_test.rb      # test stub
  .gitignore
```

Run the generated starter code:

```bash
konpeito run src/main.rb
```

Or run the tests:

```bash
konpeito test
```

### Project configuration

`konpeito.toml` controls build settings:

```toml
[build]
target = "native"

[test]
pattern = "test/**/*_test.rb"
```

See the [CLI Reference](cli-reference.md) for all configuration options.

## JVM Backend

The JVM backend compiles Ruby code to standalone JAR files. No Ruby installation is needed on the target machine.

### Prerequisites

Java 21+ is required. LLVM is not needed for JVM-only usage.

```bash
konpeito doctor --target jvm
```

### Build and run

```bash
konpeito build --target jvm --run hello.rb
```

On the very first JVM build, you will see a "Building ASM tool" message. This is a one-time setup that builds the bytecode assembler. Subsequent builds will be fast.

To produce a JAR without running it:

```bash
konpeito build --target jvm -o hello.jar hello.rb
java -jar hello.jar
```

### Building a GUI with Castella UI

Castella UI is a reactive GUI framework for the JVM backend, based on a port of [Castella for Python](https://github.com/i2y/castella). It requires a few additional JARs (JWM for windowing, Skija for rendering) that are downloaded via a setup script.

#### Setting up Castella UI

Clone the Konpeito repository and run the setup script:

```bash
git clone https://github.com/i2y/konpeito.git
cd konpeito/examples/castella_ui
bash setup.sh
```

This downloads the required JARs (~30 MB) from Maven Central and compiles the rendering runtime. You only need to do this once.

#### Running the counter demo

```bash
bash run.sh framework_counter.rb
```

This builds and runs a counter app with increment/decrement buttons.

#### How the counter app works

Here is the counter app source (`framework_counter.rb`):

```ruby
class CounterApp < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    label = "Count: " + @count.value.to_s
    Column(
      Text(label).font_size(32.0),
      Row(
        Button("  -  ").on_click { @count -= 1 },
        Button("  +  ").on_click { @count += 1 }
      ).spacing(8.0)
    )
  end
end

$theme = theme_tokyo_night
frame = JWMFrame.new("Counter", 400, 300)
app = App.new(frame, CounterApp.new)
app.run
```

**Key concepts:**

- **`Component`** is the base class for reactive UI. Override `view()` to return your widget tree.
- **`state(initial)`** creates an observable value. When it changes, `view()` is automatically re-called and the UI updates.
- **`Column(...)` / `Row(...)`** are layout widgets that stack children vertically or horizontally.
- **`Text(content)`** displays text. Chain `.font_size()`, `.color()`, `.bold` for styling.
- **`Button(label)`** is a clickable button. Use `.on_click { ... }` for the click handler.
- State operators (`+=`, `-=`) mutate the state and trigger a re-render.

#### DSL style

A block-based DSL is also available for more concise UI definitions:

```ruby
class CounterApp < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    column(padding: 16.0) do
      text "Count: #{@count}", font_size: 32.0, color: 0xFFC0CAF5
      row(spacing: 8.0) do
        button("-", width: 60.0) { @count -= 1 }
        button("+", width: 60.0) { @count += 1 }
      end
    end
  end
end
```

Keyword arguments (`padding:`, `font_size:`, `color:`, etc.) configure layout and styling directly. Style objects via the `s` helper are also supported and composable with `+`:

```ruby
title_style = s.font_size(24.0).bold.color(0xFFC0CAF5)
card_style = s.bg_color(0xFF1A1B26).border_radius(8.0).padding(16.0)
```

#### More demos

The `examples/castella_ui/` directory contains many working demos:

```bash
bash run.sh tabs_demo.rb            # tabbed interface
bash run.sh theme_demo.rb           # theme switching
bash run.sh data_table_demo.rb      # sortable data table
bash run.sh chart_demo.rb           # charts (bar, line, pie)
bash run.sh input_demo.rb           # text input fields
bash run.sh markdown_demo.rb        # Markdown rendering
bash run.sh calendar_demo.rb        # date picker
```

#### Themes

Castella ships with five built-in themes:

```ruby
$theme = theme_tokyo_night   # dark (default)
$theme = theme_light         # light
$theme = theme_nord          # nord palette
$theme = theme_dracula       # dracula palette
$theme = theme_catppuccin    # catppuccin palette
```

Use theme colors in your styles:

```ruby
text "Hello", color: $theme.text_primary
container(bg_color: $theme.bg_secondary) { ... }
```

### Castella Widgets Quick Tour

#### Text and display

```ruby
Text("Hello").font_size(18.0).color(0xFFC0CAF5).bold
MultilineText("Long text with\nline breaks").font_size(14.0)
Markdown("# Heading\n\n**Bold** text").font_size(14.0)
```

#### Input widgets

```ruby
# Text input
input_state = InputState.new("Enter your name")
Input(input_state).on_change { puts input_state.value }

# Checkbox
Checkbox("Enable notifications").on_toggle { |checked| puts checked }

# Slider
Slider(0, 100).with_value(50).on_change { |val| puts val }
```

#### Layout

```ruby
Column(
  Text("Top"),
  Text("Middle"),
  Text("Bottom")
).spacing(8.0)

Row(
  Button("Left"),
  Spacer(),
  Button("Right")
).spacing(8.0)

# Scrollable layout
Column(
  # many children...
).scrollable
```

#### Container with background and border

```ruby
Container(
  Text("Card content")
).bg_color(0xFF1A1B26).border_color(0xFF3B4261).border_radius(8.0).padding(12.0, 16.0, 12.0, 16.0)
```

#### Tabs

```ruby
Tabs(
  ["Tab 1", "Tab 2", "Tab 3"],
  [
    Text("Content 1"),
    Text("Content 2"),
    Text("Content 3")
  ]
)
```

#### Data table

```ruby
DataTable(
  ["Name", "Age", "City"],
  [150.0, 60.0, 120.0],
  [
    ["Alice", "30", "Tokyo"],
    ["Bob", "25", "Osaka"],
    ["Charlie", "35", "Kyoto"]
  ]
).on_select { |row| puts "Selected row #{row}" }
```

#### Charts

```ruby
bar_chart(
  ["Jan", "Feb", "Mar"],
  [[10.0, 20.0, 15.0], [5.0, 15.0, 25.0]],
  ["Sales", "Returns"]
)

pie_chart(["Ruby", "Python", "Go"], [45.0, 30.0, 25.0])
```

## Standalone Executables (mruby Backend)

The mruby backend compiles Ruby code to standalone executables. No Ruby or Java installation is needed on the target machine — a single binary is all you need.

### Prerequisites

mruby must be installed. Konpeito uses `mruby-config` to locate the mruby installation, or you can set the `MRUBY_DIR` environment variable.

```bash
konpeito doctor --target mruby
```

### Build and run

```bash
konpeito build --target mruby -o hello hello.rb
./hello
```

A license file (`hello.LICENSES.txt`) is automatically generated alongside the executable, containing the MIT license for mruby and any other linked libraries. When distributing your binary, include this file to comply with third-party license requirements.

Or build and run in one step (with compilation caching):

```bash
konpeito run --target mruby hello.rb
```

Cached artifacts are stored in `.konpeito_cache/run/`. Use `--no-cache` to force a rebuild, or `--clean-run-cache` to wipe the cache.

### Game development with raylib stdlib

Konpeito includes a raylib stdlib for the mruby backend. Simply reference `module Raylib` in your code and the compiler auto-detects and injects the RBS definitions and C wrapper.

```ruby
# bouncing_ball.rb
module Raylib
end

def main
  Raylib.init_window(800, 600, "Bouncing Ball")
  Raylib.set_target_fps(60)

  x = 400
  y = 300
  dx = 4
  dy = 3
  radius = 20.0
  color = Raylib.color_red

  while Raylib.window_should_close == 0
    x = x + dx
    y = y + dy
    if x < 20 || x > 780
      dx = 0 - dx
    end
    if y < 20 || y > 580
      dy = 0 - dy
    end

    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)
    Raylib.draw_circle(x, y, radius, color)
    Raylib.end_drawing
  end

  Raylib.close_window
end

main
```

```bash
konpeito run --target mruby bouncing_ball.rb
```

The raylib stdlib provides 87 functions covering window management, shape/text drawing, keyboard/mouse input, 27 color constants, key constants, and random number generation. See the [API Reference](api-reference.md) for the full list.

### UI layout with Clay stdlib

Konpeito includes a Clay UI stdlib for the mruby backend. Clay is a Flexbox-style layout engine — you define containers, configure layout/styling via scalar API calls, and Clay computes the layout. Rendering is done via the built-in raylib renderer.

Reference `module Clay` in your code and the compiler auto-detects it (same as raylib).

```ruby
# simple_ui.rb
module Raylib
end
module Clay
end

FIT = 0
GROW = 1
LTR = 0
TTB = 1

def main
  Raylib.set_config_flags(Raylib.flag_window_resizable)
  Raylib.init_window(640, 480, "Clay UI")
  Raylib.set_target_fps(60)

  Clay.init(640.0, 480.0)
  font = Clay.load_font("/System/Library/Fonts/Supplemental/Arial.ttf", 32)
  Clay.set_measure_text_raylib

  while Raylib.window_should_close == 0
    w = Raylib.get_screen_width
    h = Raylib.get_screen_height
    Clay.set_dimensions(w * 1.0, h * 1.0)

    mx = Raylib.get_mouse_x
    my = Raylib.get_mouse_y
    Clay.set_pointer(mx * 1.0, my * 1.0, 0)

    Clay.begin_layout
    Clay.open("root")
    Clay.layout(TTB, 24, 24, 24, 24, 16, GROW, 0.0, GROW, 0.0, 2, 2)
    Clay.bg(40.0, 40.0, 60.0, 255.0, 0.0)
      Clay.text("Hello, Clay!", font, 32, 255.0, 255.0, 255.0, 255.0, 0)
    Clay.close
    Clay.end_layout

    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)
    Clay.render_raylib
    Raylib.end_drawing
  end

  Clay.destroy
  Raylib.close_window
end

main
```

```bash
konpeito run --target mruby simple_ui.rb
```

Clay provides 40+ functions covering element construction (`open`/`close`/`layout`/`bg`/`border`), text rendering with TTF fonts, scrolling, floating elements, pointer hit-testing, and bulk rendering. See the [API Reference](api-reference.md) for the full list.

### RPG Framework

Konpeito includes an RPG framework (`rpg_framework.rb`) that provides helper functions for building 2D RPGs with the mruby backend. The framework covers:

- **Tilemap rendering** — `fw_draw_tilemap` draws multi-layer tile maps with camera offset
- **Sprite animation** — `fw_draw_sprite` handles sprite sheets with directional animation
- **Scene management** — `fw_push_scene` / `fw_pop_scene` with scene stack
- **NPC system** — `fw_draw_npc` / `fw_update_npc` for wandering NPCs
- **Text display** — `fw_draw_text_box` for RPG-style message windows
- **Clay UI helpers** — `fw_clay_rpg_window`, `fw_clay_bar`, `fw_clay_num`, `fw_clay_menu_item` for building menus, status panels, and HUD elements with Clay

The framework uses `module G` with `NativeArray` globals for game state (no heap allocation). Include it with `require_relative "./rpg_framework"`.

See `examples/mruby_dq_rpg/` for a full JRPG demo (tilemap, NPCs, turn-based battle, menu, shop) that uses Clay UI for battle HUD, menu, and shop interfaces.

### Cross-compilation

Cross-compile for other platforms using `zig cc` as the cross-compiler:

```bash
konpeito build --target mruby \
  --cross aarch64-linux-musl \
  --cross-mruby ~/mruby-aarch64 \
  -o game game.rb
```

Options:

| Option | Description |
|---|---|
| `--cross TARGET` | Target triple (e.g., `x86_64-linux-gnu`, `aarch64-linux-musl`) |
| `--cross-mruby DIR` | Path to cross-compiled mruby (must contain `include/` and `lib/`) |
| `--cross-libs DIR` | Additional library search path for cross-compilation |

## Next Steps

- **[Tutorial](tutorial.md)** — Step-by-step guide with practical examples
- **[CLI Reference](cli-reference.md)** — All commands and options
- **[API Reference](api-reference.md)** — Castella UI widgets, native data structures, and standard library
- **[Language Specification](language-specification.md)** — Supported syntax and type system rules
- **[Castella UI demos](https://github.com/i2y/konpeito/tree/main/examples/castella_ui)** — Working GUI demo programs
