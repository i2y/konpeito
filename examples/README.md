# Konpeito Examples

## Getting Started

| File | Description |
|------|-------------|
| `hello.rb` | Minimal "Hello, World!" example |
| `calculator.rb` | Basic arithmetic with type inference |
| `typed_example.rb` | Explicit RBS type annotations for unboxed optimization |
| `counter.rb` | Stateful counter with instance variables |

## Language Features

| File | Description |
|------|-------------|
| `block_example.rb` | Blocks, yield, and iterators |
| `block_given_test.rb` | `block_given?` conditional check |
| `block_receiver.rb` | Block as method argument |
| `lambda_test.rb` / `.rbs` | Lambda literals and `Proc#call` |
| `exception_test.rb` | begin/rescue/ensure exception handling |
| `raise_test.rb` | Custom exception classes and raise |
| `infer_from_body.rb` | HM type inference without RBS |

## C Interop

| File | Description |
|------|-------------|
| `cfunc_demo.rb` / `.rbs` | `%a{cfunc}` direct C function calls (libm) |
| `cfunc_demo2.rb` / `.rbs` | Additional cfunc patterns |
| `ffi_demo.rb` / `.rbs` | `%a{ffi}` external library linking |

## JVM Backend

| File | Description |
|------|-------------|
| `jvm_hello.rb` / `.rbs` | JVM "Hello, World!" (compiles to .jar) |
| `jvm_ractor.rb` | Ractor concurrency on JVM |
| `jvm_ractor_extended.rb` | Advanced Ractor patterns (Port, select) |

## Developer Tools

| File | Description |
|------|-------------|
| `debug_sample.rb` / `.rbs` | DWARF debug info (`konpeito build -g`) |
| `type_error_sample.rb` / `.rbs` | Diagnostic error messages demo |

## Subdirectories

| Directory | Description |
|-----------|-------------|
| `http_server/` | Fiber-based HTTP server (has its own README) |
| `json_example/` | JSON parsing with KonpeitoJSON (yyjson) |
| `castella_ui/` | Reactive GUI framework (see [docs/castella-ui.md](../docs/castella-ui.md)) |
| `jwm_canvas/` | Low-level JWM + Skia canvas demo |

## Running Examples

```bash
# LLVM backend (CRuby extension)
konpeito build examples/hello.rb
cd examples && ruby -r ./hello -e ""

# JVM backend (standalone .jar)
konpeito build --target jvm examples/jvm_hello.rb
java -jar examples/jvm_hello.jar

# With explicit RBS types
konpeito build examples/typed_example.rb
```
