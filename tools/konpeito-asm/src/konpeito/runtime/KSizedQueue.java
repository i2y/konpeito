package konpeito.runtime;

import java.util.concurrent.ArrayBlockingQueue;

/**
 * KSizedQueue - Ruby SizedQueue implementation for JVM backend.
 *
 * Wraps ArrayBlockingQueue to provide Ruby's SizedQueue semantics:
 * - push blocks when queue is full
 * - pop blocks when queue is empty
 */
public class KSizedQueue {
    private final ArrayBlockingQueue<Object> queue;
    private final int maxSize;

    public KSizedQueue(int max) {
        this.maxSize = max;
        this.queue = new ArrayBlockingQueue<>(max);
    }

    /** Ruby: sq.push(value) — blocks if full */
    public void push(Object value) {
        try {
            queue.put(value);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** Ruby: sq.pop — blocks if empty */
    public Object pop() {
        try {
            return queue.take();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    /** Ruby: sq.max — returns maximum queue size */
    public int max() {
        return maxSize;
    }

    /** Ruby: sq.size — returns current queue size */
    public int size() {
        return queue.size();
    }
}
