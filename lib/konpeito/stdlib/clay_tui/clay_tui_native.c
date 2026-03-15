/*
 * clay_tui_native.c — Konpeito stdlib ClayTUI bindings
 *
 * Clay layout engine + termbox2 terminal renderer.
 * Based on clay_native.c, replacing raylib with termbox2.
 *
 * Design: "auto-flush" pattern — configuration is accumulated in a global
 * Clay_ElementDeclaration, then committed (flushed) when the next child
 * element opens, text is added, or the element closes.
 */

#define TB_OPT_ATTR_W 32
#include "../../../../vendor/clay/clay.h"
#include "../../../../vendor/termbox2/termbox2.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ── Include Clay termbox2 renderer ── */
#include "../../../../vendor/clay/clay_renderer_termbox2.c"

/* ═══════════════════════════════════════════
 *  Global state
 * ═══════════════════════════════════════════ */

static Clay_Arena g_arena;
static Clay_Context *g_ctx = NULL;
static Clay_RenderCommandArray g_commands;
static Clay_ElementDeclaration g_decl;
static int g_needs_configure = 0;

/* ═══════════════════════════════════════════
 *  Event storage
 * ═══════════════════════════════════════════ */

static struct tb_event g_last_event;
static int g_last_event_valid = 0;

/* Per-frame string pool — copies string data so Clay never holds pointers
 * to GC-managed mruby heap memory. Reset each frame in begin_layout. */
#define STRING_POOL_SIZE (64 * 1024)
static char g_string_pool[STRING_POOL_SIZE];
static int g_string_pool_pos = 0;

/* ═══════════════════════════════════════════
 *  Helpers
 * ═══════════════════════════════════════════ */

static const char *pool_string(const char *s, int len) {
    if (g_string_pool_pos + len + 1 > STRING_POOL_SIZE) {
        return s; /* pool full — fallback (rare) */
    }
    char *copy = g_string_pool + g_string_pool_pos;
    memcpy(copy, s, len);
    copy[len] = '\0';
    g_string_pool_pos += len + 1;
    return copy;
}

static Clay_String make_string(const char *s) {
    int len = (int32_t)strlen(s);
    const char *pooled = pool_string(s, len);
    return (Clay_String){ .isStaticallyAllocated = false, .length = len, .chars = pooled };
}

static void flush_config(void) {
    if (g_needs_configure) {
        Clay__ConfigureOpenElement(g_decl);
        g_needs_configure = 0;
    }
}

static Clay_SizingAxis make_sizing(int type, double val) {
    Clay_SizingAxis axis = {0};
    switch (type) {
        case 1:  /* GROW */
            axis.type = CLAY__SIZING_TYPE_GROW;
            break;
        case 2:  /* FIXED */
            axis.size.minMax.min = (float)val;
            axis.size.minMax.max = (float)val;
            axis.type = CLAY__SIZING_TYPE_FIXED;
            break;
        case 3:  /* PERCENT */
            axis.size.percent = (float)val;
            axis.type = CLAY__SIZING_TYPE_PERCENT;
            break;
        default: /* FIT (0) */
            axis.type = CLAY__SIZING_TYPE_FIT;
            break;
    }
    return axis;
}

static void clay_error_handler(Clay_ErrorData error) {
    fprintf(stderr, "[ClayTUI] Error: %.*s\n",
            (int)error.errorText.length, error.errorText.chars);
}

/* ═══════════════════════════════════════════
 *  Lifecycle
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_init(double w, double h) {
    tb_init();
    tb_set_output_mode(TB_OUTPUT_TRUECOLOR);
    tb_set_input_mode(TB_INPUT_ESC | TB_INPUT_MOUSE);

    uint32_t min_mem = Clay_MinMemorySize();
    g_arena = Clay_CreateArenaWithCapacityAndMemory(min_mem, malloc(min_mem));
    g_ctx = Clay_Initialize(g_arena, (Clay_Dimensions){(float)w, (float)h},
                            (Clay_ErrorHandler){ .errorHandlerFunction = clay_error_handler });
}

void konpeito_clay_tui_destroy(void) {
    if (g_arena.memory) {
        free(g_arena.memory);
        g_arena.memory = NULL;
    }
    g_ctx = NULL;
    tb_shutdown();
}

void konpeito_clay_tui_begin_layout(void) {
    g_string_pool_pos = 0;  /* reset per-frame string pool */
    Clay_BeginLayout();
}

