/*
 * clay_native.c — Konpeito stdlib Clay UI bindings
 *
 * Thin C wrappers that solve the ABI mismatch between Clay's C macro/struct
 * API and Konpeito's @cfunc scalar parameter convention.
 *
 * Design: "auto-flush" pattern — configuration is accumulated in a global
 * Clay_ElementDeclaration, then committed (flushed) when the next child
 * element opens, text is added, or the element closes.
 *
 * Users never need to see this file. They just write Ruby code using the
 * Clay module defined in clay.rbs.
 */

#include "../../../../vendor/clay/clay.h"
#include <raylib.h>
#include <rlgl.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ── Include official Clay raylib renderer ── */
/* We include it directly so its static helpers are available. */
#include "../../../../vendor/clay/clay_renderer_raylib.c"

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

/* ═══════════════════════════════════════════
 *  GLFW forward declarations (linked via raylib)
 * ═══════════════════════════════════════════ */
typedef struct GLFWwindow GLFWwindow;
typedef void (*GLFWwindowrefreshfun)(GLFWwindow*);
typedef void (*GLFWframebuffersizefun)(GLFWwindow*, int, int);
extern GLFWwindow* glfwGetCurrentContext(void);
extern GLFWwindowrefreshfun glfwSetWindowRefreshCallback(GLFWwindow*, GLFWwindowrefreshfun);
extern GLFWframebuffersizefun glfwSetFramebufferSizeCallback(GLFWwindow*, GLFWframebuffersizefun);
extern void glfwGetFramebufferSize(GLFWwindow*, int*, int*);
extern void glfwSwapBuffers(GLFWwindow*);

/* ═══════════════════════════════════════════
 *  Global state
 * ═══════════════════════════════════════════ */

static Clay_Arena g_arena;
static Clay_Context *g_ctx = NULL;
static Clay_RenderCommandArray g_commands;
static Clay_ElementDeclaration g_decl;
static int g_needs_configure = 0;

/* Font storage for the raylib renderer */
#define MAX_FONTS 16
static Font g_fonts[MAX_FONTS];
static int g_font_count = 0;

/* Per-frame string pool — copies string data so Clay never holds pointers
 * to GC-managed mruby heap memory. Reset each frame in begin_layout. */
#define STRING_POOL_SIZE (64 * 1024)
static char g_string_pool[STRING_POOL_SIZE];
static int g_string_pool_pos = 0;

/* Background color for live resize re-render */
static unsigned char g_bg_r = 30, g_bg_g = 30, g_bg_b = 46;

/* Live resize state */
static int g_in_resize_callback = 0;

/* Live resize full-frame callback (calls back into mruby) */
typedef void (*clay_frame_fn)(void);
static clay_frame_fn g_resize_frame_fn = NULL;

/* ═══════════════════════════════════════════
 *  Helpers
 * ═══════════════════════════════════════════ */

/* Copy a string into the per-frame pool and return a stable pointer.
 * Falls back to the original pointer if the pool is exhausted. */
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

/* Create Clay_String from a runtime C string, copying data to the pool */
static Clay_String make_string(const char *s) {
    int len = (int32_t)strlen(s);
    const char *pooled = pool_string(s, len);
    return (Clay_String){ .isStaticallyAllocated = false, .length = len, .chars = pooled };
}

/* Auto-flush: commit pending config before adding children */
static void flush_config(void) {
    if (g_needs_configure) {
        Clay__ConfigureOpenElement(g_decl);
        g_needs_configure = 0;
    }
}

/* Build a Clay_SizingAxis from type enum + value */
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

/* Clay error handler — print to stderr */
static void clay_error_handler(Clay_ErrorData error) {
    fprintf(stderr, "[Clay] Error: %.*s\n",
            (int)error.errorText.length, error.errorText.chars);
}

/* Forward declarations for live resize callbacks */
static void live_resize_framebuffer_callback(GLFWwindow *window, int w, int h);
static void live_resize_refresh_callback(GLFWwindow *window);

