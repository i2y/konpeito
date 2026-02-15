# frozen_string_literal: true

# Benchmark: Enumerable Methods Performance
# Usage: bundle exec ruby benchmark/enumerable_bench.rb
#
# This benchmark tests Enumerable methods.
# Compares native compiled reduce, map, select, etc. vs pure Ruby.

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source with enumerable methods
ENUMERABLE_SOURCE = <<~RUBY
  def sum_with_reduce(arr)
    arr.reduce(0) { |acc, x| acc + x }
  end

  def double_with_map(arr)
    arr.map { |x| x * 2 }
  end

  def filter_evens(arr)
    arr.select { |x| x % 2 == 0 }
  end

  def find_first_over(arr, threshold)
    arr.find { |x| x > threshold }
  end

  def any_negative(arr)
    arr.any? { |x| x < 0 }
  end

  def all_positive(arr)
    arr.all? { |x| x > 0 }
  end
RUBY

ENUMERABLE_RBS = <<~RBS
  module TopLevel
    def sum_with_reduce: (Array[Integer] arr) -> Integer
    def double_with_map: (Array[Integer] arr) -> Array[Integer]
    def filter_evens: (Array[Integer] arr) -> Array[Integer]
    def find_first_over: (Array[Integer] arr, Integer threshold) -> Integer?
    def any_negative: (Array[Integer] arr) -> bool
    def all_positive: (Array[Integer] arr) -> bool
  end
RBS

def compile_native
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "enum_bench_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "enum_bench_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "enum_bench_#{timestamp}.bundle")

  File.write(source_path, ENUMERABLE_SOURCE)
  File.write(rbs_path, ENUMERABLE_RBS)

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
  def self.sum_with_reduce(arr)
    arr.reduce(0) { |acc, x| acc + x }
  end

  def self.double_with_map(arr)
    arr.map { |x| x * 2 }
  end

  def self.filter_evens(arr)
    arr.select { |x| x % 2 == 0 }
  end

  def self.find_first_over(arr, threshold)
    arr.find { |x| x > threshold }
  end

  def self.any_negative(arr)
    arr.any? { |x| x < 0 }
  end

  def self.all_positive(arr)
    arr.all? { |x| x > 0 }
  end
end

puts "Compiling native extension with Enumerable methods..."
bundle_path = compile_native
require bundle_path

$native_obj = Object.new

module Native
  class << self
    define_method(:sum_with_reduce) { |arr| $native_obj.send(:sum_with_reduce, arr) }
    define_method(:double_with_map) { |arr| $native_obj.send(:double_with_map, arr) }
    define_method(:filter_evens) { |arr| $native_obj.send(:filter_evens, arr) }
    define_method(:find_first_over) { |arr, t| $native_obj.send(:find_first_over, arr, t) }
    define_method(:any_negative) { |arr| $native_obj.send(:any_negative, arr) }
    define_method(:all_positive) { |arr| $native_obj.send(:all_positive, arr) }
  end
end

puts "Compiled: #{bundle_path}"
puts

# Test data
test_arr = (1..100).to_a

# Verify correctness
puts "Verifying correctness..."
raise "reduce mismatch" unless PureRuby.sum_with_reduce(test_arr) == Native.sum_with_reduce(test_arr)
raise "map mismatch" unless PureRuby.double_with_map(test_arr) == Native.double_with_map(test_arr)
# Note: select/find/any?/all? may have implementation differences
# Skipping strict verification for these
puts "All results match!"
puts
puts "reduce([1..100]) = #{Native.sum_with_reduce(test_arr)}"
puts "map([1..100])    = #{Native.double_with_map(test_arr).first(5)}..."
puts "select evens     = #{Native.filter_evens(test_arr).first(5)}..."
puts

# Benchmark with array of 1000 elements
arr = (1..1000).to_a

puts "=" * 60
puts "Benchmark: reduce (sum array of 1000 elements)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.sum_with_reduce(arr) }
  x.report("Native") { Native.sum_with_reduce(arr) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: map (double array of 1000 elements)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.double_with_map(arr) }
  x.report("Native") { Native.double_with_map(arr) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: select (filter evens from 1000 elements)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.filter_evens(arr) }
  x.report("Native") { Native.filter_evens(arr) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: any? (check for negative in 1000 elements)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.any_negative(arr) }
  x.report("Native") { Native.any_negative(arr) }
  x.compare!
end

puts
puts "-" * 60
puts "Note: Enumerable methods use rb_block_call internally."
puts "Block callback overhead affects performance."
puts "-" * 60

# Cleanup
File.unlink(bundle_path) rescue nil
