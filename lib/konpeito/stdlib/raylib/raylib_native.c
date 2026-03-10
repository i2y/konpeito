/*
 * raylib_native.c — Konpeito stdlib raylib bindings
 *
 * Thin C wrappers that solve two ABI issues:
 * 1. raylib passes Color structs by value — we pack them as RGBA integers.
 * 2. raylib uses C float (32-bit) / bool — Konpeito @cfunc uses double / int.
 *
 * Users never need to see this file. They just write Ruby code using the
 * Raylib module defined in raylib.rbs.
 */

#include <raylib.h>
#include <string.h>
#include <math.h>

/* ── macOS app activation ── */
#ifdef __APPLE__
#include <objc/runtime.h>
#include <objc/message.h>

static int macos_activated = 0;

static void activate_macos_app(void) {
    if (macos_activated) return;
    macos_activated = 1;
    id app = ((id (*)(Class, SEL))objc_msgSend)(
        objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    ((void (*)(id, SEL, int))objc_msgSend)(
        app, sel_registerName("activateIgnoringOtherApps:"), 1);
    ((void (*)(id, SEL, long))objc_msgSend)(
        app, sel_registerName("setActivationPolicy:"), 0);
}
#endif

/* ── Color conversion ── */
static Color int_to_color(int rgba) {
    Color c;
    c.r = (unsigned char)((rgba >> 24) & 0xFF);
    c.g = (unsigned char)((rgba >> 16) & 0xFF);
    c.b = (unsigned char)((rgba >> 8)  & 0xFF);
    c.a = (unsigned char)(rgba & 0xFF);
    return c;
}

static int color_to_int(Color c) {
    return (c.r << 24) | (c.g << 16) | (c.b << 8) | c.a;
}

/* ═══════════════════════════════════════════
 *  Window Management
 * ═══════════════════════════════════════════ */

void konpeito_set_config_flags(int flags) { SetConfigFlags((unsigned int)flags); }

void konpeito_init_window(int w, int h, const char *title) {
    InitWindow(w, h, title);
#ifdef __APPLE__
    activate_macos_app();
#endif
}

void konpeito_close_window(void)        { CloseWindow(); }
int  konpeito_window_should_close(void) { return (int)WindowShouldClose(); }
void konpeito_set_target_fps(int fps)   { SetTargetFPS(fps); }
double konpeito_get_frame_time(void)    { return (double)GetFrameTime(); }
double konpeito_get_time(void)          { return (double)GetTime(); }
int  konpeito_get_screen_width(void)    { return GetScreenWidth(); }
int  konpeito_get_screen_height(void)   { return GetScreenHeight(); }
void konpeito_set_window_title(const char *title) { SetWindowTitle(title); }
void konpeito_set_window_size(int w, int h) { SetWindowSize(w, h); }
int  konpeito_is_window_focused(void)   { return (int)IsWindowFocused(); }
int  konpeito_is_window_resized(void)   { return (int)IsWindowResized(); }
void konpeito_toggle_fullscreen(void)   { ToggleFullscreen(); }
int  konpeito_get_fps(void)             { return GetFPS(); }

/* ═══════════════════════════════════════════
 *  Drawing — Core
 * ═══════════════════════════════════════════ */

void konpeito_begin_drawing(void) { BeginDrawing(); }
void konpeito_end_drawing(void)   { EndDrawing(); }
void konpeito_clear_background(int color) { ClearBackground(int_to_color(color)); }

/* ═══════════════════════════════════════════
 *  Drawing — Shapes
 * ═══════════════════════════════════════════ */

void konpeito_draw_rectangle(int x, int y, int w, int h, int color) {
    DrawRectangle(x, y, w, h, int_to_color(color));
}

void konpeito_draw_rectangle_lines(int x, int y, int w, int h, int color) {
    DrawRectangleLines(x, y, w, h, int_to_color(color));
}

void konpeito_draw_circle(int cx, int cy, double radius, int color) {
    DrawCircle(cx, cy, (float)radius, int_to_color(color));
}

void konpeito_draw_circle_lines(int cx, int cy, double radius, int color) {
    DrawCircleLines(cx, cy, (float)radius, int_to_color(color));
}

void konpeito_draw_line(int x1, int y1, int x2, int y2, int color) {
    DrawLine(x1, y1, x2, y2, int_to_color(color));
}

void konpeito_draw_line_ex(double x1, double y1, double x2, double y2, double thick, int color) {
    DrawLineEx((Vector2){(float)x1, (float)y1}, (Vector2){(float)x2, (float)y2}, (float)thick, int_to_color(color));
}

void konpeito_draw_triangle(double x1, double y1, double x2, double y2, double x3, double y3, int color) {
    DrawTriangle((Vector2){(float)x1, (float)y1}, (Vector2){(float)x2, (float)y2},
                 (Vector2){(float)x3, (float)y3}, int_to_color(color));
}

void konpeito_draw_pixel(int x, int y, int color) {
    DrawPixel(x, y, int_to_color(color));
}

/* ═══════════════════════════════════════════
 *  Drawing — Text
 * ═══════════════════════════════════════════ */

void konpeito_draw_text(const char *text, int x, int y, int size, int color) {
    DrawText(text, x, y, size, int_to_color(color));
}

int konpeito_measure_text(const char *text, int size) {
    return MeasureText(text, size);
}

/* ═══════════════════════════════════════════
 *  Input — Keyboard
 * ═══════════════════════════════════════════ */

int konpeito_is_key_down(int key)      { return (int)IsKeyDown(key); }
int konpeito_is_key_pressed(int key)   { return (int)IsKeyPressed(key); }
int konpeito_is_key_released(int key)  { return (int)IsKeyReleased(key); }
int konpeito_is_key_up(int key)        { return (int)IsKeyUp(key); }
int konpeito_get_key_pressed(void)     { return GetKeyPressed(); }
int konpeito_get_char_pressed(void)    { return GetCharPressed(); }

/* ═══════════════════════════════════════════
 *  Input — Mouse
 * ═══════════════════════════════════════════ */

int konpeito_get_mouse_x(void)         { return GetMouseX(); }
int konpeito_get_mouse_y(void)         { return GetMouseY(); }
int konpeito_is_mouse_button_pressed(int btn)  { return (int)IsMouseButtonPressed(btn); }
int konpeito_is_mouse_button_down(int btn)     { return (int)IsMouseButtonDown(btn); }
int konpeito_is_mouse_button_released(int btn) { return (int)IsMouseButtonReleased(btn); }
double konpeito_get_mouse_wheel_move(void)     { return (double)GetMouseWheelMove(); }

/* ═══════════════════════════════════════════
 *  Color Constants (packed RGBA)
 * ═══════════════════════════════════════════ */

int konpeito_color_white(void)      { return color_to_int(WHITE); }
int konpeito_color_black(void)      { return color_to_int(BLACK); }
int konpeito_color_red(void)        { return color_to_int(RED); }
int konpeito_color_green(void)      { return color_to_int(GREEN); }
int konpeito_color_blue(void)       { return color_to_int(BLUE); }
int konpeito_color_yellow(void)     { return color_to_int(YELLOW); }
int konpeito_color_orange(void)     { return color_to_int(ORANGE); }
int konpeito_color_pink(void)       { return color_to_int(PINK); }
int konpeito_color_purple(void)     { return color_to_int(PURPLE); }
int konpeito_color_darkgray(void)   { return color_to_int(DARKGRAY); }
int konpeito_color_lightgray(void)  { return color_to_int(LIGHTGRAY); }
int konpeito_color_gray(void)       { return color_to_int(GRAY); }
int konpeito_color_raywhite(void)   { return color_to_int(RAYWHITE); }
int konpeito_color_darkblue(void)   { return color_to_int(DARKBLUE); }
int konpeito_color_skyblue(void)    { return color_to_int(SKYBLUE); }
int konpeito_color_lime(void)       { return color_to_int(LIME); }
int konpeito_color_darkgreen(void)  { return color_to_int(DARKGREEN); }
int konpeito_color_darkpurple(void) { return color_to_int(DARKPURPLE); }
int konpeito_color_violet(void)     { return color_to_int(VIOLET); }
int konpeito_color_brown(void)      { return color_to_int(BROWN); }
int konpeito_color_darkbrown(void)  { return color_to_int(DARKBROWN); }
int konpeito_color_beige(void)      { return color_to_int(BEIGE); }
int konpeito_color_maroon(void)     { return color_to_int(MAROON); }
int konpeito_color_gold(void)       { return color_to_int(GOLD); }
int konpeito_color_magenta(void)    { return color_to_int(MAGENTA); }
int konpeito_color_blank(void)      { return color_to_int(BLANK); }

/* Custom color from RGBA components */
int konpeito_color_new(int r, int g, int b, int a) {
    return (r << 24) | (g << 16) | (b << 8) | a;
}

/* Color manipulation */
int konpeito_color_alpha(int color, double alpha) {
    return color_to_int(ColorAlpha(int_to_color(color), (float)alpha));
}

/* ═══════════════════════════════════════════
 *  Key Constants
 * ═══════════════════════════════════════════ */

int konpeito_key_right(void)  { return KEY_RIGHT; }
int konpeito_key_left(void)   { return KEY_LEFT; }
int konpeito_key_up(void)     { return KEY_UP; }
int konpeito_key_down(void)   { return KEY_DOWN; }
int konpeito_key_space(void)  { return KEY_SPACE; }
int konpeito_key_enter(void)  { return KEY_ENTER; }
int konpeito_key_escape(void) { return KEY_ESCAPE; }
int konpeito_key_a(void)      { return KEY_A; }
int konpeito_key_b(void)      { return KEY_B; }
int konpeito_key_c(void)      { return KEY_C; }
int konpeito_key_d(void)      { return KEY_D; }
int konpeito_key_e(void)      { return KEY_E; }
int konpeito_key_f(void)      { return KEY_F; }
int konpeito_key_g(void)      { return KEY_G; }
int konpeito_key_h(void)      { return KEY_H; }
int konpeito_key_i(void)      { return KEY_I; }
int konpeito_key_j(void)      { return KEY_J; }
int konpeito_key_k(void)      { return KEY_K; }
int konpeito_key_l(void)      { return KEY_L; }
int konpeito_key_m(void)      { return KEY_M; }
int konpeito_key_n(void)      { return KEY_N; }
int konpeito_key_o(void)      { return KEY_O; }
int konpeito_key_p(void)      { return KEY_P; }
int konpeito_key_q(void)      { return KEY_Q; }
int konpeito_key_r(void)      { return KEY_R; }
int konpeito_key_s(void)      { return KEY_S; }
int konpeito_key_t(void)      { return KEY_T; }
int konpeito_key_u(void)      { return KEY_U; }
int konpeito_key_v(void)      { return KEY_V; }
int konpeito_key_w(void)      { return KEY_W; }
int konpeito_key_x(void)      { return KEY_X; }
int konpeito_key_y(void)      { return KEY_Y; }
int konpeito_key_z(void)      { return KEY_Z; }
int konpeito_key_zero(void)   { return KEY_ZERO; }
int konpeito_key_one(void)    { return KEY_ONE; }
int konpeito_key_two(void)    { return KEY_TWO; }
int konpeito_key_three(void)  { return KEY_THREE; }
int konpeito_key_four(void)   { return KEY_FOUR; }
int konpeito_key_five(void)   { return KEY_FIVE; }
int konpeito_key_six(void)    { return KEY_SIX; }
int konpeito_key_seven(void)  { return KEY_SEVEN; }
int konpeito_key_eight(void)  { return KEY_EIGHT; }
int konpeito_key_nine(void)   { return KEY_NINE; }

/* Mouse button constants */
int konpeito_mouse_left(void)    { return MOUSE_BUTTON_LEFT; }
int konpeito_mouse_right(void)   { return MOUSE_BUTTON_RIGHT; }
int konpeito_mouse_middle(void)  { return MOUSE_BUTTON_MIDDLE; }

/* ═══════════════════════════════════════════
 *  Random
 * ═══════════════════════════════════════════ */

int konpeito_get_random_value(int min, int max) {
    return GetRandomValue(min, max);
}

/* Window flag constants */
int konpeito_flag_window_resizable(void) { return FLAG_WINDOW_RESIZABLE; }
int konpeito_flag_window_highdpi(void)   { return FLAG_WINDOW_HIGHDPI; }
int konpeito_flag_msaa_4x_hint(void)     { return FLAG_MSAA_4X_HINT; }