/* ═══════════════════════════════════════════
 *  Lifecycle
 * ═══════════════════════════════════════════ */

void konpeito_clay_init(double w, double h) {
    uint32_t min_mem = Clay_MinMemorySize();
    g_arena = Clay_CreateArenaWithCapacityAndMemory(min_mem, malloc(min_mem));
    g_ctx = Clay_Initialize(g_arena, (Clay_Dimensions){(float)w, (float)h},
                            (Clay_ErrorHandler){ .errorHandlerFunction = clay_error_handler });

    /* Initialize default font (raylib's built-in font) */
    g_fonts[0] = GetFontDefault();
    g_font_count = 1;

#ifdef __APPLE__
    activate_macos_app();
#endif

    /* Register GLFW callbacks for live resize on macOS */
    GLFWwindow *glfw_win = glfwGetCurrentContext();
    if (glfw_win) {
        glfwSetFramebufferSizeCallback(glfw_win, live_resize_framebuffer_callback);
        glfwSetWindowRefreshCallback(glfw_win, live_resize_refresh_callback);
    }
}

void konpeito_clay_destroy(void) {
    if (g_arena.memory) {
        free(g_arena.memory);
        g_arena.memory = NULL;
    }
    g_ctx = NULL;
}

void konpeito_clay_begin_layout(void) {
    g_string_pool_pos = 0;  /* reset per-frame string pool */
    Clay_BeginLayout();
}

int konpeito_clay_end_layout(void) {
    g_commands = Clay_EndLayout();
    return g_commands.length;
}

void konpeito_clay_set_dimensions(double w, double h) {
    Clay_SetLayoutDimensions((Clay_Dimensions){(float)w, (float)h});
}

/* ═══════════════════════════════════════════
 *  Input
 * ═══════════════════════════════════════════ */

void konpeito_clay_set_pointer(double x, double y, int down) {
    Clay_SetPointerState((Clay_Vector2){(float)x, (float)y}, down != 0);
}

int konpeito_clay_pointer_over(const char *id) {
    Clay_ElementId eid = Clay_GetElementId(make_string(id));
    return Clay_PointerOver(eid) ? 1 : 0;
}

int konpeito_clay_pointer_over_i(const char *id, int index) {
    Clay_ElementId eid = Clay_GetElementIdWithIndex(make_string(id), (uint32_t)index);
    return Clay_PointerOver(eid) ? 1 : 0;
}

/* ═══════════════════════════════════════════
 *  Element Construction
 * ═══════════════════════════════════════════ */

void konpeito_clay_open(const char *id) {
    flush_config();  /* flush parent's pending config */

    Clay_ElementId eid = Clay__HashString(make_string(id), 0);
    Clay__OpenElementWithId(eid);

    /* Zero out the declaration for this new element */
    memset(&g_decl, 0, sizeof(g_decl));
    g_needs_configure = 1;
}

void konpeito_clay_open_i(const char *id, int index) {
    flush_config();

    Clay_ElementId eid = Clay__HashStringWithOffset(make_string(id), (uint32_t)index, 0);
    Clay__OpenElementWithId(eid);

    memset(&g_decl, 0, sizeof(g_decl));
    g_needs_configure = 1;
}

void konpeito_clay_close(void) {
    flush_config();  /* commit config if no children were added */
    Clay__CloseElement();
}

/*
 * Layout configuration.
 *
 * Parameters (all scalars for @cfunc compatibility):
 *   dir   — layout direction: 0=LEFT_TO_RIGHT, 1=TOP_TO_BOTTOM
 *   pl, pr, pt, pb — padding left, right, top, bottom
 *   gap   — child gap in pixels
 *   swt   — sizing width type: 0=FIT, 1=GROW, 2=FIXED, 3=PERCENT
 *   swv   — sizing width value (used for FIXED=pixels, PERCENT=0-1)
 *   sht   — sizing height type
 *   shv   — sizing height value
 *   ax    — child alignment X: 0=LEFT, 1=RIGHT, 2=CENTER
 *   ay    — child alignment Y: 0=TOP, 1=BOTTOM, 2=CENTER
 */
