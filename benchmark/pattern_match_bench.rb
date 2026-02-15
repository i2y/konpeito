# frozen_string_literal: true

# Pattern Matching Benchmark
# Compares Native vs Pure Ruby case/in pattern matching
#
# Run: bundle exec ruby benchmark/pattern_match_bench.rb
#
# NOTE: Some benchmarks are skipped due to known limitations with
# if/else expressions that mix unboxed and boxed types.

require "benchmark/ips"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

OUTPUT_DIR = File.join(__dir__, "tmp")
FileUtils.mkdir_p(OUTPUT_DIR)

def compile_to_bundle(source, name)
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

puts "="*60
puts "Pattern Matching Benchmark (case/in)"
puts "="*60
puts

# ============================================================
# Benchmark 1: Literal Pattern (looped internally)
# ============================================================

case_in_source = <<~RUBY
  def match_literal_loop(iterations)
    i = 0
    count = 0
    while i < iterations
      val = i % 4
      result = case val
      in 0 then 1
      in 1 then 2
      in 2 then 3
      else 0
      end
      count = count + result
      i = i + 1
    end
    count
  end
RUBY

puts "Compiling literal pattern benchmark..."
begin
  require compile_to_bundle(case_in_source, "bench_case_in")
  case_in_compiled = true
rescue => e
  puts "  Failed: #{e.message}"
  case_in_compiled = false
end

# Pure Ruby version
def pure_ruby_case_in(iterations)
  i = 0
  count = 0
  while i < iterations
    val = i % 4
    result = case val
    in 0 then 1
    in 1 then 2
    in 2 then 3
    else 0
    end
    count = count + result
    i = i + 1
  end
  count
end

iterations = 10_000

puts
puts "-"*60
puts "Benchmark: Literal Pattern Matching (#{iterations} iterations)"
puts "-"*60
puts

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("Pure Ruby case/in") { pure_ruby_case_in(iterations) }

  if case_in_compiled
    x.report("Native case/in")  { match_literal_loop(iterations) }
  end

  x.compare!
end

# ============================================================
# Benchmark 2: Alternation Pattern
# ============================================================

alt_pattern_source = <<~RUBY
  def alt_pattern_loop(iterations)
    i = 0
    count = 0
    while i < iterations
      val = i % 10
      result = case val
      in 0 | 1 | 2 then 1
      in 3 | 4 | 5 then 2
      in 6 | 7 | 8 then 3
      else 0
      end
      count = count + result
      i = i + 1
    end
    count
  end
RUBY

puts
puts "Compiling alternation pattern benchmark..."
begin
  require compile_to_bundle(alt_pattern_source, "bench_alt_pattern")
  alt_pattern_compiled = true
rescue => e
  puts "  Failed: #{e.message}"
  alt_pattern_compiled = false
end

def pure_ruby_alt_pattern(iterations)
  i = 0
  count = 0
  while i < iterations
    val = i % 10
    result = case val
    in 0 | 1 | 2 then 1
    in 3 | 4 | 5 then 2
    in 6 | 7 | 8 then 3
    else 0
    end
    count = count + result
    i = i + 1
  end
  count
end

puts
puts "-"*60
puts "Benchmark: Alternation Pattern (#{iterations} iterations)"
puts "-"*60
puts

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("Pure Ruby alternation") { pure_ruby_alt_pattern(iterations) }

  if alt_pattern_compiled
    x.report("Native alternation")   { alt_pattern_loop(iterations) }
  end

  x.compare!
end

puts
puts "="*60
puts "Benchmark complete"
puts "="*60
puts
puts "NOTE: Type pattern benchmark skipped due to mixed boxed/unboxed phi limitation."

# Cleanup
FileUtils.rm_rf(OUTPUT_DIR)
