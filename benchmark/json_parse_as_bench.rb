#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: KonpeitoJSON.parse_as vs Ruby JSON.parse
#
# Compares:
# 1. Ruby JSON.parse -> Hash -> manual struct creation
# 2. KonpeitoJSON.parse_as -> NativeClass directly

require "benchmark/ips"
require "json"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Test data
SMALL_JSON = '{"x": 10, "y": 20}'
MEDIUM_JSON = '{"id": 12345, "name": "Alice", "score": 95.5, "active": true}'
LARGE_JSON = {
  id: 12345,
  name: "Alice Johnson",
  email: "alice@example.com",
  score: 95.5,
  active: true,
  tags: ["developer", "ruby", "konpeito"],
  metadata: { created_at: "2024-01-01", updated_at: "2024-12-01" }
}.to_json

# Compile Konpeito version
def compile_konpeito_parse_as
  tmp_dir = Dir.mktmpdir("json_bench_")

  source = <<~RUBY
    def parse_point(json)
      p = KonpeitoJSON.parse_as(json, Point)
      p.x + p.y
    end

    def parse_point_only(json)
      KonpeitoJSON.parse_as(json, Point)
      nil
    end
  RUBY

  rbs = <<~RBS
    class Point
      @x: Integer
      @y: Integer

      def self.new: () -> Point
      def x: () -> Integer
      def y: () -> Integer
    end

    module KonpeitoJSON
      def self.parse_as: [T] (String json, Class[T] target_class) -> T
    end

    module TopLevel
      def parse_point: (String json) -> Integer
      def parse_point_only: (String json) -> nil
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

# Ruby Point class for comparison
class RubyPoint
  attr_accessor :x, :y

  def initialize(x = 0, y = 0)
    @x = x
    @y = y
  end
end

puts "=" * 60
puts "JSON Parsing Benchmark: parse_as vs Ruby JSON"
puts "=" * 60
puts

# Compile Konpeito
print "Compiling Konpeito parse_as... "
tmp_dir = compile_konpeito_parse_as
puts "done"
puts

# Verify correctness
puts "Verification:"
puts "  Ruby JSON.parse: #{JSON.parse(SMALL_JSON)}"
konpeito_result = parse_point(SMALL_JSON)
puts "  Konpeito parse_as result: #{konpeito_result}"
puts

# Warmup
10.times { JSON.parse(SMALL_JSON) }
10.times { parse_point(SMALL_JSON) }

puts "=" * 60
puts "Benchmark 1: Small JSON (2 integer fields)"
puts "JSON: #{SMALL_JSON}"
puts "=" * 60

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Ruby JSON.parse + access") do
    h = JSON.parse(SMALL_JSON)
    h["x"] + h["y"]
  end

  x.report("Ruby JSON.parse + struct") do
    h = JSON.parse(SMALL_JSON)
    p = RubyPoint.new(h["x"], h["y"])
    p.x + p.y
  end

  x.report("Konpeito parse_as + access") do
    parse_point(SMALL_JSON)
  end

  x.compare!
end

puts
puts "=" * 60
puts "Benchmark 2: Parse only (no field access)"
puts "=" * 60

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Ruby JSON.parse") do
    JSON.parse(SMALL_JSON)
  end

  x.report("Konpeito parse_as") do
    parse_point_only(SMALL_JSON)
  end

  x.compare!
end

# Cleanup
FileUtils.rm_rf(tmp_dir)
