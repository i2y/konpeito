/*
 * clay_renderer_termbox2.c — Clay render command → termbox2 output
 *
 * Coordinate system: 1 Clay unit = 1 terminal cell.
 * Color model: Truecolor (TB_OUTPUT_TRUECOLOR) by default.
 *
 * Supported Clay commands:
 *   RECTANGLE — fill area with background color using space characters
 *   TEXT      — print text with fg color (bg inherited from parent rectangle)
 *   BORDER   — draw box-drawing characters (┌─┐│└─┘)
 *   SCISSOR_START/END — software clipping (clip rect tracking)
 *   IMAGE/CUSTOM — skipped (not applicable to TUI)
 */

#include "../../vendor/termbox2/termbox2.h"
#include "clay.h"
#include <string.h>
#include <math.h>

/* ── Clip rect stack ── */
#define MAX_CLIP_STACK 32
typedef struct { int x, y, w, h; } ClipRect;
static ClipRect clip_stack[MAX_CLIP_STACK];
static int clip_depth = 0;

static void push_clip(int x, int y, int w, int h) {
    if (clip_depth < MAX_CLIP_STACK) {
        clip_stack[clip_depth++] = (ClipRect){x, y, w, h};
    }
}

static void pop_clip(void) {
    if (clip_depth > 0) clip_depth--;
}

static int clipped(int x, int y) {
    if (clip_depth == 0) return 0;
    ClipRect *c = &clip_stack[clip_depth - 1];
    return (x < c->x || x >= c->x + c->w || y < c->y || y >= c->y + c->h);
}

/* ── Color conversion: Clay RGBA → termbox2 truecolor ── */
static uintattr_t rgba_to_tb(Clay_Color c) {
    if (c.a < 128.0f) return TB_DEFAULT;
    unsigned int r = (unsigned int)roundf(c.r);
    unsigned int g = (unsigned int)roundf(c.g);
    unsigned int b = (unsigned int)roundf(c.b);
    if (r > 255) r = 255;
    if (g > 255) g = 255;
    if (b > 255) b = 255;
    return (uintattr_t)((r << 16) | (g << 8) | b);
}

/* ── Text measurement (monospace: width = char count, height = 1) ── */
static inline Clay_Dimensions Termbox_MeasureText(Clay_StringSlice text,
                                                    Clay_TextElementConfig *config,
                                                    void *userData) {
    (void)config;
    (void)userData;
    /* Simple ASCII/UTF-8 byte count — in a monospace terminal each
     * printable character occupies one cell. For pure ASCII this is exact.
     * Multi-byte UTF-8 will slightly overcount width but is safe. */
    int width = 0;
    for (int i = 0; i < text.length; i++) {
        unsigned char ch = (unsigned char)text.chars[i];
        /* Skip UTF-8 continuation bytes */
        if ((ch & 0xC0) != 0x80) width++;
    }
    return (Clay_Dimensions){ .width = (float)width, .height = 1.0f };
}

