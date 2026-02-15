package konpeito.ui;

import io.github.humbleui.jwm.*;
import io.github.humbleui.jwm.skija.*;
import io.github.humbleui.skija.*;
import io.github.humbleui.types.*;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * KUIRuntime - Frame-callback-based JWM + Skija wrapper for Castella UI.
 *
 * Unlike Canvas.java (command-buffer model), KUIRuntime uses a frame callback:
 *   1. Create a KUIRuntime instance with new KUIRuntime(title, width, height)
 *   2. Register onFrame callback — Ruby side draws here each frame
 *   3. Call run() to start the event loop
 *
 * Drawing methods (fillRect, drawText, etc.) are immediate-mode:
 * they draw directly to the current Skija Canvas during the frame callback.
 *
 * No RBS file needed — all types are auto-introspected from classpath.
 */
public class KUIRuntime {

    // ========================================================================
    // SAM Callback interfaces (auto-detected by ClassIntrospector)
    // ========================================================================

    public interface FrameCallback { void call(); }
    public interface MouseCallback { void call(long type, double x, double y, long button); }
    public interface KeyCallback { void call(long type, long keyCode, long modifiers); }
    public interface TextCallback { void call(String text); }
    public interface ScrollCallback { void call(double x, double y, double dx, double dy); }
    public interface ScrollDeltaCallback { void call(double dx, double dy); }
    public interface ResizeCallback { void call(double width, double height); }
    public interface IMECallback { void call(String text, long selectionStart, long selectionEnd); }

    // ========================================================================
    // Instance state
    // ========================================================================

    private String winTitle;
    private int winWidth;
    private int winHeight;
    private Window window;
    private io.github.humbleui.skija.Canvas skCanvas;

    // Callback holders
    private FrameCallback onFrame;
    private MouseCallback onMouse;
    private KeyCallback onKey;
    private TextCallback onText;
    private ScrollCallback onScroll;
    private ScrollDeltaCallback onScrollDelta;
    private ResizeCallback onResize;
    private IMECallback onIME;

    // Reusable paint + font (avoid per-call allocation)
    private Paint sharedPaint;

    // Image cache
    private HashMap<Integer, Image> imageCache = new HashMap<>();

