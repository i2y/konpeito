# frozen_string_literal: true

# Benchmark: Measure NATIVE code performance (not Ruby→Native call overhead)
#
# This benchmark measures the actual performance of compiled native code
# by including the benchmark loop inside the native code itself.
# Ruby only calls the benchmark function once, avoiding boundary overhead.

require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

ITERATIONS = 10_000_000

# Native benchmark code - the loop is INSIDE the native code
NATIVE_BENCH_SOURCE = <<~RUBY
  def multiply_add(a, b, c)
    a * b + c
  end

  def compute_chain(x)
    y = x * 2
    z = y + 10
    w = z * 3
    w - x
  end

  # Benchmark loops are compiled to native code
  def bench_multiply_add(iterations)
    i = 0
    result = 0
    while i < iterations
      result = multiply_add(10, 20, 5)
      i = i + 1
    end
    result
  end

  def bench_compute_chain(iterations)
    i = 0
    result = 0
    while i < iterations
      result = compute_chain(100)
      i = i + 1
    end
    result
  end

  def bench_arithmetic_intensive(iterations)
    i = 0
    total = 0
    while i < iterations
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    total
  end
RUBY

NATIVE_BENCH_RBS = <<~RBS
module TopLevel
  def multiply_add: (Integer a, Integer b, Integer c) -> Integer
  def compute_chain: (Integer x) -> Integer
  def bench_multiply_add: (Integer iterations) -> Integer
  def bench_compute_chain: (Integer iterations) -> Integer
  def bench_arithmetic_intensive: (Integer iterations) -> Integer
end
RBS

def compile_native
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "internal_bench_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "internal_bench_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "internal_bench_#{timestamp}.bundle")

  File.write(source_path, NATIVE_BENCH_SOURCE)
  File.write(rbs_path, NATIVE_BENCH_RBS)

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

# Pure Ruby equivalents
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

  def self.bench_multiply_add(iterations)
    i = 0
    result = 0
    while i < iterations
      result = multiply_add(10, 20, 5)
      i = i + 1
    end
    result
  end

  def self.bench_compute_chain(iterations)
    i = 0
    result = 0
    while i < iterations
      result = compute_chain(100)
      i = i + 1
    end
    result
  end

  def self.bench_arithmetic_intensive(iterations)
    i = 0
    total = 0
    while i < iterations
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    total
  end
end

puts "Compiling native benchmark code..."
bundle_path = compile_native
require bundle_path
$native_obj = Object.new

puts "Compiled: #{bundle_path}"
puts "Iterations: #{ITERATIONS.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')}"
puts

# Verify correctness
puts "Verifying correctness..."
ruby_ma = PureRuby.bench_multiply_add(100)
native_ma = $native_obj.send(:bench_multiply_add, 100)
raise "multiply_add mismatch: Ruby=#{ruby_ma}, Native=#{native_ma}" unless ruby_ma == native_ma

ruby_cc = PureRuby.bench_compute_chain(100)
native_cc = $native_obj.send(:bench_compute_chain, 100)
raise "compute_chain mismatch: Ruby=#{ruby_cc}, Native=#{native_cc}" unless ruby_cc == native_cc

ruby_ai = PureRuby.bench_arithmetic_intensive(100)
native_ai = $native_obj.send(:bench_arithmetic_intensive, 100)
raise "arithmetic_intensive mismatch: Ruby=#{ruby_ai}, Native=#{native_ai}" unless ruby_ai == native_ai

puts "All results match!"
puts

def measure_time(name)
  GC.disable
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  GC.enable
  [elapsed, result]
end

puts "=" * 70
puts "Benchmark: Multiply Add (#{ITERATIONS} iterations)"
puts "=" * 70

ruby_time, ruby_result = measure_time("Ruby") { PureRuby.bench_multiply_add(ITERATIONS) }
native_time, native_result = measure_time("Native") { $native_obj.send(:bench_multiply_add, ITERATIONS) }

puts "Pure Ruby:     #{ruby_time.round(4)}s (result: #{ruby_result})"
puts "Ruby Native:   #{native_time.round(4)}s (result: #{native_result})"
speedup = ruby_time / native_time
if speedup > 1
  puts "Speedup:       #{speedup.round(2)}x faster"
else
  puts "Slowdown:      #{(1/speedup).round(2)}x slower"
end

puts
puts "=" * 70
puts "Benchmark: Compute Chain (#{ITERATIONS} iterations)"
puts "=" * 70

ruby_time, ruby_result = measure_time("Ruby") { PureRuby.bench_compute_chain(ITERATIONS) }
native_time, native_result = measure_time("Native") { $native_obj.send(:bench_compute_chain, ITERATIONS) }

puts "Pure Ruby:     #{ruby_time.round(4)}s (result: #{ruby_result})"
puts "Ruby Native:   #{native_time.round(4)}s (result: #{native_result})"
speedup = ruby_time / native_time
if speedup > 1
  puts "Speedup:       #{speedup.round(2)}x faster"
else
  puts "Slowdown:      #{(1/speedup).round(2)}x slower"
end

puts
puts "=" * 70
puts "Benchmark: Arithmetic Intensive (#{ITERATIONS} iterations)"
puts "=" * 70

ruby_time, ruby_result = measure_time("Ruby") { PureRuby.bench_arithmetic_intensive(ITERATIONS) }
native_time, native_result = measure_time("Native") { $native_obj.send(:bench_arithmetic_intensive, ITERATIONS) }

puts "Pure Ruby:     #{ruby_time.round(4)}s (result: #{ruby_result})"
puts "Ruby Native:   #{native_time.round(4)}s (result: #{native_result})"
speedup = ruby_time / native_time
if speedup > 1
  puts "Speedup:       #{speedup.round(2)}x faster"
else
  puts "Slowdown:      #{(1/speedup).round(2)}x slower"
end

puts
puts "-" * 70
puts "Note: This benchmark measures NATIVE code performance."
puts "The benchmark loop runs entirely inside compiled native code."
puts "Ruby only calls the benchmark function once."
puts "-" * 70

# Cleanup
File.unlink(bundle_path) rescue nil
