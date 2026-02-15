# frozen_string_literal: true

require 'benchmark/ips'
require 'openssl'
require 'zlib'
require 'securerandom'

# Build extensions
%w[http crypto compression].each do |lib|
  dir = File.expand_path("../lib/konpeito/stdlib/#{lib}", __dir__)
  Dir.chdir(dir) do
    system('ruby extconf.rb > /dev/null 2>&1')
    system('make clean > /dev/null 2>&1')
    system('make > /dev/null 2>&1')
  end
end

require_relative '../lib/konpeito/stdlib/crypto/crypto'
require_relative '../lib/konpeito/stdlib/compression/compression'

puts "=" * 60
puts "Konpeito @cfunc stdlib Benchmark"
puts "=" * 60
puts

# Test data
SMALL_DATA = "Hello, World!"
MEDIUM_DATA = "The quick brown fox jumps over the lazy dog. " * 100
LARGE_DATA = "x" * (64 * 1024)  # 64KB

puts "=== Crypto Benchmarks ==="
puts

puts "--- SHA256 ---"
Benchmark.ips do |x|
  x.report("OpenSSL SHA256 (small)") { OpenSSL::Digest::SHA256.hexdigest(SMALL_DATA) }
  x.report("Konpeito SHA256 (small)") { KonpeitoCrypto.sha256(SMALL_DATA) }
  x.compare!
end
puts

Benchmark.ips do |x|
  x.report("OpenSSL SHA256 (64KB)") { OpenSSL::Digest::SHA256.hexdigest(LARGE_DATA) }
  x.report("Konpeito SHA256 (64KB)") { KonpeitoCrypto.sha256(LARGE_DATA) }
  x.compare!
end
puts

puts "--- SHA512 ---"
Benchmark.ips do |x|
  x.report("OpenSSL SHA512 (small)") { OpenSSL::Digest::SHA512.hexdigest(SMALL_DATA) }
  x.report("Konpeito SHA512 (small)") { KonpeitoCrypto.sha512(SMALL_DATA) }
  x.compare!
end
puts

puts "--- HMAC-SHA256 ---"
KEY = "secret-key-for-hmac"
Benchmark.ips do |x|
  x.report("OpenSSL HMAC-SHA256") { OpenSSL::HMAC.hexdigest('SHA256', KEY, MEDIUM_DATA) }
  x.report("Konpeito HMAC-SHA256") { KonpeitoCrypto.hmac_sha256(KEY, MEDIUM_DATA) }
  x.compare!
end
puts

puts "--- Random Bytes ---"
Benchmark.ips do |x|
  x.report("SecureRandom (32 bytes)") { SecureRandom.random_bytes(32) }
  x.report("Konpeito random_bytes (32)") { KonpeitoCrypto.random_bytes(32) }
  x.compare!
end
puts

puts "=== Compression Benchmarks ==="
puts

puts "--- Gzip (#{MEDIUM_DATA.bytesize} bytes) ---"
Benchmark.ips do |x|
  x.report("Zlib.gzip") { Zlib.gzip(MEDIUM_DATA) }
  x.report("Konpeito gzip") { KonpeitoCompression.gzip(MEDIUM_DATA) }
  x.compare!
end
puts

puts "--- Gunzip ---"
gzipped_ruby = Zlib.gzip(MEDIUM_DATA)
gzipped_konpeito = KonpeitoCompression.gzip(MEDIUM_DATA)

Benchmark.ips do |x|
  x.report("Zlib.gunzip") { Zlib.gunzip(gzipped_ruby) }
  x.report("Konpeito gunzip") { KonpeitoCompression.gunzip(gzipped_konpeito) }
  x.compare!
end
puts

puts "--- Gzip Large (#{LARGE_DATA.bytesize / 1024}KB) ---"
Benchmark.ips do |x|
  x.report("Zlib.gzip (64KB)") { Zlib.gzip(LARGE_DATA) }
  x.report("Konpeito gzip (64KB)") { KonpeitoCompression.gzip(LARGE_DATA) }
  x.compare!
end
puts

puts "--- Deflate/Inflate ---"
Benchmark.ips do |x|
  x.report("Zlib::Deflate") do
    d = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    d.deflate(MEDIUM_DATA, Zlib::FINISH)
    d.close
  end
  x.report("Konpeito deflate") { KonpeitoCompression.deflate(MEDIUM_DATA, nil) }
  x.compare!
end
puts

puts "--- Zlib format ---"
Benchmark.ips do |x|
  x.report("Zlib.deflate") { Zlib.deflate(MEDIUM_DATA) }
  x.report("Konpeito zlib_compress") { KonpeitoCompression.zlib_compress(MEDIUM_DATA) }
  x.compare!
end
puts

puts "=" * 60
puts "Summary"
puts "=" * 60
puts
puts "Data sizes used:"
puts "  Small: #{SMALL_DATA.bytesize} bytes"
puts "  Medium: #{MEDIUM_DATA.bytesize} bytes"
puts "  Large: #{LARGE_DATA.bytesize / 1024} KB"
