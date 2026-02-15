/*
 * Konpeito HTTP stdlib - libcurl wrapper
 *
 * Provides HTTP client functionality using libcurl.
 * Supports GET, POST, and custom headers.
 */

#include <ruby.h>
#include <curl/curl.h>
#include <stdlib.h>
#include <string.h>

/* Response buffer structure */
typedef struct {
    char *data;
    size_t size;
} response_buffer_t;

/* Write callback for curl */
static size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    response_buffer_t *buf = (response_buffer_t *)userp;

    char *ptr = realloc(buf->data, buf->size + realsize + 1);
    if (!ptr) {
        return 0; /* out of memory */
    }

    buf->data = ptr;
    memcpy(&(buf->data[buf->size]), contents, realsize);
    buf->size += realsize;
    buf->data[buf->size] = '\0';

    return realsize;
}

/* Header write callback for curl */
static size_t header_callback(char *buffer, size_t size, size_t nitems, void *userp) {
    size_t realsize = size * nitems;
    VALUE headers_hash = (VALUE)userp;

    /* Parse header line: "Key: Value\r\n" */
    char *colon = memchr(buffer, ':', realsize);
    if (colon && colon > buffer) {
        size_t key_len = colon - buffer;
        char *value_start = colon + 1;

        /* Skip leading whitespace in value */
        while (*value_start == ' ' && value_start < buffer + realsize) {
            value_start++;
        }

        /* Calculate value length, removing trailing \r\n */
        size_t value_len = realsize - (value_start - buffer);
        while (value_len > 0 && (value_start[value_len - 1] == '\r' || value_start[value_len - 1] == '\n')) {
            value_len--;
        }

        if (value_len > 0) {
            VALUE key = rb_utf8_str_new(buffer, key_len);
            VALUE value = rb_utf8_str_new(value_start, value_len);
            rb_hash_aset(headers_hash, key, value);
        }
    }

    return realsize;
}

/*
 * Perform HTTP GET request
 *
 * @param url [String] URL to fetch
 * @return [String] Response body
 * @raise [RuntimeError] if request fails
 */
VALUE konpeito_http_get(VALUE self, VALUE url) {
    Check_Type(url, T_STRING);

    const char *url_str = RSTRING_PTR(url);

    CURL *curl = curl_easy_init();
    if (!curl) {
        rb_raise(rb_eRuntimeError, "Failed to initialize curl");
        return Qnil;
    }

    response_buffer_t buf = {0};
    buf.data = malloc(1);
    buf.data[0] = '\0';
    buf.size = 0;

    curl_easy_setopt(curl, CURLOPT_URL, url_str);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);  /* Required for multi-threaded use */
    curl_easy_setopt(curl, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Konpeito-HTTP/1.0");

    CURLcode res = curl_easy_perform(curl);

    if (res != CURLE_OK) {
        free(buf.data);
        curl_easy_cleanup(curl);
        rb_raise(rb_eRuntimeError, "HTTP request failed: %s", curl_easy_strerror(res));
        return Qnil;
    }

    VALUE result = rb_utf8_str_new(buf.data, buf.size);

    free(buf.data);
    curl_easy_cleanup(curl);

    return result;
}

/*
 * Perform HTTP POST request
 *
 * @param url [String] URL to post to
 * @param body [String] Request body
 * @return [String] Response body
 * @raise [RuntimeError] if request fails
 */
VALUE konpeito_http_post(VALUE self, VALUE url, VALUE body) {
    Check_Type(url, T_STRING);
    Check_Type(body, T_STRING);

    const char *url_str = RSTRING_PTR(url);
    const char *body_str = RSTRING_PTR(body);
    size_t body_len = RSTRING_LEN(body);

    CURL *curl = curl_easy_init();
    if (!curl) {
        rb_raise(rb_eRuntimeError, "Failed to initialize curl");
        return Qnil;
    }

    response_buffer_t buf = {0};
    buf.data = malloc(1);
    buf.data[0] = '\0';
    buf.size = 0;

    curl_easy_setopt(curl, CURLOPT_URL, url_str);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body_str);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)body_len);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Konpeito-HTTP/1.0");

    CURLcode res = curl_easy_perform(curl);

    if (res != CURLE_OK) {
        free(buf.data);
        curl_easy_cleanup(curl);
        rb_raise(rb_eRuntimeError, "HTTP request failed: %s", curl_easy_strerror(res));
        return Qnil;
    }

    VALUE result = rb_utf8_str_new(buf.data, buf.size);

    free(buf.data);
    curl_easy_cleanup(curl);

    return result;
}

