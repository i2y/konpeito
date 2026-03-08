# frozen_string_literal: true

# Benchmark: Compare mruby standalone vs CRuby extension vs Pure Ruby (YJIT)
#
# Usage: bundle exec ruby -I lib benchmark/mruby_bench.rb

require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

ITERATIONS = 10_000_000
NESTED_N   = 3000

# ── Source code (shared by all backends) ──

BENCH_SOURCE = <<~RUBY
  def multiply_add(a, b, c)
    a * b + c
  end

  def compute_chain(x)
    y = x * 2
    z = y + 10
    w = z * 3
    w - x
  end

  def bench_multiply_add(iterations)
    i = 0
    result = 0
    while i < iterations
      result = multiply_add(10, 20, 5)
      i = i + 1
    end
    result
  end

  def bench_compute_chain(iterations)
    i = 0
    result = 0
    while i < iterations
      result = compute_chain(100)
      i = i + 1
    end
    result
  end

  def bench_arithmetic_intensive(iterations)
    i = 0
    total = 0
    while i < iterations
      a = i * 3
      b = a + 17
      c = b * 2
      d = c - i
      total = total + d
      i = i + 1
    end
    total
  end

  def bench_loop_sum(iterations)
    i = 0
    total = 0
    while i < iterations
      total = total + i
      i = i + 1
    end
    total
  end

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

BENCH_RBS = <<~RBS
  module TopLevel
    def multiply_add: (Integer a, Integer b, Integer c) -> Integer
    def compute_chain: (Integer x) -> Integer
    def bench_multiply_add: (Integer iterations) -> Integer
    def bench_compute_chain: (Integer iterations) -> Integer
    def bench_arithmetic_intensive: (Integer iterations) -> Integer
    def bench_loop_sum: (Integer iterations) -> Integer
    def bench_nested_loop: (Integer n) -> Integer
  end
RBS

# ── Pure Ruby ──

module PureRuby
  module_eval(BENCH_SOURCE)
  module_function :multiply_add, :compute_chain,
                  :bench_multiply_add, :bench_compute_chain,
                  :bench_arithmetic_intensive, :bench_loop_sum, :bench_nested_loop
end

# ── Compile CRuby extension ──

def compile_cruby
  tmp_dir = File.expand_path("../tmp/bench_cruby", __dir__)
  FileUtils.mkdir_p(tmp_dir)
  ts = Time.now.to_i
  src = File.join(tmp_dir, "bench_#{ts}.rb")
  rbs = File.join(tmp_dir, "bench_#{ts}.rbs")
  out = File.join(tmp_dir, "bench_#{ts}.bundle")
  File.write(src, BENCH_SOURCE)
  File.write(rbs, BENCH_RBS)
  Konpeito::Compiler.new(
    source_file: src, output_file: out,
    format: :cruby_ext, rbs_paths: [rbs], optimize: true
  ).compile
  out
ensure
  File.unlink(src) rescue nil
  File.unlink(rbs) rescue nil
end

# ── Compile mruby individual binaries ──

def compile_mruby_individual(rbs_path, bench_name, *args)
  tmp_dir = File.expand_path("../tmp/bench_mruby", __dir__)
  FileUtils.mkdir_p(tmp_dir)
  ts = Time.now.to_i
  src = File.join(tmp_dir, "mb_#{bench_name}_#{ts}.rb")
  out = File.join(tmp_dir, "mb_#{bench_name}_#{ts}")
  main_code = "\ndef main\n  #{bench_name}(#{args.join(', ')})\nend\n\nmain\n"
  File.write(src, BENCH_SOURCE + main_code)
  Konpeito::Compiler.new(
    source_file: src, output_file: out,
    format: :standalone, target: :mruby,
    rbs_paths: [rbs_path], optimize: true
  ).compile
  File.unlink(src) rescue nil
  out
end

# ── Helpers ──

def measure
  GC.disable
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  GC.enable
  [elapsed, result]
end

def measure_exe(path, runs: 3)
  times = runs.times.map do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    system(path, out: File::NULL, err: File::NULL)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end
  times.min  # best of N
ensure
  File.unlink(path) rescue nil
end

