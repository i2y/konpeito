# frozen_string_literal: true

require 'minitest/autorun'
require 'openssl'

# Build the extension first
crypto_dir = File.expand_path('../../lib/konpeito/stdlib/crypto', __dir__)
Dir.chdir(crypto_dir) do
  system('ruby extconf.rb > /dev/null 2>&1') || raise("extconf.rb failed")
  system('make clean > /dev/null 2>&1')
  system('make > /dev/null 2>&1') || raise("make failed")
end

require_relative '../../lib/konpeito/stdlib/crypto/crypto'

class KonpeitoCryptoTest < Minitest::Test
  def test_sha256_hello_world
    # Test against known hash value
    result = KonpeitoCrypto.sha256("hello world")
    expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
    assert_equal expected, result
  end

  def test_sha256_empty_string
    result = KonpeitoCrypto.sha256("")
    expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    assert_equal expected, result
  end

  def test_sha256_matches_openssl
    data = "The quick brown fox jumps over the lazy dog"
    konpeito_result = KonpeitoCrypto.sha256(data)
    openssl_result = OpenSSL::Digest::SHA256.hexdigest(data)
    assert_equal openssl_result, konpeito_result
  end

  def test_sha256_binary
    result = KonpeitoCrypto.sha256_binary("hello")
    assert_equal 32, result.bytesize
    # Verify it matches the binary version of hex output
    hex_result = KonpeitoCrypto.sha256("hello")
    assert_equal [hex_result].pack('H*'), result
  end

  def test_sha512_hello_world
    result = KonpeitoCrypto.sha512("hello world")
    expected = OpenSSL::Digest::SHA512.hexdigest("hello world")
    assert_equal expected, result
    assert_equal 128, result.length # 512 bits = 128 hex chars
  end

  def test_sha512_binary
    result = KonpeitoCrypto.sha512_binary("hello")
    assert_equal 64, result.bytesize # 512 bits = 64 bytes
  end

  def test_hmac_sha256
    key = "secret"
    data = "message"
    result = KonpeitoCrypto.hmac_sha256(key, data)
    expected = OpenSSL::HMAC.hexdigest('SHA256', key, data)
    assert_equal expected, result
    assert_equal 64, result.length
  end

  def test_hmac_sha256_binary
    key = "secret"
    data = "message"
    result = KonpeitoCrypto.hmac_sha256_binary(key, data)
    assert_equal 32, result.bytesize
    expected = OpenSSL::HMAC.digest('SHA256', key, data)
    assert_equal expected, result
  end

  def test_hmac_sha512
    key = "secret"
    data = "message"
    result = KonpeitoCrypto.hmac_sha512(key, data)
    expected = OpenSSL::HMAC.hexdigest('SHA512', key, data)
    assert_equal expected, result
    assert_equal 128, result.length
  end

  def test_random_bytes_length
    result = KonpeitoCrypto.random_bytes(32)
    assert_equal 32, result.bytesize
  end

  def test_random_bytes_uniqueness
    bytes1 = KonpeitoCrypto.random_bytes(32)
    bytes2 = KonpeitoCrypto.random_bytes(32)
    refute_equal bytes1, bytes2
  end

  def test_random_bytes_error_on_zero
    assert_raises(ArgumentError) do
      KonpeitoCrypto.random_bytes(0)
    end
  end

  def test_random_bytes_error_on_negative
    assert_raises(ArgumentError) do
      KonpeitoCrypto.random_bytes(-1)
    end
  end

  def test_random_hex_length
    result = KonpeitoCrypto.random_hex(16)
    assert_equal 32, result.length # 16 bytes = 32 hex chars
  end

  def test_random_hex_format
    result = KonpeitoCrypto.random_hex(16)
    assert_match(/\A[0-9a-f]{32}\z/, result)
  end

  def test_secure_compare_equal
    assert KonpeitoCrypto.secure_compare("hello", "hello")
  end

  def test_secure_compare_not_equal
    refute KonpeitoCrypto.secure_compare("hello", "world")
  end

  def test_secure_compare_different_length
    refute KonpeitoCrypto.secure_compare("hello", "hi")
  end

  def test_secure_compare_empty_strings
    assert KonpeitoCrypto.secure_compare("", "")
  end

  def test_secure_compare_binary_data
    data1 = KonpeitoCrypto.sha256_binary("test")
    data2 = KonpeitoCrypto.sha256_binary("test")
    data3 = KonpeitoCrypto.sha256_binary("other")
    assert KonpeitoCrypto.secure_compare(data1, data2)
    refute KonpeitoCrypto.secure_compare(data1, data3)
  end

  # Test that module exists and has correct methods
  def test_module_exists
    assert_kind_of Module, KonpeitoCrypto
  end

  def test_methods_defined
    assert_respond_to KonpeitoCrypto, :sha256
    assert_respond_to KonpeitoCrypto, :sha256_binary
    assert_respond_to KonpeitoCrypto, :sha512
    assert_respond_to KonpeitoCrypto, :sha512_binary
    assert_respond_to KonpeitoCrypto, :hmac_sha256
    assert_respond_to KonpeitoCrypto, :hmac_sha256_binary
    assert_respond_to KonpeitoCrypto, :hmac_sha512
    assert_respond_to KonpeitoCrypto, :random_bytes
    assert_respond_to KonpeitoCrypto, :random_hex
    assert_respond_to KonpeitoCrypto, :secure_compare
  end
end