void konpeito_clay_layout(int dir, int pl, int pr, int pt, int pb,
                          int gap, int swt, double swv,
                          int sht, double shv, int ax, int ay) {
    g_decl.layout.layoutDirection = (Clay_LayoutDirection)dir;
    g_decl.layout.padding = (Clay_Padding){
        .left = (uint16_t)pl, .right = (uint16_t)pr,
        .top = (uint16_t)pt, .bottom = (uint16_t)pb
    };
    g_decl.layout.childGap = (uint16_t)gap;
    g_decl.layout.sizing.width = make_sizing(swt, swv);
    g_decl.layout.sizing.height = make_sizing(sht, shv);
    g_decl.layout.childAlignment = (Clay_ChildAlignment){
        .x = (Clay_LayoutAlignmentX)ax,
        .y = (Clay_LayoutAlignmentY)ay
    };
}

/* Background color + corner radius */
void konpeito_clay_bg(double r, double g, double b, double a, double cr) {
    g_decl.backgroundColor = (Clay_Color){(float)r, (float)g, (float)b, (float)a};
    if (cr > 0.0) {
        g_decl.cornerRadius = (Clay_CornerRadius){
            .topLeft = (float)cr, .topRight = (float)cr,
            .bottomLeft = (float)cr, .bottomRight = (float)cr
        };
    }
}

