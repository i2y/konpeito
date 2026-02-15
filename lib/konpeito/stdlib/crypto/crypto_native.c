/*
 * Konpeito Crypto stdlib - OpenSSL wrapper
 *
 * Provides cryptographic functionality using OpenSSL.
 * Supports SHA256, SHA512, HMAC, and secure random bytes.
 */

#include <ruby.h>
#include <openssl/sha.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <openssl/evp.h>
#include <string.h>

/*
 * Convert binary data to hex string
 */
static VALUE binary_to_hex(const unsigned char *data, size_t len) {
    char *hex = malloc(len * 2 + 1);
    if (!hex) {
        rb_raise(rb_eNoMemError, "Failed to allocate hex string");
        return Qnil;
    }

    for (size_t i = 0; i < len; i++) {
        sprintf(hex + i * 2, "%02x", data[i]);
    }
    hex[len * 2] = '\0';

    VALUE result = rb_utf8_str_new(hex, len * 2);
    free(hex);
    return result;
}

/*
 * Compute SHA256 hash
 *
 * @param data [String] Data to hash
 * @return [String] Hex-encoded SHA256 hash (64 characters)
 */
VALUE konpeito_crypto_sha256(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(input, input_len, hash);

    return binary_to_hex(hash, SHA256_DIGEST_LENGTH);
}

/*
 * Compute SHA256 hash (binary output)
 *
 * @param data [String] Data to hash
 * @return [String] Binary SHA256 hash (32 bytes)
 */
VALUE konpeito_crypto_sha256_binary(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(input, input_len, hash);

    return rb_str_new((const char *)hash, SHA256_DIGEST_LENGTH);
}

/*
 * Compute SHA512 hash
 *
 * @param data [String] Data to hash
 * @return [String] Hex-encoded SHA512 hash (128 characters)
 */
VALUE konpeito_crypto_sha512(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    unsigned char hash[SHA512_DIGEST_LENGTH];
    SHA512(input, input_len, hash);

    return binary_to_hex(hash, SHA512_DIGEST_LENGTH);
}

/*
 * Compute SHA512 hash (binary output)
 *
 * @param data [String] Data to hash
 * @return [String] Binary SHA512 hash (64 bytes)
 */
VALUE konpeito_crypto_sha512_binary(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    unsigned char hash[SHA512_DIGEST_LENGTH];
    SHA512(input, input_len, hash);

    return rb_str_new((const char *)hash, SHA512_DIGEST_LENGTH);
}

/*
 * Compute HMAC-SHA256
 *
 * @param key [String] Secret key
 * @param data [String] Data to authenticate
 * @return [String] Hex-encoded HMAC-SHA256 (64 characters)
 */
VALUE konpeito_crypto_hmac_sha256(VALUE self, VALUE key, VALUE data) {
    Check_Type(key, T_STRING);
    Check_Type(data, T_STRING);

    const unsigned char *key_ptr = (const unsigned char *)RSTRING_PTR(key);
    size_t key_len = RSTRING_LEN(key);
    const unsigned char *data_ptr = (const unsigned char *)RSTRING_PTR(data);
    size_t data_len = RSTRING_LEN(data);

    unsigned char result[EVP_MAX_MD_SIZE];
    unsigned int result_len;

    HMAC(EVP_sha256(), key_ptr, (int)key_len, data_ptr, data_len, result, &result_len);

    return binary_to_hex(result, result_len);
}

/*
 * Compute HMAC-SHA256 (binary output)
 *
 * @param key [String] Secret key
 * @param data [String] Data to authenticate
 * @return [String] Binary HMAC-SHA256 (32 bytes)
 */
VALUE konpeito_crypto_hmac_sha256_binary(VALUE self, VALUE key, VALUE data) {
    Check_Type(key, T_STRING);
    Check_Type(data, T_STRING);

    const unsigned char *key_ptr = (const unsigned char *)RSTRING_PTR(key);
    size_t key_len = RSTRING_LEN(key);
    const unsigned char *data_ptr = (const unsigned char *)RSTRING_PTR(data);
    size_t data_len = RSTRING_LEN(data);

    unsigned char result[EVP_MAX_MD_SIZE];
    unsigned int result_len;

    HMAC(EVP_sha256(), key_ptr, (int)key_len, data_ptr, data_len, result, &result_len);

    return rb_str_new((const char *)result, result_len);
}

/*
 * Compute HMAC-SHA512
 *
 * @param key [String] Secret key
 * @param data [String] Data to authenticate
 * @return [String] Hex-encoded HMAC-SHA512 (128 characters)
 */
VALUE konpeito_crypto_hmac_sha512(VALUE self, VALUE key, VALUE data) {
    Check_Type(key, T_STRING);
    Check_Type(data, T_STRING);

    const unsigned char *key_ptr = (const unsigned char *)RSTRING_PTR(key);
    size_t key_len = RSTRING_LEN(key);
    const unsigned char *data_ptr = (const unsigned char *)RSTRING_PTR(data);
    size_t data_len = RSTRING_LEN(data);

    unsigned char result[EVP_MAX_MD_SIZE];
    unsigned int result_len;

    HMAC(EVP_sha512(), key_ptr, (int)key_len, data_ptr, data_len, result, &result_len);

    return binary_to_hex(result, result_len);
}

