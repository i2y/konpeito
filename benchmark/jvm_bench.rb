# frozen_string_literal: true

# JVM Backend Performance Benchmark
#
# Compiles benchmark code to JAR, runs it, and compares with Pure Ruby.
# Runs TWO modes:
#   1. JIT-friendly: constant args (HotSpot can constant-fold & vectorize)
#   2. Anti-optimization: loop var used as arg, results accumulated
# This shows the real performance range of the JVM backend.
#
# Usage:
#   bundle exec ruby benchmark/jvm_bench.rb

require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

JAVA_CMD = "/opt/homebrew/opt/openjdk@21/bin/java"
ITERATIONS = 10_000_000

# ── Mode 1: JIT-Friendly (constant args — JIT can optimize aggressively) ──
JVM_BENCH_JIT_SOURCE = <<~'RUBY'
  def multiply_add(a, b, c)
    a * b + c
  end

  def compute_chain(x)
    y = x * 2
    z = y + 10
    w = z * 3
    w - x
  end

  def bench_multiply_add_jit(n)
    i = 0
    while i < 100000
      multiply_add(10, 20, 5)
      i = i + 1
    end
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    result = 0
    while i < n
      result = multiply_add(10, 20, 5)
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:multiply_add_jit:" + (t1 - t0).to_s + ":" + result.to_s
    result
  end

  def bench_compute_chain_jit(n)
    i = 0
    while i < 100000
      compute_chain(100)
      i = i + 1
    end
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    result = 0
    while i < n
      result = compute_chain(100)
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:compute_chain_jit:" + (t1 - t0).to_s + ":" + result.to_s
    result
  end

  def bench_loop_sum_jit(n)
    i = 0
    s = 0
    while i < 100000
      s = s + i
      i = i + 1
    end
    s = 0
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    while i < n
      s = s + i
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:loop_sum_jit:" + (t1 - t0).to_s + ":" + s.to_s
    s
  end

  def bench_arithmetic_jit(n)
    i = 0
    total = 0
    while i < 100000
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    total = 0
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    while i < n
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:arithmetic_jit:" + (t1 - t0).to_s + ":" + total.to_s
    total
  end

  def bench_multiply_add_real(n)
    i = 0
    s = 0
    while i < 100000
      s = s + multiply_add(i, 20, 5)
      i = i + 1
    end
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    s = 0
    while i < n
      s = s + multiply_add(i, 20, 5)
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:multiply_add_real:" + (t1 - t0).to_s + ":" + s.to_s
    s
  end

  def bench_compute_chain_real(n)
    i = 0
    s = 0
    while i < 100000
      s = s + compute_chain(i)
      i = i + 1
    end
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    s = 0
    while i < n
      s = s + compute_chain(i)
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:compute_chain_real:" + (t1 - t0).to_s + ":" + s.to_s
    s
  end

  def bench_arithmetic_real(n)
    i = 0
    total = 0
    while i < 100000
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    total = 0
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    while i < n
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:arithmetic_real:" + (t1 - t0).to_s + ":" + total.to_s
    total
  end

  def bench_loop_sum_real(n)
    i = 0
    s = 0
    while i < 100000
      s = s + i
      i = i + 1
    end
    s = 0
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    while i < n
      s = s + i
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:loop_sum_real:" + (t1 - t0).to_s + ":" + s.to_s
    s
  end

  def fib(n)
    if n < 2
      return n
    end
    fib(n - 1) + fib(n - 2)
  end

  def bench_fibonacci(n)
    fib(25)
    fib(25)
    t0 = KonpeitoTime.epoch_nanos
    i = 0
    result = 0
    while i < n
      result = fib(30)
      i = i + 1
    end
    t1 = KonpeitoTime.epoch_nanos
    puts "RESULT:fibonacci:" + (t1 - t0).to_s + ":" + result.to_s
    result
  end

  bench_multiply_add_jit(10000000)
  bench_compute_chain_jit(10000000)
  bench_arithmetic_jit(10000000)
  bench_loop_sum_jit(10000000)
  bench_multiply_add_real(10000000)
  bench_compute_chain_real(10000000)
  bench_arithmetic_real(10000000)
  bench_loop_sum_real(10000000)
  bench_fibonacci(10)
RUBY

JVM_BENCH_RBS = <<~RBS
module TopLevel
  def multiply_add: (Integer a, Integer b, Integer c) -> Integer
  def compute_chain: (Integer x) -> Integer
  def bench_multiply_add_jit: (Integer n) -> Integer
  def bench_compute_chain_jit: (Integer n) -> Integer
  def bench_arithmetic_jit: (Integer n) -> Integer
  def bench_loop_sum_jit: (Integer n) -> Integer
  def bench_multiply_add_real: (Integer n) -> Integer
  def bench_compute_chain_real: (Integer n) -> Integer
  def bench_arithmetic_real: (Integer n) -> Integer
  def bench_loop_sum_real: (Integer n) -> Integer
  def fib: (Integer n) -> Integer
  def bench_fibonacci: (Integer n) -> Integer
end
RBS

