/*
 * breakout_wrapper.c - raylib wrappers + block grid for Breakout
 *
 * Raylib wrappers handle float/double and Color struct ABI issues.
 * Block grid is a simple C array exposed via getter/setter functions,
 * because Konpeito mruby backend doesn't yet support Array in @cfunc context.
 */

#include <raylib.h>
#include <string.h>

#ifdef __APPLE__
#include <objc/runtime.h>
#include <objc/message.h>
static void activate_macos_app(void) {
    id app = ((id (*)(Class, SEL))objc_msgSend)(
        objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    ((void (*)(id, SEL, int))objc_msgSend)(
        app, sel_registerName("activateIgnoringOtherApps:"), 1);
    ((void (*)(id, SEL, long))objc_msgSend)(
        app, sel_registerName("setActivationPolicy:"), 0);
}
#endif

/* ── Color helpers ── */
static Color int_to_color(int rgba) {
    Color c;
    c.r = (unsigned char)((rgba >> 24) & 0xFF);
    c.g = (unsigned char)((rgba >> 16) & 0xFF);
    c.b = (unsigned char)((rgba >> 8)  & 0xFF);
    c.a = (unsigned char)(rgba & 0xFF);
    return c;
}

/* ── Color constants ── */
int konpeito_color_white(void)     { return (int)0xFFFFFFFF; }
int konpeito_color_black(void)     { return (int)0x000000FF; }
int konpeito_color_red(void)       { return (int)0xE62937FF; }
int konpeito_color_orange(void)    { return (int)0xFF6A00FF; }
int konpeito_color_yellow(void)    { return (int)0xFFF700FF; }
int konpeito_color_green(void)     { return (int)0x00E430FF; }
int konpeito_color_blue(void)      { return (int)0x0079F1FF; }
int konpeito_color_darkgray(void)  { return (int)0x505050FF; }
int konpeito_color_lightgray(void) { return (int)0xC8C8C8FF; }
int konpeito_color_raywhite(void)  { return (int)0xF5F5F5FF; }
int konpeito_color_darkblue(void)  { return (int)0x002B59FF; }
int konpeito_color_skyblue(void)   { return (int)0x66BFFFFF; }
int konpeito_color_purple(void)    { return (int)0xC87AFFFF; }
int konpeito_color_pink(void)      { return (int)0xFF6B9DFF; }

/* ── Window ── */
void konpeito_init_window(int w, int h, const char *title) {
    InitWindow(w, h, title);
#ifdef __APPLE__
    activate_macos_app();
#endif
}
void konpeito_close_window(void)          { CloseWindow(); }
int  konpeito_window_should_close(void)   { return (int)WindowShouldClose(); }
void konpeito_set_target_fps(int fps)     { SetTargetFPS(fps); }
double konpeito_get_frame_time(void)      { return (double)GetFrameTime(); }

/* ── Drawing ── */
void konpeito_begin_drawing(void) { BeginDrawing(); }
void konpeito_end_drawing(void)   { EndDrawing(); }

void konpeito_clear_background(int color) {
    ClearBackground(int_to_color(color));
}
void konpeito_draw_rectangle(int x, int y, int w, int h, int color) {
    DrawRectangle(x, y, w, h, int_to_color(color));
}
void konpeito_draw_circle(int cx, int cy, double radius, int color) {
    DrawCircle(cx, cy, (float)radius, int_to_color(color));
}
void konpeito_draw_text(const char *text, int x, int y, int size, int color) {
    DrawText(text, x, y, size, int_to_color(color));
}
void konpeito_draw_line(int x1, int y1, int x2, int y2, int color) {
    DrawLine(x1, y1, x2, y2, int_to_color(color));
}

/* ── Input ── */
int konpeito_is_key_down(int key)    { return (int)IsKeyDown(key); }
int konpeito_is_key_pressed(int key) { return (int)IsKeyPressed(key); }

/* ── Block grid (5 rows x 10 cols) ── */
#define BLOCK_ROWS 5
#define BLOCK_COLS 10
static int block_grid[BLOCK_ROWS * BLOCK_COLS];

void konpeito_blocks_init(void) {
    for (int i = 0; i < BLOCK_ROWS * BLOCK_COLS; i++)
        block_grid[i] = 1;
}

int konpeito_block_get(int row, int col) {
    if (row < 0 || row >= BLOCK_ROWS || col < 0 || col >= BLOCK_COLS) return 0;
    return block_grid[row * BLOCK_COLS + col];
}

void konpeito_block_set(int row, int col, int val) {
    if (row < 0 || row >= BLOCK_ROWS || col < 0 || col >= BLOCK_COLS) return;
    block_grid[row * BLOCK_COLS + col] = val;
}

int konpeito_blocks_remaining(void) {
    int count = 0;
    for (int i = 0; i < BLOCK_ROWS * BLOCK_COLS; i++)
        count += block_grid[i];
    return count;
}

/* ── Audio (simple beep via raylib) ── */
void konpeito_play_sound_beep(void) {
    /* No-op if audio not initialized; keeps things simple */
}