int konpeito_clay_tui_end_layout(void) {
    g_commands = Clay_EndLayout();
    return g_commands.length;
}

void konpeito_clay_tui_set_dimensions(double w, double h) {
    Clay_SetLayoutDimensions((Clay_Dimensions){(float)w, (float)h});
}

void konpeito_clay_tui_set_measure_text(void) {
    Clay_SetMeasureTextFunction(Termbox_MeasureText, NULL);
}

/* ═══════════════════════════════════════════
 *  Element Construction
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_open(const char *id) {
    flush_config();
    Clay_ElementId eid = Clay__HashString(make_string(id), 0);
    Clay__OpenElementWithId(eid);
    memset(&g_decl, 0, sizeof(g_decl));
    g_needs_configure = 1;
}

void konpeito_clay_tui_open_i(const char *id, int index) {
    flush_config();
    Clay_ElementId eid = Clay__HashStringWithOffset(make_string(id), (uint32_t)index, 0);
    Clay__OpenElementWithId(eid);
    memset(&g_decl, 0, sizeof(g_decl));
    g_needs_configure = 1;
}

void konpeito_clay_tui_close(void) {
    flush_config();
    Clay__CloseElement();
}

/* ═══════════════════════════════════════════
 *  Layout Direction
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_hbox(void) {
    g_decl.layout.layoutDirection = CLAY_LEFT_TO_RIGHT;
}

void konpeito_clay_tui_vbox(void) {
    g_decl.layout.layoutDirection = CLAY_TOP_TO_BOTTOM;
}

/* ═══════════════════════════════════════════
 *  Padding & Gap
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_pad(int l, int r, int t, int b) {
    g_decl.layout.padding = (Clay_Padding){
        .left = (uint16_t)l, .right = (uint16_t)r,
        .top = (uint16_t)t, .bottom = (uint16_t)b
    };
}

void konpeito_clay_tui_gap(int gap) {
    g_decl.layout.childGap = (uint16_t)gap;
}

/* ═══════════════════════════════════════════
 *  Sizing (Width)
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_width_fit(void) {
    g_decl.layout.sizing.width = make_sizing(0, 0);
}

void konpeito_clay_tui_width_grow(void) {
    g_decl.layout.sizing.width = make_sizing(1, 0);
}

void konpeito_clay_tui_width_fixed(double v) {
    g_decl.layout.sizing.width = make_sizing(2, v);
}

void konpeito_clay_tui_width_percent(double v) {
    g_decl.layout.sizing.width = make_sizing(3, v);
}

/* ═══════════════════════════════════════════
 *  Sizing (Height)
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_height_fit(void) {
    g_decl.layout.sizing.height = make_sizing(0, 0);
}

void konpeito_clay_tui_height_grow(void) {
    g_decl.layout.sizing.height = make_sizing(1, 0);
}

void konpeito_clay_tui_height_fixed(double v) {
    g_decl.layout.sizing.height = make_sizing(2, v);
}

void konpeito_clay_tui_height_percent(double v) {
    g_decl.layout.sizing.height = make_sizing(3, v);
}

/* ═══════════════════════════════════════════
 *  Alignment
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_align(int ax, int ay) {
    g_decl.layout.childAlignment = (Clay_ChildAlignment){
        .x = (Clay_LayoutAlignmentX)ax, .y = (Clay_LayoutAlignmentY)ay
    };
}

/* ═══════════════════════════════════════════
 *  Decoration
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_bg(int r, int g, int b) {
    g_decl.backgroundColor = (Clay_Color){(float)r, (float)g, (float)b, 255.0f};
}

void konpeito_clay_tui_bg_ex(int r, int g, int b, int a, double cr) {
    g_decl.backgroundColor = (Clay_Color){(float)r, (float)g, (float)b, (float)a};
    if (cr > 0.0) {
        g_decl.cornerRadius = (Clay_CornerRadius){
            .topLeft = (float)cr, .topRight = (float)cr,
            .bottomLeft = (float)cr, .bottomRight = (float)cr
        };
    }
}

void konpeito_clay_tui_border(double r, double g, double b, double a,
                               int top, int right, int bottom, int left,
                               double cr) {
    g_decl.border.color = (Clay_Color){(float)r, (float)g, (float)b, (float)a};
    g_decl.border.width = (Clay_BorderWidth){
        .left = (uint16_t)left, .right = (uint16_t)right,
        .top = (uint16_t)top, .bottom = (uint16_t)bottom
    };
    if (cr > 0.0) {
        g_decl.cornerRadius = (Clay_CornerRadius){
            .topLeft = (float)cr, .topRight = (float)cr,
            .bottomLeft = (float)cr, .bottomRight = (float)cr
        };
    }
}

/* ═══════════════════════════════════════════
 *  Text
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_text(const char *str, int r, int g, int b) {
    flush_config();
    Clay_TextElementConfig cfg = {
        .textColor = {(float)r, (float)g, (float)b, 255.0f},
        .fontId = 0, .fontSize = 1, .wrapMode = 0
    };
    Clay__OpenTextElement(make_string(str), Clay__StoreTextElementConfig(cfg));
}

void konpeito_clay_tui_text_ex(const char *str, int fid, int fsz,
                                int r, int g, int b, int a, int wrap) {
    flush_config();
    Clay_TextElementConfig cfg = {
        .textColor = {(float)r, (float)g, (float)b, (float)a},
        .fontId = (uint16_t)fid, .fontSize = (uint16_t)fsz,
        .wrapMode = (Clay_TextElementConfigWrapMode)wrap
    };
    Clay__OpenTextElement(make_string(str), Clay__StoreTextElementConfig(cfg));
}

/* ═══════════════════════════════════════════
 *  Scroll & Floating
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_scroll(int horizontal, int vertical) {
    g_decl.clip.horizontal = horizontal != 0;
    g_decl.clip.vertical = vertical != 0;
    g_decl.clip.childOffset = Clay_GetScrollOffset();
}

void konpeito_clay_tui_floating(double ox, double oy, int z,
                                 int att_elem, int att_parent) {
    g_decl.floating.offset = (Clay_Vector2){(float)ox, (float)oy};
    g_decl.floating.zIndex = (int16_t)z;
    g_decl.floating.attachPoints = (Clay_FloatingAttachPoints){
        .element = (Clay_FloatingAttachPointType)att_elem,
        .parent = (Clay_FloatingAttachPointType)att_parent
    };
    g_decl.floating.attachTo = CLAY_ATTACH_TO_PARENT;
}

/* ═══════════════════════════════════════════
 *  Pointer Input (Mouse)
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_set_pointer(double x, double y, int down) {
    Clay_SetPointerState((Clay_Vector2){(float)x, (float)y}, down != 0);
}

int konpeito_clay_tui_pointer_over(const char *id) {
    Clay_ElementId eid = Clay_GetElementId(make_string(id));
    return Clay_PointerOver(eid) ? 1 : 0;
}

int konpeito_clay_tui_pointer_over_i(const char *id, int index) {
    Clay_ElementId eid = Clay_GetElementIdWithIndex(make_string(id), (uint32_t)index);
    return Clay_PointerOver(eid) ? 1 : 0;
}

void konpeito_clay_tui_update_scroll(double dx, double dy, double dt) {
    Clay_UpdateScrollContainers(true, (Clay_Vector2){(float)dx, (float)dy}, (float)dt);
}

/* ═══════════════════════════════════════════
 *  Rendering
 * ═══════════════════════════════════════════ */

