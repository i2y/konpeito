/*
 * Konpeito UI Native - SDL3 + Skia C API header
 *
 * Provides window management, event polling, and 2D drawing
 * for the Castella UI framework on the LLVM backend.
 */

#ifndef KONPEITO_UI_NATIVE_H
#define KONPEITO_UI_NATIVE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to the UI context (window + canvas + event queue) */
typedef struct KUIContext KUIContext;

/* --- Event types (matches JWM/Castella conventions) --- */
#define KUI_EVENT_NONE          0
#define KUI_EVENT_MOUSE_DOWN    1
#define KUI_EVENT_MOUSE_UP      2
#define KUI_EVENT_MOUSE_MOVE    3
#define KUI_EVENT_MOUSE_WHEEL   4
#define KUI_EVENT_KEY_DOWN      5
#define KUI_EVENT_KEY_UP        6
#define KUI_EVENT_TEXT_INPUT    7
#define KUI_EVENT_RESIZE        8
#define KUI_EVENT_IME_PREEDIT   9
#define KUI_EVENT_QUIT         10

/* --- Key modifier flags (matches JWM conventions) --- */
#define KUI_MOD_SHIFT    1
#define KUI_MOD_CONTROL  2
#define KUI_MOD_ALT      4
#define KUI_MOD_SUPER    8  /* Command on macOS */

/* --- Event ring buffer entry --- */
typedef struct {
    int type;
    double x, y;           /* mouse position or scroll delta */
    double dx, dy;         /* scroll delta for wheel events */
    int button;            /* mouse button (0=left, 1=middle, 2=right) */
    int key_code;          /* JWM-compatible key ordinal */
    int modifiers;         /* modifier flags */
    char text[128];        /* text input or IME preedit text */
    int ime_sel_start;     /* IME selection start */
    int ime_sel_end;       /* IME selection end */
} KUIEvent;

/* Max events in ring buffer */
#define KUI_EVENT_BUFFER_SIZE 256

/* --- Window management --- */
KUIContext* kui_create_window(const char* title, int width, int height);
void        kui_destroy_window(KUIContext* ctx);
void        kui_step(KUIContext* ctx);  /* Poll SDL events into ring buffer */

/* --- Event access (scalar field getters, no struct passing) --- */
bool kui_has_event(KUIContext* ctx);
int  kui_event_type(KUIContext* ctx);
double kui_event_x(KUIContext* ctx);
double kui_event_y(KUIContext* ctx);
double kui_event_dx(KUIContext* ctx);
double kui_event_dy(KUIContext* ctx);
int  kui_event_button(KUIContext* ctx);
int  kui_event_key_code(KUIContext* ctx);
int  kui_event_modifiers(KUIContext* ctx);
const char* kui_event_text(KUIContext* ctx);
int  kui_event_ime_sel_start(KUIContext* ctx);
int  kui_event_ime_sel_end(KUIContext* ctx);
void kui_consume_event(KUIContext* ctx);

/* --- Frame management (Skia canvas begin/end) --- */
void kui_begin_frame(KUIContext* ctx);
void kui_end_frame(KUIContext* ctx);

/* --- Drawing primitives --- */
void kui_clear(KUIContext* ctx, uint32_t color);
void kui_fill_rect(KUIContext* ctx, double x, double y, double w, double h, uint32_t color);
void kui_stroke_rect(KUIContext* ctx, double x, double y, double w, double h, uint32_t color, double stroke_width);
void kui_fill_round_rect(KUIContext* ctx, double x, double y, double w, double h, double r, uint32_t color);
void kui_stroke_round_rect(KUIContext* ctx, double x, double y, double w, double h, double r, uint32_t color, double stroke_width);
void kui_fill_circle(KUIContext* ctx, double cx, double cy, double r, uint32_t color);
void kui_stroke_circle(KUIContext* ctx, double cx, double cy, double r, uint32_t color, double stroke_width);
void kui_draw_line(KUIContext* ctx, double x1, double y1, double x2, double y2, uint32_t color, double width);
void kui_fill_arc(KUIContext* ctx, double cx, double cy, double r, double start_angle, double sweep_angle, uint32_t color);
void kui_stroke_arc(KUIContext* ctx, double cx, double cy, double r, double start_angle, double sweep_angle, uint32_t color, double stroke_width);
void kui_fill_triangle(KUIContext* ctx, double x1, double y1, double x2, double y2, double x3, double y3, uint32_t color);

/* --- Text drawing --- */
void kui_draw_text(KUIContext* ctx, const char* text, double x, double y,
                   const char* font_family, double font_size, uint32_t color);
void kui_draw_text_styled(KUIContext* ctx, const char* text, double x, double y,
                          const char* font_family, double font_size, uint32_t color,
                          int weight, int slant);

/* --- Text measurement --- */
double kui_measure_text_width(KUIContext* ctx, const char* text, const char* font_family, double font_size);
double kui_measure_text_height(KUIContext* ctx, const char* font_family, double font_size);
double kui_get_text_ascent(KUIContext* ctx, const char* font_family, double font_size);

/* --- Path drawing --- */
void kui_begin_path(KUIContext* ctx);
void kui_path_move_to(KUIContext* ctx, double x, double y);
void kui_path_line_to(KUIContext* ctx, double x, double y);
void kui_close_fill_path(KUIContext* ctx, uint32_t color);
void kui_fill_path(KUIContext* ctx, uint32_t color);

/* --- Canvas state --- */
void kui_save(KUIContext* ctx);
void kui_restore(KUIContext* ctx);
void kui_translate(KUIContext* ctx, double dx, double dy);
void kui_clip_rect(KUIContext* ctx, double x, double y, double w, double h);

/* --- Image operations --- */
int    kui_load_image(KUIContext* ctx, const char* path);
int    kui_load_net_image(KUIContext* ctx, const char* url);
void   kui_draw_image(KUIContext* ctx, int image_id, double x, double y, double w, double h);
double kui_get_image_width(KUIContext* ctx, int image_id);
double kui_get_image_height(KUIContext* ctx, int image_id);

/* --- Color utilities --- */
uint32_t kui_interpolate_color(uint32_t c1, uint32_t c2, double t);
uint32_t kui_with_alpha(uint32_t color, int alpha);
uint32_t kui_lighten_color(uint32_t color, double amount);
uint32_t kui_darken_color(uint32_t color, double amount);

/* --- Window queries --- */
double kui_get_width(KUIContext* ctx);
double kui_get_height(KUIContext* ctx);
double kui_get_scale(KUIContext* ctx);
bool   kui_is_dark_mode(KUIContext* ctx);
void   kui_request_frame(KUIContext* ctx);
void   kui_mark_dirty(KUIContext* ctx);

/* --- IME / Text Input --- */
void kui_set_text_input_enabled(KUIContext* ctx, bool enabled);
void kui_set_text_input_rect(KUIContext* ctx, int x, int y, int w, int h);

/* --- Clipboard --- */
const char* kui_get_clipboard_text(KUIContext* ctx);
void        kui_set_clipboard_text(KUIContext* ctx, const char* text);

/* --- Utilities --- */
int64_t kui_current_time_millis(void);
const char* kui_number_to_string(double value);

/* --- Math helpers (mirrors KUIRuntime.java) --- */
double kui_math_cos(double radians);
double kui_math_sin(double radians);
double kui_math_sqrt(double value);
double kui_math_atan2(double y, double x);
double kui_math_abs(double value);

#ifdef __cplusplus
}
#endif

#endif /* KONPEITO_UI_NATIVE_H */
