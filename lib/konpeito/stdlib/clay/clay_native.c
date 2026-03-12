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

void konpeito_clay_set_measure_text_raylib(void) {
    Clay_SetMeasureTextFunction(Raylib_MeasureText, (void *)g_fonts);
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
    Clay_SetMeasureTextFunction(Raylib_MeasureText, (void *)g_fonts);
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
