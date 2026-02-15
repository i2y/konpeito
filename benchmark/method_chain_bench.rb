# Benchmark for method chaining - tests the boxing/unboxing optimization

require "benchmark"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "konpeito"

ITERATIONS = 2_000_000

tmp_dir = Dir.mktmpdir("chain_bench")

begin
  puts "=" * 60
  puts "Method Chaining Benchmark (Unboxed Operations)"
  puts "=" * 60
  puts "Iterations: #{ITERATIONS.to_s.gsub(/(\\d)(?=(\\d{3})+$)/, '\\1,')}"
  puts

  # Pure Ruby version
  ruby_vector = Class.new do
    attr_accessor :x, :y

    def initialize(x, y)
      @x = x
      @y = y
    end

    def length_squared
      @x * @x + @y * @y
    end

    def dot(other)
      @x * other.x + @y * other.y
    end

    # Chained method - calls dot and length_squared
    def normalized_dot(other)
      dot(other) / length_squared
    end
  end

  # Compile NativeClass version
  rbs = <<~RBS
    # @native
    class Vec2
      @x: Float
      @y: Float

      def self.new: () -> Vec2
      def x: () -> Float
      def x=: (Float value) -> Float
      def y: () -> Float
      def y=: (Float value) -> Float
      def length_squared: () -> Float
      def dot: (Vec2 other) -> Float
      def normalized_dot: (Vec2 other) -> Float
    end
  RBS

  source = <<~RUBY
    class Vec2
      def length_squared
        @x * @x + @y * @y
      end

      def dot(other)
        @x * other.x + @y * other.y
      end

      def normalized_dot(other)
        dot(other) / length_squared
      end
    end
  RUBY

  rbs_path = File.join(tmp_dir, "vec2.rbs")
  source_path = File.join(tmp_dir, "vec2.rb")
  output_path = File.join(tmp_dir, "vec2.bundle")

  File.write(rbs_path, rbs)
  File.write(source_path, source)

  compiler = Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    rbs_paths: [rbs_path],
    verbose: false
  )
  compiler.compile
  require output_path

  ruby_v1 = ruby_vector.new(3.0, 4.0)
  ruby_v2 = ruby_vector.new(1.0, 2.0)

  native_v1 = Vec2.new
  native_v1.x = 3.0
  native_v1.y = 4.0
  native_v2 = Vec2.new
  native_v2.x = 1.0
  native_v2.y = 2.0

  # Verify results match
  ruby_result = ruby_v1.normalized_dot(ruby_v2)
  native_result = native_v1.normalized_dot(native_v2)

  puts "Ruby normalized_dot result: #{ruby_result}"
  puts "Native normalized_dot result: #{native_result}"
  puts "Results match: #{(ruby_result - native_result).abs < 0.0001 ? "✓" : "✗"}"
  puts

  puts "Method Chaining (normalized_dot = dot / length_squared)"
  puts "-" * 60

  Benchmark.bm(25) do |x|
    x.report("Ruby normalized_dot:") do
      ITERATIONS.times { ruby_v1.normalized_dot(ruby_v2) }
    end

    x.report("NativeClass normalized_dot:") do
      ITERATIONS.times { native_v1.normalized_dot(native_v2) }
    end
  end

  puts
  puts "Note: NativeClass method chaining is fully unboxed - no boxing"
  puts "      between method calls (dot result -> division -> return)"

ensure
  FileUtils.rm_rf(tmp_dir)
end
