package konpeito.canvas;

import io.github.humbleui.jwm.*;
import io.github.humbleui.jwm.skija.*;
import io.github.humbleui.skija.*;
import io.github.humbleui.types.*;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/**
 * KCanvas - Imperative drawing API wrapping JWM + Skija.
 *
 * Provides a simple command-buffer model:
 *   1. Call open() to set window parameters
 *   2. Call draw*() methods to buffer drawing commands
 *   3. Call show() to create the window and render
 *
 * All methods are static, used from Konpeito via %a{jvm_static} RBS annotation.
 */
public class KCanvas {

    // ========================================================================
    // Callback functional interfaces (used by Konpeito blocks via invokedynamic)
    // ========================================================================

    public interface MouseCallback { void call(double x, double y); }
    public interface KeyCallback { void call(long keyCode); }

    // ========================================================================
    // Internal state
    // ========================================================================

    private static final List<Object[]> commands = new ArrayList<>();
    private static String winTitle = "Konpeito";
    private static int winWidth = 800;
    private static int winHeight = 600;
    private static int bgColor = 0xFFFFFFFF;

    // Event callbacks
    private static MouseCallback clickCallback;
    private static MouseCallback mouseMoveCallback;
    private static KeyCallback keyPressCallback;

    // Command type constants
    private static final String CMD_RECT = "rect";
    private static final String CMD_CIRCLE = "circle";
    private static final String CMD_LINE = "line";
    private static final String CMD_TEXT = "text";
    private static final String CMD_RRECT = "rrect";

    // ========================================================================
    // Public API (called from Konpeito via invokestatic)
    // ========================================================================

    /** Set window title and size. Call before show(). */
    public static void open(String title, int width, int height) {
        winTitle = title;
        winWidth = width;
        winHeight = height;
        commands.clear();
    }

    /** Set background color (ARGB). */
    public static void setBackground(int color) {
        bgColor = color;
    }

    /** Draw a filled rectangle. */
    public static void drawRect(double x, double y, double w, double h, int color) {
        commands.add(new Object[]{CMD_RECT, x, y, w, h, color});
    }

    /** Draw a filled circle. */
    public static void drawCircle(double cx, double cy, double r, int color) {
        commands.add(new Object[]{CMD_CIRCLE, cx, cy, r, color});
    }

    /** Draw a line. */
    public static void drawLine(double x1, double y1, double x2, double y2, int color) {
        commands.add(new Object[]{CMD_LINE, x1, y1, x2, y2, color});
    }

    /** Draw text at the given position. */
    public static void drawText(String text, double x, double y, double fontSize, int color) {
        commands.add(new Object[]{CMD_TEXT, text, x, y, fontSize, color});
    }

    /** Draw a filled rounded rectangle. */
    public static void drawRoundRect(double x, double y, double w, double h, double r, int color) {
        commands.add(new Object[]{CMD_RRECT, x, y, w, h, r, color});
    }

    /** Register a click callback: (double x, double y) -> void */
    public static void setClickCallback(MouseCallback cb) { clickCallback = cb; }

    /** Register a mouse-move callback: (double x, double y) -> void */
    public static void setMouseMoveCallback(MouseCallback cb) { mouseMoveCallback = cb; }

    /** Register a key-press callback: (long keyCode) -> void */
    public static void setKeyPressCallback(KeyCallback cb) { keyPressCallback = cb; }

    /** Create the window, render all buffered commands, and run the event loop. */
    public static void show() {
        App.start(() -> {
            Window window = App.makeWindow();
            window.setTitle(winTitle);
            window.setWindowSize(winWidth, winHeight);

            // Set platform-appropriate Skija rendering layer
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
                        Surface surface = ee.getSurface();
                        io.github.humbleui.skija.Canvas canvas = surface.getCanvas();
                        renderAll(canvas);
                        window.requestFrame();
                    } else if (e instanceof EventMouseButton) {
                        EventMouseButton em = (EventMouseButton) e;
                        if (em.isPressed() && clickCallback != null) {
                            clickCallback.call((double) em.getX(), (double) em.getY());
                            window.requestFrame();
                        }
                    } else if (e instanceof EventMouseMove) {
                        EventMouseMove em = (EventMouseMove) e;
                        if (mouseMoveCallback != null) {
                            mouseMoveCallback.call((double) em.getX(), (double) em.getY());
                            window.requestFrame();
                        }
                    } else if (e instanceof EventKey) {
                        EventKey ek = (EventKey) e;
                        if (ek.isPressed() && keyPressCallback != null) {
                            keyPressCallback.call((long) ek.getKey().ordinal());
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

    // ========================================================================
    // Internal rendering
    // ========================================================================

    private static void renderAll(io.github.humbleui.skija.Canvas canvas) {
        canvas.clear(bgColor);

        for (Object[] cmd : commands) {
            String type = (String) cmd[0];
            switch (type) {
                case CMD_RECT -> {
                    float x = ((Double) cmd[1]).floatValue();
                    float y = ((Double) cmd[2]).floatValue();
                    float w = ((Double) cmd[3]).floatValue();
                    float h = ((Double) cmd[4]).floatValue();
                    int color = (Integer) cmd[5];
                    try (Paint paint = new Paint()) {
                        paint.setColor(color);
                        canvas.drawRect(Rect.makeXYWH(x, y, w, h), paint);
                    }
                }
                case CMD_CIRCLE -> {
                    float cx = ((Double) cmd[1]).floatValue();
                    float cy = ((Double) cmd[2]).floatValue();
                    float r = ((Double) cmd[3]).floatValue();
                    int color = (Integer) cmd[4];
                    try (Paint paint = new Paint()) {
                        paint.setColor(color);
                        canvas.drawCircle(cx, cy, r, paint);
                    }
                }
                case CMD_LINE -> {
                    float x1 = ((Double) cmd[1]).floatValue();
                    float y1 = ((Double) cmd[2]).floatValue();
                    float x2 = ((Double) cmd[3]).floatValue();
                    float y2 = ((Double) cmd[4]).floatValue();
                    int color = (Integer) cmd[5];
                    try (Paint paint = new Paint()) {
                        paint.setColor(color);
                        paint.setMode(PaintMode.STROKE);
                        paint.setStrokeWidth(2.0f);
                        canvas.drawLine(x1, y1, x2, y2, paint);
                    }
                }
                case CMD_TEXT -> {
                    String text = (String) cmd[1];
                    float x = ((Double) cmd[2]).floatValue();
                    float y = ((Double) cmd[3]).floatValue();
                    float fontSize = ((Double) cmd[4]).floatValue();
                    int color = (Integer) cmd[5];
                    try (Paint paint = new Paint();
                         Font font = new Font(Typeface.makeDefault(), fontSize)) {
                        paint.setColor(color);
                        canvas.drawString(text, x, y, font, paint);
                    }
                }
                case CMD_RRECT -> {
                    float x = ((Double) cmd[1]).floatValue();
                    float y = ((Double) cmd[2]).floatValue();
                    float w = ((Double) cmd[3]).floatValue();
                    float h = ((Double) cmd[4]).floatValue();
                    float r = ((Double) cmd[5]).floatValue();
                    int color = (Integer) cmd[6];
                    try (Paint paint = new Paint()) {
                        paint.setColor(color);
                        canvas.drawRRect(RRect.makeXYWH(x, y, w, h, r), paint);
                    }
                }
            }
        }
    }
}
