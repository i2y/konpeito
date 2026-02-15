# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class ByteBufferTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_counter = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # ===================
  # ByteBuffer allocation and basic operations
  # ===================

  def test_byte_buffer_alloc_and_length
    source = <<~RUBY
      def test_alloc
        buf = ByteBuffer.new(256)
        buf.length
      end
    RUBY

    result = compile_and_run(source, "test_alloc")
    assert_equal 0, result
  end

  def test_byte_buffer_append_byte_and_get
    source = <<~RUBY
      def test_append_byte
        buf = ByteBuffer.new(256)
        buf << 65  # 'A'
        buf << 66  # 'B'
        buf << 67  # 'C'
        buf[0] + buf[1] + buf[2]
      end
    RUBY

    result = compile_and_run(source, "test_append_byte")
    assert_equal 198, result  # 65 + 66 + 67
  end

  def test_byte_buffer_write_string
    source = <<~RUBY
      def test_write_string
        buf = ByteBuffer.new(256)
        buf.write("Hello")
        buf.length
      end
    RUBY

    result = compile_and_run(source, "test_write_string")
    assert_equal 5, result
  end

  def test_byte_buffer_to_string
    source = <<~RUBY
      def test_to_string
        buf = ByteBuffer.new(256)
        buf.write("Hello")
        buf.to_s
      end
    RUBY

    result = compile_and_run(source, "test_to_string")
    assert_equal "Hello", result
  end

  def test_byte_buffer_chained_writes
    source = <<~RUBY
      def test_chained
        buf = ByteBuffer.new(256)
        buf.write("HTTP/1.1 ")
        buf.write("200 OK")
        buf.to_s
      end
    RUBY

    result = compile_and_run(source, "test_chained")
    assert_equal "HTTP/1.1 200 OK", result
  end

  # ===================
  # ByteBuffer index_of tests
  # ===================

  def test_byte_buffer_index_of_byte
    source = <<~RUBY
      def test_index_of
        buf = ByteBuffer.new(256)
        buf.write("GET /path HTTP/1.1")
        buf.index_of(32)  # space character
      end
    RUBY

    result = compile_and_run(source, "test_index_of")
    assert_equal 3, result  # First space at index 3
  end

  def test_byte_buffer_index_of_not_found
    source = <<~RUBY
      def test_index_of_not_found
        buf = ByteBuffer.new(256)
        buf.write("Hello")
        result = buf.index_of(64)  # '@' not in string
        if result == nil
          -1
        else
          result
        end
      end
    RUBY

    result = compile_and_run(source, "test_index_of_not_found")
    assert_equal(-1, result)
  end

  # ===================
  # StringBuffer tests
  # ===================

  def test_string_buffer_alloc
    source = <<~RUBY
      def test_strbuf_alloc
        buf = StringBuffer.new(256)
        buf.length
      end
    RUBY

    result = compile_and_run(source, "test_strbuf_alloc")
    assert_equal 0, result
  end

  def test_string_buffer_append
    source = <<~RUBY
      def test_strbuf_append
        buf = StringBuffer.new(256)
        buf << "Hello"
        buf << " "
        buf << "World"
        buf.to_s
      end
    RUBY

    result = compile_and_run(source, "test_strbuf_append")
    assert_equal "Hello World", result
  end

  def test_string_buffer_http_response
    source = <<~RUBY
      def build_response(status, body)
        buf = StringBuffer.new(256)
        buf << "HTTP/1.1 "
        buf << status
        buf << "\\r\\n"
        buf << "Content-Length: "
        buf << body.length.to_s
        buf << "\\r\\n\\r\\n"
        buf << body
        buf.to_s
      end
    RUBY

    result = compile_and_run(source, 'build_response("200 OK", "Hello")')
    expected = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nHello"
    assert_equal expected, result
  end

  private

  def compile_and_run(source, call_expr)
    @test_counter += 1
    source_file = File.join(@tmp_dir, "test_#{@test_counter}.rb")
    rbs_file = File.join(@tmp_dir, "test_#{@test_counter}.rbs")
    output_file = File.join(@tmp_dir, "test_#{@test_counter}.bundle")

    File.write(source_file, source)

    # Write RBS file with ByteBuffer and StringBuffer types
    rbs_content = <<~RBS
      %a{native}      class ByteBuffer
        def self.new: (Integer capacity) -> ByteBuffer

        def []: (Integer index) -> Integer
        def []=: (Integer index, Integer byte) -> Integer
        def length: () -> Integer

        def <<: (Integer byte) -> ByteBuffer
        def write: (String s) -> ByteBuffer

        def index_of: (Integer byte) -> Integer?

        def to_s: () -> String
      end

      %a{native}      class StringBuffer
        def self.new: (Integer capacity) -> StringBuffer

        def <<: (String s) -> StringBuffer
        def length: () -> Integer
        def to_s: () -> String
      end

      module TopLevel
        def test_alloc: () -> Integer
        def test_append_byte: () -> Integer
        def test_write_string: () -> Integer
        def test_to_string: () -> String
        def test_chained: () -> String
        def test_index_of: () -> Integer
        def test_index_of_not_found: () -> Integer
        def test_strbuf_alloc: () -> Integer
        def test_strbuf_append: () -> String
        def build_response: (String status, String body) -> String
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
