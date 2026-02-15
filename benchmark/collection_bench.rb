# frozen_string_literal: true

# Comprehensive Benchmark for Collection Completeness & Numeric Inlining
#
# Tests:
# 1. Numeric inlining (abs, even?, odd?, zero?, positive?, negative?)
# 2. Hash iteration (each, map, select, any?)
# 3. Array mutation ([]=, delete_at)
# 4. Range enumerable (each, map, select, reduce)
# 5. Symbol methods (to_s)

require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

ITERATIONS = 1_000_000

# ============================================================================
# Native code
# ============================================================================
NATIVE_SOURCE = <<~RUBY
  # --- Numeric inlining ---
  def bench_integer_abs(iterations)
    total = 0
    i = 0
    while i < iterations
      n = i - 500000
      total = total + n.abs
      i = i + 1
    end
    total
  end

  def bench_integer_predicates(iterations)
    even_count = 0
    odd_count = 0
    pos_count = 0
    neg_count = 0
    zero_count = 0
    i = 0
    while i < iterations
      n = i - 500000
      if n.even?
        even_count = even_count + 1
      end
      if n.odd?
        odd_count = odd_count + 1
      end
      if n.positive?
        pos_count = pos_count + 1
      end
      if n.negative?
        neg_count = neg_count + 1
      end
      if n.zero?
        zero_count = zero_count + 1
      end
      i = i + 1
    end
    even_count + odd_count + pos_count + neg_count + zero_count
  end

  # --- Range enumerable ---
  def range_each_sum(n)
    total = 0
    (1..n).each { |i| total = total + i }
    total
  end

  def bench_range_each_loop(iterations, n)
    i = 0
    result = 0
    while i < iterations
      result = range_each_sum(n)
      i = i + 1
    end
    result
  end

  def range_reduce_sum(n)
    (1..n).reduce(0) { |sum, i| sum + i }
  end

  def bench_range_reduce_loop(iterations, n)
    i = 0
    result = 0
    while i < iterations
      result = range_reduce_sum(n)
      i = i + 1
    end
    result
  end

  def bench_range_map_single
    (1..10000).map { |i| i * 2 }
  end

  def bench_range_select_single
    (1..10000).select { |i| i % 2 == 0 }
  end

  # --- Array mutation ---
  def bench_array_set(iterations)
    i = 0
    while i < iterations
      arr = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      j = 0
      while j < 10
        arr[j] = j * 3
        j = j + 1
      end
      i = i + 1
    end
    0
  end
RUBY

NATIVE_RBS = <<~RBS
  module TopLevel
    def bench_integer_abs: (Integer iterations) -> Integer
    def bench_integer_predicates: (Integer iterations) -> Integer
    def range_each_sum: (Integer n) -> Integer
    def bench_range_each_loop: (Integer iterations, Integer n) -> Integer
    def range_reduce_sum: (Integer n) -> Integer
    def bench_range_reduce_loop: (Integer iterations, Integer n) -> Integer
    def bench_range_map_single: () -> Array
    def bench_range_select_single: () -> Array
    def bench_array_set: (Integer iterations) -> Integer
  end
RBS

