#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark for intermediate variable optimization
# Tests that `dx = x2 - x1; dx * dx` chains use unboxed arithmetic

require "benchmark/ips"
require "konpeito"
require "tempfile"
require "fileutils"

ITERATIONS = 1_000_000

# Create native code with intermediate variables
def compile_native
  source = <<~RUBY
    # Distance calculation using intermediate variables
    def compute_distance_squared(x1, y1, x2, y2)
      dx = x2 - x1
      dy = y2 - y1
      dx * dx + dy * dy
    end

    # Benchmark wrapper that runs iterations inside native code
    def bench_distance_squared(n)
      i = 0
      total = 0.0
      while i < n
        total = total + compute_distance_squared(1.0, 2.0, 4.0, 6.0)
        i = i + 1
      end
      total
    end
  RUBY

  rbs = <<~RBS
    module TopLevel
      def compute_distance_squared: (Float x1, Float y1, Float x2, Float y2) -> Float
      def bench_distance_squared: (Integer n) -> Float
    end
  RBS

  # Create temp directory
  tmp_dir = File.expand_path(File.join(File.dirname(__FILE__), "..", "tmp"))
  FileUtils.mkdir_p(tmp_dir)

  source_file = File.join(tmp_dir, "intermediate_bench_#{$$}.rb")
  rbs_file = File.join(tmp_dir, "intermediate_bench_#{$$}.rbs")
  output_file = File.join(tmp_dir, "intermediate_bench_#{$$}.bundle")

  File.write(source_file, source)
  File.write(rbs_file, rbs)

  puts "Compiling native benchmark code with intermediate variables..."

  compiler = Konpeito::Compiler.new(
    source_file: source_file,
    output_file: output_file,
    rbs_paths: [rbs_file]
  )
  compiler.compile

  puts "Compiled: #{output_file}"
  output_file
end

# Pure Ruby implementations
module PureRuby
  def self.compute_distance_squared(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  def self.bench_distance_squared(n)
    i = 0
    total = 0.0
    while i < n
      total = total + compute_distance_squared(1.0, 2.0, 4.0, 6.0)
      i = i + 1
    end
    total
  end
end

# Main
bundle_path = compile_native
require bundle_path

puts "Iterations: #{ITERATIONS.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')}"
puts

# Verify correctness
puts "Verifying correctness..."
ruby_result = PureRuby.bench_distance_squared(100)
native_result = bench_distance_squared(100)

if (ruby_result - native_result).abs < 0.001
  puts "Results match! (Ruby: #{ruby_result}, Native: #{native_result})"
else
  puts "MISMATCH! Ruby: #{ruby_result}, Native: #{native_result}"
  exit 1
end

puts
puts "=" * 70
puts "Benchmark: Intermediate Variable Optimization (#{ITERATIONS} iterations)"
puts "=" * 70

# Measure native performance
native_start = Time.now
native_result = bench_distance_squared(ITERATIONS)
native_time = Time.now - native_start

# Measure Ruby performance
ruby_start = Time.now
ruby_result = PureRuby.bench_distance_squared(ITERATIONS)
ruby_time = Time.now - ruby_start

puts "Pure Ruby:     #{format('%.4fs', ruby_time)} (result: #{ruby_result})"
puts "Ruby Native:   #{format('%.4fs', native_time)} (result: #{native_result})"
puts "Speedup:       #{format('%.2fx', ruby_time / native_time)} faster"
puts

puts "-" * 70
puts "This benchmark measures intermediate variable optimization."
puts "Variables like `dx = x2 - x1` should remain unboxed throughout."
puts "-" * 70
