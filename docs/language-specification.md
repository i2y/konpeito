# Konpeito Language Specification

**Version 0.1 (Draft)**
**Date: 2026-02-13**

Konpeito is an Ahead-of-Time (AOT) native compiler for a statically typable subset of Ruby 4.0. It uses the Prism parser and RBS type system with Hindley-Milner type inference, generating native code via LLVM and JVM backends.

> 金平糖（konpeitō）— Sugar crystals. Crystallizing Ruby code into native code.

---

## Part I: Introduction and Basics

### 1. Scope and Purpose

Konpeito compiles a **static subset** of Ruby 4.0 to native code. It uses HM type inference to determine types where possible, generating optimized native code for type-resolved paths and falling back to dynamic dispatch for unresolved paths.

**Goals:**
- Enable Ruby developers to write performance-critical code in familiar syntax
- Provide 5-5000x speedup over interpreted Ruby through native compilation (for type-resolved code paths)
- Maintain compatibility with CRuby's ecosystem via the C extension interface

**Non-goals:**
- Replace CRuby as a general-purpose Ruby implementation
- Support dynamically-typed Ruby features (eval, method_missing, etc.)

**Type Resolution Philosophy:**

Konpeito uses a **gradual approach** to type resolution. When HM inference and RBS can fully determine types, the compiler generates optimized native code (unboxed arithmetic, direct method calls). When types cannot be fully resolved, the compiler falls back to dynamic dispatch:

| Type Resolution | LLVM Backend | JVM Backend | Performance |
|----------------|-------------|-------------|-------------|
| **Fully resolved** | Native CPU instructions | `invokevirtual` | Optimal (5-5000x) |
| **Partially resolved** | `rb_funcallv` (CRuby API) | `invokedynamic` (RubyDispatch) | CRuby-equivalent |
| **Unresolved** | `rb_funcallv` fallback | `invokedynamic` fallback | CRuby-equivalent |

Unresolved types produce **informational warnings** during compilation, not hard errors. This means Konpeito can compile most valid Ruby code, with performance benefits proportional to how much type information is available.

### 2. Notation

This specification uses the following notation conventions.

#### 2.1 Type Judgment Notation

Type judgments use the standard form:

```
Γ ⊢ e : T
```

Read as: "Under environment Γ, expression e has type T."

#### 2.2 Inference Rules

Inference rules are written as:

```
  premise₁   premise₂   ...
  ─────────────────────────
  conclusion
```

Where all premises must hold for the conclusion to be derived.

#### 2.3 Terminology

| Term | Definition |
|------|-----------|
| **Type** | A compile-time classification of values |
| **TypeVar** | A placeholder type variable (τ₁, τ₂, ...) awaiting resolution |
| **Unification** | The process of making two types equal by binding TypeVars |
| **LUB** | Least Upper Bound — the most specific common supertype |
| **Prune** | Following TypeVar chains to find the final bound type |
| **Boxing** | Converting a native value (i64, double) to a Ruby VALUE |
| **Unboxing** | Converting a Ruby VALUE to a native value |
| **Statement position** | A context where an expression's value is not used (e.g., `while` body, `if`/`unless` whose result is not assigned or returned, non-final expressions in a sequence) |
| **HIR** | High-level Intermediate Representation |
| **Native class** | A class with fixed C struct layout (unboxed fields) |
| **VALUE** | CRuby's universal tagged pointer type |

### 3. Conformance Levels

Konpeito defines two backend conformance levels:

| Level | Backend | Output | Runtime Dependency |
|-------|---------|--------|-------------------|
| **LLVM** | LLVM 20 | CRuby extension (.so/.bundle) | CRuby 4.0+ |
| **JVM** | ASM bytecode | Standalone JAR (.jar) | Java 21+ |

Both backends accept the same source language but may differ in:
- Available standard library modules
- Native data structure memory layout details
- Java interop (JVM only) / C interop (LLVM only)

Backend-specific differences are documented in Part VII.

---

## Part II: Lexical Structure and Syntax

### 4. Source Text

#### 4.1 Encoding

All source files must be UTF-8 encoded.

#### 4.2 File Types

| Extension | Purpose |
|-----------|---------|
| `.rb` | Ruby source code |
| `.rbs` | RBS type definitions (optional) |

When using `--inline` mode, RBS annotations are embedded in `.rb` files using `rbs-inline` comments:

```ruby
# rbs_inline: enabled

#: (Integer, Integer) -> Integer
def add(a, b)
  a + b
end
```

### 5. Supported Ruby Syntax

Konpeito accepts the following Ruby 4.0 syntax elements.

#### 5.1 Literals

| Literal | Examples |
|---------|----------|
| Integer | `42`, `-1`, `0xFF`, `0b1010`, `1_000_000` |
| Float | `3.14`, `-0.5`, `1.0e10` |
| String | `"hello"`, `'world'`, `"Hello #{name}"` |
| Symbol | `:foo`, `:"complex-name"` |
| Array | `[1, 2, 3]`, `%w[a b c]`, `%i[x y z]` |
| Hash | `{ key: value }`, `{ "k" => v }` |
| Range | `1..5` (inclusive), `1...5` (exclusive) |
| Regexp | `/pattern/`, `/pattern/i` |
| Boolean | `true`, `false` |
| Nil | `nil` |
| Heredoc | `<<HEREDOC`, `<<~HEREDOC` |
| Lambda | `-> { expr }`, `->(x) { expr }` |

#### 5.2 Variables

| Kind | Syntax | Scope |
|------|--------|-------|
| Local | `name` | Method/block |
| Instance | `@name` | Instance |
| Class | `@@name` | Class hierarchy |
| Global | `$name` | Process-wide |
| Constant | `NAME` | Lexical |

#### 5.3 Operators

**Arithmetic:** `+`, `-`, `*`, `/`, `%`, `**`
**Comparison:** `==`, `!=`, `<`, `>`, `<=`, `>=`, `<=>`
**Logical:** `&&`, `||`, `!` (short-circuit evaluation)
**Bitwise:** `&`, `|`, `^`, `<<`, `>>`
**Assignment:** `=`, `+=`, `-=`, `*=`, `/=`, `||=`, `&&=`
**Other:** `&.` (safe navigation), `..`/`...` (range), `defined?`

#### 5.4 Control Flow

- `if`/`elsif`/`else`/`end`, `unless`
- `while`, `until`
- `for x in collection`
- `case`/`when` (value matching)
- `case`/`in` (pattern matching, Ruby 3.0+)
- `break`, `next`, `return`

#### 5.5 Definitions

- `def`/`end` (method), `def foo = expr` (endless method, Ruby 3.0+)
- `class`/`end`, `class << self` (singleton class)
- `module`/`end`
- `begin`/`rescue`/`else`/`ensure`/`end`
- `private`, `protected`, `public`
- `alias`, `alias_method`
- `attr_accessor`, `attr_reader`, `attr_writer`
- `include`, `extend`, `prepend`
- `super`, `super(args)`

#### 5.6 Block and Proc

- `method { |x| ... }`, `method do |x| ... end`
- `yield`, `block_given?`
- `_1`, `_2` (numbered parameters, Ruby 2.7+)
- `it` (implicit parameter, Ruby 3.4+)
- `-> { ... }` (lambda literal)
- `proc.call(args)`

#### 5.7 Pattern Matching (case/in)

```ruby
case expr
in pattern then body
in pattern if guard then body
else body
end
```

Supported patterns: literal, type/constant, variable, alternation (`|`), array deconstruction, hash deconstruction, rest (`*`), capture (`=>`), pin (`^`), guard (`if`).

#### 5.8 Multiple Assignment