void konpeito_clay_tui_render(void) {
    tb_clear();
    Clay_Termbox_Render(g_commands);
    tb_present();
}

/* ═══════════════════════════════════════════
 *  Events
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_peek_event(int timeout_ms) {
    int result = tb_peek_event(&g_last_event, timeout_ms);
    g_last_event_valid = (result == TB_OK) ? 1 : 0;
    return g_last_event_valid ? (int)g_last_event.type : 0;
}

int konpeito_clay_tui_poll_event(void) {
    int result = tb_poll_event(&g_last_event);
    g_last_event_valid = (result == TB_OK) ? 1 : 0;
    return g_last_event_valid ? (int)g_last_event.type : 0;
}

int konpeito_clay_tui_event_type(void) {
    return g_last_event_valid ? (int)g_last_event.type : 0;
}

int konpeito_clay_tui_event_key(void) {
    return g_last_event_valid ? (int)g_last_event.key : 0;
}

int konpeito_clay_tui_event_ch(void) {
    return g_last_event_valid ? (int)g_last_event.ch : 0;
}

int konpeito_clay_tui_event_mouse_x(void) {
    return g_last_event_valid ? (int)g_last_event.x : 0;
}

int konpeito_clay_tui_event_mouse_y(void) {
    return g_last_event_valid ? (int)g_last_event.y : 0;
}

int konpeito_clay_tui_event_w(void) {
    return g_last_event_valid ? (int)g_last_event.w : 0;
}

int konpeito_clay_tui_event_h(void) {
    return g_last_event_valid ? (int)g_last_event.h : 0;
}

/* ═══════════════════════════════════════════
 *  Terminal Info
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_term_width(void) {
    return tb_width();
}

int konpeito_clay_tui_term_height(void) {
    return tb_height();
}

/* ═══════════════════════════════════════════
 *  Key Constants
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_key_esc(void)         { return TB_KEY_ESC; }
int konpeito_clay_tui_key_enter(void)       { return TB_KEY_ENTER; }
int konpeito_clay_tui_key_tab(void)         { return TB_KEY_TAB; }
int konpeito_clay_tui_key_backspace(void)   { return TB_KEY_BACKSPACE2; }
int konpeito_clay_tui_key_arrow_up(void)    { return TB_KEY_ARROW_UP; }
int konpeito_clay_tui_key_arrow_down(void)  { return TB_KEY_ARROW_DOWN; }
int konpeito_clay_tui_key_arrow_left(void)  { return TB_KEY_ARROW_LEFT; }
int konpeito_clay_tui_key_arrow_right(void) { return TB_KEY_ARROW_RIGHT; }
int konpeito_clay_tui_key_space(void)       { return TB_KEY_SPACE; }

/* ═══════════════════════════════════════════
 *  Color Constants (basic 8)
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_color_default(void) { return (int)TB_DEFAULT; }
int konpeito_clay_tui_color_black(void)   { return (int)TB_BLACK; }
int konpeito_clay_tui_color_red(void)     { return (int)TB_RED; }
int konpeito_clay_tui_color_green(void)   { return (int)TB_GREEN; }
int konpeito_clay_tui_color_yellow(void)  { return (int)TB_YELLOW; }
int konpeito_clay_tui_color_blue(void)    { return (int)TB_BLUE; }
int konpeito_clay_tui_color_magenta(void) { return (int)TB_MAGENTA; }
int konpeito_clay_tui_color_cyan(void)    { return (int)TB_CYAN; }
int konpeito_clay_tui_color_white(void)   { return (int)TB_WHITE; }

/* ═══════════════════════════════════════════
 *  Attribute Constants
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_attr_bold(void)      { return (int)TB_BOLD; }
int konpeito_clay_tui_attr_underline(void) { return (int)TB_UNDERLINE; }
int konpeito_clay_tui_attr_reverse(void)   { return (int)TB_REVERSE; }

/* ═══════════════════════════════════════════
 *  Color Helper
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_rgb(int r, int g, int b) {
    return (r << 16) | (g << 8) | b;
}

/* ═══════════════════════════════════════════
 *  Extended Key Constants
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_key_delete(void)    { return TB_KEY_DELETE; }
int konpeito_clay_tui_key_home(void)      { return TB_KEY_HOME; }
int konpeito_clay_tui_key_end(void)       { return TB_KEY_END; }
int konpeito_clay_tui_key_pgup(void)      { return TB_KEY_PGUP; }
int konpeito_clay_tui_key_pgdn(void)      { return TB_KEY_PGDN; }
int konpeito_clay_tui_key_f1(void)        { return TB_KEY_F1; }
int konpeito_clay_tui_key_f2(void)        { return TB_KEY_F2; }
int konpeito_clay_tui_key_f3(void)        { return TB_KEY_F3; }
int konpeito_clay_tui_key_f4(void)        { return TB_KEY_F4; }
int konpeito_clay_tui_key_f5(void)        { return TB_KEY_F5; }
int konpeito_clay_tui_key_f6(void)        { return TB_KEY_F6; }
int konpeito_clay_tui_key_f7(void)        { return TB_KEY_F7; }
int konpeito_clay_tui_key_f8(void)        { return TB_KEY_F8; }
int konpeito_clay_tui_key_f9(void)        { return TB_KEY_F9; }
int konpeito_clay_tui_key_f10(void)       { return TB_KEY_F10; }
int konpeito_clay_tui_key_f11(void)       { return TB_KEY_F11; }
int konpeito_clay_tui_key_f12(void)       { return TB_KEY_F12; }

/* ═══════════════════════════════════════════
 *  Modifier Keys
 * ═══════════════════════════════════════════ */

