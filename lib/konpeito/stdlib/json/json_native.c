/*
 * Konpeito JSON stdlib - yyjson wrapper
 *
 * Provides fast JSON parsing and generation using yyjson library.
 */

#include <ruby.h>
#include "../../../../vendor/yyjson/yyjson.h"

/* Forward declarations */
static VALUE yyjson_val_to_ruby(yyjson_val *val);
static yyjson_mut_val *ruby_to_yyjson_mut(yyjson_mut_doc *doc, VALUE obj);

/* Convert yyjson value to Ruby VALUE (recursive) */
static VALUE yyjson_val_to_ruby(yyjson_val *val) {
    if (!val) return Qnil;

    yyjson_type type = yyjson_get_type(val);

    switch (type) {
    case YYJSON_TYPE_NULL:
        return Qnil;

    case YYJSON_TYPE_BOOL:
        return yyjson_get_bool(val) ? Qtrue : Qfalse;

    case YYJSON_TYPE_NUM:
        if (yyjson_is_sint(val)) {
            return LONG2NUM(yyjson_get_sint(val));
        } else if (yyjson_is_uint(val)) {
            return ULONG2NUM(yyjson_get_uint(val));
        } else {
            return DBL2NUM(yyjson_get_real(val));
        }

    case YYJSON_TYPE_STR: {
        const char *str = yyjson_get_str(val);
        size_t len = yyjson_get_len(val);
        return rb_utf8_str_new(str, len);
    }

    case YYJSON_TYPE_ARR: {
        VALUE arr = rb_ary_new();
        yyjson_arr_iter iter;
        yyjson_arr_iter_init(val, &iter);
        yyjson_val *elem;
        while ((elem = yyjson_arr_iter_next(&iter))) {
            rb_ary_push(arr, yyjson_val_to_ruby(elem));
        }
        return arr;
    }

    case YYJSON_TYPE_OBJ: {
        VALUE hash = rb_hash_new();
        yyjson_obj_iter iter;
        yyjson_obj_iter_init(val, &iter);
        yyjson_val *key;
        while ((key = yyjson_obj_iter_next(&iter))) {
            yyjson_val *obj_val = yyjson_obj_iter_get_val(key);
            const char *key_str = yyjson_get_str(key);
            size_t key_len = yyjson_get_len(key);
            rb_hash_aset(hash,
                         rb_utf8_str_new(key_str, key_len),
                         yyjson_val_to_ruby(obj_val));
        }
        return hash;
    }

    default:
        return Qnil;
    }
}

/* Convert Ruby VALUE to yyjson mutable value (recursive) */
static yyjson_mut_val *ruby_to_yyjson_mut(yyjson_mut_doc *doc, VALUE obj) {
    if (NIL_P(obj)) {
        return yyjson_mut_null(doc);
    }

    if (obj == Qtrue) {
        return yyjson_mut_bool(doc, true);
    }

    if (obj == Qfalse) {
        return yyjson_mut_bool(doc, false);
    }

    if (RB_INTEGER_TYPE_P(obj)) {
        if (FIXNUM_P(obj)) {
            return yyjson_mut_sint(doc, FIX2LONG(obj));
        } else {
            /* Bignum - try to convert to long long */
            return yyjson_mut_sint(doc, NUM2LL(obj));
        }
    }

    if (RB_FLOAT_TYPE_P(obj)) {
        return yyjson_mut_real(doc, NUM2DBL(obj));
    }

    if (RB_TYPE_P(obj, T_STRING)) {
        const char *str = RSTRING_PTR(obj);
        size_t len = RSTRING_LEN(obj);
        return yyjson_mut_strncpy(doc, str, len);
    }

    if (RB_TYPE_P(obj, T_SYMBOL)) {
        VALUE str = rb_sym2str(obj);
        const char *cstr = RSTRING_PTR(str);
        size_t len = RSTRING_LEN(str);
        return yyjson_mut_strncpy(doc, cstr, len);
    }

    if (RB_TYPE_P(obj, T_ARRAY)) {
        yyjson_mut_val *arr = yyjson_mut_arr(doc);
        long len = RARRAY_LEN(obj);
        for (long i = 0; i < len; i++) {
            VALUE elem = rb_ary_entry(obj, i);
            yyjson_mut_val *mut_elem = ruby_to_yyjson_mut(doc, elem);
            yyjson_mut_arr_append(arr, mut_elem);
        }
        return arr;
    }

    if (RB_TYPE_P(obj, T_HASH)) {
        yyjson_mut_val *hash_obj = yyjson_mut_obj(doc);
        VALUE keys = rb_funcall(obj, rb_intern("keys"), 0);
        long len = RARRAY_LEN(keys);
        for (long i = 0; i < len; i++) {
            VALUE key = rb_ary_entry(keys, i);
            VALUE val = rb_hash_aref(obj, key);

            /* Convert key to string */
            VALUE key_str;
            if (RB_TYPE_P(key, T_STRING)) {
                key_str = key;
            } else if (RB_TYPE_P(key, T_SYMBOL)) {
                key_str = rb_sym2str(key);
            } else {
                key_str = rb_funcall(key, rb_intern("to_s"), 0);
            }

            const char *key_cstr = RSTRING_PTR(key_str);
            size_t key_len = RSTRING_LEN(key_str);
            yyjson_mut_val *mut_key = yyjson_mut_strncpy(doc, key_cstr, key_len);
            yyjson_mut_val *mut_val = ruby_to_yyjson_mut(doc, val);
            yyjson_mut_obj_add(hash_obj, mut_key, mut_val);
        }
        return hash_obj;
    }

    /* For other objects, try to_json or to_s */
    if (rb_respond_to(obj, rb_intern("to_json"))) {
        VALUE json_str = rb_funcall(obj, rb_intern("to_json"), 0);
        const char *str = RSTRING_PTR(json_str);
        size_t len = RSTRING_LEN(json_str);
        /* Parse and return as raw JSON */
        yyjson_doc *inner_doc = yyjson_read(str, len, 0);
        if (inner_doc) {
            yyjson_val *root = yyjson_doc_get_root(inner_doc);
            yyjson_mut_val *result = yyjson_val_mut_copy(doc, root);
            yyjson_doc_free(inner_doc);
            return result;
        }
    }

    /* Fallback: convert to string */
    VALUE str = rb_funcall(obj, rb_intern("to_s"), 0);
    const char *cstr = RSTRING_PTR(str);
    size_t len = RSTRING_LEN(str);
    return yyjson_mut_strncpy(doc, cstr, len);
}

