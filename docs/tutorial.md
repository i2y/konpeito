# Tutorial

Konpeito compiles Ruby source files into native code. It has two backends:

- **LLVM backend** — Produces CRuby extensions (`.bundle` on macOS, `.so` on Linux). The compiled code runs inside a normal Ruby process.
- **JVM backend** — Produces standalone JAR files. No Ruby installation needed on the target machine.

And two usage patterns:

1. **Extension library** — Compile performance-critical code and `require` it from your regular Ruby application.
2. **Whole application** — Compile an entire Ruby application, including framework code resolved via `require`.

## The Native Boundary

When Konpeito compiles your code, each operation falls into one of two categories:

- **Native** — The compiler resolved the types and emitted native CPU instructions (LLVM) or typed JVM bytecode. Integer arithmetic becomes `add i64` or `iadd`, float math becomes `fadd double` or `dadd`. No Ruby method dispatch overhead.
- **Dynamic fallback** — The compiler couldn't determine the type. The call compiles to `rb_funcallv` (LLVM) or `invokedynamic` (JVM), which is the same speed as regular Ruby. The compiler emits a warning so you know where the boundaries are.

Adding RBS type annotations promotes dynamic fallbacks to native dispatch. You can leave them dynamic if you don't need the speed there — it's your call.

### Gems and Runtime Dependencies

When your code says `require "some_gem"`, the compiler checks whether the gem's source is available on the compile-time load path (specified by `-I`):

- **On the load path (`-I`)** — The gem's source files are compiled together with your code into a single extension. Method calls between your code and the gem use direct dispatch, monomorphization, and inlining.
- **Not on the load path** — The compiler emits a `rb_require("some_gem")` call so CRuby loads the gem at runtime. Your compiled code can still call the gem's methods, but those calls go through `rb_funcallv` (dynamic dispatch). This still works correctly — it's just not optimized.

In practice, many applications only need to compile their own code. Gems like UI frameworks, HTTP clients, or database drivers are often I/O-bound, so compiling them provides little benefit. Use `-I` when you want to maximize optimization across the entire codebase.

---

## LLVM Backend (CRuby Extension)

### Pattern 1: Extension Library

Write performance-critical functions in a `.rb` file, compile it, and `require` it from your regular Ruby application.

#### Step 1: Write the code

Wrap your code in a module to avoid polluting the top-level namespace:

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

Without RBS, HM inference will still resolve types from literals and call sites. But explicit types let the compiler optimize more aggressively:

```rbs
# physics.rbs
module Physics
  def self.distance: (Float x1, Float y1, Float x2, Float y2) -> Float
  def self.sum_distances: (Array[Float] xs, Array[Float] ys, Integer n) -> Float
end
```

#### Step 3: Compile