int konpeito_clay_tui_event_mod(void) {
    return g_last_event_valid ? (int)g_last_event.mod : 0;
}

int konpeito_clay_tui_mod_alt(void)   { return TB_MOD_ALT; }
int konpeito_clay_tui_mod_ctrl(void)  { return TB_MOD_CTRL; }
int konpeito_clay_tui_mod_shift(void) { return TB_MOD_SHIFT; }

/* ═══════════════════════════════════════════
 *  Text Buffer System
 * ═══════════════════════════════════════════
 * 8 independent text buffers for text_input widgets.
 * Each buffer holds up to 255 characters (256 bytes including null).
 * Buffer operations are GC-free — no mruby String allocation.
 */

#define TEXTBUF_COUNT 32
#define TEXTBUF_SIZE 256

static char g_textbufs[TEXTBUF_COUNT][TEXTBUF_SIZE];
static int g_textbuf_lens[TEXTBUF_COUNT];
static int g_textbuf_cursors[TEXTBUF_COUNT];

void konpeito_clay_tui_textbuf_clear(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    g_textbufs[id][0] = '\0';
    g_textbuf_lens[id] = 0;
    g_textbuf_cursors[id] = 0;
}

void konpeito_clay_tui_textbuf_copy(int dst, int src) {
    if (dst < 0 || dst >= TEXTBUF_COUNT) return;
    if (src < 0 || src >= TEXTBUF_COUNT) return;
    int len = g_textbuf_lens[src];
    for (int i = 0; i <= len; i++) {
        g_textbufs[dst][i] = g_textbufs[src][i];
    }
    g_textbuf_lens[dst] = len;
    g_textbuf_cursors[dst] = len;
}

