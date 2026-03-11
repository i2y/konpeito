---
layout: default
title: Tutorial
parent: Guides
nav_order: 1
---

# Tutorial

This tutorial walks you through installing Konpeito and running your first compiled Ruby code.

## 1. Installation

### Prerequisites

| Dependency | Version | Required for |
|---|---|---|
| Ruby | 4.0.1+ | Always (runs the compiler) |
| LLVM | 20 | CRuby native backend, mruby backend |
| Java | 21+ | JVM backend |
| mruby | 3.x | mruby backend |

LLVM, Java, and mruby are needed depending on which backend you use. You only need one.

### Install Konpeito

```bash
gem install konpeito
```

### Install LLVM 20 (for CRuby backend)

**macOS:**
```bash
brew install llvm@20
ln -sf /opt/homebrew/opt/llvm@20/lib/libLLVM-20.dylib /opt/homebrew/lib/
gem install ruby-llvm
```

**Ubuntu / Debian:**
```bash
sudo apt install llvm-20 clang-20
gem install ruby-llvm
```

**Fedora:**
```bash
sudo dnf install llvm20 clang20
gem install ruby-llvm
```

### Install Java 21 (for JVM backend)

**macOS:**
```bash
brew install openjdk@21
```

**Ubuntu / Debian:**
```bash
sudo apt install openjdk-21-jdk
```

**Fedora:**
```bash
sudo dnf install java-21-openjdk-devel
```

### Verify your environment

```bash
konpeito doctor              # check CRuby backend
konpeito doctor --target jvm # check JVM backend
```

You should see green checkmarks for each dependency. Two warnings are expected and can be safely ignored:

- **ASM tool: WARNING** — The ASM tool (bytecode assembler for the JVM backend) is built automatically the first time you run a JVM build. No action needed.
- **Config: WARNING** — No `konpeito.toml` found in the current directory. This is normal when you haven't created a project yet. You can create one with `konpeito init`, or simply pass source files directly to `konpeito build`.

---

## 2. Hello World

### CRuby backend (native extension)

```ruby
# hello.rb
module Hello
  def self.greet(name)
    "Hello, #{name}!"
  end
end
```

```bash
konpeito build hello.rb   # → hello.bundle (macOS) / hello.so (Linux)
```

Use it from Ruby:
```ruby
require_relative "hello"
puts Hello.greet("World")   # => "Hello, World!"
```

The compiled extension is a standard CRuby C extension. It loads into any Ruby process just like a gem written in C. Wrapping your code in a module avoids polluting the top-level namespace — this is the recommended pattern for extension libraries.

### JVM backend (standalone JAR)

```ruby
# hello_jvm.rb
puts "Hello from Konpeito!"
```

```bash
konpeito build --target jvm --run hello_jvm.rb
```

On the very first JVM build, you will see a "Building ASM tool" message. This is a one-time setup.

Expected output:
```
     Compiling hello_jvm.rb (jvm)
Building ASM tool (first-time setup)...
ASM tool ready.
Running: java -jar hello_jvm.jar
Hello from Konpeito!
      Finished in 0.9s -> hello_jvm.jar (36 KB)
```

The generated JAR is standalone — no Ruby installation needed on the target machine.

---

## 3. How Konpeito Works

When Konpeito compiles your code, each operation falls into one of two categories:

- **Native** — The compiler resolved the types and emitted native CPU instructions (e.g. LLVM: `add i64`, `fadd double`, `getelementptr`) or typed JVM bytecode (e.g. `iadd`, `dadd`). No Ruby method dispatch overhead.
- **Dynamic fallback** — The compiler couldn't determine the type. The call compiles to `rb_funcallv` (LLVM) or `invokedynamic` (JVM), which runs at the same speed as regular Ruby. The compiler emits a warning so you know where the boundaries are.

Adding RBS type annotations promotes dynamic fallbacks to native dispatch. You can leave them dynamic if you don't need the speed there — it's your call.

### Gems and runtime dependencies