# Measure startup overhead once
STARTUP_OVERHEAD = begin
  tmp = File.expand_path("../tmp/bench_mruby", __dir__)
  FileUtils.mkdir_p(tmp)
  src = File.join(tmp, "_startup.rb")
  rbs = File.join(tmp, "_startup.rbs")
  out = File.join(tmp, "_startup")
  File.write(src, "def main\nend\nmain\n")
  File.write(rbs, "module TopLevel\n  def main: () -> void\nend\n")
  Konpeito::Compiler.new(
    source_file: src, output_file: out,
    format: :standalone, target: :mruby,
    rbs_paths: [rbs], optimize: true
  ).compile
  File.unlink(src) rescue nil
  File.unlink(rbs) rescue nil
  times = 5.times.map do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    system(out, out: File::NULL, err: File::NULL)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end
  File.unlink(out) rescue nil
  times.min
end

# ── Main ──

puts "Konpeito Backend Benchmark"
puts "=========================="
puts
puts "Ruby: #{RUBY_VERSION} (YJIT: #{defined?(RubyVM::YJIT) ? 'enabled' : 'disabled'})"
puts "mruby startup overhead: #{format('%.1f', STARTUP_OVERHEAD * 1000)}ms"
puts

$stderr.puts "Compiling CRuby extension..."
cruby_path = compile_cruby
require cruby_path
$cruby_obj = Object.new

# Verify CRuby extension works
test_result = $cruby_obj.send(:bench_multiply_add, 100)
raise "CRuby ext not working (got #{test_result.inspect})" unless test_result.is_a?(Integer) && test_result > 0

mruby_tmp = File.expand_path("../tmp/bench_mruby", __dir__)
FileUtils.mkdir_p(mruby_tmp)
rbs_path = File.join(mruby_tmp, "bench_shared.rbs")
File.write(rbs_path, BENCH_RBS)

BENCHMARKS = [
  ["Multiply Add",         :bench_multiply_add,         [ITERATIONS]],
  ["Compute Chain",        :bench_compute_chain,         [ITERATIONS]],
  ["Arithmetic Intensive", :bench_arithmetic_intensive,  [ITERATIONS]],
  ["Loop Sum",             :bench_loop_sum,              [ITERATIONS]],
  ["Nested Loop",          :bench_nested_loop,           [NESTED_N]],
]

puts "=" * 86
puts "%-25s %10s %10s %10s  %10s %10s" % ["Benchmark", "Ruby+YJIT", "CRuby ext", "mruby", "ext/Ruby", "mruby/Ruby"]
puts "=" * 86

BENCHMARKS.each do |label, method, args|
  # Pure Ruby (warm up + measure)
  3.times { PureRuby.send(method, *args) }
  ruby_time, ruby_result = measure { PureRuby.send(method, *args) }

  # CRuby extension (warm up + measure)
  3.times { $cruby_obj.send(method, *args) }
  cruby_time, cruby_result = measure { $cruby_obj.send(method, *args) }

  # Verify results match
  if ruby_result != cruby_result
    $stderr.puts "  WARNING: #{method} result mismatch Ruby=#{ruby_result} CRuby=#{cruby_result}"
  end

  # mruby standalone
  $stderr.print "  Compiling #{method}... "
  mruby_exe = compile_mruby_individual(rbs_path, method.to_s, *args.map(&:to_s))
  $stderr.puts "running..."
  mruby_raw = measure_exe(mruby_exe, runs: 3)
  mruby_time = [mruby_raw - STARTUP_OVERHEAD, 0.0001].max

  ext_ratio = ruby_time / cruby_time
  mruby_ratio = ruby_time / mruby_time

  puts "%-25s %9.4fs %9.4fs %9.4fs  %9.1fx %9.1fx" % [
    label, ruby_time, cruby_time, mruby_time, ext_ratio, mruby_ratio
  ]
end

puts "=" * 86
puts
puts "Notes:"
puts "  - Ruby+YJIT  = Pure Ruby #{RUBY_VERSION} with YJIT JIT compiler"
puts "  - CRuby ext  = Konpeito LLVM O2 -> .bundle (loaded into CRuby process)"
puts "  - mruby      = Konpeito LLVM O2 -> standalone executable (mruby runtime)"
puts "  - mruby times have #{format('%.1f', STARTUP_OVERHEAD * 1000)}ms startup overhead subtracted"
puts "  - CRuby ext and mruby share the same LLVM IR + O2 optimization pipeline"
puts "  - ext/Ruby > 1 means CRuby ext is faster; mruby/Ruby > 1 means mruby is faster"

# Cleanup
File.unlink(cruby_path) rescue nil
File.unlink(rbs_path) rescue nil
