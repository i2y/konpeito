/*
 * Konpeito UI Native - SDL3 + Skia CRuby Extension
 *
 * Provides window management, event polling, and 2D drawing
 * for the Castella UI framework on the LLVM backend.
 *
 * Architecture:
 *   Ruby (NativeFrame) -> CRuby C API -> SDL3 (window/events) + Skia (drawing)
 *
 * Event model: Polling (not callbacks) -- avoids C->Ruby callback requirement.
 *   SDL3 events are polled into a ring buffer; Ruby reads them one at a time.
 */

#include "konpeito_ui_native.h"

#include <SDL3/SDL.h>

#include <include/core/SkCanvas.h>
#include <include/core/SkSurface.h>
#include <include/core/SkPaint.h>
#include <include/core/SkPath.h>
#include <include/core/SkFont.h>
#include <include/core/SkFontMgr.h>
#include <include/core/SkTypeface.h>
#include <include/core/SkImage.h>
#include <include/core/SkData.h>
#include <include/core/SkColorSpace.h>
#include <include/core/SkRRect.h>
#include <include/core/SkFontStyle.h>
#include <include/core/SkFontMetrics.h>
#include <include/core/SkTextBlob.h>
#include <include/core/SkStream.h>
#include <include/core/SkBitmap.h>
#include <include/codec/SkCodec.h>
#include <include/ports/SkFontMgr_directory.h>

/* Windows: GetWindowsDirectoryA for font path */
#ifdef _WIN32
#include <windows.h>
#endif

/* GPU backend headers (Metal on macOS, GL on Linux/Windows) */
#ifdef __APPLE__
#include <include/gpu/GrDirectContext.h>
#include <include/gpu/GrBackendSurface.h>
#include <include/gpu/ganesh/mtl/GrMtlDirectContext.h>
#include <include/gpu/ganesh/mtl/GrMtlBackendContext.h>
#include <include/gpu/ganesh/mtl/GrMtlTypes.h>
#include <include/gpu/ganesh/SkSurfaceGanesh.h>
#include <SDL3/SDL_metal.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#else
#include <include/gpu/GrDirectContext.h>
#include <include/gpu/GrBackendSurface.h>
#include <include/gpu/ganesh/gl/GrGLDirectContext.h>
#include <include/gpu/ganesh/gl/GrGLInterface.h>
#include <include/gpu/ganesh/SkSurfaceGanesh.h>
#include <SDL3/SDL_opengl.h>
#endif

#include <cmath>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <unordered_map>
#include <string>
#include <chrono>

/* ---------- SDL3 scancode -> JWM key ordinal mapping ---------- */

static int sdl_scancode_to_jwm_ordinal(SDL_Scancode sc) {
    switch (sc) {
        /* Function keys */
        case SDL_SCANCODE_CAPSLOCK:    return 0;
        case SDL_SCANCODE_F1:         return 1;
        case SDL_SCANCODE_F2:         return 2;
        case SDL_SCANCODE_F3:         return 3;
        case SDL_SCANCODE_F4:         return 4;
        case SDL_SCANCODE_F5:         return 5;
        case SDL_SCANCODE_F6:         return 6;
        case SDL_SCANCODE_F7:         return 7;
        case SDL_SCANCODE_F8:         return 8;
        case SDL_SCANCODE_F9:         return 9;
        case SDL_SCANCODE_F10:        return 10;
        case SDL_SCANCODE_RETURN:     return 11;  /* ENTER */
        case SDL_SCANCODE_BACKSPACE:  return 12;
        case SDL_SCANCODE_TAB:        return 13;
        case SDL_SCANCODE_SPACE:      return 14;
        case SDL_SCANCODE_PRINTSCREEN: return 15;
        case SDL_SCANCODE_SCROLLLOCK: return 16;
        case SDL_SCANCODE_ESCAPE:     return 17;
        case SDL_SCANCODE_INSERT:     return 20;
        case SDL_SCANCODE_END:        return 21;
        case SDL_SCANCODE_HOME:       return 22;
        case SDL_SCANCODE_LEFT:       return 23;
        case SDL_SCANCODE_UP:         return 24;
        case SDL_SCANCODE_RIGHT:      return 25;
        case SDL_SCANCODE_DOWN:       return 26;
        case SDL_SCANCODE_PAGEUP:     return 27;
        case SDL_SCANCODE_PAGEDOWN:   return 28;

        /* Punctuation (ordinals 29-34) */
        case SDL_SCANCODE_COMMA:      return 29;
        case SDL_SCANCODE_PERIOD:     return 30;
        case SDL_SCANCODE_SLASH:      return 31;
        case SDL_SCANCODE_LEFTBRACKET: return 32;
        case SDL_SCANCODE_RIGHTBRACKET: return 33;
        case SDL_SCANCODE_BACKSLASH:  return 34;

        /* Digits (ordinals 35-44) -> 0-9 */
        case SDL_SCANCODE_0:          return 35;
        case SDL_SCANCODE_1:          return 36;
        case SDL_SCANCODE_2:          return 37;
        case SDL_SCANCODE_3:          return 38;
        case SDL_SCANCODE_4:          return 39;
        case SDL_SCANCODE_5:          return 40;
        case SDL_SCANCODE_6:          return 41;
        case SDL_SCANCODE_7:          return 42;

        /* Letter keys A-Z (ordinals 43-68) */
        case SDL_SCANCODE_A:          return 43;
        case SDL_SCANCODE_B:          return 44;
        case SDL_SCANCODE_C:          return 45;
        case SDL_SCANCODE_D:          return 46;
        case SDL_SCANCODE_E:          return 47;
        case SDL_SCANCODE_F:          return 48;
        case SDL_SCANCODE_G:          return 49;
        case SDL_SCANCODE_H:          return 50;
        case SDL_SCANCODE_I:          return 51;
        case SDL_SCANCODE_J:          return 52;
        case SDL_SCANCODE_K:          return 53;
        case SDL_SCANCODE_L:          return 54;
        case SDL_SCANCODE_M:          return 55;
        case SDL_SCANCODE_N:          return 56;
        case SDL_SCANCODE_O:          return 57;
        case SDL_SCANCODE_P:          return 58;
        case SDL_SCANCODE_Q:          return 59;
        case SDL_SCANCODE_R:          return 60;
        case SDL_SCANCODE_S:          return 61;
        case SDL_SCANCODE_T:          return 62;
        case SDL_SCANCODE_U:          return 63;
        case SDL_SCANCODE_V:          return 64;
        case SDL_SCANCODE_W:          return 65;
        case SDL_SCANCODE_X:          return 66;
        case SDL_SCANCODE_Y:          return 67;
        case SDL_SCANCODE_Z:          return 68;

        case SDL_SCANCODE_DELETE:     return 75;

        default:                      return -1;  /* Unknown */
    }
}

/* ---------- SDL3 modifier conversion ---------- */

static int sdl_mod_to_jwm_mod(SDL_Keymod mod) {
    int result = 0;
    if (mod & SDL_KMOD_SHIFT) result |= KUI_MOD_SHIFT;
    if (mod & SDL_KMOD_CTRL)  result |= KUI_MOD_CONTROL;
    if (mod & SDL_KMOD_ALT)   result |= KUI_MOD_ALT;
    if (mod & SDL_KMOD_GUI)   result |= KUI_MOD_SUPER;
    return result;
}

/* ---------- KUIContext structure ---------- */

struct KUIContext {
    /* SDL */
    SDL_Window* window;
    int width, height;
    float scale;
    bool dirty;
    bool frame_requested;
    bool text_input_enabled;

    /* Skia GPU context */
#ifdef __APPLE__
    SDL_MetalView metal_view;
    sk_sp<GrDirectContext> gr_context;
    id<MTLDevice> mtl_device;
    id<MTLCommandQueue> mtl_queue;
    CAMetalLayer* metal_layer;
    id<CAMetalDrawable> current_drawable;  /* Retained between begin/end frame */
#else
    SDL_GLContext gl_context;
    sk_sp<GrDirectContext> gr_context;
#endif

    /* Skia drawing state */
    sk_sp<SkSurface> surface;
    SkCanvas* canvas;
    SkPath current_path;

    /* Font manager */
    sk_sp<SkFontMgr> font_mgr;

    /* Image cache */
    std::unordered_map<int, sk_sp<SkImage>> images;
    int next_image_id;