When your code says `require "some_gem"`, the compiler checks whether the gem's source is available on the compile-time load path (specified by `-I`):

- **On the load path (`-I`)** — The gem's source files are compiled together with your code into a single extension. Method calls between your code and the gem use direct dispatch, monomorphization, and inlining.
- **Not on the load path** — The compiler emits a `rb_require("some_gem")` call so CRuby loads the gem at runtime. Your compiled code can still call the gem's methods, but those calls go through `rb_funcallv` (dynamic dispatch). This still works correctly — it's just not optimized.

In practice, many applications only need to compile their own code. Gems like UI frameworks or database drivers are bottlenecked by rendering or external services, so compiling them provides little benefit. Use `-I` when you want to maximize optimization across the entire codebase.

---

## 4. CRuby Backend: Practical Examples

### Pattern 1: Extension Library

Compile performance-critical functions into a native extension and `require` it from your regular Ruby application.

#### Step 1: Write the code

```ruby
# physics.rb
module Physics
  def self.distance(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  def self.sum_distances(xs, ys, n)
    total = 0.0
    i = 0
    while i < n - 1
      total = total + distance(xs[i], ys[i], xs[i + 1], ys[i + 1])
      i = i + 1
    end
    total
  end
end
```

#### Step 2: Optionally add RBS for better optimization

Without RBS, HM inference will still resolve types from literals and call sites. But explicit types let the compiler optimize more aggressively.

**Option A: Inline RBS (recommended for getting started)**

Write type annotations directly in the Ruby source using rbs-inline comments:

```ruby
# physics.rb
# rbs_inline: enabled

module Physics
  #: (Float x1, Float y1, Float x2, Float y2) -> Float
  def self.distance(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  #: (Array[Float] xs, Array[Float] ys, Integer n) -> Float
  def self.sum_distances(xs, ys, n)
    total = 0.0
    i = 0
    while i < n - 1
      total = total + distance(xs[i], ys[i], xs[i + 1], ys[i + 1])
      i = i + 1
    end
    total
  end
end
```

**Option B: Separate RBS file**

```rbs
# physics.rbs
module Physics
  def self.distance: (Float x1, Float y1, Float x2, Float y2) -> Float
  def self.sum_distances: (Array[Float] xs, Array[Float] ys, Integer n) -> Float
end
```

#### Step 3: Compile

```bash
# Inline RBS (Option A)
konpeito build --inline physics.rb

# Separate RBS file (Option B)
konpeito build physics.rb
```

Use `-v` to see what the compiler inferred and where dynamic fallbacks occur:

```bash
konpeito build -v physics.rb
```

#### Step 4: Use from Ruby

```ruby
# app.rb — regular Ruby, NOT compiled by Konpeito
require_relative "physics"

xs = Array.new(10000) { rand }
ys = Array.new(10000) { rand }
puts Physics.sum_distances(xs, ys, 10000)
```

```bash
ruby app.rb
```

**What's native:** `distance` is fully native — `dx * dx + dy * dy` compiles to `fmul double` + `fadd double` instructions. The `while` loop in `sum_distances` is a native counter loop.

**What's dynamic:** `xs[i]` calls `rb_funcallv` on the Ruby Array (because the Array itself is a CRuby object, not a NativeArray). If you need that inner access to be native too, use `NativeArray[Float]`:

#### Going fully native with NativeArray

`NativeArray[Float]` stores unboxed `double` values in contiguous memory. Array element access becomes a direct `getelementptr` + `load` — no method dispatch at all.

##### Local NativeArray (function-scoped)

Since `NativeArray` is a Konpeito-specific type, it must be created and accessed within the same compiled scope. Here we put the NativeArray creation, population, and computation together in one method:

```ruby
# physics_native.rb
# rbs_inline: enabled

module Physics
  #: (Float, Float, Float, Float) -> Float
  def self.distance(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  def self.run
    n = 10000
    xs = NativeArray.new(n)
    ys = NativeArray.new(n)
    i = 0
    while i < n
      xs[i] = i * 0.0001
      ys[i] = i * 0.0002
      i = i + 1
    end

    total = 0.0
    i = 0
    while i < n - 1
      total = total + distance(xs[i], ys[i], xs[i + 1], ys[i + 1])
      i = i + 1
    end
    puts total
  end
end

Physics.run
```

```bash
konpeito run physics_native.rb
```

> **Tip:** `konpeito run` caches compiled artifacts in `.konpeito_cache/run/`. On subsequent runs, if no source or RBS files have changed, compilation is skipped entirely. Use `--no-cache` to force recompilation, or `--clean-run-cache` to wipe the cache.

> **Note:** When both `physics_native.rb` and `physics_native.bundle` exist in the same directory, `require "./physics_native"` loads the `.rb` source file first. `konpeito run` avoids this problem by handling the load path automatically. If you need to build and run separately, output to a different directory:
> ```bash
> konpeito build -o build/physics_native.bundle physics_native.rb
> ruby -r ./build/physics_native -e ""
> ```

> **Important:** Local NativeArray values are stack-allocated pointers and cannot be passed as arguments to other methods via CRuby's method dispatch. Always create and use local NativeArrays within the same function scope. If you need arrays shared across functions, use module NativeArray instead.

Now `xs[i]` and `ys[i]` are also native — the entire loop runs without touching Ruby's method dispatch.

##### Module NativeArray (global, cross-function)

For game state, simulation data, or any arrays that need to be accessed from multiple functions, you can declare fixed-size NativeArrays as module instance variables in RBS. The compiler generates LLVM global arrays — no C wrapper file needed.

Using inline RBS (`rbs_inline: enabled`), the module declaration and array types live in the same file:

```ruby
# physics.rb
# rbs_inline: enabled

# @rbs module PhysicsData
# @rbs   @xs: NativeArray[Float, 10000]
# @rbs   @ys: NativeArray[Float, 10000]
# @rbs end

#: (Float, Float, Float, Float) -> Float
def distance(x1, y1, x2, y2)
  dx = x2 - x1
  dy = y2 - y1
  dx * dx + dy * dy
end

def init_data
  i = 0
  while i < 10000
    PhysicsData.xs[i] = i * 0.0001
    PhysicsData.ys[i] = i * 0.0002
    i = i + 1
  end
end

#: () -> Float
def compute_total
  total = 0.0
  i = 0
  while i < 9999
    total = total + distance(PhysicsData.xs[i], PhysicsData.ys[i],
                             PhysicsData.xs[i + 1], PhysicsData.ys[i + 1])
    i = i + 1
  end
  total
end

def run_physics
  init_data
  compute_total
end
```

```bash
konpeito run --inline physics.rb
```

Or with a separate RBS file:

```rbs
# physics.rbs
module PhysicsData
  @xs: NativeArray[Float, 10000]
  @ys: NativeArray[Float, 10000]
end
```

The syntax is `NativeArray[T, N]` where `T` is the element type (`Integer` or `Float`) and `N` is the fixed size. Access uses `ModuleName.field_name[index]` and `ModuleName.field_name[index] = value`.

> **Note:** Module NativeArray is available on the LLVM (CRuby) and mruby backends. JVM backend is not yet supported. See `examples/mruby_space_invaders/` for a full game using this pattern.

### Pattern 2: Whole Application

Compile an entire Ruby application. The compiler traces `require` / `require_relative` statements and compiles everything it can find on the load path into a single extension.

#### Example: A kumiki GUI app

