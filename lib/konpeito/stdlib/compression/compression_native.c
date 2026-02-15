/*
 * Konpeito Compression stdlib - zlib wrapper
 *
 * Provides compression/decompression using zlib.
 * Supports gzip, deflate, and raw compression.
 */

#include <ruby.h>
#include <zlib.h>
#include <stdlib.h>
#include <string.h>

/* Default chunk size for compression */
#define CHUNK_SIZE 16384

/*
 * Compress data using gzip format
 *
 * @param data [String] Data to compress
 * @return [String] Gzip-compressed data
 * @raise [RuntimeError] if compression fails
 */
VALUE konpeito_compression_gzip(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    /* Allocate output buffer (worst case: input size + overhead) */
    uLongf output_len = compressBound(input_len) + 18; /* gzip header/footer */
    unsigned char *output = malloc(output_len);
    if (!output) {
        rb_raise(rb_eNoMemError, "Failed to allocate compression buffer");
        return Qnil;
    }

    /* Initialize zlib stream for gzip */
    z_stream stream;
    memset(&stream, 0, sizeof(stream));

    /* windowBits 15 + 16 = gzip format */
    int ret = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                           15 + 16, 8, Z_DEFAULT_STRATEGY);
    if (ret != Z_OK) {
        free(output);
        rb_raise(rb_eRuntimeError, "Failed to initialize compression: %s",
                 stream.msg ? stream.msg : "unknown error");
        return Qnil;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;
    stream.next_out = output;
    stream.avail_out = (uInt)output_len;

    ret = deflate(&stream, Z_FINISH);
    if (ret != Z_STREAM_END) {
        deflateEnd(&stream);
        free(output);
        rb_raise(rb_eRuntimeError, "Compression failed: %s",
                 stream.msg ? stream.msg : "unknown error");
        return Qnil;
    }

    size_t compressed_len = stream.total_out;
    deflateEnd(&stream);

    VALUE result = rb_str_new((const char *)output, compressed_len);
    free(output);

    return result;
}

/*
 * Decompress gzip data
 *
 * @param data [String] Gzip-compressed data
 * @return [String] Decompressed data
 * @raise [RuntimeError] if decompression fails
 */
VALUE konpeito_compression_gunzip(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    /* Start with a reasonable output buffer size */
    size_t output_size = input_len * 4;
    if (output_size < CHUNK_SIZE) output_size = CHUNK_SIZE;
    unsigned char *output = malloc(output_size);
    if (!output) {
        rb_raise(rb_eNoMemError, "Failed to allocate decompression buffer");
        return Qnil;
    }

    /* Initialize zlib stream for gzip */
    z_stream stream;
    memset(&stream, 0, sizeof(stream));

    /* windowBits 15 + 32 = auto-detect gzip/zlib */
    int ret = inflateInit2(&stream, 15 + 32);
    if (ret != Z_OK) {
        free(output);
        rb_raise(rb_eRuntimeError, "Failed to initialize decompression: %s",
                 stream.msg ? stream.msg : "unknown error");
        return Qnil;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;

    size_t total_out = 0;

    do {
        /* Expand buffer if needed */
        if (total_out >= output_size) {
            output_size *= 2;
            unsigned char *new_output = realloc(output, output_size);
            if (!new_output) {
                inflateEnd(&stream);
                free(output);
                rb_raise(rb_eNoMemError, "Failed to expand decompression buffer");
                return Qnil;
            }
            output = new_output;
        }

        stream.next_out = output + total_out;
        stream.avail_out = (uInt)(output_size - total_out);

        ret = inflate(&stream, Z_NO_FLUSH);

        if (ret == Z_NEED_DICT || ret == Z_DATA_ERROR || ret == Z_MEM_ERROR) {
            inflateEnd(&stream);
            free(output);
            rb_raise(rb_eRuntimeError, "Decompression failed: %s",
                     stream.msg ? stream.msg : "data error");
            return Qnil;
        }

        total_out = stream.total_out;

    } while (ret != Z_STREAM_END);

    inflateEnd(&stream);

    VALUE result = rb_str_new((const char *)output, total_out);
    free(output);

    return result;
}

/*
 * Compress data using deflate (raw zlib format, no header)
 *
 * @param data [String] Data to compress
 * @param level [Integer] Compression level (0-9, default 6)
 * @return [String] Deflate-compressed data
 * @raise [RuntimeError] if compression fails
 */
VALUE konpeito_compression_deflate(VALUE self, VALUE data, VALUE level) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);
    int compression_level = NIL_P(level) ? Z_DEFAULT_COMPRESSION : NUM2INT(level);

    if (compression_level < 0 || compression_level > 9) {
        if (compression_level != Z_DEFAULT_COMPRESSION) {
            rb_raise(rb_eArgError, "Compression level must be 0-9");
            return Qnil;
        }
    }

    /* Allocate output buffer */
    uLongf output_len = compressBound(input_len);
    unsigned char *output = malloc(output_len);
    if (!output) {
        rb_raise(rb_eNoMemError, "Failed to allocate compression buffer");
        return Qnil;
    }

    /* Initialize zlib stream for raw deflate */
    z_stream stream;
    memset(&stream, 0, sizeof(stream));

    /* windowBits -15 = raw deflate (no zlib header) */
    int ret = deflateInit2(&stream, compression_level, Z_DEFLATED,
                           -15, 8, Z_DEFAULT_STRATEGY);
    if (ret != Z_OK) {
        free(output);
        rb_raise(rb_eRuntimeError, "Failed to initialize compression: %s",
                 stream.msg ? stream.msg : "unknown error");
        return Qnil;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;
    stream.next_out = output;
    stream.avail_out = (uInt)output_len;

    ret = deflate(&stream, Z_FINISH);
    if (ret != Z_STREAM_END) {
        deflateEnd(&stream);
        free(output);
        rb_raise(rb_eRuntimeError, "Compression failed: %s",
                 stream.msg ? stream.msg : "unknown error");
        return Qnil;
    }

    size_t compressed_len = stream.total_out;
    deflateEnd(&stream);

    VALUE result = rb_str_new((const char *)output, compressed_len);
    free(output);

    return result;
}