    /* Event ring buffer */
    KUIEvent events[KUI_EVENT_BUFFER_SIZE];
    int event_read;
    int event_write;
    int event_count;

    /* Clipboard cache (to return stable pointer) */
    std::string clipboard_cache;

    /* Number-to-string cache */
    char num_str_buf[64];
};

/* ---------- Event ring buffer helpers ---------- */

static void push_event(KUIContext* ctx, const KUIEvent& ev) {
    if (ctx->event_count >= KUI_EVENT_BUFFER_SIZE) return; /* drop if full */
    ctx->events[ctx->event_write] = ev;
    ctx->event_write = (ctx->event_write + 1) % KUI_EVENT_BUFFER_SIZE;
    ctx->event_count++;
}

static KUIEvent* peek_event(KUIContext* ctx) {
    if (ctx->event_count == 0) return nullptr;
    return &ctx->events[ctx->event_read];
}

/* ---------- Color helpers ---------- */

static SkColor uint32_to_skcolor(uint32_t c) {
    /* Konpeito/JWM colors are 0xAARRGGBB (same as SkColor) */
    return (SkColor)c;
}

static uint8_t clamp_u8(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

/* ---------- Font helper ---------- */

static sk_sp<SkTypeface> find_typeface(KUIContext* ctx, const char* family,
                                        int weight, int slant) {
    SkFontStyle style(
        weight == 1 ? SkFontStyle::kBold_Weight : SkFontStyle::kNormal_Weight,
        SkFontStyle::kNormal_Width,
        slant == 1 ? SkFontStyle::kItalic_Slant : SkFontStyle::kUpright_Slant
    );
    sk_sp<SkTypeface> tf = ctx->font_mgr->matchFamilyStyle(family, style);
    if (!tf) {
        /* Fallback to default */
        tf = ctx->font_mgr->matchFamilyStyle(nullptr, style);
    }
    if (!tf) {
        /* Last resort: try sans-serif */
        tf = ctx->font_mgr->matchFamilyStyle("Helvetica", style);
    }
    return tf;
}

/* ============================================================
 * C API Implementation
 * ============================================================ */

extern "C" {

/* --- Window management --- */

KUIContext* kui_create_window(const char* title, int width, int height) {
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return nullptr;
    }

    KUIContext* ctx = new KUIContext();
    memset(ctx->events, 0, sizeof(ctx->events));
    ctx->event_read = 0;
    ctx->event_write = 0;
    ctx->event_count = 0;
    ctx->dirty = true;
    ctx->frame_requested = true;
    ctx->text_input_enabled = false;
    ctx->next_image_id = 1;
    ctx->canvas = nullptr;
    ctx->scale = 1.0f;

#ifdef __APPLE__
    /* Metal backend on macOS */
    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
    ctx->window = SDL_CreateWindow(title, width, height,
                                    SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_METAL);
    if (!ctx->window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        delete ctx;
        return nullptr;
    }

    ctx->metal_view = SDL_Metal_CreateView(ctx->window);
    ctx->metal_layer = (__bridge CAMetalLayer*)SDL_Metal_GetLayer(ctx->metal_view);

    ctx->mtl_device = MTLCreateSystemDefaultDevice();
    ctx->metal_layer.device = ctx->mtl_device;
    ctx->metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    ctx->metal_layer.framebufferOnly = NO;
    ctx->current_drawable = nil;

    ctx->mtl_queue = [ctx->mtl_device newCommandQueue];

    GrMtlBackendContext backend_ctx = {};
    backend_ctx.fDevice.retain((__bridge void*)ctx->mtl_device);
    backend_ctx.fQueue.retain((__bridge void*)ctx->mtl_queue);

    ctx->gr_context = GrDirectContexts::MakeMetal(backend_ctx);
    if (!ctx->gr_context) {
        fprintf(stderr, "Failed to create Skia Metal context\n");
        SDL_DestroyWindow(ctx->window);
        delete ctx;
        return nullptr;
    }
#else
    /* OpenGL backend on Linux/Windows */
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);

    ctx->window = SDL_CreateWindow(title, width, height,
                                    SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_OPENGL);
    if (!ctx->window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        delete ctx;
        return nullptr;
    }

    ctx->gl_context = SDL_GL_CreateContext(ctx->window);
    SDL_GL_MakeCurrent(ctx->window, ctx->gl_context);

    auto gl_interface = GrGLMakeNativeInterface();
    ctx->gr_context = GrDirectContexts::MakeGL(gl_interface);
    if (!ctx->gr_context) {
        fprintf(stderr, "Failed to create Skia GL context\n");
        SDL_DestroyWindow(ctx->window);
        delete ctx;
        return nullptr;
    }
#endif

    /* Get actual pixel size (for HiDPI) */
    int pw, ph;
    SDL_GetWindowSizeInPixels(ctx->window, &pw, &ph);
    ctx->width = width;
    ctx->height = height;
    ctx->scale = (float)pw / (float)width;

    /* Font manager: scan system fonts directory (FreeType-based) */
#ifdef __APPLE__
    ctx->font_mgr = SkFontMgr_New_Custom_Directory("/System/Library/Fonts");
#elif defined(_WIN32)
    {
        char windir[MAX_PATH];
        GetWindowsDirectoryA(windir, MAX_PATH);
        std::string font_path = std::string(windir) + "\\Fonts";
        ctx->font_mgr = SkFontMgr_New_Custom_Directory(font_path.c_str());
    }
#else
    ctx->font_mgr = SkFontMgr_New_Custom_Directory("/usr/share/fonts");
#endif

    if (!ctx->font_mgr) {
        /* Fallback */
        ctx->font_mgr = SkFontMgr::RefEmpty();
    }

    return ctx;
}

void kui_destroy_window(KUIContext* ctx) {
    if (!ctx) return;

    ctx->images.clear();
    ctx->surface.reset();
    ctx->canvas = nullptr;

#ifdef __APPLE__
    ctx->current_drawable = nil;
#endif

    ctx->gr_context.reset();

#ifdef __APPLE__
    if (ctx->metal_view) {
        SDL_Metal_DestroyView(ctx->metal_view);
    }
#else
    if (ctx->gl_context) {
        SDL_GL_DestroyContext(ctx->gl_context);
    }
#endif

    if (ctx->window) {
        SDL_DestroyWindow(ctx->window);
    }

    SDL_Quit();
    delete ctx;
}

void kui_step(KUIContext* ctx) {
    if (!ctx) return;

    SDL_Event sdl_ev;
    while (SDL_PollEvent(&sdl_ev)) {
        KUIEvent ev;
        memset(&ev, 0, sizeof(ev));

        switch (sdl_ev.type) {
            case SDL_EVENT_QUIT:
                ev.type = KUI_EVENT_QUIT;
                push_event(ctx, ev);
                break;

            case SDL_EVENT_MOUSE_BUTTON_DOWN:
                ev.type = KUI_EVENT_MOUSE_DOWN;
                ev.x = sdl_ev.button.x;
                ev.y = sdl_ev.button.y;
                ev.button = sdl_ev.button.button - 1; /* SDL: 1-based -> 0-based */
                push_event(ctx, ev);
                break;

            case SDL_EVENT_MOUSE_BUTTON_UP:
                ev.type = KUI_EVENT_MOUSE_UP;
                ev.x = sdl_ev.button.x;
                ev.y = sdl_ev.button.y;
                ev.button = sdl_ev.button.button - 1;
                push_event(ctx, ev);
                break;

            case SDL_EVENT_MOUSE_MOTION:
                ev.type = KUI_EVENT_MOUSE_MOVE;
                ev.x = sdl_ev.motion.x;
                ev.y = sdl_ev.motion.y;
                push_event(ctx, ev);
                break;

            case SDL_EVENT_MOUSE_WHEEL:
                ev.type = KUI_EVENT_MOUSE_WHEEL;
                ev.dx = sdl_ev.wheel.x;
                ev.dy = sdl_ev.wheel.y;
                /* Get current mouse position for wheel events */
                {
                    float mx, my;
                    SDL_GetMouseState(&mx, &my);
                    ev.x = mx;
                    ev.y = my;
                }
                push_event(ctx, ev);
                break;

            case SDL_EVENT_KEY_DOWN:
            case SDL_EVENT_KEY_UP: {
                ev.type = (sdl_ev.type == SDL_EVENT_KEY_DOWN) ? KUI_EVENT_KEY_DOWN : KUI_EVENT_KEY_UP;
                ev.key_code = sdl_scancode_to_jwm_ordinal(sdl_ev.key.scancode);
                ev.modifiers = sdl_mod_to_jwm_mod(sdl_ev.key.mod);
                if (ev.key_code >= 0) {
                    push_event(ctx, ev);
                }
                break;
            }

            case SDL_EVENT_TEXT_INPUT:
                ev.type = KUI_EVENT_TEXT_INPUT;
                strncpy(ev.text, sdl_ev.text.text, sizeof(ev.text) - 1);
                ev.text[sizeof(ev.text) - 1] = '\0';
                push_event(ctx, ev);
                break;

            case SDL_EVENT_TEXT_EDITING:
                ev.type = KUI_EVENT_IME_PREEDIT;
                strncpy(ev.text, sdl_ev.edit.text, sizeof(ev.text) - 1);
                ev.text[sizeof(ev.text) - 1] = '\0';
                ev.ime_sel_start = sdl_ev.edit.start;
                ev.ime_sel_end = sdl_ev.edit.start + sdl_ev.edit.length;
                push_event(ctx, ev);
                break;

            case SDL_EVENT_WINDOW_RESIZED:
            case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: {
                ev.type = KUI_EVENT_RESIZE;
                int w, h;
                SDL_GetWindowSize(ctx->window, &w, &h);
                ctx->width = w;
                ctx->height = h;
                int pw, ph;
                SDL_GetWindowSizeInPixels(ctx->window, &pw, &ph);
                ctx->scale = (float)pw / (float)w;
                ctx->dirty = true;
                push_event(ctx, ev);
                break;
            }

            default:
                break;
        }
    }
}