[kumiki](https://github.com/i2y/kumiki) is a cross-platform desktop UI framework for Ruby.

```bash
gem install kumiki
```

```ruby
# counter.rb
require "kumiki"
include Kumiki

class CounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    column(padding: 16.0, spacing: 8.0) {
      text "Count: #{@count}", font_size: 32.0, color: 0xFFC0CAF5, align: :center
      row(spacing: 8.0) {
        button(" - ") { @count -= 1 }
        button(" + ") { @count += 1 }
      }
    }
  end
end

frame = RanmaFrame.new("Kumiki Counter", 400, 300)
app = App.new(frame, CounterComponent.new)
app.run
```

**Option A: Compile everything (whole application)**

```bash
konpeito build -I /path/to/kumiki/lib counter.rb
```

`-I` adds kumiki's `lib/` directory to the load path. The compiler resolves `require "kumiki"` and all of kumiki's internal requires, compiling 59 files into a single `counter.bundle` (971 KB). Method calls between your code and kumiki use direct dispatch; monomorphization and inlining are applied across the entire codebase.

**Option B: Compile only your code (extension library)**

```bash
konpeito build counter.rb
```

Without `-I`, the compiler compiles only `counter.rb` (~50 KB). kumiki is loaded at runtime by CRuby via `rb_require`. Your code is still compiled natively, but calls into kumiki go through `rb_funcallv` (dynamic dispatch).

**Run:**

```bash
konpeito run counter.rb
```

Or build to a separate directory to avoid the `.rb` / `.bundle` name conflict:

```bash
konpeito build -o build/counter.bundle counter.rb
ruby -r ./build/counter -e ""
```

- `-r ./build/counter` loads the extension. Its `Init` function runs the top-level code (creates the frame, component, and enters the event loop).
- `-e ""` provides an empty script so Ruby doesn't wait for stdin.
- **Do not** use `ruby -r ./counter -e ""` in the same directory as `counter.rb` — Ruby loads `.rb` before `.bundle`, so it would run the uncompiled source instead.

---

## 5. JVM Backend: Practical Examples

### Standalone Program

```ruby
# physics_jvm.rb
def distance(x1, y1, x2, y2)
  dx = x2 - x1
  dy = y2 - y1
  dx * dx + dy * dy
end

def sum_distances(n)
  total = 0.0
  i = 0
  while i < n
    total = total + distance(i * 1.0, 0.0, 0.0, i * 2.0)
    i = i + 1
  end
  total
end

puts sum_distances(1000)
```

```bash
konpeito build --target jvm --run physics_jvm.rb
```

Or produce a JAR and run it separately:

```bash
konpeito build --target jvm -o physics.jar physics_jvm.rb
java -jar physics.jar
```

The JAR is self-contained — no Ruby installation needed on the target machine.

### GUI Application (Castella UI)

The JVM backend supports Castella UI, a reactive GUI framework based on Skia rendering.

```bash
git clone https://github.com/i2y/konpeito.git
cd konpeito/examples/castella_ui
bash setup.sh    # downloads JWM + Skija JARs (~30 MB, one-time)
bash run.sh framework_counter.rb
```

```ruby
# framework_counter.rb
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

See [Getting Started](getting-started.md) for the full Castella UI widget catalog and theme list.

---

## 5.5. mruby Backend: Standalone Executables

The mruby backend produces standalone executables — no Ruby or Java required on the target machine. This is ideal for distributing applications, writing games, or deploying to environments without a Ruby installation.

### Standalone Hello World

```ruby
# hello.rb
def main
  puts "Hello from Konpeito!"
end

main
```

```bash
konpeito build --target mruby -o hello hello.rb
./hello    # => Hello from Konpeito!
```

Or build and run in one step:

```bash
konpeito run --target mruby hello.rb
```

### Game Development with raylib stdlib

Konpeito includes a raylib stdlib for the mruby backend. Reference `module Raylib` in your code and the compiler auto-detects the RBS/C wrapper — no manual setup needed.

```ruby
# catch_game.rb
module Raylib
end

def main
  screen_w = 600
  screen_h = 400

  Raylib.init_window(screen_w, screen_h, "Catch Game")
  Raylib.set_target_fps(60)

  paddle_x = screen_w / 2 - 40
  paddle_y = screen_h - 40
  paddle_speed = 400

  obj_x = Raylib.get_random_value(30, screen_w - 30)
  obj_y = 0
  obj_speed = 150.0
  score = 0

  while Raylib.window_should_close == 0
    dt = Raylib.get_frame_time

    if Raylib.key_down?(Raylib.key_left) != 0
      paddle_x = paddle_x - (paddle_speed * dt).to_i
    end
    if Raylib.key_down?(Raylib.key_right) != 0
      paddle_x = paddle_x + (paddle_speed * dt).to_i
    end

    obj_y = obj_y + (obj_speed * dt).to_i
    if obj_y > screen_h
      obj_x = Raylib.get_random_value(30, screen_w - 30)
      obj_y = 0
    end

    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)
    Raylib.draw_rectangle(paddle_x, paddle_y, 80, 14, Raylib.color_skyblue)
    Raylib.draw_rectangle(obj_x, obj_y, 16, 16, Raylib.color_gold)
    Raylib.draw_text("Score: #{score}", 10, 10, 20, Raylib.color_white)
    Raylib.end_drawing
  end

  Raylib.close_window
