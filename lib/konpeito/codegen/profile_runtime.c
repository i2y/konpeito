/* profile_runtime.c - Konpeito Profiling Runtime
 *
 * Thread-safe profiling with minimal overhead.
 * Uses atomic counters and clock_gettime for timing.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

/* Maximum number of functions we can profile */
#define MAX_FUNCTIONS 4096

/* Maximum call stack depth for timing */
#define MAX_CALL_DEPTH 256

/* Maximum number of unique stack traces for flame graph */
#define MAX_STACK_SAMPLES 65536

/* Per-function profiling data */
typedef struct {
    const char* name;
    uint64_t call_count;
    uint64_t total_time_ns;
} FunctionProfile;

/* Stack sample for flame graph */
typedef struct {
    int func_ids[MAX_CALL_DEPTH];
    int depth;
    uint64_t time_ns;  /* Time spent at this exact stack */
} StackSample;

/* Thread-local call stack for timing */
typedef struct {
    int func_id;
    uint64_t entry_time;
} CallStackEntry;

/* Global profiling state */
static FunctionProfile g_profiles[MAX_FUNCTIONS];
static int g_num_functions = 0;
static char g_output_path[1024] = "konpeito_profile.json";
static int g_initialized = 0;

/* Flame graph stack samples - stores aggregated time per unique call stack */
static StackSample g_stack_samples[MAX_STACK_SAMPLES];
static int g_num_stack_samples = 0;

/* Thread-local storage for call stack */
static __thread CallStackEntry tls_call_stack[MAX_CALL_DEPTH];
static __thread int tls_stack_depth = 0;
static __thread int tls_current_stack[MAX_CALL_DEPTH];  /* Current stack for flame graph */

#ifdef __APPLE__
static mach_timebase_info_data_t g_timebase_info;
#endif

/* Get current time in nanoseconds */
static inline uint64_t get_time_ns(void) {
#ifdef __APPLE__
    uint64_t mach_time = mach_absolute_time();
    return mach_time * g_timebase_info.numer / g_timebase_info.denom;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
#endif
}

/* Forward declaration */
void konpeito_profile_finalize(void);

/* Find or create a stack sample for the current call stack */
static int find_or_create_stack_sample(int* stack, int depth) {
    /* Search for existing sample with same stack */
    for (int i = 0; i < g_num_stack_samples; i++) {
        if (g_stack_samples[i].depth == depth) {
            int match = 1;
            for (int j = 0; j < depth; j++) {
                if (g_stack_samples[i].func_ids[j] != stack[j]) {
                    match = 0;
                    break;
                }
            }
            if (match) return i;
        }
    }

    /* Create new sample if space available */
    if (g_num_stack_samples >= MAX_STACK_SAMPLES) return -1;

    int idx = g_num_stack_samples++;
    g_stack_samples[idx].depth = depth;
    for (int j = 0; j < depth; j++) {
        g_stack_samples[idx].func_ids[j] = stack[j];
    }
    g_stack_samples[idx].time_ns = 0;
    return idx;
}

/* Record time for current stack */
static void record_stack_time(uint64_t time_ns) {
    if (tls_stack_depth <= 0) return;

    int idx = find_or_create_stack_sample(tls_current_stack, tls_stack_depth);
    if (idx >= 0) {
        g_stack_samples[idx].time_ns += time_ns;
    }
}

/* Initialize profiling system */
void konpeito_profile_init(int num_functions, const char* output_path) {
    if (g_initialized) return;

    g_num_functions = num_functions < MAX_FUNCTIONS ? num_functions : MAX_FUNCTIONS;

    if (output_path && strlen(output_path) < sizeof(g_output_path)) {
        strncpy(g_output_path, output_path, sizeof(g_output_path) - 1);
        g_output_path[sizeof(g_output_path) - 1] = '\0';
    }

    for (int i = 0; i < MAX_FUNCTIONS; i++) {
        g_profiles[i].name = NULL;
        g_profiles[i].call_count = 0;
        g_profiles[i].total_time_ns = 0;
    }

#ifdef __APPLE__
    mach_timebase_info(&g_timebase_info);
#endif

    g_initialized = 1;

    /* Register atexit handler */
    atexit(konpeito_profile_finalize);
}

/* Called at function entry */
void konpeito_profile_enter(int func_id, const char* func_name) {
    if (!g_initialized) return;
    if (func_id < 0 || func_id >= MAX_FUNCTIONS) return;
    if (tls_stack_depth >= MAX_CALL_DEPTH) return;

    /* Register function name (only first call matters) */
    if (g_profiles[func_id].name == NULL) {
        g_profiles[func_id].name = func_name;
    }

    /* Increment call count */
    g_profiles[func_id].call_count++;

    /* Push entry onto call stack with timestamp */
    tls_call_stack[tls_stack_depth].func_id = func_id;
    tls_call_stack[tls_stack_depth].entry_time = get_time_ns();

    /* Track current stack for flame graph */
    tls_current_stack[tls_stack_depth] = func_id;

    tls_stack_depth++;
}

/* Called at function exit */
void konpeito_profile_exit(int func_id) {
    if (!g_initialized) return;
    if (func_id < 0 || func_id >= MAX_FUNCTIONS) return;
    if (tls_stack_depth <= 0) return;

    /* Calculate elapsed time */
    uint64_t exit_time = get_time_ns();

    /* Verify we're exiting the right function */
    if (tls_call_stack[tls_stack_depth - 1].func_id == func_id) {
        uint64_t elapsed = exit_time - tls_call_stack[tls_stack_depth - 1].entry_time;
        g_profiles[func_id].total_time_ns += elapsed;

        /* Record time for flame graph at current stack depth */
        record_stack_time(elapsed);
    }

    /* Pop from call stack */
    tls_stack_depth--;
}

