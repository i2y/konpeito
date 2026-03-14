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
#include <stdlib.h>

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
int  konpeito_get_render_width(void)    { return GetRenderWidth(); }
int  konpeito_get_render_height(void)   { return GetRenderHeight(); }
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

/* Extended key constants */
int konpeito_key_tab(void)           { return KEY_TAB; }
int konpeito_key_backspace(void)     { return KEY_BACKSPACE; }
int konpeito_key_delete(void)        { return KEY_DELETE; }
int konpeito_key_home(void)          { return KEY_HOME; }
int konpeito_key_end(void)           { return KEY_END; }
int konpeito_key_page_up(void)       { return KEY_PAGE_UP; }
int konpeito_key_page_down(void)     { return KEY_PAGE_DOWN; }
int konpeito_key_f1(void)            { return KEY_F1; }
int konpeito_key_f2(void)            { return KEY_F2; }
int konpeito_key_f3(void)            { return KEY_F3; }
int konpeito_key_f4(void)            { return KEY_F4; }
int konpeito_key_f5(void)            { return KEY_F5; }
int konpeito_key_f6(void)            { return KEY_F6; }
int konpeito_key_f7(void)            { return KEY_F7; }
int konpeito_key_f8(void)            { return KEY_F8; }
int konpeito_key_f9(void)            { return KEY_F9; }
int konpeito_key_f10(void)           { return KEY_F10; }
int konpeito_key_f11(void)           { return KEY_F11; }
int konpeito_key_f12(void)           { return KEY_F12; }
int konpeito_key_left_shift(void)    { return KEY_LEFT_SHIFT; }
int konpeito_key_right_shift(void)   { return KEY_RIGHT_SHIFT; }
int konpeito_key_left_control(void)  { return KEY_LEFT_CONTROL; }
int konpeito_key_right_control(void) { return KEY_RIGHT_CONTROL; }
int konpeito_key_left_alt(void)      { return KEY_LEFT_ALT; }
int konpeito_key_right_alt(void)     { return KEY_RIGHT_ALT; }

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

/* ═══════════════════════════════════════════
 *  Texture Management (ID-based table)
 * ═══════════════════════════════════════════ */

#define MAX_TEXTURES 256

static Texture2D g_textures[MAX_TEXTURES];
static int       g_texture_used[MAX_TEXTURES];
static int       g_textures_initialized = 0;

static void ensure_textures_init(void) {
    if (g_textures_initialized) return;
    memset(g_texture_used, 0, sizeof(g_texture_used));
    g_textures_initialized = 1;
}

static int alloc_texture_slot(void) {
    ensure_textures_init();
    for (int i = 0; i < MAX_TEXTURES; i++) {
        if (!g_texture_used[i]) {
            g_texture_used[i] = 1;
            return i;
        }
    }
    return -1;
}

int konpeito_load_texture(const char *path) {
    int slot = alloc_texture_slot();
    if (slot < 0) return -1;
    g_textures[slot] = LoadTexture(path);
    if (g_textures[slot].id == 0) {
        g_texture_used[slot] = 0;
        return -1;
    }
    return slot;
}

void konpeito_unload_texture(int id) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return;
    UnloadTexture(g_textures[id]);
    g_texture_used[id] = 0;
}

void konpeito_draw_texture(int id, int x, int y, int tint) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return;
    DrawTexture(g_textures[id], x, y, int_to_color(tint));
}

void konpeito_draw_texture_rec(int id, double sx, double sy, double sw, double sh,
                                int dx, int dy, int tint) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return;
    Rectangle source = { (float)sx, (float)sy, (float)sw, (float)sh };
    Vector2 pos = { (float)dx, (float)dy };
    DrawTextureRec(g_textures[id], source, pos, int_to_color(tint));
}

void konpeito_draw_texture_pro(int id,
                                double sx, double sy, double sw, double sh,
                                double dx, double dy, double dw, double dh,
                                double ox, double oy, double rotation, int tint) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return;
    Rectangle source = { (float)sx, (float)sy, (float)sw, (float)sh };
    Rectangle dest   = { (float)dx, (float)dy, (float)dw, (float)dh };
    Vector2 origin   = { (float)ox, (float)oy };
    DrawTexturePro(g_textures[id], source, dest, origin, (float)rotation, int_to_color(tint));
}

