# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class NativeStringTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @test_counter = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # ===================
  # NativeString creation and byte-level operations
  # ===================

  def test_native_string_byte_length
    source = <<~RUBY
      def test_byte_length
        ns = NativeString.from("Hello")
        ns.byte_length
      end
    RUBY

    result = compile_and_run(source, "test_byte_length")
    assert_equal 5, result
  end

  def test_native_string_byte_at
    source = <<~RUBY
      def test_byte_at
        ns = NativeString.from("ABC")
        ns.byte_at(0) + ns.byte_at(1) + ns.byte_at(2)
      end
    RUBY

    result = compile_and_run(source, "test_byte_at")
    assert_equal 198, result  # 65 + 66 + 67
  end

  def test_native_string_byte_index_of
    source = <<~RUBY
      def test_byte_index
        ns = NativeString.from("GET /path HTTP/1.1")
        ns.byte_index_of(32)  # space character
      end
    RUBY

    result = compile_and_run(source, "test_byte_index")
    assert_equal 3, result
  end

  def test_native_string_byte_index_not_found
    source = <<~RUBY
      def test_byte_index_not_found
        ns = NativeString.from("Hello")
        idx = ns.byte_index_of(255)
        if idx == nil
          0
        else
          idx
        end
      end
    RUBY

    result = compile_and_run(source, "test_byte_index_not_found")
    assert_equal 0, result
  end

  def test_native_string_to_s
    source = <<~RUBY
      def test_to_s
        ns = NativeString.from("Hello World")
        ns.to_s
      end
    RUBY

    result = compile_and_run(source, "test_to_s")
    assert_equal "Hello World", result
  end

  def test_native_string_byte_slice
    source = <<~RUBY
      def test_byte_slice
        ns = NativeString.from("Hello World")
        slice = ns.byte_slice(0, 5)
        slice.to_s
      end
    RUBY

    result = compile_and_run(source, "test_byte_slice")
    assert_equal "Hello", result
  end

  # ===================
  # NativeString inspection methods
  # ===================

  def test_native_string_ascii_only_true
    source = <<~RUBY
      def test_ascii
        ns = NativeString.from("Hello")
        if ns.ascii_only?
          1
        else
          0
        end
      end
    RUBY

    result = compile_and_run(source, "test_ascii")
    assert_equal 1, result
  end

  def test_native_string_ascii_only_false
    source = <<~RUBY
      def test_ascii_false
        ns = NativeString.from("こんにちは")
        if ns.ascii_only?
          1
        else
          0
        end
      end
    RUBY

    result = compile_and_run(source, "test_ascii_false")
    assert_equal 0, result
  end

  def test_native_string_starts_with
    source = <<~RUBY
      def test_starts
        ns = NativeString.from("Hello World")
        if ns.starts_with?("Hello")
          1
        else
          0
        end
      end
    RUBY

    result = compile_and_run(source, "test_starts")
    assert_equal 1, result
  end

  def test_native_string_starts_with_false
    source = <<~RUBY
      def test_starts_false
        ns = NativeString.from("Hello World")
        if ns.starts_with?("World")
          1
        else
          0
        end
      end
    RUBY

    result = compile_and_run(source, "test_starts_false")
    assert_equal 0, result
  end

  def test_native_string_ends_with
    source = <<~RUBY
      def test_ends
        ns = NativeString.from("Hello World")
        if ns.ends_with?("World")
          1
        else
          0
        end
      end
    RUBY

    result = compile_and_run(source, "test_ends")
    assert_equal 1, result
  end

  # ===================
  # NativeString UTF-8 character operations
  # ===================

  def test_native_string_char_length_ascii
    source = <<~RUBY
      def test_char_len
        ns = NativeString.from("Hello")
        ns.char_length
      end
    RUBY

    result = compile_and_run(source, "test_char_len")
    assert_equal 5, result
  end

  def test_native_string_char_length_utf8
    source = <<~RUBY
      def test_char_len_utf8
        ns = NativeString.from("日本語")
        ns.char_length
      end
    RUBY

    result = compile_and_run(source, "test_char_len_utf8")
    assert_equal 3, result
  end

  def test_native_string_char_at_ascii
    source = <<~RUBY
      def test_char_at
        ns = NativeString.from("ABC")
        ns.char_at(1)
      end
    RUBY

    result = compile_and_run(source, "test_char_at")
    assert_equal "B", result
  end

  def test_native_string_char_at_utf8
    source = <<~RUBY
      def test_char_at_utf8
        ns = NativeString.from("日本語")
        ns.char_at(1)
      end
    RUBY

    result = compile_and_run(source, "test_char_at_utf8")
    assert_equal "本", result
  end

  # ===================
  # NativeString comparison
  # ===================

  def test_native_string_compare_equal
    source = <<~RUBY
      def test_compare
        ns1 = NativeString.from("Hello")
        ns2 = NativeString.from("Hello")
        if ns1 == ns2
          1
        else
          0
        end
      end
    RUBY

    result = compile_and_run(source, "test_compare")
    assert_equal 1, result
  end

  def test_native_string_compare_not_equal
    source = <<~RUBY
      def test_compare_ne
        ns1 = NativeString.from("Hello")
        ns2 = NativeString.from("World")
        if ns1 == ns2
          1
        else
          0
        end
      end
    RUBY

    result = compile_and_run(source, "test_compare_ne")
    assert_equal 0, result
  end

  # ===================
  # HTTP parsing example
  # ===================

  def test_parse_http_method
    source = <<~RUBY
      def parse_method(line)
        ns = NativeString.from(line)
        space_idx = ns.byte_index_of(32)
        if space_idx != nil
          ns.byte_slice(0, space_idx).to_s
        else
          line
        end
      end
    RUBY

    result = compile_and_run(source, "parse_method", ["GET /path HTTP/1.1"])
    assert_equal "GET", result
  end

  private

  def compile_and_run(source, method_name, args = [])
    @test_counter += 1
    source_file = File.join(@tmp_dir, "test_#{@test_counter}.rb")
    rbs_file = File.join(@tmp_dir, "test_#{@test_counter}.rbs")
    output_file = File.join(@tmp_dir, "test_#{@test_counter}.bundle")

    File.write(source_file, source)

    # Write RBS file with NativeString type
    rbs_content = <<~RBS
      %a{native}      class NativeString
        def self.from: (String s) -> NativeString

        # Byte-level operations (fast)
        def byte_at: (Integer index) -> Integer
        def byte_length: () -> Integer
        def byte_index_of: (Integer byte) -> Integer?
        def byte_slice: (Integer start, Integer length) -> NativeString

        # Character-level operations (UTF-8 aware)
        def char_at: (Integer index) -> String
        def char_length: () -> Integer
        def char_index_of: (String needle) -> Integer?
        def char_slice: (Integer start, Integer length) -> NativeString

        # Inspection
        def ascii_only?: () -> bool
        def starts_with?: (String prefix) -> bool
        def ends_with?: (String suffix) -> bool
        def valid_encoding?: () -> bool

        # Conversion
        def to_s: () -> String
        def ==: (NativeString other) -> bool
      end

      module TopLevel
        def test_byte_length: () -> Integer
        def test_byte_at: () -> Integer
        def test_byte_index: () -> Integer
        def test_byte_index_not_found: () -> Integer
        def test_to_s: () -> String
        def test_byte_slice: () -> String
        def test_ascii: () -> Integer
        def test_ascii_false: () -> Integer
        def test_starts: () -> Integer
        def test_starts_false: () -> Integer
        def test_ends: () -> Integer
        def test_char_len: () -> Integer
        def test_char_len_utf8: () -> Integer
        def test_char_at: () -> String
        def test_char_at_utf8: () -> String
        def test_compare: () -> Integer
        def test_compare_ne: () -> Integer
        def parse_method: (String line) -> String
      end
    RBS
    File.write(rbs_file, rbs_content)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      rbs_paths: [rbs_file]
    )
    compiler.compile

    # Load and call the compiled method
    require output_file

    if args.empty?
      send(method_name.to_sym)
    else
      send(method_name.to_sym, *args)
    end
  end
end
