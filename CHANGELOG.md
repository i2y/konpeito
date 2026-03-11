# Changelog

All notable changes to Konpeito will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-03-11

### Added
- **Raylib stdlib expansion**: 119 new cfunc bindings (87 → 206 total) for 2D RPG/SLG game development
  - Texture/Sprite management (10): load, unload, draw, draw_rec, draw_pro, draw_scaled, dimensions, validity check
  - Audio — Sound (10): load, unload, play, stop, pause, resume, playing?, volume, pitch
  - Audio — Music (13): load, unload, play, stop, pause, resume, update, playing?, volume, pitch, time_length, time_played, seek
  - Audio — Device (4): init, close, ready?, master volume
  - Camera2D (4): begin/end mode, world-to-screen coordinate conversion (x/y)
  - File I/O (4): save/load text files, file/directory existence checks
  - Font management (6): load, load_ex, unload, draw_text_ex, measure_text_ex (x/y)
  - Gamepad input (7 + 21 constants): button pressed/down/released/up, axis movement/count, D-pad/face/trigger/middle button and axis constants
  - Extended shapes (5): draw_rectangle_pro, draw_rectangle_rounded, gradient v/h, circle sector
  - Collision detection (5): recs, circles, circle-rec, point-rec, point-circle
  - ID table pattern for resource management: textures (256), sounds (128), music (32), fonts (32)
- **RPG tilemap demo**: `examples/mruby_rpg_demo/rpg_demo.rb` — 40×40 tilemap, smooth camera scrolling, 4-direction player movement with animation, sign interaction, HUD with step counter
- macOS audio framework linker flags (CoreAudio, AudioToolbox, CoreFoundation)

### Fixed
- **Inliner CFuncCall bug**: `clone_and_rename()` now handles `CFuncCall`, `ExternConstructorCall`, and `ExternMethodCall` — parameters are correctly remapped when user functions calling `@cfunc` are inlined (previously fell through to default case, returning instructions with unmapped parameters)
- **CI lint**: use anonymous block forwarding (`&`) in `rbs_loader.rb`
- **CI test isolation**: use unique symbol names in `module_native_array_test` to avoid ELF symbol interposition on Linux

## [0.5.0] - 2026-03-10

### Added
- **Clay UI layout stdlib**: Flexbox-style UI layout library for the mruby backend. `module Clay` auto-detected like raylib — 40+ `%a{cfunc}` bindings covering lifecycle, element construction, text, borders, scrolling, floating elements, and bulk rendering via the official raylib renderer. Vendored Clay v0.14 under `vendor/clay/`.
- **Clay UI demo**: `examples/mruby_clay_ui/clay_demo.rb` — sidebar + main content layout with TTF fonts
- **Memory Match game**: `examples/mruby_clay_ui/memory_game.rb` — card matching game using Clay layout system with module NativeArray game state
- **Module NativeArray**: fixed-size global arrays shared across functions via RBS module instance variables (`@field: NativeArray[T, N]`). Compiles to LLVM global arrays — no C wrapper file needed. Available on LLVM (CRuby) and mruby backends.
- **Inline RBS module blocks**: `# @rbs module Foo ... # @rbs end` comment blocks are now extracted by the preprocessor and emitted as raw RBS, enabling module NativeArray declarations without separate `.rbs` files or empty `module Foo; end` stubs.
- **Space Invaders example rewrite**: `examples/mruby_space_invaders/` rewritten to use module NativeArray with inline RBS — single `.rb` file, no C wrapper or separate `.rbs` needed
- **Third-party license file**: `THIRD_PARTY_LICENSES.md` summarizing vendored library licenses (yyjson, Clay)

### Fixed
- **NativeArray GEP stride**: fix `gep` → `gep2` for all NativeArray element access (14 call sites). With LLVM opaque pointers, `gep` used array type as stride instead of element type, causing memory corruption and SIGSEGV crashes.

## [0.4.2] - 2026-03-10

### Fixed
- **Linux symbol collision**: use `internal` linkage for LLVM callback functions to prevent flat namespace collisions on Linux
- **NativeClass ptr→VALUE**: add missing `ptr2int` conversion for NativeClass objects passed to CRuby APIs
- **JSON codegen tests**: skip when vendored yyjson source is unavailable (CI environments)
- **CI stabilization**: run codegen tests per-file in separate processes to prevent `.so` accumulation crashes

### Added
- **macOS ARM CI job**: unit tests and codegen tests on `macos-latest` (ARM)
- **mruby CI job**: build and run verification with `konpeito run --target mruby`
- **Japanese tutorial**: add mruby backend section (5.5) matching English tutorial

