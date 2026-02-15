# frozen_string_literal: true

# Benchmark: Compare HM inference (no RBS) vs RBS TopLevel vs Pure Ruby
# Usage: bundle exec ruby benchmark/hm_inference_bench.rb
#
# This benchmark verifies that HM type inference can enable unboxed arithmetic
# optimization without explicit RBS type annotations.

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source code to benchmark
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

  # This function calls others with literal arguments
  # HM inference should infer Integer from the literals
  def test_multiply_add
    multiply_add(10, 20, 5)
  end

  def test_compute_chain
    compute_chain(100)
  end
RUBY

# TopLevel module pattern for explicit type annotations
BENCH_RBS = <<~RBS
module TopLevel
  def multiply_add: (Integer a, Integer b, Integer c) -> Integer
  def compute_chain: (Integer x) -> Integer
  def test_multiply_add: () -> Integer
  def test_compute_chain: () -> Integer
end
RBS

def compile_native(name, rbs_content = nil)
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "#{name}_#{timestamp}.rb")
  output_path = File.join(tmp_dir, "#{name}_#{timestamp}.bundle")
  rbs_paths = []

  File.write(source_path, BENCH_SOURCE)

  if rbs_content
    rbs_path = File.join(tmp_dir, "#{name}_#{timestamp}.rbs")
    File.write(rbs_path, rbs_content)
    rbs_paths = [rbs_path]
  end

  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    format: :cruby_ext,
    rbs_paths: rbs_paths,
    optimize: true
  ).compile

  output_path
ensure
  File.unlink(source_path) rescue nil
  File.unlink(rbs_paths.first) if rbs_paths.any? rescue nil
end

# Pure Ruby implementations for comparison
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

  def self.test_multiply_add
    multiply_add(10, 20, 5)
  end

  def self.test_compute_chain
    compute_chain(100)
  end
end

puts "Compiling with HM inference only (no RBS)..."
hm_bundle = compile_native("hm_only")
require hm_bundle
$hm_obj = Object.new

module HMOnly
  class << self
    define_method(:test_multiply_add) { $hm_obj.send(:test_multiply_add) }
    define_method(:test_compute_chain) { $hm_obj.send(:test_compute_chain) }
  end
end

puts "Compiled HM: #{hm_bundle}"

puts "\nCompiling with RBS TopLevel module..."
rbs_bundle = compile_native("rbs_toplevel", BENCH_RBS)
require rbs_bundle
$rbs_obj = Object.new

module RBSTopLevel
  class << self
    define_method(:test_multiply_add) { $rbs_obj.send(:test_multiply_add) }
    define_method(:test_compute_chain) { $rbs_obj.send(:test_compute_chain) }
  end
end

puts "Compiled RBS: #{rbs_bundle}"
puts

# Verify correctness
puts "Verifying correctness..."
expected_ma = PureRuby.test_multiply_add
expected_cc = PureRuby.test_compute_chain

raise "HM multiply_add mismatch" unless HMOnly.test_multiply_add == expected_ma
raise "HM compute_chain mismatch" unless HMOnly.test_compute_chain == expected_cc
raise "RBS multiply_add mismatch" unless RBSTopLevel.test_multiply_add == expected_ma
raise "RBS compute_chain mismatch" unless RBSTopLevel.test_compute_chain == expected_cc
puts "All results match!"
puts

puts "=" * 70
puts "Benchmark: Test Multiply Add (calls multiply_add(10, 20, 5))"
puts "=" * 70
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.test_multiply_add }
  x.report("Native (HM only)") { HMOnly.test_multiply_add }
  x.report("Native (RBS TopLevel)") { RBSTopLevel.test_multiply_add }
  x.compare!
end

puts
puts "=" * 70
puts "Benchmark: Test Compute Chain (calls compute_chain(100))"
puts "=" * 70
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.test_compute_chain }
  x.report("Native (HM only)") { HMOnly.test_compute_chain }
  x.report("Native (RBS TopLevel)") { RBSTopLevel.test_compute_chain }
  x.compare!
end

puts
puts "-" * 70
puts "Note: The performance difference between HM-only and RBS TopLevel"
puts "shows whether TypeVar resolution for unboxed arithmetic is working."
puts "-" * 70

# Cleanup
File.unlink(hm_bundle) rescue nil
File.unlink(rbs_bundle) rescue nil
