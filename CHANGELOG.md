# Changelog

All notable changes to Konpeito will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/i2y/konpeito/releases/tag/v0.1.0
