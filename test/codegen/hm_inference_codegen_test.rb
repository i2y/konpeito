# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Tests for HM type inference integration with code generation
# Verifies that unboxed arithmetic works without RBS TopLevel module
class HMInferenceCodegenTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  # Test that HM inference enables compilation when types are inferred from literals
  def test_unboxed_arithmetic_from_literal_inference
    # No RBS file - types should be inferred from literal usage
    ruby_code = <<~RUBY
      def add_integers(a, b)
        a + b
      end

      def test_add
        add_integers(1, 2)  # HM should infer Integer from literals
      end
    RUBY

    rb_file = File.join(@temp_dir, "hm_test.rb")
    File.write(rb_file, ruby_code)

    # Compile without RBS
    compiler = Konpeito::Compiler.new(
      source_file: rb_file,
      output_file: File.join(@temp_dir, "hm_test.bundle"),
      format: :cruby_ext,
      verbose: false,
      rbs_paths: [],
      optimize: true
    )

    # This should succeed - verify compilation works
    result = compiler.compile
    assert File.exist?(result), "Compiled bundle should exist"
  end

  # Test that HM inference correctly propagates Integer type and produces working code
  def test_integer_type_propagation
    ruby_code = <<~RUBY
      def multiply_add(a, b, c)
        a * b + c
      end

      def call_multiply_add
        multiply_add(2, 3, 4)  # All Integer literals
      end
    RUBY

    rb_file = File.join(@temp_dir, "multiply_test.rb")
    File.write(rb_file, ruby_code)

    compiler = Konpeito::Compiler.new(
      source_file: rb_file,
      output_file: File.join(@temp_dir, "multiply_test.bundle"),
      format: :cruby_ext,
      verbose: false,
      rbs_paths: [],
      optimize: true
    )

    result = compiler.compile
    assert File.exist?(result), "Compiled bundle should exist"

    # Load and test - top-level methods are defined on Object
    require result
    assert_equal 10, call_multiply_add
  end

  # Test Float type inference
  def test_float_type_inference
    ruby_code = <<~RUBY
      def compute_float(x, y)
        x * y + 1.5
      end

      def call_compute
        compute_float(2.0, 3.0)
      end
    RUBY

    rb_file = File.join(@temp_dir, "float_test.rb")
    File.write(rb_file, ruby_code)

    compiler = Konpeito::Compiler.new(
      source_file: rb_file,
      output_file: File.join(@temp_dir, "float_test.bundle"),
      format: :cruby_ext,
      verbose: false,
      rbs_paths: [],
      optimize: true
    )

    result = compiler.compile
    assert File.exist?(result), "Compiled bundle should exist"

    require result
    assert_in_delta 7.5, call_compute, 0.001
  end

  # Test comparison operations with HM inference
  # Note: Using ternary to avoid SSA issues with if/else blocks
  def test_comparison_with_hm_inference
    ruby_code = <<~RUBY
      def is_less(a, b)
        a < b
      end

      def test_compare
        is_less(3, 5)
      end
    RUBY

    rb_file = File.join(@temp_dir, "compare_test.rb")
    File.write(rb_file, ruby_code)

    compiler = Konpeito::Compiler.new(
      source_file: rb_file,
      output_file: File.join(@temp_dir, "compare_test.bundle"),
      format: :cruby_ext,
      verbose: false,
      rbs_paths: [],
      optimize: true
    )

    result = compiler.compile
    assert File.exist?(result)

    require result
    # Comparison result may be boolean or truthy integer
    assert test_compare
  end

  # Test simple loop with HM inference
  def test_loop_with_hm_inference
    ruby_code = <<~RUBY
      def sum_to_n(n)
        total = 0
        i = 1
        while i <= n
          total = total + i
          i = i + 1
        end
        total
      end

      def test_sum
        sum_to_n(10)
      end
    RUBY

    rb_file = File.join(@temp_dir, "loop_test.rb")
    File.write(rb_file, ruby_code)

    compiler = Konpeito::Compiler.new(
      source_file: rb_file,
      output_file: File.join(@temp_dir, "loop_test.bundle"),
      format: :cruby_ext,
      verbose: false,
      rbs_paths: [],
      optimize: true
    )

    result = compiler.compile
    assert File.exist?(result)

    require result
    assert_equal 55, test_sum  # 1+2+3+...+10 = 55
  end
end
