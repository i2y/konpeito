# KonpeitoCrypto - Cryptographic operations using OpenSSL
#
# This module provides cryptographic functionality using the OpenSSL library.
# It is implemented as a C extension for maximum performance.
#
# Usage:
#   require 'konpeito/stdlib/crypto'
#
#   # Hash functions (hex output)
#   hash = KonpeitoCrypto.sha256("hello world")
#   # => "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
#
#   hash = KonpeitoCrypto.sha512("hello world")
#   # => "309ecc489c12d6eb4cc40f50c902f2b4d0ed77ee511a7c7a9bcd3ca86d4cd86f..."
#
#   # HMAC for message authentication
#   mac = KonpeitoCrypto.hmac_sha256("secret-key", "message to authenticate")
#
#   # Secure random bytes
#   bytes = KonpeitoCrypto.random_bytes(32)  # 32 random bytes
#   hex = KonpeitoCrypto.random_hex(16)      # 32 character hex string
#
#   # Timing-safe comparison (for password/token verification)
#   if KonpeitoCrypto.secure_compare(user_token, stored_token)
#     puts "Valid token"
#   end

# Try to load the native extension
begin
  require_relative 'konpeito_crypto'
rescue LoadError => e
  # Fallback to OpenSSL gem if native extension is not available
  require 'openssl'
  require 'securerandom'

  module KonpeitoCrypto
    class << self
      def sha256(data)
        OpenSSL::Digest::SHA256.hexdigest(data)
      end

      def sha256_binary(data)
        OpenSSL::Digest::SHA256.digest(data)
      end

      def sha512(data)
        OpenSSL::Digest::SHA512.hexdigest(data)
      end

      def sha512_binary(data)
        OpenSSL::Digest::SHA512.digest(data)
      end

      def hmac_sha256(key, data)
        OpenSSL::HMAC.hexdigest('SHA256', key, data)
      end

      def hmac_sha256_binary(key, data)
        OpenSSL::HMAC.digest('SHA256', key, data)
      end

      def hmac_sha512(key, data)
        OpenSSL::HMAC.hexdigest('SHA512', key, data)
      end

      def random_bytes(count)
        SecureRandom.random_bytes(count)
      end

      def random_hex(count)
        SecureRandom.hex(count)
      end

      def secure_compare(a, b)
        return false if a.bytesize != b.bytesize

        result = 0
        a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
        result == 0
      end
    end
  end

  warn "KonpeitoCrypto: Native extension not available, using OpenSSL gem fallback (#{e.message})"
end