/*
 * Decompress deflate data (raw zlib format, no header)
 *
 * @param data [String] Deflate-compressed data
 * @return [String] Decompressed data
 * @raise [RuntimeError] if decompression fails
 */
VALUE konpeito_compression_inflate(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    /* Start with a reasonable output buffer size */
    size_t output_size = input_len * 4;
    if (output_size < CHUNK_SIZE) output_size = CHUNK_SIZE;
    unsigned char *output = malloc(output_size);
    if (!output) {
        rb_raise(rb_eNoMemError, "Failed to allocate decompression buffer");
        return Qnil;
    }

    /* Initialize zlib stream for raw inflate */
    z_stream stream;
    memset(&stream, 0, sizeof(stream));

    /* windowBits -15 = raw inflate (no zlib header) */
    int ret = inflateInit2(&stream, -15);
    if (ret != Z_OK) {
        free(output);
        rb_raise(rb_eRuntimeError, "Failed to initialize decompression: %s",
                 stream.msg ? stream.msg : "unknown error");
        return Qnil;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;

    size_t total_out = 0;

    do {
        /* Expand buffer if needed */
        if (total_out >= output_size) {
            output_size *= 2;
            unsigned char *new_output = realloc(output, output_size);
            if (!new_output) {
                inflateEnd(&stream);
                free(output);
                rb_raise(rb_eNoMemError, "Failed to expand decompression buffer");
                return Qnil;
            }
            output = new_output;
        }

        stream.next_out = output + total_out;
        stream.avail_out = (uInt)(output_size - total_out);

        ret = inflate(&stream, Z_NO_FLUSH);

        if (ret == Z_NEED_DICT || ret == Z_DATA_ERROR || ret == Z_MEM_ERROR) {
            inflateEnd(&stream);
            free(output);
            rb_raise(rb_eRuntimeError, "Decompression failed: %s",
                     stream.msg ? stream.msg : "data error");
            return Qnil;
        }

        total_out = stream.total_out;

    } while (ret != Z_STREAM_END);

    inflateEnd(&stream);

    VALUE result = rb_str_new((const char *)output, total_out);
    free(output);

    return result;
}

/*
 * Compress data using zlib format (with header)
 *
 * @param data [String] Data to compress
 * @return [String] Zlib-compressed data
 * @raise [RuntimeError] if compression fails
 */
VALUE konpeito_compression_zlib_compress(VALUE self, VALUE data) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);

    uLongf output_len = compressBound(input_len);
    unsigned char *output = malloc(output_len);
    if (!output) {
        rb_raise(rb_eNoMemError, "Failed to allocate compression buffer");
        return Qnil;
    }

    int ret = compress(output, &output_len, input, input_len);
    if (ret != Z_OK) {
        free(output);
        rb_raise(rb_eRuntimeError, "Compression failed with code %d", ret);
        return Qnil;
    }

    VALUE result = rb_str_new((const char *)output, output_len);
    free(output);

    return result;
}

