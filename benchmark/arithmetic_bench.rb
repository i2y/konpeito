# frozen_string_literal: true

# Benchmark: Compare native compiled code vs pure Ruby
# Usage: bundle exec ruby benchmark/arithmetic_bench.rb
#
# NOTE: Ruby 4.0's YJIT is extremely optimized for arithmetic operations.
# The CRuby extension approach has overhead from:
# - C function call dispatch
# - Boxing/unboxing (rb_num2long / rb_int2inum)
#
# The real advantage of AOT compilation will be in:
# - Startup time (no JIT warmup)
# - Standalone executables (future work)
# - Complex loops where we can avoid repeated boxing/unboxing

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source code to benchmark (straight-line code, no loops to avoid SSA issues)
BENCH_SOURCE = <<~RUBY
  def multiply_add(a, b, c)
    a * b + c
  end

  def compute_chain(x)
    y = x * 2
    z = y + 10
    w = z * 3
    w - x
  end

  def arithmetic_expr(a, b, c, d)
    (a + b) * (c - d) + (a * d) - (b / 2)
  end

  def bitwise_ops(a, b)
    (a << 2) | (b >> 1) ^ (a & b)
  end
RUBY

# TopLevel module pattern for unboxed arithmetic optimization
BENCH_RBS = <<~RBS
module TopLevel
  def multiply_add: (Integer a, Integer b, Integer c) -> Integer
  def compute_chain: (Integer x) -> Integer
  def arithmetic_expr: (Integer a, Integer b, Integer c, Integer d) -> Integer
  def bitwise_ops: (Integer a, Integer b) -> Integer
end
RBS

def compile_native(optimize:)
  # Use project's tmp directory to avoid permission issues
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "bench_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "bench_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "bench_#{timestamp}.bundle")

  File.write(source_path, BENCH_SOURCE)
  File.write(rbs_path, BENCH_RBS)

  # Compile
  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    format: :cruby_ext,
    rbs_paths: [rbs_path],
    optimize: optimize
  ).compile

  output_path
ensure
  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil
end

# Pure Ruby implementations for comparison
module PureRuby
  def self.multiply_add(a, b, c)
    a * b + c
  end

  def self.compute_chain(x)
    y = x * 2
    z = y + 10
    w = z * 3
    w - x
  end

  def self.arithmetic_expr(a, b, c, d)
    (a + b) * (c - d) + (a * d) - (b / 2)
  end

  def self.bitwise_ops(a, b)
    (a << 2) | (b >> 1) ^ (a & b)
  end
end

puts "Compiling optimized native extension..."
optimized_bundle = compile_native(optimize: true)
require optimized_bundle

# Create a single instance to avoid Object.new overhead
$native_obj = Object.new

# Store optimized versions (using send to call private methods)
module Optimized
  class << self
    define_method(:multiply_add) { |a, b, c| $native_obj.send(:multiply_add, a, b, c) }
    define_method(:compute_chain) { |x| $native_obj.send(:compute_chain, x) }
    define_method(:arithmetic_expr) { |a, b, c, d| $native_obj.send(:arithmetic_expr, a, b, c, d) }
    define_method(:bitwise_ops) { |a, b| $native_obj.send(:bitwise_ops, a, b) }
  end
end

puts "Compiled: #{optimized_bundle}"
puts

# Verify correctness
puts "Verifying correctness..."
raise "multiply_add mismatch" unless PureRuby.multiply_add(10, 20, 5) == Optimized.multiply_add(10, 20, 5)
raise "compute_chain mismatch" unless PureRuby.compute_chain(100) == Optimized.compute_chain(100)
raise "arithmetic_expr mismatch" unless PureRuby.arithmetic_expr(10, 20, 30, 5) == Optimized.arithmetic_expr(10, 20, 30, 5)
raise "bitwise_ops mismatch" unless PureRuby.bitwise_ops(100, 50) == Optimized.bitwise_ops(100, 50)
puts "All results match!"
puts

puts "=" * 60
puts "Benchmark: Multiply Add (a * b + c)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.multiply_add(10, 20, 5) }
  x.report("Native (optimized)") { Optimized.multiply_add(10, 20, 5) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Compute Chain (x*2+10)*3-x"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.compute_chain(100) }
  x.report("Native (optimized)") { Optimized.compute_chain(100) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Arithmetic Expression"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.arithmetic_expr(10, 20, 30, 5) }
  x.report("Native (optimized)") { Optimized.arithmetic_expr(10, 20, 30, 5) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Bitwise Operations"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.bitwise_ops(100, 50) }
  x.report("Native (optimized)") { Optimized.bitwise_ops(100, 50) }
  x.compare!
end

# Cleanup
File.unlink(optimized_bundle) rescue nil