/* Border */
void konpeito_clay_border(double r, double g, double b, double a,
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

/* Scroll / clip */
void konpeito_clay_scroll(int horizontal, int vertical) {
    g_decl.clip.horizontal = horizontal != 0;
    g_decl.clip.vertical = vertical != 0;
    g_decl.clip.childOffset = Clay_GetScrollOffset();
}

/* Floating element */
void konpeito_clay_floating(double ox, double oy, int z,
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
 *  Text
 * ═══════════════════════════════════════════ */

void konpeito_clay_text(const char *text, int font_id, int font_size,
                        double r, double g, double b, double a, int wrap) {
    flush_config();

    Clay_TextElementConfig text_config = {
        .textColor = {(float)r, (float)g, (float)b, (float)a},
        .fontId = (uint16_t)font_id,
        .fontSize = (uint16_t)font_size,
        .wrapMode = (Clay_TextElementConfigWrapMode)wrap,
    };

    Clay__OpenTextElement(
        make_string(text),
        Clay__StoreTextElementConfig(text_config)
    );
}

/* ═══════════════════════════════════════════
 *  Text Measurement (raylib)
 * ═══════════════════════════════════════════ */

/* UTF-8 aware text measurement using raylib's MeasureTextEx */
static inline Clay_Dimensions Konpeito_MeasureText(Clay_StringSlice text,
                                                     Clay_TextElementConfig *config,
                                                     void *userData) {
    Font *fonts = (Font *)userData;
    Font fontToUse = fonts[config->fontId];
    if (!fontToUse.glyphs) fontToUse = GetFontDefault();
    char temp[4096];
    int len = text.length < 4095 ? (int)text.length : 4095;
    memcpy(temp, text.chars, len);
    temp[len] = '\0';
    Vector2 size = MeasureTextEx(fontToUse, temp, (float)config->fontSize, 0);
    return (Clay_Dimensions){ size.x, size.y };
}

void konpeito_clay_set_measure_text_raylib(void) {
    Clay_SetMeasureTextFunction(Konpeito_MeasureText, (void *)g_fonts);
}

/* ═══════════════════════════════════════════
 *  Font Management
 * ═══════════════════════════════════════════ */

int konpeito_clay_load_font(const char *path, int size) {
    if (g_font_count >= MAX_FONTS) return -1;
    int id = g_font_count;
    g_fonts[id] = LoadFontEx(path, size, NULL, 0);
    SetTextureFilter(g_fonts[id].texture, TEXTURE_FILTER_BILINEAR);
    g_font_count++;
    /* Re-register measure function with updated fonts array */
    Clay_SetMeasureTextFunction(Konpeito_MeasureText, (void *)g_fonts);
    return id;
}

int konpeito_clay_load_font_cjk(const char *path, int size) {
    if (g_font_count >= MAX_FONTS) return -1;
    int id = g_font_count;
    /* ASCII + CJK Symbols + Hiragana + Katakana + CJK Unified + Fullwidth */
    int count = 0;
    int *cps = (int *)malloc(22000 * sizeof(int));
    if (!cps) return -1;
    for (int c = 32; c <= 126; c++) cps[count++] = c;
    for (int c = 0x3000; c <= 0x303F; c++) cps[count++] = c;
    for (int c = 0x3040; c <= 0x309F; c++) cps[count++] = c;
    for (int c = 0x30A0; c <= 0x30FF; c++) cps[count++] = c;
    for (int c = 0x4E00; c <= 0x9FFF; c++) cps[count++] = c;
    for (int c = 0xFF00; c <= 0xFFEF; c++) cps[count++] = c;
    g_fonts[id] = LoadFontEx(path, size, cps, count);
    free(cps);
    SetTextureFilter(g_fonts[id].texture, TEXTURE_FILTER_BILINEAR);
    g_font_count++;
    Clay_SetMeasureTextFunction(Konpeito_MeasureText, (void *)g_fonts);
    return id;
}

/* ═══════════════════════════════════════════
 *  Render Command Access
 * ═══════════════════════════════════════════ */

static Clay_RenderCommand *get_cmd(int index) {
    return Clay_RenderCommandArray_Get(&g_commands, index);
}

int konpeito_clay_cmd_type(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    return cmd ? (int)cmd->commandType : 0;
}

double konpeito_clay_cmd_x(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    return cmd ? (double)cmd->boundingBox.x : 0.0;
}

double konpeito_clay_cmd_y(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    return cmd ? (double)cmd->boundingBox.y : 0.0;
}

double konpeito_clay_cmd_width(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    return cmd ? (double)cmd->boundingBox.width : 0.0;
}

double konpeito_clay_cmd_height(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    return cmd ? (double)cmd->boundingBox.height : 0.0;
}

double konpeito_clay_cmd_color_r(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd) return 0.0;
    switch (cmd->commandType) {
        case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
            return (double)cmd->renderData.rectangle.backgroundColor.r;
        case CLAY_RENDER_COMMAND_TYPE_TEXT:
            return (double)cmd->renderData.text.textColor.r;
        case CLAY_RENDER_COMMAND_TYPE_BORDER:
            return (double)cmd->renderData.border.color.r;
        default: return 0.0;
    }
}

double konpeito_clay_cmd_color_g(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd) return 0.0;
    switch (cmd->commandType) {
        case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
            return (double)cmd->renderData.rectangle.backgroundColor.g;
        case CLAY_RENDER_COMMAND_TYPE_TEXT:
            return (double)cmd->renderData.text.textColor.g;
        case CLAY_RENDER_COMMAND_TYPE_BORDER:
            return (double)cmd->renderData.border.color.g;
        default: return 0.0;
    }
}

double konpeito_clay_cmd_color_b(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd) return 0.0;
    switch (cmd->commandType) {
        case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
            return (double)cmd->renderData.rectangle.backgroundColor.b;
        case CLAY_RENDER_COMMAND_TYPE_TEXT:
            return (double)cmd->renderData.text.textColor.b;
        case CLAY_RENDER_COMMAND_TYPE_BORDER:
            return (double)cmd->renderData.border.color.b;
        default: return 0.0;
    }
}

double konpeito_clay_cmd_color_a(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd) return 0.0;
    switch (cmd->commandType) {
        case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
            return (double)cmd->renderData.rectangle.backgroundColor.a;
        case CLAY_RENDER_COMMAND_TYPE_TEXT:
            return (double)cmd->renderData.text.textColor.a;
        case CLAY_RENDER_COMMAND_TYPE_BORDER:
            return (double)cmd->renderData.border.color.a;
        default: return 0.0;
    }
}

