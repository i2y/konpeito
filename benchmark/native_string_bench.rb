# frozen_string_literal: true

# NativeString Benchmark
#
# Compares NativeString byte operations vs Ruby String operations
# Run: bundle exec ruby benchmark/native_string_bench.rb

require "bundler/setup"
require "benchmark/ips"
require "konpeito"
require "tempfile"
require "fileutils"

puts "=== NativeString Benchmark ==="
puts "Ruby: #{RUBY_VERSION}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? 'enabled' : 'disabled'}"
puts

# Setup
TMP_DIR = Dir.mktmpdir

# Compile NativeString functions
def compile_native_string_bench
  source = <<~RUBY
    def native_byte_slice_bench(iterations, input)
      i = 0
      total = 0
      while i < iterations
        ns = NativeString.from(input)
        space_idx = ns.byte_index_of(32)
        if space_idx != nil
          method_len = ns.byte_slice(0, space_idx).byte_length
          total = total + method_len
        end
        i = i + 1
      end
      total
    end

    def native_starts_with_bench(iterations, input, prefix)
      i = 0
      count = 0
      while i < iterations
        ns = NativeString.from(input)
        if ns.starts_with?(prefix)
          count = count + 1
        end
        i = i + 1
      end
      count
    end

    def native_ascii_check_bench(iterations, input)
      i = 0
      count = 0
      while i < iterations
        ns = NativeString.from(input)
        if ns.ascii_only?
          count = count + 1
        end
        i = i + 1
      end
      count
    end

    def native_char_length_bench(iterations, input)
      i = 0
      total = 0
      while i < iterations
        ns = NativeString.from(input)
        total = total + ns.char_length
        i = i + 1
      end
      total
    end
  RUBY

  rbs_content = <<~RBS
    # @native
    class NativeString
      def self.from: (String s) -> NativeString
      def byte_at: (Integer index) -> Integer
      def byte_length: () -> Integer
      def byte_index_of: (Integer byte) -> Integer?
      def byte_slice: (Integer start, Integer length) -> NativeString
      def char_length: () -> Integer
      def ascii_only?: () -> bool
      def starts_with?: (String prefix) -> bool
      def to_s: () -> String
    end

    module TopLevel
      def native_byte_slice_bench: (Integer iterations, String input) -> Integer
      def native_starts_with_bench: (Integer iterations, String input, String prefix) -> Integer
      def native_ascii_check_bench: (Integer iterations, String input) -> Integer
      def native_char_length_bench: (Integer iterations, String input) -> Integer
    end
  RBS

  source_file = File.join(TMP_DIR, "native_string_bench.rb")
  rbs_file = File.join(TMP_DIR, "native_string_bench.rbs")
  output_file = File.join(TMP_DIR, "native_string_bench.bundle")

  File.write(source_file, source)
  File.write(rbs_file, rbs_content)

  compiler = Konpeito::Compiler.new(
    source_file: source_file,
    output_file: output_file,
    rbs_paths: [rbs_file]
  )
  compiler.compile

  require output_file
end

# Pure Ruby versions for comparison
def ruby_byte_slice_bench(iterations, input)
  i = 0
  total = 0
  while i < iterations
    space_idx = input.index(" ")
    if space_idx
      method_len = input[0, space_idx].bytesize
      total = total + method_len
    end
    i = i + 1
  end
  total
end

def ruby_starts_with_bench(iterations, input, prefix)
  i = 0
  count = 0
  while i < iterations
    if input.start_with?(prefix)
      count = count + 1
    end
    i = i + 1
  end
  count
end

def ruby_ascii_check_bench(iterations, input)
  i = 0
  count = 0
  while i < iterations
    if input.ascii_only?
      count = count + 1
    end
    i = i + 1
  end
  count
end

def ruby_char_length_bench(iterations, input)
  i = 0
  total = 0
  while i < iterations
    total = total + input.length
    i = i + 1
  end
  total
end

# Test data
HTTP_LINE = "GET /api/users/12345 HTTP/1.1"
UTF8_TEXT = "Hello World, \u3053\u3093\u306b\u3061\u306f"  # "Hello World, こんにちは"
ASCII_TEXT = "Hello World, this is a test string for benchmarking"
PREFIX = "GET"
ITERATIONS = 1000

# Compile
print "Compiling NativeString functions..."
compile_native_string_bench
puts " done"
puts

# Verify correctness
puts "Verifying correctness..."
puts "  byte_slice: Ruby=#{ruby_byte_slice_bench(1, HTTP_LINE)}, Native=#{native_byte_slice_bench(1, HTTP_LINE)}"
puts "  starts_with: Ruby=#{ruby_starts_with_bench(1, HTTP_LINE, PREFIX)}, Native=#{native_starts_with_bench(1, HTTP_LINE, PREFIX)}"
puts "  ascii_check: Ruby=#{ruby_ascii_check_bench(1, ASCII_TEXT)}, Native=#{native_ascii_check_bench(1, ASCII_TEXT)}"
puts "  char_length (UTF-8): Ruby=#{ruby_char_length_bench(1, UTF8_TEXT)}, Native=#{native_char_length_bench(1, UTF8_TEXT)}"
puts

# Run benchmarks
puts "=== Byte Operations (HTTP parsing) ==="
Benchmark.ips do |x|
  x.report("Ruby byte_slice (#{ITERATIONS}x)") { ruby_byte_slice_bench(ITERATIONS, HTTP_LINE) }
  x.report("Native byte_slice (#{ITERATIONS}x)") { native_byte_slice_bench(ITERATIONS, HTTP_LINE) }
  x.compare!
end

puts
puts "=== String Prefix Check ==="
Benchmark.ips do |x|
  x.report("Ruby starts_with? (#{ITERATIONS}x)") { ruby_starts_with_bench(ITERATIONS, HTTP_LINE, PREFIX) }
  x.report("Native starts_with? (#{ITERATIONS}x)") { native_starts_with_bench(ITERATIONS, HTTP_LINE, PREFIX) }
  x.compare!
end

puts
puts "=== ASCII Check ==="
Benchmark.ips do |x|
  x.report("Ruby ascii_only? (#{ITERATIONS}x)") { ruby_ascii_check_bench(ITERATIONS, ASCII_TEXT) }
  x.report("Native ascii_only? (#{ITERATIONS}x)") { native_ascii_check_bench(ITERATIONS, ASCII_TEXT) }
  x.compare!
end

puts
puts "=== Character Length (UTF-8) ==="
Benchmark.ips do |x|
  x.report("Ruby char_length (#{ITERATIONS}x)") { ruby_char_length_bench(ITERATIONS, UTF8_TEXT) }
  x.report("Native char_length (#{ITERATIONS}x)") { native_char_length_bench(ITERATIONS, UTF8_TEXT) }
  x.compare!
end

# Cleanup
FileUtils.rm_rf(TMP_DIR)