### Changed
- Update `actions/checkout` v4 → v6, `actions/setup-java` v4 → v5

## [0.4.1] - 2026-03-09

### Added
- `THIRD_PARTY_NOTICES.md` — vendored code and linked library license summary
- `vendor/yyjson/LICENSE` — MIT license file for vendored yyjson
- mruby backend: auto-generate `<output>.LICENSES.txt` alongside standalone executables
  - Always includes Konpeito (MIT) and mruby (MIT)
  - Conditionally includes yyjson (MIT) when JSON stdlib is used
  - Conditionally includes raylib (zlib) when raylib stdlib is used

### Changed
- `.gitignore`: allow `vendor/yyjson/LICENSE` to be tracked

## [0.4.0] - 2026-03-08

### Added
- **mruby backend**: standalone executable generation (`konpeito build --target mruby`)
  - CRuby-compatible C wrappers (`mruby_helpers.c`) — same LLVM IR for both runtimes
  - Block/yield, Proc, Fiber, exception handling support
  - Static linking for FFI libraries
  - Compilation caching for `konpeito run --target mruby`
- **Cross-compilation**: `--cross` + `--cross-mruby` + zig cc for targeting other platforms
- **raylib stdlib**: zero-boilerplate game development for mruby backend
  - 87 cfunc bindings (window, drawing, text, keyboard, mouse, colors, keys, random)
  - Auto-detected when `module Raylib` is referenced — no manual setup needed
- **Game examples**: Breakout and catch game demos (`examples/mruby_breakout/`, `examples/mruby_stdlib_demo/`)
- Documentation: mruby backend, raylib stdlib, and cross-compilation guides

### Fixed
- MergedAST handling in stdlib auto-detection
- Float/double ABI mismatch in mruby runtime
- mruby truthiness check compatibility
- Skip stdlib tests when native extension build fails on CI

## [0.3.1] - 2026-03-07

### Added
- Compilation caching for `konpeito run` — cached artifacts in `.konpeito_cache/run/`
- Jekyll/GitHub Pages documentation site with just-the-docs theme

### Fixed
- GitHub Pages baseurl resolution for step IDs

### Changed
- Documentation restructured: Getting Started now leads with CRuby backend
- Removed speculative performance claims and inaccurate benchmark numbers from docs
- Language specification: removed benchmark numbers, fixed Known Limitations

## [0.3.0] - 2026-03-05

### Added
- GitHub Actions CI workflow (unit tests + conformance tests)
- `examples/README.md` — guide to all example files and how to run them
- gemspec metadata: `source_code_uri`, `documentation_uri`
- Milestone: successfully compiled and ran kumiki's `all_widgets_demo.rb` (20+ widget reactive GUI) as a CRuby extension
- Tutorial (`docs/tutorial.md`) with working examples for both CRuby and JVM backends
- Japanese translation of tutorial (`docs/tutorial-ja.md`)
- Shell completion scripts (`konpeito completion bash/zsh/fish`)
- `konpeito fmt` command — delegates to RuboCop (replaces removed Prism formatter)
- Just task runner configuration (`Justfile`)
- CLI UX improvements: did-you-mean suggestions, build hints, default source detection

### Changed
- Language specification version updated from 0.1 to 0.3
- `.gitignore` hardened to exclude build artifacts (`*_init.c`, `*_debug.json`, example JARs)
- Removed scattered ad-hoc test scripts and build artifacts from project root
- README: replaced JVM maturity note with kumiki all_widgets_demo compilation milestone
- `konpeito deps` — now analyzes source file dependencies (JAR download moved to `--fetch` flag)
- README: benchmark section rewritten with ranges and honest notes on slower cases (pattern matching, NativeString)

### Removed
- LSP server (`konpeito lsp`) — Ruby's existing LSPs (ruby-lsp, Steep) cover this adequately

### Fixed
- JVM backend: phi type inference for instance variables with HM TypeVar pollution (ClassCastException fix)
- Thread callback protocol fallback and `visit_begin` guard for control flow
- Conformance test failures for thread capture, rescue, and JVM bare rescue
- CFG-based RPO block ordering in rescue try callbacks
- CRuby interop: gem require, kwargs+block, toplevel include ordering
- NativeString UTF-8 byte length (use `strlen` instead of `rb_str_length`)
- String operations optimization (`rb_obj_as_string`, `empty?` inline, `substr`/`split` direct call)
- GC-safe block capture for `&blk` methods (escape-cells strategy)
- Rescue callback escape-cells for method parameters and locals

