# Changelog

All notable changes to Konpeito will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.4]: https://github.com/i2y/konpeito/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/i2y/konpeito/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/i2y/konpeito/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/i2y/konpeito/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/i2y/konpeito/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/i2y/konpeito/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/i2y/konpeito/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/i2y/konpeito/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/i2y/konpeito/releases/tag/v0.1.0
