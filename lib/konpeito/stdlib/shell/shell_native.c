/*
 * shell_native.c — Konpeito stdlib Shell/Env/File operations
 *
 * Provides shell execution (popen), environment variables (getenv),
 * and basic file I/O (fopen/fread/fwrite) for mruby backend.
 *
 * All functions use scalar types (const char*, int) for @cfunc compatibility.
 * Returned strings use a dynamically allocated global buffer that is reused
 * across calls (caller must use result before next call).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* ═══════════════════════════════════════════
 *  Shell Execution (popen)
 * ═══════════════════════════════════════════ */

static char *g_exec_result = NULL;
static int g_exec_status = 0;

/*
 * Execute a shell command and return its stdout output.
 * The returned string is valid until the next exec/exec_capture call.
 */
const char *konpeito_shell_exec(const char *cmd) {
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        free(g_exec_result);
        g_exec_result = NULL;
        g_exec_status = -1;
        return "";
    }

    size_t capacity = 4096;
    size_t total = 0;
    char *buf = (char *)malloc(capacity);
    if (!buf) {
        pclose(fp);
        g_exec_status = -1;
        return "";
    }

    while (1) {
        size_t n = fread(buf + total, 1, capacity - total - 1, fp);
        if (n == 0) break;
        total += n;
        if (total >= capacity - 1) {
            capacity *= 2;
            char *newbuf = (char *)realloc(buf, capacity);
            if (!newbuf) break;
            buf = newbuf;
        }
    }
    buf[total] = '\0';

    /* Remove trailing newline if present */
    if (total > 0 && buf[total - 1] == '\n') {
        buf[total - 1] = '\0';
    }

    int status = pclose(fp);
    g_exec_status = WIFEXITED(status) ? WEXITSTATUS(status) : -1;

    free(g_exec_result);
    g_exec_result = buf;
    return g_exec_result;
}

/*
 * Return the exit status of the last exec() call.
 * 0 = success, non-zero = error, -1 = popen failed.
 */
int konpeito_shell_exec_status(void) {
    return g_exec_status;
}

/*
 * Execute a shell command and return only the exit status.
 * Stdout is discarded.
 */
int konpeito_shell_system(const char *cmd) {
    int status = system(cmd);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/* ═══════════════════════════════════════════
 *  Environment Variables
 * ═══════════════════════════════════════════ */

/*
 * Get an environment variable value.
 * Returns "" if the variable is not set.
 */
const char *konpeito_shell_getenv(const char *name) {
    const char *val = getenv(name);
    return val ? val : "";
}

/*
 * Set an environment variable.
 * Returns 0 on success, -1 on failure.
 */
int konpeito_shell_setenv(const char *name, const char *value) {
    return setenv(name, value, 1);
}

/* ═══════════════════════════════════════════
 *  File I/O
 * ═══════════════════════════════════════════ */

static char *g_file_result = NULL;

/*
 * Read entire file contents as a string.
 * Returns "" if file cannot be opened.
 */
const char *konpeito_shell_read_file(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        free(g_file_result);
        g_file_result = NULL;
        return "";
    }

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if (size < 0 || size > 100 * 1024 * 1024) { /* 100MB limit */
        fclose(fp);
        free(g_file_result);
        g_file_result = NULL;
        return "";
    }

    char *buf = (char *)malloc((size_t)size + 1);
    if (!buf) {
        fclose(fp);
        return "";
    }

    size_t read = fread(buf, 1, (size_t)size, fp);
    buf[read] = '\0';
    fclose(fp);

    free(g_file_result);
    g_file_result = buf;
    return g_file_result;
}

/*
 * Write a string to a file (overwrite).
 * Returns number of bytes written, or -1 on failure.
 */
int konpeito_shell_write_file(const char *path, const char *content) {
    FILE *fp = fopen(path, "wb");
    if (!fp) return -1;

    size_t len = strlen(content);
    size_t written = fwrite(content, 1, len, fp);
    fclose(fp);

    return (int)written;
}

/*
 * Append a string to a file.
 * Returns number of bytes written, or -1 on failure.
 */
int konpeito_shell_append_file(const char *path, const char *content) {
    FILE *fp = fopen(path, "ab");
    if (!fp) return -1;

    size_t len = strlen(content);
    size_t written = fwrite(content, 1, len, fp);
    fclose(fp);

    return (int)written;
}

/*
 * Check if a file exists.
 * Returns 1 if exists, 0 otherwise.
 */
int konpeito_shell_file_exists(const char *path) {
    FILE *fp = fopen(path, "r");
    if (fp) {
        fclose(fp);
        return 1;
    }
    return 0;
}