void konpeito_clay_tui_textbuf_putchar(int id, int ch) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int len = g_textbuf_lens[id];
    int cur = g_textbuf_cursors[id];
    if (len >= TEXTBUF_SIZE - 1) return;
    /* Shift chars right from cursor position */
    for (int i = len; i > cur; i--) {
        g_textbufs[id][i] = g_textbufs[id][i - 1];
    }
    g_textbufs[id][cur] = (char)ch;
    g_textbuf_lens[id] = len + 1;
    g_textbuf_cursors[id] = cur + 1;
    g_textbufs[id][len + 1] = '\0';
}

void konpeito_clay_tui_textbuf_backspace(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int cur = g_textbuf_cursors[id];
    int len = g_textbuf_lens[id];
    if (cur <= 0) return;
    for (int i = cur - 1; i < len - 1; i++) {
        g_textbufs[id][i] = g_textbufs[id][i + 1];
    }
    g_textbuf_lens[id] = len - 1;
    g_textbuf_cursors[id] = cur - 1;
    g_textbufs[id][len - 1] = '\0';
}

void konpeito_clay_tui_textbuf_delete(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int cur = g_textbuf_cursors[id];
    int len = g_textbuf_lens[id];
    if (cur >= len) return;
    for (int i = cur; i < len - 1; i++) {
        g_textbufs[id][i] = g_textbufs[id][i + 1];
    }
    g_textbuf_lens[id] = len - 1;
    g_textbufs[id][len - 1] = '\0';
}

