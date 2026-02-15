# RBS File Requirements Guide

Konpeito can compile and run many programs without RBS files thanks to HM type inference (Algorithm W). This document explains when RBS is required and when it is not.

## Cases Where RBS is Not Required

### 1. When Types Can Be Inferred from Literals

HM type inference can reverse-infer argument and variable types from literal values.

```ruby
# Works - 10 is Integer, so a and b are inferred as Integer
def add(a, b)
  a + b + 10
end

# Works - String#+ implies name is String
def greet(name)
  "Hello, " + name
end

# Works - 1.5 is Float, so x is inferred as Float
def scale(x)
  x * 1.5
end
```

### 2. When Types Can Be Inferred from Call Sites

Types are inferred from function call sites, and monomorphization generates concrete code for each specific type.

```ruby
# Works - inferred from call sites
def identity(x)
  x
end

identity(42)       # identity_Integer is generated
identity("hello")  # identity_String is generated
identity(3.14)     # identity_Float is generated
```

### 3. When Using Methods of Built-in Types

The RBS loader always loads RBS definitions for Ruby standard built-in types (Integer, Float, String, Array, Hash, etc.). Methods of these types can be used without explicit RBS.

```ruby
# Works - built-in type methods
arr = [1, 2, 3]                        # Array[Integer]
doubled = arr.map { |x| x * 2 }        # Array#map is known
sum = arr.reduce(0) { |s, x| s + x }   # Array#reduce is known

str = "hello"
len = str.length    # String#length is known
upper = str.upcase  # String#upcase is known

hash = { a: 1, b: 2 }
hash[:a]            # Hash#[] is known
```

### 4. Control Structures and Basic Syntax

Control structures such as if/unless, while, case/when work without type annotations.

```ruby
# Works
def factorial(n)
  if n <= 1
    1
  else
    n * factorial(n - 1)
  end
end

# Works
def sum_to(n)
  total = 0
  i = 1
  while i <= n
    total = total + i
    i = i + 1
  end
  total
end

# Works
def classify(x)
  case x
  when 0 then "zero"
  when 1..10 then "small"
  else "large"
  end
end
```

### 5. Blocks and Iterators

```ruby
# Works
def each_squared(arr)
  arr.each { |x| puts x * x }
end

# Works
def select_positive(arr)
  arr.select { |x| x > 0 }
end
```

## Cases Where RBS is Required

### 1. NativeClass (Native Struct)

To treat a class as a native struct, you must define the field layout in RBS.

```rbs
# types.rbs - Required
class Point
  @x: Float
  @y: Float

  def self.new: () -> Point
  def x: () -> Float
  def x=: (Float) -> Float
  def y: () -> Float
  def y=: (Float) -> Float
end
```

```ruby
# point.rb
class Point
  def x = @x
  def x=(v) = @x = v
  def y = @y
  def y=(v) = @y = v
end
```

Without RBS, the class is treated as a regular Ruby object (VALUE type), and unboxed optimizations are not applied.

### 2. NativeArray

RBS is required to specify the element type of a NativeArray.

```rbs
# types.rbs - Required
class NativeArray[T]
  def self.new: (Integer size) -> NativeArray[Float]
  def []: (Integer index) -> Float
  def []=: (Integer index, Float value) -> Float
  def length: () -> Integer
end
```

### 3. %a{cfunc}/%a{ffi} (External C Library Integration)

To call external C functions directly, you must specify annotations in RBS.

```rbs
# math_lib.rbs - Required
%a{ffi: "libm"}
module MathLib
  %a{cfunc}
  def self.sin: (Float) -> Float

  %a{cfunc: "sqrt"}
  def self.square_root: (Float) -> Float
end
```

### 4. %a{simd} (SIMD Vectorization)

To use SIMD vector types, you must define annotations and fields in RBS.

```rbs
# vector.rbs - Required
%a{simd}
class Vector4
  @x: Float
  @y: Float
  @z: Float
  @w: Float

  def self.new: () -> Vector4
  def add: (Vector4 other) -> Vector4
  def dot: (Vector4 other) -> Float
end
```

### 5. %a{extern} (External C Struct Wrapper)

RBS is required to wrap structs from external C libraries.

```rbs
# sqlite.rbs - Required
%a{ffi: "libsqlite3"}
%a{extern}
class SQLiteDB
  def self.open: (String path) -> SQLiteDB
  def execute: (String sql) -> Array
  def close: () -> void
end
```

### 6. When Explicit Type Constraints Are Needed

RBS is used when type inference alone is insufficient and you want to enforce specific types.

```rbs
# types.rbs - Optional but recommended
module TopLevel
  # Guarantee that the argument is always Integer
  def compute: (Integer n) -> Integer
end
```

## Fallback Behavior

When there is no RBS and type inference is not possible, Konpeito falls back to VALUE type (Ruby object).

```ruby
# Falls back to VALUE type (works but is not optimized)
def mystery(x)
  x.unknown_method  # type of unknown_method is unknown
end
```

In this case:
- The code can be compiled and executed
- Method calls go through `rb_funcallv`
- Optimizations such as unboxed arithmetic are not applied

## Decision Flowchart

```
Want to compile code
    |
    v
Using NativeClass/NativeArray?
    |
    +-- Yes -> RBS required (field layout definition)
    |
    v
Using @cfunc/@ffi/extern/simd?
    |
    +-- Yes -> RBS required (annotation needed)
    |
    v
Can types be determined by inference?
    |
    +-- Yes -> RBS not required (works with HM inference)
    |
    v
Is VALUE type fallback acceptable?
    |
    +-- Yes -> RBS not required (works without optimization)
    |
    v
RBS recommended (enable optimization with explicit types)
```

## Summary

| Situation | RBS | Notes |
|-----------|-----|-------|
| Pure computation and loops | Not required | Types determined by HM inference |
| Built-in type operations | Not required | Standard RBS loaded automatically |
| NativeClass | **Required** | Field layout definition |
| NativeArray | **Required** | Element type specification |
| StaticArray | **Required** | Size and element type specification |
| Slice | **Required** | Element type specification |
| %a{cfunc}/%a{ffi} | **Required** | Annotation needed |
| %a{simd} | **Required** | Annotation needed |
| %a{extern} | **Required** | Annotation needed |
| When types cannot be inferred | Recommended | Works with VALUE type fallback |
| Explicitly enabling optimization | Recommended | Guarantees unboxed arithmetic |

## Related Documents

- [Architecture Guide](architecture-ja.md) - Details of the compilation pipeline
- [Native Standard Library Proposal](native-stdlib-proposal.md) - Design of NativeArray, StaticArray, Slice, etc.
