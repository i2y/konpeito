# frozen_string_literal: true

# Benchmark: NativeClass (Point) vs Ruby Class
# Usage: bundle exec ruby benchmark/native_class_bench.rb
#
# This benchmark compares:
# - Pure Ruby classes with instance variables
# - Native compiled code with NativeClass (unboxed fields, fixed layout)
#
# Expected: 5-10x speedup with NativeClass due to:
# - No instance variable hash lookup
# - Unboxed field storage (double instead of VALUE)
# - Fixed struct layout (known offsets)

require "benchmark/ips"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

NATIVE_SOURCE = <<~RUBY
  def native_distance_squared(x1, y1, x2, y2)
    p1 = Point.new
    p1.x = x1
    p1.y = y1

    p2 = Point.new
    p2.x = x2
    p2.y = y2

    dx = p2.x - p1.x
    dy = p2.y - p1.y
    dx * dx + dy * dy
  end

  def native_vector_ops(n)
    p = Point.new
    p.x = 0.0
    p.y = 0.0

    i = 0
    while i < n
      p.x = p.x + 1.5
      p.y = p.y + 2.5
      i = i + 1
    end

    p.x + p.y
  end

  def native_point_sum(count)
    total_x = 0.0
    total_y = 0.0

    i = 0
    while i < count
      p = Point.new
      p.x = i * 1.0
      p.y = i * 2.0
      total_x = total_x + p.x
      total_y = total_y + p.y
      i = i + 1
    end

    total_x + total_y
  end
RUBY

NATIVE_RBS = <<~RBS
  # @native
  class Point
    @x: Float
    @y: Float

    def self.new: () -> Point
    def x: () -> Float
    def x=: (Float value) -> Float
    def y: () -> Float
    def y=: (Float value) -> Float
  end

  # TopLevel module for top-level method type annotations
  # This enables unboxed arithmetic for loop conditions and parameters
  module TopLevel
    def native_distance_squared: (Float x1, Float y1, Float x2, Float y2) -> Float
    def native_vector_ops: (Integer n) -> Float
    def native_point_sum: (Integer count) -> Float
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

  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil

  output_path
end

# Pure Ruby Point class
class RubyPoint
  attr_accessor :x, :y

  def initialize
    @x = 0.0
    @y = 0.0
  end
end

module PureRuby
  def self.distance_squared(x1, y1, x2, y2)
    p1 = RubyPoint.new
    p1.x = x1
    p1.y = y1

    p2 = RubyPoint.new
    p2.x = x2
    p2.y = y2

    dx = p2.x - p1.x
    dy = p2.y - p1.y
    dx * dx + dy * dy
  end

  def self.vector_ops(n)
    p = RubyPoint.new
    p.x = 0.0
    p.y = 0.0

    i = 0
    while i < n
      p.x = p.x + 1.5
      p.y = p.y + 2.5
      i = i + 1
    end

    p.x + p.y
  end

  def self.point_sum(count)
    total_x = 0.0
    total_y = 0.0

    i = 0
    while i < count
      p = RubyPoint.new
      p.x = i * 1.0
      p.y = i * 2.0
      total_x = total_x + p.x
      total_y = total_y + p.y
      i = i + 1
    end

    total_x + total_y
  end
end

puts "Compiling NativeClass extension..."
begin
  native_bundle = compile_native(NATIVE_SOURCE, NATIVE_RBS, "native_class_bench")
  require native_bundle
  $native_obj = Object.new

  module Native
    class << self
      define_method(:distance_squared) { |x1, y1, x2, y2| $native_obj.send(:native_distance_squared, x1, y1, x2, y2) }
      define_method(:vector_ops) { |n| $native_obj.send(:native_vector_ops, n) }
      define_method(:point_sum) { |count| $native_obj.send(:native_point_sum, count) }
    end
  end

  puts "Compiled: #{native_bundle}"
  puts

  # Verify correctness
  puts "=" * 60
  puts "Verifying correctness..."

  ruby_result = PureRuby.distance_squared(0.0, 0.0, 3.0, 4.0)
  native_result = Native.distance_squared(0.0, 0.0, 3.0, 4.0)
  if (ruby_result - native_result).abs > 0.001
    puts "WARNING: distance_squared mismatch! Ruby=#{ruby_result}, Native=#{native_result}"
  else
    puts "distance_squared results match: #{ruby_result}"
  end

  ruby_result = PureRuby.vector_ops(100)
  native_result = Native.vector_ops(100)
  if (ruby_result - native_result).abs > 0.001
    puts "WARNING: vector_ops mismatch! Ruby=#{ruby_result}, Native=#{native_result}"
  else
    puts "vector_ops(100) results match: #{ruby_result}"
  end

  ruby_result = PureRuby.point_sum(100)
  native_result = Native.point_sum(100)
  if (ruby_result - native_result).abs > 0.001
    puts "WARNING: point_sum mismatch! Ruby=#{ruby_result}, Native=#{native_result}"
  else
    puts "point_sum(100) results match: #{ruby_result}"
  end
  puts

  # Benchmarks
  puts "=" * 60
  puts "Benchmark: Distance Squared (single computation)"
  puts "=" * 60
  Benchmark.ips do |x|
    x.report("Ruby Point") { PureRuby.distance_squared(0.0, 0.0, 3.0, 4.0) }
    x.report("NativeClass") { Native.distance_squared(0.0, 0.0, 3.0, 4.0) }
    x.compare!
  end

  puts
  puts "=" * 60
  puts "Benchmark: Vector Ops (n=1000 field updates)"
  puts "=" * 60
  n = 1000
  Benchmark.ips do |x|
    x.report("Ruby Point") { PureRuby.vector_ops(n) }
    x.report("NativeClass") { Native.vector_ops(n) }
    x.compare!
  end

  puts
  puts "=" * 60
  puts "Benchmark: Point Sum (n=1000 allocations + field access)"
  puts "=" * 60
  n = 1000
  Benchmark.ips do |x|
    x.report("Ruby Point") { PureRuby.point_sum(n) }
    x.report("NativeClass") { Native.point_sum(n) }
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