## [0.2.4] - 2026-02-28

### Added
- Conformance test suite expanded to 87 spec files (10 new specs: array_functional, frozen_immutable, hash_transform, integer_step, kernel_format, object_protocol, proc_curry, range_advanced, regexp_matchdata, string_succ_ord)
- JVM runtime: updated KFiber, KMatchData, KRactor, KRactorPort classes for new conformance specs

### Fixed
- Native backend: `lambda?` and `arity` singleton methods now correctly attached to Proc objects via `rb_define_singleton_method`, achieving 87/87 native conformance
- Native backend: NativeClass method chaining — monomorphized call results (e.g. `dot_Vec2`) now correctly tagged as `:double`/`:i64` in `@variable_types`, preventing `rb_num2dbl` from being called on an already-unboxed double (was causing segfault in `normalized_dot` benchmark)
- Benchmark: `slice_bench.rb` RBS overload syntax updated from duplicate `def []:` to union `|` syntax (RBS 3.x compatibility)

### Changed
- `.gitignore`: `*.class` pattern extended to cover all subdirectories (was only matching root-level `.class` files)

## [0.2.3] - 2026-02-24

### Added
- Conformance test suite expansion: 77 spec files with 1,095+ assertions
- JVM runtime: Fiber support, ConditionVariable deadlock fix, Math module (PI, E, sqrt)
- `&blk` block argument support at call sites (e.g., `arr.map(&blk)`)

### Fixed
- Native backend: BUS error in `defined?(:method)` at top-level
- Native backend: inliner no longer inlines functions with `&blk` block params
- JVM backend: ConditionVariable deadlock — rewritten to release mutex during wait
- JVM backend: Math::PI, Math::E constants and Math.sqrt dispatch
- JVM backend: nested rescue, pattern matching, SizedQueue#empty?
- JVM backend: Integer()/Float() kernel methods, String#split limit, sleep, Symbol#frozen?
- JVM backend: hash iteration, KArray methods, splat args, user-defined ==, super(args)
- JVM backend: VerifyError for widened instance method parameters
- JVM backend: Fiber resume/yield, thread_mutex, runtime class identity

## [0.2.2] - 2026-02-21

### Added
- Conformance test suite expansion: 41 spec files with 1,009 assertions covering core Ruby language features
- JVM runtime: comprehensive method dispatch for String, Array, Hash, Integer, Float, Symbol, Range, Regexp, MatchData in RubyDispatch
- JVM runtime: KArray methods — flatten, compact, zip, take, drop, rotate, sample

### Fixed
- JVM backend: VerifyError for double parameter slot reuse — `_nil_assigned_vars` now infers types from HIR annotations for non-literal values instead of falsely tagging as mixed-type
- Native backend: monomorphizer now skips specialization for functions that compare parameters with nil (fixes `assert_nil` crash on out-of-bounds array access)
- Native backend: for-loop rewritten to index-based while loop, enabling break/next inside for bodies
- Native backend: enumerable, string_methods, symbol conformance fixes

## [0.2.1] - 2026-02-20

### Added
- Conformance test framework (`spec/conformance/`) for verifying LLVM and JVM backend output against CRuby reference

### Fixed
- Code generation: if/unless truthiness evaluation for non-boolean values (phi type mixing)
- Code generation: method argument count mismatch in certain call patterns
- Code generation: block yield / `block_given?` interaction with monomorphizer inconsistent call sites

## [0.2.0] - 2026-02-19

### Added
- Inliner: keyword argument mapping for correct inlining of functions with keyword params
- Inliner: ProcNew/BlockDef deep cloning with proper captured variable renaming
- Vendor setup script (`scripts/setup_vendor.sh`) to download yyjson source files

### Fixed
- HIR builder: save/restore `@current_block` in NativeHashEach to emit into correct basic block
- Inliner: ProcCall handler for proc_value and args renaming during inlining
- JSON stdlib: add tracked `yyjson_wrapper.c` providing non-inline wrappers for LLVM-generated code (fixes SEGV in `parse_as`/`parse_array_as` tests)
- CRuby backend: reference yyjson wrapper from tracked source location instead of vendor directory

## [0.1.3] - 2026-02-18

### Fixed
- JVM backend: resolve class method descriptor mismatch when called from instance methods (pre-register singleton method descriptors)
- Documentation: correct JWM and Skija GitHub URLs in README

### Added
- Documentation: Castella UI calculator demo with Style composition

## [0.1.2] - 2026-02-17

