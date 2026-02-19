/*
 * yyjson_wrapper.c - Non-inline wrappers for yyjson functions
 *
 * yyjson uses static inline functions in its header. When linking with
 * LLVM-generated code, we need non-inline versions that can be called
 * via external symbol references. This file provides those wrappers.
 */

#include "yyjson.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

yyjson_doc *konpeito_yyjson_read(const char *dat, size_t len, yyjson_read_flag flg) {
    return yyjson_read(dat, len, flg);
}

yyjson_val *konpeito_yyjson_doc_get_root(yyjson_doc *doc) {
    return yyjson_doc_get_root(doc);
}

void konpeito_yyjson_doc_free(yyjson_doc *doc) {
    yyjson_doc_free(doc);
}

yyjson_val *konpeito_yyjson_obj_get(yyjson_val *obj, const char *key) {
    return yyjson_obj_get(obj, key);
}

int64_t konpeito_yyjson_get_sint(yyjson_val *val) {
    return yyjson_get_sint(val);
}

uint64_t konpeito_yyjson_get_uint(yyjson_val *val) {
    return yyjson_get_uint(val);
}

double konpeito_yyjson_get_real(yyjson_val *val) {
    return yyjson_get_real(val);
}

bool konpeito_yyjson_get_bool(yyjson_val *val) {
    return yyjson_get_bool(val);
}

const char *konpeito_yyjson_get_str(yyjson_val *val) {
    return yyjson_get_str(val);
}

size_t konpeito_yyjson_get_len(yyjson_val *val) {
    return yyjson_get_len(val);
}

size_t konpeito_yyjson_arr_size(yyjson_val *arr) {
    return yyjson_arr_size(arr);
}

yyjson_val *konpeito_yyjson_arr_get(yyjson_val *arr, size_t idx) {
    return yyjson_arr_get(arr, idx);
}