/* Text-specific command accessors */
static char g_text_buf[4096];

const char *konpeito_clay_cmd_text(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd || cmd->commandType != CLAY_RENDER_COMMAND_TYPE_TEXT) return "";
    int len = cmd->renderData.text.stringContents.length;
    if (len > 4095) len = 4095;
    memcpy(g_text_buf, cmd->renderData.text.stringContents.chars, len);
    g_text_buf[len] = '\0';
    return g_text_buf;
}

int konpeito_clay_cmd_font_id(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd || cmd->commandType != CLAY_RENDER_COMMAND_TYPE_TEXT) return 0;
    return (int)cmd->renderData.text.fontId;
}

int konpeito_clay_cmd_font_size(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd || cmd->commandType != CLAY_RENDER_COMMAND_TYPE_TEXT) return 0;
    return (int)cmd->renderData.text.fontSize;
}

double konpeito_clay_cmd_corner_radius(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd) return 0.0;
    switch (cmd->commandType) {
        case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
            return (double)cmd->renderData.rectangle.cornerRadius.topLeft;
        case CLAY_RENDER_COMMAND_TYPE_BORDER:
            return (double)cmd->renderData.border.cornerRadius.topLeft;
        default: return 0.0;
    }
}

int konpeito_clay_cmd_border_width_top(int i) {
    Clay_RenderCommand *cmd = get_cmd(i);
    if (!cmd || cmd->commandType != CLAY_RENDER_COMMAND_TYPE_BORDER) return 0;
    return (int)cmd->renderData.border.width.top;
}

/* ═══════════════════════════════════════════
 *  Bulk Rendering (official raylib renderer)
 * ═══════════════════════════════════════════ */

void konpeito_clay_render_raylib(void) {
    Clay_Raylib_Render(g_commands, g_fonts);
}

/* Store background color for live resize re-render */
void konpeito_clay_set_bg_color(int r, int g, int b) {
    g_bg_r = (unsigned char)r;
    g_bg_g = (unsigned char)g;
    g_bg_b = (unsigned char)b;
}

int konpeito_clay_is_resizing(void) {
    return g_in_resize_callback;
}

/* ═══════════════════════════════════════════
 *  Live Resize (macOS GLFW callback)
 * ═══════════════════════════════════════════ */

static void live_resize_framebuffer_callback(GLFWwindow *window, int w, int h) {
    (void)window;
    g_in_resize_callback = 1;
    /* Update raylib's internal viewport */
    rlViewport(0, 0, w, h);
    /* Update Clay dimensions for next layout */
    Clay_SetLayoutDimensions((Clay_Dimensions){(float)w, (float)h});
}

static void live_resize_refresh_callback(GLFWwindow *window) {
    g_in_resize_callback = 1;
    int w, h;
    glfwGetFramebufferSize(window, &w, &h);
    rlViewport(0, 0, w, h);
    Clay_SetLayoutDimensions((Clay_Dimensions){(float)w, (float)h});

    if (g_resize_frame_fn) {
        /* Full relayout: call back into mruby to run draw + render */
        g_resize_frame_fn();
    } else {
        /* Fallback: re-render last frame's commands */
        rlClearColor(g_bg_r, g_bg_g, g_bg_b, 255);
        rlClearScreenBuffers();
        if (g_commands.length > 0) {
            Clay_Raylib_Render(g_commands, g_fonts);
        }
        rlDrawRenderBatchActive();
        glfwSwapBuffers(window);
    }
    g_in_resize_callback = 0;
}

void konpeito_clay_set_resize_frame_fn(clay_frame_fn fn) {
    g_resize_frame_fn = fn;
}

/* ═══════════════════════════════════════════
 *  Scroll
 * ═══════════════════════════════════════════ */

void konpeito_clay_update_scroll(double dx, double dy, double dt) {
    Clay_UpdateScrollContainers(true, (Clay_Vector2){(float)dx, (float)dy}, (float)dt);
}

