# frozen_string_literal: true

# Benchmark: Compare native compiled code vs pure Ruby for loop constructs
# Usage: bundle exec ruby benchmark/loop_bench.rb
#
# This benchmark tests while loops which require proper SSA handling
# (Phi nodes for loop-carried variables). The alloca + mem2reg approach
# used in the compiler automatically handles this.

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source code to benchmark (while loops)
LOOP_SOURCE = <<~RUBY
  def sum_range(n)
    total = 0
    i = 0
    while i <= n
      total = total + i
      i = i + 1
    end
    total
  end

  def factorial(n)
    result = 1
    i = 1
    while i <= n
      result = result * i
      i = i + 1
    end
    result
  end

  def count_down(n)
    count = 0
    while n > 0
      count = count + 1
      n = n - 1
    end
    count
  end
RUBY

# RBS type annotations using TopLevel module (avoids "superclass mismatch" with Object)
# This enables unboxed arithmetic optimization for function parameters
LOOP_RBS = <<~RBS
module TopLevel
  def sum_range: (Integer n) -> Integer
  def factorial: (Integer n) -> Integer
  def count_down: (Integer n) -> Integer
end
RBS

def compile_native(optimize:)
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "loop_bench_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "loop_bench_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "loop_bench_#{timestamp}.bundle")

  File.write(source_path, LOOP_SOURCE)
  File.write(rbs_path, LOOP_RBS)

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
  def self.sum_range(n)
    total = 0
    i = 0
    while i <= n
      total = total + i
      i = i + 1
    end
    total
  end

  def self.factorial(n)
    result = 1
    i = 1
    while i <= n
      result = result * i
      i = i + 1
    end
    result
  end

  def self.count_down(n)
    count = 0
    while n > 0
      count = count + 1
      n = n - 1
    end
    count
  end
end

puts "Compiling native extension with loop support..."
loop_bundle = compile_native(optimize: true)
require loop_bundle

$native_obj = Object.new

module Native
  class << self
    define_method(:sum_range) { |n| $native_obj.send(:sum_range, n) }
    define_method(:factorial) { |n| $native_obj.send(:factorial, n) }
    define_method(:count_down) { |n| $native_obj.send(:count_down, n) }
  end
end

puts "Compiled: #{loop_bundle}"
puts

# Verify correctness
puts "Verifying correctness..."
raise "sum_range mismatch" unless PureRuby.sum_range(100) == Native.sum_range(100)
raise "factorial mismatch" unless PureRuby.factorial(10) == Native.factorial(10)
raise "count_down mismatch" unless PureRuby.count_down(100) == Native.count_down(100)
puts "All results match!"
puts
puts "Pure Ruby sum_range(100) = #{PureRuby.sum_range(100)}"
puts "Native sum_range(100)    = #{Native.sum_range(100)}"
puts "Pure Ruby factorial(10)  = #{PureRuby.factorial(10)}"
puts "Native factorial(10)     = #{Native.factorial(10)}"
puts

puts "=" * 60
puts "Benchmark: Sum Range (0 to n)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.sum_range(100) }
  x.report("Native") { Native.sum_range(100) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Factorial"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.factorial(10) }
  x.report("Native") { Native.factorial(10) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Count Down"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.count_down(100) }
  x.report("Native") { Native.count_down(100) }
  x.compare!
end

# Cleanup
File.unlink(loop_bundle) rescue nil