# ── Pure Ruby equivalents ──
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

  # JIT-friendly (constant args)
  def self.bench_multiply_add_jit(n)
    i = 0
    result = 0
    while i < n
      result = multiply_add(10, 20, 5)
      i = i + 1
    end
    result
  end

  def self.bench_compute_chain_jit(n)
    i = 0
    result = 0
    while i < n
      result = compute_chain(100)
      i = i + 1
    end
    result
  end

  def self.bench_arithmetic_jit(n)
    i = 0
    total = 0
    while i < n
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    total
  end

  def self.bench_loop_sum_jit(n)
    i = 0
    s = 0
    while i < n
      s = s + i
      i = i + 1
    end
    s
  end

  # Anti-optimization (variable args)
  def self.bench_multiply_add_real(n)
    i = 0
    s = 0
    while i < n
      s = s + multiply_add(i, 20, 5)
      i = i + 1
    end
    s
  end

  def self.bench_compute_chain_real(n)
    i = 0
    s = 0
    while i < n
      s = s + compute_chain(i)
      i = i + 1
    end
    s
  end

  def self.bench_arithmetic_real(n)
    i = 0
    total = 0
    while i < n
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    total
  end

  def self.bench_loop_sum_real(n)
    i = 0
    s = 0
    while i < n
      s = s + i
      i = i + 1
    end
    s
  end

  def self.fib(n)
    return n if n < 2
    fib(n - 1) + fib(n - 2)
  end

  def self.bench_fibonacci(n)
    i = 0
    result = 0
    while i < n
      result = fib(30)
      i = i + 1
    end
    result
  end
end

# ── Compile to JAR ──
def compile_jvm_bench
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  source_path = File.join(tmp_dir, "jvm_bench.rb")
  rbs_path = File.join(tmp_dir, "jvm_bench.rbs")
  jar_path = File.join(tmp_dir, "jvm_bench.jar")

  File.write(source_path, JVM_BENCH_JIT_SOURCE)
  File.write(rbs_path, JVM_BENCH_RBS)

  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: jar_path,
    target: :jvm,
    rbs_paths: [rbs_path],
    optimize: true
  ).compile

  jar_path
ensure
  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil
end

def measure_ruby(name, n)
  yield  # warmup
  GC.disable
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  elapsed_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  GC.enable
  elapsed_ms = (elapsed_s * 1000).round(2)
  [elapsed_ms, result]
end

def parse_jvm_results(output)
  results = {}
  output.each_line do |line|
    line = line.strip
    if line.start_with?("RESULT:")
      parts = line.split(":")
      name = parts[1]
      ns = parts[2].to_i
      value = parts[3].to_i
      ms = ns / 1_000_000.0
      results[name] = { ms: ms, value: value }
    end
  end
  results
end

def print_row(label, ruby_ms, jvm_ms, match)
  if jvm_ms > 0 && ruby_ms > 0
    if jvm_ms < ruby_ms
      ratio = "%.1fx faster" % [ruby_ms.to_f / jvm_ms]
    else
      ratio = "%.1fx slower" % [jvm_ms.to_f / ruby_ms]
    end
  else
    ratio = "N/A"
  end
  check = match ? "OK" : "MISMATCH!"
  printf "  %-28s  %8.2f ms  %8.2f ms  %-14s  %s\n", label, ruby_ms, jvm_ms.to_f, ratio, check
end

# ── Main ──
puts "JVM Backend Performance Benchmark"
puts "=" * 80
puts "  Ruby: #{RUBY_DESCRIPTION}"
puts "  Java: #{`#{JAVA_CMD} -version 2>&1`.lines.first.strip}"
puts "  Iterations: #{ITERATIONS.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')}"
puts "  (fibonacci: 10 x fib(30))"
puts "=" * 80
puts

# Step 1: Compile
puts "Compiling to JVM bytecode..."
jar_path = compile_jvm_bench
puts "  -> #{jar_path}"
puts

# Step 2: Run JVM benchmark
puts "Running JVM benchmark (includes warmup)..."
jvm_output = `#{JAVA_CMD} -jar #{jar_path} 2>&1`
jvm_results = parse_jvm_results(jvm_output)
puts "  -> Done"
puts

# Step 3: Run Pure Ruby benchmarks
puts "Running Pure Ruby benchmarks..."

# JIT-friendly
ruby_ma_jit_ms, ruby_ma_jit_val = measure_ruby("multiply_add_jit", ITERATIONS) {
  PureRuby.bench_multiply_add_jit(ITERATIONS)
}
ruby_cc_jit_ms, ruby_cc_jit_val = measure_ruby("compute_chain_jit", ITERATIONS) {
  PureRuby.bench_compute_chain_jit(ITERATIONS)
}
ruby_ar_jit_ms, ruby_ar_jit_val = measure_ruby("arithmetic_jit", ITERATIONS) {
  PureRuby.bench_arithmetic_jit(ITERATIONS)
}
ruby_ls_jit_ms, ruby_ls_jit_val = measure_ruby("loop_sum_jit", ITERATIONS) {
  PureRuby.bench_loop_sum_jit(ITERATIONS)
}