/* --- Event access --- */

bool kui_has_event(KUIContext* ctx) {
    return ctx && ctx->event_count > 0;
}

int kui_event_type(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->type : KUI_EVENT_NONE;
}

double kui_event_x(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->x : 0.0;
}

double kui_event_y(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->y : 0.0;
}

double kui_event_dx(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->dx : 0.0;
}

double kui_event_dy(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->dy : 0.0;
}

int kui_event_button(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->button : 0;
}

int kui_event_key_code(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->key_code : -1;
}

int kui_event_modifiers(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->modifiers : 0;
}

const char* kui_event_text(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->text : "";
}

int kui_event_ime_sel_start(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->ime_sel_start : 0;
}

int kui_event_ime_sel_end(KUIContext* ctx) {
    KUIEvent* ev = peek_event(ctx);
    return ev ? ev->ime_sel_end : 0;
}

void kui_consume_event(KUIContext* ctx) {
    if (!ctx || ctx->event_count == 0) return;
    ctx->event_read = (ctx->event_read + 1) % KUI_EVENT_BUFFER_SIZE;
    ctx->event_count--;
}

/* --- Frame management --- */

void kui_begin_frame(KUIContext* ctx) {
    if (!ctx || !ctx->gr_context) return;

#ifdef __APPLE__
    /* Get Metal drawable and create Skia surface */
    int pw = (int)(ctx->width * ctx->scale);
    int ph = (int)(ctx->height * ctx->scale);

    ctx->metal_layer.drawableSize = CGSizeMake(pw, ph);
    id<CAMetalDrawable> drawable = [ctx->metal_layer nextDrawable];
    if (!drawable) return;

    ctx->current_drawable = drawable;

    GrMtlTextureInfo info;
    info.fTexture.retain((__bridge void*)drawable.texture);

    GrBackendRenderTarget target(pw, ph, info);

    SkSurfaceProps props(0, kRGB_H_SkPixelGeometry);
    ctx->surface = SkSurfaces::WrapBackendRenderTarget(
        ctx->gr_context.get(),
        target,
        kTopLeft_GrSurfaceOrigin,
        kBGRA_8888_SkColorType,
        SkColorSpace::MakeSRGB(),
        &props
    );

    if (ctx->surface) {
        ctx->canvas = ctx->surface->getCanvas();
        ctx->canvas->scale(ctx->scale, ctx->scale);
    }
#else
    /* Create Skia surface from GL framebuffer */
    int pw, ph;
    SDL_GetWindowSizeInPixels(ctx->window, &pw, &ph);

    GrGLFramebufferInfo fbi;
    fbi.fFBOID = 0;
    fbi.fFormat = GL_RGBA8;

    GrBackendRenderTarget target(pw, ph, 0, 8, fbi);

    SkSurfaceProps props(0, kRGB_H_SkPixelGeometry);
    ctx->surface = SkSurfaces::WrapBackendRenderTarget(
        ctx->gr_context.get(),
        target,
        kBottomLeft_GrSurfaceOrigin,
        kRGBA_8888_SkColorType,
        SkColorSpace::MakeSRGB(),
        &props
    );

    if (ctx->surface) {
        ctx->canvas = ctx->surface->getCanvas();
        ctx->canvas->scale(ctx->scale, ctx->scale);
    }
#endif
}

void kui_end_frame(KUIContext* ctx) {
    if (!ctx || !ctx->canvas) return;

    skgpu::ganesh::FlushAndSubmit(ctx->surface);

#ifdef __APPLE__
    /* Present the SAME drawable we got in begin_frame */
    if (ctx->current_drawable) {
        id<MTLCommandBuffer> cmdBuf = [ctx->mtl_queue commandBuffer];
        [cmdBuf presentDrawable:ctx->current_drawable];
        [cmdBuf commit];
        ctx->current_drawable = nil;
    }
#else
    SDL_GL_SwapWindow(ctx->window);
#endif

    ctx->surface.reset();
    ctx->canvas = nullptr;
    // NOTE: Don't clear dirty here — the redraw callback may have set dirty=true
    // again (e.g., for animations). Ruby side manages dirty flag via clear_dirty().
}

/* --- Drawing primitives --- */

void kui_clear(KUIContext* ctx, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    ctx->canvas->clear(uint32_to_skcolor(color));
}

void kui_fill_rect(KUIContext* ctx, double x, double y, double w, double h, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);
    ctx->canvas->drawRect(SkRect::MakeXYWH(x, y, w, h), paint);
}

void kui_stroke_rect(KUIContext* ctx, double x, double y, double w, double h,
                     uint32_t color, double stroke_width) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(stroke_width);
    paint.setAntiAlias(true);
    ctx->canvas->drawRect(SkRect::MakeXYWH(x, y, w, h), paint);
}

void kui_fill_round_rect(KUIContext* ctx, double x, double y, double w, double h,
                         double r, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);
    ctx->canvas->drawRRect(
        SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), r, r),
        paint
    );
}

void kui_stroke_round_rect(KUIContext* ctx, double x, double y, double w, double h,
                           double r, uint32_t color, double stroke_width) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(stroke_width);
    paint.setAntiAlias(true);
    ctx->canvas->drawRRect(
        SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), r, r),
        paint
    );
}

void kui_fill_circle(KUIContext* ctx, double cx, double cy, double r, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);
    ctx->canvas->drawCircle(cx, cy, r, paint);
}

void kui_stroke_circle(KUIContext* ctx, double cx, double cy, double r,
                       uint32_t color, double stroke_width) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(stroke_width);
    paint.setAntiAlias(true);
    ctx->canvas->drawCircle(cx, cy, r, paint);
}

void kui_draw_line(KUIContext* ctx, double x1, double y1, double x2, double y2,
                   uint32_t color, double width) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setStrokeWidth(width);
    paint.setAntiAlias(true);
    ctx->canvas->drawLine(x1, y1, x2, y2, paint);
}

void kui_fill_arc(KUIContext* ctx, double cx, double cy, double r,
                  double start_angle, double sweep_angle, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);
    SkRect oval = SkRect::MakeXYWH(cx - r, cy - r, r * 2, r * 2);
    SkPath path;
    path.moveTo(cx, cy);
    path.arcTo(oval, start_angle, sweep_angle, false);
    path.close();
    ctx->canvas->drawPath(path, paint);
}

void kui_stroke_arc(KUIContext* ctx, double cx, double cy, double r,
                    double start_angle, double sweep_angle,
                    uint32_t color, double stroke_width) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(stroke_width);
    paint.setAntiAlias(true);
    SkRect oval = SkRect::MakeXYWH(cx - r, cy - r, r * 2, r * 2);
    ctx->canvas->drawArc(oval, start_angle, sweep_angle, false, paint);
}

