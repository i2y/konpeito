# frozen_string_literal: true

# Fiber Performance Benchmark
# Compares Konpeito-compiled Fiber operations vs Pure Ruby

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Setup temporary directory
TMP_DIR = Dir.mktmpdir

# Compile the native module
# Note: Due to LLVM IR variable naming issue with assignments inside fiber blocks,
# the benchmark uses patterns that work around this limitation.
def compile_native_module
  source = <<~RUBY
    def fiber_simple_resume(iterations)
      i = 0
      while i < iterations
        f = Fiber.new { 42 }
        f.resume
        i = i + 1
      end
      i
    end

    def fiber_with_arg(iterations)
      i = 0
      total = 0
      while i < iterations
        f = Fiber.new { |x| x * 2 }
        total = total + f.resume(i)
        i = i + 1
      end
      total
    end

    def fiber_yield_simple(iterations)
      i = 0
      total = 0
      while i < iterations
        f = Fiber.new do
          Fiber.yield(1)
          2
        end
        total = total + f.resume
        total = total + f.resume
        i = i + 1
      end
      total
    end

    def fiber_alive_check(iterations)
      i = 0
      count = 0
      while i < iterations
        f = Fiber.new { Fiber.yield(1); 2 }
        f.resume
        if f.alive?
          count = count + 1
        end
        f.resume
        i = i + 1
      end
      count
    end
  RUBY

  source_file = File.join(TMP_DIR, "fiber_bench.rb")
  output_file = File.join(TMP_DIR, "fiber_bench.bundle")

  File.write(source_file, source)

  require_relative "../lib/konpeito"
  compiler = Konpeito::Compiler.new(
    source_file: source_file,
    output_file: output_file
  )
  compiler.compile

  require output_file
end

# Pure Ruby implementations for comparison
module PureRuby
  def self.fiber_simple_resume(iterations)
    i = 0
    while i < iterations
      f = Fiber.new { 42 }
      f.resume
      i = i + 1
    end
    i
  end

  def self.fiber_with_arg(iterations)
    i = 0
    total = 0
    while i < iterations
      f = Fiber.new { |x| x * 2 }
      total = total + f.resume(i)
      i = i + 1
    end
    total
  end

  def self.fiber_yield_simple(iterations)
    i = 0
    total = 0
    while i < iterations
      f = Fiber.new do
        Fiber.yield(1)
        2
      end
      total = total + f.resume
      total = total + f.resume
      i = i + 1
    end
    total
  end

  def self.fiber_alive_check(iterations)
    i = 0
    count = 0
    while i < iterations
      f = Fiber.new { Fiber.yield(1); 2 }
      f.resume
      if f.alive?
        count = count + 1
      end
      f.resume
      i = i + 1
    end
    count
  end
end

puts "Compiling native Fiber module..."
compile_native_module

puts "\n=== Fiber Benchmark ==="
puts "Ruby version: #{RUBY_VERSION}"
puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts

# Verify correctness
ruby_result = PureRuby.fiber_simple_resume(100)
native_result = fiber_simple_resume(100)
raise "Mismatch! Ruby: #{ruby_result}, Native: #{native_result}" unless ruby_result == native_result
puts "Correctness verified for fiber_simple_resume(100): #{ruby_result}"

ruby_result = PureRuby.fiber_with_arg(100)
native_result = fiber_with_arg(100)
raise "Mismatch! Ruby: #{ruby_result}, Native: #{native_result}" unless ruby_result == native_result
puts "Correctness verified for fiber_with_arg(100): #{ruby_result}"

ruby_result = PureRuby.fiber_yield_simple(100)
native_result = fiber_yield_simple(100)
raise "Mismatch! Ruby: #{ruby_result}, Native: #{native_result}" unless ruby_result == native_result
puts "Correctness verified for fiber_yield_simple(100): #{ruby_result}"

ruby_result = PureRuby.fiber_alive_check(100)
native_result = fiber_alive_check(100)
raise "Mismatch! Ruby: #{ruby_result}, Native: #{native_result}" unless ruby_result == native_result
puts "Correctness verified for fiber_alive_check(100): #{ruby_result}"

puts "\n--- Benchmark: fiber_simple_resume(1000) ---"
puts "Creates and resumes 1000 simple fibers"
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.fiber_simple_resume(1000) }
  x.report("Konpeito") { fiber_simple_resume(1000) }
  x.compare!
end

puts "\n--- Benchmark: fiber_with_arg(1000) ---"
puts "Creates 1000 fibers with argument passing"
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.fiber_with_arg(1000) }
  x.report("Konpeito") { fiber_with_arg(1000) }
  x.compare!
end

puts "\n--- Benchmark: fiber_yield_simple(500) ---"
puts "Creates 500 fibers with yield/resume pattern"
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.fiber_yield_simple(500) }
  x.report("Konpeito") { fiber_yield_simple(500) }
  x.compare!
end

puts "\n--- Benchmark: fiber_alive_check(500) ---"
puts "Creates 500 fibers with alive? check"
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.fiber_alive_check(500) }
  x.report("Konpeito") { fiber_alive_check(500) }
  x.compare!
end

# Cleanup
FileUtils.rm_rf(TMP_DIR)
