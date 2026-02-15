package konpeito.runtime;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;

/**
 * KTime - Time operations for Konpeito JVM backend.
 * Maps to KonpeitoTime Ruby module (JVM-only).
 * Uses java.time.* (Java 8+).
 */
public class KTime {

    /** KonpeitoTime.now -> String (ISO 8601) */
    public static String now() {
        return Instant.now().toString();
    }

    /** KonpeitoTime.epoch_millis -> long */
    public static long epochMillis() {
        return System.currentTimeMillis();
    }

    /** KonpeitoTime.epoch_nanos -> long (monotonic, for benchmarking) */
    public static long epochNanos() {
        return System.nanoTime();
    }

    /** KonpeitoTime.format(epoch_millis, pattern) -> String */
    public static String format(long epochMillis, String pattern) {
        try {
            Instant instant = Instant.ofEpochMilli(epochMillis);
            ZonedDateTime zdt = instant.atZone(ZoneId.systemDefault());
            DateTimeFormatter formatter = DateTimeFormatter.ofPattern(pattern);
            return zdt.format(formatter);
        } catch (Exception e) {
            throw new RuntimeException("Time format failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoTime.parse(str, pattern) -> long (epoch millis) */
    public static long parse(String str, String pattern) {
        try {
            DateTimeFormatter formatter = DateTimeFormatter.ofPattern(pattern);
            LocalDateTime ldt = LocalDateTime.parse(str, formatter);
            return ldt.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();
        } catch (Exception e) {
            throw new RuntimeException("Time parse failed: " + e.getMessage(), e);
        }
    }
}
