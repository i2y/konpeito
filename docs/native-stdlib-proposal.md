# Konpeito Native Standard Library Proposal

Based on research into [Crystal's standard library](https://crystal-lang.org/reference/1.19/guides/performance.html) and its [native data structures](https://crystal-lang.org/api/1.18.2/StaticArray.html).

## Design Philosophy

Konpeitoの目標は「CRuby拡張をRubyで書く」ツールであり、Crystalのような完全なスタンドアロンコンパイラではない。そのため、ネイティブ標準ライブラリは以下の原則に基づいて設計する：

1. **CRuby互換性**: Rubyの標準ライブラリと互換性のあるAPIを提供
2. **段階的最適化**: 必要な部分だけネイティブ化できる設計
3. **型安全性**: RBSによる静的型チェックと実行時安全性の両立
4. **ゼロコスト抽象化**: 使わない機能はオーバーヘッドを発生させない

## Crystal Standard Library Insights

### Performance Patterns (from Crystal)

| Pattern | Performance Impact |
|---------|-------------------|
| Struct vs Class | 15x faster (stack vs heap) |
| StaticArray vs Array | No GC pressure, predictable layout |
| Slice vs Pointer | Bounds-checked, safe memory access |
| String ASCII optimization | O(1) indexing for ASCII strings |
| IO-based string building | Avoids intermediate allocations |
| Tuple literals in loops | No heap allocation per iteration |

### Key Crystal Types

```
StaticArray(T, N) - Fixed-size, stack-allocated array
Slice(T)          - Bounds-checked pointer view
Bytes             - Slice(UInt8) alias for binary data
StringPool        - Interned string optimization
```

## Proposed Konpeito Native Types

### Core Types (Implemented)

Already available in Konpeito:

```ruby
# NativeArray[T] - Contiguous unboxed numeric array
arr = NativeArray.new(1000)  # Float64 array
arr[0] = 3.14
arr.each { |x| ... }
arr.reduce(0.0) { |acc, x| acc + x }

# NativeClass - Unboxed struct with native fields
class Point
  @x: Float
  @y: Float
end
```

### StaticArray[T, N] (New)

固定サイズのスタック割り当て配列。サイズがコンパイル時に既知の場合に最適。

```ruby
# RBS Definition
class StaticArray[T, N]
  def self.new: () -> StaticArray[T, N]
  def self.new: (T value) -> StaticArray[T, N]

  def []: (Integer index) -> T
  def []=: (Integer index, T value) -> T
  def size: () -> Integer  # Returns N

  # Enumerable
  def each: () { (T) -> void } -> self
  def map: [U] () { (T) -> U } -> StaticArray[U, N]
  def reduce: (T initial) { (T, T) -> T } -> T

  # Conversion
  def to_slice: () -> Slice[T]
  def to_a: () -> Array[T]
end
```

**Implementation Notes:**
- LLVM: `alloca [N x T]` for stack allocation
- Size N is embedded in type, not runtime value
- No bounds checking needed if index is constant and in range
- Copy semantics (like Crystal struct)

**Use Cases:**
```ruby
# Fixed-size buffer for SIMD operations
buffer = StaticArray[Float, 4].new(0.0)

# Known-size lookup table
COEFFICIENTS = StaticArray[Float, 10].new { |i| i * 0.1 }

# Local scratch space without heap allocation
def process(data)
  temp = StaticArray[Integer, 256].new(0)
  # ... processing ...
end
```

### Slice[T] (New)

バウンドチェック付きポインタビュー。メモリの一部分への安全なアクセスを提供。

```ruby
# RBS Definition
class Slice[T]
  def self.new: (Integer size) -> Slice[T]
  def self.empty: () -> Slice[T]

  def []: (Integer index) -> T
  def []=: (Integer index, T value) -> T
  def size: () -> Integer

  # Sub-slicing (returns view, not copy)
  def []: (Range range) -> Slice[T]
  def []: (Integer start, Integer count) -> Slice[T]

  # Enumerable
  def each: () { (T) -> void } -> self
  def map: [U] () { (T) -> U } -> Slice[U]

  # Memory operations
  def copy_from: (Slice[T] source) -> self
  def fill: (T value) -> self

  # Safety
  def read_only?: () -> bool
  def read_only: () -> Slice[T]
end
```

**Relationship to NativeArray:**
```
NativeArray[T]  = owns memory, manages lifetime
Slice[T]        = borrows memory, no ownership
```

### Native String Operations (New)

パフォーマンスクリティカルな文字列操作のネイティブ実装。

```ruby
# RBS Definition
module NativeString
  # Fast ASCII check (for O(1) indexing optimization)
  def self.ascii_only?: (String s) -> bool

  # Direct byte access without encoding overhead
  def self.byte_at: (String s, Integer index) -> Integer
  def self.bytes: (String s) -> Slice[UInt8]

  # Efficient string building
  def self.build: (Integer capacity) { (StringBuffer) -> void } -> String

  # Pattern matching without regex overhead
  def self.index_of: (String haystack, String needle) -> Integer?
  def self.starts_with?: (String s, String prefix) -> bool
  def self.ends_with?: (String s, String suffix) -> bool
end

class StringBuffer
  def <<: (String s) -> self
  def <<: (Integer byte) -> self
  def to_s: () -> String
end
```

**Optimization Strategy:**
- ASCII文字列の判定結果をキャッシュ
- UTF-8デコードを必要な時だけ実行
- `String.build`でバッファサイズを事前確保

### Native Numeric Types (Future)

数値演算の最適化のための追加型。

```ruby
# Complex numbers (unboxed pair of Float)
class NativeComplex
  @real: Float
  @imag: Float

  def +: (NativeComplex other) -> NativeComplex
  def *: (NativeComplex other) -> NativeComplex
  def abs: () -> Float
  def conjugate: () -> NativeComplex
end

# Rational numbers (unboxed pair of Integer)
class NativeRational
  @num: Integer
  @den: Integer

  def +: (NativeRational other) -> NativeRational
  def *: (NativeRational other) -> NativeRational
  def to_f: () -> Float
end

# Fixed-point decimal (for financial calculations)
class NativeDecimal
  @value: Integer  # Scaled integer representation

  def +: (NativeDecimal other) -> NativeDecimal
  def round: (Integer places) -> NativeDecimal
end
```

## Implementation Priority

| Type | Complexity | Impact |
|------|------------|--------|
| NativeArray, NativeClass | Done | High |
| StaticArray[T, N] | Done | Medium |
| Slice[T] | Done | Medium |
| NativeString | Done (limited value) | Low |
| NativeComplex, NativeRational | Low | Low |

**Note on NativeString**: Implemented but benchmarks show it's 2-6x slower than Ruby String due to conversion overhead. Ruby's String is already highly optimized in C. NativeString is only beneficial for batch processing scenarios where the same string is operated on many times. For future stdlib (JSON, HTTP), using `@cfunc` to call C libraries directly is more effective.

## Memory Layout Examples

### StaticArray[Float, 4]
```
Stack:
┌────────────────────────────────────┐
│ Float64 │ Float64 │ Float64 │ Float64 │  32 bytes total
└────────────────────────────────────┘
```

### Slice[Float]
```
Stack:          Heap (or other allocation):
┌───────┬───────┐    ┌─────────────────────┐
│ ptr   │ size  │ -> │ Float64 │ Float64 │...│
└───────┴───────┘    └─────────────────────┘
  16 bytes             N * 8 bytes
```

### NativeString ASCII optimization
```
String object:
┌──────────┬────────────┬─────────────┐
│ ptr      │ bytesize   │ flags       │
└──────────┴────────────┴─────────────┘
                         └─ ASCII_ONLY bit

If ASCII_ONLY:
  string[i] = O(1) direct byte access
Else:
  string[i] = O(n) UTF-8 decode from start
```

## Benchmarking Goals

Based on Crystal's performance characteristics:

| Operation | Ruby | Konpeito Target | Crystal Reference |
|-----------|------|-----------------|-------------------|
| StaticArray iteration | N/A | 15-20x faster | 15x (struct) |
| Slice bounds check | N/A | <5% overhead | ~3% overhead |
| ASCII string index | 1x | 5-10x faster | ~8x faster |
| String.build | 1x | 2-3x faster | ~1.4x faster |

## Integration with Existing Konpeito Features

### @simd for StaticArray
```ruby
# @simd
class Vector4 < StaticArray[Float, 4]
  def dot: (Vector4 other) -> Float
end
```

### NativeArray[NativeClass]
Already supported - enables particle systems, physics simulations.

### Fiber + NativeString
Efficient request parsing in HTTP server example.

## Migration Path from Ruby

```ruby
# Ruby code
data = [1.0, 2.0, 3.0, 4.0]
sum = data.reduce(0.0) { |acc, x| acc + x }

# Konpeito optimized (drop-in replacement with RBS)
# RBS: data: NativeArray[Float]
data = NativeArray.new(4)
data[0] = 1.0; data[1] = 2.0; data[2] = 3.0; data[3] = 4.0
sum = data.reduce(0.0) { |acc, x| acc + x }  # 8-10x faster
```

## References

- [Crystal Performance Guide](https://crystal-lang.org/reference/1.19/guides/performance.html)
- [Crystal StaticArray API](https://crystal-lang.org/api/1.18.2/StaticArray.html)
- [Crystal Slice API](https://crystal-lang.org/api/1.17.1/Slice.html)
- [Crystal Struct vs Class](https://crystal-lang.org/reference/1.19/syntax_and_semantics/structs.html)
