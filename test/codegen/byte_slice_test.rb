# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class ByteSliceTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_counter = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # ===================
  # ByteSlice creation and basic operations
  # ===================

  def test_byte_slice_creation_and_length
    source = <<~RUBY
      def test_slice_length
        buf = ByteBuffer.new(256)
        buf.write("Hello World")
        slice = buf.slice(0, 5)
        slice.length
      end
    RUBY

    result = compile_and_run(source, "test_slice_length")
    assert_equal 5, result
  end

  def test_byte_slice_get_byte
    source = <<~RUBY
      def test_slice_get
        buf = ByteBuffer.new(256)
        buf.write("ABCDE")
        slice = buf.slice(1, 3)  # "BCD"
        slice[0] + slice[1] + slice[2]
      end
    RUBY

    result = compile_and_run(source, "test_slice_get")
    # B=66, C=67, D=68, sum=201
    assert_equal 201, result
  end

  def test_byte_slice_to_string
    source = <<~RUBY
      def test_slice_to_s
        buf = ByteBuffer.new(256)
        buf.write("Hello World")
        slice = buf.slice(6, 5)  # "World"
        slice.to_s
      end
    RUBY

    result = compile_and_run(source, "test_slice_to_s")
    assert_equal "World", result
  end

  def test_byte_slice_zero_copy
    source = <<~RUBY
      def test_zero_copy
        buf = ByteBuffer.new(256)
        buf.write("ABCDEFGH")
        slice1 = buf.slice(0, 4)  # "ABCD"
        slice2 = buf.slice(4, 4)  # "EFGH"
        slice1.to_s + slice2.to_s
      end
    RUBY

    result = compile_and_run(source, "test_zero_copy")
    assert_equal "ABCDEFGH", result
  end

  def test_byte_slice_partial
    source = <<~RUBY
      def test_partial
        buf = ByteBuffer.new(256)
        buf.write("GET /path HTTP/1.1")
        # Extract method (first 3 bytes)
        method_slice = buf.slice(0, 3)
        method_slice.to_s
      end
    RUBY

    result = compile_and_run(source, "test_partial")
    assert_equal "GET", result
  end

  private

  def compile_and_run(source, call_expr)
    @test_counter += 1
    source_file = File.join(@tmp_dir, "test_#{@test_counter}.rb")
    rbs_file = File.join(@tmp_dir, "test_#{@test_counter}.rbs")
    output_file = File.join(@tmp_dir, "test_#{@test_counter}.bundle")

    File.write(source_file, source)

    # Write RBS file with ByteBuffer and ByteSlice types
    rbs_content = <<~RBS
      %a{native}      class ByteBuffer
        def self.new: (Integer capacity) -> ByteBuffer

        def []: (Integer index) -> Integer
        def []=: (Integer index, Integer byte) -> Integer
        def length: () -> Integer

        def <<: (Integer byte) -> ByteBuffer
        def write: (String s) -> ByteBuffer

        def slice: (Integer start, Integer length) -> ByteSlice

        def to_s: () -> String
      end

      %a{native}      class ByteSlice
        def []: (Integer index) -> Integer
        def length: () -> Integer
        def to_s: () -> String
      end

      module TopLevel
        def test_slice_length: () -> Integer
        def test_slice_get: () -> Integer
        def test_slice_to_s: () -> String
        def test_zero_copy: () -> String
        def test_partial: () -> String
      end
    RBS
    File.write(rbs_file, rbs_content)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      rbs_paths: [rbs_file]
    )
    compiler.compile

    require output_file

    eval(call_expr)
  end
end
