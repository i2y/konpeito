/*
 * raylib_wrapper.c - Thin C wrappers for raylib functions
 *
 * Two issues solved by these wrappers:
 * 1. raylib passes Color structs by value — converted to packed RGBA integers.
 * 2. raylib uses C `float` (32-bit) and `bool` — Konpeito's @cfunc maps Float
 *    to LLVM `double` (64-bit) and bool to `int`. Without wrappers, ARM64 ABI
 *    mismatch causes garbage values.
 *
 * All wrapper functions use `double` for floats and `int` for bools so that
 * the C compiler handles the narrowing/widening conversions correctly.
 *
 * Build: clang -c -I$(brew --prefix raylib)/include raylib_wrapper.c -o raylib_wrapper.o
 */

#include <raylib.h>

#ifdef __APPLE__
#include <objc/runtime.h>
#include <objc/message.h>

/* Activate the app so it receives keyboard focus on macOS.
 * Without this, standalone executables (not .app bundles) don't get key events. */
static void activate_macos_app(void) {
    id app = ((id (*)(Class, SEL))objc_msgSend)(
        objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    ((void (*)(id, SEL, int))objc_msgSend)(
        app, sel_registerName("activateIgnoringOtherApps:"), 1);
    /* Also set activation policy to regular (foreground app) */
    ((void (*)(id, SEL, long))objc_msgSend)(
        app, sel_registerName("setActivationPolicy:"), 0);
}
#endif

/* Convert packed RGBA integer to Color struct */
static Color int_to_color(int rgba) {
    Color c;
    c.r = (unsigned char)((rgba >> 24) & 0xFF);
    c.g = (unsigned char)((rgba >> 16) & 0xFF);
    c.b = (unsigned char)((rgba >> 8)  & 0xFF);
    c.a = (unsigned char)(rgba & 0xFF);
    return c;
}

/* ── Color constants (packed RGBA) ── */
int konpeito_raylib_color_white(void)     { return (int)0xFFFFFFFF; }
int konpeito_raylib_color_black(void)     { return (int)0x000000FF; }
int konpeito_raylib_color_red(void)       { return (int)0xFF0000FF; }
int konpeito_raylib_color_green(void)     { return (int)0x00FF00FF; }
int konpeito_raylib_color_blue(void)      { return (int)0x0000FFFF; }
int konpeito_raylib_color_yellow(void)    { return (int)0xFFF700FF; }
int konpeito_raylib_color_darkgray(void)  { return (int)0x505050FF; }
int konpeito_raylib_color_lightgray(void) { return (int)0xC8C8C8FF; }
int konpeito_raylib_color_raywhite(void)  { return (int)0xF5F5F5FF; }

/* ── Window management ── */
void konpeito_init_window(int width, int height, const char *title) {
    InitWindow(width, height, title);
#ifdef __APPLE__
    activate_macos_app();
#endif
}

void konpeito_close_window(void) {
    CloseWindow();
}

int konpeito_window_should_close(void) {
    return (int)WindowShouldClose();
}

void konpeito_set_target_fps(int fps) {
    SetTargetFPS(fps);
}

/* Returns double (64-bit) — raylib's GetFrameTime() returns float (32-bit) */
double konpeito_get_frame_time(void) {
    return (double)GetFrameTime();
}

/* ── Drawing ── */
void konpeito_begin_drawing(void) {
    BeginDrawing();
}

void konpeito_end_drawing(void) {
    EndDrawing();
}

void konpeito_clear_background(int color) {
    ClearBackground(int_to_color(color));
}

void konpeito_draw_rectangle(int x, int y, int width, int height, int color) {
    DrawRectangle(x, y, width, height, int_to_color(color));
}

/* radius: double → float conversion handled by C compiler */
void konpeito_draw_circle(int cx, int cy, double radius, int color) {
    DrawCircle(cx, cy, (float)radius, int_to_color(color));
}

void konpeito_draw_text(const char *text, int x, int y, int font_size, int color) {
    DrawText(text, x, y, font_size, int_to_color(color));
}

void konpeito_draw_line(int x1, int y1, int x2, int y2, int color) {
    DrawLine(x1, y1, x2, y2, int_to_color(color));
}

/* ── Input ── */
int konpeito_is_key_down(int key) {
    return (int)IsKeyDown(key);
}

int konpeito_is_key_pressed(int key) {
    return (int)IsKeyPressed(key);
}