void kui_fill_triangle(KUIContext* ctx, double x1, double y1, double x2, double y2,
                       double x3, double y3, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);
    SkPath path;
    path.moveTo(x1, y1);
    path.lineTo(x2, y2);
    path.lineTo(x3, y3);
    path.close();
    ctx->canvas->drawPath(path, paint);
}

/* --- Text drawing --- */

void kui_draw_text(KUIContext* ctx, const char* text, double x, double y,
                   const char* font_family, double font_size, uint32_t color) {
    kui_draw_text_styled(ctx, text, x, y, font_family, font_size, color, 0, 0);
}

void kui_draw_text_styled(KUIContext* ctx, const char* text, double x, double y,
                          const char* font_family, double font_size, uint32_t color,
                          int weight, int slant) {
    if (!ctx || !ctx->canvas || !text) return;

    sk_sp<SkTypeface> tf = find_typeface(ctx, font_family, weight, slant);
    SkFont font(tf, font_size);
    font.setEdging(SkFont::Edging::kSubpixelAntiAlias);
    font.setSubpixel(true);

    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);

    auto blob = SkTextBlob::MakeFromString(text, font);
    if (blob) {
        ctx->canvas->drawTextBlob(blob, x, y, paint);
    }
}

/* --- Text measurement --- */

double kui_measure_text_width(KUIContext* ctx, const char* text,
                               const char* font_family, double font_size) {
    if (!ctx || !text) return 0.0;

    sk_sp<SkTypeface> tf = find_typeface(ctx, font_family, 0, 0);
    SkFont font(tf, font_size);
    font.setSubpixel(true);

    return font.measureText(text, strlen(text), SkTextEncoding::kUTF8);
}

double kui_measure_text_height(KUIContext* ctx, const char* font_family, double font_size) {
    if (!ctx) return 0.0;

    sk_sp<SkTypeface> tf = find_typeface(ctx, font_family, 0, 0);
    SkFont font(tf, font_size);

    SkFontMetrics metrics;
    font.getMetrics(&metrics);
    return metrics.fDescent - metrics.fAscent + metrics.fLeading;
}

double kui_get_text_ascent(KUIContext* ctx, const char* font_family, double font_size) {
    if (!ctx) return 0.0;

    sk_sp<SkTypeface> tf = find_typeface(ctx, font_family, 0, 0);
    SkFont font(tf, font_size);

    SkFontMetrics metrics;
    font.getMetrics(&metrics);
    return -metrics.fAscent; /* fAscent is negative, we return positive */
}

/* --- Path drawing --- */

void kui_begin_path(KUIContext* ctx) {
    if (!ctx) return;
    ctx->current_path.reset();
}

void kui_path_move_to(KUIContext* ctx, double x, double y) {
    if (!ctx) return;
    ctx->current_path.moveTo(x, y);
}

void kui_path_line_to(KUIContext* ctx, double x, double y) {
    if (!ctx) return;
    ctx->current_path.lineTo(x, y);
}

void kui_close_fill_path(KUIContext* ctx, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    ctx->current_path.close();
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);
    ctx->canvas->drawPath(ctx->current_path, paint);
}

void kui_fill_path(KUIContext* ctx, uint32_t color) {
    if (!ctx || !ctx->canvas) return;
    SkPaint paint;
    paint.setColor(uint32_to_skcolor(color));
    paint.setAntiAlias(true);
    ctx->canvas->drawPath(ctx->current_path, paint);
}

/* --- Canvas state --- */

void kui_save(KUIContext* ctx) {
    if (!ctx || !ctx->canvas) return;
    ctx->canvas->save();
}

void kui_restore(KUIContext* ctx) {
    if (!ctx || !ctx->canvas) return;
    ctx->canvas->restore();
}

void kui_translate(KUIContext* ctx, double dx, double dy) {
    if (!ctx || !ctx->canvas) return;
    ctx->canvas->translate(dx, dy);
}

void kui_clip_rect(KUIContext* ctx, double x, double y, double w, double h) {
    if (!ctx || !ctx->canvas) return;
    ctx->canvas->clipRect(SkRect::MakeXYWH(x, y, w, h));
}

/* --- Image operations --- */

int kui_load_image(KUIContext* ctx, const char* path) {
    if (!ctx || !path) return 0;

    auto data = SkData::MakeFromFileName(path);
    if (!data) return 0;

    /* Use deprecated MakeFromData (still available in m124) */
    auto codec = SkCodec::MakeFromData(data);
    if (!codec) return 0;

    SkImageInfo info = codec->getInfo().makeColorType(kN32_SkColorType);
    SkBitmap bitmap;
    bitmap.allocPixels(info);
    if (codec->getPixels(info, bitmap.getPixels(), bitmap.rowBytes()) != SkCodec::kSuccess) {
        return 0;
    }

    auto image = bitmap.asImage();
    if (!image) return 0;

    int id = ctx->next_image_id++;
    ctx->images[id] = image;
    return id;
}

int kui_load_net_image(KUIContext* ctx, const char* url) {
    /* TODO: implement URL image loading (curl + Skia decode) */
    (void)ctx; (void)url;
    return 0;
}

void kui_draw_image(KUIContext* ctx, int image_id, double x, double y, double w, double h) {
    if (!ctx || !ctx->canvas) return;
    auto it = ctx->images.find(image_id);
    if (it == ctx->images.end()) return;

    SkRect dst = SkRect::MakeXYWH(x, y, w, h);
    ctx->canvas->drawImageRect(it->second.get(), dst, SkSamplingOptions());
}

double kui_get_image_width(KUIContext* ctx, int image_id) {
    if (!ctx) return 0.0;
    auto it = ctx->images.find(image_id);
    return (it != ctx->images.end()) ? (double)it->second->width() : 0.0;
}

double kui_get_image_height(KUIContext* ctx, int image_id) {
    if (!ctx) return 0.0;
    auto it = ctx->images.find(image_id);
    return (it != ctx->images.end()) ? (double)it->second->height() : 0.0;
}

/* --- Color utilities --- */

uint32_t kui_interpolate_color(uint32_t c1, uint32_t c2, double t) {
    if (t <= 0.0) return c1;
    if (t >= 1.0) return c2;
    int a1 = (c1 >> 24) & 0xFF, r1 = (c1 >> 16) & 0xFF, g1 = (c1 >> 8) & 0xFF, b1 = c1 & 0xFF;
    int a2 = (c2 >> 24) & 0xFF, r2 = (c2 >> 16) & 0xFF, g2 = (c2 >> 8) & 0xFF, b2 = c2 & 0xFF;
    int a = (int)(a1 + (a2 - a1) * t);
    int r = (int)(r1 + (r2 - r1) * t);
    int g = (int)(g1 + (g2 - g1) * t);
    int b = (int)(b1 + (b2 - b1) * t);
    return ((uint32_t)clamp_u8(a) << 24) | ((uint32_t)clamp_u8(r) << 16) |
           ((uint32_t)clamp_u8(g) << 8)  | (uint32_t)clamp_u8(b);
}

uint32_t kui_with_alpha(uint32_t color, int alpha) {
    return (color & 0x00FFFFFF) | ((uint32_t)clamp_u8(alpha) << 24);
}

uint32_t kui_lighten_color(uint32_t color, double amount) {
    int r = (color >> 16) & 0xFF;
    int g = (color >> 8) & 0xFF;
    int b = color & 0xFF;
    int a = (color >> 24) & 0xFF;
    r = (int)(r + (255 - r) * amount);
    g = (int)(g + (255 - g) * amount);
    b = (int)(b + (255 - b) * amount);
    return ((uint32_t)a << 24) | ((uint32_t)clamp_u8(r) << 16) |
           ((uint32_t)clamp_u8(g) << 8) | (uint32_t)clamp_u8(b);
}

uint32_t kui_darken_color(uint32_t color, double amount) {
    int r = (color >> 16) & 0xFF;
    int g = (color >> 8) & 0xFF;
    int b = color & 0xFF;
    int a = (color >> 24) & 0xFF;
    r = (int)(r * (1.0 - amount));
    g = (int)(g * (1.0 - amount));
    b = (int)(b * (1.0 - amount));
    return ((uint32_t)a << 24) | ((uint32_t)clamp_u8(r) << 16) |
           ((uint32_t)clamp_u8(g) << 8) | (uint32_t)clamp_u8(b);
}