int konpeito_get_texture_width(int id) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return 0;
    return g_textures[id].width;
}

int konpeito_get_texture_height(int id) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return 0;
    return g_textures[id].height;
}

int konpeito_is_texture_valid(int id) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return 0;
    return (int)IsTextureValid(g_textures[id]);
}

void konpeito_draw_texture_scaled(int id, int x, int y, double scale, int tint) {
    if (id < 0 || id >= MAX_TEXTURES || !g_texture_used[id]) return;
    DrawTextureEx(g_textures[id], (Vector2){(float)x, (float)y},
                  0.0f, (float)scale, int_to_color(tint));
}

/* ═══════════════════════════════════════════
 *  Audio Management (ID-based tables)
 * ═══════════════════════════════════════════ */

#define MAX_SOUNDS 128
#define MAX_MUSIC  32

static Sound  g_sounds[MAX_SOUNDS];
static int    g_sound_used[MAX_SOUNDS];
static int    g_sounds_initialized = 0;

static Music  g_music[MAX_MUSIC];
static int    g_music_used[MAX_MUSIC];
static int    g_music_initialized = 0;

static void ensure_sounds_init(void) {
    if (g_sounds_initialized) return;
    memset(g_sound_used, 0, sizeof(g_sound_used));
    g_sounds_initialized = 1;
}

static void ensure_music_init(void) {
    if (g_music_initialized) return;
    memset(g_music_used, 0, sizeof(g_music_used));
    g_music_initialized = 1;
}

/* Audio device */
void konpeito_init_audio_device(void)  { InitAudioDevice(); }
void konpeito_close_audio_device(void) { CloseAudioDevice(); }
int  konpeito_is_audio_device_ready(void) { return (int)IsAudioDeviceReady(); }
void konpeito_set_master_volume(double vol) { SetMasterVolume((float)vol); }
double konpeito_get_master_volume(void) { return (double)GetMasterVolume(); }

/* Sound */
int konpeito_load_sound(const char *path) {
    ensure_sounds_init();
    for (int i = 0; i < MAX_SOUNDS; i++) {
        if (!g_sound_used[i]) {
            g_sounds[i] = LoadSound(path);
            if (g_sounds[i].frameCount == 0) return -1;
            g_sound_used[i] = 1;
            return i;
        }
    }
    return -1;
}

void konpeito_unload_sound(int id) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return;
    UnloadSound(g_sounds[id]);
    g_sound_used[id] = 0;
}

void konpeito_play_sound(int id) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return;
    PlaySound(g_sounds[id]);
}

void konpeito_stop_sound(int id) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return;
    StopSound(g_sounds[id]);
}

void konpeito_pause_sound(int id) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return;
    PauseSound(g_sounds[id]);
}

void konpeito_resume_sound(int id) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return;
    ResumeSound(g_sounds[id]);
}

int konpeito_is_sound_playing(int id) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return 0;
    return (int)IsSoundPlaying(g_sounds[id]);
}

void konpeito_set_sound_volume(int id, double vol) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return;
    SetSoundVolume(g_sounds[id], (float)vol);
}

void konpeito_set_sound_pitch(int id, double pitch) {
    if (id < 0 || id >= MAX_SOUNDS || !g_sound_used[id]) return;
    SetSoundPitch(g_sounds[id], (float)pitch);
}

/* Music stream */
int konpeito_load_music(const char *path) {
    ensure_music_init();
    for (int i = 0; i < MAX_MUSIC; i++) {
        if (!g_music_used[i]) {
            g_music[i] = LoadMusicStream(path);
            if (g_music[i].frameCount == 0) return -1;
            g_music_used[i] = 1;
            return i;
        }
    }
    return -1;
}

void konpeito_unload_music(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    UnloadMusicStream(g_music[id]);
    g_music_used[id] = 0;
}

void konpeito_play_music(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    PlayMusicStream(g_music[id]);
}

void konpeito_stop_music(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    StopMusicStream(g_music[id]);
}

void konpeito_pause_music(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    PauseMusicStream(g_music[id]);
}

void konpeito_resume_music(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    ResumeMusicStream(g_music[id]);
}

void konpeito_update_music(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    UpdateMusicStream(g_music[id]);
}

int konpeito_is_music_playing(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return 0;
    return (int)IsMusicStreamPlaying(g_music[id]);
}

