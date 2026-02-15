# frozen_string_literal: true

# Test for NativeArray[NativeClass] - array of structs

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "konpeito"

source = <<~RUBY
  def test_create_and_access(n)
    particles = NativeArray.new(n)

    # Set first particle
    particles[0].x = 1.0
    particles[0].y = 2.0

    # Set second particle
    particles[1].x = 3.0
    particles[1].y = 4.0

    # Return sum of all coordinates
    particles[0].x + particles[0].y + particles[1].x + particles[1].y
  end

  def test_loop_access(n)
    particles = NativeArray.new(n)

    # Initialize particles
    i = 0
    while i < n
      particles[i].x = i * 1.0
      particles[i].y = i * 2.0
      i = i + 1
    end

    # Sum all x coordinates
    total = 0.0
    i = 0
    while i < n
      total = total + particles[i].x
      i = i + 1
    end

    total
  end

  def test_distance_sum(n)
    particles = NativeArray.new(n)

    # Place particles in a line
    i = 0
    while i < n
      particles[i].x = i * 10.0
      particles[i].y = 0.0
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

  class Object
    def test_create_and_access: (Integer n) -> Float
    def test_loop_access: (Integer n) -> Float
    def test_distance_sum: (Integer n) -> Float
  end
RBS

require "tempfile"
require "fileutils"

tmp_dir = "tmp"
FileUtils.mkdir_p(tmp_dir)

source_path = File.join(tmp_dir, "test_native_array_class.rb")
rbs_path = File.join(tmp_dir, "test_native_array_class.rbs")
output_path = File.join(tmp_dir, "test_native_array_class.bundle")

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
      case inst
      when Konpeito::HIR::NativeArrayAlloc
        puts "    NativeArrayAlloc: #{inst.result_var} (element: #{inst.element_type})"
      when Konpeito::HIR::NativeArrayGet
        puts "    NativeArrayGet: #{inst.result_var} (element: #{inst.element_type})"
      when Konpeito::HIR::NativeFieldGet
        puts "    NativeFieldGet: #{inst.result_var} (field: #{inst.field_name})"
      when Konpeito::HIR::NativeFieldSet
        puts "    NativeFieldSet: (field: #{inst.field_name})"
      else
        puts "    #{inst.class.name.split('::').last}: #{inst.result_var}"
      end
    end
    puts "    Terminator: #{block.terminator.class.name.split('::').last}" if block.terminator
  end
end

llvm_gen = Konpeito::Codegen::LLVMGenerator.new(
  module_name: "test_native_array_class",
  monomorphizer: nil
)
llvm_gen.generate(hir)

puts "\n=== LLVM IR ==="
puts llvm_gen.to_ir

puts "\n=== Compiling to native ==="
backend = Konpeito::Codegen::CRubyBackend.new(
  llvm_gen,
  output_file: output_path,
  module_name: "test_native_array_class"
)
backend.generate
puts "Generated: #{output_path}"

puts "\n=== Testing ==="
require File.expand_path(output_path)

puts "\nTest 1: test_create_and_access"
result = Object.new.send(:test_create_and_access, 5)
expected = 1.0 + 2.0 + 3.0 + 4.0  # 10.0
puts "test_create_and_access(5) = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"

puts "\nTest 2: test_loop_access"
result = Object.new.send(:test_loop_access, 5)
# Sum of 0*1.0 + 1*1.0 + 2*1.0 + 3*1.0 + 4*1.0 = 0+1+2+3+4 = 10.0
expected = 10.0
puts "test_loop_access(5) = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"

puts "\nTest 3: test_distance_sum"
result = Object.new.send(:test_distance_sum, 5)
# Distance squared between consecutive particles at x=0,10,20,30,40
# Each distance squared = 10*10 = 100, 4 pairs = 400
expected = 400.0
puts "test_distance_sum(5) = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"
