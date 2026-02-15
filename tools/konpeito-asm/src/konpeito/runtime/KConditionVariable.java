package konpeito.runtime;

import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

/**
 * KConditionVariable - Ruby ConditionVariable implementation for JVM backend.
 *
 * Uses an internal ReentrantLock + Condition pair.
 * Note: In Ruby, ConditionVariable can be used with any Mutex.
 * This simplified implementation uses its own internal lock.
 */
public class KConditionVariable {
    private final ReentrantLock lock = new ReentrantLock();
    private final Condition condition = lock.newCondition();

    /** Ruby: cv.wait(mutex) — waits for signal */
    public void await() {
        lock.lock();
        try {
            condition.await();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } finally {
            lock.unlock();
        }
    }

    /** Ruby: cv.signal — wakes one waiting thread */
    public void signal() {
        lock.lock();
        try {
            condition.signal();
        } finally {
            lock.unlock();
        }
    }

    /** Ruby: cv.broadcast — wakes all waiting threads */
    public void broadcast() {
        lock.lock();
        try {
            condition.signalAll();
        } finally {
            lock.unlock();
        }
    }
}
