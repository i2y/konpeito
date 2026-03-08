/*
 * raylib_wrapper.c - Thin C wrappers for raylib functions
 *
 * raylib passes Color structs by value, which Konpeito's @cfunc can't handle.
 * These wrappers take colors as packed 32-bit integers (RGBA) and convert them.
 *
 * Build: clang -c -I$(brew --prefix raylib)/include raylib_wrapper.c -o raylib_wrapper.o
 */

#include <raylib.h>

/* Convert packed RGBA integer to Color struct */
static Color int_to_color(int rgba) {
    Color c;
    c.r = (unsigned char)((rgba >> 24) & 0xFF);
    c.g = (unsigned char)((rgba >> 16) & 0xFF);
    c.b = (unsigned char)((rgba >> 8)  & 0xFF);
    c.a = (unsigned char)(rgba & 0xFF);
    return c;
}

/* Pre-defined color constants as packed RGBA integers */
int konpeito_raylib_color_white(void)     { return (int)0xFFFFFFFF; }
int konpeito_raylib_color_black(void)     { return (int)0x000000FF; }
int konpeito_raylib_color_red(void)       { return (int)0xFF0000FF; }
int konpeito_raylib_color_green(void)     { return (int)0x00FF00FF; }
int konpeito_raylib_color_blue(void)      { return (int)0x0000FFFF; }
int konpeito_raylib_color_yellow(void)    { return (int)0xFFF700FF; }
int konpeito_raylib_color_darkgray(void)  { return (int)0x505050FF; }
int konpeito_raylib_color_lightgray(void) { return (int)0xC8C8C8FF; }
int konpeito_raylib_color_raywhite(void)  { return (int)0xF5F5F5FF; }

/* Wrapped raylib functions that take Color as packed integer */

void konpeito_clear_background(int color) {
    ClearBackground(int_to_color(color));
}

void konpeito_draw_rectangle(int x, int y, int width, int height, int color) {
    DrawRectangle(x, y, width, height, int_to_color(color));
}

void konpeito_draw_circle(int cx, int cy, float radius, int color) {
    DrawCircle(cx, cy, radius, int_to_color(color));
}

void konpeito_draw_text(const char *text, int x, int y, int font_size, int color) {
    DrawText(text, x, y, font_size, int_to_color(color));
}

void konpeito_draw_line(int x1, int y1, int x2, int y2, int color) {
    DrawLine(x1, y1, x2, y2, int_to_color(color));
}