/* Escape string for JSON output */
static void write_json_string(FILE* fp, const char* str) {
    fputc('"', fp);
    while (*str) {
        switch (*str) {
            case '"':  fputs("\\\"", fp); break;
            case '\\': fputs("\\\\", fp); break;
            case '\n': fputs("\\n", fp); break;
            case '\r': fputs("\\r", fp); break;
            case '\t': fputs("\\t", fp); break;
            default:   fputc(*str, fp); break;
        }
        str++;
    }
    fputc('"', fp);
}

/* Write flame graph folded format */
static void write_flame_graph_folded(void) {
    /* Generate folded file path */
    char folded_path[1024];
    strncpy(folded_path, g_output_path, sizeof(folded_path) - 1);
    folded_path[sizeof(folded_path) - 1] = '\0';

    /* Replace .json with .folded */
    char* ext = strstr(folded_path, ".json");
    if (ext) {
        strcpy(ext, ".folded");
    } else {
        strncat(folded_path, ".folded", sizeof(folded_path) - strlen(folded_path) - 1);
    }

    FILE* fp = fopen(folded_path, "w");
    if (!fp) {
        fprintf(stderr, "Warning: Could not write flame graph to %s\n", folded_path);
        return;
    }

    /* Write folded format: func1;func2;func3 samples
     * Use microseconds as sample count for better granularity */
    for (int i = 0; i < g_num_stack_samples; i++) {
        if (g_stack_samples[i].time_ns == 0) continue;

        /* Write stack (semicolon-separated function names) */
        for (int j = 0; j < g_stack_samples[i].depth; j++) {
            int func_id = g_stack_samples[i].func_ids[j];
            const char* name = g_profiles[func_id].name;
            if (name) {
                if (j > 0) fputc(';', fp);
                fputs(name, fp);
            }
        }

        /* Write sample count (microseconds) */
        uint64_t samples = g_stack_samples[i].time_ns / 1000;  /* ns to us */
        if (samples == 0) samples = 1;  /* At least 1 sample */
        fprintf(fp, " %llu\n", (unsigned long long)samples);
    }

    fclose(fp);
    fprintf(stderr, "Flame graph data written to: %s\n", folded_path);
    fprintf(stderr, "  Generate SVG with: flamegraph.pl %s > profile.svg\n", folded_path);
}

/* Finalize and write profile data */
void konpeito_profile_finalize(void) {
    if (!g_initialized) return;
    g_initialized = 0;  /* Prevent double finalization */

    /* Write flame graph folded format */
    write_flame_graph_folded();

    FILE* fp = fopen(g_output_path, "w");
    if (!fp) {
        fprintf(stderr, "Warning: Could not write profile to %s\n", g_output_path);
        return;
    }

    /* Calculate total time */
    uint64_t total_time = 0;
    for (int i = 0; i < g_num_functions; i++) {
        if (g_profiles[i].name) {
            total_time += g_profiles[i].total_time_ns;
        }
    }

    /* Write JSON output */
    fprintf(fp, "{\n  \"functions\": [\n");

    int first = 1;
    for (int i = 0; i < g_num_functions; i++) {
        if (g_profiles[i].name == NULL) continue;

        uint64_t calls = g_profiles[i].call_count;
        uint64_t time_ns = g_profiles[i].total_time_ns;
        double time_ms = time_ns / 1000000.0;
        double percent = total_time > 0 ? (time_ns * 100.0 / total_time) : 0.0;

        if (!first) fprintf(fp, ",\n");
        first = 0;

        fprintf(fp, "    {\n");
        fprintf(fp, "      \"name\": ");
        write_json_string(fp, g_profiles[i].name);
        fprintf(fp, ",\n");
        fprintf(fp, "      \"calls\": %llu,\n", (unsigned long long)calls);
        fprintf(fp, "      \"time_ms\": %.3f,\n", time_ms);
        fprintf(fp, "      \"percent\": %.2f\n", percent);
        fprintf(fp, "    }");
    }

    fprintf(fp, "\n  ],\n");
    fprintf(fp, "  \"total_time_ms\": %.3f\n", total_time / 1000000.0);
    fprintf(fp, "}\n");

    fclose(fp);

    /* Print summary to stderr */
    fprintf(stderr, "\n=== Konpeito Profile Summary ===\n");
    fprintf(stderr, "%-40s %12s %12s %8s\n", "Function", "Calls", "Time (ms)", "%");
    fprintf(stderr, "%-40s %12s %12s %8s\n",
            "----------------------------------------",
            "------------", "------------", "--------");

    for (int i = 0; i < g_num_functions; i++) {
        if (g_profiles[i].name == NULL) continue;

        uint64_t calls = g_profiles[i].call_count;
        uint64_t time_ns = g_profiles[i].total_time_ns;
        double time_ms = time_ns / 1000000.0;
        double percent = total_time > 0 ? (time_ns * 100.0 / total_time) : 0.0;

        /* Truncate function name if too long */
        char truncated_name[41];
        if (strlen(g_profiles[i].name) > 40) {
            strncpy(truncated_name, g_profiles[i].name, 37);
            truncated_name[37] = '.';
            truncated_name[38] = '.';
            truncated_name[39] = '.';
            truncated_name[40] = '\0';
        } else {
            strncpy(truncated_name, g_profiles[i].name, 40);
            truncated_name[40] = '\0';
        }

        fprintf(stderr, "%-40s %12llu %12.3f %7.2f%%\n",
                truncated_name, (unsigned long long)calls, time_ms, percent);
    }

    fprintf(stderr, "\nProfile data written to: %s\n", g_output_path);
}
