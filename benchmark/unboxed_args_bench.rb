# Benchmark for unboxed argument passing

require "benchmark"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "konpeito"

ITERATIONS = 5_000_000

tmp_dir = Dir.mktmpdir("unboxed_args_bench")

begin
  puts "=" * 60
  puts "Unboxed Argument Passing Benchmark"
  puts "=" * 60
  puts "Iterations: #{ITERATIONS.to_s.gsub(/(\\d)(?=(\\d{3})+$)/, '\\1,')}"
  puts

  # Pure Ruby version
  ruby_class = Class.new do
    def add(a, b)
      a + b
    end

    def multiply(x, y)
      x * y
    end

    def compute(a, b, c)
      sum = add(a, b)
      multiply(sum, c)
    end

    def chain_compute(a, b, c, d)
      x = add(a, b)
      y = multiply(x, c)
      add(y, d)
    end
  end

  # Compile NativeClass version
  rbs = <<~RBS
    # @native
    class Calc
      def add: (Float a, Float b) -> Float
      def multiply: (Float x, Float y) -> Float
      def compute: (Float a, Float b, Float c) -> Float
      def chain_compute: (Float a, Float b, Float c, Float d) -> Float
    end
  RBS

  source = <<~RUBY
    class Calc
      def add(a, b)
        a + b
      end

      def multiply(x, y)
        x * y
      end

      def compute(a, b, c)
        sum = add(a, b)
        multiply(sum, c)
      end

      def chain_compute(a, b, c, d)
        x = add(a, b)
        y = multiply(x, c)
        add(y, d)
      end
    end
  RUBY

  rbs_path = File.join(tmp_dir, "calc.rbs")
  source_path = File.join(tmp_dir, "calc.rb")
  output_path = File.join(tmp_dir, "calc.bundle")

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

  ruby_obj = ruby_class.new
  native_obj = Calc.new

  a, b, c, d = 2.0, 3.0, 4.0, 5.0

  # Verify results match
  puts "Verifying results match..."
  puts "  Ruby compute: #{ruby_obj.compute(a, b, c)}"
  puts "  Native compute: #{native_obj.compute(a, b, c)}"
  puts "  Ruby chain_compute: #{ruby_obj.chain_compute(a, b, c, d)}"
  puts "  Native chain_compute: #{native_obj.chain_compute(a, b, c, d)}"
  puts

  puts "1. compute(a, b, c) = add(a, b) * c"
  puts "   (Tests argument passing between methods)"
  puts "-" * 60

  Benchmark.bm(25) do |x|
    x.report("Ruby compute:") do
      ITERATIONS.times { ruby_obj.compute(a, b, c) }
    end

    x.report("NativeClass compute:") do
      ITERATIONS.times { native_obj.compute(a, b, c) }
    end
  end

  puts
  puts "2. chain_compute(a, b, c, d) = add(multiply(add(a,b), c), d)"
  puts "   (Tests multiple chained method calls with arguments)"
  puts "-" * 60

  Benchmark.bm(25) do |x|
    x.report("Ruby chain_compute:") do
      ITERATIONS.times { ruby_obj.chain_compute(a, b, c, d) }
    end

    x.report("NativeClass chain_compute:") do
      ITERATIONS.times { native_obj.chain_compute(a, b, c, d) }
    end
  end

  puts
  puts "Note: NativeClass methods pass arguments unboxed between calls."
  puts "      No rb_float_new/NUM2DBL overhead between method calls."

ensure
  FileUtils.rm_rf(tmp_dir)
end