```ruby
a, b = [1, 2]
a, b, c = array
```

### 6. Excluded Syntax

The following Ruby features are **not supported** by design:

| Feature | Reason |
|---------|--------|
| `eval`, `instance_eval`, `class_eval` | Requires runtime code generation |
| `define_method`, `method_missing` | Dynamic dispatch incompatible with static compilation |
| `ObjectSpace` | Requires GC introspection |
| `Binding` | Requires runtime scope capture |
| Dynamic `require`/`load` | Variable paths cannot be resolved at compile time |
| `send`, `public_send` | Dynamic method dispatch |

Encountering these constructs produces a compile-time warning.

### 7. Semantic Differences from CRuby

| Aspect | CRuby | Konpeito |
|--------|-------|---------|
| Integer overflow | Automatic Bignum promotion | Wraps at i64 bounds (LLVM), Long bounds (JVM); no automatic Bignum fallback |
| Nil safety | Runtime NoMethodError | Compile-time type narrowing available |
| Method resolution | Dynamic dispatch | Static dispatch when type resolved; falls back to dynamic dispatch (`rb_funcallv` / `invokedynamic`) otherwise |
| Blocks | Closures over mutable state | Capture semantics (value or reference based on backend) |
| Thread parallelism | GVL limits to one Ruby thread at a time | LLVM: Same GVL limitation; JVM: True parallelism via Virtual Threads |
| Hash#each arguments | `[k, v]` as single argument (Ruby 4.0) | Both backends handle Ruby 4.0 semantics (runtime argc check in block callback) |

---

## Part III: Type System

The type system is the core of Konpeito. It determines how values are classified, how types are inferred, and how native code is generated.

### 8. Types

#### 8.1 Primitive Types

Primitive types map directly to machine representations:

| Type | Konpeito Name | LLVM | JVM | Description |
|------|--------------|------|-----|-------------|
| Integer | `Types::INTEGER` | `i64` | `long` | 64-bit signed integer |
| Float | `Types::FLOAT` | `double` | `double` | IEEE 754 double precision |
| Bool | `Types::BOOL` | `i8` | `boolean` | Boolean value |
| Nil | `Types::NIL` | `i64` (VALUE=4) | `null` | Absence of value |

**Integer** is represented as a ClassInstance with name `:Integer`. When type is known at compile time, values are stored unboxed as native `i64`/`long`.

**Float** is represented as a ClassInstance with name `:Float`. When type is known, values are stored unboxed as native `double`.

**Bool** is a distinct type from Integer. In CRuby, `true` and `false` are instances of `TrueClass` and `FalseClass` respectively. Konpeito unifies these with `BoolType` for unboxed representation (`i8`).

