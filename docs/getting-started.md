# Getting Started with Konpeito

## What is Konpeito?

Konpeito is an ahead-of-time (AOT) compiler for Ruby. It takes ordinary Ruby source files and compiles them to standalone JVM JARs or CRuby C extensions — no runtime interpreter overhead. Types are inferred automatically via Hindley-Milner inference; RBS annotations are optional for extra precision.

Konpeito also ships with **Castella UI**, a reactive GUI framework that runs on the JVM backend, based on a port of [Castella for Python](https://github.com/i2y/castella). Build desktop apps with a familiar component model, observable state, and a rich widget library — all in Ruby.

## Installation

### Prerequisites

| Dependency | Version | Required for |
|---|---|---|
| Ruby | 4.0+ | Always |
| Java | 21+ | JVM backend |
| LLVM | 20 | CRuby native backend only |

For JVM-only usage, you need only Ruby and Java. LLVM 20 and the `ruby-llvm` gem are required only if you plan to compile CRuby native extensions (`--target native`). See the [README](../README.md) for platform-specific installation instructions.

### Install Konpeito

```bash
gem install konpeito
```

### Verify your environment

```bash
konpeito doctor --target jvm
```

This checks that Ruby, Java, and the compiler toolchain are correctly installed. You should see green checkmarks for each dependency. It is normal to see an "ASM tool" warning at this point — the ASM tool is built automatically the first time you compile for the JVM.

## Hello World (JVM)

Create a file called `hello.rb`:

```ruby
# hello.rb
puts "Hello from Konpeito!"
```

Compile and run it:

```bash
konpeito build --target jvm --run hello.rb
```

On the very first JVM build, you will see a "Building ASM tool" message. This is a one-time setup that builds the bytecode assembler. Subsequent builds will be fast.

Expected output:

```
     Compiling hello.rb (jvm)
Building ASM tool (first-time setup)...
ASM tool ready.
Running: java -jar hello.jar
Hello from Konpeito!
      Finished in 0.9s -> hello.jar (36 KB)
```

This compiles your Ruby code to JVM bytecode, packages it into a standalone JAR, and runs it immediately. The JAR is self-contained — no Ruby installation needed on the target machine.

To produce a JAR without running it:

```bash
konpeito build --target jvm -o hello.jar hello.rb
java -jar hello.jar
```

## Your First Project

Konpeito can scaffold a new project for you:

```bash
konpeito init --target jvm my_app
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
  lib/                # JVM dependencies (JARs)
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
target = "jvm"

[jvm]
classpath = ""

[test]
pattern = "test/**/*_test.rb"
```

See the [CLI Reference](cli-reference.md) for all configuration options.

## Type Inference

Konpeito infers types automatically using Hindley-Milner inference. No annotations are needed for most code:

```ruby
# types are inferred from usage
def double(x)
  x * 2          # 2 is Integer, so x is Integer, return is Integer
end

def greet(name)
  "Hello, " + name   # String + String -> String
end
```

### Adding inline RBS for precision

When you want explicit types — for documentation, optimization, or to resolve ambiguity — use inline RBS annotations:

```ruby
# rbs_inline: enabled

#: (Integer, Integer) -> Integer
def add(a, b)
  a + b
end

puts add(3, 4)
```

Compile with the `--inline` flag:

```bash
konpeito build --target jvm --inline --run math.rb
```

### Separate RBS files

You can also write type definitions in separate `.rbs` files:

```rbs
# sig/math.rbs
module TopLevel
  def add: (Integer a, Integer b) -> Integer
end
```

```bash
konpeito build --target jvm --rbs sig/math.rbs --run math.rb
```

Types are always optional — the compiler works without them. Adding types unlocks deeper optimizations like unboxed arithmetic (native CPU instructions instead of Ruby method dispatch).

## Building a GUI with Castella UI

Castella UI is a reactive GUI framework for the JVM backend, based on a port of [Castella for Python](https://github.com/i2y/castella). It requires a few additional JARs (JWM for windowing, Skija for rendering) that are downloaded via a setup script.

### Setting up Castella UI

Clone the Konpeito repository and run the setup script:

```bash
git clone https://github.com/i2y/konpeito.git
cd konpeito/examples/castella_ui
bash setup.sh
```

This downloads the required JARs (~30 MB) from Maven Central and compiles the rendering runtime. You only need to do this once.

### Running the counter demo

```bash
bash run.sh framework_counter.rb
```

This builds and runs a counter app with increment/decrement buttons.

### How the counter app works

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

### DSL style

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

### More demos

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

### Themes

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

## Castella Widgets Quick Tour

### Text and display

```ruby
Text("Hello").font_size(18.0).color(0xFFC0CAF5).bold
MultilineText("Long text with\nline breaks").font_size(14.0)
Markdown("# Heading\n\n**Bold** text").font_size(14.0)
```

### Input widgets

```ruby
# Text input
input_state = InputState.new("Enter your name")
Input(input_state).on_change { puts input_state.value }

# Checkbox
Checkbox("Enable notifications").on_toggle { |checked| puts checked }

# Slider
Slider(0, 100).with_value(50).on_change { |val| puts val }
```

### Layout

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

### Container with background and border

```ruby
Container(
  Text("Card content")
).bg_color(0xFF1A1B26).border_color(0xFF3B4261).border_radius(8.0).padding(12.0, 16.0, 12.0, 16.0)
```

### Tabs

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

### Data table

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

### Charts

```ruby
bar_chart(
  ["Jan", "Feb", "Mar"],
  [[10.0, 20.0, 15.0], [5.0, 15.0, 25.0]],
  ["Sales", "Returns"]
)

pie_chart(["Ruby", "Python", "Go"], [45.0, 30.0, 25.0])
```

## CRuby Backend (Alternative)

The CRuby backend compiles Ruby code into C extensions that plug into your existing Ruby application.

### Prerequisites

LLVM 20 and the `ruby-llvm` gem are required:

```bash
gem install ruby-llvm
```

See the main [README](../README.md) for LLVM installation instructions.

### Build and use

```ruby
# math.rb
def add(a, b)
  a + b
end
```

```bash
konpeito build math.rb        # produces math.bundle (macOS) or math.so (Linux)
```

Use it from any Ruby script:

```ruby
require_relative "math"
puts add(3, 4)   # => 7
```

The CRuby backend is ideal for embedding optimized computation into existing Ruby applications. The JVM backend is better for standalone programs and GUI apps.

## Next Steps

- **[CLI Reference](cli-reference.md)** — All commands and options
- **[API Reference](api-reference.md)** — Castella UI widgets, native data structures, and standard library
- **[Language Specification](language-specification.md)** — Supported syntax and type system rules
- **[Architecture](architecture.md)** — Compiler internals and design philosophy
- **[Castella UI demos](https://github.com/i2y/konpeito/tree/main/examples/castella_ui)** — Working GUI demo programs
