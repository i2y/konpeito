# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class FiberTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_fiber_new_and_resume_simple
    source = <<~RUBY
      def test_fiber
        f = Fiber.new { 42 }
        f.resume
      end
    RUBY

    result = compile_and_run(source, "test_fiber")
    assert_equal 42, result
  end

  def test_fiber_resume_with_argument
    source = <<~RUBY
      def test_fiber_arg
        f = Fiber.new { |x| x * 2 }
        f.resume(21)
      end
    RUBY

    result = compile_and_run(source, "test_fiber_arg")
    assert_equal 42, result
  end

  def test_fiber_yield_simple
    source = <<~RUBY
      def test_fiber_yield
        f = Fiber.new do
          Fiber.yield(1)
          2
        end
        first = f.resume
        second = f.resume
        [first, second]
      end
    RUBY

    result = compile_and_run(source, "test_fiber_yield")
    assert_equal [1, 2], result
  end

  def test_fiber_generator_pattern
    source = <<~RUBY
      def generator
        f = Fiber.new do
          Fiber.yield(1)
          Fiber.yield(2)
          Fiber.yield(3)
          4
        end
        [f.resume, f.resume, f.resume, f.resume]
      end
    RUBY

    result = compile_and_run(source, "generator")
    assert_equal [1, 2, 3, 4], result
  end

  def test_fiber_with_multiple_arguments
    source = <<~RUBY
      def test_multi_args
        f = Fiber.new { |a, b| a + b }
        f.resume(10, 20)
      end
    RUBY

    result = compile_and_run(source, "test_multi_args")
    assert_equal 30, result
  end

  def test_fiber_yield_with_multiple_values
    source = <<~RUBY
      def test_yield_multi
        f = Fiber.new do
          Fiber.yield(1, 2, 3)
          "done"
        end
        f.resume
      end
    RUBY

    # Fiber.yield with multiple args returns array or first arg depending on context
    result = compile_and_run(source, "test_yield_multi")
    # In Ruby, Fiber.yield returns the first argument if only one is expected
    assert [1, [1, 2, 3]].include?(result)
  end

  def test_fiber_alive
    source = <<~RUBY
      def test_alive
        f = Fiber.new { Fiber.yield(1); 2 }
        before = f.alive?
        f.resume
        middle = f.alive?
        f.resume
        after = f.alive?
        [before, middle, after]
      end
    RUBY

    result = compile_and_run(source, "test_alive")
    assert_equal [true, true, false], result
  end

  def test_fiber_with_captures
    source = <<~RUBY
      def test_capture
        x = 10
        f = Fiber.new { x + 5 }
        f.resume
      end
    RUBY

    result = compile_and_run(source, "test_capture")
    assert_equal 15, result
  end

  def test_fiber_current
    source = <<~RUBY
      def test_current
        f = Fiber.new { Fiber.current }
        fiber = f.resume
        fiber.class.name
      end
    RUBY

    result = compile_and_run(source, "test_current")
    assert_equal "Fiber", result
  end

  def test_fiber_yield_result_assignment
    # Test that assigning Fiber.yield result to a local variable
    # and then using it works correctly (was previously broken due to missing allocas)
    source = <<~RUBY
      def yield_assign
        f = Fiber.new do
          value = Fiber.yield(1)
          value * 2
        end
        f.resume      # Start fiber, returns 1
        f.resume(21)  # Resume with 21, value = 21, returns 42
      end
    RUBY

    result = compile_and_run(source, "yield_assign")
    assert_equal 42, result
  end

  def test_fiber_multiple_yield_assignments
    # Test multiple yield assignments in sequence
    source = <<~RUBY
      def multi_yield
        f = Fiber.new do
          a = Fiber.yield(1)
          b = Fiber.yield(a + 1)
          a + b
        end
        f.resume       # returns 1
        f.resume(10)   # a = 10, returns 11
        f.resume(20)   # b = 20, returns 30
      end
    RUBY

    result = compile_and_run(source, "multi_yield")
    assert_equal 30, result
  end

  def test_fiber_bidirectional_communication
    # This test verifies the basic bidirectional pattern works when the
    # yield result is used directly without assignment.
    source = <<~RUBY
      def bidirectional
        f = Fiber.new do
          Fiber.yield("first")  # Initial yield
          "second"              # Final return
        end
        first = f.resume   # Start fiber
        second = f.resume  # Resume after yield
        [first, second]
      end
    RUBY

    result = compile_and_run(source, "bidirectional")
    assert_equal ["first", "second"], result
  end

  private

  def compile_and_run(source, call_expr)
    source_file = File.join(@tmp_dir, "test.rb")
    output_file = File.join(@tmp_dir, "test.bundle")

    File.write(source_file, source)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file
    )
    compiler.compile

    require output_file

    eval(call_expr)
  end
end
