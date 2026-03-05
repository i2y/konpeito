# Konpeito

> *Konpeito (konpeitō) — Japanese sugar crystals. Crystallizing Ruby into native code.*

A gradually typed Ruby compiler with Hindley-Milner type inference, dual LLVM/JVM backends, and seamless Java interop.

Write ordinary Ruby. Konpeito infers types automatically, compiles to fast native code, and falls back to dynamic dispatch where it can't resolve statically — with a warning so you always know.

## How It Works

Konpeito uses a three-tier type resolution strategy:

1. **HM inference** resolves most types automatically — no annotations needed. Like Crystal, but for Ruby.
2. **RBS annotations** add precision where needed. Optional type hints that help the compiler optimize further.
3. **Dynamic fallback** handles the rest. Unresolved calls compile to runtime dispatch (LLVM: `rb_funcallv`, JVM: `invokedynamic`), and the compiler warns you.

Adding an RBS signature promotes a dynamic fallback to static dispatch. The compiler tells you where the boundaries are — fix them if you want, or leave them dynamic. Your call.

## What Gets Compiled

Konpeito compiles your `.rb` source files into native code. Understanding the boundary between compiled and non-compiled code is key:

**Compiled (native code):**
- All `.rb` files you pass to `konpeito build`
- Files resolved via `require` / `require_relative` at compile time (when source is available on the load path via `-I`)
- Within compiled code: type-resolved operations become native CPU instructions; unresolved operations fall back to `rb_funcallv` (CRuby's dynamic dispatch) with a compiler warning

**Not compiled (loaded at runtime by CRuby):**
- Installed gems referenced by `require` — the compiler detects these and emits `rb_require` calls so CRuby loads them at runtime
- Standard libraries (`json`, `net/http`, `fileutils`, etc.) — same treatment
- Any Ruby code running in the host CRuby process outside the compiled extension

The compiled extension and CRuby coexist in the same process. Native code calls CRuby C API functions (`rb_define_class`, `rb_funcallv`, `rb_ary_push`, etc.), so compiled code can freely create Ruby objects, call Ruby methods, and interact with any loaded gem. The speed gain comes from the parts where Konpeito resolves types and emits native instructions instead of going through Ruby's method dispatch.

This leads to two usage patterns:

### Pattern 1: Extension Library

Compile performance-critical code into a CRuby extension (`.bundle` / `.so`). Your main application stays as regular Ruby and loads the compiled code via `require`:

```ruby
# math.rb — compiled by Konpeito
module MyMath
  def self.sum_up_to(n)
    total = 0
    i = 1
    while i <= n
      total += i
      i += 1
    end
    total
  end
end
```

```bash
konpeito build math.rb   # → math.bundle
```

```ruby
# app.rb — regular Ruby, NOT compiled
require_relative "math"
puts MyMath.sum_up_to(10_000_000)   # calls into compiled native code
```

Your code can `require` installed gems freely. The compiler compiles your code and emits runtime `require` calls for the gems, so everything works together at runtime:

```ruby
# my_app.rb — compiled by Konpeito
require "kumiki"     # gem — loaded at runtime by CRuby
include Kumiki

class MyComponent < Component
  # ... your code is compiled natively
  # ... calls to kumiki methods go through rb_funcallv (dynamic dispatch)
end
```

This is the pattern shown in [Hello World](#hello-world) below.

### Pattern 2: Whole Application

Compile an entire Ruby application including framework code — the compiler traces all `require` statements on the load path specified by `-I` and compiles everything into a single extension:

```bash
konpeito build -I /path/to/kumiki/lib counter.rb   # → counter.bundle (971 KB)
ruby -r ./counter -e ""                             # load and run
```

The difference from Pattern 1: framework code (kumiki) is also compiled, enabling direct dispatch, monomorphization, and inlining across the entire codebase. Without `-I`, only your code is compiled (~50 KB) and the framework is loaded at runtime — this still works, but method calls into the framework go through dynamic dispatch.

See [Tutorial](docs/tutorial.md) for step-by-step walkthroughs of both patterns with working examples.

## Quick Start

### Prerequisites

Ruby 4.0+ is required. Java 21+ is needed for the JVM backend. LLVM 20 is needed only for the CRuby native backend.

```bash
gem install konpeito
```

**JVM backend** (recommended — standalone JARs, Castella UI, Java interop):
```bash
# macOS
brew install openjdk@21

# Ubuntu / Debian
sudo apt install openjdk-21-jdk

# Fedora
sudo dnf install java-21-openjdk-devel

# Windows (MSYS2 / MinGW)
winget install EclipseAdoptium.Temurin.21.JDK
```

**CRuby native backend** (optional — C extensions):
```bash
gem install ruby-llvm

# macOS
brew install llvm@20
ln -sf /opt/homebrew/opt/llvm@20/lib/libLLVM-20.dylib /opt/homebrew/lib/

# Ubuntu / Debian
sudo apt install llvm-20 clang-20

# Fedora
sudo dnf install llvm20 clang20

# Windows (MSYS2 / MinGW)
winget install LLVM.LLVM
```

### Hello World

Write a small Ruby file:

```ruby
# math.rb
module MyMath
  def self.add(a, b)
    a + b
  end

  def self.sum_up_to(n)
    total = 0
    i = 1
    while i <= n
      total = total + i
      i = i + 1
    end
    total
  end
end
```

Compile and use it from Ruby:

```bash
konpeito build math.rb          # produces math.bundle (macOS), math.so (Linux), or math.dll (Windows)
```

```ruby
require_relative "math"
puts MyMath.add(3, 4)        # => 7
puts MyMath.sum_up_to(100)   # => 5050
```

### CLI Overview

```bash
konpeito build src/main.rb                          # compile to CRuby extension
konpeito build --target jvm -o app.jar src/main.rb  # compile to standalone JAR
konpeito run src/main.rb                            # build and run in one step
konpeito check src/main.rb                          # type check only (no codegen)
konpeito init my_project                            # scaffold a new project
konpeito test                                       # run project tests
konpeito fmt                                        # format source files
konpeito watch src/main.rb                          # auto-recompile on changes
konpeito doctor                                     # check your environment
```

For detailed options and examples, see [CLI Reference](docs/cli-reference.md).

## Features

- **HM Type Inference** — Types are inferred automatically. No annotations needed for most code.
- **Gradual Typing** — Static where possible, dynamic where necessary. The compiler shows you the boundary.
- **Flow Typing** — Type narrowing via `if x.nil?`, `case/in Integer`, boolean guards, and more.
- **Unboxed Arithmetic** — Integer and Float operations compile to native CPU instructions, skipping Ruby's method dispatch entirely.
- **Loop Optimizations** — LICM, inlined iterators (`each`, `map`, `reduce`, `times`), and LLVM O2 passes.
- **CRuby C Extensions** — Output plugs directly into your existing Ruby app via `require`.
- **JVM Backend** — Generate standalone `.jar` files that run on any Java 21+ VM.
- **Java Interop** — Call Java libraries directly with full type safety. Java type information flows into HM inference automatically.
- **Native Data Structures** — `NativeArray[T]`, `NativeHash[K,V]`, `StaticArray[T,N]`, `Slice[T]`, `@struct` value types for high-performance data handling.
- **C Interop** — Call external C libraries with `%a{cfunc}` / `%a{ffi}`, plus built-in HTTP (libcurl), Crypto (OpenSSL), and Compression (zlib) modules.
- **SIMD Vectorization** — `%a{simd}` compiles vector types to LLVM vector instructions.
- **Operator Overloading** — Define `+`, `-`, `*`, `==`, `<=>`, etc. on your own classes with full type inference.
- **Pattern Matching** — Full `case/in` support with array, hash, guard, and capture patterns.
- **Modern Ruby Syntax** — `_1`/`_2` numbered params, `it`, endless methods, `class << self`, safe navigation (`&.`), and more.
- **Concurrency** — Fiber, Thread, Mutex, ConditionVariable, SizedQueue, and Ractor (with `Ractor::Port`, `Ractor.select`, `Ractor[:key]` local storage, `name:`, `monitor`/`unmonitor`). JVM Ractor uses Virtual Threads for scheduling but does not enforce object isolation — objects are shared by reference, unlike CRuby's strict isolation model.
- **Built-in Tooling** — Formatter (`fmt`), debug info (`-g`), and profiling (`--profile`).
- **Castella UI** — A reactive GUI framework for the JVM backend (see below).

## Supported Ruby Syntax

Konpeito supports most Ruby 4.0 syntax:

| Category | Supported |
|----------|-----------|
| Literals | Integer, Float, String, Symbol, Array, Hash, Regexp, Range, Heredoc, nil/true/false |
| String interpolation | `"Hello #{name}"` |
| Variables | Local, `@instance`, `@@class`, `$global` |
| Control flow | `if`/`unless`, `while`/`until`, `for`, `case`/`when`, `case`/`in`, `break`, `next`, `return` |
| Methods & OOP | Classes, modules, inheritance, `super`, `attr_accessor`, method visibility (`private`/`protected`) |
| Blocks & closures | `yield`, `block_given?`, Proc, Lambda, `&blk` |
| Pattern matching | Literals, arrays, hashes, guards (`if`), captures (`=>`), pins (`^`), rest (`*`) |
| Exceptions | `begin`/`rescue`/`else`/`ensure`, custom exception classes |
| Modern syntax | `_1`/`_2` numbered params, `it`, endless methods, `class << self`, `&.` safe navigation |
| Operators | Full overloading (`+`, `-`, `*`, `==`, `<=>`, etc.), compound assignment (`+=`, `\|\|=`, `&&=`) |
| Arguments | Keyword args, rest args (`*args`), keyword rest (`**kwargs`), splat (`foo(*arr)`) |
| Concurrency | Fiber, Thread, Mutex, ConditionVariable, SizedQueue, Ractor (JVM) |
| Misc | `alias`, `defined?`, open classes, multi-assignment, `%w`/`%i` literals |

### Not Supported (by design)

- `eval`, `instance_eval`, `class_eval`
- `define_method`, `method_missing`
- `ObjectSpace`, `Binding`
- Dynamic `require`/`load` (variable-based require)

For the complete specification, see [Language Specification](docs/language-specification.md).

## JVM Backend

Konpeito can also compile to JVM bytecode, producing standalone JAR files:

```bash
konpeito build --target jvm -o app.jar main.rb
# or compile and run immediately:
konpeito build --target jvm --run main.rb
```

The JVM backend supports seamless Java interop — call Java libraries directly from your Ruby code without writing any glue. Java type information is introspected from the classpath and fed into HM inference, so calling Java APIs is type-safe without annotations.

## Castella UI

A reactive GUI framework for the JVM backend, powered by [JWM](https://github.com/HumbleUI/JWM) + [Skija](https://github.com/HumbleUI/Skija).

### DSL

Ruby's block syntax becomes a UI DSL — `column`, `row`, `text`, `button` etc. nest naturally with keyword arguments. A plain Ruby method is a reusable component.

<p align="center">
  <img src="docs/screenshots/dashboard.png" alt="Analytics Dashboard" width="720" />
</p>

```ruby
def view
  column(padding: 20.0, spacing: 16.0) {
    row(spacing: 12.0) {
      text("Analytics Dashboard", font_size: 26.0, bold: true)
      spacer
      button("Refresh", width: 90.0) {}
    }.fixed_height(40.0)

    # KPI Cards — extract a method, and it's a reusable component
    row(spacing: 12.0) {
      kpi_card("Revenue", "$48,250", "+12.5%", $theme.accent)
      kpi_card("Users",   "3,842",   "+8.1%",  $theme.success)
      kpi_card("Orders",  "1,205",   "-2.3%",  $theme.error)
    }

    # Charts, tables, and layouts compose with blocks
    row(spacing: 12.0) {
      column(expanding_width: true, bg_color: $theme.bg_primary, border_radius: 10.0, padding: 14.0) {
        bar_chart(labels, data, ["Revenue", "Costs"]).title("Monthly Overview").fixed_height(220.0)
      }
      column(expanding_width: true, bg_color: $theme.bg_primary, border_radius: 10.0, padding: 14.0) {
        data_table(headers, widths, rows).fixed_height(200.0)
      }
    }
  }
end

# A Ruby method is a reusable component
def kpi_card(label, value, change, color)
  column(spacing: 6.0, bg_color: $theme.bg_primary, border_radius: 10.0, padding: 16.0, expanding_width: true) {
    text(label, font_size: 12.0, color: $theme.text_secondary)
    text(value, font_size: 24.0, bold: true)
    text(change, font_size: 13.0, color: color)
  }
end
```

### Reactive State

`state(0)` creates an observable value, and the UI re-renders automatically when it changes:

<p align="center">
  <img src="docs/screenshots/counter.png" alt="Counter App" width="320" />
</p>

```ruby
class Counter < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    column(padding: 16.0, spacing: 8.0) {
      text "Count: #{@count}", font_size: 32.0, align: :center
      row(spacing: 8.0) {
        button(" - ") { @count -= 1 }
        button(" + ") { @count += 1 }
      }
    }
  end
end
```

An OOP-style API (`Column(...)`, `Row(...)`) is also available. Available widgets: `Text`, `Button`, `TextInput`, `MultilineText`, `Column`, `Row`, `Image`, `Checkbox`, `Slider`, `ProgressBar`, `Tabs`, `DataTable`, `TreeView`, `BarChart`, `LineChart`, `PieChart`, `Markdown`, and more.

### Style Composition

Styles are first-class objects — store them in variables and compose with `+`:

<p align="center">
  <img src="docs/screenshots/style_composition.png" alt="Style Composition" width="480" />
</p>

```ruby
card = Style.new.bg_color($theme.bg_primary).border_radius(10.0).padding(16.0)
green_card = card + Style.new.border_color($theme.success)

column(spacing: 12.0) {
  container(card)       { text "Default card" }
  container(green_card) { text "Green border variant" }
}
```

### Calculator Demo

A port of the original Python Castella calculator. Flex layout, button kinds (`KIND_DANGER`, `KIND_WARNING`, `KIND_SUCCESS`), reactive `state()`, and class methods called from instance method callbacks — all in ~130 lines:

<p align="center">
  <img src="docs/screenshots/calc.png" alt="Calculator" width="320" />
</p>

```ruby
class Calc < Component
  def initialize
    super
    @display = state("0")
    @lhs = 0.0
    @current_op = ""
    @is_refresh = true
  end

  # --- Calculator logic ---

  def press_number(label)
    if @display.value == "0" || @is_refresh
      @display.set(label)
    else
      @display.set(@display.value + label)
    end
    @is_refresh = false
  end

  def press_dot
    if @is_refresh
      @display.set("0.")
      @is_refresh = false
      return
    end
    if !@display.value.include?(".")
      @display.set(@display.value + ".")
    end
  end

  def all_clear
    @display.set("0")
    @lhs = 0.0
    @current_op = ""
    @is_refresh = true
  end

  def self.calc(lhs, op, rhs)
    if op == "+"
      lhs + rhs
    elsif op == "-"
      lhs - rhs
    elsif op == "\u00D7"
      lhs * rhs
    elsif op == "\u00F7"
      if rhs == 0.0
        0.0
      else
        lhs / rhs
      end
    else
      rhs
    end
  end

  def self.format_result(val)
    if val == val.to_i.to_f
      val.to_i.to_s
    else
      val.to_s
    end
  end

  def press_operator(new_op)
    rhs = @display.value.to_f
    if @current_op != ""
      result = Calc.calc(@lhs, @current_op, rhs)
      @display.set(Calc.format_result(result))
      @lhs = result
    else
      @lhs = rhs
    end
    if new_op == "="
      @current_op = ""
    else
      @current_op = new_op
    end
    @is_refresh = true
  end

  # --- View ---

  def view
    grid = Style.new.spacing(4.0)
    btn  = Style.new.font_size(32.0)
    op   = btn + Style.new.kind(KIND_WARNING)
    ac   = btn + Style.new.kind(KIND_DANGER).flex(3)
    eq   = btn + Style.new.kind(KIND_SUCCESS)
    wide = btn + Style.new.flex(2)

    column(spacing: 4.0, padding: 4.0) {
      text @display.value, font_size: 48.0, align: :right, kind: KIND_INFO, height: 72.0
      row(grid) {
        button("AC", ac) { all_clear }
        button("\u00F7", op) { press_operator("\u00F7") }
      }
      row(grid) {
        button("7", btn) { press_number("7") }
        button("8", btn) { press_number("8") }
        button("9", btn) { press_number("9") }
        button("\u00D7", op) { press_operator("\u00D7") }
      }
      row(grid) {
        button("4", btn) { press_number("4") }
        button("5", btn) { press_number("5") }
        button("6", btn) { press_number("6") }
        button("-", op) { press_operator("-") }
      }
      row(grid) {
        button("1", btn) { press_number("1") }
        button("2", btn) { press_number("2") }
        button("3", btn) { press_number("3") }
        button("+", op) { press_operator("+") }
      }
      row(grid) {
        button("0", wide) { press_number("0") }
        button(".", btn) { press_dot }
        button("=", eq) { press_operator("=") }
      }
    }
  end
end

frame = JWMFrame.new("Castella Calculator", 320, 480)
app = App.new(frame, Calc.new)
app.run
```

## Performance

Konpeito targets compute-heavy, typed loops where unboxed arithmetic and backend optimizations can make a meaningful difference. Actual speedups depend heavily on the workload, input data, and hardware — the numbers below are from one specific environment and should be taken as rough indicators, not guarantees.

### LLVM Backend (CRuby Extension)

Typical speedup ranges observed on our test machine (vs Ruby YJIT):

- **Numeric loops** (arithmetic, counters, reductions): often **5–80x** faster, depending on how much of the loop body can be fully unboxed
- **Native data structures** (NativeArray, StaticArray): **~10–60x** faster for tight element-access loops
- **Iterator inlining** (each, map, reduce, times): **~7–50x** faster with typed arrays or ranges

These figures reflect native-internal performance — the loop itself runs entirely inside compiled code. Cross-boundary calls (Ruby ↔ native) see smaller gains due to interop overhead.

**Where Konpeito is slower:** Pattern matching (`case/in`) is currently **~2–3x slower** than YJIT — Ruby's VM is highly optimized for this. String operations (NativeString) are also slower than CRuby's mature string implementation due to conversion overhead. Workloads that are I/O-bound, rely heavily on dynamic features, or hit areas where YJIT already excels may see no benefit or even regressions.

### JVM Backend (Standalone JAR)

For numeric workloads, the JVM backend typically shows **~30–60x** speedups over Ruby YJIT, benefiting from HotSpot's JIT on top of Konpeito's static type resolution. I/O-bound or polymorphic code will see less improvement.

> **Test environment:** Apple M4 Max, Ruby 4.0.1 + YJIT, Java 21.0.10 (HotSpot), macOS 15. Results will vary on different hardware and configurations.

## Documentation

### User Guides

- **[Getting Started](docs/getting-started.md)** — Installation, Hello World, first project, Castella UI tutorial
- **[Tutorial](docs/tutorial.md)** — Extension library and whole-application compilation patterns
- **[CLI Reference](docs/cli-reference.md)** — All commands, options, and configuration
- **[API Reference](docs/api-reference.md)** — Castella UI widgets, native data structures, standard library

### Architecture & Design

- **[Architecture](docs/architecture.md)** — Full compiler pipeline, design philosophy, and roadmap
- **[JVM Backend](docs/architecture-jvm.md)** — Dual-backend strategy, JVM codegen, Java interop
- **[Castella UI](docs/castella-ui.md)** — GUI framework design and widget reference
- **[Native Stdlib Proposal](docs/native-stdlib-proposal.md)** — NativeArray, StaticArray, Slice, and friends
- **[Language Specification](docs/language-specification.md)** — Supported syntax, type system rules, backend behavior
- **[RBS Requirements](docs/rbs-requirements-en.md)** — When you need RBS files and when you don't

## Requirements

| Dependency | Version | Required for |
|---|---|---|
| Ruby | 4.0.1+ | Always |
| Java | 21+ | JVM backend |
| LLVM | 20 | CRuby native backend |
| ruby-llvm gem | ~> 20.1 | CRuby native backend |
| Platform | macOS (ARM64/x64), Linux (x64/ARM64), Windows (x64, MSYS2/MinGW) | — |

## Built with AI

This project was developed collaboratively between a human director ([Yasushi Itoh](https://github.com/i2y)) and [Claude Code](https://claude.com/claude-code) by Anthropic. The human set the vision, made design decisions, and guided the direction; the AI wrote the implementation. It's an experiment in what's possible when human judgment meets AI capability.

## Status

Konpeito is in an early stage. Bugs and undocumented limitations should be expected. Actively improving — bug reports and feedback are very welcome.

Both LLVM and JVM backends are tested against the project's conformance test suite covering core language features (control flow, classes, blocks, exceptions, pattern matching, concurrency, etc.). The LLVM backend has been successfully used to compile and run [kumiki](https://github.com/i2y/kumiki)'s `all_widgets_demo.rb` — a non-trivial reactive GUI application with 20+ widget types — as a CRuby extension.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions and guidelines.

The core principle: **no ambiguous behavior**. If the compiler can't determine a type, it falls back to dynamic dispatch with a warning — never guesses heuristically. Adding RBS promotes the fallback to static dispatch.

## License

[MIT](LICENSE) — Copyright (c) 2026 Yasushi Itoh
