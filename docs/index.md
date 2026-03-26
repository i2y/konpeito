---
layout: default
title: Home
nav_order: 1
permalink: /
---

# Konpeito

> *Konpeito (konpeito) — Japanese sugar crystals. Crystallizing Ruby into native code.*

A gradually typed Ruby compiler with Hindley-Milner type inference, three backends (LLVM, JVM, mruby), and seamless interop with C and Java.

Write ordinary Ruby. Konpeito infers types automatically, compiles to fast native code, and falls back to dynamic dispatch where it can't resolve statically — with a warning so you always know.

---

## How It Works

Konpeito uses a three-tier type resolution strategy:

1. **HM inference** resolves most types automatically — no annotations needed.
2. **RBS annotations** add precision where needed. Optional type hints that help the compiler optimize further.
3. **Dynamic fallback** handles the rest. Unresolved calls compile to runtime dispatch, and the compiler warns you.

## Architecture

```
Source (.rb) + Types (.rbs)
        |                |
        v                v
   +----------+    +------------+
   |  Prism   |    | RBS::Parser|
   +----+-----+    +-----+------+
        |                |
        v                v
   +------------------------+
   |   HM Type Inferrer     |
   | (Algorithm W + RBS)    |
   +-----------+------------+
               |
               v
   +------------------------+
   |     Typed AST          |
   +-----------+------------+
               |
               v
   +------------------------+
   |     HIR Generator      |
   +-----------+------------+
               |
        +------+------+--------+
        v             v        v
   +---------+   +--------+  +----------+
   |  LLVM   |   |  JVM   |  |  mruby   |
   |Generator|   |  Gen   |  | (LLVM +  |
   +----+----+   +---+----+  | mruby RT)|
        |             |       +----+-----+
        v             v            v
   +---------+   +--------+  +----------+
   |CRuby Ext|   |  JAR   |  |Standalone|
   |  (.so)  |   | (.jar) |  |Executable|
   +---------+   +--------+  +----------+
```

## Quick Start

```bash
# Install
gem install konpeito

# Compile to CRuby extension
konpeito build src/main.rb

# Compile to JVM JAR
konpeito build --target jvm -o output.jar src/main.rb

# Compile to standalone executable (mruby)
konpeito build --target mruby -o app src/main.rb

# Type check only
konpeito check src/main.rb
```

See the [Getting Started](getting-started.md) guide and [Tutorial](tutorial.md) for detailed walkthroughs.

## Key Features

| Feature | Description |
|---------|-------------|
| **Three backends** | LLVM (CRuby extensions), JVM (standalone JARs), mruby (standalone executables) |
| **HM type inference** | Types inferred automatically, RBS optional |
| **Unboxed arithmetic** | Integer/Float operations use native CPU instructions |
| **Native data structures** | NativeArray, NativeClass, NativeHash, StaticArray, Slice |
| **C interop** | `@cfunc`/`@ffi` for direct C library calls |
| **SIMD** | `@simd` annotation for vector operations |
| **Castella UI** | Cross-platform GUI framework (JVM backend) |
| **KUI** | 66-widget declarative UI framework — GUI and TUI from the same code (mruby backend) |
| **Raylib stdlib** | Graphics, audio, input for game development (mruby backend) |
| **Game framework** | Physics, tween, particles, FSM, tilemap, and more (mruby backend) |
| **Pattern matching** | Full `case/in` support |
| **Concurrency** | Fiber, Thread, Mutex, Ractor (JVM) |

## Documentation

- [Getting Started](getting-started.md) — Installation and first steps
- [Tutorial](tutorial.md) — Step-by-step walkthrough
- [CLI Reference](cli-reference.md) — Command-line usage
- [API Reference](api-reference.md) — Castella UI and stdlib APIs
- [Language Specification](language-specification.md) — Supported syntax and semantics
