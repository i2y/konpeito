package konpeito.runtime;

import java.util.concurrent.LinkedBlockingQueue;

/**
 * KRactorPort - Ruby 4.0 Ractor::Port implementation for JVM backend.
 *
 * Standalone message queue for inter-Ractor communication.
 */
public class KRactorPort {
    private final LinkedBlockingQueue<Object> queue;
    private volatile boolean closed;

    /** Ruby: Ractor::Port.new */
    public KRactorPort() {
        this.queue = new LinkedBlockingQueue<>();
        this.closed = false;
    }

    /** Ruby: port.send(msg) or port << msg */
    public void send(Object msg) {
        if (closed) {
            throw new RuntimeException("can't send to a closed port");
        }
        queue.offer(msg);
    }

    /** Ruby: port.receive */
    public Object receive() {
        try {
            return queue.take();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    /** Ruby: port.close */
    public void close() {
        closed = true;
        queue.clear();
    }

    /** Ruby: port.closed? */
    public boolean isClosed() {
        return closed;
    }

    /** Package-private poll for Ractor.select */
    Object poll() {
        return queue.poll();
    }
}