    // Font fallback: cached FontMgr and typeface lookup cache
    private static FontMgr fontMgr;
    private static final int TYPEFACE_CACHE_SIZE = 4096;
    @SuppressWarnings("serial")
    private static final LinkedHashMap<Long, Typeface> typefaceCache =
        new LinkedHashMap<Long, Typeface>(256, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<Long, Typeface> eldest) {
                return size() > TYPEFACE_CACHE_SIZE;
            }
        };

    // Canvas state save/restore stack depth
    private int saveCount = 0;

    // Off-screen retained surface for differential rendering
    private Surface offscreenSurface;
    private Image cachedSnapshot;
    private boolean needsRedraw = true;


    // ========================================================================
    // Constructor
    // ========================================================================

    public KUIRuntime(String title, int width, int height) {
        this.winTitle = title;
        this.winWidth = width;
        this.winHeight = height;
    }

    // ========================================================================
    // Callback registration
    // ========================================================================

    public void setOnFrame(FrameCallback cb) { this.onFrame = cb; }
    public void setOnMouse(MouseCallback cb) { this.onMouse = cb; }
    public void setOnKey(KeyCallback cb) { this.onKey = cb; }
    public void setOnText(TextCallback cb) { this.onText = cb; }
    public void setOnScroll(ScrollCallback cb) { this.onScroll = cb; }
    public void setOnScrollDelta(ScrollDeltaCallback cb) { this.onScrollDelta = cb; }
    public void setOnResize(ResizeCallback cb) { this.onResize = cb; }
    public void setOnIME(IMECallback cb) { this.onIME = cb; }

    // ========================================================================
    // Immediate-mode drawing (call within onFrame callback)
    // ========================================================================

    /** Clear the canvas with the given ARGB color. */
    public void clear(int color) {
        if (skCanvas != null) skCanvas.clear(color);
    }

    /** Fill a rectangle. */
    public void fillRect(double x, double y, double w, double h, int color) {
        if (skCanvas == null) return;
        if (w < 0) w = 0;
        if (h < 0) h = 0;
        try (Paint p = new Paint()) {
            p.setColor(color);
            skCanvas.drawRect(Rect.makeXYWH((float)x, (float)y, (float)w, (float)h), p);
        }
    }

    /** Stroke a rectangle outline. */
    public void strokeRect(double x, double y, double w, double h, int color, double sw) {
        if (skCanvas == null) return;
        if (w < 0) w = 0;
        if (h < 0) h = 0;
        try (Paint p = new Paint()) {
            p.setColor(color);
            p.setMode(PaintMode.STROKE);
            p.setStrokeWidth((float)sw);
            skCanvas.drawRect(Rect.makeXYWH((float)x, (float)y, (float)w, (float)h), p);
        }
    }

    /** Fill a rounded rectangle. */
    public void fillRoundRect(double x, double y, double w, double h, double r, int color) {
        if (skCanvas == null) return;
        if (w < 0) w = 0;
        if (h < 0) h = 0;
        try (Paint p = new Paint()) {
            p.setColor(color);
            skCanvas.drawRRect(RRect.makeXYWH((float)x, (float)y, (float)w, (float)h, (float)r), p);
        }
    }

    /** Stroke a rounded rectangle outline. */
    public void strokeRoundRect(double x, double y, double w, double h, double r, int color, double sw) {
        if (skCanvas == null) return;
        if (w < 0) w = 0;
        if (h < 0) h = 0;
        try (Paint p = new Paint()) {
            p.setColor(color);
            p.setMode(PaintMode.STROKE);
            p.setStrokeWidth((float)sw);
            skCanvas.drawRRect(RRect.makeXYWH((float)x, (float)y, (float)w, (float)h, (float)r), p);
        }
    }

    /** Fill a circle. */
    public void fillCircle(double cx, double cy, double r, int color) {
        if (skCanvas == null) return;
        try (Paint p = new Paint()) {
            p.setColor(color);
            skCanvas.drawCircle((float)cx, (float)cy, (float)r, p);
        }
    }

    /** Draw a line. */
    public void drawLine(double x1, double y1, double x2, double y2, int color, double w) {
        if (skCanvas == null) return;
        try (Paint p = new Paint()) {
            p.setColor(color);
            p.setMode(PaintMode.STROKE);
            p.setStrokeWidth((float)w);
            skCanvas.drawLine((float)x1, (float)y1, (float)x2, (float)y2, p);
        }
    }

    /** Stroke a circle outline. */
    public void strokeCircle(double cx, double cy, double r, int color, double sw) {
        if (skCanvas == null) return;
        try (Paint p = new Paint()) {
            p.setColor(color);
            p.setMode(PaintMode.STROKE);
            p.setStrokeWidth((float)sw);
            skCanvas.drawCircle((float)cx, (float)cy, (float)r, p);
        }
    }

    /** Fill an arc (pie slice). Angles in degrees, 0=3 o'clock, clockwise. */
    public void fillArc(double cx, double cy, double r, double startAngle, double sweepAngle, int color) {
        if (skCanvas == null) return;
        try (Paint p = new Paint()) {
            p.setColor(color);
            Rect oval = Rect.makeXYWH((float)(cx - r), (float)(cy - r), (float)(r * 2), (float)(r * 2));
            skCanvas.drawArc((float)(cx - r), (float)(cy - r), (float)(cx + r), (float)(cy + r),
                (float)startAngle, (float)sweepAngle, true, p);
        }
    }

    /** Stroke an arc outline (no center lines). Angles in degrees. */
    public void strokeArc(double cx, double cy, double r, double startAngle, double sweepAngle, int color, double sw) {
        if (skCanvas == null) return;
        try (Paint p = new Paint()) {
            p.setColor(color);
            p.setMode(PaintMode.STROKE);
            p.setStrokeWidth((float)sw);
            skCanvas.drawArc((float)(cx - r), (float)(cy - r), (float)(cx + r), (float)(cy + r),
                (float)startAngle, (float)sweepAngle, false, p);
        }
    }

    /** Draw a polyline (connected line segments). xs/ys are interleaved point coordinates. */
    public void drawPolyline(double x1, double y1, double x2, double y2, int color, double sw, int dummy) {
        // Overloaded: single segment version (fallback for iterative calls from Ruby)
        if (skCanvas == null) return;
        try (Paint p = new Paint()) {
            p.setColor(color);
            p.setMode(PaintMode.STROKE);
            p.setStrokeWidth((float)sw);
            p.setAntiAlias(true);
            skCanvas.drawLine((float)x1, (float)y1, (float)x2, (float)y2, p);
        }
    }

    /** Fill a triangle. Used for chart markers and indicators. */
    public void fillTriangle(double x1, double y1, double x2, double y2, double x3, double y3, int color) {
        if (skCanvas == null) return;
        try (Paint p = new Paint();
             Path path = new Path()) {
            p.setColor(color);
            path.moveTo((float)x1, (float)y1);
            path.lineTo((float)x2, (float)y2);
            path.lineTo((float)x3, (float)y3);
            path.closePath();
            skCanvas.drawPath(path, p);
        }
    }

    // ========================================================================
    // Path drawing (for area charts, polygons)
    // ========================================================================

    private Path currentPath = null;

    /** Begin a new path for building filled shapes. */
    public void beginPath() {
        if (currentPath != null) { currentPath.close(); }
        currentPath = new Path();
    }

    /** Move the path cursor to (x, y). */
    public void pathMoveTo(double x, double y) {
        if (currentPath != null) currentPath.moveTo((float)x, (float)y);
    }

    /** Add a line from the current position to (x, y). */
    public void pathLineTo(double x, double y) {
        if (currentPath != null) currentPath.lineTo((float)x, (float)y);
    }

    /** Close the current path and fill it with the given color. */
    public void closeFillPath(int color) {
        if (skCanvas == null || currentPath == null) return;
        currentPath.closePath();
        try (Paint p = new Paint()) {
            p.setColor(color);
            skCanvas.drawPath(currentPath, p);
        }
        currentPath.close();
        currentPath = null;
    }

    /** Fill a path without closing it (for open area fills). */
    public void fillPath(int color) {
        if (skCanvas == null || currentPath == null) return;
        try (Paint p = new Paint()) {
            p.setColor(color);
            skCanvas.drawPath(currentPath, p);
        }
        currentPath.close();
        currentPath = null;
    }

    // ========================================================================
    // Color utilities
    // ========================================================================

    /** Interpolate between two ARGB colors. t in [0.0, 1.0]. */
    public int interpolateColor(int c1, int c2, double t) {
        if (t <= 0.0) return c1;
        if (t >= 1.0) return c2;
        int a1 = (c1 >>> 24) & 0xFF, r1 = (c1 >>> 16) & 0xFF, g1 = (c1 >>> 8) & 0xFF, b1 = c1 & 0xFF;
        int a2 = (c2 >>> 24) & 0xFF, r2 = (c2 >>> 16) & 0xFF, g2 = (c2 >>> 8) & 0xFF, b2 = c2 & 0xFF;
        int a = (int)(a1 + (a2 - a1) * t);
        int r = (int)(r1 + (r2 - r1) * t);
        int g = (int)(g1 + (g2 - g1) * t);
        int b = (int)(b1 + (b2 - b1) * t);
        return (a << 24) | (r << 16) | (g << 8) | b;
    }

    // ========================================================================
    // Font fallback support
    // ========================================================================

    private static FontMgr getFontMgr() {
        if (fontMgr == null) {
            fontMgr = FontMgr.getDefault();
        }
        return fontMgr;
    }

    /** Check if a typeface has a glyph for the given codepoint. */
    private static boolean hasGlyph(Typeface typeface, int codepoint) {
        if (typeface == null) return false;
        return typeface.getUTF32Glyph(codepoint) != 0;
    }

    /** Find a system font that can render the given codepoint. */
    private static Typeface findFallbackTypeface(int codepoint, FontStyle fontStyle) {
        // Cache key: combine codepoint and fontStyle hash
        long key = ((long) codepoint << 32) | (fontStyle.hashCode() & 0xFFFFFFFFL);
        Typeface cached = typefaceCache.get(key);
        if (cached != null) return cached;

        FontMgr fm = getFontMgr();
        Typeface fallback = fm.matchFamilyStyleCharacter(
            null, fontStyle, new String[]{"ja", "zh", "ko", "en"}, codepoint);
        if (fallback != null) {
            typefaceCache.put(key, fallback);
        }
        return fallback;
    }

    /** A text segment with its typeface for rendering. */
    private static class TextSegment {
        final String text;
        final Typeface typeface;
        TextSegment(String text, Typeface typeface) {
            this.text = text;
            this.typeface = typeface;
        }
    }

    /** Segment text into runs of consecutive characters using the same font. */
    private static List<TextSegment> segmentTextByFont(String text, Typeface primaryTypeface, FontStyle fontStyle) {
        List<TextSegment> segments = new ArrayList<>();
        if (text == null || text.isEmpty()) return segments;

        StringBuilder currentText = new StringBuilder();
        Typeface currentTypeface = primaryTypeface;

        int i = 0;
        while (i < text.length()) {
            int codepoint = text.codePointAt(i);
            int charCount = Character.charCount(codepoint);

            Typeface neededTypeface;
            if (hasGlyph(primaryTypeface, codepoint)) {
                neededTypeface = primaryTypeface;
            } else {
                Typeface fallback = findFallbackTypeface(codepoint, fontStyle);
                neededTypeface = (fallback != null) ? fallback : primaryTypeface;
            }

            if (neededTypeface != currentTypeface && currentText.length() > 0) {
                segments.add(new TextSegment(currentText.toString(), currentTypeface));
                currentText = new StringBuilder();
            }
            currentTypeface = neededTypeface;
            currentText.appendCodePoint(codepoint);
            i += charCount;
        }

        if (currentText.length() > 0) {
            segments.add(new TextSegment(currentText.toString(), currentTypeface));
        }
        return segments;
    }

    /** Draw text segments with font fallback, returning total width drawn. */
    private float drawTextWithFallback(String text, float x, float y, Typeface primaryTypeface,
                                        FontStyle fontStyle, float fontSize, Paint paint) {
        List<TextSegment> segments = segmentTextByFont(text, primaryTypeface, fontStyle);
        float cx = x;
        for (TextSegment seg : segments) {
            try (Font font = new Font(seg.typeface, fontSize)) {
                skCanvas.drawString(seg.text, cx, y, font, paint);
                cx += font.measureTextWidth(seg.text);
            }
        }
        return cx - x;
    }

    /** Draw text with font weight and slant support. weight: 0=normal,1=bold. slant: 0=upright,1=italic. */
    public void drawText(String text, double x, double y, String fontFamily, double fontSize, int color, int weight, int slant) {
        if (skCanvas == null) return;
        FontStyle fs = FontStyle.NORMAL;
        if (weight == 1 && slant == 1) fs = FontStyle.BOLD_ITALIC;
        else if (weight == 1) fs = FontStyle.BOLD;
        else if (slant == 1) fs = FontStyle.ITALIC;
        Typeface tf;
        if (fontFamily.equals("default") || fontFamily.isEmpty()) {
            tf = Typeface.makeDefault();
        } else {
            tf = Typeface.makeFromName(fontFamily, fs);
        }
        try (Paint p = new Paint()) {
            p.setColor(color);
            drawTextWithFallback(text, (float)x, (float)y, tf, fs, (float)fontSize, p);
        }
    }

    /** Draw text with font fallback for CJK/emoji support. */
    public void drawText(String text, double x, double y, String fontFamily, double fontSize, int color) {
        if (skCanvas == null) return;
        Typeface tf;
        if (fontFamily.equals("default") || fontFamily.isEmpty()) {
            tf = Typeface.makeDefault();
        } else {
            tf = Typeface.makeFromName(fontFamily, FontStyle.NORMAL);
        }
        try (Paint p = new Paint()) {
            p.setColor(color);
            drawTextWithFallback(text, (float)x, (float)y, tf, FontStyle.NORMAL, (float)fontSize, p);
        }
    }

    // ========================================================================
    // Image operations
    // ========================================================================

    /** Load an image from file path. Returns image ID (>0) or 0 on failure. */
    public int loadImage(String path) {
        int pathHash = path.hashCode();
        if (imageCache.containsKey(pathHash)) return pathHash;
        try {
            byte[] bytes = Files.readAllBytes(Paths.get(path));
            Image img = Image.makeFromEncoded(bytes);
            if (img != null) {
                imageCache.put(pathHash, img);
                return pathHash;
            }
        } catch (Exception e) { /* ignore */ }
        return 0;
    }

    /** Load an image from a network URL. Returns image ID (>0) or 0 on failure.
     *  Downloads the image bytes via HTTP(S) and caches by URL hash. */
    public int loadNetImage(String urlStr) {
        int urlHash = urlStr.hashCode();
        if (imageCache.containsKey(urlHash)) return urlHash;
        try {
            URL url = URI.create(urlStr).toURL();
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            conn.setRequestProperty("User-Agent", "Castella/1.0");
            // Follow redirects
            conn.setInstanceFollowRedirects(true);
            int status = conn.getResponseCode();
            if (status != 200) return 0;
            InputStream is = conn.getInputStream();
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = is.read(buf)) != -1) {
                baos.write(buf, 0, n);
            }
            is.close();
            conn.disconnect();
            byte[] bytes = baos.toByteArray();
            Image img = Image.makeFromEncoded(bytes);
            if (img != null) {
                imageCache.put(urlHash, img);
                return urlHash;
            }
        } catch (Exception e) { /* ignore network errors */ }
        return 0;
    }

    /** Draw a loaded image scaled to fit w x h at position (x,y). */
    public void drawImage(int imageId, double x, double y, double w, double h) {
        if (skCanvas == null) return;
        if (w < 0) w = 0;
        if (h < 0) h = 0;
        Image img = imageCache.get(imageId);
        if (img == null) return;
        try (Paint p = new Paint()) {
            skCanvas.drawImageRect(img,
                Rect.makeXYWH((float)x, (float)y, (float)w, (float)h), p);
        }
    }

    /** Get natural width of loaded image. Returns 0 if not found. */
    public double getImageWidth(int imageId) {
        Image img = imageCache.get(imageId);
        return img != null ? img.getWidth() : 0;
    }

    /** Get natural height of loaded image. Returns 0 if not found. */
    public double getImageHeight(int imageId) {
        Image img = imageCache.get(imageId);
        return img != null ? img.getHeight() : 0;
    }

    // ========================================================================
    // Canvas state operations
    // ========================================================================

    public void save() {
        if (skCanvas != null) {
            skCanvas.save();
            saveCount++;
        }
    }

    public void restore() {
        if (skCanvas != null && saveCount > 0) {
            skCanvas.restore();
            saveCount--;
        }
    }

    public void translate(double dx, double dy) {
        if (skCanvas != null) skCanvas.translate((float)dx, (float)dy);
    }

    public void clipRect(double x, double y, double w, double h) {
        if (skCanvas != null) {
            if (w < 0) w = 0;
            if (h < 0) h = 0;
            skCanvas.clipRect(Rect.makeXYWH((float)x, (float)y, (float)w, (float)h));
        }
    }

    // ========================================================================
    // Text measurement
    // ========================================================================

    private Typeface resolveTypeface(String fontFamily) {
        if (fontFamily.equals("default") || fontFamily.isEmpty()) {
            return Typeface.makeDefault();
        }
        return Typeface.makeFromName(fontFamily, FontStyle.NORMAL);
    }

    public double measureTextWidth(String text, String fontFamily, double fontSize) {
        Typeface primaryTf = resolveTypeface(fontFamily);
        List<TextSegment> segments = segmentTextByFont(text, primaryTf, FontStyle.NORMAL);
        float totalWidth = 0;
        for (TextSegment seg : segments) {
            try (Font font = new Font(seg.typeface, (float)fontSize)) {
                totalWidth += font.measureTextWidth(seg.text);
            }
        }
        return totalWidth;
    }

    public double measureTextHeight(String fontFamily, double fontSize) {
        try (Font font = new Font(resolveTypeface(fontFamily), (float)fontSize)) {
            FontMetrics metrics = font.getMetrics();
            return metrics.getDescent() - metrics.getAscent();
        }
    }

    public double getTextAscent(String fontFamily, double fontSize) {
        try (Font font = new Font(resolveTypeface(fontFamily), (float)fontSize)) {
            FontMetrics metrics = font.getMetrics();
            return -metrics.getAscent(); // Ascent is negative in Skija
        }
    }

    /** Get current time in milliseconds (for animation delta-time calculation). */
    public long currentTimeMillis() {
        return System.currentTimeMillis();
    }

    // ========================================================================
    // Color utility methods (bitwise ops done in Java to avoid JVM verifier issues)
    // ========================================================================

    /** Set alpha channel on an ARGB color. */
    public long withAlpha(long color, long alpha) {
        return (color & 0x00FFFFFFL) | ((alpha & 0xFFL) << 24);
    }

    /** Lighten a color by blending toward white. amount: 0.0=original, 1.0=white. */
    public long lightenColor(long color, double amount) {
        long a = (color >> 24) & 0xFFL;
        long r = (color >> 16) & 0xFFL;
        long g = (color >> 8) & 0xFFL;
        long b = color & 0xFFL;
        r = r + (long)((255 - r) * amount);
        g = g + (long)((255 - g) * amount);
        b = b + (long)((255 - b) * amount);
        if (r > 255) r = 255;
        if (g > 255) g = 255;
        if (b > 255) b = 255;
        return (a << 24) | (r << 16) | (g << 8) | b;
    }

    /** Darken a color by blending toward black. amount: 0.0=original, 1.0=black. */
    public long darkenColor(long color, double amount) {
        long a = (color >> 24) & 0xFFL;
        long r = (color >> 16) & 0xFFL;
        long g = (color >> 8) & 0xFFL;
        long b = color & 0xFFL;
        r = (long)(r * (1.0 - amount));
        g = (long)(g * (1.0 - amount));
        b = (long)(b * (1.0 - amount));
        if (r < 0) r = 0;
        if (g < 0) g = 0;
        if (b < 0) b = 0;
        return (a << 24) | (r << 16) | (g << 8) | b;
    }

    /** Convert a numeric value to its integer string representation. */
    public String numberToString(double value) {
        return Long.toString((long) value);
    }

    // ========================================================================
    // Math helper methods (Java.lang.Math wrappers for JVM-compiled Ruby)
    // ========================================================================

    public double mathCos(double radians) { return Math.cos(radians); }
    public double mathSin(double radians) { return Math.sin(radians); }
    public double mathSqrt(double value)  { return Math.sqrt(value); }
    public double mathAtan2(double y, double x) { return Math.atan2(y, x); }
    public double mathAbs(double value) { return Math.abs(value); }

    // ========================================================================
    // Window queries
    // ========================================================================

    public double getWidth() {
        if (window != null) return window.getContentRectAbsolute().getWidth();
        return winWidth;
    }

    public double getHeight() {
        if (window != null) return window.getContentRectAbsolute().getHeight();
        return winHeight;
    }

    public double getScale() {
        if (window != null) return window.getScreen().getScale();
        return 1.0;
    }

    public void requestFrame() {
        if (window != null) {
            window.requestFrame();
        }
    }

    /** Check if the OS is using dark mode (macOS supported). Defaults to true. */
    public boolean isDarkMode() {
        try {
            return io.github.humbleui.jwm.Theme.isDark();
        } catch (Throwable e) {
            return true;
        }
    }

    /** Mark the off-screen surface as dirty, triggering re-render on next frame. */
    public void markDirty() {
        this.needsRedraw = true;
    }

    // ========================================================================
    // IME / Text Input control
    // ========================================================================

    /** Enable or disable IME text input on the window. */
    public void setTextInputEnabled(boolean enabled) {
        if (window != null) {
            window.setTextInputEnabled(enabled);
        }
    }

    /** Set the IME cursor rect for candidate window positioning. */
    public void setTextInputRect(int x, int y, int w, int h) {
        if (window != null) {
            window.setTextInputClient(new TextInputClient() {
                @Override
                public IRect getRectForMarkedRange(int selectionStart, int selectionEnd) {
                    return IRect.makeXYWH(x, y, w, h);
                }
            });
        }
    }

    // ========================================================================
    // Clipboard
    // ========================================================================

    /** Get text from system clipboard. Returns empty string if unavailable. */
    public String getClipboardText() {
        try {
            ClipboardEntry entry = Clipboard.get(ClipboardFormat.TEXT);
            if (entry != null) {
                return entry.getString();
            }
        } catch (Exception e) { /* ignore clipboard errors */ }
        return "";
    }

    /** Set text to system clipboard. */
    public void setClipboardText(String text) {
        try {
            Clipboard.set(ClipboardEntry.makePlainText(text));
        } catch (Exception e) { /* ignore clipboard errors */ }
    }

    // ========================================================================
    // Event loop
    // ========================================================================

    public void run() {
        final KUIRuntime self = this;

        App.start(() -> {
            window = App.makeWindow();
            window.setTitle(self.winTitle);
            window.setWindowSize(self.winWidth, self.winHeight);

            // Platform-appropriate Skija rendering layer
            String os = System.getProperty("os.name", "").toLowerCase();
            if (os.contains("mac")) {
                window.setLayer(new LayerMetalSkija());
            } else if (os.contains("win")) {
                window.setLayer(new LayerD3D12Skija());
            } else {
                window.setLayer(new LayerGLSkija());
            }

            window.setEventListener(new Consumer<Event>() {
                @Override
                public void accept(Event e) {
                    if (e instanceof EventFrameSkija) {
                        EventFrameSkija ee = (EventFrameSkija) e;
                        Surface screenSurface = ee.getSurface();
                        io.github.humbleui.skija.Canvas screenCanvas = screenSurface.getCanvas();

                        int sw = screenSurface.getWidth();
                        int sh = screenSurface.getHeight();

                        // Create or resize off-screen surface
                        if (self.offscreenSurface == null ||
                            self.offscreenSurface.getWidth() != sw ||
                            self.offscreenSurface.getHeight() != sh) {
                            if (self.cachedSnapshot != null) {
                                self.cachedSnapshot.close();
                                self.cachedSnapshot = null;
                            }
                            if (self.offscreenSurface != null) {
                                self.offscreenSurface.close();
                            }
                            self.offscreenSurface = Surface.makeRasterN32Premul(sw, sh);
                            self.needsRedraw = true;
                        }

                        // Re-render to off-screen surface only when dirty
                        if (self.needsRedraw) {
                            self.needsRedraw = false;  // Clear BEFORE callback so mark_dirty() can re-set it
                            self.skCanvas = self.offscreenSurface.getCanvas();
                            self.saveCount = 0;
                            if (self.onFrame != null) {
                                self.onFrame.call();
                            }
                            // Cache snapshot for blitting
                            if (self.cachedSnapshot != null) {
                                self.cachedSnapshot.close();
                            }
                            self.cachedSnapshot = self.offscreenSurface.makeImageSnapshot();
                        }

                        // Always blit cached snapshot to screen (back buffer is ephemeral)
                        if (self.cachedSnapshot != null) {
                            screenCanvas.drawImage(self.cachedSnapshot, 0, 0);
                        }
                        // If animation set needsRedraw during frame, request another frame
                        if (self.needsRedraw) {
                            window.requestFrame();
                        }
                    } else if (e instanceof EventMouseButton) {
                        EventMouseButton em = (EventMouseButton) e;
                        if (self.onMouse != null) {
                            long type = em.isPressed() ? 1 : 2;
                            self.onMouse.call(type, (double) em.getX(), (double) em.getY(),
                                              (long) em.getButton().ordinal());
                            window.requestFrame();
                        }
                    } else if (e instanceof EventMouseScroll) {
                        EventMouseScroll es = (EventMouseScroll) e;
                        if (self.onScrollDelta != null) {
                            self.onScrollDelta.call(es.getDeltaX(), es.getDeltaY());
                            window.requestFrame();
                        } else if (self.onScroll != null) {
                            self.onScroll.call((double) es.getX(), (double) es.getY(),
                                               es.getDeltaX(), es.getDeltaY());
                            window.requestFrame();
                        }
                    } else if (e instanceof EventMouseMove) {
                        EventMouseMove em = (EventMouseMove) e;
                        if (self.onMouse != null) {
                            self.onMouse.call(0, (double) em.getX(), (double) em.getY(), 0);
                            window.requestFrame();
                        }
                    } else if (e instanceof EventKey) {
                        EventKey ek = (EventKey) e;
                        if (self.onKey != null) {
                            long type = ek.isPressed() ? 1 : 2;
                            long mods = 0;
                            if (ek.isModifierDown(KeyModifier.SHIFT))       mods |= 1;
                            if (ek.isModifierDown(KeyModifier.CONTROL))     mods |= 2;
                            if (ek.isModifierDown(KeyModifier.ALT))         mods |= 4;
                            if (ek.isModifierDown(KeyModifier.MAC_COMMAND)) mods |= 8;
                            self.onKey.call(type, (long) ek.getKey().ordinal(), mods);
                            window.requestFrame();
                        }
                    } else if (e instanceof EventTextInput) {
                        EventTextInput et = (EventTextInput) e;
                        if (self.onText != null) {
                            self.onText.call(et.getText());
                            window.requestFrame();
                        }
                    } else if (e instanceof EventTextInputMarked) {
                        EventTextInputMarked et = (EventTextInputMarked) e;
                        if (self.onIME != null) {
                            self.onIME.call(et.getText(),
                                (long) et.getSelectionStart(), (long) et.getSelectionEnd());
                            window.requestFrame();
                        }
                    } else if (e instanceof EventWindowResize) {
                        if (self.onResize != null) {
                            self.onResize.call(self.getWidth(), self.getHeight());
                            window.requestFrame();
                        }
                    } else if (e instanceof EventWindowCloseRequest) {
                        window.close();
                        App.terminate();
                    }
                }
            });

            window.setVisible(true);
            window.requestFrame();
        });
    }
}
