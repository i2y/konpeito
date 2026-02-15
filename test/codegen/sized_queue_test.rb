# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class SizedQueueTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_counter = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_sized_queue_new
    result = compile_and_run(<<~RUBY, "sq_new")
      def sq_new
        sq = SizedQueue.new(10)
        sq.class.name
      end
    RUBY
    assert_equal "Thread::SizedQueue", result
  end

  def test_sized_queue_push_pop
    result = compile_and_run(<<~RUBY, "sq_push_pop")
      def sq_push_pop
        sq = SizedQueue.new(10)
        sq.push(42)
        sq.pop
      end
    RUBY
    assert_equal 42, result
  end

  def test_sized_queue_multiple_items
    result = compile_and_run(<<~RUBY, "sq_multiple")
      def sq_multiple
        sq = SizedQueue.new(10)
        sq.push(1)
        sq.push(2)
        sq.push(3)
        [sq.pop, sq.pop, sq.pop]
      end
    RUBY
    assert_equal [1, 2, 3], result
  end

  def test_sized_queue_max
    result = compile_and_run(<<~RUBY, "sq_max")
      def sq_max
        sq = SizedQueue.new(5)
        sq.max
      end
    RUBY
    assert_equal 5, result
  end

  def test_sized_queue_with_thread
    result = compile_and_run(<<~RUBY, "sq_thread")
      def sq_thread
        sq = SizedQueue.new(2)

        producer = Thread.new do
          sq.push(10)
          sq.push(20)
        end

        producer.join

        sq.pop + sq.pop
      end
    RUBY
    assert_equal 30, result
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
