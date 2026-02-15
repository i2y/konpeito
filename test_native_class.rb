# frozen_string_literal: true

# Simple test for NativeClass (Point with x, y fields)

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "konpeito"

source = <<~RUBY
  def test_create
    p = Point.new
    p.x = 3.0
    p.y = 4.0
    p.x
  end

  def test_distance(x1, y1, x2, y2)
    p1 = Point.new
    p1.x = x1
    p1.y = y1

    p2 = Point.new
    p2.x = x2
    p2.y = y2

    dx = p2.x - p1.x
    dy = p2.y - p1.y
    dx * dx + dy * dy
  end

  def test_sum_coords
    p = Point.new
    p.x = 10.0
    p.y = 20.0
    p.x + p.y
  end
RUBY

rbs = <<~RBS
  # @native
  class Point
    @x: Float
    @y: Float

    def self.new: () -> Point
    def x: () -> Float
    def x=: (Float value) -> Float
    def y: () -> Float
    def y=: (Float value) -> Float
  end

  class Object
    def test_create: () -> Float
    def test_distance: (Float x1, Float y1, Float x2, Float y2) -> Float
    def test_sum_coords: () -> Float
  end
RBS

require "tempfile"
require "fileutils"

tmp_dir = "tmp"
FileUtils.mkdir_p(tmp_dir)

source_path = File.join(tmp_dir, "test_native_class.rb")
rbs_path = File.join(tmp_dir, "test_native_class.rbs")
output_path = File.join(tmp_dir, "test_native_class.bundle")

File.write(source_path, source)
File.write(rbs_path, rbs)

compiler = Konpeito::Compiler.new(
  source_file: source_path,
  output_file: output_path,
  format: :cruby_ext,
  rbs_paths: [rbs_path],
  optimize: false,
  verbose: true
)

# Patch to capture LLVM IR
module Konpeito
  module Codegen
    class LLVMGenerator
      def to_ir
        @mod.to_s
      end
    end
  end
end

puts "Compiling..."

# Manual compilation steps to capture IR
ast = compiler.send(:parse)
typed_ast = compiler.send(:type_check_ast, ast)
hir = compiler.send(:generate_hir, typed_ast)

puts "\n=== HIR Functions ==="
hir.functions.each do |func|
  puts "Function: #{func.name}"
  func.body.each do |block|
    puts "  Block: #{block.label}"
    block.instructions.each do |inst|
      puts "    #{inst.class.name.split('::').last}: #{inst.result_var}"
    end
    puts "    Terminator: #{block.terminator.class.name.split('::').last}" if block.terminator
  end
end

llvm_gen = Konpeito::Codegen::LLVMGenerator.new(
  module_name: "test_native_class",
  monomorphizer: nil
)
llvm_gen.generate(hir)

puts "\n=== LLVM IR ==="
puts llvm_gen.to_ir

puts "\n=== Compiling to native ==="
backend = Konpeito::Codegen::CRubyBackend.new(
  llvm_gen,
  output_file: output_path,
  module_name: "test_native_class"
)
backend.generate
puts "Generated: #{output_path}"

puts "\n=== Testing ==="
require File.expand_path(output_path)

puts "\nTest 1: test_create"
result = Object.new.send(:test_create)
expected = 3.0
puts "test_create() = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"

puts "\nTest 2: test_distance"
# Distance squared from (0,0) to (3,4) = 9 + 16 = 25
result = Object.new.send(:test_distance, 0.0, 0.0, 3.0, 4.0)
expected = 25.0
puts "test_distance(0, 0, 3, 4) = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"

puts "\nTest 3: test_sum_coords"
result = Object.new.send(:test_sum_coords)
expected = 30.0
puts "test_sum_coords() = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"