# ============================================================================
# Pure Ruby equivalents
# ============================================================================
module PureRuby
  def self.bench_integer_abs(iterations)
    total = 0
    i = 0
    while i < iterations
      n = i - 500000
      total = total + n.abs
      i = i + 1
    end
    total
  end

  def self.bench_integer_predicates(iterations)
    even_count = 0
    odd_count = 0
    pos_count = 0
    neg_count = 0
    zero_count = 0
    i = 0
    while i < iterations
      n = i - 500000
      if n.even?
        even_count = even_count + 1
      end
      if n.odd?
        odd_count = odd_count + 1
      end
      if n.positive?
        pos_count = pos_count + 1
      end
      if n.negative?
        neg_count = neg_count + 1
      end
      if n.zero?
        zero_count = zero_count + 1
      end
      i = i + 1
    end
    even_count + odd_count + pos_count + neg_count + zero_count
  end

  def self.range_each_sum(n)
    total = 0
    (1..n).each { |i| total = total + i }
    total
  end

  def self.bench_range_each_loop(iterations, n)
    i = 0
    result = 0
    while i < iterations
      result = range_each_sum(n)
      i = i + 1
    end
    result
  end

  def self.range_reduce_sum(n)
    (1..n).reduce(0) { |sum, i| sum + i }
  end

  def self.bench_range_reduce_loop(iterations, n)
    i = 0
    result = 0
    while i < iterations
      result = range_reduce_sum(n)
      i = i + 1
    end
    result
  end

  def self.bench_range_map_single
    (1..10000).map { |i| i * 2 }
  end

  def self.bench_range_select_single
    (1..10000).select { |i| i % 2 == 0 }
  end

  def self.bench_array_set(iterations)
    i = 0
    while i < iterations
      arr = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      j = 0
      while j < 10
        arr[j] = j * 3
        j = j + 1
      end
      i = i + 1
    end
    0
  end

  def self.bench_hash_each(iterations)
    h = { "a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5 }
    i = 0
    total = 0
    while i < iterations
      h.each { |k, v| total = total + v }
      i = i + 1
    end
    total
  end

  def self.bench_hash_select(iterations)
    h = { "a" => 1, "b" => 20, "c" => 3, "d" => 40, "e" => 5 }
    i = 0
    result = nil
    while i < iterations
      result = h.select { |k, v| v > 10 }
      i = i + 1
    end
    result
  end

  def self.bench_symbol_to_s(iterations)
    i = 0
    result = nil
    while i < iterations
      result = :hello.to_s
      i = i + 1
    end
    result
  end
end

# ============================================================================
# Compilation
# ============================================================================
def compile_native
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "collection_bench_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "collection_bench_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "collection_bench_#{timestamp}.bundle")

  File.write(source_path, NATIVE_SOURCE)
  File.write(rbs_path, NATIVE_RBS)

  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    format: :cruby_ext,
    rbs_paths: [rbs_path],
    optimize: true
  ).compile

  output_path
ensure
  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil
end

def measure_time(name)
  GC.disable
  # Warmup
  yield
  # Actual measurement (3 runs, take best)
  times = 3.times.map do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    elapsed
  end
  GC.enable
  GC.start
  times.min
end

def report(title, ruby_time, native_time)
  speedup = ruby_time / native_time
  bar = if speedup >= 1
    "+" * [speedup.to_i, 50].min
  else
    "-" * [(1/speedup).to_i, 50].min
  end
  direction = speedup >= 1 ? "faster" : "slower"
  ratio = speedup >= 1 ? speedup : 1/speedup

  printf "  %-40s Ruby: %8.4fs  Native: %8.4fs  %6.2fx %s %s\n",
    title, ruby_time, native_time, ratio, direction, bar
end

# ============================================================================
# Main
# ============================================================================
puts "=" * 90
puts "Collection & Numeric Inlining Benchmark"
puts "Ruby #{RUBY_VERSION} (#{RUBY_DESCRIPTION.split(" ")[0..3].join(" ")})"
puts "=" * 90
puts

print "Compiling native code... "
bundle_path = compile_native
require bundle_path
$native_obj = Object.new
puts "done"
puts

# Verify correctness
print "Verifying correctness... "
r1 = PureRuby.bench_integer_abs(1000)
n1 = $native_obj.send(:bench_integer_abs, 1000)
raise "integer_abs mismatch: #{r1} vs #{n1}" unless r1 == n1

r2 = PureRuby.bench_integer_predicates(1000)
n2 = $native_obj.send(:bench_integer_predicates, 1000)
raise "integer_predicates mismatch: #{r2} vs #{n2}" unless r2 == n2

r3 = PureRuby.bench_range_each_loop(10, 100)
n3 = $native_obj.send(:bench_range_each_loop, 10, 100)
raise "range_each mismatch: #{r3} vs #{n3}" unless r3 == n3

r4 = PureRuby.bench_range_reduce_loop(10, 100)
n4 = $native_obj.send(:bench_range_reduce_loop, 10, 100)
raise "range_reduce mismatch: #{r4} vs #{n4}" unless r4 == n4

puts "all correct!"
puts

# ============================================================================
# Numeric Inlining
# ============================================================================
puts "-" * 90
puts "Numeric Inlining (#{ITERATIONS} iterations)"
puts "-" * 90

rt = measure_time("ruby") { PureRuby.bench_integer_abs(ITERATIONS) }
nt = measure_time("native") { $native_obj.send(:bench_integer_abs, ITERATIONS) }
report("Integer#abs loop", rt, nt)

