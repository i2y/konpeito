# frozen_string_literal: true

# Benchmark for new syntax extensions: rescue, case/when, for loop
# This benchmark tests compilation and basic functionality

require "benchmark"
require "fileutils"
require_relative "../lib/konpeito"

OUTPUT_DIR = File.join(__dir__, "..", "tmp", "syntax_bench")
FileUtils.mkdir_p(OUTPUT_DIR)

def compile_source(source, name)
  loader = Konpeito::TypeChecker::RBSLoader.new.load
  ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
  hir_builder = Konpeito::HIR::Builder.new

  ast = Konpeito::Parser::PrismAdapter.parse(source)
  typed_ast = ast_builder.build(ast)
  hir = hir_builder.build(typed_ast)

  llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: name)
  llvm_gen.generate(hir)

  output_file = File.join(OUTPUT_DIR, "#{name}.bundle")
  backend = Konpeito::Codegen::CRubyBackend.new(
    llvm_gen,
    output_file: output_file,
    module_name: name
  )
  backend.generate
  output_file
end

# Test sources
RESCUE_SOURCE = <<~RUBY
  def test_rescue_basic
    begin
      raise "error"
    rescue StandardError => e
      "caught"
    end
  end

  def test_rescue_ensure
    result = nil
    begin
      result = "try"
    rescue
      result = "rescue"
    ensure
      result = "ensure"
    end
    result
  end
RUBY

CASE_SOURCE = <<~RUBY
  def test_case_performance(x)
    case x
    when 1
      "one"
    when 2
      "two"
    when 3
      "three"
    else
      "other"
    end
  end
RUBY

FOR_SOURCE = <<~RUBY
  def test_for_basic(arr)
    result = nil
    for x in arr
      result = x
    end
    result
  end
RUBY

puts "=" * 60
puts "Syntax Extensions Benchmark"
puts "=" * 60
puts

# Compilation benchmarks
puts "Compilation Time:"
puts "-" * 40

Benchmark.bm(20) do |x|
  x.report("rescue compile:") { compile_source(RESCUE_SOURCE, "bench_rescue") }
  x.report("case/when compile:") { compile_source(CASE_SOURCE, "bench_case") }
  x.report("for loop compile:") { compile_source(FOR_SOURCE, "bench_for") }
end

puts
puts "Compilation successful!"
puts

# Verify output files exist
%w[bench_rescue bench_case bench_for].each do |name|
  path = File.join(OUTPUT_DIR, "#{name}.bundle")
  size = File.size(path)
  puts "  #{name}.bundle: #{size} bytes"
end

puts
puts "=" * 60
puts "All syntax extensions compiled successfully!"
puts "=" * 60

# Cleanup
FileUtils.rm_rf(OUTPUT_DIR)