### Fixed
- Castella UI: include padding and respect FIXED sizes in Column/Row measure
- Castella UI: use lighter accent variant for normal button hover across all themes
- JVM backend: preserve subclass type through inherited self-returning method chains

### Changed
- Documentation: reorganize Castella UI section in README with DSL / Reactive State / Style Composition subheadings
- Documentation: add Style Composition example and screenshot to README
- Documentation: remove filler spacers from counter demos (EXPANDING default makes them unnecessary)
- Documentation: update counter screenshot

## [0.1.1] - 2026-02-16

### Fixed
- JVM backend: detect and resolve field type conflicts in `dedup_inherited_fields` to prevent runtime NPE when parent/child classes use same ivar with different types
- JVM backend: UI layout fixes for Castella dashboard (`.class` dispatch, `attr_accessor` field access, scrollbar thumb rendering, etc.)
- Remove duplicate `source_code_uri` from gemspec metadata
- Remove debug `puts` from data_table widget

### Added
- Castella UI: visual properties (`bg_color`, `border_radius`, `border_color`, `border_width`) directly on Column/Row layouts, eliminating Container wrapper boilerplate

### Changed
- Documentation: note that JVM backend might be more mature than LLVM backend

## [0.1.0] - 2026-02-13

### Added

#### Compiler Core
- Prism parser integration for Ruby 4.0 syntax
- Hindley-Milner type inference (Algorithm W) with RBS integration
- High-level IR (HIR) with SSA form
- Typed AST generation

#### LLVM Backend (CRuby Extension)
- Native code generation via LLVM 20
- CRuby extension output (.so/.bundle)
- Unboxed arithmetic for Integer/Float (5-5000x faster than YJIT)
- Monomorphization and function inlining
- Loop-invariant code motion (LICM)
- LLVM O2 optimization pass integration

#### JVM Backend
- Standalone .jar generation via ASM bytecode
- Java 21 Virtual Threads support
- Java interop (RBS-free, classpath introspection)
- Block-to-SAM conversion
- Pattern matching (Array/Hash/Capture/Pin/Rest)
- Module/Mixin support (include/extend/prepend)

#### Native Data Structures
- `NativeArray[T]` - contiguous unboxed arrays (up to 31x faster)
- `NativeClass` - fixed-layout C structs with GC integration
- `NativeHash[K,V]` - generic hash map with linear probing
- `StaticArray[T,N]` - stack-allocated fixed-size arrays
- `Slice[T]` - bounds-checked pointer views
- `ByteBuffer` / `StringBuffer` / `ByteSlice`
- `NativeString` - UTF-8 byte/char operations
- `@struct` - value type structs (register passing)

#### Standard Library
- `KonpeitoJSON` - JSON parse/generate (yyjson)
- `KonpeitoHTTP` - HTTP client (libcurl)
- `KonpeitoCrypto` - cryptographic primitives (OpenSSL)
- `KonpeitoCompression` - gzip/deflate/zlib compression

#### Ruby Language Features
- Classes, modules, inheritance, mixins
- Blocks, yield, Proc/Lambda
- Pattern matching (case/in with literals, arrays, hashes, guards, captures, pins)
- Exception handling (begin/rescue/else/ensure)
- Fiber, Thread, Mutex, ConditionVariable, SizedQueue
- String interpolation, regular expressions, ranges
- Keyword arguments, rest arguments, splat expansion
- Compound assignment (`+=`, `||=`, `&&=`)
- Safe navigation (`&.`), `defined?`, `alias`
- Open classes, `class << self`, endless methods
- Numbered block parameters (`_1`, `_2`), `it` parameter

#### Developer Tools
- LSP server (diagnostics, hover, completion, go-to-definition, references, rename)
- DWARF debug info (`-g` flag, lldb/gdb support)
- Profiling instrumentation (`--profile`)
- Incremental compilation (`--incremental`)
- Rust/Elm-style diagnostic error messages

#### C Interop
- `%a{cfunc}` / `%a{ffi}` - direct C function calls
- `%a{extern}` - external C struct wrappers
- `%a{simd}` - SIMD vectorization

[0.4.1]: https://github.com/i2y/konpeito/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/i2y/konpeito/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/i2y/konpeito/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/i2y/konpeito/compare/v0.2.4...v0.3.0
[0.2.4]: https://github.com/i2y/konpeito/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/i2y/konpeito/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/i2y/konpeito/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/i2y/konpeito/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/i2y/konpeito/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/i2y/konpeito/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/i2y/konpeito/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/i2y/konpeito/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/i2y/konpeito/releases/tag/v0.1.0