/*
 * Decompress zlib data (with header)
 *
 * @param data [String] Zlib-compressed data
 * @param max_size [Integer] Maximum decompressed size (for safety)
 * @return [String] Decompressed data
 * @raise [RuntimeError] if decompression fails
 */
VALUE konpeito_compression_zlib_decompress(VALUE self, VALUE data, VALUE max_size) {
    Check_Type(data, T_STRING);

    const unsigned char *input = (const unsigned char *)RSTRING_PTR(data);
    size_t input_len = RSTRING_LEN(data);
    size_t max_output = NIL_P(max_size) ? 100 * 1024 * 1024 : (size_t)NUM2LONG(max_size); /* 100MB default */

    /* Start with estimated output size */
    size_t output_size = input_len * 4;
    if (output_size < CHUNK_SIZE) output_size = CHUNK_SIZE;
    if (output_size > max_output) output_size = max_output;

    unsigned char *output = malloc(output_size);
    if (!output) {
        rb_raise(rb_eNoMemError, "Failed to allocate decompression buffer");
        return Qnil;
    }

    uLongf destLen = (uLongf)output_size;
    int ret;

    while (1) {
        ret = uncompress(output, &destLen, input, input_len);

        if (ret == Z_OK) {
            break;
        } else if (ret == Z_BUF_ERROR) {
            /* Need bigger buffer */
            output_size *= 2;
            if (output_size > max_output) {
                free(output);
                rb_raise(rb_eRuntimeError, "Decompressed data exceeds maximum size");
                return Qnil;
            }
            unsigned char *new_output = realloc(output, output_size);
            if (!new_output) {
                free(output);
                rb_raise(rb_eNoMemError, "Failed to expand decompression buffer");
                return Qnil;
            }
            output = new_output;
            destLen = (uLongf)output_size;
        } else {
            free(output);
            rb_raise(rb_eRuntimeError, "Decompression failed with code %d", ret);
            return Qnil;
        }
    }

    VALUE result = rb_str_new((const char *)output, destLen);
    free(output);

    return result;
}

/* Module initialization */
void Init_konpeito_compression(void) {
    VALUE mKonpeitoCompression = rb_define_module("KonpeitoCompression");

    /* Gzip format (RFC 1952) */
    rb_define_module_function(mKonpeitoCompression, "gzip", konpeito_compression_gzip, 1);
    rb_define_module_function(mKonpeitoCompression, "gunzip", konpeito_compression_gunzip, 1);

    /* Raw deflate (RFC 1951) - no header */
    rb_define_module_function(mKonpeitoCompression, "deflate", konpeito_compression_deflate, 2);
    rb_define_module_function(mKonpeitoCompression, "inflate", konpeito_compression_inflate, 1);

    /* Zlib format (RFC 1950) - with header */
    rb_define_module_function(mKonpeitoCompression, "zlib_compress", konpeito_compression_zlib_compress, 1);
    rb_define_module_function(mKonpeitoCompression, "zlib_decompress", konpeito_compression_zlib_decompress, 2);

    /* Constants */
    rb_define_const(mKonpeitoCompression, "BEST_SPEED", INT2FIX(Z_BEST_SPEED));
    rb_define_const(mKonpeitoCompression, "BEST_COMPRESSION", INT2FIX(Z_BEST_COMPRESSION));
    rb_define_const(mKonpeitoCompression, "DEFAULT_COMPRESSION", INT2FIX(Z_DEFAULT_COMPRESSION));
}