/*
 * Perform HTTP GET request with full response details
 *
 * @param url [String] URL to fetch
 * @return [Hash] Response with :status, :body, :headers
 * @raise [RuntimeError] if request fails
 */
VALUE konpeito_http_get_response(VALUE self, VALUE url) {
    Check_Type(url, T_STRING);

    const char *url_str = RSTRING_PTR(url);

    CURL *curl = curl_easy_init();
    if (!curl) {
        rb_raise(rb_eRuntimeError, "Failed to initialize curl");
        return Qnil;
    }

    response_buffer_t buf = {0};
    buf.data = malloc(1);
    buf.data[0] = '\0';
    buf.size = 0;

    VALUE headers_hash = rb_hash_new();

    curl_easy_setopt(curl, CURLOPT_URL, url_str);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, header_callback);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)headers_hash);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Konpeito-HTTP/1.0");

    CURLcode res = curl_easy_perform(curl);

    if (res != CURLE_OK) {
        free(buf.data);
        curl_easy_cleanup(curl);
        rb_raise(rb_eRuntimeError, "HTTP request failed: %s", curl_easy_strerror(res));
        return Qnil;
    }

    long status_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status_code);

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("status")), LONG2NUM(status_code));
    rb_hash_aset(result, ID2SYM(rb_intern("body")), rb_utf8_str_new(buf.data, buf.size));
    rb_hash_aset(result, ID2SYM(rb_intern("headers")), headers_hash);

    free(buf.data);
    curl_easy_cleanup(curl);

    return result;
}

/*
 * Perform HTTP POST request with full response details
 *
 * @param url [String] URL to post to
 * @param body [String] Request body
 * @param content_type [String] Content-Type header (optional, default: application/x-www-form-urlencoded)
 * @return [Hash] Response with :status, :body, :headers
 * @raise [RuntimeError] if request fails
 */
VALUE konpeito_http_post_response(VALUE self, VALUE url, VALUE body, VALUE content_type) {
    Check_Type(url, T_STRING);
    Check_Type(body, T_STRING);

    const char *url_str = RSTRING_PTR(url);
    const char *body_str = RSTRING_PTR(body);
    size_t body_len = RSTRING_LEN(body);

    CURL *curl = curl_easy_init();
    if (!curl) {
        rb_raise(rb_eRuntimeError, "Failed to initialize curl");
        return Qnil;
    }

    struct curl_slist *headers_list = NULL;
    if (!NIL_P(content_type)) {
        Check_Type(content_type, T_STRING);
        char header_buf[256];
        snprintf(header_buf, sizeof(header_buf), "Content-Type: %s", RSTRING_PTR(content_type));
        headers_list = curl_slist_append(headers_list, header_buf);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers_list);
    }

    response_buffer_t buf = {0};
    buf.data = malloc(1);
    buf.data[0] = '\0';
    buf.size = 0;

    VALUE headers_hash = rb_hash_new();

    curl_easy_setopt(curl, CURLOPT_URL, url_str);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body_str);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)body_len);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, header_callback);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)headers_hash);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Konpeito-HTTP/1.0");

    CURLcode res = curl_easy_perform(curl);

    if (headers_list) {
        curl_slist_free_all(headers_list);
    }

    if (res != CURLE_OK) {
        free(buf.data);
        curl_easy_cleanup(curl);
        rb_raise(rb_eRuntimeError, "HTTP request failed: %s", curl_easy_strerror(res));
        return Qnil;
    }

    long status_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status_code);

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("status")), LONG2NUM(status_code));
    rb_hash_aset(result, ID2SYM(rb_intern("body")), rb_utf8_str_new(buf.data, buf.size));
    rb_hash_aset(result, ID2SYM(rb_intern("headers")), headers_hash);

    free(buf.data);
    curl_easy_cleanup(curl);

    return result;
}

/*
 * Perform HTTP request with custom method and headers
 *
 * @param method [String] HTTP method (GET, POST, PUT, DELETE, PATCH)
 * @param url [String] URL
 * @param body [String, nil] Request body (optional)
 * @param headers [Hash, nil] Custom headers (optional)
 * @return [Hash] Response with :status, :body, :headers
 * @raise [RuntimeError] if request fails
 */