/* ═══════════════════════════════════════════
 *  Constants (returned as integers)
 * ═══════════════════════════════════════════ */

int konpeito_clay_sizing_fit(void)    { return 0; }
int konpeito_clay_sizing_grow(void)   { return 1; }
int konpeito_clay_sizing_fixed(void)  { return 2; }
int konpeito_clay_sizing_percent(void){ return 3; }
int konpeito_clay_left_to_right(void) { return 0; }
int konpeito_clay_top_to_bottom(void) { return 1; }

/* ═══════════════════════════════════════════
 *  UTF-8 Helpers
 * ═══════════════════════════════════════════ */

static int utf8_char_len(unsigned char b) {
    if (b < 0x80) return 1;
    if ((b & 0xE0) == 0xC0) return 2;
    if ((b & 0xF0) == 0xE0) return 3;
    if ((b & 0xF8) == 0xF0) return 4;
    return 1;
}

static int utf8_prev_char_len(const char *buf, int pos) {
    if (pos <= 0) return 0;
    int back = 1;
    while (back < 4 && pos - back > 0 && ((unsigned char)buf[pos - back] & 0xC0) == 0x80) {
        back++;
    }
    return back;
}

static int utf8_encode(int cp, char *out) {
    if (cp < 0x80) {
        out[0] = (char)cp;
        return 1;
    } else if (cp < 0x800) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    } else if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    } else if (cp < 0x110000) {
        out[0] = (char)(0xF0 | (cp >> 18));
        out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[3] = (char)(0x80 | (cp & 0x3F));
        return 4;
    }
    return 0;
}

/* ═══════════════════════════════════════════
 *  Text Buffer System (UTF-8 aware)
 * ═══════════════════════════════════════════
 * 32 independent text buffers for text_input widgets.
 * Buffers store UTF-8 encoded text. Lengths and cursors are byte offsets.
 * Buffer operations are GC-free — no mruby String allocation.
 */

#define TEXTBUF_COUNT 32
#define TEXTBUF_SIZE 1024

static char g_textbufs[TEXTBUF_COUNT][TEXTBUF_SIZE];
static int g_textbuf_lens[TEXTBUF_COUNT];
static int g_textbuf_cursors[TEXTBUF_COUNT];

void konpeito_clay_textbuf_clear(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    g_textbufs[id][0] = '\0';
    g_textbuf_lens[id] = 0;
    g_textbuf_cursors[id] = 0;
}

void konpeito_clay_textbuf_copy(int dst, int src) {
    if (dst < 0 || dst >= TEXTBUF_COUNT) return;
    if (src < 0 || src >= TEXTBUF_COUNT) return;
    int len = g_textbuf_lens[src];
    for (int i = 0; i <= len; i++) {
        g_textbufs[dst][i] = g_textbufs[src][i];
    }
    g_textbuf_lens[dst] = len;
    g_textbuf_cursors[dst] = len;
}

void konpeito_clay_textbuf_putchar(int id, int ch) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    char encoded[4];
    int enc_len = utf8_encode(ch, encoded);
    if (enc_len == 0) return;
    int len = g_textbuf_lens[id];
    int cur = g_textbuf_cursors[id];
    if (len + enc_len >= TEXTBUF_SIZE) return;
    for (int i = len - 1; i >= cur; i--) {
        g_textbufs[id][i + enc_len] = g_textbufs[id][i];
    }
    for (int i = 0; i < enc_len; i++) {
        g_textbufs[id][cur + i] = encoded[i];
    }
    g_textbuf_lens[id] = len + enc_len;
    g_textbuf_cursors[id] = cur + enc_len;
    g_textbufs[id][len + enc_len] = '\0';
}

void konpeito_clay_textbuf_backspace(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int cur = g_textbuf_cursors[id];
    int len = g_textbuf_lens[id];
    if (cur <= 0) return;
    int clen = utf8_prev_char_len(g_textbufs[id], cur);
    for (int i = cur - clen; i < len - clen; i++) {
        g_textbufs[id][i] = g_textbufs[id][i + clen];
    }
    g_textbuf_lens[id] = len - clen;
    g_textbuf_cursors[id] = cur - clen;
    g_textbufs[id][len - clen] = '\0';
}

