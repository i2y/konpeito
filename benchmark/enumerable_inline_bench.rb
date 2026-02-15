# frozen_string_literal: true

# Benchmark: Enumerable Inline Loop Optimization
# Compares performance with and without inline optimization

require "benchmark/ips"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source with type annotations to trigger inline optimization
TYPED_SOURCE = <<~RUBY
  def typed_reduce(arr)
    arr.reduce(0) { |acc, x| acc + x }
  end

  def typed_map(arr)
    arr.map { |x| x * 2 }
  end

  def typed_select(arr)
    arr.select { |x| x % 2 == 0 }
  end
RUBY

TYPED_RBS = <<~RBS
  module TopLevel
    def typed_reduce: (Array[Integer] arr) -> Integer
    def typed_map: (Array[Integer] arr) -> Array[Integer]
    def typed_select: (Array[Integer] arr) -> Array[Integer]
  end
RBS

def compile_with_types
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "enum_typed_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "enum_typed_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "enum_typed_#{timestamp}.bundle")

  File.write(source_path, TYPED_SOURCE)
  File.write(rbs_path, TYPED_RBS)

  puts "Compiling with type annotations..."
  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    format: :cruby_ext,
    rbs_paths: [rbs_path],
    optimize: true,
    verbose: false
  ).compile

  puts "Compiled: #{output_path}"
  output_path
ensure
  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil
end

# Pure Ruby implementations
module PureRuby
  def self.reduce(arr)
    arr.reduce(0) { |acc, x| acc + x }
  end

  def self.map(arr)
    arr.map { |x| x * 2 }
  end

  def self.select(arr)
    arr.select { |x| x % 2 == 0 }
  end
end

# Main
puts "=" * 60
puts "Enumerable Inline Optimization Benchmark"
puts "=" * 60
puts

native_ext = compile_with_types
require native_ext

# Test data
arr_1000 = (1..1000).to_a

# Verify correctness
puts "\nVerifying correctness..."
ruby_reduce = PureRuby.reduce(arr_1000)
native_reduce = typed_reduce(arr_1000)
raise "reduce mismatch: #{ruby_reduce} vs #{native_reduce}" unless ruby_reduce == native_reduce

ruby_map = PureRuby.map(arr_1000)
native_map = typed_map(arr_1000)
raise "map mismatch" unless ruby_map == native_map

ruby_select = PureRuby.select(arr_1000)
native_select = typed_select(arr_1000)
raise "select mismatch" unless ruby_select == native_select

puts "All results match!"
puts

# Benchmarks
puts "=" * 60
puts "Benchmark: reduce (sum 1000 integers)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.reduce(arr_1000) }
  x.report("Native (typed)") { typed_reduce(arr_1000) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: map (double 1000 integers)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.map(arr_1000) }
  x.report("Native (typed)") { typed_map(arr_1000) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: select (filter evens from 1000)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.select(arr_1000) }
  x.report("Native (typed)") { typed_select(arr_1000) }
  x.compare!
end

puts
puts "-" * 60
puts "Note: This benchmark uses RBS type annotations to trigger"
puts "inline loop optimization. Without types, rb_block_call is used."
puts "-" * 60