/*
 * Generate cryptographically secure random bytes
 *
 * @param count [Integer] Number of bytes to generate
 * @return [String] Binary string of random bytes
 * @raise [RuntimeError] if random generation fails
 */
VALUE konpeito_crypto_random_bytes(VALUE self, VALUE count) {
    int num_bytes = NUM2INT(count);

    if (num_bytes <= 0) {
        rb_raise(rb_eArgError, "count must be positive");
        return Qnil;
    }

    if (num_bytes > 1024 * 1024) { /* 1MB limit */
        rb_raise(rb_eArgError, "count too large (max 1MB)");
        return Qnil;
    }

    unsigned char *buf = malloc(num_bytes);
    if (!buf) {
        rb_raise(rb_eNoMemError, "Failed to allocate random buffer");
        return Qnil;
    }

    if (RAND_bytes(buf, num_bytes) != 1) {
        free(buf);
        rb_raise(rb_eRuntimeError, "Failed to generate random bytes");
        return Qnil;
    }

    VALUE result = rb_str_new((const char *)buf, num_bytes);
    free(buf);

    return result;
}

/*
 * Generate cryptographically secure random bytes as hex string
 *
 * @param count [Integer] Number of bytes to generate (output will be 2x this length)
 * @return [String] Hex-encoded random bytes
 * @raise [RuntimeError] if random generation fails
 */
VALUE konpeito_crypto_random_hex(VALUE self, VALUE count) {
    int num_bytes = NUM2INT(count);

    if (num_bytes <= 0) {
        rb_raise(rb_eArgError, "count must be positive");
        return Qnil;
    }

    if (num_bytes > 1024 * 1024) { /* 1MB limit */
        rb_raise(rb_eArgError, "count too large (max 1MB)");
        return Qnil;
    }

    unsigned char *buf = malloc(num_bytes);
    if (!buf) {
        rb_raise(rb_eNoMemError, "Failed to allocate random buffer");
        return Qnil;
    }

    if (RAND_bytes(buf, num_bytes) != 1) {
        free(buf);
        rb_raise(rb_eRuntimeError, "Failed to generate random bytes");
        return Qnil;
    }

    VALUE result = binary_to_hex(buf, num_bytes);
    free(buf);

    return result;
}

/*
 * Constant-time comparison of two strings
 * Prevents timing attacks when comparing secrets
 *
 * @param a [String] First string
 * @param b [String] Second string
 * @return [Boolean] true if strings are equal, false otherwise
 */
VALUE konpeito_crypto_secure_compare(VALUE self, VALUE a, VALUE b) {
    Check_Type(a, T_STRING);
    Check_Type(b, T_STRING);

    size_t a_len = RSTRING_LEN(a);
    size_t b_len = RSTRING_LEN(b);

    /* Length must match */
    if (a_len != b_len) {
        return Qfalse;
    }

    const unsigned char *a_ptr = (const unsigned char *)RSTRING_PTR(a);
    const unsigned char *b_ptr = (const unsigned char *)RSTRING_PTR(b);

    /* Constant-time comparison */
    unsigned char result = 0;
    for (size_t i = 0; i < a_len; i++) {
        result |= a_ptr[i] ^ b_ptr[i];
    }

    return result == 0 ? Qtrue : Qfalse;
}

/* Module initialization */
void Init_konpeito_crypto(void) {
    VALUE mKonpeitoCrypto = rb_define_module("KonpeitoCrypto");

    /* Hash functions (hex output) */
    rb_define_module_function(mKonpeitoCrypto, "sha256", konpeito_crypto_sha256, 1);
    rb_define_module_function(mKonpeitoCrypto, "sha512", konpeito_crypto_sha512, 1);

    /* Hash functions (binary output) */
    rb_define_module_function(mKonpeitoCrypto, "sha256_binary", konpeito_crypto_sha256_binary, 1);
    rb_define_module_function(mKonpeitoCrypto, "sha512_binary", konpeito_crypto_sha512_binary, 1);

    /* HMAC functions (hex output) */
    rb_define_module_function(mKonpeitoCrypto, "hmac_sha256", konpeito_crypto_hmac_sha256, 2);
    rb_define_module_function(mKonpeitoCrypto, "hmac_sha512", konpeito_crypto_hmac_sha512, 2);

    /* HMAC functions (binary output) */
    rb_define_module_function(mKonpeitoCrypto, "hmac_sha256_binary", konpeito_crypto_hmac_sha256_binary, 2);

    /* Random generation */
    rb_define_module_function(mKonpeitoCrypto, "random_bytes", konpeito_crypto_random_bytes, 1);
    rb_define_module_function(mKonpeitoCrypto, "random_hex", konpeito_crypto_random_hex, 1);

    /* Utilities */
    rb_define_module_function(mKonpeitoCrypto, "secure_compare", konpeito_crypto_secure_compare, 2);
}