/* --- Window queries --- */

double kui_get_width(KUIContext* ctx) {
    return ctx ? (double)ctx->width : 0.0;
}

double kui_get_height(KUIContext* ctx) {
    return ctx ? (double)ctx->height : 0.0;
}

double kui_get_scale(KUIContext* ctx) {
    return ctx ? (double)ctx->scale : 1.0;
}

bool kui_is_dark_mode(KUIContext* ctx) {
    (void)ctx;
    /* SDL3 doesn't have a direct dark mode query.
     * For now, return false (light mode default). */
    return false;
}

void kui_request_frame(KUIContext* ctx) {
    if (ctx) ctx->frame_requested = true;
}

void kui_mark_dirty(KUIContext* ctx) {
    if (ctx) ctx->dirty = true;
}

bool kui_needs_redraw(KUIContext* ctx) {
    if (!ctx) return false;
    return ctx->dirty || ctx->frame_requested;
}

void kui_clear_frame_requested(KUIContext* ctx) {
    if (ctx) ctx->frame_requested = false;
}

void kui_clear_dirty(KUIContext* ctx) {
    if (ctx) ctx->dirty = false;
}

/* --- IME / Text Input --- */

void kui_set_text_input_enabled(KUIContext* ctx, bool enabled) {
    if (!ctx) return;
    if (enabled && !ctx->text_input_enabled) {
        SDL_StartTextInput(ctx->window);
        ctx->text_input_enabled = true;
    } else if (!enabled && ctx->text_input_enabled) {
        SDL_StopTextInput(ctx->window);
        ctx->text_input_enabled = false;
    }
}

void kui_set_text_input_rect(KUIContext* ctx, int x, int y, int w, int h) {
    if (!ctx) return;
    SDL_Rect rect = { x, y, w, h };
    SDL_SetTextInputArea(ctx->window, &rect, 0);
}

/* --- Clipboard --- */

const char* kui_get_clipboard_text(KUIContext* ctx) {
    if (!ctx) return "";
    char* text = SDL_GetClipboardText();
    if (text) {
        ctx->clipboard_cache = text;
        SDL_free(text);
        return ctx->clipboard_cache.c_str();
    }
    return "";
}

void kui_set_clipboard_text(KUIContext* ctx, const char* text) {
    (void)ctx;
    if (text) {
        SDL_SetClipboardText(text);
    }
}

/* --- Utilities --- */

int64_t kui_current_time_millis(void) {
    auto now = std::chrono::system_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch());
    return ms.count();
}

const char* kui_number_to_string(double value) {
    /* Thread-unsafe, but matches KUIRuntime.java behavior */
    static char buf[64];
    snprintf(buf, sizeof(buf), "%.10g", value);
    return buf;
}

/* --- Math helpers --- */

double kui_math_cos(double radians) { return cos(radians); }
double kui_math_sin(double radians) { return sin(radians); }
double kui_math_sqrt(double value) { return sqrt(value); }
double kui_math_atan2(double y, double x) { return atan2(y, x); }
double kui_math_abs(double value) { return fabs(value); }

} /* extern "C" */


/* ============================================================
 * CRuby Extension Wrapper
 * ============================================================ */

#include <ruby.h>

static VALUE mKonpeitoUI;

/* Helper: extract KUIContext* from Ruby Integer (pointer as Fixnum) */
static KUIContext* get_ctx(VALUE handle) {
    return (KUIContext*)(uintptr_t)NUM2ULL(handle);
}

/* --- Ruby wrapper functions --- */

static VALUE rb_kui_create_window(VALUE self, VALUE title, VALUE width, VALUE height) {
    Check_Type(title, T_STRING);
    KUIContext* ctx = kui_create_window(RSTRING_PTR(title), NUM2INT(width), NUM2INT(height));
    if (!ctx) {
        rb_raise(rb_eRuntimeError, "Failed to create window");
        return Qnil;
    }
    return ULL2NUM((uintptr_t)ctx);
}

static VALUE rb_kui_destroy_window(VALUE self, VALUE handle) {
    kui_destroy_window(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_step(VALUE self, VALUE handle) {
    kui_step(get_ctx(handle));
    return Qnil;
}

/* Event access */
static VALUE rb_kui_has_event(VALUE self, VALUE handle) {
    return kui_has_event(get_ctx(handle)) ? Qtrue : Qfalse;
}

static VALUE rb_kui_event_type(VALUE self, VALUE handle) {
    return INT2NUM(kui_event_type(get_ctx(handle)));
}

static VALUE rb_kui_event_x(VALUE self, VALUE handle) {
    return DBL2NUM(kui_event_x(get_ctx(handle)));
}

static VALUE rb_kui_event_y(VALUE self, VALUE handle) {
    return DBL2NUM(kui_event_y(get_ctx(handle)));
}

static VALUE rb_kui_event_dx(VALUE self, VALUE handle) {
    return DBL2NUM(kui_event_dx(get_ctx(handle)));
}

static VALUE rb_kui_event_dy(VALUE self, VALUE handle) {
    return DBL2NUM(kui_event_dy(get_ctx(handle)));
}

static VALUE rb_kui_event_button(VALUE self, VALUE handle) {
    return INT2NUM(kui_event_button(get_ctx(handle)));
}

static VALUE rb_kui_event_key_code(VALUE self, VALUE handle) {
    return INT2NUM(kui_event_key_code(get_ctx(handle)));
}

static VALUE rb_kui_event_modifiers(VALUE self, VALUE handle) {
    return INT2NUM(kui_event_modifiers(get_ctx(handle)));
}

static VALUE rb_kui_event_text(VALUE self, VALUE handle) {
    const char* text = kui_event_text(get_ctx(handle));
    return rb_utf8_str_new_cstr(text);
}

static VALUE rb_kui_event_ime_sel_start(VALUE self, VALUE handle) {
    return INT2NUM(kui_event_ime_sel_start(get_ctx(handle)));
}

static VALUE rb_kui_event_ime_sel_end(VALUE self, VALUE handle) {
    return INT2NUM(kui_event_ime_sel_end(get_ctx(handle)));
}

static VALUE rb_kui_consume_event(VALUE self, VALUE handle) {
    kui_consume_event(get_ctx(handle));
    return Qnil;
}

/* Frame management */
static VALUE rb_kui_begin_frame(VALUE self, VALUE handle) {
    kui_begin_frame(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_end_frame(VALUE self, VALUE handle) {
    kui_end_frame(get_ctx(handle));
    return Qnil;
}

/* Drawing */
static VALUE rb_kui_clear(VALUE self, VALUE handle, VALUE color) {
    kui_clear(get_ctx(handle), (uint32_t)NUM2ULL(color));
    return Qnil;
}

static VALUE rb_kui_fill_rect(VALUE self, VALUE h, VALUE x, VALUE y, VALUE w, VALUE ht, VALUE color) {
    kui_fill_rect(get_ctx(h), NUM2DBL(x), NUM2DBL(y), NUM2DBL(w), NUM2DBL(ht), (uint32_t)NUM2ULL(color));
    return Qnil;
}

static VALUE rb_kui_stroke_rect(int argc, VALUE* argv, VALUE self) {
    if (argc != 7) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 7)", argc);
    kui_stroke_rect(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                    NUM2DBL(argv[3]), NUM2DBL(argv[4]),
                    (uint32_t)NUM2ULL(argv[5]), NUM2DBL(argv[6]));
    return Qnil;
}

static VALUE rb_kui_fill_round_rect(int argc, VALUE* argv, VALUE self) {
    if (argc != 7) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 7)", argc);
    kui_fill_round_rect(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                        NUM2DBL(argv[3]), NUM2DBL(argv[4]),
                        NUM2DBL(argv[5]), (uint32_t)NUM2ULL(argv[6]));
    return Qnil;
}

static VALUE rb_kui_stroke_round_rect(int argc, VALUE* argv, VALUE self) {
    if (argc != 8) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 8)", argc);
    kui_stroke_round_rect(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                          NUM2DBL(argv[3]), NUM2DBL(argv[4]),
                          NUM2DBL(argv[5]), (uint32_t)NUM2ULL(argv[6]), NUM2DBL(argv[7]));
    return Qnil;
}

static VALUE rb_kui_fill_circle(VALUE self, VALUE h, VALUE cx, VALUE cy, VALUE r, VALUE color) {
    kui_fill_circle(get_ctx(h), NUM2DBL(cx), NUM2DBL(cy), NUM2DBL(r), (uint32_t)NUM2ULL(color));
    return Qnil;
}

static VALUE rb_kui_stroke_circle(int argc, VALUE* argv, VALUE self) {
    if (argc != 6) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 6)", argc);
    kui_stroke_circle(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                      NUM2DBL(argv[3]), (uint32_t)NUM2ULL(argv[4]), NUM2DBL(argv[5]));
    return Qnil;
}

