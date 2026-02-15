# frozen_string_literal: true

# Phi Node Optimization Benchmark
# Measures the impact of unboxed phi nodes for if/else and case/when
#
# Run: bundle exec ruby benchmark/phi_optimization_bench.rb

require "benchmark/ips"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

OUTPUT_DIR = File.join(__dir__, "tmp")
FileUtils.mkdir_p(OUTPUT_DIR)

def compile_to_bundle(source, rbs, name)
  # Write RBS file
  rbs_path = File.join(OUTPUT_DIR, "#{name}.rbs")
  File.write(rbs_path, rbs)

  loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_path])
  ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
  hir_builder = Konpeito::HIR::Builder.new(rbs_loader: loader)

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

puts "=" * 60
puts "Phi Node Optimization Benchmark"
puts "=" * 60
puts

# ============================================================
# Benchmark 1: If/Else with Integer literals + subsequent arithmetic
# ============================================================

if_else_source = <<~RUBY
  def if_else_arithmetic_loop(iterations, flag)
    i = 0
    total = 0
    while i < iterations
      # If/else returns unboxed integer (phi optimization)
      base = if flag
        10
      else
        20
      end
      # Subsequent arithmetic should also be unboxed
      total = total + base * 2
      i = i + 1
    end
    total
  end
RUBY

if_else_rbs = <<~RBS
  module TopLevel
    def if_else_arithmetic_loop: (Integer iterations, bool flag) -> Integer
  end
RBS

puts "Compiling if/else arithmetic benchmark..."
begin
  require compile_to_bundle(if_else_source, if_else_rbs, "bench_if_else")
  if_else_compiled = true
rescue => e
  puts "  Failed: #{e.message}"
  if_else_compiled = false
end

# Pure Ruby version
def pure_ruby_if_else_arithmetic(iterations, flag)
  i = 0
  total = 0
  while i < iterations
    base = if flag
      10
    else
      20
    end
    total = total + base * 2
    i = i + 1
  end
  total
end

iterations = 100_000

puts
puts "-" * 60
puts "Benchmark 1: If/Else + Arithmetic (#{iterations} iterations)"
puts "-" * 60
puts

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("Pure Ruby if/else") { pure_ruby_if_else_arithmetic(iterations, true) }

  if if_else_compiled
    x.report("Native if/else")   { if_else_arithmetic_loop(iterations, true) }
  end

  x.compare!
end

# ============================================================
# Benchmark 2: Case/When with Integer literals + subsequent arithmetic
# ============================================================

case_when_source = <<~RUBY
  def case_when_arithmetic_loop(iterations, selector)
    i = 0
    total = 0
    while i < iterations
      # Case/when returns unboxed integer (phi optimization)
      multiplier = case selector
      when 0 then 1
      when 1 then 2
      when 2 then 3
      else 4
      end
      # Subsequent arithmetic should also be unboxed
      total = total + i * multiplier
      i = i + 1
    end
    total
  end
RUBY

case_when_rbs = <<~RBS
  module TopLevel
    def case_when_arithmetic_loop: (Integer iterations, Integer selector) -> Integer
  end
RBS

puts
puts "Compiling case/when arithmetic benchmark..."
begin
  require compile_to_bundle(case_when_source, case_when_rbs, "bench_case_when")
  case_when_compiled = true
rescue => e
  puts "  Failed: #{e.message}"
  case_when_compiled = false
end

# Pure Ruby version
def pure_ruby_case_when_arithmetic(iterations, selector)
  i = 0
  total = 0
  while i < iterations
    multiplier = case selector
    when 0 then 1
    when 1 then 2
    when 2 then 3
    else 4
    end
    total = total + i * multiplier
    i = i + 1
  end
  total
end

puts
puts "-" * 60
puts "Benchmark 2: Case/When + Arithmetic (#{iterations} iterations)"
puts "-" * 60
puts

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("Pure Ruby case/when") { pure_ruby_case_when_arithmetic(iterations, 1) }

  if case_when_compiled
    x.report("Native case/when")   { case_when_arithmetic_loop(iterations, 1) }
  end

  x.compare!
end

# ============================================================
# Benchmark 3: Simple if/else with Float (simpler than nested)
# ============================================================

simple_float_source = <<~RUBY
  def simple_float_loop(iterations, flag)
    i = 0
    total = 0.0
    while i < iterations
      # Simple if/else with float results
      val = if flag
        1.5
      else
        2.5
      end
      total = total + val
      i = i + 1
    end
    total
  end
RUBY

simple_float_rbs = <<~RBS
  module TopLevel
    def simple_float_loop: (Integer iterations, bool flag) -> Float
  end
RBS

puts
puts "Compiling simple float benchmark..."
begin
  require compile_to_bundle(simple_float_source, simple_float_rbs, "bench_simple_float")
  simple_float_compiled = true
rescue => e
  puts "  Failed: #{e.message}"
  simple_float_compiled = false
end

# Pure Ruby version
def pure_ruby_simple_float(iterations, flag)
  i = 0
  total = 0.0
  while i < iterations
    val = if flag
      1.5
    else
      2.5
    end
    total = total + val
    i = i + 1
  end
  total
end

puts
puts "-" * 60
puts "Benchmark 3: Simple Float If/Else (#{iterations} iterations)"
puts "-" * 60
puts

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("Pure Ruby float") { pure_ruby_simple_float(iterations, true) }

  if simple_float_compiled
    x.report("Native float")   { simple_float_loop(iterations, true) }
  end

  x.compare!
end

# ============================================================
# Benchmark 4: Nested conditionals with Float (fixed!)
# ============================================================

nested_float_source = <<~RUBY
  def nested_float_loop(iterations, a, b)
    i = 0
    total = 0.0
    while i < iterations
      # Nested if/else with float results
      val = if a > b
        if a > 10.0
          a * 2.0
        else
          a + 5.0
        end
      else
        if b > 10.0
          b * 2.0
        else
          b + 5.0
        end
      end
      total = total + val
      i = i + 1
    end
    total
  end
RUBY

nested_float_rbs = <<~RBS
  module TopLevel
    def nested_float_loop: (Integer iterations, Float a, Float b) -> Float
  end
RBS

puts
puts "Compiling nested float benchmark..."
begin
  require compile_to_bundle(nested_float_source, nested_float_rbs, "bench_nested_float")
  nested_float_compiled = true
rescue => e
  puts "  Failed: #{e.message}"
  nested_float_compiled = false
end

# Pure Ruby version
def pure_ruby_nested_float(iterations, a, b)
  i = 0
  total = 0.0
  while i < iterations
    val = if a > b
      if a > 10.0
        a * 2.0
      else
        a + 5.0
      end
    else
      if b > 10.0
        b * 2.0
      else
        b + 5.0
      end
    end
    total = total + val
    i = i + 1
  end
  total
end

puts
puts "-" * 60
puts "Benchmark 4: Nested Float Conditionals (#{iterations} iterations)"
puts "-" * 60
puts

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("Pure Ruby nested") { pure_ruby_nested_float(iterations, 15.0, 8.0) }

  if nested_float_compiled
    x.report("Native nested")   { nested_float_loop(iterations, 15.0, 8.0) }
  end

  x.compare!
end

puts
puts "=" * 60
puts "Benchmark complete"
puts "=" * 60

# Cleanup
FileUtils.rm_rf(OUTPUT_DIR)