end

main
```

```bash
konpeito run --target mruby catch_game.rb
```

### UI Layout with Clay stdlib

Konpeito includes a Clay UI stdlib for building Flexbox-style layouts. Clay computes layout from a tree of containers and outputs draw commands rendered via raylib. Reference `module Clay` in your code for auto-detection.

```ruby
# Clay layout: open/close containers, set layout/bg, add text
Clay.begin_layout

Clay.open("root")
Clay.layout(1, 16, 16, 16, 16, 8, 1, 0.0, 1, 0.0, 2, 0)  # vertical, grow, center-x
Clay.bg(40.0, 40.0, 60.0, 255.0, 0.0)

  Clay.open("card")
  Clay.layout(1, 12, 12, 12, 12, 4, 1, 0.0, 0, 0.0, 0, 0)  # vertical, grow-w, fit-h
  Clay.bg(255.0, 255.0, 255.0, 255.0, 8.0)                  # white, rounded
  Clay.border(200.0, 200.0, 200.0, 255.0, 1, 1, 1, 1, 8.0)  # gray border
    Clay.text("Hello!", font, 24, 40.0, 40.0, 40.0, 255.0, 0)
  Clay.close

Clay.close

Clay.end_layout
Clay.render_raylib  # render all commands via raylib
```

Key concepts:
- `Clay.open(id)` / `Clay.close` — define nested containers
- `Clay.layout(dir, pl, pr, pt, pb, gap, sw_type, sw_val, sh_type, sh_val, ax, ay)` — Flexbox layout
- `Clay.bg(r, g, b, a, corner_radius)` — background color with rounded corners
- `Clay.border(r, g, b, a, top, right, bottom, left, corner_radius)` — border
- `Clay.text(str, font_id, size, r, g, b, a, wrap)` — text element
- `Clay.pointer_over(id)` / `Clay.pointer_over_i(id, index)` — hit testing

See `examples/mruby_clay_ui/` for a full sidebar layout demo and a Memory Match card game.

### RPG Framework

Konpeito includes an RPG framework (`rpg_framework.rb`) with helpers for building 2D RPGs:

- Tilemap rendering, sprite animation, scene management, NPC system, text boxes
- Clay UI helpers: `fw_clay_rpg_window`, `fw_clay_bar`, `fw_clay_num`, `fw_clay_menu_item`
- Uses `module G` with `NativeArray` globals for zero-allocation game state

See `examples/mruby_dq_rpg/` for a full JRPG demo with Clay UI battle HUD, menu, and shop.

### Cross-compilation

Cross-compile for other platforms using `zig cc`:

```bash
konpeito build --target mruby \
  --cross aarch64-linux-musl \
  --cross-mruby ~/mruby-aarch64 \
  -o game game.rb
