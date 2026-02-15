package konpeito.runtime;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.Deflater;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;
import java.util.zip.Inflater;

/**
 * KCompression - Data compression for Konpeito JVM backend.
 * Maps to KonpeitoCompression Ruby module.
 * Uses java.util.zip.* (no external dependencies).
 *
 * Binary data is encoded as ISO-8859-1 strings for lossless round-tripping.
 */
public class KCompression {

    public static final long BEST_SPEED = 1;
    public static final long BEST_COMPRESSION = 9;
    public static final long DEFAULT_COMPRESSION = -1;

    // ========================================================================
    // Gzip (RFC 1952)
    // ========================================================================

    /** KonpeitoCompression.gzip(data) -> String (binary) */
    public static String gzip(String data) {
        try {
            byte[] input = data.getBytes(StandardCharsets.UTF_8);
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            try (GZIPOutputStream gzos = new GZIPOutputStream(baos)) {
                gzos.write(input);
            }
            return new String(baos.toByteArray(), StandardCharsets.ISO_8859_1);
        } catch (Exception e) {
            throw new RuntimeException("gzip failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoCompression.gunzip(data) -> String */
    public static String gunzip(String data) {
        try {
            byte[] input = data.getBytes(StandardCharsets.ISO_8859_1);
            ByteArrayInputStream bais = new ByteArrayInputStream(input);
            try (GZIPInputStream gzis = new GZIPInputStream(bais)) {
                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                byte[] buffer = new byte[4096];
                int n;
                while ((n = gzis.read(buffer)) != -1) {
                    baos.write(buffer, 0, n);
                }
                return baos.toString(StandardCharsets.UTF_8);
            }
        } catch (Exception e) {
            throw new RuntimeException("gunzip failed: " + e.getMessage(), e);
        }
    }

    // ========================================================================
    // Raw Deflate (RFC 1951)
    // ========================================================================

    /** KonpeitoCompression.deflate(data, level) -> String (binary) */
    public static String deflate(String data, Object level) {
        try {
            int compressionLevel = Deflater.DEFAULT_COMPRESSION;
            if (level instanceof Long) {
                compressionLevel = ((Long) level).intValue();
            } else if (level instanceof Integer) {
                compressionLevel = (Integer) level;
            }
            byte[] input = data.getBytes(StandardCharsets.UTF_8);
            Deflater deflater = new Deflater(compressionLevel, true); // true = raw deflate (no zlib header)
            deflater.setInput(input);
            deflater.finish();
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            while (!deflater.finished()) {
                int count = deflater.deflate(buffer);
                baos.write(buffer, 0, count);
            }
            deflater.end();
            return new String(baos.toByteArray(), StandardCharsets.ISO_8859_1);
        } catch (Exception e) {
            throw new RuntimeException("deflate failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoCompression.inflate(data) -> String */
    public static String inflate(String data) {
        try {
            byte[] input = data.getBytes(StandardCharsets.ISO_8859_1);
            Inflater inflater = new Inflater(true); // true = raw inflate (no zlib header)
            inflater.setInput(input);
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            while (!inflater.finished()) {
                int count = inflater.inflate(buffer);
                if (count == 0 && inflater.needsInput()) break;
                baos.write(buffer, 0, count);
            }
            inflater.end();
            return baos.toString(StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new RuntimeException("inflate failed: " + e.getMessage(), e);
        }
    }

    // ========================================================================
    // Zlib (RFC 1950) - with zlib header
    // ========================================================================

    /** KonpeitoCompression.zlib_compress(data) -> String (binary) */
    public static String zlibCompress(String data) {
        try {
            byte[] input = data.getBytes(StandardCharsets.UTF_8);
            Deflater deflater = new Deflater(); // default: zlib format (with header)
            deflater.setInput(input);
            deflater.finish();
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            while (!deflater.finished()) {
                int count = deflater.deflate(buffer);
                baos.write(buffer, 0, count);
            }
            deflater.end();
            return new String(baos.toByteArray(), StandardCharsets.ISO_8859_1);
        } catch (Exception e) {
            throw new RuntimeException("zlib_compress failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoCompression.zlib_decompress(data, maxSize) -> String */
    public static String zlibDecompress(String data, Object maxSize) {
        try {
            long maxBytes = 100 * 1024 * 1024; // 100MB default
            if (maxSize instanceof Long) {
                maxBytes = (Long) maxSize;
            } else if (maxSize instanceof Integer) {
                maxBytes = (Integer) maxSize;
            }
            byte[] input = data.getBytes(StandardCharsets.ISO_8859_1);
            Inflater inflater = new Inflater(); // default: zlib format (with header)
            inflater.setInput(input);
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            long totalBytes = 0;
            while (!inflater.finished()) {
                int count = inflater.inflate(buffer);
                if (count == 0 && inflater.needsInput()) break;
                totalBytes += count;
                if (totalBytes > maxBytes) {
                    inflater.end();
                    throw new RuntimeException("Decompressed data exceeds max size: " + maxBytes);
                }
                baos.write(buffer, 0, count);
            }
            inflater.end();
            return baos.toString(StandardCharsets.UTF_8);
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException("zlib_decompress failed: " + e.getMessage(), e);
        }
    }
}