```bash
konpeito build physics.rb    # → physics.bundle (macOS) or physics.so (Linux)
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

**What's native here:** `distance` is fully native — `dx * dx + dy * dy` compiles to `fmul double` + `fadd double` instructions. The `while` loop in `sum_distances` is a native counter loop.

**What's dynamic:** `xs[i]` calls `rb_funcallv` on the Ruby Array (because the Array itself is a CRuby object, not a NativeArray). If you need that inner access to be native too, use `NativeArray[Float]`.

### Pattern 2: Whole Application

Compile an entire Ruby application. The compiler traces `require` / `require_relative` statements and compiles everything it can find on the load path into a single extension.

#### Example: A kumiki GUI app

[kumiki](https://github.com/i2y/kumiki) is a cross-platform desktop UI framework for Ruby. Here we compile a kumiki counter app as a single native extension.

##### Prerequisites

- Ruby 4.0.1+, LLVM 20, Konpeito
- kumiki (`gem install kumiki`)

##### Step 1: Write the app

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

##### Step 2: Compile

You have two choices here. Both produce a working `.bundle`, but with different optimization levels:

**Option A: Compile everything (whole application)**

```bash
konpeito build -I /path/to/kumiki/lib counter.rb
```

`-I` adds kumiki's `lib/` directory to the load path. The compiler resolves `require "kumiki"` and all of kumiki's internal requires, compiling 59 files into a single `counter.bundle` (971 KB). Method calls between your code and kumiki use direct dispatch; monomorphization and inlining are applied across the entire codebase.

**Option B: Compile only your code (extension library)**

```bash
konpeito build counter.rb
```

Without `-I`, the compiler compiles only `counter.rb` (50 KB). kumiki is loaded at runtime by CRuby via `rb_require`. Your code is still compiled natively, but calls into kumiki go through `rb_funcallv` (dynamic dispatch). For a GUI app this makes no practical difference — the rendering pipeline is I/O-bound.

##### Step 3: Run

```bash
ruby -r ./counter -e ""
```

- `-r ./counter` loads the extension. Its `Init` function runs the top-level code (creates the frame, component, and enters the event loop).
- `-e ""` provides an empty script so Ruby doesn't wait for stdin.
- **Do not** run `ruby -r ./counter counter.rb` — that loads the compiled extension (starting the app) and then runs `counter.rb` as pure Ruby (starting a second copy).

Use `-v` to see what the compiler does. The actual output for this build:

```
Resolved 59 files (kumiki's full source tree)
Stdlib requires (will be loaded at runtime): ranma, tmpdir, open-uri, ...

Inferred function types:
  CounterComponent#initialize: () -> nil
  CounterComponent#view: () -> untyped

Generated specializations:
  state(Integer) -> state_Integer
  Text(String)   -> Text_String
  Button(String) -> Button_String

Inlined 8 call site(s)
Finished in 3.25s -> counter.bundle (971 KB)
```

**What's native:**
- Class definitions (`CounterComponent`, and all 59 kumiki source files) — compiled into a single `.bundle`
- Method dispatch between compiled code (e.g., `column`, `row`, `text`, `button` DSL calls resolve to compiled kumiki methods)
- Monomorphized specializations — `state(Integer)`, `Text(String)`, `Button(String)` each get a type-specialized version
- `@count -= 1` — integer arithmetic in the button callback

**What's dynamic (runtime loaded by CRuby):**
- `ranma` (windowing), `tmpdir`, `open-uri`, `fileutils`, `digest`, `uri` — these are gems/stdlib that the compiler detects as runtime dependencies and does not compile. They are loaded by CRuby at runtime via `rb_require`
- `CounterComponent#view` returns `untyped` (the widget tree type isn't tracked by HM inference) — method calls on those return values use `rb_funcallv`
- This is fine — the rendering pipeline is I/O-bound, not CPU-bound

##### Larger example

kumiki's `all_widgets_demo.rb` (20+ widget types, 10 tabbed pages) compiles the same way:

```bash
konpeito build -I /path/to/kumiki/lib all_widgets_demo.rb
ruby -r ./all_widgets_demo -e ""
```

---

## JVM Backend (Standalone JAR)

The JVM backend compiles Ruby code into JVM bytecode and packages it as a standalone JAR. No Ruby installation is needed to run the output.

### Standalone Program

JVM backend produces standalone JARs — the entire program is compiled, including `puts` at the top level.

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

#### Compile and run

```bash
konpeito build --target jvm --run physics_jvm.rb
```

Or produce a JAR and run it separately:

```bash
konpeito build --target jvm -o physics.jar physics_jvm.rb
java -jar physics.jar
```

The JAR is self-contained — no Ruby installation needed on the target machine.

### Pattern 2: GUI Application (Castella UI)

The JVM backend supports [Castella UI](castella-ui.md), a reactive GUI framework based on Skia rendering.

#### Prerequisites

Clone the Konpeito repository and run the setup script:

```bash
cd konpeito/examples/castella_ui
bash setup.sh    # downloads JWM + Skija JARs (~30 MB, one-time)
```

#### Run the counter demo

```bash
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

See [Getting Started](getting-started.md) for more Castella UI details, widget catalog, and themes.

---

## Tips

- `konpeito build -v` shows inferred types and dynamic fallback warnings
- `konpeito build -g` emits DWARF debug info for `lldb` / `gdb` (LLVM backend)
- `konpeito check` runs type checking without code generation — useful for finding type issues early
- Add RBS annotations where you see dynamic fallback warnings and want native speed
- For compute-heavy inner loops, prefer `NativeArray[T]` / `StaticArray[T,N]` over Ruby `Array` — they store unboxed values in contiguous memory (LLVM backend)
- Use `--inline` to write RBS annotations directly in Ruby source files (rbs-inline format)