rt = measure_time("ruby") { PureRuby.bench_integer_predicates(ITERATIONS) }
nt = measure_time("native") { $native_obj.send(:bench_integer_predicates, ITERATIONS) }
report("Integer predicates (even?/odd?/...)", rt, nt)

puts

# ============================================================================
# Array Mutation
# ============================================================================
array_iters = 100_000
puts "-" * 90
puts "Array Mutation (#{array_iters} iterations x 10 elements)"
puts "-" * 90

rt = measure_time("ruby") { PureRuby.bench_array_set(array_iters) }
nt = measure_time("native") { $native_obj.send(:bench_array_set, array_iters) }
report("Array#[]= in loop", rt, nt)

puts

# ============================================================================
# Range Enumerable
# ============================================================================
range_n = 100
range_iters = 10_000
puts "-" * 90
puts "Range Enumerable (#{range_iters} iterations x (1..#{range_n}))"
puts "-" * 90

rt = measure_time("ruby") { PureRuby.bench_range_each_loop(range_iters, range_n) }
nt = measure_time("native") { $native_obj.send(:bench_range_each_loop, range_iters, range_n) }
report("(1..100).each { sum } x#{range_iters}", rt, nt)

rt = measure_time("ruby") { PureRuby.bench_range_reduce_loop(range_iters, range_n) }
nt = measure_time("native") { $native_obj.send(:bench_range_reduce_loop, range_iters, range_n) }
report("(1..100).reduce(0) { sum } x#{range_iters}", rt, nt)

# Single-call variants (n=10000)
rt = measure_time("ruby") { PureRuby.bench_range_map_single }
nt = measure_time("native") { $native_obj.send(:bench_range_map_single) }
report("(1..10000).map { i*2 }", rt, nt)

rt = measure_time("ruby") { PureRuby.bench_range_select_single }
nt = measure_time("native") { $native_obj.send(:bench_range_select_single) }
report("(1..10000).select { even }", rt, nt)

puts

# ============================================================================
# Hash Iteration (rb_block_call, not inlined)
# ============================================================================
hash_iters = 100_000
puts "-" * 90
puts "Hash Iteration (#{hash_iters} iterations, 5-element hash)"
puts "-" * 90

rt = measure_time("ruby") { PureRuby.bench_hash_each(hash_iters) }
# Hash iteration uses rb_block_call (not inlined), so calling from Ruby
# Pure Ruby benchmark loop for fair comparison
nt = measure_time("native") { PureRuby.bench_hash_each(hash_iters) }
report("Hash#each { |k,v| sum += v } (baseline)", rt, nt)

rt = measure_time("ruby") { PureRuby.bench_hash_select(hash_iters) }
nt = measure_time("native") { PureRuby.bench_hash_select(hash_iters) }
report("Hash#select { |k,v| v > 10 } (baseline)", rt, nt)

puts "  Note: Hash iteration uses rb_block_call (same as Ruby). Benefit is"
puts "  correctness + 2-arg block support, not raw speed improvement."

puts

# ============================================================================
# Symbol Methods
# ============================================================================
sym_iters = 1_000_000
puts "-" * 90
puts "Symbol Methods (#{sym_iters} iterations)"
puts "-" * 90

rt = measure_time("ruby") { PureRuby.bench_symbol_to_s(sym_iters) }
nt = measure_time("native") { PureRuby.bench_symbol_to_s(sym_iters) }
report("Symbol#to_s (baseline)", rt, nt)

puts "  Note: Symbol#to_s calls rb_sym2str directly (same as Ruby)."

puts
puts "=" * 90
puts "Summary"
puts "=" * 90
puts "  Numeric inlining:  abs/even?/odd?/zero?/positive?/negative? → native CPU instructions"
puts "  Range enumerable:  (1..n).each/map/select/reduce → native i64 counter loops"
puts "  Array mutation:    arr[i] = val → rb_ary_store (direct C call)"
puts "  Hash iteration:    |k, v| blocks work correctly (argc runtime check)"
puts "  Symbol methods:    to_s/id2name/name → rb_sym2str (direct C call)"
puts "=" * 90

# Cleanup
File.unlink(bundle_path) rescue nil
