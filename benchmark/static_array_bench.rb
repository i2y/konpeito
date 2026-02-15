#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark for StaticArray vs NativeArray vs Ruby Array
# StaticArray: Stack-allocated, fixed size, no GC pressure
# NativeArray: Heap-allocated, dynamic size
# Ruby Array: Standard Ruby array

require "benchmark/ips"
require "tempfile"
require "fileutils"

puts "=" * 60
puts "StaticArray vs NativeArray vs Ruby Array Benchmark"
puts "=" * 60

# Create temporary directory for compilation
tmp_dir = Dir.mktmpdir

# Write Ruby source with both StaticArray and NativeArray
source = <<~RUBY
  # StaticArray sum - stack allocated
  def static_array_sum_4
    arr = StaticArray4Float.new
    arr[0] = 1.0
    arr[1] = 2.0
    arr[2] = 3.0
    arr[3] = 4.0

    total = 0.0
    i = 0
    while i < 4
      total = total + arr[i]
      i = i + 1
    end
    total
  end

  # StaticArray larger - 16 elements
  def static_array_sum_16
    arr = StaticArray16Float.new(1.0)

    total = 0.0
    i = 0
    while i < 16
      total = total + arr[i]
      i = i + 1
    end
    total
  end

  # NativeArray sum - heap allocated
  def native_array_sum_4
    arr = NativeArray.new(4)
    arr[0] = 1.0
    arr[1] = 2.0
    arr[2] = 3.0
    arr[3] = 4.0

    total = 0.0
    i = 0
    while i < 4
      total = total + arr[i]
      i = i + 1
    end
    total
  end

  # NativeArray larger - 16 elements
  def native_array_sum_16
    arr = NativeArray.new(16)
    i = 0
    while i < 16
      arr[i] = 1.0
      i = i + 1
    end

    total = 0.0
    i = 0
    while i < 16
      total = total + arr[i]
      i = i + 1
    end
    total
  end

  # Benchmark wrapper - run iterations internally
  def bench_static_4(iterations)
    i = 0
    while i < iterations
      static_array_sum_4
      i = i + 1
    end
    iterations
  end

  def bench_static_16(iterations)
    i = 0
    while i < iterations
      static_array_sum_16
      i = i + 1
    end
    iterations
  end

  def bench_native_4(iterations)
    i = 0
    while i < iterations
      native_array_sum_4
      i = i + 1
    end
    iterations
  end

  def bench_native_16(iterations)
    i = 0
    while i < iterations
      native_array_sum_16
      i = i + 1
    end
    iterations
  end
RUBY

# RBS type definitions
rbs_content = <<~RBS
  # @native
  class StaticArray4Float
    def self.new: () -> StaticArray4Float
                | (Float value) -> StaticArray4Float
    def []: (Integer index) -> Float
    def []=: (Integer index, Float value) -> Float
    def size: () -> Integer
  end

  # @native
  class StaticArray16Float
    def self.new: () -> StaticArray16Float
                | (Float value) -> StaticArray16Float
    def []: (Integer index) -> Float
    def []=: (Integer index, Float value) -> Float
    def size: () -> Integer
  end

  # @native
  class NativeArray
    def self.new: (Integer size) -> NativeArray
    def []: (Integer index) -> Float
    def []=: (Integer index, Float value) -> Float
    def length: () -> Integer
  end

  module TopLevel
    def static_array_sum_4: () -> Float
    def static_array_sum_16: () -> Float
    def native_array_sum_4: () -> Float
    def native_array_sum_16: () -> Float
    def bench_static_4: (Integer iterations) -> Integer
    def bench_static_16: (Integer iterations) -> Integer
    def bench_native_4: (Integer iterations) -> Integer
    def bench_native_16: (Integer iterations) -> Integer
  end
RBS

# Write files
source_file = File.join(tmp_dir, "bench.rb")
rbs_file = File.join(tmp_dir, "bench.rbs")
output_file = File.join(tmp_dir, "bench.bundle")

File.write(source_file, source)
File.write(rbs_file, rbs_content)

# Compile
require "konpeito"
compiler = Konpeito::Compiler.new(
  source_file: source_file,
  output_file: output_file,
  rbs_paths: [rbs_file]
)
compiler.compile

# Load compiled bundle
require output_file

# Pure Ruby implementations for comparison
def ruby_array_sum_4
  arr = [1.0, 2.0, 3.0, 4.0]
  total = 0.0
  i = 0
  while i < 4
    total = total + arr[i]
    i = i + 1
  end
  total
end

def ruby_array_sum_16
  arr = Array.new(16, 1.0)
  total = 0.0
  i = 0
  while i < 16
    total = total + arr[i]
    i = i + 1
  end
  total
end

def bench_ruby_4(iterations)
  i = 0
  while i < iterations
    ruby_array_sum_4
    i = i + 1
  end
  iterations
end

def bench_ruby_16(iterations)
  i = 0
  while i < iterations
    ruby_array_sum_16
    i = i + 1
  end
  iterations
end

# Verify results
puts "\nVerification:"
puts "static_array_sum_4:  #{static_array_sum_4}"
puts "static_array_sum_16: #{static_array_sum_16}"
puts "native_array_sum_4:  #{native_array_sum_4}"
puts "native_array_sum_16: #{native_array_sum_16}"
puts "ruby_array_sum_4:    #{ruby_array_sum_4}"
puts "ruby_array_sum_16:   #{ruby_array_sum_16}"

iterations = 10_000

puts "\n" + "=" * 60
puts "Internal Benchmark (#{iterations} iterations per call)"
puts "=" * 60

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("StaticArray[4] sum") { bench_static_4(iterations) }
  x.report("NativeArray[4] sum") { bench_native_4(iterations) }
  x.report("Ruby Array[4] sum") { bench_ruby_4(iterations) }

  x.compare!
end

puts "\n" + "=" * 60
puts "Internal Benchmark - 16 elements (#{iterations} iterations)"
puts "=" * 60

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("StaticArray[16] sum") { bench_static_16(iterations) }
  x.report("NativeArray[16] sum") { bench_native_16(iterations) }
  x.report("Ruby Array[16] sum") { bench_ruby_16(iterations) }

  x.compare!
end

# Cleanup
FileUtils.rm_rf(tmp_dir)

puts "\n" + "=" * 60
puts "Summary"
puts "=" * 60
puts "StaticArray: Stack-allocated (alloca), no heap, no GC"
puts "NativeArray: Heap-allocated (alloca for large arrays)"
puts "Ruby Array: Standard boxed array with GC overhead"
