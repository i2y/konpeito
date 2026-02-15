# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class ConditionVariableTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_counter = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_cv_new
    result = compile_and_run(<<~RUBY, "cv_new")
      def cv_new
        cv = ConditionVariable.new
        cv.class.name
      end
    RUBY
    assert_equal "Thread::ConditionVariable", result
  end

  def test_cv_signal
    result = compile_and_run(<<~RUBY, "cv_signal")
      def cv_signal
        cv = ConditionVariable.new
        cv.signal
        "signaled"
      end
    RUBY
    assert_equal "signaled", result
  end

  def test_cv_broadcast
    result = compile_and_run(<<~RUBY, "cv_broadcast")
      def cv_broadcast
        cv = ConditionVariable.new
        cv.broadcast
        "broadcasted"
      end
    RUBY
    assert_equal "broadcasted", result
  end

  private

  def compile_and_run(source, method_name)
    @test_counter += 1
    source_file = File.join(@tmp_dir, "test_#{method_name}_#{@test_counter}.rb")
    output_file = File.join(@tmp_dir, "test_#{method_name}_#{@test_counter}.bundle")

    File.write(source_file, source)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file
    )
    compiler.compile

    require output_file

    send(method_name)
  end
end