**Nil** has special semantics: it is compatible with every type (Ruby's implicit nullable semantics). See Section 9.2.

#### 8.2 Object Types

##### ClassInstance

Represents an instance of a named class, optionally with generic type arguments.

```
ClassInstance(name, type_args?)
```

Examples:
- `ClassInstance(:Integer)` — an Integer value
- `ClassInstance(:Array, [ClassInstance(:String)])` — `Array[String]`
- `ClassInstance(:Hash, [ClassInstance(:Symbol), ClassInstance(:Integer)])` — `Hash[Symbol, Integer]`

##### ClassSingleton

Represents the class object itself (not an instance). Used for class method calls and constant references.

```
ClassSingleton(name)
```

Examples:
- `ClassSingleton(:Math)` — the Math module/class
- `ClassSingleton(:Array)` — receiver of `Array.new`

##### Class Hierarchy

Built-in subtype relationships:

```
Integer   < Numeric < Object < BasicObject
Float     < Numeric < Object < BasicObject
String    < Object < BasicObject
Array     < Object < BasicObject
Hash      < Object < BasicObject
Symbol    < Object < BasicObject
Range     < Object < BasicObject
Regexp    < Object < BasicObject
Proc      < Object < BasicObject
TrueClass < Object < BasicObject
FalseClass < Object < BasicObject
NilClass  < Object < BasicObject
Fiber     < Object < BasicObject
Thread    < Object < BasicObject
Mutex     < Object < BasicObject

Exception        < Object < BasicObject
StandardError    < Exception
RuntimeError     < StandardError
TypeError        < StandardError
ArgumentError    < StandardError
NameError        < StandardError
NoMethodError    < NameError
IOError          < StandardError
ZeroDivisionError < StandardError
```

User-defined classes register their hierarchy at compile time via `register_class_hierarchy`.

#### 8.3 Composite Types

##### Union Type

Represents a value that could be one of several types.

```
Union(T₁, T₂, ..., Tₙ)
```

RBS notation: `Integer | String`

Rules:
- Nested unions are flattened: `Union(Union(A, B), C)` → `Union(A, B, C)`
- Duplicate types are removed
- A union `Union(T₁, ..., Tₙ)` is a subtype of `U` if and only if every `Tᵢ` is a subtype of `U`

##### ProcType

Represents a callable (lambda or Proc).

```
ProcType(param_types, return_type)
```

RBS notation: `^(Integer, String) -> Bool`

##### FunctionType

Internal representation of a method signature during inference.

```
FunctionType(param_types, return_type, rest_param_type?)
```

Where `rest_param_type` is the element type of `*args` (if any).

##### Tuple

Represents a fixed-size ordered collection of heterogeneous types.

```
Tuple(T₁, T₂, ..., Tₙ)
```

##### Array and Hash Types

Array and Hash are ClassInstance types with generic arguments:

```
Array[T]     = ClassInstance(:Array, [T])
Hash[K, V]   = ClassInstance(:Hash, [K, V])
```

#### 8.4 Native Data Structure Types

These types have special memory layouts optimized for performance.

##### NativeArrayType

Contiguous memory array with unboxed elements.

```
NativeArray[T]   where T ∈ { Int64, Float64, NativeClassType }
```

Memory layout: `alloca T, N` (stack-allocated contiguous array)

| Element Type | LLVM Type | JVM Type |
|-------------|-----------|----------|
| `Int64` | `i64*` | `long[]` |
| `Float64` | `double*` | `double[]` |
| NativeClass | `struct*` | `Object[]` |

##### StaticArrayType

Fixed-size, stack-allocated array with compile-time known size.

```
StaticArray[T, N]   where T ∈ { Int64, Float64 }, N > 0
```

Memory layout: `alloca [N x T]` (no heap allocation)

Constraints:
- Size `N` must be a compile-time constant
- Only primitive element types

##### SliceType

Bounds-checked pointer view into contiguous memory.

```
Slice[T]   where T ∈ { Int64, Float64 }
```

Memory layout: `{ ptr: T*, size: i64 }` (16 bytes)

Operations: indexed access (bounds-checked), sub-slicing (zero-copy), copy, fill.

##### NativeHashType

Typed hash map with linear probing.

```
NativeHash[K, V]
  where K ∈ { String, Symbol, Integer }
  and   V ∈ { Integer, Float, Bool, String, Object, Array, Hash, NativeClassType }
```

Memory layout:
- Header: `{ buckets_ptr, size, capacity }` (24 bytes)
- Entry: `{ hash_value: i64, key, value, state: i8 }` (32 bytes aligned)
- State: 0=empty, 1=occupied, 2=tombstone
- Auto-resize at load factor > 0.75

##### NativeClassType

Fixed-layout C struct with typed fields and instance methods.

```
NativeClass { field₁: T₁, field₂: T₂, ... }
```

Field types:
- Unboxed: `Int64` (i64), `Float64` (double), `Bool` (i8)
- Boxed (VALUE): `String`, `Array`, `Hash`, `Object`
- Embedded: another `NativeClassType`

Features:
- Inheritance (superclass chain)
- Optional vtable for dynamic dispatch (`%a{native: vtable}`)
- GC marking for VALUE fields
- Value type variant (`%a{struct}` — pass-by-value, max 128 bytes, no VALUE fields)

##### ByteBufferType, ByteSliceType, StringBufferType, NativeStringType

Specialized buffer types for I/O and string operations.

| Type | Purpose | Memory |
|------|---------|--------|
| `ByteBuffer` | Growable byte array | Heap-allocated, capacity-tracked |
| `ByteSlice` | Zero-copy view into ByteBuffer | Pointer + length |
| `StringBuffer` | Efficient string building | Wraps `rb_str_buf_new` |
| `NativeString` | UTF-8 byte/char operations | `{ ptr, byte_len, char_len, flags }` (32 bytes) |

#### 8.5 Special Types

##### Untyped

Represents an unknown or unconstrained type. Compatible with all types.

```
Untyped.subtype_of?(T) = true   for all T
unify(Untyped, T) = success     for all T
```

Used when:
- RBS declares `untyped`
- Type inference cannot determine a type (fallback, not recommended)

##### Bottom

Represents an impossible value (unreachable code, diverging computation).

```
Bottom.subtype_of?(T) = true   for all T
```

##### TypeVar

A placeholder type variable used during inference.

```
TypeVar(id, name?, instance?)
```

TypeVars are created fresh during inference and resolved by unification. After inference completes, no TypeVar should remain unresolved (validated by `validate_all_types_resolved!`).

#### 8.6 Subtyping Rules

The subtyping relation `T₁ <: T₂` ("T₁ is a subtype of T₂") is defined by:

**Reflexivity:**
```
T <: T
```

**Top types:**
```
T <: Untyped     for all T
```

**Bottom type:**
```
Bottom <: T      for all T
```

**Nil universality (Ruby nullable semantics):**
```
NilType <: T     for all T
```

**Class hierarchy:**
```
  class C < P
  ──────────────
  C <: P
```

**Transitivity:**
```
  T₁ <: T₂    T₂ <: T₃
  ─────────────────────
  T₁ <: T₃
```

**Union subtyping:**
```
  T₁ <: U    T₂ <: U    ...    Tₙ <: U
  ─────────────────────────────────────
  Union(T₁, T₂, ..., Tₙ) <: U
```

**Boolean compatibility:**
```
TrueClass  <: Bool
FalseClass <: Bool
Bool <: TrueClass    (mutual compatibility)
Bool <: FalseClass   (mutual compatibility)
```

Note: The `Bool <: TrueClass` and `Bool <: FalseClass` rules are not formal subtyping in the classical sense. They express **mutual compatibility** — Konpeito unifies `Bool` with either `TrueClass` or `FalseClass` in any direction to simplify boolean handling. This avoids requiring explicit `is_a?` checks when a method returns `Bool` but the caller expects `TrueClass`/`FalseClass` (or vice versa).

### 9. Type Inference

Konpeito uses Hindley-Milner type inference (Algorithm W) as the primary mechanism for determining types. RBS type definitions serve as optional supplementary information.

#### 9.1 Algorithm W (HM Inference)

The inference algorithm traverses the Typed AST, assigning types to each expression.

##### Literals

```
  ──────────────────────
  Γ ⊢ n : Integer          (integer literal)

  ──────────────────────
  Γ ⊢ f : Float             (float literal)

  ──────────────────────
  Γ ⊢ "s" : String          (string literal)

  ──────────────────────
  Γ ⊢ :s : Symbol           (symbol literal)

  ──────────────────────
  Γ ⊢ true : Bool           (boolean literal)

  ──────────────────────
  Γ ⊢ false : Bool          (boolean literal)

  ──────────────────────
  Γ ⊢ nil : NilType         (nil literal)
```

##### Variables

```
  Γ(x) = σ    τ = instantiate(σ)
  ──────────────────────────────
  Γ ⊢ x : τ
```

Variable lookup finds the type scheme `σ` in the environment, then instantiates fresh TypeVars for any quantified variables.

##### Method Definition

```
  τ₁, ..., τₙ = fresh TypeVars
  Γ' = Γ, x₁: τ₁, ..., xₙ: τₙ
  Γ' ⊢ body : τᵣ
  ──────────────────────────────────────
  Γ ⊢ (def m(x₁, ..., xₙ) = body) : (τ₁, ..., τₙ) → τᵣ
```

If RBS provides a type signature for `m`, the RBS types are used instead of fresh TypeVars. The inferred body type is unified with the RBS return type.

##### Method Call

```
  Γ ⊢ receiver : T_recv
  Γ ⊢ m : (T₁, ..., Tₙ) → Tᵣ     (looked up on T_recv)
  Γ ⊢ e₁ : T₁'   ...   Γ ⊢ eₙ : Tₙ'
  unify(T₁, T₁')   ...   unify(Tₙ, Tₙ')
  ──────────────────────────────────────
  Γ ⊢ receiver.m(e₁, ..., eₙ) : Tᵣ
```

Method lookup proceeds through three paths:
1. **Self-calls**: Look up `ClassName#method_name` in function types, walking up the class hierarchy
2. **Receiver calls**: Look up method on the receiver's ClassInstance type
3. **Built-in methods**: Check built-in type rules before RBS lookup

##### If Expression

```
  Γ ⊢ cond : T_cond
  Γ_then = narrow(Γ, cond, true)
  Γ_then ⊢ then_body : T_then
  Γ_else = narrow(Γ, cond, false)
  Γ_else ⊢ else_body : T_else
  τ = fresh TypeVar
  unify(τ, T_then)    unify(τ, T_else)
  ──────────────────────────────────────
  Γ ⊢ if cond then then_body else else_body : apply(τ)
```

In **statement position** (when the result is not used), branch type consistency is not required:

```
  Γ ⊢ cond : T_cond
  Γ_then ⊢ then_body : T_then
  Γ_else ⊢ else_body : T_else
  ──────────────────────────────    (statement position)
  Γ ⊢ if cond then ... : NilType
```

##### Array Literal

```
  Γ ⊢ e₁ : T₁   ...   Γ ⊢ eₙ : Tₙ
  τ = fresh TypeVar
  unify(τ, T₁)   ...   unify(τ, Tₙ)    (skip unresolved TypeVars)
  ──────────────────────────────────────
  Γ ⊢ [e₁, ..., eₙ] : Array[apply(τ)]
```

If any element is an unresolved TypeVar, it is skipped during unification and the array is marked heterogeneous (`Array[Untyped]`). This prevents TypeVar contamination.

##### Block / Yield

```
  Γ ⊢ block_body : T_block     (with block params bound)
  Γ ⊢ yield(args) : T_yield
  unify(T_block, T_yield)
  ──────────────────────────────
  Γ ⊢ method { |params| block_body } : T_method_return
```

#### 9.2 Unification

Unification makes two types equal by binding TypeVars. The algorithm is based on Robinson's unification with Ruby-specific extensions.

##### Core Algorithm

```
unify(t₁, t₂):
  t₁ = prune(t₁)
  t₂ = prune(t₂)

  case (t₁, t₂):
    (τ, _):
      if τ == t₂: return               # Already same
      if occurs_in?(τ, t₂): ERROR      # Infinite type
      τ.instance = t₂                  # Bind TypeVar

    (_, τ):
      unify(t₂, t₁)                    # Symmetric

    (FunctionType, FunctionType):
      check arity match
      unify each param pair
      unify rest_param_types if both exist
      unify return types

    (ClassInstance(n₁, args₁), ClassInstance(n₂, args₂)):
      if n₁ == n₂:
        unify each type argument pair
      else:
        check subtype or find LUB

    (_, _):
      if t₁ == t₂: return              # Structural equality
      if either is UNTYPED: return      # Wildcard
      if either is NIL: return          # Nil compatible with all
      if boolean_compatible?(t₁, t₂): return
      if singleton_value_compatible?(t₁, t₂): return
      ERROR                             # Cannot unify
```

##### Prune (Path Compression)

```
prune(t):
  if t is TypeVar and t.instance exists:
    t.instance = prune(t.instance)    # Path compression
    return t.instance
  return t
```

##### Occurs Check

Prevents infinite types (e.g., `τ = τ → Integer`):

```
occurs_in?(τ, t):
  t = prune(t)
  if τ == t: return true
  if t is FunctionType:
    return true if any param/return contains τ
  if t is ClassInstance:
    return true if any type_arg contains τ
  return false
```

##### Special Unification Rules

**Nil compatibility:**
Nil unifies with any type, preserving the concrete type:
```
unify(Integer, NilType) = success    (result: Integer)
unify(String,  NilType) = success    (result: String)
```

**Boolean compatibility:**
`TrueClass`, `FalseClass`, and `Bool` are mutually compatible:
```
unify(TrueClass, FalseClass) = success
unify(Bool, TrueClass) = success
unify(Bool, FalseClass) = success
```

**Numeric widening:**
Integer→Float is treated as a safe widening primitive conversion (Java/Kotlin style), not as a LUB lookup:
```
unify(Integer, Float) → Float     (widening primitive conversion)
unify(Float, Integer) → Float     (reverse direction also widens to Float)
```
This prevents TypeVar contamination to `Numeric` (which would lose unboxed optimization on JVM).
The reverse direction (Float→Integer) is not implicit — explicit conversion (`.to_i`) is required.

**ClassSingleton value compatibility:**
Value constants (e.g., `EXPANDING = 2`) produce `ClassSingleton(:EXPANDING)` which unifies with its base type:
```
unify(ClassSingleton(:EXPANDING), Integer) = success
```

#### 9.3 Deferred Constraint Resolution

When a method body calls another method on a TypeVar receiver, the call cannot be resolved immediately. Instead, it is **deferred**.

```
def process(x)        # x : τ₁ (TypeVar)
  x.length            # Deferred: τ₁.length → τ₂
end

process("hello")      # Call site: τ₁ unified with String
```

**Resolution algorithm (`propagate_call_site_types`):**

1. At each call site, build a **local solutions map** mapping param TypeVars to concrete argument types
2. Iteratively resolve deferred constraints (up to 5 iterations):
   - For each deferred constraint `(receiver_typevar, method_name, args)`:
     - Resolve receiver using local solutions
     - If still TypeVar, skip
     - Look up method on resolved type
     - Store result in solutions map
3. Apply solutions to return type

This is a **local** resolution — it does not modify the original TypeVars, enabling the same polymorphic function to be instantiated differently at different call sites.

#### 9.4 RBS Integration

RBS provides supplementary type information. The priority order is:

1. **Built-in method rules** (checked first — ensures `==` returns `Bool`, not `Numeric`)
2. **RBS type signatures** (if available)
3. **HM inference** (always runs)

When RBS provides a method signature:
- Parameter types from RBS constrain the corresponding TypeVars
- Return type from RBS is unified with the inferred return type
- Generic type parameters in RBS are instantiated as fresh TypeVars

RBS for top-level methods uses the `TopLevel` module:

```rbs
module TopLevel
  def add: (Integer a, Integer b) -> Integer
end
```

**RBS is optional.** The compiler must produce correct results with HM inference alone. RBS serves to:
- Provide more precise types for optimization (e.g., `Array[Integer]` enables unboxed iteration)
- Document API contracts
- Resolve ambiguous cases

#### 9.5 Monomorphization

Polymorphic functions are specialized to concrete types at each call site:

```ruby
def identity(x)
  x
end

identity(42)       # Generates identity_Integer
identity("hello")  # Generates identity_String
```

The monomorphizer:
1. Finds all call sites for each polymorphic function
2. Collects unique type argument combinations
3. Generates specialized copies with concrete types
4. Replaces call sites with calls to specialized versions

#### 9.6 Flow Type Narrowing

Type narrowing refines variable types within conditional branches.

##### Supported Narrowing Patterns

| Condition | Then-branch | Else-branch |
|-----------|-------------|-------------|
| `if x` | `x` is non-nil | `x` may be nil |
| `if x == nil` | `x` is `NilType` | `x` is non-nil |
| `if x != nil` | `x` is non-nil | `x` may be nil |
| `if x.nil?` | `x` is `NilType` | `x` is non-nil |
| `if a && b` | both `a` and `b` are non-nil | (no narrowing) |
| `case x in Integer` | `x` is `Integer` | (remaining types) |

##### Narrowing Algorithm

Narrowing operates by temporarily rebinding variables in the environment:

```
narrow(Γ, "if x != nil", then):
  original_type = Γ(x)
  narrowed_type = remove_nil(original_type)
  Γ' = Γ[x ↦ narrowed_type]
  return Γ'

remove_nil(Union(Integer, NilType)) = Integer
remove_nil(T) = T    (if T is not a union containing NilType)
```

After branch inference, the original binding is restored.

#### 9.7 Post-Inference Validation

After inference completes, `validate_all_types_resolved!` checks for remaining unbound TypeVars:

```
for each function (name, FunctionType(params, return)):
  for each param type:
    if unresolved_typevar?(apply(param)):
      collect warning
  if unresolved_typevar?(apply(return)):
    collect warning
```

Unresolved TypeVars produce **informational warnings** (not compile errors). The compiler continues and uses dynamic dispatch fallbacks for unresolved paths:
- **LLVM backend:** Falls back to `rb_funcallv` (CRuby generic method call)
- **JVM backend:** Falls back to `invokedynamic` with `RubyDispatch` bootstrap

This means code with unresolved types will still compile and run correctly, but without the performance benefits of static type resolution. The warnings help developers identify opportunities for optimization by adding RBS type annotations.

### 10. Annotations

Konpeito uses RBS annotation syntax `%a{...}` for native code generation directives.

| Annotation | Target | Effect |
|-----------|--------|--------|
| `%a{native}` | class | Treat as native struct (C struct layout) |
| `%a{native: vtable}` | class | Enable vtable dynamic dispatch |
| `%a{extern}` | class | Wrap external C struct pointer |
| `%a{boxed}` | class | Force VALUE representation (CRuby interop) |
| `%a{struct}` | class | Value type (pass-by-value, max 128 bytes) |
| `%a{simd}` | class | SIMD vector type (all Float fields) |
| `%a{ffi: "lib"}` | module/class | Link external library |
| `%a{cfunc}` | method | Direct C function call (method name = C name) |
| `%a{cfunc: "name"}` | method | Direct C function call (explicit C name) |
| `%a{jvm_static}` | method | JVM static method |
| `%a{callback: "iface"}` | method | JVM SAM callback (Block→functional interface) |
| `%a{callback: "iface" descriptor: "desc"}` | method | JVM SAM callback with explicit descriptor |

**Auto-detection:** Classes with `@field: Type` declarations in RBS are automatically treated as native classes. The `%a{native}` annotation is not required.

---

## Part IV: Declarations and Definitions

### 11. Variables

#### 11.1 Local Variables

Local variables are scoped to their enclosing method or block. They require no declaration — first assignment creates the binding.

```ruby
x = 42       # x : Integer
y = x + 1    # y : Integer (inferred from x + 1)
```

Type is inferred from the first assignment and cannot change within a scope (except via flow narrowing).

#### 11.2 Instance Variables

Instance variables are scoped to the object instance. Their types are declared in RBS:

```rbs
class Point
  @x: Float
  @y: Float
end
```

For native classes, instance variables become struct fields with fixed offsets.

#### 11.3 Class Variables

Class variables (`@@var`) are shared across a class hierarchy:

```ruby
class Counter
  @@count = 0
  def self.increment
    @@count = @@count + 1
  end
end
```

LLVM: implemented via `rb_cvar_get`/`rb_cvar_set`.
JVM: implemented as static fields.

#### 11.4 Global Variables

Global variables (`$var`) are process-wide:

```ruby
$debug = false
```

LLVM: implemented via `rb_gv_get`/`rb_gv_set`.

#### 11.5 Constants

Constants are lexically scoped and immutable after first assignment:

```ruby
MAX_SIZE = 100
PI = 3.14159
```

### 12. Methods

#### 12.1 Method Definition

```ruby
def method_name(param1, param2)
  body
end

def method_name = expression    # Endless method (Ruby 3.0+)
```

#### 12.2 Parameter Forms

| Form | Example | Description |
|------|---------|-------------|
| Positional | `def f(a, b)` | Required positional |
| Default | `def f(a, b = 1)` | Optional with default |
| Keyword | `def f(name:)` | Required keyword |
| Keyword default | `def f(name: "")` | Optional keyword |
| Rest | `def f(*args)` | Variable positional |
| Keyword rest | `def f(**kwargs)` | Variable keyword |

#### 12.3 Visibility

```ruby
class Foo
  private

  def secret_method    # private
    # ...
  end

  public

  def public_method    # public
    # ...
  end
end

# Name-based form
class Bar
  def method_a; end
  def method_b; end
  private :method_a
end
```

LLVM: `private` → `rb_define_private_method`, `protected` → `rb_define_protected_method`.
JVM: `private` → method access flags.

#### 12.4 Operator Methods

User-defined classes can define operator methods:

```ruby
class Vector2
  def +(other)     # Addition
    # ...
  end
  def <=>(other)   # Three-way comparison
    # ...
  end
end
```

Supported operators: `+`, `-`, `*`, `/`, `%`, `**`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `<=>`, `<<`, `>>`, `[]`, `[]=`.

Internal name mapping: `+` → `op_plus`, `-` → `op_minus`, etc.

#### 12.5 Alias

```ruby
alias new_name old_name
alias_method :new_name, :old_name
```

### 13. Classes

#### 13.1 Class Definition

```ruby
class ClassName < SuperClass
  # body
end
```

#### 13.2 Native Class Auto-Detection

A class is automatically treated as a native class when its RBS definition includes instance variable declarations:

```rbs
class Point
  @x: Float      # Triggers native class treatment
  @y: Float
end
```

No `%a{native}` annotation required.

#### 13.3 Value Type (@struct)

Classes annotated with `%a{struct}` are pass-by-value:

```rbs
# @struct
class Color
  @r: Integer
  @g: Integer
  @b: Integer
end
```

Constraints:
- No VALUE fields (String, Array, Hash, Object)
- Maximum 128 bytes
- No superclass

#### 13.4 Open Classes

Existing classes can be reopened to add methods:

```ruby
class String
  def shout
    self + "!"
  end
end
```

Ruby core classes are accessed via `rb_const_get`; user classes merge method definitions.

### 14. Modules

#### 14.1 Module Definition

```ruby
module MyModule
  def self.class_method
    # ...
  end

  def instance_method
    # ...
  end
end
```

#### 14.2 Mixin

```ruby
class MyClass
  include MyModule    # Instance methods
  extend MyModule     # Class methods
  prepend MyModule    # Method chain (called before own methods)
end
```

LLVM: `rb_include_module`, `rb_extend_object`, `rb_prepend_module`.
JVM: `module` → Java interface, `include` → `implements`.

---

## Part V: Expressions and Statements

### 15. Literals

See Section 5.1 for the complete literal syntax. Type inference rules for literals are given in Section 9.1.

### 16. Operators

#### 16.1 Arithmetic Operators

When both operands have known numeric types, arithmetic operators generate unboxed native instructions.

**LLVM backend:**

```ruby
a + b    # If a : Integer, b : Integer → i64 add (fully unboxed)
a * b    # If a : Float, b : Float → double fmul (fully unboxed)
```

Falls back to `rb_funcallv` when types are unknown.

**JVM backend:**

On JVM, the level of unboxed arithmetic depends on conditions:

| Condition | Method Signature | Arithmetic Instruction | Overhead |
|-----------|-----------------|----------------------|----------|
| RBS type annotation | `(JJ)J` (primitive) | `ladd` direct | None |
| HM inference + monomorphized copy | `(JJ)J` (primitive) | `ladd` direct | None |
| HM inference (generic method) | `(Object,Object)Object` | `checkcast Long` → `longValue()` → `ladd` → `Long.valueOf()` | boxing/unboxing |
| Type unknown | `(Object,Object)Object` | `invokedynamic` | Runtime dispatch |

Supported unboxed operators:
- **Integer:** `+`, `-`, `*`, `/`, `%`, `<<`, `>>`, `&`, `|`, `^`
- **Float:** `+`, `-`, `*`, `/`

#### 16.2 Comparison Operators

All comparison operators return `Bool`:

```ruby
a == b    # Returns Bool
a < b     # Returns Bool
a <=> b   # Returns Integer (-1, 0, 1)
```

#### 16.3 Logical Operators (Short-Circuit)

```ruby
a && b    # Evaluates b only if a is truthy; returns a or b
a || b    # Evaluates b only if a is falsy; returns a or b
!a        # Logical negation; returns Bool
```

Implementation: Branch + Jump + Phi (no new HIR nodes).

#### 16.4 Safe Navigation Operator

```ruby
obj&.method    # Returns nil if obj is nil, otherwise calls method
a&.b&.c        # Chaining supported
```

Implementation: nil check → branch → phi (nil or method result).

#### 16.5 Compound Assignment

```ruby
x += 1       # x = x + 1
x ||= 42     # x = x || 42 (short-circuit)
x &&= val    # x = x && val (short-circuit)
@x += 1      # Instance variable
@@x += 1     # Class variable
```

### 17. Control Flow

#### 17.1 Conditional (if/unless)

```ruby
if condition
  then_body
elsif condition2
  body2
else
  else_body
end

unless condition
  body
end
```

Type of if/unless expression:
- **Expression position:** Unify then and else branch types
- **Statement position:** NilType (branch types may differ)

#### 17.2 Loops (while/until)

```ruby
while condition
  body
end

until condition    # Equivalent to while !condition
  body
end
```

Loop body is always in statement position. `break` exits the loop; `next` skips to the next iteration.

#### 17.3 Case/When (Value Matching)

```ruby
case expr
when value1 then body1
when value2 then body2
else default_body
end
```

Matching uses `===` operator. Optimizations (LLVM backend only):
- **Integer when-values:** Inlined Fixnum check + value comparison
- **String when-values:** Direct `rb_str_equal` call
- **Class/Module when-values:** Direct `rb_obj_is_kind_of` call

JVM backend uses `Object.equals()` for comparison.

### 18. Pattern Matching (case/in)

```ruby
case expr
in pattern then body
in pattern if guard then body
else default_body
end
```

#### 18.1 Pattern Types

| Pattern | Example | LLVM | JVM |
|---------|---------|------|-----|
| Literal | `in 42` | ✅ | ✅ |
| Type/Constant | `in Integer` | ✅ | ✅ (Integer/Float/String only) |
| Variable | `in x` | ✅ | ✅ |
| Alternation | `in 1 \| 2 \| 3` | ✅ | ✅ |
| Array | `in [a, b]` | ✅ | ✅ (`KArray` deconstruction) |
| Hash | `in {x:, y:}` | ✅ | ✅ (`KHash` key lookup) |
| Rest | `in [first, *rest]` | ✅ | ✅ (`KArray` sub-range) |
| Capture | `in Integer => n` | ✅ | ✅ (variable binding) |
| Pin | `in ^var` | ✅ | ✅ (value comparison) |
| Guard | `in n if n > 0` | ✅ | ✅ |

#### 18.2 Known Limitations

1. Mixing array and hash patterns in the same `case` may cause issues with `deconstruct`/`deconstruct_keys` ordering (LLVM)
2. Branches returning mixed boxed/unboxed types require phi node unification

### 19. Exception Handling

```ruby
begin
  risky_code
rescue TypeError => e
  handle_type_error(e)
rescue StandardError
  handle_standard
else
  no_exception_body
ensure
  always_runs
end

raise "error message"
raise TypeError, "message"
```

LLVM implementation:
- `rb_rescue2` for rescue clauses
- `rb_ensure` for ensure blocks
- Global i32 flag for else clause detection

JVM implementation:
- Native try/catch/finally bytecode

### 20. Blocks, Proc, and Lambda

```ruby
# Block with explicit params
[1, 2, 3].map { |x| x * 2 }

# Numbered parameters (Ruby 2.7+)
[1, 2, 3].map { _1 * 2 }

# it parameter (Ruby 3.4+)
[1, 2, 3].map { it * 2 }

# Lambda
square = ->(x) { x * x }
square.call(5)

# yield
def with_value(x)
  yield x if block_given?
end
```

#### 20.1 Inlined Iterators

The following methods are inlined as native loops when type information is available:

**LLVM backend:**

| Method | Inlined As |
|--------|-----------|
| `Array#each`, `map`, `select`, `reject`, `reduce` | Indexed loop over array |
| `Array#find`, `any?`, `all?`, `none?` | Early-exit loop |
| `Integer#times` | Counter loop (i64) |
| `Range#each`, `map`, `select`, `reduce` | Counter loop (i64) |

**JVM backend:**

| Method | Inlined As |
|--------|-----------|
| `Array#each`, `map`, `select`, `reject`, `reduce` | Indexed loop (`KArray.get()`) |
| `Array#find`, `any?`, `all?`, `none?` | Early-exit loop |
| `Integer#times` | Counter loop (long) |
| `Hash#each` | Iterator loop (`KHash.keys()`) |
| `Range#each`, `map`, `select`, `reduce` | Counter loop (long) |

### 21. Concurrency

#### 21.1 Fiber (LLVM Only)

Fiber is implemented only in the LLVM backend, using CRuby's native fiber API (`rb_fiber_*`).

```ruby
# Fiber (cooperative concurrency) — LLVM backend only
fiber = Fiber.new { |x| Fiber.yield(x * 2) }
result = fiber.resume(21)    # 42
```

**Not available on JVM.** Use Thread with Virtual Threads instead.

#### 21.2 Thread, Mutex, ConditionVariable, SizedQueue (Both Backends)

```ruby
# Thread
thread = Thread.new { expensive_computation }
result = thread.value

# Mutex
mutex = Mutex.new
mutex.synchronize { shared_state_update }

# ConditionVariable
cv = ConditionVariable.new
cv.wait(mutex)
cv.signal

# SizedQueue
queue = SizedQueue.new(10)
queue.push(item)
item = queue.pop
```

| Primitive | LLVM (CRuby API) | JVM (Java 21) |
|-----------|-----------------|----------------|
| Thread | `rb_thread_create` (GVL-limited) | Virtual Threads (true parallelism) |
| Mutex | `rb_mutex_*` | `ReentrantLock` |
| ConditionVariable | `rb_condvar_*` | `Condition` |
| SizedQueue | `rb_szqueue_*` | `ArrayBlockingQueue` |

#### 21.3 Ractor (JVM Only)

Ractor is implemented only in the JVM backend, using Java 21 Virtual Threads.

```ruby
ractor = Ractor.new { Ractor.receive * 2 }
ractor.send(21)
result = ractor.value    # 42
```

Supported operations:
- `Ractor.new { ... }` — create new Ractor
- `ractor.send(msg)` / `ractor << msg` — send message
- `Ractor.receive` — receive message
- `ractor.join` / `ractor.value` — wait for completion
- `ractor.close` / `ractor.name` — lifecycle management
- `Ractor.current` / `Ractor.main` — Ractor references
- `Ractor.make_shareable(obj)` / `Ractor.shareable?(obj)` — shareability
- `Ractor[:key]` / `Ractor[:key]=` — Ractor-local storage
- `Ractor::Port` — Port-based communication
- `Ractor.select` — multi-Ractor waiting
- `ractor.monitor` / `ractor.unmonitor` — monitoring

**Limitations:**
- **No isolation enforcement:** On JVM, objects are shared by reference. `Ractor.make_shareable(obj)` is a no-op (returns the object as-is) and `Ractor.shareable?(obj)` always returns `true`. There is no deep copy or freeze enforcement on `send`.
- **Not available on LLVM backend.**

---

## Part VI: Compilation Model

### 22. Compilation Pipeline

```
Source (.rb) + Types (.rbs)
       │              │
       ▼              ▼
  ┌─────────┐   ┌────────────┐
  │  Prism   │   │ RBS::Parser│
  └────┬─────┘   └─────┬──────┘
       │               │
       ▼               ▼
  ┌────────────────────────┐
  │   HM Type Inferrer     │
  │ (Algorithm W + RBS)    │
  └───────────┬────────────┘
              │
              ▼
  ┌────────────────────────┐
  │     Typed AST          │
  └───────────┬────────────┘
              │
              ▼
  ┌────────────────────────┐
  │     HIR Generator      │
  │   (High-level IR)      │
  └───────────┬────────────┘
              │
              ▼
  ┌────────────────────────┐
  │     Optimizations      │
  │  (Inline, LICM, Mono)  │
  └───────────┬────────────┘
              │
       ┌──────┴──────┐
       ▼             ▼
  ┌─────────┐   ┌──────────┐
  │  LLVM   │   │   JVM    │
  │Generator│   │Generator │
  └────┬────┘   └────┬─────┘
       │              │
       ▼              ▼
  ┌─────────┐   ┌──────────┐
  │ .so/.dll│   │   .jar   │
  └─────────┘   └──────────┘
```

### 23. HIR Specification

The High-level Intermediate Representation (HIR) is a graph of basic blocks containing typed instructions.

#### 23.1 Instruction Categories

| Category | Examples |
|----------|---------|
| **Literals** | IntLit, FloatLit, StringLit, SymbolLit, ArrayLit, HashLit, RangeLit, RegexpLit |
| **Variables** | LoadLocal, StoreLocal, LoadInstanceVar, StoreInstanceVar, LoadClassVar, StoreClassVar, LoadGlobalVar, StoreGlobalVar, LoadConstant, StoreConstant |
| **Control** | Branch, Jump, Phi, Return, CaseWhen, CaseMatchStatement |
| **Calls** | MethodCall, BlockCall, YieldCall, SuperCall |
| **Native** | NativeNew, NativeMethodCall, NativeFieldGet, NativeFieldSet, NativeArrayNew, NativeArrayGet, NativeArraySet |
| **Arithmetic** | BinaryOp (unboxed +, -, *, /, etc.) |
| **Type** | Box, Unbox, Checkcast |

#### 23.2 SSA Properties

HIR uses a modified SSA (Static Single Assignment) form:
- Variables are represented as `alloca` + `load`/`store` pairs
- LLVM's `mem2reg` pass converts to true SSA
- Phi nodes are used for control flow merges (if/else, loops)

### 24. Optimization Guarantees

#### 24.1 Optimization Guarantees

| Optimization | LLVM | JVM | Notes |
|-------------|------|-----|-------|
| **Unboxed arithmetic** | ✅ Full | ✅ Conditional | JVM: Fully unboxed only with RBS or monomorphized copies |
| **Inline iterators (Array)** | ✅ | ✅ | Both backends |
| **Inline iterators (Range)** | ✅ | ✅ | Both backends inline as counter loop |
| **Numeric method inlining** | ✅ | ✅ | `abs`, `even?`, `odd?` etc. → CPU instructions |
| **`===` inlining** | ✅ | ❌ | LLVM only; JVM uses `Object.equals()` |
| **Monomorphization** | ✅ | ✅ | Both backends |

#### 24.2 LLVM-Specific Optimizations

| Optimization | Current Behavior |
|-------------|-----------------|
| Method inlining | Methods with ≤10 instructions, depth ≤3 |
| LICM | Pure methods (`.length`, `.size`, etc.) hoisted from loops |
| LLVM O2 | GVN, SROA, instcombine applied to LLVM IR |
| Range inlining | `(1..n).each` → native i64 counter loop |
| `===` inlining | Integer: Fixnum check, String: `rb_str_equal`, Class: `rb_obj_is_kind_of` |

---

## Part VII: Backend-Specific Semantics

### 25. LLVM/CRuby Backend

#### 25.1 Output Format

Generates CRuby C extensions (`.so` on Linux, `.bundle` on macOS, `.dll` on Windows).

#### 25.2 Memory Layout

- Unboxed values: native `i64`, `double`, `i8`
- Boxed values: CRuby `VALUE` (tagged pointer, 64-bit)
- NativeClass: C struct allocated via `rb_data_typed_s_new`
- NativeArray: `alloca` (stack) or `xmalloc` (heap)

#### 25.3 Boxing Rules

Values are boxed when crossing the native/CRuby boundary:
- `Integer` (i64) → `rb_int2inum(value)`
- `Float` (double) → `rb_float_new(value)`
- `Bool` (i8) → `Qtrue` (6) / `Qfalse` (0)
- `Nil` → `Qnil` (4)

Values are unboxed when entering native code:
- VALUE → `rb_num2long(value)` (Integer)
- VALUE → `rb_float_value(value)` (Float)

#### 25.4 C API Integration

Methods are registered via `rb_define_method` in the `Init_` function. Classes use `rb_define_class`. Constants use `rb_const_set`.

### 26. JVM Backend

#### 26.1 Output Format

Generates standalone JAR files containing Java bytecode (`.class` files).

#### 26.2 Type Mapping

| Konpeito | JVM | Notes |
|---------|-----|-------|
| Integer | `long` / `java.lang.Long` | Primitive `long`; boxed as `Long` |
| Float | `double` / `java.lang.Double` | Same as above |
| Bool | `boolean` / `java.lang.Boolean` | i8 ↔ boolean |
| String | `java.lang.String` | |
| Array | `konpeito.runtime.KArray` | Ruby-compatible array |
| Hash | `konpeito.runtime.KHash` | Ruby-compatible hash |
| Block | `konpeito.runtime.KBlock` | Block/lambda |
| User class | `konpeito/generated/ClassName` | See below |

#### 26.3 User-Defined Class Mapping

User-defined Ruby classes are compiled to Java classes under the `konpeito/generated/` package.

```ruby
class Person
  def initialize(name, age)
    @name = name
    @age = age
  end
  def greet
    @name
  end
end
```

Generated JVM class:

```
Class: konpeito/generated/Person
  extends: java/lang/Object

  Fields:
    public name : Ljava/lang/String;
    public age  : J (long)

  Methods:
    public <init>()V                          # No-arg constructor
    public <init>(Ljava/lang/String;J)V       # Parameterized constructor
    public greet()Ljava/lang/Object;          # Instance method
```

**Three-level method dispatch:**

| Resolution Level | Generated Bytecode | Condition |
|-----------------|-------------------|-----------|
| Fully resolved | `invokevirtual konpeito/generated/Person/greet` | Type determined by HM inference |
| Fields only | `getfield`/`putfield` direct access | Method undefined but fields known |
| Unresolved | `invokedynamic` (RubyDispatch bootstrap) | Type unknown → runtime resolution |

**Method name mapping:**

| Ruby | JVM |
|------|-----|
| `greet` | `greet` |
| `name=` | `name_eq` |
| `even?` | `even_q` |
| `+` | `op_plus` |
| `[]` | `op_aref` |
| `[]=` | `op_aset` |

**Inheritance:** `class Dog < Animal` → `konpeito/generated/Dog extends konpeito/generated/Animal`
**Modules:** `module Walkable` → `konpeito/generated/Walkable` (Java interface with default methods)

#### 26.4 Java Interop

Java classes are accessed via the `Java::` module convention:

```ruby
frame = Java::JWM::Window.new
```

RBS-free Java interop is available with AST pre-scanning and automatic type extraction.

#### 26.5 Virtual Threads (Java 21)

`Thread.new` maps to Java 21 Virtual Threads for lightweight concurrency.

#### 26.6 Fiber (Not Available)

Fiber is not implemented in the JVM backend. CRuby's Fiber API (`rb_fiber_*`) has no direct JVM equivalent. Use Thread with Virtual Threads instead.

### 27. Backend Differences

| Feature | LLVM | JVM |
|---------|------|-----|
| Integer overflow | Wraps (i64) | Wraps (long) |
| String interning | No (CRuby manages) | JVM string pool |
| GC | CRuby GC (mark & sweep) | JVM GC (G1/ZGC) |
| Fiber | CRuby API (`rb_fiber_*`) | **Not implemented** |
| Thread/Mutex | CRuby API (GVL-limited) | Virtual Threads (true parallelism) |
| Unresolved type fallback | `rb_funcallv` | `invokedynamic` (RubyDispatch) |
| User classes | CRuby extension (`rb_define_class`) | Java class (`konpeito/generated/`) |
| C interop | Direct (`@cfunc`/`@ffi`) | JNI required |
| Java interop | N/A | Direct (classpath) |
| Ractor | N/A | Virtual Threads (JVM only) |
| SIMD | LLVM vector types | N/A |
| Debug info | DWARF | N/A |
| `Integer#times` inlining | Native i64 loop | Counter loop (long) |
| NativeArray | Stack/heap array | JVM primitive array (`long[]`, `double[]`) |
| @cfunc stdlib | Available (libcurl, OpenSSL, zlib) | **Not implemented** |

---

## Part VIII: Standard Library

### 28. Built-in Type Methods

#### 28.1 Integer

| Method | Return Type | Inlined |
|--------|------------|---------|
| `+`, `-`, `*`, `/`, `%` | Integer | Unboxed i64 ops |
| `<<`, `>>`, `&`, `\|`, `^` | Integer | Unboxed i64 ops |
| `abs` | Integer | `select` + `sub` |
| `even?`, `odd?` | Bool | `and` + `icmp` |
| `zero?`, `positive?`, `negative?` | Bool | `icmp` |
| `to_s` | String | `rb_funcallv` |
| `to_f` | Float | `sitofp` |
| `times { \|i\| ... }` | nil | Native counter loop |

#### 28.2 Float

| Method | Return Type | Inlined |
|--------|------------|---------|
| `+`, `-`, `*`, `/` | Float | Unboxed double ops |
| `abs` | Float | `fcmp` + `fsub` + `select` |
| `zero?`, `positive?`, `negative?` | Bool | `fcmp` |
| `to_i` | Integer | `fptosi` |

#### 28.3 String

Available methods: `length`, `size`, `+` (concatenation), `*` (repetition), `[]`, `upcase`, `downcase`, `capitalize`, `strip`, `lstrip`, `rstrip`, `chomp`, `chop`, `squeeze`, `tr`, `delete`, `split`, `chars`, `bytes`, `include?`, `start_with?`, `end_with?`, `gsub`, `sub`, `to_i`, `to_f`, `empty?`, `reverse`, `encode`, `freeze`, `dup`, `clone`, `index`, `rindex`, `ord`, `scan`, `match`, `match?`, `ascii_only?`.

#### 28.4 Array

Available methods: `length`, `size`, `[]`, `[]=`, `push`, `<<`, `pop`, `shift`, `unshift`, `prepend`, `append`, `first`, `last`, `delete_at`, `each`, `map`/`collect`, `select`/`filter`, `reject`, `reduce`/`inject`, `find`/`detect`, `any?`, `all?`, `none?`, `one?`, `count`, `min`, `max`, `min_by`, `max_by`, `sort_by`, `find_index`, `sample`, `rotate`, `shuffle`, `take_while`, `drop_while`, `partition`, `group_by`, `flat_map`/`collect_concat`, `sum`, `empty?`, `include?`, `join`, `reverse`, `sort`, `uniq`, `flatten`, `compact`.

#### 28.5 Hash

Available methods: `[]`, `[]=`, `size`, `length`, `keys`, `values`, `has_key?`/`key?`/`include?`, `has_value?`/`value?`, `delete`, `each`, `map`, `select`, `reject`, `any?`, `all?`, `none?`, `merge`, `empty?`, `to_a`.

#### 28.6 Symbol

Available methods: `to_s`, `id2name`, `name`.

### 29. Native Data Structure Library

See Section 8.4 for type definitions.

### 30. @cfunc Standard Library

| Module | Backend | Functions |
|--------|---------|-----------|
| `KonpeitoJSON` | yyjson | `parse`, `generate`, `parse_array_as` |
| `KonpeitoHTTP` | libcurl | `get`, `post`, `get_response`, `request` |
| `KonpeitoCrypto` | OpenSSL | `sha256`, `sha512`, `hmac_sha256`, `random_bytes`, `secure_compare` |
| `KonpeitoCompression` | zlib | `gzip`, `gunzip`, `deflate`, `inflate`, `zlib_compress`, `zlib_decompress` |

---

## Appendices

### Appendix A: Type Tag Reference

| Tag | Type | LLVM | JVM | Size |
|-----|------|------|-----|------|
| `:i64` | Integer | `i64` | `long` | 8 bytes |
| `:double` | Float | `double` | `double` | 8 bytes |
| `:i8` | Bool | `i8` | `boolean` | 1 byte |
| `:value` | VALUE (boxed) | `i64` | `Object` | 8 bytes |
| `:native_class` | NativeClass | `struct*` | class ref | 8 bytes |
| `:value_struct` | @struct | `{...}` | class ref | varies |
| `:native_hash` | NativeHash | `{ptr, i64, i64}` | N/A | 24 bytes |

### Appendix B: Annotation Quick Reference

```rbs
# Native struct (auto-detected from field declarations)
class Point
  @x: Float
  @y: Float
end

# Value type (pass-by-value, stack-allocated)
# @struct
class Color
  @r: Integer
  @g: Integer
  @b: Integer
end

# SIMD vector
%a{simd}
class Vector4
  @x: Float
  @y: Float
  @z: Float
  @w: Float
end

# External C library
%a{ffi: "libm"}
module MathLib
  %a{cfunc}
  def self.sin: (Float) -> Float

  %a{cfunc: "sqrt"}
  def self.square_root: (Float) -> Float
end

# External C struct wrapper
%a{ffi: "libsqlite3"}
%a{extern}
class SQLiteDB
  def self.open: (String path) -> SQLiteDB
  def close: () -> void
end

# Boxed (CRuby VALUE interop)
%a{boxed}
class LegacyWrapper
  # Uses rb_define_class instead of native struct
end
```

### Appendix C: Known Limitations

**Type Resolution:**
1. **Unresolved type fallback:** When types cannot be fully resolved, compilation does not error. Instead, dynamic dispatch (`rb_funcallv` on LLVM, `invokedynamic` on JVM) is used. Warnings are emitted but compilation continues
2. **TypeVar fallback:** TypeVars remaining after inference are reported as informational warnings (not compile errors)

**Numeric:**
3. **Integer overflow:** No automatic Bignum promotion; wraps at i64/long bounds

**Pattern Matching:**
4. **Mixed patterns (LLVM):** Mixing array and hash patterns in the same `case` may cause issues with `deconstruct`/`deconstruct_keys` ordering
5. **Phi node type mixing:** If/else branches returning different unboxed types require careful handling

**JVM Backend:**
6. **Fiber (JVM):** Not implemented on JVM backend. Use Virtual Threads instead
7. **@cfunc stdlib (JVM):** JSON/HTTP/Crypto/Compression C library integration is LLVM backend only
8. **SIMD (JVM):** SIMD vectorization is LLVM backend only
9. **`===` inlining (JVM):** case/when `===` optimization not implemented (uses `Object.equals()`)
10. **Unboxed arithmetic (JVM):** Generic method signatures use `Object→Object`, incurring boxing/unboxing overhead. Fully unboxed only with RBS type annotations or monomorphized copies

**LLVM Backend:**
11. **GVL limitation (LLVM):** CRuby's GVL prevents true thread parallelism
12. **Mutex.synchronize exception safety:** Uses `rb_ensure` for proper cleanup (LLVM only)

**Native Types:**
13. **NativeString performance:** Currently slower than Ruby String due to conversion overhead
14. **SIMD field count:** Must be 2, 3, 4, 8, or 16 (all Float)
15. **Value type constraints:** @struct cannot have VALUE fields or exceed 128 bytes

**Ractor:**
16. **Ractor (LLVM):** Not implemented on LLVM backend
17. **Ractor isolation (JVM):** No isolation enforcement — objects are shared by reference, not copied or frozen. `make_shareable`/`shareable?` are compatibility stubs

### Appendix D: Glossary

| Term | Definition |
|------|-----------|
| **AOT** | Ahead-of-Time compilation — compiles before execution |
| **Algorithm W** | The classic Hindley-Milner type inference algorithm |
| **Boxing** | Wrapping a native value in CRuby's tagged VALUE pointer |
| **CRuby** | The reference implementation of Ruby (MRI) |
| **GVL** | Global VM Lock — CRuby's thread synchronization mechanism |
| **HIR** | High-level Intermediate Representation |
| **HM** | Hindley-Milner type system |
| **JIT** | Just-In-Time compilation |
| **LUB** | Least Upper Bound — most specific common ancestor type |
| **Monomorphization** | Specializing generic code for specific type arguments |
| **Prism** | Ruby 4.0's built-in parser |
| **RBS** | Ruby type signature format |
| **SSA** | Static Single Assignment form |
| **Unboxing** | Extracting a native value from a CRuby VALUE |
| **VALUE** | CRuby's universal tagged pointer type (64-bit) |
| **YJIT** | Yet Another JIT — CRuby's built-in JIT compiler |
