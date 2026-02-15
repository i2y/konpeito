package konpeito.runtime;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * KFile - File I/O operations for Konpeito JVM backend.
 * Maps to KonpeitoFile Ruby module (JVM-only).
 * Uses java.nio.file.* (Java 7+).
 */
public class KFile {

    /** KonpeitoFile.read(path) -> String */
    public static String read(String path) {
        try {
            return Files.readString(Path.of(path), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new RuntimeException("File read failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoFile.write(path, content) -> String (content) */
    public static String write(String path, String content) {
        try {
            Files.writeString(Path.of(path), content, StandardCharsets.UTF_8);
            return content;
        } catch (IOException e) {
            throw new RuntimeException("File write failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoFile.exist?(path) -> boolean */
    public static boolean exists(String path) {
        return Files.exists(Path.of(path));
    }

    /** KonpeitoFile.delete(path) -> boolean */
    public static boolean delete(String path) {
        try {
            return Files.deleteIfExists(Path.of(path));
        } catch (IOException e) {
            throw new RuntimeException("File delete failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoFile.size(path) -> long */
    public static long size(String path) {
        try {
            return Files.size(Path.of(path));
        } catch (IOException e) {
            throw new RuntimeException("File size failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoFile.readlines(path) -> KArray<String> */
    public static KArray<String> readlines(String path) {
        try {
            List<String> lines = Files.readAllLines(Path.of(path), StandardCharsets.UTF_8);
            KArray<String> result = new KArray<>();
            for (String line : lines) {
                result.add(line);
            }
            return result;
        } catch (IOException e) {
            throw new RuntimeException("File readlines failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoFile.basename(path) -> String */
    public static String basename(String path) {
        Path p = Path.of(path).getFileName();
        return p != null ? p.toString() : "";
    }

    /** KonpeitoFile.dirname(path) -> String */
    public static String dirname(String path) {
        Path p = Path.of(path).getParent();
        return p != null ? p.toString() : ".";
    }

    /** KonpeitoFile.extname(path) -> String */
    public static String extname(String path) {
        String name = Path.of(path).getFileName().toString();
        int dot = name.lastIndexOf('.');
        return dot > 0 ? name.substring(dot) : "";
    }

    /** KonpeitoFile.mkdir(path) -> boolean */
    public static boolean mkdir(String path) {
        try {
            Files.createDirectories(Path.of(path));
            return true;
        } catch (IOException e) {
            throw new RuntimeException("mkdir failed: " + e.getMessage(), e);
        }
    }
}
