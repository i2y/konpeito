package konpeito.runtime;

import java.util.concurrent.Callable;
import java.util.concurrent.SynchronousQueue;

/**
 * KFiber - Ruby Fiber implementation for JVM backend using Java 21 Virtual Threads.
 *
 * Uses a pair of SynchronousQueues for handshake between caller and fiber:
 * - resumeQueue: caller sends resume value to fiber
 * - yieldQueue: fiber sends yielded value to caller
 *
 * ThreadLocal tracks the current fiber for Fiber.yield().
 */
public class KFiber {
    private static final ThreadLocal<KFiber> currentFiber = new ThreadLocal<>();

    // Sentinel object to distinguish null/nil yield values from "no value"
    private static final Object SENTINEL = new Object();

    private final Callable<Object> body;
    private final SynchronousQueue<Object> resumeQueue = new SynchronousQueue<>();
    private final SynchronousQueue<Object> yieldQueue = new SynchronousQueue<>();
    private Thread thread;
    private volatile boolean alive = true;
    private volatile boolean started = false;

    public KFiber(Callable<Object> body) {
        this.body = body;
    }

    /**
     * Ruby: fiber.resume or fiber.resume(value)
     * Starts the fiber on first call, resumes it on subsequent calls.
     * Returns the value passed to Fiber.yield or the fiber's final return value.
     */
    public Object resume(Object value) {
        try {
            if (!started) {
                started = true;
                thread = Thread.ofVirtual().start(() -> {
                    currentFiber.set(this);
                    try {
                        Object result = body.call();
                        // Fiber completed: send final result
                        yieldQueue.put(result != null ? result : SENTINEL);
                    } catch (Exception e) {
                        try {
                            yieldQueue.put(SENTINEL);
                        } catch (InterruptedException ie) {
                            Thread.currentThread().interrupt();
                        }
                    } finally {
                        alive = false;
                        currentFiber.remove();
                    }
                });
            } else {
                // Send resume value to fiber
                resumeQueue.put(value != null ? value : SENTINEL);
            }
            // Wait for fiber to yield or complete
            Object result = yieldQueue.take();
            return result == SENTINEL ? null : result;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    /** Ruby: fiber.resume (no args) */
    public Object resume() {
        return resume(null);
    }

    /**
     * Ruby: Fiber.yield(value)
     * Called from within a fiber to suspend execution and send a value to the caller.
     * Returns the value passed to the next resume() call.
     */
    public static Object fiberYield(Object value) {
        KFiber fiber = currentFiber.get();
        if (fiber == null) {
            throw new RuntimeException("Fiber.yield called outside of a fiber");
        }
        try {
            // Send yielded value to caller
            fiber.yieldQueue.put(value != null ? value : SENTINEL);
            // Wait for next resume
            Object resumeValue = fiber.resumeQueue.take();
            return resumeValue == SENTINEL ? null : resumeValue;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    /** Ruby: Fiber.yield (no args) */
    public static Object fiberYield() {
        return fiberYield(null);
    }

    /** Ruby: fiber.alive? */
    public boolean isAlive() {
        return alive;
    }

    /** Ruby: Fiber.current */
    public static KFiber current() {
        return currentFiber.get();
    }
}