# Anti-optimization
ruby_ma_real_ms, ruby_ma_real_val = measure_ruby("multiply_add_real", ITERATIONS) {
  PureRuby.bench_multiply_add_real(ITERATIONS)
}
ruby_cc_real_ms, ruby_cc_real_val = measure_ruby("compute_chain_real", ITERATIONS) {
  PureRuby.bench_compute_chain_real(ITERATIONS)
}
ruby_ar_real_ms, ruby_ar_real_val = measure_ruby("arithmetic_real", ITERATIONS) {
  PureRuby.bench_arithmetic_real(ITERATIONS)
}
ruby_ls_real_ms, ruby_ls_real_val = measure_ruby("loop_sum_real", ITERATIONS) {
  PureRuby.bench_loop_sum_real(ITERATIONS)
}

# Fibonacci (same for both)
ruby_fb_ms, ruby_fb_val = measure_ruby("fibonacci", 10) {
  PureRuby.bench_fibonacci(10)
}
puts "  -> Done"
puts

# Step 4: Compare
N = ITERATIONS / 1_000_000

puts
puts "=" * 80
puts "  MODE 1: JIT-Friendly (constant args — HotSpot can constant-fold)"
puts "=" * 80
printf "  %-28s  %8s     %8s     %-14s  %s\n", "Benchmark", "Ruby", "JVM", "Ratio", "Match"
puts "  " + "-" * 76

jvm_ma_jit = jvm_results.dig("multiply_add_jit", :ms) || 0
jvm_cc_jit = jvm_results.dig("compute_chain_jit", :ms) || 0
jvm_ar_jit = jvm_results.dig("arithmetic_jit", :ms) || 0
jvm_ls_jit = jvm_results.dig("loop_sum_jit", :ms) || 0

print_row("Multiply Add (#{N}M)", ruby_ma_jit_ms, jvm_ma_jit,
  ruby_ma_jit_val == (jvm_results.dig("multiply_add_jit", :value) || -1))
print_row("Compute Chain (#{N}M)", ruby_cc_jit_ms, jvm_cc_jit,
  ruby_cc_jit_val == (jvm_results.dig("compute_chain_jit", :value) || -1))
print_row("Arithmetic (#{N}M)", ruby_ar_jit_ms, jvm_ar_jit,
  ruby_ar_jit_val == (jvm_results.dig("arithmetic_jit", :value) || -1))
print_row("Loop Sum (#{N}M)", ruby_ls_jit_ms, jvm_ls_jit,
  ruby_ls_jit_val == (jvm_results.dig("loop_sum_jit", :value) || -1))
puts

puts "=" * 80
puts "  MODE 2: Anti-Optimization (variable args, accumulation — prevents DCE)"
puts "=" * 80
printf "  %-28s  %8s     %8s     %-14s  %s\n", "Benchmark", "Ruby", "JVM", "Ratio", "Match"
puts "  " + "-" * 76

jvm_ma_real = jvm_results.dig("multiply_add_real", :ms) || 0
jvm_cc_real = jvm_results.dig("compute_chain_real", :ms) || 0
jvm_ar_real = jvm_results.dig("arithmetic_real", :ms) || 0
jvm_ls_real = jvm_results.dig("loop_sum_real", :ms) || 0

print_row("Multiply Add (#{N}M)", ruby_ma_real_ms, jvm_ma_real,
  ruby_ma_real_val == (jvm_results.dig("multiply_add_real", :value) || -1))
print_row("Compute Chain (#{N}M)", ruby_cc_real_ms, jvm_cc_real,
  ruby_cc_real_val == (jvm_results.dig("compute_chain_real", :value) || -1))
print_row("Arithmetic (#{N}M)", ruby_ar_real_ms, jvm_ar_real,
  ruby_ar_real_val == (jvm_results.dig("arithmetic_real", :value) || -1))
print_row("Loop Sum (#{N}M)", ruby_ls_real_ms, jvm_ls_real,
  ruby_ls_real_val == (jvm_results.dig("loop_sum_real", :value) || -1))
puts

puts "=" * 80
puts "  Fibonacci fib(30) x 10  (recursive — hard to optimize away)"
puts "=" * 80
printf "  %-28s  %8s     %8s     %-14s  %s\n", "Benchmark", "Ruby", "JVM", "Ratio", "Match"
puts "  " + "-" * 76

jvm_fb = jvm_results.dig("fibonacci", :ms) || 0
print_row("fib(30) x 10", ruby_fb_ms, jvm_fb,
  ruby_fb_val == (jvm_results.dig("fibonacci", :value) || -1))
puts

puts "-" * 80
puts "Note: JVM times = System.nanoTime() inside compiled code."
puts "      JIT-Friendly: HotSpot may constant-fold/vectorize (best-case JVM)."
puts "      Anti-Optimization: loop var as arg prevents constant folding (realistic)."
puts "      Fibonacci: recursive calls — neither JIT trick helps much."
puts "      Pure Ruby measured with YJIT enabled, GC disabled, 1 warmup run."
puts "-" * 80

# Cleanup
File.unlink(jar_path) rescue nil
