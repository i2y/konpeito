# frozen_string_literal: true

# Comprehensive benchmark for konpeito compiler
# Compares NativeClass performance against pure Ruby

require "benchmark"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

class ComprehensiveBenchmark
  ITERATIONS = 1_000_000

  def initialize
    @tmp_dir = Dir.mktmpdir("konpeito_bench")
    @results = {}
  end

  def run
    puts "=" * 70
    puts "Ruby Native Compiler - Comprehensive Benchmark"
    puts "=" * 70
    puts "Ruby version: #{RUBY_VERSION}"
    puts "Iterations: #{ITERATIONS.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\\1,')}"
    puts "=" * 70
    puts

    benchmark_field_access
    benchmark_bool_field
    benchmark_object_allocation
    benchmark_gc_stress

    print_summary
  ensure
    FileUtils.rm_rf(@tmp_dir)
  end

  private

  # ============================================
  # 1. Field Access Benchmark (Float)
  # ============================================
  def benchmark_field_access
    puts "1. Field Access - Float (getter/setter)"
    puts "-" * 50

    # Pure Ruby version
    ruby_point = Class.new do
      attr_accessor :x, :y
      def initialize
        @x = 0.0
        @y = 0.0
      end
    end

    # Compile NativeClass version
    native_ext = compile_native_class(
      "point_bench",
      <<~RBS,
        # @native
        class Point
          @x: Float
          @y: Float
        end
      RBS
      <<~RUBY
        class Point
        end
      RUBY
    )

    require native_ext

    ruby_obj = ruby_point.new
    native_obj = Point.new

    Benchmark.bm(25) do |x|
      @results[:field_get_ruby] = x.report("Ruby getter:") do
        ITERATIONS.times { ruby_obj.x }
      end

      @results[:field_get_native] = x.report("NativeClass getter:") do
        ITERATIONS.times { native_obj.x }
      end

      @results[:field_set_ruby] = x.report("Ruby setter:") do
        ITERATIONS.times { |i| ruby_obj.x = i.to_f }
      end

      @results[:field_set_native] = x.report("NativeClass setter:") do
        ITERATIONS.times { |i| native_obj.x = i.to_f }
      end
    end

    puts
  end

  # ============================================
  # 2. Bool Field Access Benchmark
  # ============================================
  def benchmark_bool_field
    puts "2. Field Access - Bool (getter/setter)"
    puts "-" * 50

    # Pure Ruby version
    ruby_flag = Class.new do
      attr_accessor :active, :visible
      def initialize
        @active = false
        @visible = false
      end
    end

    # Compile NativeClass version
    native_ext = compile_native_class(
      "flag_bench",
      <<~RBS,
        # @native
        class Flag
          @active: Bool
          @visible: Bool
        end
      RBS
      <<~RUBY
        class Flag
        end
      RUBY
    )

    require native_ext

    ruby_obj = ruby_flag.new
    native_obj = Flag.new

    Benchmark.bm(25) do |x|
      @results[:bool_get_ruby] = x.report("Ruby Bool getter:") do
        ITERATIONS.times { ruby_obj.active }
      end

      @results[:bool_get_native] = x.report("NativeClass Bool getter:") do
        ITERATIONS.times { native_obj.active }
      end

      @results[:bool_set_ruby] = x.report("Ruby Bool setter:") do
        ITERATIONS.times { |i| ruby_obj.active = i.even? }
      end

      @results[:bool_set_native] = x.report("NativeClass Bool setter:") do
        ITERATIONS.times { |i| native_obj.active = i.even? }
      end
    end

    puts
  end

  # ============================================
  # 3. Object Allocation Benchmark
  # ============================================
  def benchmark_object_allocation
    puts "3. Object Allocation (TypedData vs Ruby Object)"
    puts "-" * 50

    # Pure Ruby with multiple fields
    ruby_entity = Class.new do
      attr_accessor :x, :y, :z, :active
      def initialize
        @x = 0.0
        @y = 0.0
        @z = 0.0
        @active = false
      end
    end

    # Compile NativeClass
    native_ext = compile_native_class(
      "entity_bench",
      <<~RBS,
        # @native
        class Entity
          @x: Float
          @y: Float
          @z: Float
          @active: Bool
        end
      RBS
      <<~RUBY
        class Entity
        end
      RUBY
    )

    require native_ext

    alloc_iters = ITERATIONS / 10

    Benchmark.bm(25) do |x|
      @results[:alloc_ruby] = x.report("Ruby object alloc:") do
        alloc_iters.times { ruby_entity.new }
      end

      @results[:alloc_native] = x.report("NativeClass alloc:") do
        alloc_iters.times { Entity.new }
      end
    end

    puts
  end

  # ============================================
  # 4. GC Stress Test
  # ============================================
  def benchmark_gc_stress
    puts "4. GC Stress Test (allocation + collection)"
    puts "-" * 50

    # Pure Ruby
    ruby_point = Class.new do
      attr_accessor :x, :y
      def initialize
        @x = 0.0
        @y = 0.0
      end
    end

    # Native version should already be loaded from previous test
    # Point class should exist

    gc_iters = 100_000

    Benchmark.bm(25) do |x|
      @results[:gc_ruby] = x.report("Ruby + GC:") do
        gc_iters.times do |i|
          obj = ruby_point.new
          obj.x = i.to_f
          obj.y = (i * 2).to_f
          GC.start if i % 10_000 == 0
        end
      end

      @results[:gc_native] = x.report("NativeClass + GC:") do
        gc_iters.times do |i|
          obj = Point.new
          obj.x = i.to_f
          obj.y = (i * 2).to_f
          GC.start if i % 10_000 == 0
        end
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

  def print_summary
    puts "=" * 70
    puts "Summary - Performance Comparison"
    puts "=" * 70
    puts

    comparisons = [
      ["Float getter", :field_get_ruby, :field_get_native],
      ["Float setter", :field_set_ruby, :field_set_native],
      ["Bool getter", :bool_get_ruby, :bool_get_native],
      ["Bool setter", :bool_set_ruby, :bool_set_native],
      ["Object allocation", :alloc_ruby, :alloc_native],
      ["GC stress", :gc_ruby, :gc_native],
    ]

    puts format("%-25s %-15s %-15s %-15s", "Operation", "Ruby", "Native", "Ratio")
    puts "-" * 70

    comparisons.each do |label, ruby_key, native_key|
      ruby_time = @results[ruby_key]&.real
      native_time = @results[native_key]&.real

      if ruby_time && native_time && native_time > 0
        ratio = ruby_time / native_time
        ratio_str = if ratio > 1
          "#{format('%.2f', ratio)}x faster"
        elsif ratio < 1
          "#{format('%.2f', 1 / ratio)}x slower"
        else
          "same"
        end

        puts format("%-25s %-15s %-15s %-15s",
          label,
          format("%.3fs", ruby_time),
          format("%.3fs", native_time),
          ratio_str
        )
      end
    end

    puts
    puts "Interpretation:"
    puts "  - 'faster' = NativeClass outperforms pure Ruby"
    puts "  - 'slower' = Pure Ruby outperforms NativeClass"
    puts
    puts "Note: Field access involves CRuby interop overhead (TypedData_Get_Struct)."
    puts "Real speedup comes from unboxed arithmetic in native methods."
  end
end

# Run benchmark
ComprehensiveBenchmark.new.run
