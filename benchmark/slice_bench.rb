# frozen_string_literal: true

# Benchmark for Slice[T] operations
# Compare Slice vs Ruby Array operations

require "benchmark/ips"
require "konpeito"
require "tempfile"
require "fileutils"

def create_slice_benchmark
  tmp_dir = Dir.mktmpdir
  source_file = File.join(tmp_dir, "slice_bench.rb")
  output_file = File.join(tmp_dir, "slice_bench.bundle")
  rbs_file = File.join(tmp_dir, "slice_bench.rbs")

  source = <<~RUBY
    def slice_sum(n)
      s = SliceInt64.new(n)
      i = 0
      while i < n
        s[i] = i
        i = i + 1
      end

      total = 0
      i = 0
      while i < s.size
        total = total + s[i]
        i = i + 1
      end
      total
    end

    def slice_fill_and_sum(n)
      s = SliceInt64.new(n)
      s.fill(42)

      total = 0
      i = 0
      while i < s.size
        total = total + s[i]
        i = i + 1
      end
      total
    end

    def slice_copy_sum(n)
      src = SliceInt64.new(n)
      i = 0
      while i < n
        src[i] = i * 2
        i = i + 1
      end

      dest = SliceInt64.new(n)
      dest.copy_from(src)

      total = 0
      i = 0
      while i < dest.size
        total = total + dest[i]
        i = i + 1
      end
      total
    end

    def slice_subslice_sum(n)
      s = SliceInt64.new(n)
      i = 0
      while i < n
        s[i] = i
        i = i + 1
      end

      # Sum middle half
      start_idx = n / 4
      count = n / 2
      sub = s[start_idx, count]

      total = 0
      i = 0
      while i < sub.size
        total = total + sub[i]
        i = i + 1
      end
      total
    end

    def slice_float_sum(n)
      s = SliceFloat64.new(n)
      i = 0
      while i < n
        s[i] = i * 1.5
        i = i + 1
      end

      total = 0.0
      i = 0
      while i < s.size
        total = total + s[i]
        i = i + 1
      end
      total
    end

    # Inner benchmark loops
    def bench_slice_sum(iterations, n)
      i = 0
      while i < iterations
        slice_sum(n)
        i = i + 1
      end
      i
    end

    def bench_slice_fill(iterations, n)
      i = 0
      while i < iterations
        slice_fill_and_sum(n)
        i = i + 1
      end
      i
    end

    def bench_slice_copy(iterations, n)
      i = 0
      while i < iterations
        slice_copy_sum(n)
        i = i + 1
      end
      i
    end

    def bench_slice_subslice(iterations, n)
      i = 0
      while i < iterations
        slice_subslice_sum(n)
        i = i + 1
      end
      i
    end

    def bench_slice_float(iterations, n)
      i = 0
      while i < iterations
        slice_float_sum(n)
        i = i + 1
      end
      i
    end
  RUBY

  rbs = <<~RBS
    # @native
    class SliceInt64
      def self.new: (Integer size) -> SliceInt64
      def self.empty: () -> SliceInt64
      def []: (Integer index) -> Integer
      def []=: (Integer index, Integer value) -> Integer
      def []: (Integer start, Integer count) -> SliceInt64
      def size: () -> Integer
      def copy_from: (SliceInt64 source) -> SliceInt64
      def fill: (Integer value) -> SliceInt64
    end

    # @native
    class SliceFloat64
      def self.new: (Integer size) -> SliceFloat64
      def self.empty: () -> SliceFloat64
      def []: (Integer index) -> Float
      def []=: (Integer index, Float value) -> Float
      def []: (Integer start, Integer count) -> SliceFloat64
      def size: () -> Integer
      def copy_from: (SliceFloat64 source) -> SliceFloat64
      def fill: (Float value) -> SliceFloat64
    end

    module TopLevel
      def slice_sum: (Integer n) -> Integer
      def slice_fill_and_sum: (Integer n) -> Integer
      def slice_copy_sum: (Integer n) -> Integer
      def slice_subslice_sum: (Integer n) -> Integer
      def slice_float_sum: (Integer n) -> Float
      def bench_slice_sum: (Integer iterations, Integer n) -> Integer
      def bench_slice_fill: (Integer iterations, Integer n) -> Integer
      def bench_slice_copy: (Integer iterations, Integer n) -> Integer
      def bench_slice_subslice: (Integer iterations, Integer n) -> Integer
      def bench_slice_float: (Integer iterations, Integer n) -> Integer
    end
  RBS

  File.write(source_file, source)
  File.write(rbs_file, rbs)

  compiler = Konpeito::Compiler.new(
    source_file: source_file,
    output_file: output_file,
    rbs_paths: [rbs_file]
  )
  compiler.compile

  require output_file

  [tmp_dir, output_file]
