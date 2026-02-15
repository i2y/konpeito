# frozen_string_literal: true

# Benchmark for native method performance (unboxed arithmetic)
# Compares NativeClass methods against pure Ruby methods

require "benchmark"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

class NativeMethodBenchmark
  ITERATIONS = 10_000_000
  SMALL_ITERATIONS = 1_000_000

  def initialize
    @tmp_dir = Dir.mktmpdir("konpeito_bench")
  end

  def run
    puts "=" * 70
    puts "Ruby Native Compiler - Native Method Benchmark"
    puts "=" * 70
    puts "Ruby version: #{RUBY_VERSION}"
    puts "Iterations: #{ITERATIONS.to_s.gsub(/(\\d)(?=(\\d{3})+$)/, '\\1,')}"
    puts "=" * 70
    puts

    benchmark_arithmetic_method
    benchmark_vector_operations
    benchmark_complex_computation
  ensure
    FileUtils.rm_rf(@tmp_dir)
  end

  private

  # ============================================
  # 1. Simple Arithmetic Method
  # ============================================
  def benchmark_arithmetic_method
    puts "1. Simple Arithmetic Method (a + b)"
    puts "-" * 50

    # Pure Ruby version
    ruby_class = Class.new do
      def add(a, b)
        a + b
      end
    end

    # Compile NativeClass version
    native_ext = compile_native_class(
      "arith_bench",
      <<~RBS,
        # @native
        class Arithmetic
          def add: (Float a, Float b) -> Float
        end
      RBS
      <<~RUBY
        class Arithmetic
          def add(a, b)
            a + b
          end
        end
      RUBY
    )

    require native_ext

    ruby_obj = ruby_class.new
    native_obj = Arithmetic.new

    a = 3.14
    b = 2.71

    Benchmark.bm(25) do |x|
      x.report("Ruby add:") do
        ITERATIONS.times { ruby_obj.add(a, b) }
      end

      x.report("NativeClass add:") do
        ITERATIONS.times { native_obj.add(a, b) }
      end
    end

    puts
  end

  # ============================================
  # 2. Vector Operations
  # ============================================
  def benchmark_vector_operations
    puts "2. Vector Operations (length_squared, dot product)"
    puts "-" * 50

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
    end

    # Compile NativeClass version
    native_ext = compile_native_class(
      "vector_bench",
      <<~RBS,
        # @native
        class Vector2D
          @x: Float
          @y: Float

          def self.new: () -> Vector2D
          def x: () -> Float
          def x=: (Float value) -> Float
          def y: () -> Float
          def y=: (Float value) -> Float
          def length_squared: () -> Float
          def dot: (Vector2D other) -> Float
        end
      RBS
      <<~RUBY
        class Vector2D
          def length_squared
            @x * @x + @y * @y
          end

          def dot(other)
            @x * other.x + @y * other.y
          end
        end
      RUBY
    )

    require native_ext

    ruby_v1 = ruby_vector.new(3.0, 4.0)
    ruby_v2 = ruby_vector.new(1.0, 2.0)

    native_v1 = Vector2D.new
    native_v1.x = 3.0
    native_v1.y = 4.0
    native_v2 = Vector2D.new
    native_v2.x = 1.0
    native_v2.y = 2.0

    Benchmark.bm(25) do |x|
      x.report("Ruby length_squared:") do
        SMALL_ITERATIONS.times { ruby_v1.length_squared }
      end

      x.report("NativeClass length_squared:") do
        SMALL_ITERATIONS.times { native_v1.length_squared }
      end

      x.report("Ruby dot:") do
        SMALL_ITERATIONS.times { ruby_v1.dot(ruby_v2) }
      end

      x.report("NativeClass dot:") do
        SMALL_ITERATIONS.times { native_v1.dot(native_v2) }
      end
    end

    puts
  end

  # ============================================
  # 3. Complex Computation
  # ============================================
  def benchmark_complex_computation
    puts "3. Complex Computation (multiple operations)"
    puts "-" * 50

    # Pure Ruby version
    ruby_class = Class.new do
      def compute(a, b, c)
        (a * b + c) * (a - b)
      end
    end

    # Compile NativeClass version
    native_ext = compile_native_class(
      "compute_bench",
      <<~RBS,
        # @native
        class Computer
          def compute: (Float a, Float b, Float c) -> Float
        end
      RBS
      <<~RUBY
        class Computer
          def compute(a, b, c)
            (a * b + c) * (a - b)
          end
        end
      RUBY
    )

    require native_ext

    ruby_obj = ruby_class.new
    native_obj = Computer.new

    a = 3.14
    b = 2.71
    c = 1.41

    Benchmark.bm(25) do |x|
      x.report("Ruby compute:") do
        SMALL_ITERATIONS.times { ruby_obj.compute(a, b, c) }
      end

      x.report("NativeClass compute:") do
        SMALL_ITERATIONS.times { native_obj.compute(a, b, c) }
      end
    end

    puts
  end

  # ============================================
  # Helper Methods
  # ============================================

  def compile_native_class(name, rbs_content, ruby_code)
    rbs_path = File.join(@tmp_dir, "#{name}.rbs")
    source_path = File.join(@tmp_dir, "#{name}.rb")
    output_path = File.join(@tmp_dir, "#{name}.bundle")

    File.write(rbs_path, rbs_content)
    File.write(source_path, ruby_code)

    compiler = Konpeito::Compiler.new(
      source_file: source_path,
      output_file: output_path,
      rbs_paths: [rbs_path],
      verbose: false
    )
    compiler.compile

    output_path
  end
end

# Run benchmark
NativeMethodBenchmark.new.run
