package konpeito.runtime;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * KCrypto - Cryptographic operations for Konpeito JVM backend.
 * Maps to KonpeitoCrypto Ruby module.
 * Uses java.security.* and javax.crypto.* (no external dependencies).
 */
public class KCrypto {

    private static final SecureRandom SECURE_RANDOM = new SecureRandom();
    private static final char[] HEX_CHARS = "0123456789abcdef".toCharArray();

    // ========================================================================
    // Hash Functions
    // ========================================================================

    /** KonpeitoCrypto.sha256(data) -> String (hex) */
    public static String sha256(String data) {
        return hexDigest("SHA-256", data);
    }

    /** KonpeitoCrypto.sha512(data) -> String (hex) */
    public static String sha512(String data) {
        return hexDigest("SHA-512", data);
    }

    /** KonpeitoCrypto.sha256_binary(data) -> String (binary via ISO-8859-1) */
    public static String sha256Binary(String data) {
        return binaryDigest("SHA-256", data);
    }

    /** KonpeitoCrypto.sha512_binary(data) -> String (binary via ISO-8859-1) */
    public static String sha512Binary(String data) {
        return binaryDigest("SHA-512", data);
    }

    // ========================================================================
    // HMAC
    // ========================================================================

    /** KonpeitoCrypto.hmac_sha256(key, data) -> String (hex) */
    public static String hmacSha256(String key, String data) {
        return hexHmac("HmacSHA256", key, data);
    }

    /** KonpeitoCrypto.hmac_sha512(key, data) -> String (hex) */
    public static String hmacSha512(String key, String data) {
        return hexHmac("HmacSHA512", key, data);
    }

    /** KonpeitoCrypto.hmac_sha256_binary(key, data) -> String (binary) */
    public static String hmacSha256Binary(String key, String data) {
        return binaryHmac("HmacSHA256", key, data);
    }

    // ========================================================================
    // Random
    // ========================================================================

    /** KonpeitoCrypto.random_bytes(count) -> String (binary via ISO-8859-1) */
    public static String randomBytes(long count) {
        byte[] bytes = new byte[(int) Math.min(count, Integer.MAX_VALUE)];
        SECURE_RANDOM.nextBytes(bytes);
        return new String(bytes, StandardCharsets.ISO_8859_1);
    }

    /** KonpeitoCrypto.random_hex(count) -> String (hex, 2*count chars) */
    public static String randomHex(long count) {
        byte[] bytes = new byte[(int) Math.min(count, Integer.MAX_VALUE)];
        SECURE_RANDOM.nextBytes(bytes);
        return bytesToHex(bytes);
    }

    // ========================================================================
    // Comparison
    // ========================================================================

    /** KonpeitoCrypto.secure_compare(a, b) -> boolean (constant-time) */
    public static boolean secureCompare(String a, String b) {
        byte[] aBytes = a.getBytes(StandardCharsets.UTF_8);
        byte[] bBytes = b.getBytes(StandardCharsets.UTF_8);
        if (aBytes.length != bBytes.length) return false;
        int result = 0;
        for (int i = 0; i < aBytes.length; i++) {
            result |= aBytes[i] ^ bBytes[i];
        }
        return result == 0;
    }

    // ========================================================================
    // Internal Helpers
    // ========================================================================

    private static String hexDigest(String algorithm, String data) {
        try {
            MessageDigest md = MessageDigest.getInstance(algorithm);
            byte[] hash = md.digest(data.getBytes(StandardCharsets.UTF_8));
            return bytesToHex(hash);
        } catch (Exception e) {
            throw new RuntimeException("Digest failed: " + e.getMessage(), e);
        }
    }

    private static String binaryDigest(String algorithm, String data) {
        try {
            MessageDigest md = MessageDigest.getInstance(algorithm);
            byte[] hash = md.digest(data.getBytes(StandardCharsets.UTF_8));
            return new String(hash, StandardCharsets.ISO_8859_1);
        } catch (Exception e) {
            throw new RuntimeException("Digest failed: " + e.getMessage(), e);
        }
    }

    private static String hexHmac(String algorithm, String key, String data) {
        try {
            Mac mac = Mac.getInstance(algorithm);
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), algorithm));
            byte[] hash = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            return bytesToHex(hash);
        } catch (Exception e) {
            throw new RuntimeException("HMAC failed: " + e.getMessage(), e);
        }
    }

    private static String binaryHmac(String algorithm, String key, String data) {
        try {
            Mac mac = Mac.getInstance(algorithm);
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), algorithm));
            byte[] hash = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            return new String(hash, StandardCharsets.ISO_8859_1);
        } catch (Exception e) {
            throw new RuntimeException("HMAC failed: " + e.getMessage(), e);
        }
    }

    private static String bytesToHex(byte[] bytes) {
        char[] hex = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int v = bytes[i] & 0xFF;
            hex[i * 2] = HEX_CHARS[v >>> 4];
            hex[i * 2 + 1] = HEX_CHARS[v & 0x0F];
        }
        return new String(hex);
    }
}