static VALUE rb_kui_draw_line(int argc, VALUE* argv, VALUE self) {
    if (argc != 7) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 7)", argc);
    kui_draw_line(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                  NUM2DBL(argv[3]), NUM2DBL(argv[4]),
                  (uint32_t)NUM2ULL(argv[5]), NUM2DBL(argv[6]));
    return Qnil;
}

static VALUE rb_kui_fill_arc(int argc, VALUE* argv, VALUE self) {
    if (argc != 7) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 7)", argc);
    kui_fill_arc(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                 NUM2DBL(argv[3]), NUM2DBL(argv[4]),
                 NUM2DBL(argv[5]), (uint32_t)NUM2ULL(argv[6]));
    return Qnil;
}

static VALUE rb_kui_stroke_arc(int argc, VALUE* argv, VALUE self) {
    if (argc != 8) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 8)", argc);
    kui_stroke_arc(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                   NUM2DBL(argv[3]), NUM2DBL(argv[4]),
                   NUM2DBL(argv[5]), (uint32_t)NUM2ULL(argv[6]), NUM2DBL(argv[7]));
    return Qnil;
}

static VALUE rb_kui_fill_triangle(int argc, VALUE* argv, VALUE self) {
    if (argc != 8) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 8)", argc);
    kui_fill_triangle(get_ctx(argv[0]), NUM2DBL(argv[1]), NUM2DBL(argv[2]),
                      NUM2DBL(argv[3]), NUM2DBL(argv[4]),
                      NUM2DBL(argv[5]), NUM2DBL(argv[6]),
                      (uint32_t)NUM2ULL(argv[7]));
    return Qnil;
}

/* Text */
static VALUE rb_kui_draw_text(int argc, VALUE* argv, VALUE self) {
    if (argc != 7) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 7)", argc);
    Check_Type(argv[1], T_STRING);
    Check_Type(argv[4], T_STRING);
    kui_draw_text(get_ctx(argv[0]), RSTRING_PTR(argv[1]),
                  NUM2DBL(argv[2]), NUM2DBL(argv[3]),
                  RSTRING_PTR(argv[4]), NUM2DBL(argv[5]),
                  (uint32_t)NUM2ULL(argv[6]));
    return Qnil;
}

static VALUE rb_kui_draw_text_styled(int argc, VALUE* argv, VALUE self) {
    if (argc != 9) rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 9)", argc);
    Check_Type(argv[1], T_STRING);
    Check_Type(argv[4], T_STRING);
    kui_draw_text_styled(get_ctx(argv[0]), RSTRING_PTR(argv[1]),
                         NUM2DBL(argv[2]), NUM2DBL(argv[3]),
                         RSTRING_PTR(argv[4]), NUM2DBL(argv[5]),
                         (uint32_t)NUM2ULL(argv[6]),
                         NUM2INT(argv[7]), NUM2INT(argv[8]));
    return Qnil;
}

/* Text measurement */
static VALUE rb_kui_measure_text_width(VALUE self, VALUE handle, VALUE text, VALUE font_family, VALUE font_size) {
    Check_Type(text, T_STRING);
    Check_Type(font_family, T_STRING);
    return DBL2NUM(kui_measure_text_width(get_ctx(handle), RSTRING_PTR(text),
                                           RSTRING_PTR(font_family), NUM2DBL(font_size)));
}

static VALUE rb_kui_measure_text_height(VALUE self, VALUE handle, VALUE font_family, VALUE font_size) {
    Check_Type(font_family, T_STRING);
    return DBL2NUM(kui_measure_text_height(get_ctx(handle), RSTRING_PTR(font_family), NUM2DBL(font_size)));
}

static VALUE rb_kui_get_text_ascent(VALUE self, VALUE handle, VALUE font_family, VALUE font_size) {
    Check_Type(font_family, T_STRING);
    return DBL2NUM(kui_get_text_ascent(get_ctx(handle), RSTRING_PTR(font_family), NUM2DBL(font_size)));
}