void konpeito_clay_textbuf_delete(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int cur = g_textbuf_cursors[id];
    int len = g_textbuf_lens[id];
    if (cur >= len) return;
    int clen = utf8_char_len((unsigned char)g_textbufs[id][cur]);
    for (int i = cur; i < len - clen; i++) {
        g_textbufs[id][i] = g_textbufs[id][i + clen];
    }
    g_textbuf_lens[id] = len - clen;
    g_textbufs[id][len - clen] = '\0';
}

void konpeito_clay_textbuf_cursor_left(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int cur = g_textbuf_cursors[id];
    if (cur <= 0) return;
    g_textbuf_cursors[id] = cur - utf8_prev_char_len(g_textbufs[id], cur);
}

void konpeito_clay_textbuf_cursor_right(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    int cur = g_textbuf_cursors[id];
    if (cur >= g_textbuf_lens[id]) return;
    g_textbuf_cursors[id] = cur + utf8_char_len((unsigned char)g_textbufs[id][cur]);
}

void konpeito_clay_textbuf_cursor_home(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    g_textbuf_cursors[id] = 0;
}

void konpeito_clay_textbuf_cursor_end(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    g_textbuf_cursors[id] = g_textbuf_lens[id];
}

int konpeito_clay_textbuf_len(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return 0;
    return g_textbuf_lens[id];
}

int konpeito_clay_textbuf_cursor(int id) {
    if (id < 0 || id >= TEXTBUF_COUNT) return 0;
    return g_textbuf_cursors[id];
}

void konpeito_clay_textbuf_render(int id, int fid, int fsz, double r, double g, double b) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    if (g_textbuf_lens[id] == 0) return;
    flush_config();
    Clay_TextElementConfig cfg = {
        .textColor = {(float)r, (float)g, (float)b, 255.0f},
        .fontId = (uint16_t)fid, .fontSize = (uint16_t)fsz, .wrapMode = 0
    };
    Clay_String cs = make_string(g_textbufs[id]);
    Clay__OpenTextElement(cs, Clay__StoreTextElementConfig(cfg));
}

void konpeito_clay_textbuf_render_range(int id, int start, int end, int fid, int fsz,
                                         double r, double g, double b) {
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
        .fontId = (uint16_t)fid, .fontSize = (uint16_t)fsz, .wrapMode = 0
    };
    Clay__OpenTextElement(cs, Clay__StoreTextElementConfig(cfg));
}

void konpeito_clay_text_char(int ch, int fid, int fsz, double r, double g, double b) {
    if (ch < 32) return;
    char buf[5];
    int len = utf8_encode(ch, buf);
    if (len == 0) return;
    buf[len] = '\0';
    flush_config();
    Clay_TextElementConfig cfg = {
        .textColor = {(float)r, (float)g, (float)b, 255.0f},
        .fontId = (uint16_t)fid, .fontSize = (uint16_t)fsz, .wrapMode = 0
    };
    Clay_String cs = make_string(buf);
    Clay__OpenTextElement(cs, Clay__StoreTextElementConfig(cfg));
}

int konpeito_clay_textbuf_get_char(int id, int pos) {
    if (id < 0 || id >= TEXTBUF_COUNT) return 0;
    if (pos < 0 || pos >= g_textbuf_lens[id]) return 0;
    return (int)(unsigned char)g_textbufs[id][pos];
}

void konpeito_clay_textbuf_set_str(int id, const char *str, int len) {
    if (id < 0 || id >= TEXTBUF_COUNT) return;
    if (len > TEXTBUF_SIZE - 1) len = TEXTBUF_SIZE - 1;
    for (int i = 0; i < len; i++) {
        g_textbufs[id][i] = str[i];
    }
    g_textbufs[id][len] = '\0';
    g_textbuf_lens[id] = len;
    g_textbuf_cursors[id] = len;
}