VALUE konpeito_http_request(VALUE self, VALUE method, VALUE url, VALUE body, VALUE headers) {
    Check_Type(method, T_STRING);
    Check_Type(url, T_STRING);

    const char *method_str = RSTRING_PTR(method);
    const char *url_str = RSTRING_PTR(url);

    CURL *curl = curl_easy_init();
    if (!curl) {
        rb_raise(rb_eRuntimeError, "Failed to initialize curl");
        return Qnil;
    }

    /* Set HTTP method */
    if (strcmp(method_str, "GET") == 0) {
        curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    } else if (strcmp(method_str, "POST") == 0) {
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
    } else if (strcmp(method_str, "PUT") == 0) {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PUT");
    } else if (strcmp(method_str, "DELETE") == 0) {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
    } else if (strcmp(method_str, "PATCH") == 0) {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PATCH");
    } else if (strcmp(method_str, "HEAD") == 0) {
        curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    } else {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method_str);
    }

    /* Set request body */
    if (!NIL_P(body)) {
        Check_Type(body, T_STRING);
        const char *body_str = RSTRING_PTR(body);
        size_t body_len = RSTRING_LEN(body);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body_str);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)body_len);
    }

    /* Set custom headers */
    struct curl_slist *headers_list = NULL;
    if (!NIL_P(headers)) {
        Check_Type(headers, T_HASH);
        VALUE keys = rb_funcall(headers, rb_intern("keys"), 0);
        long len = RARRAY_LEN(keys);
        for (long i = 0; i < len; i++) {
            VALUE key = rb_ary_entry(keys, i);
            VALUE val = rb_hash_aref(headers, key);
            VALUE key_str = RB_TYPE_P(key, T_STRING) ? key : rb_funcall(key, rb_intern("to_s"), 0);
            VALUE val_str = RB_TYPE_P(val, T_STRING) ? val : rb_funcall(val, rb_intern("to_s"), 0);

            char header_buf[1024];
            snprintf(header_buf, sizeof(header_buf), "%s: %s",
                     RSTRING_PTR(key_str), RSTRING_PTR(val_str));
            headers_list = curl_slist_append(headers_list, header_buf);
        }
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers_list);
    }

    response_buffer_t buf = {0};
    buf.data = malloc(1);
    buf.data[0] = '\0';
    buf.size = 0;

    VALUE response_headers = rb_hash_new();

    curl_easy_setopt(curl, CURLOPT_URL, url_str);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, header_callback);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)response_headers);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Konpeito-HTTP/1.0");

    CURLcode res = curl_easy_perform(curl);

    if (headers_list) {
        curl_slist_free_all(headers_list);
    }

    if (res != CURLE_OK) {
        free(buf.data);
        curl_easy_cleanup(curl);
        rb_raise(rb_eRuntimeError, "HTTP request failed: %s", curl_easy_strerror(res));
        return Qnil;
    }

    long status_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status_code);

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("status")), LONG2NUM(status_code));
    rb_hash_aset(result, ID2SYM(rb_intern("body")), rb_utf8_str_new(buf.data, buf.size));
    rb_hash_aset(result, ID2SYM(rb_intern("headers")), response_headers);

    free(buf.data);
    curl_easy_cleanup(curl);

    return result;
}

/* Module initialization */
void Init_konpeito_http(void) {
    /* Global curl initialization */
    curl_global_init(CURL_GLOBAL_ALL);

    VALUE mKonpeitoHTTP = rb_define_module("KonpeitoHTTP");

    /* Simple methods (return body only) */
    rb_define_module_function(mKonpeitoHTTP, "get", konpeito_http_get, 1);
    rb_define_module_function(mKonpeitoHTTP, "post", konpeito_http_post, 2);

    /* Full response methods (return Hash with status, body, headers) */
    rb_define_module_function(mKonpeitoHTTP, "get_response", konpeito_http_get_response, 1);
    rb_define_module_function(mKonpeitoHTTP, "post_response", konpeito_http_post_response, 3);

    /* Generic request method */
    rb_define_module_function(mKonpeitoHTTP, "request", konpeito_http_request, 4);

    /* Register cleanup at exit */
    rb_set_end_proc((void (*)(VALUE))curl_global_cleanup, Qnil);
}