/* Path drawing */
static VALUE rb_kui_begin_path(VALUE self, VALUE handle) {
    kui_begin_path(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_path_move_to(VALUE self, VALUE handle, VALUE x, VALUE y) {
    kui_path_move_to(get_ctx(handle), NUM2DBL(x), NUM2DBL(y));
    return Qnil;
}

static VALUE rb_kui_path_line_to(VALUE self, VALUE handle, VALUE x, VALUE y) {
    kui_path_line_to(get_ctx(handle), NUM2DBL(x), NUM2DBL(y));
    return Qnil;
}

static VALUE rb_kui_close_fill_path(VALUE self, VALUE handle, VALUE color) {
    kui_close_fill_path(get_ctx(handle), (uint32_t)NUM2ULL(color));
    return Qnil;
}

static VALUE rb_kui_fill_path_fn(VALUE self, VALUE handle, VALUE color) {
    kui_fill_path(get_ctx(handle), (uint32_t)NUM2ULL(color));
    return Qnil;
}

/* Canvas state */
static VALUE rb_kui_save(VALUE self, VALUE handle) {
    kui_save(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_restore(VALUE self, VALUE handle) {
    kui_restore(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_translate(VALUE self, VALUE handle, VALUE dx, VALUE dy) {
    kui_translate(get_ctx(handle), NUM2DBL(dx), NUM2DBL(dy));
    return Qnil;
}

static VALUE rb_kui_clip_rect(VALUE self, VALUE handle, VALUE x, VALUE y, VALUE w, VALUE h) {
    kui_clip_rect(get_ctx(handle), NUM2DBL(x), NUM2DBL(y), NUM2DBL(w), NUM2DBL(h));
    return Qnil;
}

/* Image operations */
static VALUE rb_kui_load_image(VALUE self, VALUE handle, VALUE path) {
    Check_Type(path, T_STRING);
    return INT2NUM(kui_load_image(get_ctx(handle), RSTRING_PTR(path)));
}

static VALUE rb_kui_load_net_image(VALUE self, VALUE handle, VALUE url) {
    Check_Type(url, T_STRING);
    return INT2NUM(kui_load_net_image(get_ctx(handle), RSTRING_PTR(url)));
}

static VALUE rb_kui_draw_image(VALUE self, VALUE handle, VALUE image_id, VALUE x, VALUE y, VALUE w, VALUE h) {
    kui_draw_image(get_ctx(handle), NUM2INT(image_id), NUM2DBL(x), NUM2DBL(y), NUM2DBL(w), NUM2DBL(h));
    return Qnil;
}

static VALUE rb_kui_get_image_width(VALUE self, VALUE handle, VALUE image_id) {
    return DBL2NUM(kui_get_image_width(get_ctx(handle), NUM2INT(image_id)));
}

static VALUE rb_kui_get_image_height(VALUE self, VALUE handle, VALUE image_id) {
    return DBL2NUM(kui_get_image_height(get_ctx(handle), NUM2INT(image_id)));
}

/* Color utilities */
static VALUE rb_kui_interpolate_color(VALUE self, VALUE c1, VALUE c2, VALUE t) {
    return ULL2NUM(kui_interpolate_color((uint32_t)NUM2ULL(c1), (uint32_t)NUM2ULL(c2), NUM2DBL(t)));
}

static VALUE rb_kui_with_alpha(VALUE self, VALUE color, VALUE alpha) {
    return ULL2NUM(kui_with_alpha((uint32_t)NUM2ULL(color), NUM2INT(alpha)));
}

static VALUE rb_kui_lighten_color(VALUE self, VALUE color, VALUE amount) {
    return ULL2NUM(kui_lighten_color((uint32_t)NUM2ULL(color), NUM2DBL(amount)));
}

static VALUE rb_kui_darken_color(VALUE self, VALUE color, VALUE amount) {
    return ULL2NUM(kui_darken_color((uint32_t)NUM2ULL(color), NUM2DBL(amount)));
}

/* Window queries */
static VALUE rb_kui_get_width(VALUE self, VALUE handle) {
    return DBL2NUM(kui_get_width(get_ctx(handle)));
}

static VALUE rb_kui_get_height(VALUE self, VALUE handle) {
    return DBL2NUM(kui_get_height(get_ctx(handle)));
}

static VALUE rb_kui_get_scale(VALUE self, VALUE handle) {
    return DBL2NUM(kui_get_scale(get_ctx(handle)));
}

static VALUE rb_kui_is_dark_mode(VALUE self, VALUE handle) {
    return kui_is_dark_mode(get_ctx(handle)) ? Qtrue : Qfalse;
}

static VALUE rb_kui_request_frame(VALUE self, VALUE handle) {
    kui_request_frame(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_mark_dirty(VALUE self, VALUE handle) {
    kui_mark_dirty(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_needs_redraw(VALUE self, VALUE handle) {
    return kui_needs_redraw(get_ctx(handle)) ? Qtrue : Qfalse;
}

static VALUE rb_kui_clear_frame_requested(VALUE self, VALUE handle) {
    kui_clear_frame_requested(get_ctx(handle));
    return Qnil;
}

static VALUE rb_kui_clear_dirty(VALUE self, VALUE handle) {
    kui_clear_dirty(get_ctx(handle));
    return Qnil;
}

/* IME / Text Input */
static VALUE rb_kui_set_text_input_enabled(VALUE self, VALUE handle, VALUE enabled) {
    kui_set_text_input_enabled(get_ctx(handle), RTEST(enabled));
    return Qnil;
}

static VALUE rb_kui_set_text_input_rect(VALUE self, VALUE handle, VALUE x, VALUE y, VALUE w, VALUE h) {
    kui_set_text_input_rect(get_ctx(handle), NUM2INT(x), NUM2INT(y), NUM2INT(w), NUM2INT(h));
    return Qnil;
}

/* Clipboard */
static VALUE rb_kui_get_clipboard_text(VALUE self, VALUE handle) {
    const char* text = kui_get_clipboard_text(get_ctx(handle));
    return rb_utf8_str_new_cstr(text);
}

static VALUE rb_kui_set_clipboard_text(VALUE self, VALUE handle, VALUE text) {
    Check_Type(text, T_STRING);
    kui_set_clipboard_text(get_ctx(handle), RSTRING_PTR(text));
    return Qnil;
}

/* Utilities */
static VALUE rb_kui_current_time_millis(VALUE self) {
    return LL2NUM(kui_current_time_millis());
}

static VALUE rb_kui_number_to_string(VALUE self, VALUE value) {
    const char* s = kui_number_to_string(NUM2DBL(value));
    return rb_utf8_str_new_cstr(s);
}

/* Math helpers */
static VALUE rb_kui_math_cos(VALUE self, VALUE radians) { return DBL2NUM(kui_math_cos(NUM2DBL(radians))); }
static VALUE rb_kui_math_sin(VALUE self, VALUE radians) { return DBL2NUM(kui_math_sin(NUM2DBL(radians))); }
static VALUE rb_kui_math_sqrt(VALUE self, VALUE value) { return DBL2NUM(kui_math_sqrt(NUM2DBL(value))); }
static VALUE rb_kui_math_atan2(VALUE self, VALUE y, VALUE x) { return DBL2NUM(kui_math_atan2(NUM2DBL(y), NUM2DBL(x))); }
static VALUE rb_kui_math_abs(VALUE self, VALUE value) { return DBL2NUM(kui_math_abs(NUM2DBL(value))); }


/* ============================================================
 * Module initialization
 * ============================================================ */

extern "C" void Init_konpeito_ui(void) {
    mKonpeitoUI = rb_define_module("KonpeitoUI");

    /* Window management */
    rb_define_module_function(mKonpeitoUI, "create_window", (VALUE(*)(ANYARGS))rb_kui_create_window, 3);
    rb_define_module_function(mKonpeitoUI, "destroy_window", (VALUE(*)(ANYARGS))rb_kui_destroy_window, 1);
    rb_define_module_function(mKonpeitoUI, "step", (VALUE(*)(ANYARGS))rb_kui_step, 1);

    /* Event access */
    rb_define_module_function(mKonpeitoUI, "has_event", (VALUE(*)(ANYARGS))rb_kui_has_event, 1);
    rb_define_module_function(mKonpeitoUI, "event_type", (VALUE(*)(ANYARGS))rb_kui_event_type, 1);
    rb_define_module_function(mKonpeitoUI, "event_x", (VALUE(*)(ANYARGS))rb_kui_event_x, 1);
    rb_define_module_function(mKonpeitoUI, "event_y", (VALUE(*)(ANYARGS))rb_kui_event_y, 1);
    rb_define_module_function(mKonpeitoUI, "event_dx", (VALUE(*)(ANYARGS))rb_kui_event_dx, 1);
    rb_define_module_function(mKonpeitoUI, "event_dy", (VALUE(*)(ANYARGS))rb_kui_event_dy, 1);
    rb_define_module_function(mKonpeitoUI, "event_button", (VALUE(*)(ANYARGS))rb_kui_event_button, 1);
    rb_define_module_function(mKonpeitoUI, "event_key_code", (VALUE(*)(ANYARGS))rb_kui_event_key_code, 1);
    rb_define_module_function(mKonpeitoUI, "event_modifiers", (VALUE(*)(ANYARGS))rb_kui_event_modifiers, 1);
    rb_define_module_function(mKonpeitoUI, "event_text", (VALUE(*)(ANYARGS))rb_kui_event_text, 1);
    rb_define_module_function(mKonpeitoUI, "event_ime_sel_start", (VALUE(*)(ANYARGS))rb_kui_event_ime_sel_start, 1);
    rb_define_module_function(mKonpeitoUI, "event_ime_sel_end", (VALUE(*)(ANYARGS))rb_kui_event_ime_sel_end, 1);
    rb_define_module_function(mKonpeitoUI, "consume_event", (VALUE(*)(ANYARGS))rb_kui_consume_event, 1);

    /* Frame management */
    rb_define_module_function(mKonpeitoUI, "begin_frame", (VALUE(*)(ANYARGS))rb_kui_begin_frame, 1);
    rb_define_module_function(mKonpeitoUI, "end_frame", (VALUE(*)(ANYARGS))rb_kui_end_frame, 1);

    /* Drawing primitives */
    rb_define_module_function(mKonpeitoUI, "clear", (VALUE(*)(ANYARGS))rb_kui_clear, 2);
    rb_define_module_function(mKonpeitoUI, "fill_rect", (VALUE(*)(ANYARGS))rb_kui_fill_rect, 6);
    rb_define_module_function(mKonpeitoUI, "stroke_rect", (VALUE(*)(ANYARGS))rb_kui_stroke_rect, -1);
    rb_define_module_function(mKonpeitoUI, "fill_round_rect", (VALUE(*)(ANYARGS))rb_kui_fill_round_rect, -1);
    rb_define_module_function(mKonpeitoUI, "stroke_round_rect", (VALUE(*)(ANYARGS))rb_kui_stroke_round_rect, -1);
    rb_define_module_function(mKonpeitoUI, "fill_circle", (VALUE(*)(ANYARGS))rb_kui_fill_circle, 5);
    rb_define_module_function(mKonpeitoUI, "stroke_circle", (VALUE(*)(ANYARGS))rb_kui_stroke_circle, -1);
    rb_define_module_function(mKonpeitoUI, "draw_line", (VALUE(*)(ANYARGS))rb_kui_draw_line, -1);
    rb_define_module_function(mKonpeitoUI, "fill_arc", (VALUE(*)(ANYARGS))rb_kui_fill_arc, -1);
    rb_define_module_function(mKonpeitoUI, "stroke_arc", (VALUE(*)(ANYARGS))rb_kui_stroke_arc, -1);
    rb_define_module_function(mKonpeitoUI, "fill_triangle", (VALUE(*)(ANYARGS))rb_kui_fill_triangle, -1);

    /* Text */
    rb_define_module_function(mKonpeitoUI, "draw_text", (VALUE(*)(ANYARGS))rb_kui_draw_text, -1);
    rb_define_module_function(mKonpeitoUI, "draw_text_styled", (VALUE(*)(ANYARGS))rb_kui_draw_text_styled, -1);
    rb_define_module_function(mKonpeitoUI, "measure_text_width", (VALUE(*)(ANYARGS))rb_kui_measure_text_width, 4);
    rb_define_module_function(mKonpeitoUI, "measure_text_height", (VALUE(*)(ANYARGS))rb_kui_measure_text_height, 3);
    rb_define_module_function(mKonpeitoUI, "get_text_ascent", (VALUE(*)(ANYARGS))rb_kui_get_text_ascent, 3);

    /* Path drawing */
    rb_define_module_function(mKonpeitoUI, "begin_path", (VALUE(*)(ANYARGS))rb_kui_begin_path, 1);
    rb_define_module_function(mKonpeitoUI, "path_move_to", (VALUE(*)(ANYARGS))rb_kui_path_move_to, 3);
    rb_define_module_function(mKonpeitoUI, "path_line_to", (VALUE(*)(ANYARGS))rb_kui_path_line_to, 3);
    rb_define_module_function(mKonpeitoUI, "close_fill_path", (VALUE(*)(ANYARGS))rb_kui_close_fill_path, 2);
    rb_define_module_function(mKonpeitoUI, "fill_path", (VALUE(*)(ANYARGS))rb_kui_fill_path_fn, 2);

    /* Canvas state */
    rb_define_module_function(mKonpeitoUI, "save", (VALUE(*)(ANYARGS))rb_kui_save, 1);
    rb_define_module_function(mKonpeitoUI, "restore", (VALUE(*)(ANYARGS))rb_kui_restore, 1);
    rb_define_module_function(mKonpeitoUI, "translate", (VALUE(*)(ANYARGS))rb_kui_translate, 3);
    rb_define_module_function(mKonpeitoUI, "clip_rect", (VALUE(*)(ANYARGS))rb_kui_clip_rect, 5);

    /* Image operations */
    rb_define_module_function(mKonpeitoUI, "load_image", (VALUE(*)(ANYARGS))rb_kui_load_image, 2);
    rb_define_module_function(mKonpeitoUI, "load_net_image", (VALUE(*)(ANYARGS))rb_kui_load_net_image, 2);
    rb_define_module_function(mKonpeitoUI, "draw_image", (VALUE(*)(ANYARGS))rb_kui_draw_image, 6);
    rb_define_module_function(mKonpeitoUI, "get_image_width", (VALUE(*)(ANYARGS))rb_kui_get_image_width, 2);
    rb_define_module_function(mKonpeitoUI, "get_image_height", (VALUE(*)(ANYARGS))rb_kui_get_image_height, 2);

    /* Color utilities */
    rb_define_module_function(mKonpeitoUI, "interpolate_color", (VALUE(*)(ANYARGS))rb_kui_interpolate_color, 3);
    rb_define_module_function(mKonpeitoUI, "with_alpha", (VALUE(*)(ANYARGS))rb_kui_with_alpha, 2);
    rb_define_module_function(mKonpeitoUI, "lighten_color", (VALUE(*)(ANYARGS))rb_kui_lighten_color, 2);
    rb_define_module_function(mKonpeitoUI, "darken_color", (VALUE(*)(ANYARGS))rb_kui_darken_color, 2);

    /* Window queries */
    rb_define_module_function(mKonpeitoUI, "get_width", (VALUE(*)(ANYARGS))rb_kui_get_width, 1);
    rb_define_module_function(mKonpeitoUI, "get_height", (VALUE(*)(ANYARGS))rb_kui_get_height, 1);
    rb_define_module_function(mKonpeitoUI, "get_scale", (VALUE(*)(ANYARGS))rb_kui_get_scale, 1);
    rb_define_module_function(mKonpeitoUI, "is_dark_mode", (VALUE(*)(ANYARGS))rb_kui_is_dark_mode, 1);
    rb_define_module_function(mKonpeitoUI, "request_frame", (VALUE(*)(ANYARGS))rb_kui_request_frame, 1);
    rb_define_module_function(mKonpeitoUI, "mark_dirty", (VALUE(*)(ANYARGS))rb_kui_mark_dirty, 1);
    rb_define_module_function(mKonpeitoUI, "needs_redraw", (VALUE(*)(ANYARGS))rb_kui_needs_redraw, 1);
    rb_define_module_function(mKonpeitoUI, "clear_frame_requested", (VALUE(*)(ANYARGS))rb_kui_clear_frame_requested, 1);
    rb_define_module_function(mKonpeitoUI, "clear_dirty", (VALUE(*)(ANYARGS))rb_kui_clear_dirty, 1);

    /* IME / Text Input */
    rb_define_module_function(mKonpeitoUI, "set_text_input_enabled", (VALUE(*)(ANYARGS))rb_kui_set_text_input_enabled, 2);
    rb_define_module_function(mKonpeitoUI, "set_text_input_rect", (VALUE(*)(ANYARGS))rb_kui_set_text_input_rect, 5);

    /* Clipboard */
    rb_define_module_function(mKonpeitoUI, "get_clipboard_text", (VALUE(*)(ANYARGS))rb_kui_get_clipboard_text, 1);
    rb_define_module_function(mKonpeitoUI, "set_clipboard_text", (VALUE(*)(ANYARGS))rb_kui_set_clipboard_text, 2);

    /* Utilities */
    rb_define_module_function(mKonpeitoUI, "current_time_millis", (VALUE(*)(ANYARGS))rb_kui_current_time_millis, 0);
    rb_define_module_function(mKonpeitoUI, "number_to_string", (VALUE(*)(ANYARGS))rb_kui_number_to_string, 1);

    /* Math helpers */
    rb_define_module_function(mKonpeitoUI, "math_cos", (VALUE(*)(ANYARGS))rb_kui_math_cos, 1);
    rb_define_module_function(mKonpeitoUI, "math_sin", (VALUE(*)(ANYARGS))rb_kui_math_sin, 1);
    rb_define_module_function(mKonpeitoUI, "math_sqrt", (VALUE(*)(ANYARGS))rb_kui_math_sqrt, 1);
    rb_define_module_function(mKonpeitoUI, "math_atan2", (VALUE(*)(ANYARGS))rb_kui_math_atan2, 2);
    rb_define_module_function(mKonpeitoUI, "math_abs", (VALUE(*)(ANYARGS))rb_kui_math_abs, 1);

    /* Event type constants */
    rb_define_const(mKonpeitoUI, "EVENT_NONE", INT2NUM(KUI_EVENT_NONE));
    rb_define_const(mKonpeitoUI, "EVENT_MOUSE_DOWN", INT2NUM(KUI_EVENT_MOUSE_DOWN));
    rb_define_const(mKonpeitoUI, "EVENT_MOUSE_UP", INT2NUM(KUI_EVENT_MOUSE_UP));
    rb_define_const(mKonpeitoUI, "EVENT_MOUSE_MOVE", INT2NUM(KUI_EVENT_MOUSE_MOVE));
    rb_define_const(mKonpeitoUI, "EVENT_MOUSE_WHEEL", INT2NUM(KUI_EVENT_MOUSE_WHEEL));
    rb_define_const(mKonpeitoUI, "EVENT_KEY_DOWN", INT2NUM(KUI_EVENT_KEY_DOWN));
    rb_define_const(mKonpeitoUI, "EVENT_KEY_UP", INT2NUM(KUI_EVENT_KEY_UP));
    rb_define_const(mKonpeitoUI, "EVENT_TEXT_INPUT", INT2NUM(KUI_EVENT_TEXT_INPUT));
    rb_define_const(mKonpeitoUI, "EVENT_RESIZE", INT2NUM(KUI_EVENT_RESIZE));
    rb_define_const(mKonpeitoUI, "EVENT_IME_PREEDIT", INT2NUM(KUI_EVENT_IME_PREEDIT));
    rb_define_const(mKonpeitoUI, "EVENT_QUIT", INT2NUM(KUI_EVENT_QUIT));

    /* Modifier constants */
    rb_define_const(mKonpeitoUI, "MOD_SHIFT", INT2NUM(KUI_MOD_SHIFT));
    rb_define_const(mKonpeitoUI, "MOD_CONTROL", INT2NUM(KUI_MOD_CONTROL));
    rb_define_const(mKonpeitoUI, "MOD_ALT", INT2NUM(KUI_MOD_ALT));
    rb_define_const(mKonpeitoUI, "MOD_SUPER", INT2NUM(KUI_MOD_SUPER));
}
