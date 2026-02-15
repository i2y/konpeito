# KonpeitoCompression - Data compression using zlib
#
# This module provides compression and decompression using the zlib library.
# It is implemented as a C extension for maximum performance.
#
# Usage:
#   require 'konpeito/stdlib/compression'
#
#   # Gzip format (most common for HTTP, file archives)
#   compressed = KonpeitoCompression.gzip("Hello, World!")
#   original = KonpeitoCompression.gunzip(compressed)
#
#   # With compression level
#   fast = KonpeitoCompression.deflate(data, KonpeitoCompression::BEST_SPEED)
#   small = KonpeitoCompression.deflate(data, KonpeitoCompression::BEST_COMPRESSION)
#
#   # Raw deflate (for custom protocols, no header overhead)
#   compressed = KonpeitoCompression.deflate("Hello", nil)
#   original = KonpeitoCompression.inflate(compressed)
#
#   # Zlib format (includes checksum, good for data integrity)
#   compressed = KonpeitoCompression.zlib_compress("Hello")
#   original = KonpeitoCompression.zlib_decompress(compressed, nil)

# Try to load the native extension
begin
  require_relative 'konpeito_compression'
rescue LoadError => e
  # Fallback to Zlib module if native extension is not available
  require 'zlib'

  module KonpeitoCompression
    BEST_SPEED = Zlib::BEST_SPEED
    BEST_COMPRESSION = Zlib::BEST_COMPRESSION
    DEFAULT_COMPRESSION = Zlib::DEFAULT_COMPRESSION

    class << self
      def gzip(data)
        Zlib.gzip(data)
      end

      def gunzip(data)
        Zlib.gunzip(data)
      end

      def deflate(data, level = nil)
        level ||= Zlib::DEFAULT_COMPRESSION
        deflater = Zlib::Deflate.new(level, -Zlib::MAX_WBITS)
        result = deflater.deflate(data, Zlib::FINISH)
        deflater.close
        result
      end

      def inflate(data)
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        result = inflater.inflate(data)
        inflater.close
        result
      end

      def zlib_compress(data)
        Zlib.deflate(data)
      end

      def zlib_decompress(data, max_size = nil)
        Zlib.inflate(data)
      end
    end
  end

  warn "KonpeitoCompression: Native extension not available, using Zlib fallback (#{e.message})"
end
