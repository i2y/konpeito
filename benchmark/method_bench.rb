# frozen_string_literal: true

# Benchmark: Compare native compiled code vs pure Ruby for method calls
# Usage: bundle exec ruby benchmark/method_bench.rb
#
# This benchmark tests direct C function calls (devirtualization) vs rb_funcallv
# String/Array/Hash builtin methods are called directly
#
# Note: Only methods with exported C functions can be devirtualized.
# Many Ruby methods (upcase, downcase, reverse) are internal and not callable directly.

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source code to benchmark - using only EXPORTED functions
STRING_SOURCE = <<~RUBY
  def string_length(s)
    s.length
  end

  def string_concat(s1, s2)
    s1 + s2
  end

  def string_intern(s)
    s.intern
  end
RUBY

# TopLevel module pattern for type annotations
STRING_RBS = <<~RBS
module TopLevel
  def string_length: (String s) -> Integer
  def string_concat: (String s1, String s2) -> String
  def string_intern: (String s) -> Symbol
end
RBS

# Array operations - using exported functions
ARRAY_SOURCE = <<~RUBY
  def array_push(arr, item)
    arr.push(item)
  end

  def array_pop(arr)
    arr.pop
  end

  def array_includes(arr, item)
    arr.include?(item)
  end

  def array_concat(arr1, arr2)
    arr1 + arr2
  end
RUBY

# TopLevel module pattern for type annotations
ARRAY_RBS = <<~RBS
module TopLevel
  def array_push: (Array arr, untyped item) -> Array
  def array_pop: (Array arr) -> untyped
  def array_includes: (Array arr, untyped item) -> bool
  def array_concat: (Array arr1, Array arr2) -> Array
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
  def self.string_length(s)
    s.length
  end

  def self.string_concat(s1, s2)
    s1 + s2
  end

  def self.string_intern(s)
    s.intern
  end

  def self.array_push(arr, item)
    arr.push(item)
  end

  def self.array_pop(arr)
    arr.pop
  end

  def self.array_includes(arr, item)
    arr.include?(item)
  end

  def self.array_concat(arr1, arr2)
    arr1 + arr2
  end
end

puts "Compiling native extensions with direct method calls..."
string_bundle = compile_native(STRING_SOURCE, STRING_RBS, "string_bench")
array_bundle = compile_native(ARRAY_SOURCE, ARRAY_RBS, "array_bench")

require string_bundle
require array_bundle

$native_obj = Object.new

module Native
  class << self
    define_method(:string_length) { |s| $native_obj.send(:string_length, s) }
    define_method(:string_concat) { |s1, s2| $native_obj.send(:string_concat, s1, s2) }
    define_method(:string_intern) { |s| $native_obj.send(:string_intern, s) }
    define_method(:array_push) { |arr, item| $native_obj.send(:array_push, arr.dup, item) }
    define_method(:array_pop) { |arr| $native_obj.send(:array_pop, arr.dup) }
    define_method(:array_includes) { |arr, item| $native_obj.send(:array_includes, arr, item) }
    define_method(:array_concat) { |arr1, arr2| $native_obj.send(:array_concat, arr1, arr2) }
  end
end

puts "Compiled: #{string_bundle}"
puts "Compiled: #{array_bundle}"
puts

# Test data
test_string = "Hello World"
test_s1 = "Hello, "
test_s2 = "World!"
test_array = (1..100).to_a
test_item = 50

# Verify correctness
puts "Verifying correctness..."
raise "string_length mismatch" unless PureRuby.string_length(test_string) == Native.string_length(test_string)
raise "string_concat mismatch" unless PureRuby.string_concat(test_s1, test_s2) == Native.string_concat(test_s1, test_s2)
raise "string_intern mismatch" unless PureRuby.string_intern(test_string) == Native.string_intern(test_string)
raise "array_includes mismatch" unless PureRuby.array_includes(test_array, test_item) == Native.array_includes(test_array, test_item)
raise "array_concat mismatch" unless PureRuby.array_concat(test_array, [200, 201]) == Native.array_concat(test_array, [200, 201])
puts "All results match!"
puts

puts "Pure Ruby string_length  = #{PureRuby.string_length(test_string)}"
puts "Native string_length     = #{Native.string_length(test_string)}"
puts "Pure Ruby string_concat  = #{PureRuby.string_concat(test_s1, test_s2)}"
puts "Native string_concat     = #{Native.string_concat(test_s1, test_s2)}"
puts

puts "=" * 60
puts "Benchmark: String Length (rb_str_length - direct call)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.string_length(test_string) }
  x.report("Native") { Native.string_length(test_string) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: String Concatenation (rb_str_plus - direct call)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.string_concat(test_s1, test_s2) }
  x.report("Native") { Native.string_concat(test_s1, test_s2) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: String Intern (rb_str_intern - direct call)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.string_intern(test_string) }
  x.report("Native") { Native.string_intern(test_string) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Array Includes (rb_ary_includes - direct call)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.array_includes(test_array, test_item) }
  x.report("Native") { Native.array_includes(test_array, test_item) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Array Concat (rb_ary_plus - direct call)"
puts "=" * 60
small_array1 = [1, 2, 3]
small_array2 = [4, 5, 6]
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.array_concat(small_array1, small_array2) }
  x.report("Native") { Native.array_concat(small_array1, small_array2) }
  x.compare!
end

# Cleanup
File.unlink(string_bundle) rescue nil
File.unlink(array_bundle) rescue nil
