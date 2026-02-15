# frozen_string_literal: true

require "benchmark/ips"
require "fileutils"

$LOAD_PATH.unshift File.join(__dir__, "..", "lib")
require "konpeito"

# Benchmark: Loop optimization (counter loop)
# Tests the performance of compiled loops vs pure Ruby.

OUTPUT_DIR = File.join(__dir__, "..", "tmp", "bench_loop_opt")
FileUtils.mkdir_p(OUTPUT_DIR)

def compile_bundle(source, rbs_source, name)
  rbs_path = File.join(OUTPUT_DIR, "#{name}.rbs")
  File.write(rbs_path, rbs_source)

  source_path = File.join(OUTPUT_DIR, "#{name}.rb")
  File.write(source_path, source)

  output_file = File.join(OUTPUT_DIR, "#{name}.bundle")
  compiler = Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_file,
    rbs_paths: [rbs_path],
    optimize: true
  )
  compiler.compile
  output_file
end

# ========================================
# Benchmark 1: Counter loop with addition
# ========================================
rbs1 = <<~RBS
  module TopLevel
    def bench_counter_sum: (Integer n) -> Integer
  end
RBS

source1 = <<~RUBY
  def bench_counter_sum(n)
    total = 0
    iter = 0
    while iter < 1000
      i = 0
      sum = 0
      while i < n
        sum = sum + i
        i = i + 1
      end
      total = total + sum
      iter = iter + 1
    end
    total
  end
RUBY

puts "Compiling benchmarks..."
bundle1 = compile_bundle(source1, rbs1, "bench_loop1")
require bundle1

# ========================================
# Benchmark 2: Nested loops (matrix-like)
# ========================================
rbs2 = <<~RBS
  module TopLevel
    def bench_nested_loop: (Integer n) -> Integer
  end
RBS

source2 = <<~RUBY
  def bench_nested_loop(n)
    total = 0
    i = 0
    while i < n
      j = 0
      while j < n
        total = total + i * j
        j = j + 1
      end
      i = i + 1
    end
    total
  end
RUBY

bundle2 = compile_bundle(source2, rbs2, "bench_loop2")
require bundle2

# ========================================
# Benchmark 3: Loop with conditional
# ========================================
rbs3 = <<~RBS
  module TopLevel
    def bench_loop_conditional: (Integer n) -> Integer
  end
RBS

source3 = <<~RUBY
  def bench_loop_conditional(n)
    even_sum = 0
    odd_sum = 0
    i = 0
    while i < n
      if i % 2 == 0
        even_sum = even_sum + i
      else
        odd_sum = odd_sum + i
      end
      i = i + 1
    end
    even_sum + odd_sum
  end
RUBY

bundle3 = compile_bundle(source3, rbs3, "bench_loop3")
require bundle3

# ========================================
# Verify correctness
# ========================================
puts "Counter sum (n=100, 1000 iters): #{bench_counter_sum(100)}"
puts "Nested loop (n=50): #{bench_nested_loop(50)}"
puts "Conditional loop (n=100): #{bench_loop_conditional(100)}"

# Ruby reference implementations
def ruby_counter_sum(n)
  total = 0
  iter = 0
  while iter < 1000
    i = 0
    sum = 0
    while i < n
      sum = sum + i
      i = i + 1
    end
    total = total + sum
    iter = iter + 1
  end
  total
end

def ruby_nested_loop(n)
  total = 0
  i = 0
  while i < n
    j = 0
    while j < n
      total = total + i * j
      j = j + 1
    end
    i = i + 1
  end
  total
end

def ruby_loop_conditional(n)
  even_sum = 0
  odd_sum = 0
  i = 0
  while i < n
    if i % 2 == 0
      even_sum = even_sum + i
    else
      odd_sum = odd_sum + i
    end
    i = i + 1
  end
  even_sum + odd_sum
end

puts "Ruby counter sum: #{ruby_counter_sum(100)}"
puts "Ruby nested loop: #{ruby_nested_loop(50)}"
puts "Ruby conditional: #{ruby_loop_conditional(100)}"

# ========================================
# Benchmark
# ========================================
puts "\n=== Loop Optimization Benchmark ===\n\n"

Benchmark.ips do |x|
  x.report("Ruby: counter sum (n=100, 1000 iters)") { ruby_counter_sum(100) }
  x.report("Native: counter sum (n=100, 1000 iters)") { bench_counter_sum(100) }
  x.compare!
end

puts ""

Benchmark.ips do |x|
  x.report("Ruby: nested loop (n=50)") { ruby_nested_loop(50) }
  x.report("Native: nested loop (n=50)") { bench_nested_loop(50) }
  x.compare!
end

puts ""

Benchmark.ips do |x|
  x.report("Ruby: conditional loop (n=1000)") { ruby_loop_conditional(1000) }
  x.report("Native: conditional loop (n=1000)") { bench_loop_conditional(1000) }
  x.compare!
end

# Cleanup
FileUtils.rm_rf(OUTPUT_DIR)