/* ── Render all Clay commands to the termbox2 framebuffer ── */
static void Clay_Termbox_Render(Clay_RenderCommandArray commands) {
    int tw = tb_width();
    int th = tb_height();

    for (int j = 0; j < commands.length; j++) {
        Clay_RenderCommand *cmd = Clay_RenderCommandArray_Get(&commands, j);
        Clay_BoundingBox bb = cmd->boundingBox;
        int bx = (int)roundf(bb.x);
        int by = (int)roundf(bb.y);
        int bw = (int)roundf(bb.width);
        int bh = (int)roundf(bb.height);

        switch (cmd->commandType) {
            case CLAY_RENDER_COMMAND_TYPE_RECTANGLE: {
                Clay_RectangleRenderData *rect = &cmd->renderData.rectangle;
                uintattr_t bg = rgba_to_tb(rect->backgroundColor);

                for (int y = by; y < by + bh && y < th; y++) {
                    for (int x = bx; x < bx + bw && x < tw; x++) {
                        if (x < 0 || y < 0) continue;
                        if (clipped(x, y)) continue;
                        tb_set_cell(x, y, ' ', TB_DEFAULT, bg);
                    }
                }
                break;
            }

            case CLAY_RENDER_COMMAND_TYPE_TEXT: {
                Clay_TextRenderData *text = &cmd->renderData.text;
                uintattr_t fg = rgba_to_tb(text->textColor);
                /* Read bg from cell buffer — inherits whatever RECTANGLE
                 * already painted at this position (parent or self). */
                struct tb_cell *buf = tb_cell_buffer();

                int x = bx;
                int y = by;
                const char *s = text->stringContents.chars;
                int len = text->stringContents.length;

                for (int i = 0; i < len; ) {
                    if (x >= tw || x < 0 || y < 0 || y >= th) break;
                    if (clipped(x, y)) { x++; i++; continue; }

                    /* Decode one UTF-8 codepoint */
                    uint32_t ch;
                    unsigned char c0 = (unsigned char)s[i];
                    if (c0 < 0x80) {
                        ch = c0; i += 1;
                    } else if ((c0 & 0xE0) == 0xC0 && i + 1 < len) {
                        ch = ((c0 & 0x1F) << 6) | (s[i+1] & 0x3F); i += 2;
                    } else if ((c0 & 0xF0) == 0xE0 && i + 2 < len) {
                        ch = ((c0 & 0x0F) << 12) | ((s[i+1] & 0x3F) << 6) | (s[i+2] & 0x3F); i += 3;
                    } else if ((c0 & 0xF8) == 0xF0 && i + 3 < len) {
                        ch = ((c0 & 0x07) << 18) | ((s[i+1] & 0x3F) << 12) | ((s[i+2] & 0x3F) << 6) | (s[i+3] & 0x3F); i += 4;
                    } else {
                        ch = '?'; i += 1;
                    }

                    uintattr_t bg = (buf && x >= 0 && y >= 0 && x < tw && y < th)
                        ? buf[y * tw + x].bg : TB_DEFAULT;
                    tb_set_cell(x, y, ch, fg, bg);
                    x++;
                }
                break;
            }

            case CLAY_RENDER_COMMAND_TYPE_BORDER: {
                Clay_BorderRenderData *border = &cmd->renderData.border;
                uintattr_t fg = rgba_to_tb(border->color);
                uintattr_t bg = TB_DEFAULT;

                /* Top border */
                if (border->width.top > 0) {
                    for (int x = bx + 1; x < bx + bw - 1 && x < tw; x++) {
                        if (x < 0 || by < 0 || by >= th) continue;
                        if (!clipped(x, by))
                            tb_set_cell(x, by, 0x2500, fg, bg); /* ─ */
                    }
                }
                /* Bottom border */
                if (border->width.bottom > 0) {
                    int yb = by + bh - 1;
                    for (int x = bx + 1; x < bx + bw - 1 && x < tw; x++) {
                        if (x < 0 || yb < 0 || yb >= th) continue;
                        if (!clipped(x, yb))
                            tb_set_cell(x, yb, 0x2500, fg, bg); /* ─ */
                    }
                }
                /* Left border */
                if (border->width.left > 0) {
                    for (int y = by + 1; y < by + bh - 1 && y < th; y++) {
                        if (bx < 0 || y < 0) continue;
                        if (!clipped(bx, y))
                            tb_set_cell(bx, y, 0x2502, fg, bg); /* │ */
                    }
                }
                /* Right border */
                if (border->width.right > 0) {
                    int xr = bx + bw - 1;
                    for (int y = by + 1; y < by + bh - 1 && y < th; y++) {
                        if (xr < 0 || xr >= tw || y < 0) continue;
                        if (!clipped(xr, y))
                            tb_set_cell(xr, y, 0x2502, fg, bg); /* │ */
                    }
                }

                /* Corners (only if both adjacent borders exist) */
                int has_top = border->width.top > 0;
                int has_bot = border->width.bottom > 0;
                int has_left = border->width.left > 0;
                int has_right = border->width.right > 0;
                int yb = by + bh - 1;
                int xr = bx + bw - 1;

                if (has_top && has_left && bx >= 0 && by >= 0 && bx < tw && by < th && !clipped(bx, by))
                    tb_set_cell(bx, by, 0x250C, fg, bg);           /* ┌ */
                if (has_top && has_right && xr >= 0 && by >= 0 && xr < tw && by < th && !clipped(xr, by))
                    tb_set_cell(xr, by, 0x2510, fg, bg);           /* ┐ */
                if (has_bot && has_left && bx >= 0 && yb >= 0 && bx < tw && yb < th && !clipped(bx, yb))
                    tb_set_cell(bx, yb, 0x2514, fg, bg);           /* └ */
                if (has_bot && has_right && xr >= 0 && yb >= 0 && xr < tw && yb < th && !clipped(xr, yb))
                    tb_set_cell(xr, yb, 0x2518, fg, bg);           /* ┘ */
                break;
            }

            case CLAY_RENDER_COMMAND_TYPE_SCISSOR_START: {
                push_clip(bx, by, bw, bh);
                break;
            }

            case CLAY_RENDER_COMMAND_TYPE_SCISSOR_END: {
                pop_clip();
                break;
            }

            case CLAY_RENDER_COMMAND_TYPE_IMAGE:
            case CLAY_RENDER_COMMAND_TYPE_CUSTOM:
            default:
                /* Not supported in TUI — silently skip */
                break;
        }
    }
}
