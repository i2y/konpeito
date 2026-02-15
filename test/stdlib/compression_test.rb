# frozen_string_literal: true

require 'minitest/autorun'
require 'zlib'

# Build the extension first
compression_dir = File.expand_path('../../lib/konpeito/stdlib/compression', __dir__)
Dir.chdir(compression_dir) do
  system('ruby extconf.rb > /dev/null 2>&1') || raise("extconf.rb failed")
  system('make clean > /dev/null 2>&1')
  system('make > /dev/null 2>&1') || raise("make failed")
end

require_relative '../../lib/konpeito/stdlib/compression/compression'

class KonpeitoCompressionTest < Minitest::Test
  TEST_DATA = "Hello, World! This is a test string for compression. " * 100

  def test_gzip_roundtrip
    compressed = KonpeitoCompression.gzip(TEST_DATA)
    decompressed = KonpeitoCompression.gunzip(compressed)
    assert_equal TEST_DATA, decompressed
  end

  def test_gzip_produces_smaller_output
    compressed = KonpeitoCompression.gzip(TEST_DATA)
    assert compressed.bytesize < TEST_DATA.bytesize
  end

  def test_gzip_compatible_with_ruby_zlib
    # Our gzip should be decompressible by Ruby's Zlib
    compressed = KonpeitoCompression.gzip(TEST_DATA)
    decompressed = Zlib.gunzip(compressed)
    assert_equal TEST_DATA, decompressed
  end

  def test_gunzip_compatible_with_ruby_zlib
    # Ruby's Zlib gzip should be decompressible by us
    compressed = Zlib.gzip(TEST_DATA)
    decompressed = KonpeitoCompression.gunzip(compressed)
    assert_equal TEST_DATA, decompressed
  end

  def test_gzip_empty_string
    compressed = KonpeitoCompression.gzip("")
    decompressed = KonpeitoCompression.gunzip(compressed)
    assert_equal "", decompressed
  end

  def test_gzip_binary_data
    binary_data = (0..255).to_a.pack('C*')
    compressed = KonpeitoCompression.gzip(binary_data)
    decompressed = KonpeitoCompression.gunzip(compressed)
    assert_equal binary_data, decompressed
  end

  def test_deflate_inflate_roundtrip
    compressed = KonpeitoCompression.deflate(TEST_DATA, nil)
    decompressed = KonpeitoCompression.inflate(compressed)
    assert_equal TEST_DATA, decompressed
  end

  def test_deflate_with_compression_level
    fast = KonpeitoCompression.deflate(TEST_DATA, KonpeitoCompression::BEST_SPEED)
    best = KonpeitoCompression.deflate(TEST_DATA, KonpeitoCompression::BEST_COMPRESSION)

    # Both should decompress correctly
    assert_equal TEST_DATA, KonpeitoCompression.inflate(fast)
    assert_equal TEST_DATA, KonpeitoCompression.inflate(best)

    # Best compression should be smaller or equal
    assert best.bytesize <= fast.bytesize
  end

  def test_deflate_empty_string
    compressed = KonpeitoCompression.deflate("", nil)
    decompressed = KonpeitoCompression.inflate(compressed)
    assert_equal "", decompressed
  end

  def test_zlib_compress_decompress_roundtrip
    compressed = KonpeitoCompression.zlib_compress(TEST_DATA)
    decompressed = KonpeitoCompression.zlib_decompress(compressed, nil)
    assert_equal TEST_DATA, decompressed
  end

  def test_zlib_compatible_with_ruby_zlib
    # Our zlib_compress should be decompressible by Ruby's Zlib
    compressed = KonpeitoCompression.zlib_compress(TEST_DATA)
    decompressed = Zlib.inflate(compressed)
    assert_equal TEST_DATA, decompressed

    # Ruby's Zlib deflate should be decompressible by us
    compressed = Zlib.deflate(TEST_DATA)
    decompressed = KonpeitoCompression.zlib_decompress(compressed, nil)
    assert_equal TEST_DATA, decompressed
  end

  def test_zlib_empty_string
    compressed = KonpeitoCompression.zlib_compress("")
    decompressed = KonpeitoCompression.zlib_decompress(compressed, nil)
    assert_equal "", decompressed
  end

  def test_constants_defined
    assert_kind_of Integer, KonpeitoCompression::BEST_SPEED
    assert_kind_of Integer, KonpeitoCompression::BEST_COMPRESSION
    assert_kind_of Integer, KonpeitoCompression::DEFAULT_COMPRESSION

    # Verify sensible values
    assert_equal 1, KonpeitoCompression::BEST_SPEED
    assert_equal 9, KonpeitoCompression::BEST_COMPRESSION
    assert_equal(-1, KonpeitoCompression::DEFAULT_COMPRESSION)
  end

  def test_module_exists
    assert_kind_of Module, KonpeitoCompression
  end

  def test_methods_defined
    assert_respond_to KonpeitoCompression, :gzip
    assert_respond_to KonpeitoCompression, :gunzip
    assert_respond_to KonpeitoCompression, :deflate
    assert_respond_to KonpeitoCompression, :inflate
    assert_respond_to KonpeitoCompression, :zlib_compress
    assert_respond_to KonpeitoCompression, :zlib_decompress
  end

  def test_error_on_invalid_gzip_data
    assert_raises(RuntimeError) do
      KonpeitoCompression.gunzip("not gzip data")
    end
  end

  def test_error_on_invalid_deflate_data
    assert_raises(RuntimeError) do
      KonpeitoCompression.inflate("not deflate data")
    end
  end

  def test_error_on_invalid_zlib_data
    assert_raises(RuntimeError) do
      KonpeitoCompression.zlib_decompress("not zlib data", nil)
    end
  end

  def test_large_data
    large_data = "x" * (1024 * 1024) # 1MB of data
    compressed = KonpeitoCompression.gzip(large_data)
    decompressed = KonpeitoCompression.gunzip(compressed)
    assert_equal large_data, decompressed
  end
end