```

| Option | Description |
|---|---|
| `--cross TARGET` | Target triple (e.g., `x86_64-linux-gnu`) |
| `--cross-mruby DIR` | Cross-compiled mruby install path |
| `--cross-libs DIR` | Additional library search path |

### mruby vs CRuby backend comparison

| Aspect | CRuby backend | mruby backend |
|---|---|---|
| Output | .so/.bundle (extension) | Standalone executable |
| Runtime dependency | CRuby 4.0+ | None |
| Use case | Library/app acceleration | Distribution, games |
| raylib stdlib | Not available | Auto-detected |
| Clay UI stdlib | Not available | Auto-detected |
| Thread/Mutex | Supported | Not supported |
| Keyword arguments | Supported | Not supported |
| Compilation caching | `.konpeito_cache/run/` | `.konpeito_cache/run/` |

---

## 6. Type System

### HM type inference (no annotations needed)

Konpeito infers types automatically using Hindley-Milner inference:

```ruby
def double(x)
  x * 2          # 2 is Integer → x is Integer → return is Integer
end

def greet(name)
  "Hello, " + name   # String + String → String
end
```

Inferred types are used directly for unboxed optimizations. No RBS needed.

### Adding RBS for precision

RBS gives the compiler more precise information:

**Separate file:**

```rbs
# sig/math.rbs
module TopLevel
  def add: (Integer a, Integer b) -> Integer
end
```

```bash
konpeito build --rbs sig/math.rbs math.rb
```

**Inline (rbs-inline):**

```ruby
# rbs_inline: enabled

#: (Integer, Integer) -> Integer
def add(a, b)
  a + b
end
```

```bash
konpeito build --inline math.rb
```

### Native data structures

Typed high-performance data structures are available (CRuby and mruby backends):

| Type | Use case | Characteristics |
|---|---|---|
| `NativeArray[T]` | Numeric arrays | Unboxed, contiguous memory, 5-15x faster |
| `NativeClass` | Structs | Unboxed fields, 10-20x faster |
| `StaticArray[T, N]` | Fixed-size arrays | Stack-allocated, no GC pressure |
| `NativeHash[K, V]` | Hash maps | Linear probing, 4x faster |
| `Slice[T]` | Memory views | Zero-copy, bounds-checked |

```ruby
# NativeArray example
def sum_array(n)
  arr = NativeArray.new(n)
  i = 0
  while i < n
    arr[i] = i * 1.5   # unboxed store
    i = i + 1
  end

  total = 0.0
  i = 0
  while i < n
    total = total + arr[i]   # unboxed load
    i = i + 1
  end
  total
end
```

These types require RBS definitions. See the [API Reference](api-reference.md) for details.

---

## 7. Project Setup

`konpeito init` scaffolds a new project:

```bash
konpeito init --target jvm my_app
cd my_app
```

```
my_app/
  konpeito.toml       # build configuration
  src/
    main.rb           # entry point
  test/
    main_test.rb      # test stub
  lib/                # JVM dependencies (JARs)
  .gitignore
```

```bash
konpeito run src/main.rb    # compile & run
konpeito test               # run tests
```

---

## 8. Useful Commands

```bash
konpeito build -v source.rb          # show inferred types and dynamic fallback warnings
konpeito build -g source.rb          # emit DWARF debug info for lldb/gdb (LLVM backend)
konpeito check source.rb             # type-check only (no code generation)
konpeito build --profile source.rb   # build with profiling instrumentation
konpeito run --no-cache source.rb    # force recompilation (skip run cache)
konpeito run --clean-run-cache source.rb  # clear run cache, then build and run
konpeito fmt                         # format code (RuboCop)
konpeito deps source.rb              # analyze and display dependencies

# mruby backend
konpeito build --target mruby -o app app.rb    # standalone executable
konpeito run --target mruby app.rb             # build & run (cached)
konpeito doctor --target mruby                 # check mruby environment
```

---

## Next Steps

- **[CLI Reference](cli-reference.md)** — All commands and options
- **[API Reference](api-reference.md)** — Native data structures, standard library, and Castella UI widgets
- **[Language Specification](language-specification.md)** — Supported syntax and type system rules
