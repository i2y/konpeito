# Konpeito — Development Guide

Ruby AOT native compiler. Prism + RBS + HM type inference → LLVM/JVM/mruby backends.

## Compiler Design Principles

- **No ambiguous behavior**: When a type is unknown, either infer it correctly or fall back to dynamic dispatch (with a warning)
- **HM inference first, RBS is supplementary**: Code must work without RBS. Adding RBS promotes dynamic dispatch to static dispatch
- **No heuristic guessing**: Never search all classes for a matching method name to guess the receiver type
- **JVM backend**: Follow Kotlin's type inference and code generation patterns as reference

## Build & Test

```bash
bundle install
bundle exec rake test          # All tests (LLVM + JVM)

# Specific test
bundle exec ruby -Ilib:test test/type_checker/hm_inferrer_test.rb

# mruby backend build & run
konpeito build --target mruby -o app src/main.rb
konpeito run --target mruby src/main.rb
```

## Key Directories

```
lib/konpeito/
├── cli.rb                  # CLI
├── compiler.rb             # Main compiler
├── platform.rb             # Platform detection (all path resolution centralized here)
├── parser/                 # Prism adapter
├── type_checker/           # HM inference (hm_inferrer.rb), RBS loader, type representation
├── hir/                    # HIR node definitions & AST→HIR conversion
├── codegen/
│   ├── llvm_generator.rb   # LLVM IR generation
│   ├── cruby_backend.rb    # CRuby extension (.so/.bundle)
│   ├── jvm_generator.rb    # JVM JSON IR generation
│   ├── jvm_backend.rb      # JVM .jar packaging
│   ├── mruby_backend.rb    # mruby standalone executable
│   └── mruby_helpers.c     # CRuby→mruby bridge functions
├── stdlib/                 # cfunc libraries for mruby backend
│   ├── raylib/             # Graphics (raylib)
│   ├── clay/               # GUI layout (Clay + raylib)
│   ├── clay_tui/           # Terminal UI (Clay + termbox2)
│   ├── shell/              # Shell execution & file I/O
│   ├── json/               # JSON (yyjson)
│   ├── http/               # HTTP (libcurl)
│   ├── crypto/             # Cryptography (OpenSSL)
│   ├── compression/        # Compression (zlib)
│   └── kui/                # KUI declarative UI DSL (Pure Ruby, wraps Clay/ClayTUI)
vendor/
├── clay/                   # Clay v0.14 (zlib/libpng license)
├── termbox2/               # termbox2 (MIT license)
└── yyjson/                 # yyjson (MIT license)
```

## Stdlib Auto-Detection

Module references in source code are auto-detected and injected (`compiler.rb` `STDLIB_MODULE_MAP`):

| Module Reference | stdlib | Purpose |
|-----------------|--------|---------|
| `Raylib` | raylib/ | Graphics |
| `Clay` | clay/ | GUI layout (raylib) |
| `ClayTUI` | clay_tui/ | TUI layout (termbox2) |
| `KonpeitoShell` | shell/ | Shell execution & file I/O |
| `KonpeitoJSON` | json/ | JSON parse/generate |
| `KonpeitoHTTP` | http/ | HTTP client |
| `KonpeitoCrypto` | crypto/ | Cryptography |
| `KonpeitoCompression` | compression/ | Compression |

## KUI — Declarative UI Framework

Pure Ruby DSL for building GUI/TUI apps with a single codebase. Wraps Clay+Raylib (GUI) or ClayTUI (TUI).

```ruby
# require "kui_gui" for GUI, or "kui_tui" for TUI
require "kui_gui"

def draw
  vpanel pad: 16, gap: 8 do
    label "Hello", size: 24
    button "Click me", size: 18 do
      # handle click
    end
  end
end

def main
  kui_init("App", 800, 600)
  kui_theme_dark
  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end
  kui_destroy
end
```

Build: `konpeito build --target mruby -o app app.rb`

## Coding Conventions

- No hardcoded paths. Platform-specific logic is centralized in `platform.rb`
- Never assign null for unsupported calls. Fall back to dynamic dispatch instead
- Top-level method type annotations use `module TopLevel` (not `class Object`)

## Documentation

See `docs/` for details:
- `docs/getting-started.md` — Getting started guide
- `docs/tutorial.md` / `docs/tutorial-ja.md` — Tutorials (EN/JA)
- `docs/language-specification.md` — Language specification
- `docs/api-reference.md` — API reference
- `docs/cli-reference.md` — CLI reference
- `docs/rbs-requirements-en.md` — When RBS files are needed
- `docs/guides.md` — Advanced guides
