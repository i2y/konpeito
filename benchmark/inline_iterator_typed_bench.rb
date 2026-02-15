# frozen_string_literal: true

# Benchmark for inline iterator optimizations with TYPE ANNOTATIONS
# This demonstrates the benefit when unboxed arithmetic is used inside loops

require "benchmark/ips"
require "fileutils"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

def compile_native_with_rbs(source, rbs, name)
  dir = Dir.mktmpdir
  source_file = File.join(dir, "#{name}.rb")
  rbs_file = File.join(dir, "#{name}.rbs")
  output_file = File.join(dir, "#{name}.bundle")

  File.write(source_file, source)
  File.write(rbs_file, rbs)

  compiler = Konpeito::Compiler.new(
    source_file: source_file,
    output_file: output_file,
    rbs_paths: [rbs_file]
  )
  compiler.compile

  require output_file
  dir
end

puts "=" * 70
puts "Inline Iterator Benchmark WITH TYPE ANNOTATIONS"
puts "=" * 70
puts
puts "This benchmark demonstrates performance with unboxed arithmetic inside loops."
puts

# ============================================
# Integer#times with computation
# ============================================
puts "Compiling Integer#times with computation..."

times_source = <<~RUBY
  def native_times_compute(n)
    sum = 0
    n.times do |i|
      sum = sum + i * i
    end
    sum
  end
RUBY

times_rbs = <<~RBS
  module TopLevel
    def native_times_compute: (Integer n) -> Integer
  end
RBS

compile_native_with_rbs(times_source, times_rbs, "times_typed_bench")

def ruby_times_compute(n)
  sum = 0
  n.times do |i|
    sum = sum + i * i
  end
  sum
end

puts "\n### Integer#times with i*i computation (n=1000) ###"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Pure Ruby") { ruby_times_compute(1000) }
  x.report("Native (typed)") { native_times_compute(1000) }

  x.compare!
end

# ============================================
# Nested loops - where native really shines
# ============================================
puts "\nCompiling nested loops benchmark..."

nested_source = <<~RUBY
  def native_nested_times(n)
    total = 0
    n.times do |i|
      n.times do |j|
        total = total + i * j
      end
    end
    total
  end
RUBY

nested_rbs = <<~RBS
  module TopLevel
    def native_nested_times: (Integer n) -> Integer
  end
RBS

compile_native_with_rbs(nested_source, nested_rbs, "nested_typed_bench")

def ruby_nested_times(n)
  total = 0
  n.times do |i|
    n.times do |j|
      total = total + i * j
    end
  end
  total
end

puts "\n### Nested Integer#times (n=100, 10000 iterations total) ###"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Pure Ruby") { ruby_nested_times(100) }
  x.report("Native (typed)") { native_nested_times(100) }

  x.compare!
end

# ============================================
# Internal benchmark - loop inside native
# ============================================
puts "\nCompiling internal benchmark (loop inside native)..."

internal_source = <<~RUBY
  def native_times_internal_bench(iterations, n)
    i = 0
    while i < iterations
      sum = 0
      n.times { |j| sum = sum + j * j }
      i = i + 1
    end
    sum
  end
RUBY

internal_rbs = <<~RBS
  module TopLevel
    def native_times_internal_bench: (Integer iterations, Integer n) -> Integer
  end
RBS

compile_native_with_rbs(internal_source, internal_rbs, "internal_typed_bench")

def ruby_times_internal_bench(iterations, n)
  i = 0
  while i < iterations
    sum = 0
    n.times { |j| sum = sum + j * j }
    i = i + 1
  end
  sum
end

puts "\n### Internal benchmark: 1000 iterations of times(100) ###"
puts "(Measures native code performance without boundary overhead)"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Pure Ruby") { ruby_times_internal_bench(1000, 100) }
  x.report("Native (typed)") { native_times_internal_bench(1000, 100) }

  x.compare!
end

# ============================================
# Array iteration with typed computation
# ============================================
puts "\nCompiling typed array iteration..."

array_compute_source = <<~RUBY
  def native_array_sum_squares(arr)
    total = 0
    arr.each do |x|
      total = total + x * x
    end
    total
  end
RUBY

array_compute_rbs = <<~RBS
  module TopLevel
    def native_array_sum_squares: (Array[Integer] arr) -> Integer
  end
RBS

compile_native_with_rbs(array_compute_source, array_compute_rbs, "array_typed_bench")

def ruby_array_sum_squares(arr)
  total = 0
  arr.each do |x|
    total = total + x * x
  end
  total
end

test_array = (1..1000).to_a

puts "\n### Array#each with sum of squares (n=1000) ###"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Pure Ruby") { ruby_array_sum_squares(test_array) }
  x.report("Native (typed)") { native_array_sum_squares(test_array) }

  x.compare!
end

# ============================================
# Comparison: typed reduce vs inline each
# ============================================
puts "\nCompiling reduce comparison..."

reduce_source = <<~RUBY
  def native_reduce_sum_squares(arr)
    arr.reduce(0) { |acc, x| acc + x * x }
  end
RUBY

reduce_rbs = <<~RBS
  module TopLevel
    def native_reduce_sum_squares: (Array[Integer] arr) -> Integer
  end
RBS

compile_native_with_rbs(reduce_source, reduce_rbs, "reduce_typed_bench")

def ruby_reduce_sum_squares(arr)
  arr.reduce(0) { |acc, x| acc + x * x }
end

puts "\n### reduce vs each for sum of squares (n=1000) ###"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Ruby reduce") { ruby_reduce_sum_squares(test_array) }
  x.report("Native reduce (typed)") { native_reduce_sum_squares(test_array) }
  x.report("Ruby each") { ruby_array_sum_squares(test_array) }
  x.report("Native each (typed)") { native_array_sum_squares(test_array) }

  x.compare!
end

puts "\n" + "=" * 70
puts "Benchmark Complete"
puts "=" * 70
puts
puts "Note: Native performance advantage is most visible when:"
puts "  1. Type annotations enable unboxed arithmetic"
puts "  2. Multiple iterations are done inside native code (no boundary crossing)"
puts "  3. Nested loops amplify the optimization benefit"
