package konpeito.runtime;

import java.util.concurrent.locks.ReentrantLock;

/**
 * KConditionVariable - Ruby ConditionVariable implementation for JVM backend.
 *
 * Uses an Object monitor internally. When await(mutex) is called, the caller's
 * mutex is released (matching Ruby cv.wait(mutex) semantics), then we wait on
 * the internal monitor, and reacquire the mutex before returning.
 */
public class KConditionVariable {
    private final Object monitor = new Object();

    /** Ruby: cv.wait(mutex) — releases mutex, waits for signal, reacquires mutex */
    public void await(ReentrantLock mutex) {
        // Release the caller's mutex (Ruby CV#wait semantics)
        mutex.unlock();
        synchronized (monitor) {
            try {
                monitor.wait();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        // Reacquire the caller's mutex before returning
        mutex.lock();
    }

    /** Ruby: cv.signal — wakes one waiting thread */
    public void signal() {
        synchronized (monitor) {
            monitor.notify();
        }
    }

    /** Ruby: cv.broadcast — wakes all waiting threads */
    public void broadcast() {
        synchronized (monitor) {
            monitor.notifyAll();
        }
    }
}
