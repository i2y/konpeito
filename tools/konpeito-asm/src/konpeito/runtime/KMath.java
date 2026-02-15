package konpeito.runtime;

/**
 * KMath - Math functions for Konpeito JVM backend.
 * Maps to KonpeitoMath Ruby module (JVM-only).
 * Uses java.lang.Math.
 */
public class KMath {

    /** KonpeitoMath.sqrt(x) -> double */
    public static double sqrt(double x) { return Math.sqrt(x); }

    /** KonpeitoMath.sin(x) -> double */
    public static double sin(double x) { return Math.sin(x); }

    /** KonpeitoMath.cos(x) -> double */
    public static double cos(double x) { return Math.cos(x); }

    /** KonpeitoMath.tan(x) -> double */
    public static double tan(double x) { return Math.tan(x); }

    /** KonpeitoMath.log(x) -> double */
    public static double log(double x) { return Math.log(x); }

    /** KonpeitoMath.log10(x) -> double */
    public static double log10(double x) { return Math.log10(x); }

    /** KonpeitoMath.pow(x, y) -> double */
    public static double pow(double x, double y) { return Math.pow(x, y); }

    /** KonpeitoMath.pi -> double */
    public static double pi() { return Math.PI; }

    /** KonpeitoMath.e -> double */
    public static double e() { return Math.E; }

    /** KonpeitoMath.abs(x) -> double */
    public static double abs(double x) { return Math.abs(x); }

    /** KonpeitoMath.floor(x) -> double */
    public static double floor(double x) { return Math.floor(x); }

    /** KonpeitoMath.ceil(x) -> double */
    public static double ceil(double x) { return Math.ceil(x); }

    /** KonpeitoMath.round(x) -> long */
    public static long round(double x) { return Math.round(x); }

    /** KonpeitoMath.min(a, b) -> double */
    public static double min(double a, double b) { return Math.min(a, b); }

    /** KonpeitoMath.max(a, b) -> double */
    public static double max(double a, double b) { return Math.max(a, b); }
}