/*
 * Parse JSON string to Ruby object
 *
 * @param json_string [String] JSON string to parse
 * @return [Object] Ruby object (Hash, Array, String, Integer, Float, true, false, nil)
 * @raise [ArgumentError] if JSON is invalid
 */
VALUE konpeito_json_parse(VALUE self, VALUE json_string) {
    Check_Type(json_string, T_STRING);

    const char *str = RSTRING_PTR(json_string);
    size_t len = RSTRING_LEN(json_string);

    yyjson_read_err err;
    yyjson_doc *doc = yyjson_read_opts((char *)str, len, 0, NULL, &err);

    if (!doc) {
        rb_raise(rb_eArgError, "JSON parse error at position %zu: %s",
                 err.pos, err.msg);
        return Qnil;
    }

    yyjson_val *root = yyjson_doc_get_root(doc);
    VALUE result = yyjson_val_to_ruby(root);

    yyjson_doc_free(doc);
    return result;
}

/*
 * Generate JSON string from Ruby object
 *
 * @param obj [Object] Ruby object to convert
 * @return [String] JSON string
 */
VALUE konpeito_json_generate(VALUE self, VALUE obj) {
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    if (!doc) {
        rb_raise(rb_eNoMemError, "Failed to allocate JSON document");
        return Qnil;
    }

    yyjson_mut_val *root = ruby_to_yyjson_mut(doc, obj);
    yyjson_mut_doc_set_root(doc, root);

    size_t len;
    char *json_str = yyjson_mut_write(doc, 0, &len);

    yyjson_mut_doc_free(doc);

    if (!json_str) {
        rb_raise(rb_eRuntimeError, "Failed to generate JSON");
        return Qnil;
    }

    VALUE result = rb_utf8_str_new(json_str, len);
    free(json_str);

    return result;
}

/*
 * Generate pretty-printed JSON string from Ruby object
 *
 * @param obj [Object] Ruby object to convert
 * @param indent [Integer] indentation spaces (default: 2)
 * @return [String] pretty-printed JSON string
 */
VALUE konpeito_json_generate_pretty(VALUE self, VALUE obj, VALUE indent) {
    int indent_spaces = NUM2INT(indent);
    (void)indent_spaces; /* yyjson uses fixed 4-space indent for pretty print */

    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    if (!doc) {
        rb_raise(rb_eNoMemError, "Failed to allocate JSON document");
        return Qnil;
    }

    yyjson_mut_val *root = ruby_to_yyjson_mut(doc, obj);
    yyjson_mut_doc_set_root(doc, root);

    size_t len;
    char *json_str = yyjson_mut_write(doc, YYJSON_WRITE_PRETTY, &len);

    yyjson_mut_doc_free(doc);

    if (!json_str) {
        rb_raise(rb_eRuntimeError, "Failed to generate JSON");
        return Qnil;
    }

    VALUE result = rb_utf8_str_new(json_str, len);
    free(json_str);

    return result;
}

/* Module initialization - called by Init_<extension_name> */
void Init_konpeito_json(void) {
    VALUE mKonpeitoJSON = rb_define_module("KonpeitoJSON");

    rb_define_module_function(mKonpeitoJSON, "parse", konpeito_json_parse, 1);
    rb_define_module_function(mKonpeitoJSON, "generate", konpeito_json_generate, 1);
    rb_define_module_function(mKonpeitoJSON, "generate_pretty", konpeito_json_generate_pretty, 2);

    /* Parse flags as constants */
    rb_define_const(mKonpeitoJSON, "ALLOW_COMMENTS",
                    UINT2NUM(YYJSON_READ_ALLOW_COMMENTS));
    rb_define_const(mKonpeitoJSON, "ALLOW_TRAILING_COMMAS",
                    UINT2NUM(YYJSON_READ_ALLOW_TRAILING_COMMAS));
    rb_define_const(mKonpeitoJSON, "ALLOW_INF_NAN",
                    UINT2NUM(YYJSON_READ_ALLOW_INF_AND_NAN));
}