void konpeito_set_music_volume(int id, double vol) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    SetMusicVolume(g_music[id], (float)vol);
}

void konpeito_set_music_pitch(int id, double pitch) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    SetMusicPitch(g_music[id], (float)pitch);
}

double konpeito_get_music_time_length(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return 0.0;
    return (double)GetMusicTimeLength(g_music[id]);
}

double konpeito_get_music_time_played(int id) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return 0.0;
    return (double)GetMusicTimePlayed(g_music[id]);
}

void konpeito_seek_music(int id, double position) {
    if (id < 0 || id >= MAX_MUSIC || !g_music_used[id]) return;
    SeekMusicStream(g_music[id], (float)position);
}

/* ═══════════════════════════════════════════
 *  Camera2D
 * ═══════════════════════════════════════════ */

void konpeito_begin_mode_2d(double offset_x, double offset_y,
                             double target_x, double target_y,
                             double rotation, double zoom) {
    Camera2D cam = {0};
    cam.offset   = (Vector2){ (float)offset_x, (float)offset_y };
    cam.target   = (Vector2){ (float)target_x, (float)target_y };
    cam.rotation = (float)rotation;
    cam.zoom     = (float)zoom;
    BeginMode2D(cam);
}

void konpeito_end_mode_2d(void) {
    EndMode2D();
}

/* World ↔ screen coordinate conversion */
int konpeito_get_world_to_screen_2d_x(double world_x, double world_y,
                                       double offset_x, double offset_y,
                                       double target_x, double target_y,
                                       double rotation, double zoom) {
    Camera2D cam = {0};
    cam.offset   = (Vector2){ (float)offset_x, (float)offset_y };
    cam.target   = (Vector2){ (float)target_x, (float)target_y };
    cam.rotation = (float)rotation;
    cam.zoom     = (float)zoom;
    Vector2 result = GetWorldToScreen2D((Vector2){(float)world_x, (float)world_y}, cam);
    return (int)result.x;
}

int konpeito_get_world_to_screen_2d_y(double world_x, double world_y,
                                       double offset_x, double offset_y,
                                       double target_x, double target_y,
                                       double rotation, double zoom) {
    Camera2D cam = {0};
    cam.offset   = (Vector2){ (float)offset_x, (float)offset_y };
    cam.target   = (Vector2){ (float)target_x, (float)target_y };
    cam.rotation = (float)rotation;
    cam.zoom     = (float)zoom;
    Vector2 result = GetWorldToScreen2D((Vector2){(float)world_x, (float)world_y}, cam);
    return (int)result.y;
}

/* ═══════════════════════════════════════════
 *  File I/O (Save / Load)
 * ═══════════════════════════════════════════ */

int konpeito_save_file_text(const char *path, const char *text) {
    return (int)SaveFileText(path, (char *)text);
}

const char *konpeito_load_file_text(const char *path) {
    return LoadFileText(path);
}

int konpeito_file_exists(const char *path) {
    return (int)FileExists(path);
}

int konpeito_directory_exists(const char *path) {
    return (int)DirectoryExists(path);
}

/* ═══════════════════════════════════════════
 *  Font Management (ID-based table)
 * ═══════════════════════════════════════════ */

#define MAX_FONTS 32

static Font g_raylib_fonts[MAX_FONTS];
static int  g_raylib_font_used[MAX_FONTS];
static int  g_raylib_fonts_initialized = 0;

static void ensure_fonts_init(void) {
    if (g_raylib_fonts_initialized) return;
    memset(g_raylib_font_used, 0, sizeof(g_raylib_font_used));
    g_raylib_fonts_initialized = 1;
}

int konpeito_load_font(const char *path) {
    ensure_fonts_init();
    for (int i = 0; i < MAX_FONTS; i++) {
        if (!g_raylib_font_used[i]) {
            g_raylib_fonts[i] = LoadFont(path);
            if (g_raylib_fonts[i].baseSize == 0) return -1;
            g_raylib_font_used[i] = 1;
            return i;
        }
    }
    return -1;
}

int konpeito_load_font_ex(const char *path, int size) {
    ensure_fonts_init();
    for (int i = 0; i < MAX_FONTS; i++) {
        if (!g_raylib_font_used[i]) {
            g_raylib_fonts[i] = LoadFontEx(path, size, NULL, 0);
            if (g_raylib_fonts[i].baseSize == 0) return -1;
            g_raylib_font_used[i] = 1;
            return i;
        }
    }
    return -1;
}

