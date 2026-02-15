package konpeito.runtime;

import java.util.concurrent.Callable;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.List;

/**
 * KRactor - Ruby 4.0 Ractor implementation for JVM backend using Virtual Threads.
 *
 * Each Ractor = Virtual Thread + LinkedBlockingQueue (default port).
 * No true isolation enforcement on JVM (objects shared by reference).
 */
public class KRactor {
    private final Thread thread;
    private final LinkedBlockingQueue<Object> defaultPort;
    private volatile Object result;
    private volatile Throwable error;
    private volatile boolean closed;
    private volatile boolean finished;
    private final String name;
    private final ConcurrentHashMap<String, Object> localStorage;
    private final CopyOnWriteArrayList<KRactorPort> monitors;

    private static final ThreadLocal<KRactor> CURRENT = new ThreadLocal<>();
    private static final KRactor MAIN_RACTOR = new KRactor();

    /** Private constructor for MAIN_RACTOR sentinel */
    private KRactor() {
        this.thread = null;
        this.defaultPort = new LinkedBlockingQueue<>();
        this.closed = false;
        this.finished = false;
        this.name = "main";
        this.localStorage = new ConcurrentHashMap<>();
        this.monitors = new CopyOnWriteArrayList<>();
    }

    /** Ruby: Ractor.new { block } */
    public KRactor(Callable<Object> task) {
        this(task, null);
    }

    /** Ruby: Ractor.new(name: "worker") { block } */
    public KRactor(Callable<Object> task, String name) {
        this.defaultPort = new LinkedBlockingQueue<>();
        this.closed = false;
        this.finished = false;
        this.name = name;
        this.localStorage = new ConcurrentHashMap<>();
        this.monitors = new CopyOnWriteArrayList<>();
        Thread.Builder.OfVirtual builder = Thread.ofVirtual();
        if (name != null) {
            builder = builder.name(name);
        }
        this.thread = builder.start(() -> {
            CURRENT.set(this);
            try {
                result = task.call();
            } catch (Throwable t) {
                error = t;
            } finally {
                finished = true;
                notifyMonitors();
            }
        });
    }

    /** Ruby: ractor.send(msg) or ractor << msg */
    public void send(Object msg) {
        if (closed) {
            throw new RuntimeException("can't send to a closed Ractor");
        }
        defaultPort.offer(msg);
    }

    /** Ruby: Ractor.receive -- receive on current Ractor's default port */
    public static Object receiveOnCurrent() {
        KRactor current = CURRENT.get();
        if (current == null) {
            current = MAIN_RACTOR;
        }
        try {
            return current.defaultPort.take();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    /** Ruby: ractor.join -- wait for Ractor completion */
    public KRactor join() {
        if (thread != null) {
            try {
                thread.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        return this;
    }

    /** Ruby: ractor.value -- wait and return result */
    public Object getValue() {
        join();
        if (error != null) {
            throw new RuntimeException(error);
        }
        return result;
    }

    /** Ruby: ractor.close */
    public void close() {
        closed = true;
    }

    /** Ruby: Ractor.current */
    public static KRactor current() {
        KRactor c = CURRENT.get();
        return c != null ? c : MAIN_RACTOR;
    }

    /** Ruby: Ractor.main */
    public static KRactor main() {
        return MAIN_RACTOR;
    }

    /** Ruby: ractor.name */
    public String getName() {
        return name;
    }

    // ========================================
    // Ractor-local storage
    // ========================================

    /** Ruby: Ractor[:key] */
    public Object getLocal(String key) {
        return localStorage.get(key);
    }

    /** Ruby: Ractor[:key] = value */
    public Object setLocal(String key, Object value) {
        localStorage.put(key, value);
        return value;
    }

    // ========================================
    // Shareable API (compatibility stubs)
    // ========================================

    /** Ruby: Ractor.make_shareable(obj) -- on JVM, all objects are shared by reference */
    public static Object makeSharable(Object obj) {
        return obj;
    }

    /** Ruby: Ractor.shareable?(obj) -- on JVM, all objects are shareable */
    public static boolean isSharable(Object obj) {
        return true;
    }

    // ========================================
    // Monitor API (death notification)
    // ========================================

    /** Ruby: ractor.monitor(port) -- register for death notification */
    public void monitor(KRactorPort port) {
        monitors.add(port);
    }

    /** Ruby: ractor.unmonitor(port) -- unregister from death notification */
    public void unmonitor(KRactorPort port) {
        monitors.remove(port);
    }

    /** Notify all monitors when Ractor terminates */
    private void notifyMonitors() {
        Object reason = error != null ? error.getMessage() : null;
        Object[] notification = new Object[] { this, reason };
        for (KRactorPort port : monitors) {
            try {
                port.send(notification);
            } catch (Exception e) {
                // Ignore errors sending to closed ports
            }
        }
    }

    // ========================================
    // Efficient select using Virtual Thread watchers
    // ========================================

    /**
     * Ruby: Ractor.select(*ports_or_ractors)
     * Uses Virtual Thread watchers for efficient blocking (no polling).
     * Each source gets a watcher thread that blocks on receive.
     * First result goes into a shared queue; remaining watchers are interrupted.
     */
    public static Object[] select(Object[] sources) {
        LinkedBlockingQueue<Object[]> resultQueue = new LinkedBlockingQueue<>(1);
        List<Thread> watchers = new java.util.ArrayList<>(sources.length);

        for (Object src : sources) {
            final Object source = src;
            Thread watcher = Thread.ofVirtual().start(() -> {
                try {
                    Object msg = null;
                    if (source instanceof KRactorPort) {
                        msg = ((KRactorPort) source).receive();
                    } else if (source instanceof KRactor) {
                        msg = ((KRactor) source).defaultPort.take();
                    }
                    if (msg != null) {
                        resultQueue.offer(new Object[] { source, msg });
                    }
                } catch (InterruptedException e) {
                    // Interrupted by another watcher that won
                } catch (Exception e) {
                    // Source error
                }
            });
            watchers.add(watcher);
        }

        try {
            Object[] result = resultQueue.take();
            // Interrupt remaining watchers
            for (Thread w : watchers) {
                if (w.isAlive()) {
                    w.interrupt();
                }
            }
            return result;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            for (Thread w : watchers) {
                w.interrupt();
            }
            return new Object[] { null, null };
        }
    }
}
