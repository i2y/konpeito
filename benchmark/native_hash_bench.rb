# frozen_string_literal: true

# NativeHash[K, V] Benchmark
# Compare NativeHash with generic inference vs Ruby Hash
#
# Features:
# - Generic type parameters (K, V) inferred from usage
# - Automatic resizing when load factor exceeds 0.75
# - Linear probing with open addressing

require "benchmark/ips"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

def compile_native_hash_benchmark
  tmp_dir = Dir.mktmpdir("native_hash_bench_")

  source = <<~RUBY
    # Basic get/set benchmark
    def hash_get_set(n)
      h = NativeHash.new
      i = 0
      while i < n
        h[i] = i * 2
        i = i + 1
      end

      total = 0
      i = 0
      while i < n
        total = total + h[i]
        i = i + 1
      end
      total
    end
  RUBY

  # Using generic syntax with inference
  rbs = <<~RBS
    class NativeHash[K, V]
      def self.new: () -> NativeHash[K, V]
      def []: (K key) -> V
      def []=: (K key, V value) -> V
    end

    module TopLevel
      def hash_get_set: (Integer n) -> Integer
    end
  RBS

  source_path = File.join(tmp_dir, "bench.rb")
  rbs_path = File.join(tmp_dir, "bench.rbs")
  output_path = File.join(tmp_dir, "bench.bundle")

  File.write(source_path, source)
  File.write(rbs_path, rbs)

  compiler = Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    rbs_paths: [rbs_path],
    verbose: false
  )

  compiler.compile
  require output_path

  tmp_dir
end

# Ruby implementation for comparison
def ruby_hash_get_set(n)
  h = {}
  i = 0
  while i < n
    h[i] = i * 2
    i = i + 1
  end

  total = 0
  i = 0
  while i < n
    total = total + h[i]
    i = i + 1
  end
  total
end

puts "Compiling NativeHash benchmark..."
tmp_dir = compile_native_hash_benchmark

puts "\n=== NativeHash[K, V] Benchmark (with generic inference) ==="
puts "Testing NativeHash[Integer, Integer] inferred from usage"
puts "Includes automatic resizing (load factor 0.75)\n"

[100, 1000].each do |n|
  # Verify correctness
  native_result = hash_get_set(n)
  ruby_result = ruby_hash_get_set(n)
  puts "\nCorrectness check (n=#{n}): Native=#{native_result}, Ruby=#{ruby_result}, Match=#{native_result == ruby_result}"

  puts "--- Get/Set Benchmark (n=#{n}) ---"
  Benchmark.ips do |x|
    x.config(time: 3, warmup: 1)

    x.report("Ruby Hash") { ruby_hash_get_set(n) }
    x.report("NativeHash") { hash_get_set(n) }

    x.compare!
  end
end

# Cleanup
FileUtils.rm_rf(tmp_dir)
exit!(0)  # Force immediate exit to avoid Ruby cleanup issues