void konpeito_unload_font(int id) {
    if (id < 0 || id >= MAX_FONTS || !g_raylib_font_used[id]) return;
    UnloadFont(g_raylib_fonts[id]);
    g_raylib_font_used[id] = 0;
}

void konpeito_draw_text_ex(int font_id, const char *text,
                            double x, double y, double size,
                            double spacing, int tint) {
    Font font;
    if (font_id < 0 || font_id >= MAX_FONTS || !g_raylib_font_used[font_id]) {
        font = GetFontDefault();
    } else {
        font = g_raylib_fonts[font_id];
    }
    DrawTextEx(font, text, (Vector2){(float)x, (float)y},
               (float)size, (float)spacing, int_to_color(tint));
}

int konpeito_measure_text_ex_x(int font_id, const char *text,
                                double size, double spacing) {
    Font font;
    if (font_id < 0 || font_id >= MAX_FONTS || !g_raylib_font_used[font_id]) {
        font = GetFontDefault();
    } else {
        font = g_raylib_fonts[font_id];
    }
    Vector2 v = MeasureTextEx(font, text, (float)size, (float)spacing);
    return (int)v.x;
}

int konpeito_measure_text_ex_y(int font_id, const char *text,
                                double size, double spacing) {
    Font font;
    if (font_id < 0 || font_id >= MAX_FONTS || !g_raylib_font_used[font_id]) {
        font = GetFontDefault();
    } else {
        font = g_raylib_fonts[font_id];
    }
    Vector2 v = MeasureTextEx(font, text, (float)size, (float)spacing);
    return (int)v.y;
}

/* ═══════════════════════════════════════════
 *  Gamepad Input
 * ═══════════════════════════════════════════ */

int konpeito_is_gamepad_available(int gamepad)          { return (int)IsGamepadAvailable(gamepad); }
int konpeito_is_gamepad_button_pressed(int gp, int btn) { return (int)IsGamepadButtonPressed(gp, btn); }
int konpeito_is_gamepad_button_down(int gp, int btn)    { return (int)IsGamepadButtonDown(gp, btn); }
int konpeito_is_gamepad_button_released(int gp, int btn){ return (int)IsGamepadButtonReleased(gp, btn); }
int konpeito_is_gamepad_button_up(int gp, int btn)      { return (int)IsGamepadButtonUp(gp, btn); }
double konpeito_get_gamepad_axis_movement(int gp, int axis) {
    return (double)GetGamepadAxisMovement(gp, axis);
}
int konpeito_get_gamepad_axis_count(int gp) { return GetGamepadAxisCount(gp); }

/* Gamepad button constants */
int konpeito_gamepad_button_left_face_up(void)    { return GAMEPAD_BUTTON_LEFT_FACE_UP; }
int konpeito_gamepad_button_left_face_right(void) { return GAMEPAD_BUTTON_LEFT_FACE_RIGHT; }
int konpeito_gamepad_button_left_face_down(void)  { return GAMEPAD_BUTTON_LEFT_FACE_DOWN; }
int konpeito_gamepad_button_left_face_left(void)  { return GAMEPAD_BUTTON_LEFT_FACE_LEFT; }
int konpeito_gamepad_button_right_face_up(void)   { return GAMEPAD_BUTTON_RIGHT_FACE_UP; }
int konpeito_gamepad_button_right_face_right(void){ return GAMEPAD_BUTTON_RIGHT_FACE_RIGHT; }
int konpeito_gamepad_button_right_face_down(void) { return GAMEPAD_BUTTON_RIGHT_FACE_DOWN; }
int konpeito_gamepad_button_right_face_left(void) { return GAMEPAD_BUTTON_RIGHT_FACE_LEFT; }
int konpeito_gamepad_button_left_trigger_1(void)  { return GAMEPAD_BUTTON_LEFT_TRIGGER_1; }
int konpeito_gamepad_button_left_trigger_2(void)  { return GAMEPAD_BUTTON_LEFT_TRIGGER_2; }
int konpeito_gamepad_button_right_trigger_1(void) { return GAMEPAD_BUTTON_RIGHT_TRIGGER_1; }
int konpeito_gamepad_button_right_trigger_2(void) { return GAMEPAD_BUTTON_RIGHT_TRIGGER_2; }
int konpeito_gamepad_button_middle_left(void)     { return GAMEPAD_BUTTON_MIDDLE_LEFT; }
int konpeito_gamepad_button_middle(void)          { return GAMEPAD_BUTTON_MIDDLE; }
int konpeito_gamepad_button_middle_right(void)    { return GAMEPAD_BUTTON_MIDDLE_RIGHT; }

