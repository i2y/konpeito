# Konpeito JVM Backend Architecture Guide

The Konpeito JVM backend compiles Ruby code into JVM bytecode and outputs `.jar` files.
It shares the same frontend (Prism parser, HM type inference, HIR) with the existing LLVM/CRuby backend,
while leveraging the JVM ecosystem's runtime performance and library assets.

---

## Table of Contents

1. [Vision](#vision)
2. [Design Philosophy of the Two Backends](#design-philosophy-of-the-two-backends)
3. [Architecture Overview](#architecture-overview)
4. [Compilation Pipeline](#compilation-pipeline)
5. [JVM Generator](#jvm-generator)
6. [ASM Wrapper Tool](#asm-wrapper-tool)
7. [JVM Backend](#jvm-backend)
8. [Type Mapping](#type-mapping)
9. [Phi Node Elimination](#phi-node-elimination)
10. [Usage](#usage)
11. [Implemented Features](#implemented-features)
12. [Roadmap](#roadmap)
13. [Differentiation from Kotlin](#differentiation-from-kotlin)
14. [Castella UI Framework](#castella-ui-framework)

---

## Vision

**"Ruby's writing comfort + JVM's runtime performance and ecosystem"**

Differentiation from Kotlin:

| Feature | Kotlin | Konpeito/JVM |
|---------|--------|-------------|
| Type inference | Local inference | HM global type inference |
| DSL construction | Lambda + extension functions | Ruby block syntax |
| Type definitions | Inline (mixed with source) | RBS separated type definitions (gradual typing) |
| Pattern matching | when expression (limited) | case/in (comprehensive) |
| Learning curve | Aimed at Java developers | Ruby developers can use as-is |

---

## Design Philosophy of the Two Backends

Konpeito branches from the same frontend (Prism parser, HM type inference, HIR) into two backends.
Their **purposes are fundamentally different**, so the way type information is used and the relationship with the runtime also differ significantly.

### LLVM Backend -- CRuby Extension Modules

**Purpose:** Generate extension modules (`.so` / `.bundle`) that accelerate hot paths in existing CRuby applications.

```
Ruby app --- require "my_ext" --> CRuby extension (.so)
    |                                    |
    +-- CRuby VM (GC, object model) -----+
```

**Constraints:**
- Must coexist with CRuby's GC (notify object references via `rb_gc_mark`)
- Must maintain consistency with VALUE passed from the Ruby side
- `rb_ivar_get` / `rb_ivar_set` is the standard instance variable access

**How type inference is used:**
- Only classes with **explicitly declared** field types in RBS are converted to NativeClassType (custom structs)
- Classes without declarations remain as boxed VALUE (safe but slow)
- The user guarantees that "this class is safe to nativize"

```rbs
# RBS field declaration -> NativeClass (custom struct + GC mark function)
class Point
  @x: Float    # <- This is required
  @y: Float
end
```

**Rationale:** If a class were automatically converted to a struct, the GC could lose track of VALUE inside fields,
or memory layout could become inconsistent with objects passed from the Ruby side.
Safety cannot be guaranteed without explicit declarations.

### JVM Backend -- Standalone Execution

**Purpose:** Compile Ruby code into standalone JVM applications (`.jar`).

```
konpeito build --target jvm --> .jar --> java -jar app.jar
                                          |
                                          +-- JVM (GC, JIT, ecosystem)
```

**Flexibility:**
- No integration with CRuby needed -- your class definitions are everything
- JVM's GC automatically manages all objects
- Whether a field type is `long` or `Object` is purely a performance concern; getting it wrong won't break the GC

**How type inference is used:**
- HM type inference results can be **directly** reflected in field types
- Even without RBS field declarations, `@count = 42` is inferred as a `long` field
- Type propagation from call sites works naturally

```ruby
# Works without RBS field declarations
class Counter
  def count; @count; end
  def set_count(v); @count = v; end
end
c = Counter.new
c.set_count(42)   # <- @count: Integer (long) is inferred from here
```

### Comparison Table

| Aspect | LLVM / CRuby Extension | JVM / Standalone |
|--------|------------------------|------------------|
| **Purpose** | Accelerate hot paths in existing Ruby apps | Standalone JVM application |
| **Runtime** | CRuby VM (shared GC and object model) | JVM (independent execution environment) |
| **GC** | Must coexist with CRuby GC | Delegated to JVM GC |
| **ivar type inference** | RBS field declarations required (for safety) | Works with HM inference alone |
| **Struct conversion condition** | Explicitly guaranteed by user | Inference results used directly |
| **Type errors** | Risk of GC corruption / SEGV | Only performance degradation |
| **Output format** | `.so` / `.bundle` | `.jar` |

This difference directly affects "how far type information can be automatically leveraged."
The JVM backend can aggressively use type inference results, while the LLVM backend
requires a cautious approach for safe coexistence with CRuby.

---

## Architecture Overview

```
Ruby source code (.rb) + type definitions (.rbs)
        |                |
        v                v
   +---------+    +------------+
   |  Prism  |    | RBS::Parser|    <- Existing (shared with LLVM)
   +----+----+    +-----+------+
        |               |
        v               v
   +------------------------+
   |   HM Type Inferrer     |    <- Existing (shared)
   +-----------+------------+
               |
               v
   +------------------------+
   |     HIR Generator      |    <- Existing (shared)
   +-----------+------------+
               |
               v
   +------------------------+
   |   Monomorphizer +      |    <- Existing (shared)
   |   Inliner + LICM       |
   +-----------+------------+
               |
        +------+------+
        v             v
   +---------+   +----------+
   |  LLVM   |   |  JVM     |
   |Generator|   |Generator |    <- New (Ruby)
   +----+----+   +----+-----+
        |             | JSON IR
        v             v
   +---------+   +----------+
   |  CRuby  |   |ASM Wrapper|    <- New (Java, ASM library)
   | Backend |   |Tool       |
   +----+----+   +----+-----+
        |             |
        v             v
   .so/.bundle     .jar
```

**Shared components (backend-independent):**

- `lib/konpeito/parser/prism_adapter.rb` -- Prism parser
- `lib/konpeito/type_checker/hm_inferrer.rb` -- HM type inference
- `lib/konpeito/hir/nodes.rb` + `builder.rb` -- HIR intermediate representation
- `lib/konpeito/codegen/monomorphizer.rb` -- Monomorphization
- `lib/konpeito/codegen/inliner.rb` -- Inlining
- `lib/konpeito/codegen/loop_optimizer.rb` -- Loop optimization (LICM)

**JVM-specific components:**

- `lib/konpeito/codegen/jvm_generator.rb` -- HIR to JVM IR (JSON) conversion
- `lib/konpeito/codegen/jvm_backend.rb` -- Pipeline management (ASM tool invocation + JAR construction)
- `tools/konpeito-asm/` -- ASM wrapper Java tool

---

## Compilation Pipeline

```
1. Parse      Ruby source -> Prism AST
2. Infer      HM type inference + RBS type definitions -> Typed AST
3. Lower      Typed AST -> HIR (basic blocks + SSA)
4. Optimize   Monomorphization -> Inlining -> Loop optimization
5. Generate   HIR -> JVM IR (JSON format)             <- jvm_generator.rb
6. Assemble   JSON IR -> .class files                  <- ASM wrapper tool
7. Package    .class -> .jar (with manifest)           <- jvm_backend.rb
```

Following the same pattern as the LLVM backend calling `opt`/`llc` as external processes,
the ASM wrapper tool is invoked as a Java subprocess.

---

## JVM Generator

**File:** `lib/konpeito/codegen/jvm_generator.rb`

Converts each HIR instruction into a sequence of JVM bytecode instructions (in JSON format).

### Supported HIR Nodes

| HIR Node | JVM Instruction | Description |
|----------|----------------|-------------|
| `IntegerLit` | `ldc2_w` / `lconst_0` / `lconst_1` | Load integer constant |
| `FloatLit` | `ldc2_w` / `dconst_0` / `dconst_1` | Load floating-point constant |
| `BoolLit` | `iconst` | Boolean constant (0/1) |
| `NilLit` | `aconst_null` | null |
| `StringLit` | `ldc` | String constant |
| `LoadLocal` | `lload` / `dload` / `iload` / `aload` | Load local variable |
| `StoreLocal` | `lstore` / `dstore` / `istore` / `astore` | Store local variable |
| `Call (+,-,*,/,%)` | `ladd` / `lsub` / `lmul` / `ldiv` / `lrem` | Integer arithmetic |
| `Call (+,-,*,/)` | `dadd` / `dsub` / `dmul` / `ddiv` | Floating-point arithmetic |
| `Call (<,>,==,...)` | `lcmp` + `ifgt` / `ifeq` / ... | Comparison operations |
| `Call (puts)` | `getstatic System.out` + `invokevirtual println` | Standard output |
| `Call (to_s)` | `Long.toString` / `Double.toString` / ... | Type conversion |
| `Call (user func)` | `invokestatic` | User-defined function call |
| `StringConcat` | `StringBuilder` | String interpolation |
| `Phi` | (store in predecessor block) | SSA to local variable conversion |
| `Branch` | `ifeq` / `lcmp` + `ifeq` / `ifnull` | Conditional branch |
| `Jump` | `goto` | Unconditional jump |
| `Return` | `lreturn` / `dreturn` / `areturn` / `return` | Function return |

### JSON IR Protocol

The interface between Ruby and the ASM tool is JSON format.

```json
{
  "classes": [{
    "name": "konpeito/generated/ExampleMain",
    "access": ["public", "super"],
    "superName": "java/lang/Object",
    "interfaces": [],
    "fields": [],
    "methods": [{
      "name": "add",
      "descriptor": "(JJ)J",
      "access": ["public", "static"],
      "instructions": [
        {"op": "lload", "var": 0},
        {"op": "lload", "var": 2},
        {"op": "ladd"},
        {"op": "lreturn"}
      ]
    }]
  }]
}
```

---

## ASM Wrapper Tool

**Directory:** `tools/konpeito-asm/`

```
tools/konpeito-asm/
├── src/
│   ├── KonpeitoAssembler.java        # Main class (JSON -> .class conversion)
│   ├── ClassIntrospector.java        # Classpath introspection
│   └── konpeito/runtime/
│       ├── KArray.java                # Ruby Array compatible runtime class
│       ├── KHash.java                 # Ruby Hash compatible runtime class
│       ├── RubyDispatch.java          # invokedynamic bootstrap + reflection dispatch
│       ├── KThread.java               # Virtual Threads wrapper
│       ├── KConditionVariable.java    # ConditionVariable (ReentrantLock + Condition)
│       ├── KSizedQueue.java           # SizedQueue (ArrayBlockingQueue wrapper)
│       ├── KJSON.java                 # JSON parser/generator
│       ├── KCrypto.java               # Cryptographic primitives (SHA, HMAC)
│       ├── KCompression.java          # Compression/decompression (gzip/deflate/zlib)
│       ├── KHTTP.java                 # HTTP client (HttpClient)
│       ├── KTime.java                 # Time operations (java.time)
│       ├── KFile.java                 # File I/O (java.nio.file)
│       └── KMath.java                 # Math functions (Math)
├── runtime-classes/                   # Pre-compiled .class files (14 classes)
│   └── konpeito/runtime/
│       ├── KArray.class
│       ├── KHash.class
│       ├── RubyDispatch.class
│       └── ... (KThread, KJSON, KCrypto, etc.)
├── lib/
│   └── asm-9.7.1.jar                 # ASM bytecode library
├── build.sh                           # Build script
└── konpeito-asm.jar                   # Build artifact (fat JAR, in .gitignore)
```

**Features:**

- Reads JSON IR from standard input and outputs `.class` files to a specified directory
- Uses ASM 9.7.1's `ClassWriter.COMPUTE_FRAMES | COMPUTE_MAXS` for automatic `StackMapTable` computation
- Built-in JSON parser (no external dependencies)
- Supported instructions: load/store, arithmetic, constants, branches, labels, method calls, field access, type checking, array operations, `invokedynamic`, exception table
- `--introspect` mode: outputs method signatures from the classpath as JSON

**Build:**

```bash
cd tools/konpeito-asm && bash build.sh
```

Auto-built on first compilation, so manual building is usually unnecessary.

---

## JVM Backend

**File:** `lib/konpeito/codegen/jvm_backend.rb`

An orchestrator that manages the entire pipeline.

```
1. ensure_asm_tool!     -> Auto-build ASM tool if not yet built
2. jvm_generator.to_json -> Generate JSON IR
3. run_asm_tool          -> Pipe to java -jar konpeito-asm.jar
4. create_jar            -> Package with jar cfm into .jar
5. run_jar (optional)    -> Execute with java -jar
```

---

## Type Mapping

### Konpeito to JVM Type Mapping

| Konpeito Type | JVM Type | Descriptor | Slot Count |
|---------------|----------|-----------|------------|
| Integer (`:i64`) | `long` | `J` | 2 |
| Float (`:double`) | `double` | `D` | 2 |
| Bool (`:i8`) | `boolean` / `int` | `Z` | 1 |
| String (`:value`) | `java.lang.String` | `Ljava/lang/String;` | 1 |
| nil (`:void`) | `void` / `null` | `V` | 0 |
| Object (`:value`) | `java.lang.Object` | `Ljava/lang/Object;` | 1 |
| Array (`:array`) | `konpeito.runtime.KArray` | `Lkonpeito/runtime/KArray;` | 1 |
| Hash (`:hash`) | `konpeito.runtime.KHash` | `Lkonpeito/runtime/KHash;` | 1 |
| Symbol | `java.lang.String` | `Ljava/lang/String;` | 1 |

### Boxing/Unboxing

| Ruby Type | Unboxed | Boxed |
|-----------|---------|-------|
| Integer | `long` | `Long.valueOf()` |
| Float | `double` | `Double.valueOf()` |
| Bool | `boolean` | `Boolean.valueOf()` |

Unboxed types are preferred, with automatic boxing/unboxing at collection storage and block boundaries.
`convert_object_return_to_primitive` automatically converts `areturn` to `checkcast` + `longValue()`/`doubleValue()` + `lreturn`/`dreturn` when the method return type is `:i64`/`:double`.

---

## Phi Node Elimination

Since the JVM has no hardware-level Phi nodes, SSA Phi nodes are converted to local variable assignments.

**Method: Store-Before-Jump**

```
HIR:
  block_then: ... -> Jump(merge)
  block_else: ... -> Jump(merge)
  block_merge: result = Phi(then: val_a, else: val_b) -> Return(result)

JVM:
  block_then:
    ... compute val_a ...
    lstore <phi_slot>          <- Write to the Phi result slot
    goto merge
  block_else:
    ... compute val_b ...
    lstore <phi_slot>          <- Write to the same slot
    goto merge
  block_merge:
    lload <phi_slot>           <- Read from the same slot regardless of which path was taken
    lreturn
```

**Implementation:**

1. `generate_function` pre-scans all Phi nodes and allocates slots
2. `generate_jump` / `generate_branch` stores the corresponding incoming value to the slot when the jump target block has a Phi
3. `generate_phi` itself emits nothing (the slot has already been written)

---

## Usage

### Basic Usage

```bash
# Compile to JAR
konpeito build --target jvm source.rb

# Compile + run
konpeito build --target jvm --run source.rb

# With RBS type definitions
konpeito build --target jvm --rbs types.rbs -o app.jar source.rb

# Output JSON IR (for debugging)
konpeito build --target jvm --emit-ir source.rb
```

### Sample Code

```ruby
# examples/jvm_hello.rb
def add(a, b)
  a + b
end

puts add(3, 5)
```

```rbs
# examples/jvm_hello.rbs
module TopLevel
  def add: (Integer a, Integer b) -> Integer
end
```

```bash
$ konpeito build --target jvm --run examples/jvm_hello.rb
8
```

### Working Program Examples

**Fibonacci sequence:**

```ruby
def fib(n)
  a = 0
  b = 1
  i = 0
  while i < n
    temp = b
    b = a + b
    a = temp
    i = i + 1
  end
  a
end

puts fib(10)  # => 55
```

**Greatest common divisor:**

```ruby
def gcd(a, b)
  while b != 0
    temp = b
    b = a % b
    a = temp
  end
  a
end

puts gcd(48, 18)  # => 6
```

**String interpolation:**

```ruby
def describe(n)
  "The number is #{n}"
end

puts describe(42)  # => The number is 42
```

---

## Implemented Features

### Foundation -- Integer Arithmetic

- ASM wrapper tool (JSON to .class conversion)
- `jvm_generator.rb`: HIR to JVM IR conversion
- `jvm_backend.rb`: Pipeline management
- Integer/floating-point arithmetic (+, -, *, /, %)
- Function definition and calling (`invokestatic`)
- `puts` / `print` output
- CLI: `--target jvm`, `--run`, `--emit-ir`

### Control Flow

- `if` / `else` branching (with Phi node elimination)
- `while` loops
- Nested conditionals
- Comparison operators (<, >, <=, >=, ==, !=)
- `break` / `next`

### Strings and Type Conversion

- String literals, string concatenation (`String.concat`)
- String interpolation (`StringBuilder`)
- `to_s` / `to_i` / `to_f` type conversions
- `puts` / `print` support for all types (long, double, boolean, Object)

### Classes and Objects

- Class definition as independent JVM classes (`konpeito/generated/ClassName`)
- Constructors (`<init>` method generation, field default value initialization)
- Instance fields (`getfield` / `putfield`)
- Instance methods (non-static, slot 0 = self)
- Method dispatch (`invokevirtual`)
- Class methods (`def self.xxx` -> `invokestatic`)
- Inheritance (`superName` configuration, parent class field/method inheritance)
- Auto-generated field accessors (RBS `def name=:` -> `putfield` / `getfield`)
- void method return sanitization (non-void return auto-converted to void return)
- RBS type resolution fallback (obtain type from RBS when HIR TypeVar is unresolved)

### Runtime Library

Ruby-compatible collection types (`KArray<T>`, `KHash<K,V>`) and String / numeric / Array Enumerable methods implemented.

**Runtime classes (composition pattern):**

```java
// KArray<T>: implements java.util.List<T>, internally holds ArrayList<T>
public class KArray<T> implements List<T> {
    private final ArrayList<T> data;
    // List delegation + Ruby-specific methods (first, last, push, pop, length, etc.)
}

// KHash<K,V>: implements java.util.Map<K,V>, internally holds LinkedHashMap<K,V>
public class KHash<K, V> implements Map<K, V> {
    private final LinkedHashMap<K, V> data;
    // Map delegation + Ruby-specific methods (has_key?, keys, values, length, etc.)
}
```

**Implementation details:**

- **Array literals / basic operations**: `[1, 2, 3]` -> `new KArray` + `List.add()`, `arr[i]`, `arr.push(val)`, `arr.length`, `arr.first`/`last`, `arr.empty?`/`include?`
- **Hash literals / basic operations**: `{"a" => 1}` -> `new KHash` + `Map.put()`, `hash[key]`, `hash.size`, `hash.has_key?`, `hash.keys`/`values`
- **Symbol literals**: `:sym` -> `String` via `ldc`
- **String methods**: `length`, `upcase`/`downcase`, `strip`, `reverse`, `include?`, `empty?`, `split`, `gsub`, `start_with?`/`end_with?`, `chars`
- **Numeric methods**: `abs` (`Math.abs`), `even?`/`odd?` (`land` + `icmp`), `zero?`/`positive?`/`negative?` (`lcmp`)
- **Array Enumerable (inline loops)**: `each`, `map`, `select`, `reject`, `reduce`, `any?`, `all?`, `none?`
- **Hash iteration**: `each` (`entrySet().iterator()` + `getKey()`/`getValue()`)
- **Class + collection integration**: Instance variable Array/Hash detected by type inference even without RBS, method dispatch supported
- **User-defined class type inference (RBS-free)**: HM inference correctly infers `Coordinate.new(x, y)` -> `ClassInstance(:Coordinate)`. Cross-class reference chains (`Line` -> `Coordinate`) also work without RBS
- **Typed field descriptors**: Fields with Array/Hash/user-defined class types use `KArray`/`KHash`/`Lkonpeito/generated/ClassName;` descriptors (eliminating unnecessary `checkcast`)
- **Monomorphized generics**: RBS type parameters `[T] (T value) -> T` work on the JVM backend as well. Correct dispatch via `@specialized_target`

```ruby
# Array + Enumerable
arr = [1, 2, 3, 4, 5]
doubled = arr.map { |x| x * 2 }      # => [2, 4, 6, 8, 10]
evens = arr.select { |x| x % 2 == 0 } # => [2, 4]
sum = arr.reduce(0) { |acc, x| acc + x } # => 15

# Hash
h = {"name" => "Alice", "age" => "30"}
h.each { |k, v| puts k + ": " + v }

# Class + collection (without RBS)
class TaskList
  def initialize
    @tasks = []
  end
  def add(task)
    @tasks.push(task)
  end
  def count
    @tasks.length
  end
end

# Cross-class reference chains (without RBS)
class Coordinate
  def initialize(x, y)
    @x = x
    @y = y
  end
  def x = @x
  def y = @y
end

class Line
  def initialize(x1, y1, x2, y2)
    @start = Coordinate.new(x1, y1)
    @end_pt = Coordinate.new(x2, y2)
  end
  def start_x = @start.x
  def end_y = @end_pt.y
end

line = Line.new(10, 20, 30, 40)
puts line.start_x  # => 10
puts line.end_y    # => 40
```

**Build pipeline:**
- `tools/konpeito-asm/build.sh` also compiles runtime classes
- `jvm_backend.rb` bundles runtime `.class` files into the output directory
- Runtime classes are pre-compiled in `tools/konpeito-asm/runtime-classes/`

### Test Suite

```bash
bundle exec ruby -Ilib:test test/jvm/jvm_backend_test.rb
# 370 tests, 0 failures
```

---

## Roadmap

### Implemented

| Content | Status |
|---------|--------|
| Foundation: ASM tool + arithmetic | Done |
| Control flow: if/else, while | Done |
| Strings + type conversion | Done |
| Classes and objects | Done |
| Blocks and closures | Done |
| Runtime library | Done |
| Java Interop | Done |
| Exceptions + pattern matching + minor features | Done |
| Modules + Mixin | Done |
| Concurrency -- Virtual Threads | Done |
| Generics + native structures | Done |
| Standard library (JVM edition) | Done |
| `%a{jvm_static}` + Block to SAM + classpath introspection | Done |
| RBS-free Java Interop | Done |
| invokedynamic fallback + Castella UI | Done |

### Planned

| Content | Overview |
|---------|----------|
| Tooling | Gradle plugin, IDE integration |
| Performance optimization | JIT-friendly code generation, GraalVM native-image |

### Dependencies

```
Foundation <- Prerequisite for all features
  |
  +-- Control flow
  |     |
  |     +-- Strings + boxing
  |     |     |
  |     |     +-- Classes/Objects
  |     |     |     |
  |     |     |     +-- Blocks/invokedynamic <- Core of DSL differentiation
  |     |     |     |     |
  |     |     |     |     +-- Modules/Mixin
  |     |     |     |     +-- Concurrency
  |     |     |     |
  |     |     |     +-- Runtime library
  |     |     |     |     |
  |     |     |     |     +-- Standard library
  |     |     |     |
  |     |     |     +-- Java Interop <- Core of practicality
  |     |     |           |
  |     |     |           +-- %a{jvm_static} + Block to SAM
  |     |     |           |     |
  |     |     |           |     +-- RBS-free Java Interop <- Core of zero-RBS
  |     |     |           |           |
  |     |     |           |           +-- invokedynamic Fallback + Castella UI
  |     |     |           |
  |     |     |           +-- Tooling
  |     |     |
  |     |     +-- Exceptions + pattern matching
  |     |
  |     +-- Generics + native structures
  |
  +-- Performance
```

### Classes and Object System

```ruby
# Ruby
class Point
  def x
    @x
  end
  def y
    @y
  end
end

p = Point.new
p.x = 3
p.y = 4
puts p.x  # => 3
puts p.y  # => 4
```

```
// Generated JVM class (RBS: @x: Integer, @y: Integer)
public class Point {
    public long x;     // unboxed field
    public long y;

    public Point() {
        super();
        this.x = 0L;
        this.y = 0L;
    }
    public long x() { return this.x; }
    public long y() { return this.y; }
}
```

RBS type information is reflected in JVM field types:

| RBS Type | JVM Field Type | Descriptor |
|----------|----------------|------------|
| `Integer` | `long` | `J` |
| `Float` | `double` | `D` |
| `bool` | `boolean` | `Z` |
| `String` | `java.lang.String` | `Ljava/lang/String;` |
| Other | `java.lang.Object` | `Ljava/lang/Object;` |

```ruby
# Inheritance
class Animal
  def name
    @name
  end
end

class Dog < Animal    # Dog extends Animal
  def speak
    puts "woof"
  end
end

d = Dog.new
d.name = "Rex"     # putfield (parent class field)
puts d.name        # invokevirtual (parent class method)
d.speak            # invokevirtual (child class method)
```

```java
// Generated JVM class (RBS: @name: String)
public class Animal {
    public String name;  // RBS @name: String -> Ljava/lang/String;

    public Animal() {
        super();
        this.name = null;
    }
    public String name() { return this.name; }
}

public class Dog extends Animal {
    public Dog() {
        super();  // Calls Animal.<init>
    }
    public void speak() {
        System.out.println("woof");
    }
}

// Main class
public class InheritMain {
    public static void __main__() {
        Dog d = new Dog();
        d.name = "Rex";            // putfield Animal.name (inherited field)
        System.out.println(d.name()); // invokevirtual Animal.name()
        d.speak();                  // invokevirtual Dog.speak()
    }
}
```

#### Operator Overloading

Operator methods on user-defined classes are generated as regular instance methods. Since JVM bytecode allows symbols like `+`, `-`, `*` directly as method names, no special name transformation is needed.

```ruby
class Vector2
  def +(other)
    result = Vector2.new
    result.x = @x + other.x
    result.y = @y + other.y
    result
  end
end
```

```java
// Generated JVM method
public class Vector2 {
    public double x;
    public double y;

    // Method name "+" is valid in JVM bytecode
    public Object +(Object other) {
        Vector2 result = new Vector2();
        result.x = this.x + ((Vector2)other).x;  // checkcast is inserted
        result.y = this.y + ((Vector2)other).y;
        return result;
    }
}
```

**Automatic `checkcast` insertion**: In method descriptors, user-defined class parameters and return values become `Ljava/lang/Object;`. To ensure the JVM verifier works correctly, `checkcast` is automatically inserted at the following three points:

1. **`generate_native_field_get`**: Before field access (e.g., casting `other` from `Object` to `Vector2` for `other.x`)
2. **`generate_native_field_set`**: Before field assignment (same as above)
3. **`generate_native_method_call`**: Before `invokevirtual` on the receiver + before storing the return value

### Blocks and Closures

Ruby blocks/closures are implemented using the same `invokedynamic` + `LambdaMetafactory` strategy as Kotlin.

**Implementation details:**
- **Typed KBlock interfaces**: Automatically generated type-specialized functional interfaces based on HM type inference results (`KBlock_J_ret_Obj`, `KBlock_Obj_ret_Obj`, etc.)
- **Block to static method**: Block body compiled as a `private static synthetic` method
- **invokedynamic**: KBlock instances created via `LambdaMetafactory.metafactory`
- **yield**: KBlock parameter added to the function, called via `invokeinterface`
- **block_given?**: `ifnonnull` check on the KBlock parameter
- **Integer#times**: Inline-expanded into a native i64 counter loop
- **Lambda/Proc**: `ProcNew` -> invokedynamic, `.call()` -> `invokeinterface`
- **Closure capture**: Captured variables passed as arguments at the invokedynamic site
- **Automatic Object/primitive conversion**: Boxing/unboxing with `Long.valueOf()`/`longValue()` etc. at type boundaries

```ruby
# yield + block_given?
def maybe
  if block_given?
    yield("world")
  else
    "default"
  end
end
puts maybe { |x| "hello " + x }  # => hello world

# Lambda (closure capture)
base = 10
adder = ->(x) { x + base }
puts adder.call(5)  # => 15

# Integer#times (inline optimization)
total = 0
5.times { |i| total = total + i }
puts total  # => 10
```

Tests: 8 test cases (yield basic, return value, multiple calls, 2 arguments, block_given?, times, lambda, capture)

### Java Interop

No annotations needed. Java classes are declared using the `Java::` module convention (JRuby-style) and called directly via JVM bytecode.

```rbs
# types.rbs -- Just declare in the Java:: namespace (no annotations needed)
class Java::Util::ArrayList
  def self.new: () -> Java::Util::ArrayList
  def add: (Object element) -> bool
  def get: (Integer index) -> Object
  def size: () -> Integer
  def isEmpty: () -> bool
end

class Java::Lang::StringBuilder
  def self.new: () -> Java::Lang::StringBuilder
  def append: (String s) -> Java::Lang::StringBuilder
  def toString: () -> String
end

class Java::Lang::Integer
  def self.parseInt: (String s) -> Integer
end
```

```ruby
# source.rb -- Use Java method names directly
list = Java::Util::ArrayList.new
list.add("hello")
list.add("world")
puts list.size       # => 2
puts list.get(0)     # => hello
puts list.isEmpty    # => false

sb = Java::Lang::StringBuilder.new
sb.append("Hello, ").append("World!")
puts sb.toString     # => Hello, World!

puts Java::Lang::Integer.parseInt("42")  # => 42
```

**Design principles:**
- `Java::Util::ArrayList` -> Automatically converted to JVM internal name `java/util/ArrayList`
- Package names are lowercased (`Util` -> `util`), class names remain as-is
- Java `int` (32-bit) and Konpeito `Integer` (64-bit long) are automatically converted via `l2i`/`i2l`
- Method chaining supported (`sb.append("a").append("b")` -- return type is tracked)
- `invokevirtual` (instance methods), `invokestatic` (static methods), `invokespecial` (constructors)

Tests: 6 test cases (ArrayList, HashMap, static methods, StringBuilder chaining, boolean return value, String.valueOf)

### Exception Handling + Pattern Matching + Minor Features

#### Exception Handling (raise / rescue / else / ensure)

Mapped to the JVM's `try-catch-finally` mechanism. Uses ASM's `exceptionTable`.

```ruby
# raise -> RuntimeException + athrow
def safe_divide(a, b)
  begin
    if b == 0
      raise "division by zero"
    end
    a / b
  rescue
    -1
  end
end
puts safe_divide(10, 0)  # => -1
```

**JVM implementation:**
- `raise "message"` -> `new RuntimeException(message)` + `athrow`
- `begin/rescue` -> exception table entries (start, end, handler, type)
- Multiple rescue clauses -> multiple handler labels and exception table entries
- `else` -> executed only on normal try completion (skips rescue)
- `ensure` -> normal path + catch-all handler (`type: null`) with re-throw

**Exception class mapping:**

| Ruby | JVM |
|------|-----|
| `RuntimeError` | `java/lang/RuntimeException` |
| `StandardError` | `java/lang/Exception` |
| `ArgumentError` | `java/lang/IllegalArgumentException` |
| `TypeError` | `java/lang/ClassCastException` |
| bare `rescue` | `java/lang/Exception` |

#### case/when

Value comparison using `Object.equals()` and type checking using `instanceof`.

```ruby
def classify(x)
  case x
  when 1 then "one"
  when 2 then "two"
  else "other"
  end
end
puts classify(1)  # => one
```

**JVM implementation:**
- Load the predicate once and box it -> compare with each when clause using `Object.equals()`
- For `ConstantLookup` (type names), use `instanceof`
- The else clause is executed when no when clause matches
- Results are saved via phi-store to a shared slot

#### case/in Pattern Matching

Ruby 3.0+ pattern matching syntax converted to JVM bytecode.

```ruby
def describe(x)
  case x
  in 1 | 2 | 3 then "small"
  in Integer then "number"
  in n then n.to_s
  end
end
```

**Supported patterns:**

| Pattern | JVM Implementation |
|---------|-------------------|
| Literal (`in 1`) | Boxing + `Object.equals()` |
| Type/constant (`in Integer`) | `instanceof java/lang/Long` |
| Variable (`in n`) | Always matches, `astore` to variable slot |
| Alternation (`in 1 \| 2 \| 3`) | Early-exit branching (`ifne` -> match_ok label) |

- No match + no else -> throws `RuntimeException("no matching pattern")`

#### Minor Features

**Global variables (`$var`) / Class variables (`@@var`):**
- Implemented as `static` fields on the main class
- `$counter` -> `GLOBAL_counter`, `@@total` -> `CLASSVAR_total`
- Accessed via `getstatic` / `putstatic`

**Multiple assignment (`a, b = [1, 2]`):**
- Element retrieval via `KArray.get(index)`

**Range literals (`1..5`):**
- Stored as string representation (`"1..5"`)

**Regular expressions (`/pattern/`):**
- Stored as pattern string (`ldc`)

Tests: 24 test cases (raise 2, rescue 4, rescue+else+ensure 4, case/when 4, case/in 5, minor features 5)

### Modules + Mixin

Ruby modules are mapped to JVM **interfaces + default methods** (Java 8+).

**Mapping strategy:**

| Ruby | JVM |
|------|-----|
| `module Foo` | `public interface Foo` |
| Module instance methods | `default` methods (with body) |
| `def self.method` | `public static` method on interface |
| `include M` | Class `implements M` (default methods automatically inherited) |
| `extend M` | Static wrapper methods generated on the class |
| `prepend M` | Same as `include` (simplified MRO) |

```ruby
# Module definition -> JVM interface with default methods
module Greetable
  def greet
    "Hello"
  end

  def self.version
    "1.0"
  end
end

# include -> implements
class Person
  include Greetable
end

Person.new.greet      # => "Hello" (default method via invokevirtual)
Greetable.version     # => "1.0" (invokestatic with isInterface=true)

# extend -> static method delegation
module ClassMethods
  def factory
    42
  end
end

class Widget
  extend ClassMethods
end

Widget.factory  # => 42 (invokestatic on Widget class)
```

**Technical details:**
- Static method calls on interfaces require the `isInterface=true` flag (ASM tool extension)
- Method descriptors from included modules are also registered on the class (for `invokevirtual` resolution)
- Class methods can override module default methods (standard JVM semantics)
- `extend` regenerates module instance methods as static methods on the class

Tests: 9 test cases (singleton methods 2, include basic, include with parameters, multiple includes, both method types, extend, override, arithmetic)

### Concurrency -- Virtual Threads

Ruby-style concurrency primitives leveraging Java 21 Virtual Threads.

**Runtime classes:**
- `KThread` -- `Thread.ofVirtual().start()` wrapper. Supports result retrieval via `Callable<Object>`
- `KConditionVariable` -- Internal `ReentrantLock` + `Condition` pair
- `KSizedQueue` -- `ArrayBlockingQueue` wrapper

**Supported HIR nodes (15):**
- Thread: `ThreadNew`, `ThreadJoin`, `ThreadValue`, `ThreadCurrent`
- Mutex: `MutexNew`, `MutexLock`, `MutexUnlock`, `MutexSynchronize`
- ConditionVariable: `ConditionVariableNew`, `ConditionVariableWait`, `ConditionVariableSignal`, `ConditionVariableBroadcast`
- SizedQueue: `SizedQueueNew`, `SizedQueuePush`, `SizedQueuePop`

**Additional method dispatch:** `@variable_concurrency_types` tracks Thread/Mutex/CV/SizedQueue receivers and converts calls like `sq.max`, `sq.size` to `invokevirtual`.

```ruby
# Thread: Create threads with Virtual Threads
t = Thread.new { 100 + 23 }
puts t.value  # => 123

# Mutex: Exclusive control with ReentrantLock
m = Mutex.new
m.synchronize { shared_resource }  # try/finally + exception table

# SizedQueue: Blocking queue with ArrayBlockingQueue
sq = SizedQueue.new(5)
sq.push(42)
puts sq.pop   # => 42
puts sq.max   # => 5
```

| Ruby | JVM Implementation |
|------|-------------------|
| `Thread.new { }` | `KThread(Callable)` -> `Thread.ofVirtual().start()` |
| `thread.join` / `thread.value` | `KThread.join()` / `KThread.getValue()` |
| `Mutex.new` / `lock` / `unlock` | `new ReentrantLock()` / `lock()` / `unlock()` |
| `Mutex.synchronize { }` | `lock()` + try/finally + exception table |
| `ConditionVariable` | `KConditionVariable` (internal Lock + Condition) |
| `SizedQueue.new(n)` | `KSizedQueue(ArrayBlockingQueue)` |

**Tests:** 13 tests added (156 total JVM tests, 0 failures)

---

### Generics + Native Structures

NativeArray/StaticArray converted to JVM primitive arrays, and @struct generated as JVM classes.

**NativeArray to primitive arrays:**
- `NativeArray[Integer]` -> `long[]` (`newarray long`)
- `NativeArray[Float]` -> `double[]` (`newarray double`)
- `arr[i]` -> `laload` / `daload` (unboxed element access)
- `arr[i] = v` -> `lastore` / `dastore` (unboxed element write)
- `arr.length` -> `arraylength` + `i2l`

**StaticArray to primitive arrays:**
- Since the JVM does not distinguish between stack and heap, converted to the same primitive arrays as NativeArray
- `StaticArraySize` returns compile-time constants directly via `ldc2_w`

**@struct to JVM classes:**
- Automatically detects RBS-only NativeClass/@struct types and generates Java classes
- `register_rbs_only_native_classes()` registers class information directly from RBS
- `generate_rbs_only_class()` generates fields + default constructor
- Same mutable field semantics as the LLVM side (putfield/getfield)

**Type tracking:**
- `@variable_native_array_element_type` tracks variable to element type (`:i64`, `:double`) mapping
- Propagated in `generate_store_local` / `generate_load_local` (same pattern as `@variable_collection_types`)
- `generate_call` intercepts NativeArray methods (`[]`, `[]=`, `length`) and converts them to primitive array instructions

```ruby
# NativeArray[Integer] -> long[] (unboxed)
arr = NativeArray.new(3)
arr[0] = 10   # lastore
arr[1] = 20   # lastore
puts arr[0] + arr[1]  # laload + ladd -> 30

# @struct -> JVM class (primitive fields)
p = Point.new
p.x = 3.0   # putfield (double)
p.y = 4.0   # putfield (double)
puts p.x + p.y  # getfield + dadd -> 7.0
```

| Ruby | JVM Implementation |
|------|-------------------|
| `NativeArray.new(n)` | `newarray long` / `newarray double` |
| `arr[i]` | `laload` / `daload` |
| `arr[i] = v` | `lastore` / `dastore` |
| `arr.length` | `arraylength` + `i2l` |
| `StaticArray.new` | `newarray` (compile-time size) |
| `@struct Point` | `class konpeito/generated/Point` (mutable fields) |

**Tests:** 13 tests added (169 total JVM tests, 0 failures)

---

### Standard Library (JVM Edition)

Composed of three pillars:

**Part A: Konpeito Stdlib Modules**
- `STDLIB_MODULES` registry pattern maps Ruby module names to Java runtime classes
- `generate_stdlib_call` unifies argument loading -> `invokestatic` -> result storage
- `KJSON.java` -- Custom JSON parser/generator (no external dependencies)
- `KCrypto.java` -- SHA-256/512, HMAC, SecureRandom (`java.security.*`)
- `KCompression.java` -- gzip/deflate/zlib (`java.util.zip.*`)
- `KHTTP.java` -- HTTP client (`java.net.http.HttpClient`)
- `KTime.java` -- Time operations (`java.time.*`)
- `KFile.java` -- File I/O (`java.nio.file.*`)
- `KMath.java` -- Math functions (`java.lang.Math`)

**Part B: Ruby Core Class Method Expansion**
- **String (14 methods added):** `sub`, `index`, `rindex`, `chars`, `lines`, `bytes`, `replace`, `freeze`, `frozen?`, `count`, `tr`, `chomp`, `to_i`, `to_f`
- **Array (8 methods added):** `shift`, `unshift`/`prepend`, `delete_at`, `delete`, `sum`, `find_index`, `find`/`detect`, `count`
- **Hash (4 methods added):** `fetch`, `merge`, `merge!`/`update`, `clear`
- **Numeric (6 methods added):** `round`, `floor`, `ceil`, `to_i`(Float), `to_f`(Integer), `gcd`

**Part C: ASM Tool Improvements**
- Added `dup_x1`, `dup_x2`, `dup2_x1`, `dup2_x2` instruction support

**Tests:** 45 tests added (214 total JVM tests, 0 failures)

---

### `%a{jvm_static}` + Block to SAM + Classpath Introspection

A mechanism to declare external Java classes via RBS annotations and auto-complete method signatures from the classpath.

**Part A: `%a{jvm_static}` RBS Annotation**

```rbs
# Map Ruby module name to Java class via RBS
%a{jvm_static: "konpeito/canvas/KCanvas"}
module KonpeitoCanvas
  %a{callback: "konpeito/canvas/KCanvas$MouseCallback" descriptor: "(DD)V"}
  def self.set_click_callback: () -> void
end
```

- `%a{jvm_static: "java/class/Name"}` -- Maps a Ruby module to an external Java class's static methods
- `%a{callback: "Interface" descriptor: "(DD)V"}` -- Block to SAM interface conversion (`invokedynamic` + `LambdaMetafactory`)
- `parse_jvm_static_module()` parses RBS annotations and registers them in `@jvm_classes`

**Part B: Classpath Introspection**

```bash
# Specify JARs and classes directories via --classpath option
konpeito build --target jvm --classpath "lib/jwm.jar:classes/" demo.rb
```

- `ClassIntrospector.java` -- Extracts method signatures using ASM `ClassReader`
- `--introspect` mode: outputs JSON type information via `java -jar konpeito-asm.jar --introspect`
- `load_classpath_types(classpath)` -- Auto-merges introspection results with RBS definitions
- RBS-defined methods take priority, classpath fills in the gaps
- Descriptor to type tag conversion: `Ljava/lang/String;` -> `:string`, etc.

**Part C: Block to SAM Auto-Detection**

- Inner classes with a single abstract method on an interface are auto-detected as functional interfaces (SAM)
- Ruby blocks converted to SAM instances via `invokedynamic` + `LambdaMetafactory`
- Closure support for captured variables

**Part D: snake_case to camelCase Interconversion**

- `camel_to_snake("drawCircle")` -> `"draw_circle"`
- `snake_to_camel("set_click_callback")` -> `"setClickCallback"`
- Ruby side uses snake_case, Java side uses camelCase transparently

**Tests:** 44 tests added (258 total JVM tests, 0 failures)

---

### RBS-Free Java Interop

Applying Konpeito's design philosophy of "no RBS by default" to Java Interop.
**Enables use of external Java classes without RBS files.**

**Before (RBS required):**
```rbs
# canvas_demo.rbs (was required)
%a{jvm_static: "konpeito/canvas/KCanvas"}
module KonpeitoCanvas
  %a{callback: "konpeito/canvas/KCanvas$MouseCallback" descriptor: "(DD)V"}
  def self.set_click_callback: () -> void
end
```
```ruby
KonpeitoCanvas.open("Demo", 800, 600)
KonpeitoCanvas.set_click_callback { |x, y| ... }
```

**After (No RBS file needed at all):**
```ruby
# canvas_demo.rb -- No RBS file
canvas = Java::Konpeito::Canvas::Canvas.new("Interactive Demo", 800, 600)
canvas.set_background(0xFFF5F5F5)
canvas.draw_circle(200.0, 300.0, 80.0, 0xFF4285F4)
canvas.set_click_callback { |x, y|
  canvas.draw_circle(x, y, 25.0, 0xFF4285F4)
}
canvas.show
```

**Part A: AST Pre-Scan**

Before compilation, the Prism AST is traversed to collect constant references and constant assignments starting with `Java::`:

```ruby
# compiler.rb: scan_java_references(ast)
# "Java::Konpeito::Canvas::Canvas" -> "konpeito/canvas/Canvas"
# "KCanvas = Java::..." -> alias registration
```

- `ConstantPathNode` matching `Java::X::Y::Z` pattern -> converted to JVM internal name
- `ConstantWriteNode` whose value is a `Java::` path -> alias registration
- `ruby_path_to_jvm_internal()` lowercases package names

**Part B: RBSLoader Auto-Registration**

`Java::` references found by AST scanning are introspected from the classpath and auto-registered:

- `register_java_references(java_refs, classpath)` -- Entry point
- `register_introspected_class()` -- Registration for one class (static/instance methods, constructor, fields)
- `build_sam_interface_map()` -- Collects SAM interfaces across all classes
- `detect_sam_callback!()` -- Auto-detects SAM callbacks from method parameters
- Alias registration: data from `Java::Konpeito::Canvas::Canvas` is duplicated for `KCanvas`

**Part C: HM Type Inference Extension**

- `infer_constant_path` -- Returns `ClassSingleton` for `Java::X::Y::Z`
- `infer_constant_write` -- Tracks `KCanvas = Java::...` aliases in the environment
- `infer_jvm_class_method` -- Returns `ClassInstance` for `.new` calls
- `infer_jvm_instance_method` -- Infers return types of instance methods

**Part D: Instance-Based API**

The `%a{jvm_static}` approach was centered on static methods, while RBS-Free Java Interop fully supports instance methods:

| Ruby | JVM |
|------|-----|
| `Canvas.new("title", 800, 600)` | `new` + `invokespecial <init>(Ljava/lang/String;II)V` |
| `canvas.draw_circle(x, y, r, color)` | `invokevirtual drawCircle(DDDI)V` |
| `canvas.set_click_callback { \|x, y\| ... }` | `invokedynamic` (LambdaMetafactory) + `invokevirtual setClickCallback` |

- `generate_jvm_instance_call` -- `invokevirtual` + block to SAM callback support
- `java_name` field automatically applies snake to camelCase mapping
- Class type information for captured variables in blocks is propagated

**Part E: ClassIntrospector Extension**

- Added `visitField` callback -- extracts public fields (instance + static)
- Added `fields` / `static_fields` sections to JSON output

**Part F: JVM Generator Fixes**

- `StoreConstant` skip -- `KCanvas = Java::...` is a type-level alias, no putstatic needed
- `@variable_class_types` propagation for captured variables in blocks
- `Return` node handling for void return methods -- detects unallocated variables and returns null

**Key flow:**

```
Ruby source (.rb)
    |
    v
AST pre-scan --> Java:: reference collection
    |                    |
    v                    v
HM type inference   register_java_references()
    |                    |
    v                    v
HIR generation     ClassIntrospector (ASM)
    |                    |
    v                    v
JVM code generation <-- @jvm_classes (auto-registered)
    |
    v
.jar (no RBS needed)
```

**Tests:** 8 tests added (266 total JVM tests, 0 failures)

---

### invokedynamic Fallback + RubyDispatch

Method calls that could not be resolved by HM type inference are fallback-dispatched at runtime via `invokedynamic`, instead of resulting in a compile error.

**Background:** In large-scale Ruby code such as the Castella UI framework, which involves parameter types passed through blocks and dynamic widget tree construction, HM inference alone cannot resolve types for all methods. Making these compile errors would render the entire framework unusable, so runtime resolution guarantees correct behavior.

**RubyDispatch.java -- Runtime Dispatch Class:**

```java
// Bootstrap method: called once by the JVM for invokedynamic
public static CallSite bootstrap(MethodHandles.Lookup lookup, String methodName,
                                 MethodType type) {
    // ConstantCallSite -> wraps the dispatch() method
}

// Generic dispatch: args[0]=receiver, args[1..]=arguments
public static Object dispatch(String methodName, Object[] args) {
    // Search for Java method using 3-stage name resolution
}
```

**3-Stage Name Resolution:**

| Stage | Method | Example |
|-------|--------|---------|
| 1 | Exact match | `length` -> `length()` |
| 2 | `RUBY_NAME_ALIASES` (63 entries) | `op_aref` -> `get`, `empty_q` -> `isEmpty_` |
| 3 | `snakeToCamel` conversion | `clip_rect` -> `clipRect` |

**Alias examples:**
- Operators: `op_aref` -> `get`, `op_aset` -> `set`/`put`, `op_lshift` -> `push`/`add`
- Predicates: `empty_q` -> `isEmpty_`, `has_key_q` -> `hasKey`
- Mutations: `merge_bang` -> `mergeInPlace`, `delete_at` -> `deleteAt`

**Number checkcast:**

The return value of `invokedynamic` is `Object` type, and whether a numeric value is `Long` or `Double` is unknown until runtime. The JVM generator uses `checkcast java/lang/Number` + `Number.longValue()`/`Number.doubleValue()` to safely unbox regardless of which type is returned.

**Generated JVM code:**

```
// Unresolved call: receiver.method_name(args...)
aload <receiver>       // Load receiver as Object
aload <arg1>           // Load arguments
...
invokedynamic method_name (Ljava/lang/Object;...)Ljava/lang/Object;
  bootstrap: konpeito/runtime/RubyDispatch.bootstrap
astore <result>        // Store result as Object
```

**Compile-time diagnostic messages:**

```
Info: N dynamically dispatched method call(s):
  App#run: .clear(0 args) -- receiver type: untyped [invokedynamic]
  CounterComponent#view: .color(1 args) -- receiver type: untyped [invokedynamic]
```

**Castella UI Framework Integration:**

This mechanism enables the Castella UI framework (Component/State/Layout/Widget) implemented in `lib/konpeito/ui/` to run on the JVM:

```ruby
# framework_counter.rb -- Castella UI demo
class CounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    count = @count
    Column(
      Text("Count: " + count.value.to_s).font_size(32).align(TEXT_ALIGN_CENTER),
      Row(
        Button("  -  ").on_click { count.set(count.value - 1) },
        Button("  +  ").on_click { count.set(count.value + 1) }
      )
    )
  end
end

frame = JWMFrame.new("Castella Counter", 400, 300)
app = App.new(frame, CounterComponent.new)
app.run
```

- **Statically resolved calls**: Methods whose types are determined by HM inference + RBS -> `invokevirtual`/`invokestatic`
- **Dynamic fallback**: Unresolved parameter types within blocks -> `invokedynamic` + `RubyDispatch`
- **Future**: Adding RBS type definitions can promote calls to static dispatch

**Tests:** 5 tests added (271 total JVM tests, 0 failures)

---

## Differentiation from Kotlin

### 1. HM Global Type Inference

```ruby
# Konpeito: Type inference works even without RBS
def double(x)
  x * 2           # 2 is Integer -> x is also inferred as Integer
end

def greet(name)
  "Hello, " + name  # name: String is inferred from the argument type of String#+
end
```

```kotlin
// Kotlin: Local inference only. Function parameters require type annotations
fun double(x: Int): Int = x * 2
fun greet(name: String): String = "Hello, $name"
```

### 2. DSL via Ruby Block Syntax

```ruby
# Konpeito: Natural block syntax
html do
  head do
    title { "My Page" }
  end
  body do
    h1 { "Welcome" }
    ul do
      items.each { |item| li { item.name } }
    end
  end
end
```

```kotlin
// Kotlin: Lambdas are possible but not as natural as block syntax
html {
    head {
        title { +"My Page" }  // + operator required
    }
}
```

### 3. RBS Separated Type Definitions

```ruby
# source.rb (no type annotations -- pure Ruby)
def process(data)
  data.map { |item| item.to_s }
end
```

```rbs
# types.rbs (type definitions in a separate file)
module TopLevel
  def process: (Array[Integer] data) -> Array[String]
end
```

In Kotlin, type annotations are mixed into the source code, but with Konpeito, they can be separated via RBS.
This makes gradual typing of existing Ruby code easier.

### 4. Pattern Matching

```ruby
# Konpeito: Ruby 3.0+ comprehensive pattern matching
case data
in [Integer => x, Integer => y] if x > 0
  "positive pair: #{x}, #{y}"
in {name: String => name, age: Integer => age}
  "person: #{name} (#{age})"
in ^expected
  "matched expected value"
else
  "unknown"
end
```

---

## Directory Structure

```
konpeito/
├── lib/konpeito/
│   ├── codegen/
│   │   ├── llvm_generator.rb    # LLVM backend (existing)
│   │   ├── cruby_backend.rb     # CRuby extension backend (existing)
│   │   ├── jvm_generator.rb     # JVM backend: HIR -> JSON IR
│   │   └── jvm_backend.rb       # JVM backend: pipeline management
│   ├── ui/                      # Castella UI framework (Ruby implementation)
│   │   ├── core.rb              # Widget/Component/State base classes
│   │   ├── render_node.rb       # RenderNode (rendering tree)
│   │   ├── app.rb               # App (main loop + event dispatch)
│   │   ├── frame.rb             # JWMFrame (window management)
│   │   ├── column.rb / row.rb   # Column/Row layout
│   │   ├── box.rb / spacer.rb   # Box/Spacer layout
│   │   ├── theme.rb             # Theme system
│   │   └── widgets/             # Widget collection
│   │       ├── text.rb          # Text (TextAlign support)
│   │       ├── button.rb        # Button (hover/click support)
│   │       ├── divider.rb       # Divider
│   │       ├── container.rb     # Container
│   │       └── input.rb         # Input (text input)
│   └── compiler.rb              # --target jvm branching
├── tools/
│   └── konpeito-asm/            # ASM wrapper tool
│       ├── src/
│       │   ├── KonpeitoAssembler.java
│       │   ├── ClassIntrospector.java
│       │   └── konpeito/runtime/   # Runtime classes (14 classes)
│       │       ├── KArray.java      # Ruby Array compatible
│       │       ├── KHash.java       # Ruby Hash compatible
│       │       ├── RubyDispatch.java # invokedynamic bootstrap
│       │       └── ... (KThread, KJSON, KCrypto, etc.)
│       ├── runtime-classes/      # Pre-compiled runtime .class files
│       │   └── konpeito/runtime/
│       ├── lib/
│       │   └── asm-9.7.1.jar
│       └── build.sh
├── test/
│   └── jvm/
│       └── jvm_backend_test.rb  # JVM backend tests (370 tests)
├── examples/
│   ├── jvm_hello.rb             # JVM sample
│   ├── jvm_hello.rbs
│   └── castella_ui/             # Castella UI samples
│       ├── framework_counter.rb # Counter demo (Component/State/Layout)
│       ├── src/konpeito/ui/     # Java-side runtime (KUIRuntime, JWMFrame, etc.)
│       ├── lib/                 # JWM + Skija JARs
│       └── run.sh               # Build & run script
└── docs/
    ├── architecture-jvm-ja.md   # Japanese version of this document
    ├── architecture-jvm.md      # This file
    └── castella-ui-ja.md        # Castella UI porting document
```

---

## Castella UI Framework

As a showcase for the Konpeito/JVM backend, the Castella UI framework (ported from the Python version) is implemented.
It calls JWM (window management) + Skija (2D graphics) via Java Interop to build cross-platform GUIs in Ruby code.

**See [docs/castella-ui-ja.md](castella-ui-ja.md) for details.**

### Structure

```
lib/konpeito/ui/           # Ruby implementation (compiled with Konpeito)
  ├── core.rb              # Widget, Component, State base classes
  ├── column.rb / row.rb   # Flexible layout
  ├── widgets/text.rb      # Text widget with TextAlign support
  └── ...

examples/castella_ui/
  ├── framework_counter.rb # Demo app
  ├── src/konpeito/ui/     # Java-side runtime (KUIRuntime, etc.)
  └── lib/                 # JWM + Skija JARs
```

### Technical Highlights

- **Hybrid of static + dynamic dispatch**: Methods resolved by HM inference use `invokevirtual`, unresolved ones use `invokedynamic`
- **Block to SAM conversion**: `on_click { ... }` -> Java functional interface (LambdaMetafactory)
- **Component/State pattern**: `state(initial_value)` generates an Observable, automatic rebuild on value change

### How to Run

```bash
cd examples/castella_ui && bash run.sh framework_counter.rb
```

---

## Requirements

- **Java 21+** (LTS) -- `brew install openjdk@21`
- **ASM 9.7.1** -- Bundled in `tools/konpeito-asm/lib/`
- Ruby 4.0.1+ and existing Konpeito dependencies

```bash
# Install Java 21
brew install openjdk@21

# Compile with JVM backend
konpeito build --target jvm --run examples/jvm_hello.rb
```
