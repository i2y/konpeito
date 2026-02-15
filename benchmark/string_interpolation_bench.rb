# frozen_string_literal: true

# Benchmark: String Interpolation Performance
# Usage: bundle exec ruby benchmark/string_interpolation_bench.rb
#
# This benchmark tests the string interpolation feature.
# Compares native compiled `"Hello #{name}"` vs pure Ruby.

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source with string interpolation
INTERPOLATION_SOURCE = <<~RUBY
  def greet(name)
    "Hello, \#{name}!"
  end

  def format_info(name, age)
    "\#{name} is \#{age} years old"
  end

  def build_message(count)
    "You have \#{count} new messages"
  end

  # Benchmark loop inside native code
  def bench_interpolation(iterations)
    i = 0
    result = ""
    while i < iterations
      result = greet("World")
      i = i + 1
    end
    result
  end

  def bench_multi_interpolation(iterations)
    i = 0
    result = ""
    while i < iterations
      result = format_info("Alice", 30)
      i = i + 1
    end
    result
  end
RUBY

INTERPOLATION_RBS = <<~RBS
  module TopLevel
    def greet: (String name) -> String
    def format_info: (String name, Integer age) -> String
    def build_message: (Integer count) -> String
    def bench_interpolation: (Integer iterations) -> String
    def bench_multi_interpolation: (Integer iterations) -> String
  end
RBS

def compile_native
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "interp_bench_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "interp_bench_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "interp_bench_#{timestamp}.bundle")

  File.write(source_path, INTERPOLATION_SOURCE)
  File.write(rbs_path, INTERPOLATION_RBS)

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

# Pure Ruby implementations
module PureRuby
  def self.greet(name)
    "Hello, #{name}!"
  end

  def self.format_info(name, age)
    "#{name} is #{age} years old"
  end

  def self.bench_interpolation(iterations)
    i = 0
    result = ""
    while i < iterations
      result = greet("World")
      i = i + 1
    end
    result
  end

  def self.bench_multi_interpolation(iterations)
    i = 0
    result = ""
    while i < iterations
      result = format_info("Alice", 30)
      i = i + 1
    end
    result
  end
end

puts "Compiling native extension with string interpolation..."
bundle_path = compile_native
require bundle_path

$native_obj = Object.new

module Native
  class << self
    define_method(:greet) { |name| $native_obj.send(:greet, name) }
    define_method(:format_info) { |name, age| $native_obj.send(:format_info, name, age) }
    define_method(:bench_interpolation) { |n| $native_obj.send(:bench_interpolation, n) }
    define_method(:bench_multi_interpolation) { |n| $native_obj.send(:bench_multi_interpolation, n) }
  end
end

puts "Compiled: #{bundle_path}"
puts

# Verify correctness
puts "Verifying correctness..."
raise "greet mismatch" unless PureRuby.greet("World") == Native.greet("World")
raise "format_info mismatch" unless PureRuby.format_info("Alice", 30) == Native.format_info("Alice", 30)
puts "All results match!"
puts
puts "Pure Ruby greet('World') = #{PureRuby.greet('World')}"
puts "Native greet('World')    = #{Native.greet('World')}"
puts

# Single call benchmark (shows CRuby boundary overhead)
puts "=" * 60
puts "Benchmark: Single String Interpolation Call"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.greet("World") }
  x.report("Native") { Native.greet("World") }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Multiple Interpolation (2 values)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.format_info("Alice", 30) }
  x.report("Native") { Native.format_info("Alice", 30) }
  x.compare!
end

# Internal loop benchmark (shows true native performance)
iterations = 1_000_000
puts
puts "=" * 60
puts "Benchmark: Internal Loop (#{iterations} iterations)"
puts "=" * 60

GC.disable
ruby_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ruby_result = PureRuby.bench_interpolation(iterations)
ruby_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ruby_start

native_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
native_result = Native.bench_interpolation(iterations)
native_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - native_start
GC.enable

puts "Pure Ruby:     #{ruby_time.round(4)}s"
puts "Ruby Native:   #{native_time.round(4)}s"
speedup = ruby_time / native_time
puts "Speedup:       #{speedup.round(2)}x #{speedup > 1 ? 'faster' : 'slower'}"
puts

puts "=" * 60
puts "Benchmark: Multi-Interpolation Internal Loop (#{iterations} iterations)"
puts "=" * 60

GC.disable
ruby_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ruby_result = PureRuby.bench_multi_interpolation(iterations)
ruby_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ruby_start

native_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
native_result = Native.bench_multi_interpolation(iterations)
native_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - native_start
GC.enable

puts "Pure Ruby:     #{ruby_time.round(4)}s"
puts "Ruby Native:   #{native_time.round(4)}s"
speedup = ruby_time / native_time
puts "Speedup:       #{speedup.round(2)}x #{speedup > 1 ? 'faster' : 'slower'}"

puts
puts "-" * 60
puts "Note: String interpolation uses rb_str_concat internally."
puts "Performance depends on string allocation/GC behavior."
puts "-" * 60

# Cleanup
File.unlink(bundle_path) rescue nil
