package konpeito.runtime;

/**
 * KRubyException - Wrapper for Ruby exceptions on JVM.
 *
 * Carries the Ruby exception class name and supports hierarchy checking
 * for rescue clause matching.
 */
public class KRubyException extends RuntimeException {
    private final String rubyClassName;

    // Ruby exception hierarchy (simplified)
    private static final java.util.Map<String, String> PARENT_MAP = new java.util.HashMap<>();
    static {
        // Standard exception hierarchy
        PARENT_MAP.put("RuntimeError", "StandardError");
        PARENT_MAP.put("ArgumentError", "StandardError");
        PARENT_MAP.put("TypeError", "StandardError");
        PARENT_MAP.put("NameError", "StandardError");
        PARENT_MAP.put("NoMethodError", "NameError");
        PARENT_MAP.put("ZeroDivisionError", "StandardError");
        PARENT_MAP.put("RangeError", "StandardError");
        PARENT_MAP.put("IOError", "StandardError");
        PARENT_MAP.put("StopIteration", "StandardError");
        PARENT_MAP.put("KeyError", "StandardError");
        PARENT_MAP.put("IndexError", "StandardError");
        PARENT_MAP.put("NotImplementedError", "StandardError");
        PARENT_MAP.put("StandardError", "Exception");
        PARENT_MAP.put("Exception", null);
    }

    public KRubyException(String rubyClassName, String message) {
        super(message);
        this.rubyClassName = rubyClassName;
    }

    public KRubyException(String rubyClassName) {
        super(rubyClassName);
        this.rubyClassName = rubyClassName;
    }

    public String getRubyClassName() {
        return rubyClassName;
    }

    /**
     * Register a custom exception class in the hierarchy.
     * Called during class initialization for user-defined exception classes.
     */
    public static void registerExceptionClass(String className, String parentClassName) {
        PARENT_MAP.put(className, parentClassName);
    }

    /**
     * Check if this exception matches the given rescue class name.
     * Walks up the hierarchy to find a match.
     */
    public boolean matchesRescueClass(String rescueClassName) {
        if (rescueClassName == null || rescueClassName.equals("StandardError")) {
            // bare rescue or StandardError catches all standard errors
            return isSubclassOf(rubyClassName, "StandardError");
        }
        return isSubclassOf(rubyClassName, rescueClassName);
    }

    private static boolean isSubclassOf(String className, String targetClass) {
        String current = className;
        while (current != null) {
            if (current.equals(targetClass)) return true;
            current = PARENT_MAP.get(current);
        }
        // If class not in hierarchy, assume it's a subclass of StandardError
        // (user-defined exceptions without explicit registration)
        if (className != null && !PARENT_MAP.containsKey(className)) {
            return targetClass.equals("StandardError") || targetClass.equals("Exception");
        }
        return false;
    }
}
