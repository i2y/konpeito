# frozen_string_literal: true

# Simple test for NativeArray

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "konpeito"

source = <<~RUBY
  def test_alloc(n)
    arr = NativeArray.new(n)
    arr.length
  end

  def test_set(n)
    arr = NativeArray.new(n)
    arr[0] = 3.14
    arr[0]
  end

  def test_fill(n)
    arr = NativeArray.new(n)

    # Just fill array
    i = 0
    while i < n
      arr[i] = i * 1.5
      i = i + 1
    end

    arr[0]
  end

  def test_read_sum(n)
    arr = NativeArray.new(n)

    # Fill with simple values
    i = 0
    while i < n
      arr[i] = 1.0
      i = i + 1
    end

    # Try to read all values
    total = arr[0]
    total = total + arr[1]
    total = total + arr[2]

    total
  end
RUBY

rbs = <<~RBS
  class NativeArray[T]
    def self.new: (Integer size) -> NativeArray[Float]
    def []: (Integer index) -> Float
    def []=: (Integer index, Float value) -> Float
    def length: () -> Integer
  end

  class Object
    def test_alloc: (Integer n) -> Integer
    def test_set: (Integer n) -> Float
    def test_fill: (Integer n) -> Float
    def test_read_sum: (Integer n) -> Float
  end
RBS

require "tempfile"
require "fileutils"

tmp_dir = "tmp"
FileUtils.mkdir_p(tmp_dir)

source_path = File.join(tmp_dir, "test_native.rb")
rbs_path = File.join(tmp_dir, "test_native.rbs")
output_path = File.join(tmp_dir, "test_native.bundle")

File.write(source_path, source)
File.write(rbs_path, rbs)

compiler = Konpeito::Compiler.new(
  source_file: source_path,
  output_file: output_path,
  format: :cruby_ext,
  rbs_paths: [rbs_path],
  optimize: false,  # Disable optimization for debugging
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
  module_name: "test_native",
  monomorphizer: nil
)
llvm_gen.generate(hir)

puts "\n=== LLVM IR ==="
puts llvm_gen.to_ir

puts "\n=== Compiling to native ==="
backend = Konpeito::Codegen::CRubyBackend.new(
  llvm_gen,
  output_file: output_path,
  module_name: "test_native"
)
backend.generate
puts "Generated: #{output_path}"

puts "\n=== Testing ==="
require File.expand_path(output_path)

puts "\nTest 1: test_alloc"
result = Object.new.send(:test_alloc, 10)
puts "test_alloc(10) = #{result}"
puts "Expected: 10"
puts result == 10 ? "PASS" : "FAIL"

puts "\nTest 2: test_set"
result = Object.new.send(:test_set, 5)
expected = 3.14
puts "test_set(5) = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"

puts "\nTest 3: test_fill"
result = Object.new.send(:test_fill, 5)
# arr[0] = 0 * 1.5 = 0.0
expected = 0.0
puts "test_fill(5) = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"

puts "\nTest 4: test_read_sum"
result = Object.new.send(:test_read_sum, 5)
# 1.0 + 1.0 + 1.0 = 3.0
expected = 3.0
puts "test_read_sum(5) = #{result}"
puts "Expected: #{expected}"
puts (result - expected).abs < 0.001 ? "PASS" : "FAIL"
result = Object.new.send(:test_alloc, 10)
puts "test_alloc(10) = #{result}"
puts "Expected: 10"
puts result == 10 ? "PASS" : "FAIL"
