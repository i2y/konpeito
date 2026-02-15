package konpeito.runtime;

import java.util.concurrent.Callable;

/**
 * KThread - Ruby Thread implementation for JVM backend using Java 21 Virtual Threads.
 *
 * Maps Ruby's Thread.new { } to Thread.ofVirtual().start().
 * Supports thread.value (join + return value) and thread.join.
 */
public class KThread {
    private final Thread thread;
    private volatile Object result;
    private volatile Throwable error;

    public KThread(Callable<Object> task) {
        this.thread = Thread.ofVirtual().start(() -> {
            try {
                result = task.call();
            } catch (Throwable t) {
                error = t;
            }
        });
    }

    /** Ruby: thread.join — waits for thread completion, returns self */
    public KThread join() {
        try {
            thread.join();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return this;
    }

    /** Ruby: thread.value — waits for thread completion and returns result */
    public Object getValue() {
        join();
        if (error != null) {
            throw new RuntimeException(error);
        }
        return result;
    }

    /** Ruby: thread.alive? */
    public boolean isAlive() {
        return thread.isAlive();
    }
}
