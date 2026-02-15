# frozen_string_literal: true

# Benchmark NativeArray[NativeClass] vs Ruby Array of objects

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"
require "benchmark"

# Compile native version
source = <<~RUBY
  def native_particle_sum(n)
    particles = NativeArray.new(n)

    # Initialize particles
    i = 0
    while i < n
      particles[i].x = i * 1.0
      particles[i].y = i * 2.0
      i = i + 1
    end

    # Sum all coordinates
    total = 0.0
    i = 0
    while i < n
      total = total + particles[i].x + particles[i].y
      i = i + 1
    end

    total
  end

  def native_distance_sum(n)
    particles = NativeArray.new(n)

    # Place particles
    i = 0
    while i < n
      particles[i].x = i * 10.0
      particles[i].y = i * 5.0
      i = i + 1
    end

    # Sum distances between consecutive particles
    total = 0.0
    i = 0
    while i < n - 1
      dx = particles[i + 1].x - particles[i].x
      dy = particles[i + 1].y - particles[i].y
      total = total + dx * dx + dy * dy
      i = i + 1
    end

    total
  end
RUBY

rbs = <<~RBS
  # @native
  class Particle
    @x: Float
    @y: Float

    def self.new: () -> Particle
    def x: () -> Float
    def x=: (Float value) -> Float
    def y: () -> Float
    def y=: (Float value) -> Float
  end

  # Note: RBS type annotations for top-level methods would conflict with Object class.
  # The compiler uses HM type inference to determine types automatically.
RBS

require "tempfile"
require "fileutils"

tmp_dir = "tmp"
FileUtils.mkdir_p(tmp_dir)

source_path = File.join(tmp_dir, "native_array_class_bench.rb")
rbs_path = File.join(tmp_dir, "native_array_class_bench.rbs")
output_path = File.join(tmp_dir, "native_array_class_bench.bundle")

File.write(source_path, source)
File.write(rbs_path, rbs)

puts "Compiling native version..."
compiler = Konpeito::Compiler.new(
  source_file: source_path,
  output_file: output_path,
  format: :cruby_ext,
  rbs_paths: [rbs_path],
  optimize: true,
  verbose: false
)
compiler.compile

require File.expand_path(output_path)

# Pure Ruby version using objects
class RubyParticle
  attr_accessor :x, :y

  def initialize
    @x = 0.0
    @y = 0.0
  end
end

def ruby_particle_sum(n)
  particles = Array.new(n) { RubyParticle.new }

  # Initialize particles
  i = 0
  while i < n
    particles[i].x = i * 1.0
    particles[i].y = i * 2.0
    i = i + 1
  end

  # Sum all coordinates
  total = 0.0
  i = 0
  while i < n
    total = total + particles[i].x + particles[i].y
    i = i + 1
  end

  total
end

def ruby_distance_sum(n)
  particles = Array.new(n) { RubyParticle.new }

  # Place particles
  i = 0
  while i < n
    particles[i].x = i * 10.0
    particles[i].y = i * 5.0
    i = i + 1
  end

  # Sum distances between consecutive particles
  total = 0.0
  i = 0
  while i < n - 1
    dx = particles[i + 1].x - particles[i].x
    dy = particles[i + 1].y - particles[i].y
    total = total + dx * dx + dy * dy
    i = i + 1
  end

  total
end

puts "=" * 60
puts "Benchmark: NativeArray[NativeClass] vs Ruby Array[Object]"
puts "=" * 60

[1000, 10000].each do |n|
  puts "\n--- N = #{n} ---"

  # Verify correctness
  native_result = Object.new.send(:native_particle_sum, n)
  ruby_result = ruby_particle_sum(n)
  puts "particle_sum correct: #{(native_result - ruby_result).abs < 0.001}"

  native_dist = Object.new.send(:native_distance_sum, n)
  ruby_dist = ruby_distance_sum(n)
  puts "distance_sum correct: #{(native_dist - ruby_dist).abs < 0.001}"

  iterations = 100

  Benchmark.bm(25) do |x|
    x.report("Native particle_sum") do
      obj = Object.new
      iterations.times { obj.send(:native_particle_sum, n) }
    end

    x.report("Ruby particle_sum") do
      iterations.times { ruby_particle_sum(n) }
    end

    x.report("Native distance_sum") do
      obj = Object.new
      iterations.times { obj.send(:native_distance_sum, n) }
    end

    x.report("Ruby distance_sum") do
      iterations.times { ruby_distance_sum(n) }
    end
  end

  # Calculate speedup
  puts "\nSpeedup calculation:"
  native_time = Benchmark.measure { 100.times { Object.new.send(:native_particle_sum, n) } }.real
  ruby_time = Benchmark.measure { 100.times { ruby_particle_sum(n) } }.real
  puts "  particle_sum: #{(ruby_time / native_time).round(1)}x faster"

  native_time = Benchmark.measure { 100.times { Object.new.send(:native_distance_sum, n) } }.real
  ruby_time = Benchmark.measure { 100.times { ruby_distance_sum(n) } }.real
  puts "  distance_sum: #{(ruby_time / native_time).round(1)}x faster"
end
