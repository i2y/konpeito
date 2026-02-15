# frozen_string_literal: true

# Benchmark: NativeArray vs Ruby Array
# Usage: bundle exec ruby benchmark/native_array_bench.rb
#
# This benchmark compares:
# - Pure Ruby loops with Ruby Arrays
# - Native compiled code with NativeArray[Float64] (unboxed, contiguous memory)
#
# Expected: 5-10x speedup with NativeArray due to:
# - No boxing/unboxing overhead
# - Cache-friendly contiguous memory layout
# - Direct double* pointer access vs VALUE array

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# NativeArray sum - uses unboxed Float64 throughout
# The loop stays in native code with direct memory access
NATIVE_SOURCE = <<~RUBY
  def native_sum(n)
    # Allocate NativeArray[Float64]
    arr = NativeArray.new(n)

    # Fill with values (unboxed)
    i = 0
    while i < n
      arr[i] = i * 1.5
      i = i + 1
    end

    # Sum (unboxed arithmetic)
    total = 0.0
    i = 0
    while i < n
      total = total + arr[i]
      i = i + 1
    end

    total
  end

  def native_dot_product(n)
    # Two arrays for dot product
    arr1 = NativeArray.new(n)
    arr2 = NativeArray.new(n)

    # Fill arrays
    i = 0
    while i < n
      arr1[i] = i * 1.0
      arr2[i] = i * 2.0
      i = i + 1
    end

    # Compute dot product
    result = 0.0
    i = 0
    while i < n
      result = result + arr1[i] * arr2[i]
      i = i + 1
    end

    result
  end
RUBY

NATIVE_RBS = <<~RBS
  # NativeArray is a special type handled by konpeito
  # NativeArray[Float] maps to contiguous double* memory
  class NativeArray[T]
    def self.new: (Integer size) -> NativeArray[Float]
    def []: (Integer index) -> Float
    def []=: (Integer index, Float value) -> Float
    def length: () -> Integer
  end

  # TopLevel module for top-level method type annotations
  # This enables unboxed arithmetic for loop conditions and parameters
  module TopLevel
    def native_sum: (Integer n) -> Float
    def native_dot_product: (Integer n) -> Float
  end
RBS

def compile_native(source, rbs, name)
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "#{name}_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "#{name}_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "#{name}_#{timestamp}.bundle")

  File.write(source_path, source)
  File.write(rbs_path, rbs)

  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    format: :cruby_ext,
    rbs_paths: [rbs_path],
    optimize: true,
    verbose: false
  ).compile

  # Cleanup source files
  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil

  output_path
end

# Pure Ruby implementations for comparison
module PureRuby
  def self.ruby_sum(n)
    arr = Array.new(n)

    # Fill with values
    i = 0
    while i < n
      arr[i] = i * 1.5
      i = i + 1
    end

    # Sum
    total = 0.0
    i = 0
    while i < n
      total = total + arr[i]
      i = i + 1
    end

    total
  end

  def self.ruby_dot_product(n)
    arr1 = Array.new(n)
    arr2 = Array.new(n)

    # Fill arrays
    i = 0
    while i < n
      arr1[i] = i * 1.0
      arr2[i] = i * 2.0
      i = i + 1
    end

    # Compute dot product
    result = 0.0
    i = 0
    while i < n
      result = result + arr1[i] * arr2[i]
      i = i + 1
    end

    result
  end

  # Idiomatic Ruby using each
  def self.ruby_sum_idiomatic(n)
    arr = (0...n).map { |i| i * 1.5 }
    arr.sum
  end

  def self.ruby_dot_product_idiomatic(n)
    arr1 = (0...n).map { |i| i * 1.0 }
    arr2 = (0...n).map { |i| i * 2.0 }
    arr1.zip(arr2).map { |a, b| a * b }.sum
  end
end

puts "Compiling NativeArray extension..."
begin
  native_bundle = compile_native(NATIVE_SOURCE, NATIVE_RBS, "native_array_bench")
  require native_bundle
  $native_obj = Object.new

  module Native
    class << self
      define_method(:native_sum) { |n| $native_obj.send(:native_sum, n) }
      define_method(:native_dot_product) { |n| $native_obj.send(:native_dot_product, n) }
    end
  end

  puts "Compiled: #{native_bundle}"
  puts

  # Test sizes
  sizes = [100, 1000, 10000]

  sizes.each do |n|
    puts "=" * 60
    puts "Verifying correctness for n=#{n}..."

    ruby_result = PureRuby.ruby_sum(n)
    native_result = Native.native_sum(n)
    diff = (ruby_result - native_result).abs
    if diff > 0.001
      puts "WARNING: Sum mismatch! Ruby=#{ruby_result}, Native=#{native_result}, diff=#{diff}"
    else
      puts "Sum results match: #{ruby_result.round(2)}"
    end

    ruby_result = PureRuby.ruby_dot_product(n)
    native_result = Native.native_dot_product(n)
    diff = (ruby_result - native_result).abs
    if diff > 0.001
      puts "WARNING: Dot product mismatch! Ruby=#{ruby_result}, Native=#{native_result}, diff=#{diff}"
    else
      puts "Dot product results match: #{ruby_result.round(2)}"
    end
    puts
  end

  n = 10000
  puts "=" * 60
  puts "Benchmark: Array Sum (n=#{n})"
  puts "=" * 60
  Benchmark.ips do |x|
    x.report("Ruby while-loop") { PureRuby.ruby_sum(n) }
    x.report("Ruby idiomatic") { PureRuby.ruby_sum_idiomatic(n) }
    x.report("NativeArray") { Native.native_sum(n) }
    x.compare!
  end

  puts
  puts "=" * 60
  puts "Benchmark: Dot Product (n=#{n})"
  puts "=" * 60
  Benchmark.ips do |x|
    x.report("Ruby while-loop") { PureRuby.ruby_dot_product(n) }
    x.report("Ruby idiomatic") { PureRuby.ruby_dot_product_idiomatic(n) }
    x.report("NativeArray") { Native.native_dot_product(n) }
    x.compare!
  end

  # Cleanup
  File.unlink(native_bundle) rescue nil
rescue StandardError => e
  puts "Error during compilation or execution:"
  puts e.message
  puts e.backtrace.first(10).join("\n")
  exit 1
end