void konpeito_clay_tui_textbuf_cursor_left(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    if (g_textbuf_cursors[id] > 0) g_textbuf_cursors[id]--;
}

void konpeito_clay_tui_textbuf_cursor_right(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    if (g_textbuf_cursors[id] < g_textbuf_lens[id]) g_textbuf_cursors[id]++;
}

void konpeito_clay_tui_textbuf_cursor_home(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    g_textbuf_cursors[id] = 0;
}

void konpeito_clay_tui_textbuf_cursor_end(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    g_textbuf_cursors[id] = g_textbuf_lens[id];
}

int konpeito_clay_tui_textbuf_len(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return 0;
    return g_textbuf_lens[id];
}

int konpeito_clay_tui_textbuf_cursor(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return 0;
    return g_textbuf_cursors[id];
}

/* Render entire text buffer as Clay text element (GC-free) */
void konpeito_clay_tui_textbuf_render(int id, int r, int g, int b) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    if (g_textbuf_lens[id] == 0) return;
    flush_config();
    Clay_TextElementConfig cfg = {
        .textColor = {(float)r, (float)g, (float)b, 255.0f},
        .fontId = 0, .fontSize = 1, .wrapMode = 0
    };
    Clay_String cs = make_string(g_textbufs[id]);
    Clay__OpenTextElement(cs, Clay__StoreTextElementConfig(cfg));
}

/* Render a range of the text buffer (start inclusive, end exclusive) */
void konpeito_clay_tui_textbuf_render_range(int id, int start, int end, int r, int g, int b) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int len = g_textbuf_lens[id];
    if (start >= len || start >= end) return;
    if (end > len) end = len;
    int range_len = end - start;
    flush_config();
    const char *pooled = pool_string(g_textbufs[id] + start, range_len);
    Clay_String cs = {.isStaticallyAllocated = false, .length = range_len, .chars = pooled};
    Clay_TextElementConfig cfg = {
        .textColor = {(float)r, (float)g, (float)b, 255.0f},
        .fontId = 0, .fontSize = 1, .wrapMode = 0
    };
    Clay__OpenTextElement(cs, Clay__StoreTextElementConfig(cfg));
}

/* Render a single character by code as Clay text (GC-free) */
void konpeito_clay_tui_text_char(int ch, int r, int g, int b) {
    if (ch < 32 || ch > 126) return;
    char buf[2];
    buf[0] = (char)ch;
    buf[1] = '\0';
    flush_config();
    Clay_TextElementConfig cfg = {
        .textColor = {(float)r, (float)g, (float)b, 255.0f},
        .fontId = 0, .fontSize = 1, .wrapMode = 0
    };
    Clay_String cs = make_string(buf);
    Clay__OpenTextElement(cs, Clay__StoreTextElementConfig(cfg));
}

int konpeito_clay_tui_textbuf_get_char(int id, int pos) {
    if (id < 0 || id >= TEXTBUF_COUNT) return 0;
    if (pos < 0 || pos >= g_textbuf_lens[id]) return 0;
    return (int)(unsigned char)g_textbufs[id][pos];
}

void konpeito_clay_tui_textbuf_set_str(int id, const char *str, int len) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    if (len > TEXTBUF_SIZE - 1) len = TEXTBUF_SIZE - 1;
    for (int i = 0; i < len; i++) {
        g_textbufs[id][i] = str[i];
    }
    g_textbufs[id][len] = '\0';
    g_textbuf_lens[id] = len;
    g_textbuf_cursors[id] = len;
}

/* ── Stubs for GUI-only features (linked from mruby_helpers.c) ── */

typedef void (*clay_frame_fn)(void);
void konpeito_clay_set_resize_frame_fn(clay_frame_fn fn) { (void)fn; }
void konpeito_clay_set_bg_color(int r, int g, int b) { (void)r; (void)g; (void)b; }
int  konpeito_clay_is_resizing(void) { return 0; }