/* Gamepad axis constants */
int konpeito_gamepad_axis_left_x(void)       { return GAMEPAD_AXIS_LEFT_X; }
int konpeito_gamepad_axis_left_y(void)       { return GAMEPAD_AXIS_LEFT_Y; }
int konpeito_gamepad_axis_right_x(void)      { return GAMEPAD_AXIS_RIGHT_X; }
int konpeito_gamepad_axis_right_y(void)      { return GAMEPAD_AXIS_RIGHT_Y; }
int konpeito_gamepad_axis_left_trigger(void) { return GAMEPAD_AXIS_LEFT_TRIGGER; }
int konpeito_gamepad_axis_right_trigger(void){ return GAMEPAD_AXIS_RIGHT_TRIGGER; }

/* ═══════════════════════════════════════════
 *  Drawing — Extended Shapes
 * ═══════════════════════════════════════════ */

void konpeito_draw_rectangle_pro(double x, double y, double w, double h,
                                  double ox, double oy, double rotation, int color) {
    DrawRectanglePro((Rectangle){(float)x, (float)y, (float)w, (float)h},
                     (Vector2){(float)ox, (float)oy}, (float)rotation, int_to_color(color));
}

void konpeito_draw_rectangle_rounded(double x, double y, double w, double h,
                                      double roundness, int segments, int color) {
    DrawRectangleRounded((Rectangle){(float)x, (float)y, (float)w, (float)h},
                         (float)roundness, segments, int_to_color(color));
}

void konpeito_draw_rectangle_gradient_v(int x, int y, int w, int h, int color1, int color2) {
    DrawRectangleGradientV(x, y, w, h, int_to_color(color1), int_to_color(color2));
}

void konpeito_draw_rectangle_gradient_h(int x, int y, int w, int h, int color1, int color2) {
    DrawRectangleGradientH(x, y, w, h, int_to_color(color1), int_to_color(color2));
}

void konpeito_draw_circle_sector(int cx, int cy, double radius,
                                  double start_angle, double end_angle,
                                  int segments, int color) {
    DrawCircleSector((Vector2){(float)cx, (float)cy}, (float)radius,
                     (float)start_angle, (float)end_angle, segments, int_to_color(color));
}

/* ═══════════════════════════════════════════
 *  Collision Detection Helpers
 * ═══════════════════════════════════════════ */

int konpeito_check_collision_recs(double x1, double y1, double w1, double h1,
                                   double x2, double y2, double w2, double h2) {
    Rectangle r1 = { (float)x1, (float)y1, (float)w1, (float)h1 };
    Rectangle r2 = { (float)x2, (float)y2, (float)w2, (float)h2 };
    return (int)CheckCollisionRecs(r1, r2);
}

int konpeito_check_collision_circles(double cx1, double cy1, double r1,
                                      double cx2, double cy2, double r2) {
    return (int)CheckCollisionCircles((Vector2){(float)cx1, (float)cy1}, (float)r1,
                                      (Vector2){(float)cx2, (float)cy2}, (float)r2);
}

int konpeito_check_collision_circle_rec(double cx, double cy, double radius,
                                         double rx, double ry, double rw, double rh) {
    return (int)CheckCollisionCircleRec((Vector2){(float)cx, (float)cy}, (float)radius,
                                        (Rectangle){(float)rx, (float)ry, (float)rw, (float)rh});
}

int konpeito_check_collision_point_rec(double px, double py,
                                        double rx, double ry, double rw, double rh) {
    return (int)CheckCollisionPointRec((Vector2){(float)px, (float)py},
                                       (Rectangle){(float)rx, (float)ry, (float)rw, (float)rh});
}

int konpeito_check_collision_point_circle(double px, double py,
                                           double cx, double cy, double radius) {
    return (int)CheckCollisionPointCircle((Vector2){(float)px, (float)py},
                                          (Vector2){(float)cx, (float)cy}, (float)radius);
}