end

# Pure Ruby equivalents
def ruby_array_sum(n)
  arr = Array.new(n) { |i| i }
  total = 0
  i = 0
  while i < arr.size
    total = total + arr[i]
    i = i + 1
  end
  total
end

def ruby_array_fill_sum(n)
  arr = Array.new(n, 42)
  total = 0
  i = 0
  while i < arr.size
    total = total + arr[i]
    i = i + 1
  end
  total
end

def ruby_array_copy_sum(n)
  src = Array.new(n) { |i| i * 2 }
  dest = src.dup
  total = 0
  i = 0
  while i < dest.size
    total = total + dest[i]
    i = i + 1
  end
  total
end

def ruby_array_subslice_sum(n)
  arr = Array.new(n) { |i| i }
  start_idx = n / 4
  count = n / 2
  sub = arr[start_idx, count]
  total = 0
  i = 0
  while i < sub.size
    total = total + sub[i]
    i = i + 1
  end
  total
end

def ruby_array_float_sum(n)
  arr = Array.new(n) { |i| i * 1.5 }
  total = 0.0
  i = 0
  while i < arr.size
    total = total + arr[i]
    i = i + 1
  end
  total
end

# Inner benchmark loops for Ruby
def bench_ruby_sum(iterations, n)
  i = 0
  while i < iterations
    ruby_array_sum(n)
    i = i + 1
  end
  i
end

def bench_ruby_fill(iterations, n)
  i = 0
  while i < iterations
    ruby_array_fill_sum(n)
    i = i + 1
  end
  i
end

def bench_ruby_copy(iterations, n)
  i = 0
  while i < iterations
    ruby_array_copy_sum(n)
    i = i + 1
  end
  i
end

def bench_ruby_subslice(iterations, n)
  i = 0
  while i < iterations
    ruby_array_subslice_sum(n)
    i = i + 1
  end
  i
end

def bench_ruby_float(iterations, n)
  i = 0
  while i < iterations
    ruby_array_float_sum(n)
    i = i + 1
  end
  i
end

puts "Compiling Slice benchmark..."
tmp_dir, _ = create_slice_benchmark

puts "\n=== Slice[T] Benchmark ==="
puts "Comparing Slice[T] vs Ruby Array operations"
puts

n = 1000
iterations = 1000

puts "--- Internal Benchmark (#{iterations} iterations x #{n} elements) ---"
puts

# Verify correctness first
puts "Verifying correctness..."
slice_result = slice_sum(n)
ruby_result = ruby_array_sum(n)
expected = (0...n).sum
puts "  slice_sum(#{n}) = #{slice_result} (expected: #{expected})"
puts "  ruby_array_sum(#{n}) = #{ruby_result}"
raise "Mismatch!" unless slice_result == expected && ruby_result == expected
puts "  OK!"
puts

# Internal benchmarks (loop inside native code)
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby Array sum") do
    bench_ruby_sum(iterations, n)
  end

  x.report("Slice[Int64] sum") do
    bench_slice_sum(iterations, n)
  end

  x.compare!
end

puts
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby Array fill+sum") do
    bench_ruby_fill(iterations, n)
  end

  x.report("Slice[Int64] fill+sum") do
    bench_slice_fill(iterations, n)
  end

  x.compare!
end

puts
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby Array copy+sum") do
    bench_ruby_copy(iterations, n)
  end

  x.report("Slice[Int64] copy+sum") do
    bench_slice_copy(iterations, n)
  end

  x.compare!
end

puts
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby Array subslice") do
    bench_ruby_subslice(iterations, n)
  end

  x.report("Slice[Int64] subslice") do
    bench_slice_subslice(iterations, n)
  end

  x.compare!
end

puts
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby Array Float") do
    bench_ruby_float(iterations, n)
  end

  x.report("Slice[Float64] sum") do
    bench_slice_float(iterations, n)
  end

  x.compare!
end

# Cleanup
FileUtils.rm_rf(tmp_dir)

puts
puts "=== Benchmark Complete ==="
