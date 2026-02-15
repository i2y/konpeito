# Ruby Native Compiler Architecture Guide

Ruby Native Compiler is an AOT (Ahead-of-Time) compiler that compiles Ruby code into native code through LLVM.

---

## Table of Contents

1. [Overview](#overview)
2. [Compilation Pipeline](#compilation-pipeline)
3. [Type System](#type-system)
4. [HIR (Intermediate Representation)](#hir-intermediate-representation)
5. [LLVM Code Generation](#llvm-code-generation)
6. [Optimization](#optimization)
7. [@native Annotation](#native-annotation)
8. [require Support](#require-support)
9. [Usage Examples](#usage-examples)
10. [Limitations and Future Outlook](#limitations-and-future-outlook)
11. [Appendix](#appendix)
    - [A. What is HIR](#a-hir-high-level-intermediate-representation)
    - [B. What is SSA](#b-ssa-static-single-assignment)
    - [C. What is SIMD Optimization](#c-simd-optimization)
    - [D. What is Boehm GC](#d-boehm-gc)
    - [E. Detailed Roadmap](#e-detailed-roadmap)

---

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Ruby Native Compiler                         │
│                                                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │  Prism   │→│ HM Type  │→│ HIR Gen  │→│ Optimize │→│  LLVM  │ │
│  │ Parser   │  │ Infer    │  │          │  │          │  │ IR Gen │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
│       ↑              ↑                                        │      │
│       │              │                                        ↓      │
│  ┌────┴────┐    ┌────┴────┐                            ┌──────────┐ │
│  │ .rb     │    │ .rbs    │                            │ .bundle  │ │
│  │ Source  │    │ Type    │                            │ CRuby    │ │
│  │ Code   │    │ Defs    │                            │Extension │ │
│  └─────────┘    └─────────┘                            └──────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Features

| Feature | Description |
|---------|-------------|
| **AOT Compilation** | Generates native code before execution (not JIT) |
| **Type Inference** | Infers types using Hindley-Milner type inference even without RBS |
| **RBS Integration** | Obtains precise type information by cooperating with RBS type definitions |
| **CRuby Compatible** | Generated output works as a CRuby extension |
| **Optimization** | Acceleration through monomorphization |
| **@native Types** | Unboxed fast numeric types and structs |

### Project Positioning

Ruby Native Compiler is a tool for **"writing CRuby extensions in Ruby"**.

```
┌─────────────────────────────────────────────────────────────────────┐
│               Positioning of Ruby Native Compiler                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐  │
│  │     CRuby       │   │    Crystal      │   │  Ruby Native    │  │
│  │   (Reference)   │   │                 │   │   Compiler      │  │
│  ├─────────────────┤   ├─────────────────┤   ├─────────────────┤  │
│  │ Full Ruby       │   │ Ruby-like       │   │ Write CRuby     │  │
│  │ implementation  │   │ separate lang   │   │ extensions      │  │
│  │ Interpreted     │   │ Own runtime     │   │ in Ruby         │  │
│  │                 │   │ Own GC          │   │ CRuby integrated│  │
│  └─────────────────┘   └─────────────────┘   └─────────────────┘  │
│          │                     │                     │            │
│          ↓                     ↓                     ↓            │
│   All Ruby features      Ruby gem incompatible  Full CRuby       │
│   Dynamic, flexible      Fast, statically typed ecosystem        │
│                                                    integration   │
└─────────────────────────────────────────────────────────────────────┘
```

**What Ruby Native Compiler aims for:**

```
Traditional CRuby Extension Development
─────────────────────────────────────────────────────────────────

  Write performance-critical parts in C:

  my_gem/
  ├── lib/
  │   └── my_gem.rb          ← Ruby (high-level, easy to write)
  └── ext/
      └── my_gem/
          ├── extconf.rb
          └── my_gem.c       ← C (fast but hard to write)
                                 - Manual memory management
                                 - Requires rb_* API knowledge
                                 - GC mark handling required
                                 - Difficult to debug


Development with Ruby Native Compiler
─────────────────────────────────────────────────────────────────

  Write performance-critical parts in Ruby too:

  my_gem/
  ├── lib/
  │   └── my_gem.rb          ← Ruby (regular code)
  └── native/
      ├── fast_calc.rb       ← Ruby (parts to optimize)
      └── fast_calc.rbs      ← RBS (type definitions)
              │
              ↓ Compile
      fast_calc.bundle       ← Output as CRuby extension
                                - Written in Ruby syntax
                                - C-equivalent performance
                                - Coexists with existing gems
```

**Comparison with other approaches:**

| Feature | CRuby | Crystal | mruby | Ruby Native |
|---------|-------|---------|-------|-------------|
| Ruby syntax | ✓ | Nearly identical | Subset | Subset |
| CRuby gem usage | ✓ | ✗ | ✗ | ✓ |
| CRuby GC integration | - | ✗ | ✗ | ✓ |
| C extension calling | ✓ | FFI | ✗ | ✓ (rb_* API) |
| Native performance | ✗ | ✓ | △ | ✓ |
| Dynamic features (eval etc.) | ✓ | ✗ | △ | ✗ |

**This project does NOT aim for:**

- A complete reimplementation of Ruby (like JRuby, TruffleRuby)
- A Ruby-like separate language (like Crystal)
- Compilation of all Ruby code

**This project aims for:**

- An environment where CRuby extensions can be easily written in Ruby
- Full integration with the CRuby ecosystem
- Acceleration of numerical computation and high-frequency processing

---

## Compilation Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Compilation Pipeline                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Parsing                 Type Checking             IR Generation            │
│  ┌───────────────┐      ┌───────────────┐      ┌───────────────┐           │
│  │ Source Loading │      │ RBS Loading   │      │ HIR Generation│           │
│  │      ↓        │      │      ↓        │      │      ↓        │           │
│  │ Dependency     │      │ HM Type       │      │ Optimization  │           │
│  │ Resolution    │  →   │ Inference     │  →   │ Passes        │           │
│  │ (require)     │      │      ↓        │      │      ↓        │           │
│  │      ↓        │      │ Typed AST     │      │ LLVM IR       │           │
│  │ Prism Parse   │      │              │      │              │           │
│  │      ↓        │      └───────────────┘      └───────────────┘           │
│  │ AST Generation│                                    │                    │
│  └───────────────┘                                    ↓                    │
│                                                                             │
│  Code Generation                                                            │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │  LLVM Optimize  →  Object Gen  →  Link  →  .bundle/.so        │       │
│  └─────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Details of Each Stage

#### Parsing

1. **Dependency Resolution**: Detects `require` / `require_relative` and recursively resolves dependent files
2. **Parse**: Generates AST using the Prism parser (Ruby 4.0 standard)
3. **AST Merge**: Merges ASTs from multiple files into a single compilation unit

#### Type Checking

1. **RBS Loading**: Automatically detects and loads corresponding `.rbs` files
2. **HM Type Inference**: Type inference using Algorithm W (works even without RBS)
3. **Type Concretization**: Concretizes polymorphic types based on usage

#### IR Generation

1. **HIR Generation**: Generates High-level IR from the typed AST
2. **Optimization**: Optimization passes such as monomorphization and inlining
3. **LLVM IR**: Generates LLVM IR from HIR

#### Code Generation

1. **LLVM Optimization**: LLVM optimization passes such as mem2reg
2. **Object Generation**: Generates `.o` files
3. **Link**: Links as a CRuby extension

---

## Type System

```
┌─────────────────────────────────────────────────────────────────┐
│                         Type System                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Type Information Sources           Type Categories             │
│  ┌─────────────┐                 ┌─────────────────────┐       │
│  │ RBS Type    │─────┐          │ Basic Types          │       │
│  │ Definitions │     │          │ Integer, Float,      │       │
│  │ (explicit)  │     │          │ String, Symbol...    │       │
│  └─────────────┘     │          └─────────────────────┘       │
│                      ↓                                         │
│  ┌─────────────┐   ┌──────┐     ┌─────────────────────┐       │
│  │ HM Type     │→ │Unify  │ →  │ Class Types          │       │
│  │ Inference   │   │      │     │ ClassInstance        │       │
│  │ (implicit)  │   └──────┘     └─────────────────────┘       │
│        ↓              ↓         ┌─────────────────────┐       │
│  ┌─────────────┐   ┌──────┐     │ Polymorphic Types    │       │
│  │ Type Vars   │→ │ Type  │ →  │ Array[T], Hash[K,V]  │       │
│  │ τ1, τ2...   │   │Subst │     └─────────────────────┘       │
│  └─────────────┘   └──────┘                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### HM Type Inference (Hindley-Milner)

Types can be inferred from code even without RBS.

```ruby
# Type inference works without RBS
def double(x)
  x * 2
end
# => Inferred: (Integer) -> Integer
#    (Since 2 is Integer, x is also inferred as Integer)

def greet(name)
  "Hello, " + name
end
# => Inferred: (String) -> String
#    (Inferred from String#+ argument type)
```

### RBS Integration

Type inference leveraging RBS polymorphic types:

```ruby
# Code
arr = [1, 2, 3]
doubled = arr.map { |x| x * 2 }

# RBS (Array#map definition)
# def map: [U] { (Elem) -> U } -> Array[U]

# Inference Result
# arr     : Array[Integer]
# doubled : Array[Integer]
```

```
  Type Inference Flow
  ─────────────────────────────────────────────────────────────────

  Ruby Code               HM Inferrer              RBS Loader
      │                      │                        │
      │  arr = [1, 2, 3]     │                        │
      │─────────────────────→│                        │
      │                      │ arr: Array[τ1]        │
      │                      │ τ1 = Integer          │
      │                      │                        │
      │  arr.map { ... }     │                        │
      │─────────────────────→│                        │
      │                      │  Type of Array#map?    │
      │                      │───────────────────────→│
      │                      │                        │
      │                      │←───────────────────────│
      │                      │  [U] { (Elem)->U }    │
      │                      │      -> Array[U]      │
      │                      │                        │
      │                      │ Elem=Integer, U=Integer│
      │                      │                        │
      │←─────────────────────│                        │
      │  Result: Array[Integer]                       │

```

### Flow Type Analysis

Type narrowing in conditional branches, similar to TypeScript/Kotlin smart casts:

```ruby
# Type narrowing via nil check
def process(value)  # value: String | nil
  if value != nil
    # value is treated as String (nil is excluded)
    value.length
  else
    0
  end
end

# Compound narrowing with && operator
def both_present(a, b)  # a, b: String | nil
  if a && b
    # Both treated as non-nil
    a.length + b.length
  end
end

# Natural nil check in while loop
def parse(line)
  i = 0
  while i < line.length
    c = line[i]  # c: String | nil
    if c != nil && c == " "
      # c is treated as String
      do_something
    end
    # No else branch needed (statement position)
    i = i + 1
  end
end
```

**Supported Patterns:**

| Pattern | then branch type | else branch type |
|---------|------------------|------------------|
| `if x` | non-nil | unchanged |
| `if x == nil` | nil | non-nil |
| `if x != nil` | non-nil | unchanged |
| `if x.nil?` | nil | non-nil |
| `if a && b` | both non-nil | unchanged |
| `if nil == x` | nil | non-nil |

**Statement Position:**

In positions where the result is not used (statement position), type consistency between if/unless branches is not required:

```ruby
while condition
  if x != nil
    do_something  # OK without else branch
  end
end
```

---

## HIR (Intermediate Representation)

HIR (High-level Intermediate Representation) is an intermediate representation between the typed AST and LLVM IR.

```
┌─────────────────────────────────────────────────────────────────┐
│                         HIR Structure                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Program                                                        │
│    │                                                            │
│    ├── ClassDef (name, methods)                                 │
│    │     │                                                      │
│    │     └── Function (params, body, type)                      │
│    │           │                                                │
│    │           └── BasicBlock (label)                           │
│    │                 │                                          │
│    │                 └── Instruction (various instructions)     │
│    │                                                            │
│    └── Function (top-level functions)                           │
│          │                                                      │
│          └── BasicBlock                                         │
│                │                                                │
│                └── Instruction                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### HIR Instruction Types

| Category | Instruction | Description |
|----------|-------------|-------------|
| **Literals** | `IntegerLit`, `FloatLit`, `StringLit` | Constant values |
| **Variables** | `LoadLocal`, `StoreLocal` | Local variables |
| | `LoadInstanceVar`, `StoreInstanceVar` | Instance variables |
| **Calls** | `Call` | Method calls |
| | `Yield` | Block yield |
| **Control** | `Branch`, `CondBranch`, `Return` | Control flow |
| **Type Conversion** | `ConstantLookup` | Constant (class) reference |

### HIR Example

```ruby
# Ruby code
def add(a, b)
  a + b
end
```

```
# HIR representation
Function add(a: Integer, b: Integer) -> Integer
  Block entry:
    %1 = LoadLocal a
    %2 = LoadLocal b
    %3 = Call receiver=%1 method="+" args=[%2]
    Return %3
```

---

## LLVM Code Generation

```
┌─────────────────────────────────────────────────────────────────┐
│                      LLVM Code Generation                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│       HIR                    LLVM IR              CRuby API     │
│  ┌───────────┐          ┌───────────┐        ┌──────────────┐  │
│  │ Function  │    →     │ Function  │   →    │ rb_funcallv  │  │
│  ├───────────┤          ├───────────┤        │ (method call)│  │
│  │BasicBlock │    →     │BasicBlock │        ├──────────────┤  │
│  ├───────────┤          ├───────────┤        │ rb_int2num   │  │
│  │Instruction│    →     │ LLVM Inst │   →    │(Integer conv)│  │
│  └───────────┘          └───────────┘        ├──────────────┤  │
│                                              │ rb_num2long  │  │
│                                              │ (unboxing)   │  │
│                                              └──────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Two-Pass Generation

LLVM code generation is performed in two passes:

```
  Two-Pass Generation Flow
  ─────────────────────────────────────────────────────────────────

  Pass 1: Function Declarations        Pass 2: Body Generation
  ────────────────────────             ────────────────────────

  for each function:                 for each function:
    │                                  │
    ├─ Declare function signature      ├─ Get reference from @functions
    │  (name, arg types, return type)  │
    │                                  ├─ Generate instructions sequentially
    └─ Register in @functions          │
                                       └─ Apply optimization passes


  This enables forward references to monomorphized functions:

    When compute() calls add_Integer_Integer(),
    add_Integer_Integer is already declared in Pass 1 and can be referenced
```

### Method Call Path

```
                    Method Call
                          │
                          ↓
              ┌───────────────────────┐
              │ Monomorphized target? │
              └───────────────────────┘
                    │           │
                   Yes          No
                    │           │
                    ↓           ↓
        ┌─────────────────┐   ┌───────────────────────┐
        │ Direct call     │   │ Same-class self call?  │
        │ (optimized) ◎   │   └───────────────────────┘
        └─────────────────┘         │           │
                                   Yes          No
                                    │           │
                                    ↓           ↓
                      ┌─────────────────┐   ┌───────────────────┐
                      │ Direct call     │   │ Built-in method?   │
                      │ (local func) ◎  │   └───────────────────┘
                      └─────────────────┘         │           │
                                                 Yes          No
                                                  │           │
                                                  ↓           ↓
                                    ┌─────────────────┐   ┌─────────────┐
                                    │ Built-in        │   │ rb_funcallv │
                                    │ optimized       │   │ (dynamic) △ │
                                    │ (devirtualize)○ │   └─────────────┘
                                    └─────────────────┘

        ◎ = Fast  ○ = Medium  △ = Slow (fallback)
```

---

## Optimization

### Monomorphization

Specializes polymorphic functions with concrete types.

```
                     Before Optimization
  ─────────────────────────────────────────────────

         ┌──────────────────────────────┐
         │ add(a, b)                    │
         │ Polymorphic: (τ1, τ2) -> τ3  │
         └──────────────────────────────┘
                ↑             ↑
                │             │
         add(1, 2)      add(1.0, 2.0)


                     After Optimization
  ─────────────────────────────────────────────────

    ┌─────────────────────────┐   ┌─────────────────────────┐
    │ add_Integer_Integer     │   │ add_Float_Float         │
    │ (Integer, Integer)      │   │ (Float, Float)          │
    │     -> Integer          │   │     -> Float            │
    └─────────────────────────┘   └─────────────────────────┘
                ↑                             ↑
                │                             │
         add(1, 2)                    add(1.0, 2.0)
```

### Optimization Effects

| Optimization | Effect |
|-------------|--------|
| **Monomorphization** | Generates efficient code specialized for types |
| **Direct Calls** | Reduces `rb_funcallv` overhead |
| **Unboxed Arithmetic** | Operates Integer/Float as C `i64`/`double` |

#### Numeric Widening

Integer→Float implicit conversion is supported (equivalent to Java/Kotlin widening primitive conversion):

```ruby
def scale(value, factor)  # factor: Float (RBS annotation)
  value * factor
end

scale(10, 2.5)   # Integer 10 is implicitly widened to Float
```

- `unify(Integer, Float)` → widens to Float (not LUB to Numeric)
- When a TypeVar is already bound to Integer, unification with Float widens to Float
- Reverse direction (Float→Integer) is not implicit (explicit `.to_i` required)

---

## @native Annotation

The `@native` annotation is a mechanism for marking classes and modules as "native types" in RBS files. Native types are laid out directly in memory as C structs, rather than boxed Ruby values.

### NativeClass Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    @native Annotation                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Regular Ruby Object              NativeClass                   │
│  ───────────────────              ─────────────                 │
│                                                                 │
│  ┌─────────────────┐             ┌─────────────────┐           │
│  │ Ruby VALUE      │             │ C struct        │           │
│  │ (boxed)         │             │ (unboxed)       │           │
│  ├─────────────────┤             ├─────────────────┤           │
│  │ Object ID       │             │ @x: double      │  ← 8byte  │
│  │ Class pointer   │             │ @y: double      │  ← 8byte  │
│  │ Instance vars   │             └─────────────────┘           │
│  │   @x → Float    │                    │                      │
│  │   @y → Float    │             Total 16 bytes (fixed)        │
│  └─────────────────┘                                            │
│         │                                                       │
│  GC managed, dynamic dispatch     Direct memory access, fast    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### NativeClass Definition (RBS)

```rbs
# @native
class Point
  @x: Float
  @y: Float

  def self.new: () -> Point
  def x: () -> Float
  def x=: (Float value) -> Float
  def y: () -> Float
  def y=: (Float value) -> Float
  def distance: (Point other) -> Float
end
```

Corresponding Ruby code:

```ruby
# point.rb
class Point
  def initialize
    @x = 0.0
    @y = 0.0
  end

  attr_accessor :x, :y

  def distance(other)
    dx = @x - other.x
    dy = @y - other.y
    Math.sqrt(dx * dx + dy * dy)
  end
end
```

### Supported Field Types

| RBS Type | LLVM Type | Description |
|----------|-----------|-------------|
| `Float` | `double` | 64-bit floating point (unboxed) |
| `Integer` | `i64` | 64-bit integer (unboxed) |
| `Bool` | `i1` | Boolean |
| `OtherClass` | `struct*` | Reference to another NativeClass |

### NativeArray

`NativeArray` is an array that places elements in contiguous memory.

```
┌─────────────────────────────────────────────────────────────────┐
│                        NativeArray                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Regular Ruby Array              NativeArray[Float]              │
│  ──────────────────             ─────────────────               │
│                                                                 │
│  ┌──────────────┐             ┌──────────────────────────────┐ │
│  │ VALUE array  │             │ double* (contiguous memory)   │ │
│  ├──────────────┤             ├──────┬──────┬──────┬──────┤ │
│  │ [0] → VALUE  │──→ Float    │ [0]  │ [1]  │ [2]  │ [3]  │ │
│  │ [1] → VALUE  │──→ Float    │8byte │8byte │8byte │8byte │ │
│  │ [2] → VALUE  │──→ Float    └──────┴──────┴──────┴──────┘ │
│  │ [3] → VALUE  │──→ Float                                    │
│  └──────────────┘                                              │
│                                                                 │
│  Each element is boxed          Contiguous memory, cache-       │
│  Many indirect references       efficient, SIMD optimizable    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

Supported element types:

| Element Type | Description |
|-------------|-------------|
| `Int64` | 64-bit integer array |
| `Float64` | 64-bit floating-point array |
| `NativeClass` | Array of NativeClass objects |

### NativeHash[K, V]

`NativeHash` is a hash map using open addressing with linear probing.
**Supports RBS generics syntax** and automatically infers type parameters from usage sites.

```rbs
# RBS type definition (generics syntax)
class NativeHash[K, V]
  def self.new: () -> NativeHash[K, V]
  def []: (K key) -> V
  def []=: (K key, V value) -> V
  def size: () -> Integer
  def has_key?: (K key) -> bool
  def delete: (K key) -> V
end
```

```ruby
# Usage - types are automatically inferred from usage sites
def hash_example
  h = NativeHash.new     # Inferred as NativeHash[Integer, Integer]
  h[1] = 100             # K=Integer, V=Integer determined
  h[2] = 200
  h[1] + h[2]            # 300 (unboxed i64 arithmetic)
end
```

**Features:**
- Collision resolution via linear probing
- Auto-resize (capacity doubles when load factor exceeds 0.75)
- Approximately 4x faster than Ruby Hash

**Supported types:**
| Key Types | Value Types |
|-----------|-------------|
| `String`, `Symbol`, `Integer` | `Integer`, `Float`, `Bool`, `String`, `Array`, `Hash`, `NativeClass` |

### Operator Overloading

Operator methods (`+`, `-`, `*`, etc.) can be defined on user-defined classes. Operators are uniformly treated as method calls, just like in Ruby.

```rbs
class Vector2
  @x: Float
  @y: Float

  def self.new: () -> Vector2
  def x: () -> Float
  def x=: (Float value) -> Float
  def y: () -> Float
  def y=: (Float value) -> Float
  def +: (Vector2 other) -> Vector2
  def *: (Float scalar) -> Vector2
end
```

```ruby
class Vector2
  def +(other)
    result = Vector2.new
    result.x = @x + other.x
    result.y = @y + other.y
    result
  end
end

v3 = v1 + v2        # NativeMethodCall → rb_funcallv("Vector2", "+")
v4 = v1 + v2 + v3   # Chaining is also possible
```

**LLVM/CRuby implementation notes:**

- Operator methods are registered with `rb_define_method(klass, "+", wrapper_func, arity)`
- Operator characters cannot be used in C function names, so they are converted via `OPERATOR_NAME_MAP` (`+` → `op_plus`, `-` → `op_minus`, etc.)
- Field access within method bodies (`@x + other.x`) is optimized with unboxed arithmetic
- The operator call itself goes through `rb_funcallv` (direct C function call optimization like built-in types is not yet implemented)

### vtable Support (Polymorphism)

Use `@native vtable` when inheritance and dynamic dispatch are needed:

```rbs
# @native vtable
class Shape
  @area: Float

  def self.new: () -> Shape
  def area: () -> Float
end

# @native vtable
class Circle < Shape
  @radius: Float

  def self.new: (Float radius) -> Circle
  def area: () -> Float
end

# @native vtable
class Rectangle < Shape
  @width: Float
  @height: Float

  def self.new: (Float w, Float h) -> Rectangle
  def area: () -> Float
end
```

```
  Dynamic dispatch via vtable
  ─────────────────────────────────────────────────────────────

  Shape* shapes[3] = { circle, rect1, rect2 };

  for (shape in shapes) {
      shape.area()   ───→  vtable[area_slot]  ───→ Calls correct method
  }                              │
                                 ↓
                    ┌─────────────────────────┐
                    │ Circle:  π * r * r      │
                    │ Rectangle: w * h        │
                    └─────────────────────────┘
```

### Performance Comparison

```
┌────────────────────────────────────────────────────────────────┐
│                   Performance Characteristics                    │
├──────────────────────┬──────────────────┬──────────────────────┤
│        Operation     │   Regular Ruby   │    @native           │
├──────────────────────┼──────────────────┼──────────────────────┤
│ Field access         │ Hash lookup      │ Fixed offset         │
│ Method call          │ rb_funcallv      │ Direct function call │
│ Numeric arithmetic   │ Boxed            │ Unboxed              │
│ Array access         │ Indirect ref     │ Contiguous memory    │
│ Memory usage         │ Per object       │ Struct size only     │
└──────────────────────┴──────────────────┴──────────────────────┘

 * @native is especially effective for scenarios that handle
   large numbers of objects, such as numerical computation
   and simulation
```

### Limitations

| Limitation | Description |
|-----------|-------------|
| **Field types** | Numeric types and other NativeClasses only (no String, etc.) |
| **No dynamic addition** | Cannot add fields at runtime |
| **Inheritance constraint** | NativeClass can only inherit from NativeClass |
| **No GC support** | GC marking of reference-type fields is manual |

---

## require Support

```
┌─────────────────────────────────────────────────────────────────┐
│                      require Resolution                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    Input Files                       DependencyResolver          │
│   ┌────────────┐                 ┌─────────────────┐           │
│   │ main.rb    │────────────────→│ Detect require  │           │
│   │ require    │                 │      ↓          │           │
│   │ 'helper'   │                 │ Resolve path    │           │
│   └────────────┘                 │      ↓          │           │
│         │                        │ Merge ASTs      │           │
│         ↓                        │      ↓          │           │
│   ┌────────────┐                 │ Auto-detect RBS │           │
│   │ helper.rb  │────────────────→│                 │           │
│   │ class      │                 └────────┬────────┘           │
│   │ Helper     │                          │                    │
│   └────────────┘                          ↓                    │
│                                  ┌─────────────────┐           │
│   ┌────────────┐                 │ Single compile  │           │
│   │ main.rbs   │←── Auto-detect ─│ unit            │           │
│   │ helper.rbs │                 └─────────────────┘           │
│   └────────────┘                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Static require Resolution

Dependencies are resolved at compile time and all files are merged into a single compilation unit.

```ruby
# main.rb
require_relative "helper"

class Main
  def run
    h = Helper.new
    h.add(1, 2)
  end
end

# helper.rb
class Helper
  def add(a, b)
    a + b
  end
end
```

Both files are merged at compile time, and cross-class calls work correctly.

### Circular Dependency Detection

```
    a.rb                      b.rb
  ┌─────────────┐           ┌─────────────┐
  │ require     │──────────→│ require     │
  │ 'b'         │           │ 'a'         │
  └─────────────┘           └─────────────┘
                                  │
                                  ↓
                    ┌─────────────────────────────┐
                    │ Error:                      │
                    │ Circular dependency detected│
                    │ a.rb -> b.rb -> a.rb        │
                    └─────────────────────────────┘
```

---

## Usage Examples

### Basic Usage

```bash
# Compile
bundle exec konpeito source.rb -o output.bundle

# Specify RBS
bundle exec konpeito source.rb -o output.bundle --rbs types.rbs

# Additional require paths
bundle exec konpeito source.rb -o output.bundle -I lib

# Verbose output
bundle exec konpeito source.rb -o output.bundle -v

# Type check only
bundle exec konpeito --check source.rb
```

### Execution

```bash
# Load extension with CRuby
ruby -r ./output.bundle -e "puts MyClass.new.run"
```

### Sample Code

```ruby
# calculator.rb
class Calculator
  def add(a, b)
    a + b
  end

  def multiply(a, b)
    a * b
  end

  def compute(x, y)
    add(x, y) * multiply(x, y)
  end
end
```

```rbs
# calculator.rbs
class Calculator
  def add: (Integer, Integer) -> Integer
  def multiply: (Integer, Integer) -> Integer
  def compute: (Integer, Integer) -> Integer
end
```

```bash
# Compile & Execute
bundle exec konpeito calculator.rb -o calculator.bundle --rbs calculator.rbs
ruby -r ./calculator.bundle -e "puts Calculator.new.compute(3, 4)"
# => 84  (= (3+4) * (3*4) = 7 * 12)
```

---

## Limitations and Future Outlook

### Design Limitations (Not Planned for Support)

The following are dynamic features of Ruby that are fundamentally incompatible with AOT compilation, and support is not planned:

| Feature | Reason |
|---------|--------|
| `eval`, `instance_eval` | Generates and evaluates code at runtime |
| `define_method` | Defines methods at runtime |
| `method_missing` | Call target cannot be determined by static analysis |
| `send(dynamic_name)` | Method call with dynamic name |
| Open classes | Redefines classes at runtime |
| `ObjectSpace` | Requires tracking of all objects |

**If you need these features, use regular CRuby.**
Extensions compiled with Ruby Native can coexist with CRuby code.

### Implemented Features

| Feature | Status |
|---------|--------|
| **Standard library require** | Done |
| **rescue clause** | Done |
| **NativeClass VALUE fields** | Done |
| **@cfunc direct calls** | Done |
| **Fiber/Thread/Mutex** | Done |
| **Pattern matching (case/in)** | Partial |
| **Enumerable inline optimization** | Done |

### Technical Limitations in Code Generation

#### Mixing unboxed/boxed types in if/else

When an if/else expression returns different types (such as unboxed Integer and boxed String), type inconsistency occurs in the LLVM phi node.

```ruby
# ❌ Problematic code
val = if condition
  42        # unboxed i64
else
  "hello"  # boxed VALUE (String)
end
# → i64 and VALUE mix in the phi node, causing a runtime error
```

**Workaround**: Return the same type or explicitly unify the types.

#### case/when and case/in Optimization

**Implemented: Phi Node Optimization**

When all when/in clauses return the same unboxed type (Integer, Float), the phi node is unboxed. This avoids unnecessary boxing/unboxing.

```ruby
# ✅ Optimized: phi node is unboxed i64
case x
when 0 then 1      # Used directly as i64 constant
when 1 then 2
else 3
end
# Result is maintained as unboxed i64, subsequent operations are also unboxed

# ✅ Optimized: phi node is unboxed double
case n
when 1 then 1.5
when 2 then 2.5
else 3.5
end
```

**Remaining limitations**:
- **Condition evaluation**: The `===` operator still goes through `rb_funcallv` (future optimization candidate)

**Note**: Boxing is required when different types are returned:
```ruby
# ⚠️ Boxing occurs due to mixed types
case x
when 0 then 1      # Integer
when 1 then "two"  # String → both boxed to VALUE
else nil
end
```

---

### Development Roadmap

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                         Development Roadmap
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Foundation [Done]
─────────────────────────────────────────────────────────────────

  ✓ Prism parser integration
  ✓ HM type inference + RBS integration
  ✓ HIR (intermediate representation) generation
  ✓ LLVM IR generation → CRuby extension output
  ✓ Blocks, iterators, closures
  ✓ Exception handling (begin/ensure, raise)
  ✓ require/require_relative (static resolution)
  ✓ @native annotation (NativeClass, NativeArray)


Optimization and Stabilization [Done]
─────────────────────────────────────────────────────────────────

  ✓ Monomorphization
  ✓ Direct function calls (self-call optimization)
  ✓ Inlining
  ✓ Improved type precision for unboxed arithmetic (Integer → Integer)
  ✓ Full rescue clause support
  ✓ case/when statement support


Language Features and Ecosystem Completion [Done]
─────────────────────────────────────────────────────────────────

  ✓ CRuby integration enhancements (GC, stdlib require, Proc/Lambda)
  ✓ C extension interop (@cfunc, @ffi, SIMD)
  ✓ Developer experience improvements (debug info, LSP, profiling)
  ✓ Pattern matching (case/in)
  ✓ Native stdlib (ByteBuffer, StaticArray, Slice, NativeHash)
  ✓ Concurrency (Fiber, Thread, Mutex, ConditionVariable, SizedQueue)
  ✓ Ruby core language features (&&, ||, +=, break/next, Range, until, super)


Ecosystem Enhancement, Stabilization, Performance [Done]
─────────────────────────────────────────────────────────────────

  ✓ Custom exception class fixes, type inference expansion (String/File/Dir/Time/Regexp)
  ✓ JSON array parse, rescue else full implementation
  ✓ LLVM opt --passes=default<O2> integration
  ✓ HIR-level loop optimization (LICM)
  ✓ Test suite: 1614 tests, 0 failures


CRuby Integration Enhancement [Done]
─────────────────────────────────────────────────────────────────

  This enhanced integration with the CRuby ecosystem.

  ┌─────────────────────────────────────────────────────────────┐
  │  NativeClass GC Integration                                  │
  │  ─────────────────────────────────────────────────────────  │
  │                                                             │
  │  Goal: Enable NativeClass to safely hold VALUE-type fields  │
  │        (String, Array, etc.)                                │
  │                                                             │
  │  Implementation:                                            │
  │    - TypedData via rb_data_type_t                           │
  │    - Automatic GC mark function generation                  │
  │    - Automatic rb_gc_mark() calls                           │
  │                                                             │
  │  # @native                                                  │
  │  class Container                                             │
  │    @value: Float     # Unboxed (as before)                  │
  │    @name: String     # Held as VALUE, auto GC marked        │
  │    @items: Array     # Held as VALUE, auto GC marked        │
  │  end                                                         │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  Standard Library require                                    │
  │  ─────────────────────────────────────────────────────────  │
  │                                                             │
  │  Goal: Enable use of require "json" and other stdlib        │
  │                                                             │
  │  Implementation:                                            │
  │    - Distinguish stdlib vs user files                       │
  │    - Call rb_require() in Init_xxx function                 │
  │    - User files resolved statically as before               │
  │                                                             │
  │  # User code                                                │
  │  require "json"           # → rb_require("json")            │
  │  require_relative "util"  # → Compile-time resolution       │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  rb_* API Expansion                                          │
  │  ─────────────────────────────────────────────────────────  │
  │                                                             │
  │  Goal: Make more CRuby APIs directly available              │
  │                                                             │
  │  Covered:                                                   │
  │    - rb_hash_* (Hash operations)                            │
  │    - rb_ary_* (Array operations)                            │
  │    - rb_str_* (String operations)                           │
  │    - rb_io_* (IO operations)                                │
  │    - rb_thread_* (Thread operations)                        │
  └─────────────────────────────────────────────────────────────┘


C Extension Interop [Done]
─────────────────────────────────────────────────────────────────

  This enhanced cooperation with existing C extension libraries.


Developer Experience Improvements [Done]
─────────────────────────────────────────────────────────────────

  ✓ Debug information generation (DWARF)
  ✓ Error message improvements (Rust/Elm style)
  ✓ IDE integration (LSP server)
  ✓ Profiling support
  ✓ Incremental compilation


Standalone Execution [Cancelled]
─────────────────────────────────────────────────────────────────

  * Based on mruby experiment results, decided to specialize in CRuby extension mode
  * Crystal is recommended when standalone execution is needed


Language Features and Optimization [Done]
─────────────────────────────────────────────────────────────────

  ✓ Class variables, module definitions, exception handling improvements
  ✓ Enumerable (reduce, map, select, etc.), String Interpolation
  ✓ Fiber, Thread, Mutex, ConditionVariable, SizedQueue
  ✓ Pattern matching (case/in)
  ✓ Phi node optimization, Enumerable inline optimization (2-10x speedup)


Native Data Structures and stdlib [Done]
─────────────────────────────────────────────────────────────────

  ✓ Integer#times / Array#find / any? / all? / none? inlining
  ✓ NativeArray Enumerable, StaticArray, Slice, NativeString
  ✓ @struct (Value Type), NativeHash[K,V]
  ✓ @cfunc stdlib (HTTP/Crypto/Compression)
  ✓ Pattern matching advanced features (guard/capture/pin)


Ruby Core Language Feature Completion [Done]
─────────────────────────────────────────────────────────────────

  ✓ Logical operators (&&, ||) - short-circuit evaluation
  ✓ Compound assignment (+=, -=, *=, ||=, &&=) - local/ivar/cvar
  ✓ break / next - within while/until loops
  ✓ Range literals (1..5, 1...5)
  ✓ until loop, super, multiple assignment (a, b = [1, 2])
  ✓ Global variables ($var)
  ✓ VALUE boxing fixes - ivar/cvar/constants/arrays/hashes


─────────────────────────────────────────────────────────────────
  Legend:  ✓ = Done  X = Cancelled
─────────────────────────────────────────────────────────────────
```

### Key Goal: Integration with CRuby Ecosystem

```
┌─────────────────────────────────────────────────────────────────┐
│                    Features to Maintain and Enhance               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Write Ruby extensions in Ruby                               │
│     ─────────────────────────                                   │
│     Create fast CRuby extensions without writing C              │
│                                                                 │
│     Status: ✓ Done                                              │
│                                                                 │
│  2. Integrated with CRuby's GC                                  │
│     ────────────────────                                        │
│     No custom GC; uses CRuby's GC as-is                         │
│                                                                 │
│     Status: ✓ Done (NativeClass VALUE fields supported)         │
│                                                                 │
│  3. Can call existing C extension libraries                     │
│     ───────────────────────────────────                         │
│     Cooperates with C extensions like nokogiri, sqlite3, etc.   │
│                                                                 │
│     Status: ✓ Done (direct calls via @cfunc/@ffi)               │
│                                                                 │
│  4. Coexists with existing Ruby gems                            │
│     ────────────────────────                                    │
│     Mix compiled extensions with regular Ruby code              │
│                                                                 │
│     Status: ✓ Coexistence possible via require                  │
│     Enhancement: Standard library require supported             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
konpeito/
├── bin/konpeito              # CLI entry point
├── lib/konpeito/
│   ├── cli.rb                   # Command-line interface
│   ├── compiler.rb              # Main compiler
│   ├── dependency_resolver.rb   # require resolution
│   ├── parser/
│   │   └── prism_adapter.rb     # Prism parser wrapper
│   ├── type_checker/
│   │   ├── types.rb             # Type representations
│   │   ├── hm_inferrer.rb       # HM type inference
│   │   ├── unification.rb       # Unification
│   │   └── rbs_loader.rb        # RBS loader
│   ├── hir/
│   │   ├── nodes.rb             # HIR node definitions
│   │   └── builder.rb           # HIR generation
│   └── codegen/
│       ├── llvm_generator.rb    # LLVM IR generation
│       ├── monomorphizer.rb     # Monomorphization
│       ├── inliner.rb           # Inlining
│       ├── loop_optimizer.rb    # Loop optimization (LICM)
│       └── cruby_backend.rb     # CRuby extension generation
├── docs/
│   └── architecture.md          # This document
└── test/                        # Tests
```

---

## Appendix

### A. HIR (High-level Intermediate Representation)

HIR stands for **High-level Intermediate Representation**.
It is an intermediate representation positioned between the source code AST and the final LLVM IR.

```
Compilation Flow
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Ruby Source     AST          HIR           LLVM IR        Machine Code
      │           │            │               │              │
      │  Parse    │   Convert  │    Convert    │   Compile    │
      ↓           ↓            ↓               ↓              ↓
  ┌───────┐   ┌───────┐   ┌───────┐      ┌───────┐      ┌───────┐
  │ def   │   │ DefNode│   │Function│     │ define │     │ x86_64│
  │ add   │ → │  │     │ → │ Block  │  →  │ @add   │  →  │asm    │
  │ ...   │   │  └─... │   │ Instr  │     │ ...    │     │       │
  └───────┘   └───────┘   └───────┘      └───────┘      └───────┘

   Text       Syntax        Control Flow     Low-level      Executable
              Structure     Basic Blocks     Instructions
                                             SSA Form
```

#### Why HIR is Needed

**Problems with AST (Abstract Syntax Tree):**
- Too dependent on Ruby syntax
- Difficult to optimize
- Direct conversion to LLVM IR is complex

**Benefits of HIR:**
- Language-independent general representation
- Explicit control flow (basic blocks)
- Easy to apply optimization passes
- Simple conversion to LLVM IR

#### Concrete Example

```ruby
# Ruby code
def add(a, b)
  if a > 0
    a + b
  else
    b
  end
end
```

```
# AST (syntax structure)
DefNode(name: "add")
├── params: [a, b]
└── body: IfNode
    ├── condition: CallNode(a, ">", [0])
    ├── then: CallNode(a, "+", [b])
    └── else: LocalVarRead(b)
```

```
# HIR (control flow + basic blocks)
Function add(a, b):
  Block entry:
    %1 = LoadLocal a
    %2 = Call %1.>(0)
    CondBranch %2, then_block, else_block

  Block then_block:
    %3 = LoadLocal a
    %4 = LoadLocal b
    %5 = Call %3.+(%4)
    Branch merge_block

  Block else_block:
    %6 = LoadLocal b
    Branch merge_block

  Block merge_block:
    %7 = Phi [%5, then_block], [%6, else_block]
    Return %7
```

#### Main HIR Instructions

| Instruction | Description |
|-------------|-------------|
| `LoadLocal` | Read a local variable |
| `StoreLocal` | Write to a local variable |
| `Call` | Method call |
| `Branch` | Unconditional jump |
| `CondBranch` | Conditional branch |
| `Phi` | Select value at merge point in SSA |
| `Return` | Return from function |

HIR enables optimizations such as monomorphization and inlining to be performed before passing to LLVM.

---

### B. SSA (Static Single Assignment)

SSA stands for **Static Single Assignment**.
It is a form of intermediate representation that facilitates compiler optimization.

#### Basic Concept

**Rule: Each variable is assigned only once**

```
Regular Code                     SSA Form
─────────────────                ─────────────────

x = 1                            x1 = 1
x = x + 2                        x2 = x1 + 2
x = x * 3                        x3 = x2 * 3
return x                         return x3

  │                                  │
  ↓                                  ↓
  x is assigned 3 times              Each variable is assigned only once
  (which x?)                         (clearly which value)
```

#### Why SSA is Needed

```
Optimization Becomes Easier
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problem with regular form:

  x = a + b
  y = x * 2
  x = c + d      ← x was reassigned!
  z = x + 1      ← Which x is this?

  → Data flow analysis is complex


SSA form:

  x1 = a + b
  y  = x1 * 2
  x2 = c + d     ← Different variable name
  z  = x2 + 1    ← Clearly uses x2

  → Each variable is defined in only one place
  → Optimization becomes simple
```

#### Phi Function (Merge Point Handling)

When there are conditional branches, we need to decide which value to use:

```ruby
# Ruby code
if cond
  x = 1
else
  x = 2
end
puts x        # ← Is this x 1? 2?
```

```
# SSA form
Block entry:
  CondBranch cond, then_block, else_block

Block then_block:
  x1 = 1
  Branch merge

Block else_block:
  x2 = 2
  Branch merge

Block merge:
  x3 = Phi(x1 from then_block, x2 from else_block)
  │
  └── "Select value based on where we came from"

  Call puts(x3)
```

```
Phi Function Visualization
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

         then_block          else_block
             │                   │
           x1 = 1              x2 = 2
             │                   │
             └────────┬──────────┘
                      │
                      ↓
              ┌───────────────┐
              │ x3 = Phi(x1, x2) │
              │                 │
              │ if came from    │
              │   then → x1     │
              │   else → x2     │
              └───────────────┘
                      │
                      ↓
                  puts(x3)
```

#### Benefits of SSA

| Benefit | Description |
|---------|-------------|
| **Unique definitions** | Each variable is defined in only one place → clear use-definition relationship |
| **Easy optimization** | Constant propagation, dead code elimination, common subexpression elimination become simple |
| **Register allocation** | Variable liveness ranges are clear |
| **Adopted by LLVM** | LLVM IR is in SSA form |

#### Flow in Ruby Native

```
Ruby    →    HIR (SSA form)    →    LLVM IR (SSA form)
                │
                └── Optimization happens here
                    - Monomorphization
                    - Inlining
                    - Constant folding
```

By making HIR SSA form, conversion to LLVM becomes natural, and custom optimization passes become easier to write.

---

### C. SIMD Optimization

SIMD stands for **Single Instruction, Multiple Data**.
It is a parallel processing technique that processes multiple data items simultaneously with a single instruction.

#### Basic Concept

```
Scalar Processing (Regular)          SIMD Processing (Vector)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  4 additions executed sequentially   4 additions executed simultaneously

  a[0] + b[0] → c[0]               ┌─────────────────────┐
       ↓                           │ a[0] a[1] a[2] a[3] │
  a[1] + b[1] → c[1]               │  +    +    +    +   │
       ↓                           │ b[0] b[1] b[2] b[3] │
  a[2] + b[2] → c[2]               │  ↓    ↓    ↓    ↓   │
       ↓                           │ c[0] c[1] c[2] c[3] │
  a[3] + b[3] → c[3]               └─────────────────────┘

  4 instructions                     1 instruction for all 4
```

#### Why It's Fast

```
CPU Register Usage
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Regular Register (64bit)           SIMD Register (256bit / AVX)
  ┌──────────────────┐            ┌──────────────────────────────────┐
  │    1 value       │            │ Val1  │ Val2  │ Val3  │ Val4  │
  │    (64bit)       │            │ 64bit │ 64bit │ 64bit │ 64bit │
  └──────────────────┘            └──────────────────────────────────┘

  → 1 operation per cycle         → 4 operations per cycle (theoretically 4x faster)
```

#### Concrete Example: Array Sum

```ruby
# Ruby code
def sum(arr)
  total = 0.0
  arr.each { |x| total += x }
  total
end
```

```
Scalar Processing (Regular)
━━━━━━━━━━━━━━━━━━━━━━━━━━━

  total = 0
  total += arr[0]    # 1st
  total += arr[1]    # 2nd
  total += arr[2]    # 3rd
  total += arr[3]    # 4th
  total += arr[4]    # 5th
  total += arr[5]    # 6th
  total += arr[6]    # 7th
  total += arr[7]    # 8th

  → 8 loop iterations


SIMD Processing (Vectorized)
━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # Process 4 elements simultaneously
  vec_sum = [0, 0, 0, 0]

  Loop iteration 1:
  ┌─────────────────────────────┐
  │ arr[0] arr[1] arr[2] arr[3] │
  │   +      +      +      +    │
  │ update vec_sum               │
  └─────────────────────────────┘

  Loop iteration 2:
  ┌─────────────────────────────┐
  │ arr[4] arr[5] arr[6] arr[7] │
  │   +      +      +      +    │
  │ update vec_sum               │
  └─────────────────────────────┘

  # Final horizontal sum
  total = vec_sum[0] + vec_sum[1] + vec_sum[2] + vec_sum[3]

  → 2 loop iterations + horizontal sum
```

#### SIMD Instruction Sets

| Name | Bit Width | Simultaneous (64bit) | CPU |
|------|-----------|---------------------|-----|
| SSE | 128bit | 2 | Older x86 |
| AVX | 256bit | 4 | Modern x86 |
| AVX-512 | 512bit | 8 | Server-oriented |
| NEON | 128bit | 2 | ARM (Apple Silicon) |

#### Use in Ruby Native (Future)

```
Auto-vectorization with NativeArray
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# RBS
# @native
class Vector
  @data: NativeArray[Float64]

  def dot: (Vector other) -> Float
end

# Ruby
class Vector
  def dot(other)
    sum = 0.0
    @data.length.times do |i|
      sum += @data[i] * other.data[i]
    end
    sum
  end
end


Generated LLVM IR (conceptual):

  ; SIMD-vectorized loop
  %vec_a = load <4 x double>, ptr %data_a      ; Load 4 elements
  %vec_b = load <4 x double>, ptr %data_b      ; Load 4 elements
  %vec_mul = fmul <4 x double> %vec_a, %vec_b  ; Multiply 4 elements simultaneously
  %vec_sum = fadd <4 x double> %acc, %vec_mul  ; Add 4 elements simultaneously
```

#### Applicable Operations

| Operation | SIMD Effect | Example |
|-----------|-------------|---------|
| **Array operations** | ◎ | Element-wise add/sub/mul/div |
| **Dot product/matrix** | ◎ | Vector/matrix computation |
| **Image processing** | ◎ | Pixel manipulation |
| **Physics simulation** | ◎ | Particle computation |
| **String search** | ○ | Pattern matching |
| **Branch-heavy processing** | △ | Efficiency drops with branches |

#### LLVM Auto-vectorization

```
Conditions for LLVM to auto-vectorize
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Contiguous memory access (NativeArray)
  ✓ No dependencies within the loop
  ✓ Simple operations (add/sub/mul/div)

  ✗ Random access
  ✗ Loop body depends on previous results
  ✗ Complex conditional branching
```

Ruby Native's `NativeArray` uses contiguous memory layout, making it well-designed to benefit from LLVM's auto-vectorization.

---

### D. Boehm GC

Boehm GC is a **conservative garbage collector** for C/C++.
It was considered for Ruby Native's standalone execution mode (future plan).

#### Overview

```
Characteristics of Boehm GC: "Conservative" GC
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Regular GC (Precise GC)            Boehm GC (Conservative GC)
  ─────────────────────              ─────────────────────

  Precisely identifies               Scans all values as
  "this is a pointer"                "might be a pointer"

  ┌─────┐                          ┌─────┐
  │ ptr │→ Object                  │ ??? │→ Maybe an
  │ int │  (number)                │ ??? │  object?
  │ ptr │→ Object                  │ ??? │→ Maybe an
  └─────┘                          └─────┘  object?

  Requires type information          Works without type information
```

#### Advantages

```
┌─────────────────────────────────────────────────────────────────┐
│                        Advantages                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Easy to Adopt                                               │
│     ────────────                                                │
│     - Just replace malloc → GC_malloc                           │
│     - Existing C code can be used without major changes         │
│     - Compiler doesn't need to generate GC information          │
│                                                                 │
│  2. Suitable for Standalone Execution                           │
│     ────────────────────────────                                │
│     - Can create independent executables without CRuby          │
│     - Operates with minimal runtime                             │
│                                                                 │
│  3. Mature Library                                              │
│     ──────────────────                                          │
│     - 30+ years of track record                                 │
│     - Used in many projects (Mono, parts of GCC, w3m, etc.)     │
│     - Multi-thread support                                      │
│                                                                 │
│  4. Incremental GC Support                                      │
│     ─────────────────────                                       │
│     - Can distribute pause times                                │
│     - Usable in real-time scenarios                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Disadvantages

```
┌─────────────────────────────────────────────────────────────────┐
│                        Disadvantages                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Potential Memory Leaks                                      │
│     ────────────────────                                        │
│     - Integer values that happen to look like pointers →        │
│       not collected                                             │
│     - "False positive" memory leaks                             │
│                                                                 │
│  2. Difficult CRuby GC Integration                              │
│     ─────────────────────────                                   │
│     - CRuby has its own precise GC                              │
│     - Two GCs may conflict                                      │
│     - VALUE (Ruby objects) handling becomes complex              │
│                                                                 │
│  3. Performance Overhead                                        │
│     ──────────────────                                          │
│     - Conservative scanning is slower than precise GC           │
│     - Scans entire stack/registers                              │
│     - Especially impactful with large heaps                     │
│                                                                 │
│  4. Precision Issues                                            │
│     ────────────────                                            │
│     - Problems when pointing inside objects                     │
│     - Cannot do compacting GC                                   │
│     - Cannot move objects                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Decision in Ruby Native

| Mode | GC | Reason |
|------|-----|--------|
| **CRuby Extension** (primary) | CRuby GC | Natural integration, gem coexistence |
| **Standalone** (future) | Boehm GC | No CRuby dependency, easy to adopt |

Ruby Native prioritizes **CRuby GC integration enhancement** over Boehm GC, given its focus on integration with the CRuby ecosystem. Standalone execution is only considered for specific use cases (embedded, CLI tools, etc.).

---

### E. Detailed Roadmap

This section provides detailed descriptions of implemented features along with sample code.
Use it as a guide for future design and implementation work.

---

#### Optimization and Stabilization

```
┌─────────────────────────────────────────────────────────────────┐
│  Optimization and Stabilization                                  │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Monomorphization                                               │
│  Direct function calls (self-call optimization)                  │
│  Inlining                                                        │
│  Unboxed arithmetic type precision improvement                   │
│  Full rescue clause support                                      │
│  case/when statement support                                     │
│  for loop support                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

#### Native-First Migration -- Most Important

```
┌─────────────────────────────────────────────────────────────────┐
│  Native-First Migration                      *** Most Important │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  This transitioned the Ruby Native Compiler's language          │
│  model to "native-first".                                       │
│                                                                 │
│  Changed default to native structs                              │
│  Implemented @boxed annotation                                  │
│  Removed @native annotation                                     │
│  Updated documentation and sample code                          │
│                                                                 │
│  * @native retained for backward compatibility (vtable only)    │
│  * All subsequent implementation proceeds on native-first basis │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

#### Ecosystem, Stabilization, Performance, Idiom Completion

```
┌─────────────────────────────────────────────────────────────────┐
│  Performance Deepening                                           │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LLVM optimization pass enhancement                              │
│       opt --passes=default<O2> run before llc                   │
│       LICM, GVN, SROA, instcombine etc. auto-applied           │
│                                                                 │
│  Loop optimization (HIR-level LICM)                              │
│       loop_optimizer.rb: Natural loop detection                 │
│       Hoisting of pure methods (.length, .size, etc.)           │
│                                                                 │
│  Benchmark results:                                              │
│  ┌─────────────────────┬──────────┬──────────┬────────┐         │
│  │ Benchmark           │ Ruby     │ Native   │ Speedup│         │
│  ├─────────────────────┼──────────┼──────────┼────────┤         │
│  │ Counter sum          │ 724 i/s  │ 3.89M    │ 5380x  │         │
│  │ Nested loop          │ 22.9K    │ 44.5M    │ 1941x  │         │
│  │ Conditional loop     │ 60.2K    │ 2.99M    │ 49.7x  │         │
│  └─────────────────────┴──────────┴──────────┴────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

##### Optimization Pipeline

```
Ruby Source
    │
    ▼
┌──────────────┐
│  HM Type     │  ← Obtain type information
│  Inference   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Monomorphize │  ← Specialize polymorphic functions
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Inliner    │  ← Expand small functions
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Loop Optimize│  ← HIR-level LICM (pure method hoisting)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ LLVM IR Gen  │  ← Unboxed arithmetic, inline Enumerable
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ opt -O2      │  ← LLVM-level optimization (LICM, GVN, SROA, etc.)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ llc -O2      │  ← Machine code generation
└──────┬───────┘
       │
       ▼
  .bundle/.so
```

---

#### Feature Summary

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Area                           │ Key Features                             │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Optimization & Stabilization   │ Inlining, rescue, case/when, Integer     │
│                                │ type precision                           │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Native-First Migration ***     │ Native-first migration, @native removal, │
│                                │ @boxed intro                             │
├────────────────────────────────┼──────────────────────────────────────────┤
│ CRuby Integration              │ NativeClass GC integration, stdlib       │
│                                │ require, Proc/Lambda, keyword arguments  │
├────────────────────────────────┼──────────────────────────────────────────┤
│ C Extension Interop            │ @cfunc direct calls, C struct interop,   │
│                                │ SIMD, FFI                                │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Developer Experience           │ Debug info, error improvements, LSP,     │
│                                │ profiling                                │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Standalone Execution           │ Boehm GC, single binary                  │
│                                │ * Cancelled                              │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Language Features              │ Language feature completion, performance, │
│                                │ Ruby compat, pattern matching, phi       │
│                                │ optimization, native stdlib, concurrency │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Ecosystem                      │ Custom exception fixes, type inference   │
│                                │ expansion                                │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Stabilization                  │ JSON array, rescue else, test audit      │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Performance                    │ LLVM opt O2, loop optimization (LICM)    │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Ruby Idioms                    │ private/protected, &., splat(*args),     │
│                                │ defined?, open classes, alias, negative  │
│                                │ indexing                                 │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Modern Ruby                    │ _1/_2, it, class << self, endless method,│
│                                │ %w/%i, unsupported syntax diagnostics    │
├────────────────────────────────┼──────────────────────────────────────────┤
│ Collection Completion          │ Hash 2-arg blocks, numeric inlining      │
│                                │ (24-28x), Range enumeration (39-53x),    │
│                                │ Array mutation, Symbol                   │
└────────────────────────────────┴──────────────────────────────────────────┘
```

---

#### ★★★ Important: Long-term Vision - Removal of @native Annotation ★★★

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                                                                   ┃
┃   Ruby Native Compiler ultimately aims to be a                    ┃
┃   "native-first static subset language"                           ┃
┃                                                                   ┃
┃   → The @native annotation will become unnecessary in the future  ┃
┃                                                                   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Design Philosophy Shift:**

```
┌─────────────────────────────────────────────────────────────────┐
│                        Design Philosophy Shift                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Previous Thinking                   Future Thinking             │
│  ────────────                        ────────────                │
│                                                                 │
│  "Add native optimization to         "Add CRuby interop to a   │
│   a Ruby subset"                      native-first language"    │
│                                                                 │
│       Ruby                              Native                  │
│         │                                 │                     │
│         ▼                                 ▼                     │
│    ┌─────────┐                      ┌─────────┐                │
│    │  VALUE  │ ← Default            │  struct │ ← Default      │
│    │ (boxed) │                      │(unboxed)│                │
│    └─────────┘                      └─────────┘                │
│         │                                 │                     │
│     @native                           @boxed                    │
│         ▼                                 ▼                     │
│    ┌─────────┐                      ┌─────────┐                │
│    │  struct │ ← Explicitly         │  VALUE  │ ← Explicitly   │
│    │(unboxed)│   specified          │ (boxed) │   specified    │
│    └─────────┘                      └─────────┘                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**What this shift achieves:**

| Item | Effect |
|------|--------|
| **Simple syntax** | No special annotations needed to write fast code |
| **Clear intent** | Only use `@boxed` when CRuby interop is explicitly needed |
| **Consistent performance** | All code is fast by default |
| **Type inference leverage** | Layout automatically determined from field types |

---

### F. C Library Call Design

There are two different approaches to calling C code in Ruby Native Compiler.
Their purposes and designs are clearly distinguished.

#### 1. Using Ruby C Extension Libraries (via rb_funcallv)

**Target:** Ruby C extension libraries such as `json`, `nokogiri`, `pg`

**Method:** Called via `rb_funcallv` just like regular Ruby method calls

```ruby
# Ruby Native code
require "json"
require "nokogiri"

class DataProcessor
  def parse_json(str)
    JSON.parse(str)  # → rb_funcallv(cJSON, rb_intern("parse"), ...)
  end

  def parse_html(html)
    Nokogiri::HTML(html)  # → via rb_funcallv
  end
end
```

**Characteristics:**

| Item | Description |
|------|-------------|
| Compatibility | ✅ All Ruby C extensions can be used |
| Stability | ✅ Only public APIs used |
| Performance | △ rb_funcallv overhead present |
| Type safety | △ Runtime checking |

**Note:** We do not provide functionality to directly call "internal functions" of Ruby C extensions.
Reasons:
- Internal functions are not API and change between versions
- Benefit of direct calls is small (C extensions are already native code)
- If needed, calling the original C library directly via `@ffi` is more stable

#### 2. Direct C Library Calls (@ffi + @cfunc)

**Target:** Regular C libraries such as `libm`, `libsqlite3`, `libpng`, `libcurl`

**Method:** LLVM directly generates code for C function calls

```rbs
# RBS type definitions
# @ffi "libm"
module LibM
  # @cfunc "sin"
  def self.sin: (Float) -> Float

  # @cfunc "cos"
  def self.cos: (Float) -> Float

  # @cfunc "pow"
  def self.pow: (Float, Float) -> Float
end
```

```ruby
# Ruby Native code
angle = 3.14159 / 4
sin_val = LibM.sin(angle)   # Direct C function call
cos_val = LibM.cos(angle)   # Does NOT go through rb_funcallv
```

**Characteristics:**

| Item | Description |
|------|-------------|
| Performance | ✅ Zero overhead (direct call) |
| Type safety | ✅ Type checked at compile time |
| Target | Regular C libraries (.so/.dylib) |
| Constraint | Library linking required |

#### 3. Comparison Table

```
┌─────────────────────────────────────────────────────────────────┐
│                    C Code Call Comparison                         │
├─────────────────┬───────────────────┬───────────────────────────┤
│                 │ Ruby C Extensions │ Regular C Libraries        │
│                 │ (json, nokogiri)  │ (libm, libsqlite3)        │
├─────────────────┼───────────────────┼───────────────────────────┤
│ Call method     │ via rb_funcallv   │ Direct function call      │
├─────────────────┼───────────────────┼───────────────────────────┤
│ Annotation      │ None (require)    │ @ffi + @cfunc             │
├─────────────────┼───────────────────┼───────────────────────────┤
│ Overhead        │ Present           │ None                      │
├─────────────────┼───────────────────┼───────────────────────────┤
│ Type checking   │ Runtime           │ Compile-time              │
├─────────────────┼───────────────────┼───────────────────────────┤
│ Usage example   │ JSON.parse(str)   │ LibM.sin(x)               │
└─────────────────┴───────────────────┴───────────────────────────┘
```

---

### G. TopLevel Module Pattern and Type Inference Design Philosophy

When adding type annotations to top-level methods, a pseudo-module called `TopLevel` is used.
There is a clear rationale behind this design.

#### 1. Problem: Type Inference in Loop Conditions

```ruby
def native_sum(n)
  i = 0
  while i < n    # ← What is the type of n?
    i = i + 1
  end
  i
end
```

HM type inference (Algorithm W) infers the type of `n` from `i < n`, but since the `<` operator is applicable to both `Integer` and `Float`, it infers the **most general type**, which is `Numeric`.

```
Inference result: native_sum: (Numeric) -> Integer
```

Since a `Numeric`-typed parameter is not eligible for unboxed optimization, the loop condition `i < n` becomes a slow comparison via `rb_funcallv`.

#### 2. Why We Don't Change the Type Inferrer

One might think "since there's a literal `2`, it should infer `Integer`", but we do not change the type inferrer for the following reasons.

##### (a) The Principal Type Principle

The fundamental principle of HM type inference is to "**infer the most general type**".

```ruby
def compare(a, b)
  a < b
end
```

This function works with `Integer`, `Float`, and `String`. If the type inferrer arbitrarily chose `Integer`, it would break other use cases.

##### (b) Developer Intent Cannot Be Inferred

```ruby
# Want to loop with Integer
def count_up(n)
  i = 0
  while i < n
    i = i + 1
  end
end

# Want to loop with Float
def iterate_range(limit)
  x = 0.0
  while x < limit
    x = x + 0.1
  end
end
```

Both are syntactically the same pattern. The type inferrer cannot determine which is "correct". **Only the developer knows the intent**.

##### (c) Principle of Minimal Change

| Approach | Changes | Risk |
|----------|---------|------|
| Add TopLevel RBS | RBS file only | Low |
| Change type inferrer | Core logic | High (affects other inference) |

Changing the core logic of the type inferrer could cause unexpected side effects elsewhere.

#### 3. TopLevel Module Pattern

The solution is to explicitly specify types using the `TopLevel` pseudo-module.

```rbs
# RBS file
module TopLevel
  def native_sum: (Integer n) -> Integer
  def native_dot_product: (Integer n) -> Float
end
```

```ruby
# Ruby source (no changes needed)
def native_sum(n)
  i = 0
  while i < n
    i = i + 1
  end
  i
end
```

This results in:
- `n` is recognized as `Integer` type
- `i < n` is compiled to the unboxed `icmp slt i64` instruction
- The loop is accelerated

#### 4. Design Philosophy Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    Responsibility Division for Type Info      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   RBS Type Annotations    HM Type Inference                 │
│   ─────────────────       ──────────────                    │
│   Developer explicitly    Fallback when RBS                 │
│   specifies intent        is not available                  │
│                                                             │
│   - Parameter types       - Local variables                 │
│   - Return types          - Intermediate expression types   │
│   - External APIs         - When types are obvious          │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  Principle: Type info for optimization is provided by the   │
│  developer via RBS                                          │
└─────────────────────────────────────────────────────────────┘
```

#### 5. Future Considerations

This design may change in the future.

Ideas under consideration:
- **Type hint syntax**: Respond if Ruby itself adds type hint syntax
- **Inference improvements**: Detection of specific patterns (where `i` is obviously an integer in `while i < n`)
- **Warning feature**: Warning display for locations where unboxed optimization was not applied

However, at this point, the TopLevel module pattern is the simplest and safest approach.
