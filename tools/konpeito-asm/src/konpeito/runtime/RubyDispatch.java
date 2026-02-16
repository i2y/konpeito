package konpeito.runtime;

import java.lang.invoke.*;
import java.lang.reflect.Method;

/**
 * RubyDispatch - Bootstrap method for invokedynamic-based Ruby method dispatch.
 *
 * When the Konpeito AOT compiler cannot statically resolve a method call
 * (receiver type is unknown at compile time), it emits an invokedynamic
 * instruction that delegates to this class. At runtime, the JVM calls
 * the bootstrap method once per call site, which returns a CallSite
 * wrapping a generic dispatch method. The dispatch method uses reflection
 * to find and invoke the correct method on the actual receiver object.
 *
 * This is analogous to Objective-C's objc_msgSend: AOT compilation with
 * dynamic dispatch for unresolved calls. The JVM's JIT compiler can
 * further optimize these call sites based on runtime type profiles.
 */
public class RubyDispatch {

    /**
     * Ruby operator/method name → Java method name aliases.
     * When the sanitized Ruby name doesn't match a Java method, try these fallbacks.
     * jvm_method_name() converts: [] → op_aref, []= → op_aset, << → op_lshift,
     * empty? → empty_q, include? → include_q, etc.
     */
    private static final java.util.Map<String, String[]> RUBY_NAME_ALIASES = new java.util.HashMap<>();
    static {
        // Operator aliases
        RUBY_NAME_ALIASES.put("op_aref", new String[]{"get"});
        RUBY_NAME_ALIASES.put("op_aset", new String[]{"set", "put"});
        RUBY_NAME_ALIASES.put("op_lshift", new String[]{"push", "add"});

        // Ruby ? methods (sanitized with _q suffix)
        RUBY_NAME_ALIASES.put("empty_q", new String[]{"isEmpty_", "isEmpty"});
        RUBY_NAME_ALIASES.put("include_q", new String[]{"includes", "contains"});
        RUBY_NAME_ALIASES.put("has_key_q", new String[]{"hasKey", "containsKey"});
        RUBY_NAME_ALIASES.put("has_value_q", new String[]{"hasValue", "containsValue"});
        RUBY_NAME_ALIASES.put("nil_q", new String[]{"isNil"});
        RUBY_NAME_ALIASES.put("alive_q", new String[]{"isAlive"});

        // Ruby ! methods (sanitized with _bang suffix)
        RUBY_NAME_ALIASES.put("merge_bang", new String[]{"mergeInPlace"});

        // Underscore methods mapped to camelCase
        RUBY_NAME_ALIASES.put("delete_at", new String[]{"deleteAt"});
        RUBY_NAME_ALIASES.put("find_index", new String[]{"findIndex"});
        RUBY_NAME_ALIASES.put("each_key", new String[]{"eachKeys"});
        RUBY_NAME_ALIASES.put("each_value", new String[]{"eachValues"});
        RUBY_NAME_ALIASES.put("sum_long", new String[]{"sumLong"});
        RUBY_NAME_ALIASES.put("sum_double", new String[]{"sumDouble"});
        RUBY_NAME_ALIASES.put("delete_value", new String[]{"deleteValue"});

        // Standard Ruby → Java mappings
        RUBY_NAME_ALIASES.put("to_s", new String[]{"toString"});
        RUBY_NAME_ALIASES.put("to_a", new String[]{"toArray_"});

        // Reserved name aliases (jvm_method_name mangles these)
        RUBY_NAME_ALIASES.put("k_class", new String[]{"getClass"});

        // Hash: keys/values → Ruby-specific methods returning KArray
        RUBY_NAME_ALIASES.put("keys", new String[]{"rubyKeys"});
        RUBY_NAME_ALIASES.put("values", new String[]{"rubyValues"});
    }

    /**
     * Bootstrap method — called once per call site by the JVM.
     *
     * The invokedynamic instruction's name is the Ruby method name,
     * and the type describes (Object receiver, Object arg1, ...) -> Object.
     */
    public static CallSite bootstrap(MethodHandles.Lookup lookup, String methodName,
                                     MethodType type) throws Exception {
        MethodHandle dispatch = lookup.findStatic(
            RubyDispatch.class, "dispatch",
            MethodType.methodType(Object.class, String.class, Object[].class));

        // Bind the method name as the first argument
        dispatch = MethodHandles.insertArguments(dispatch, 0, methodName);

        // Collect all invokedynamic params into Object[] for dispatch
        dispatch = dispatch.asCollector(Object[].class, type.parameterCount());

        // Adapt to match the call site type
        dispatch = dispatch.asType(type);

        return new ConstantCallSite(dispatch);
    }

    /**
     * Generic dispatch — called at every invocation.
     * args[0] = receiver, args[1..] = method arguments
     */
    public static Object dispatch(String methodName, Object[] args) throws Throwable {
        if (args.length == 0 || args[0] == null) {
            throw new NullPointerException("Method '" + methodName + "' called on null receiver");
        }

        Object receiver = args[0];
        Object[] methodArgs = new Object[args.length - 1];
        System.arraycopy(args, 1, methodArgs, 0, methodArgs.length);

        Class<?> clazz = receiver.getClass();

        // Built-in operator handling for primitive boxed types (Long, Double, Boolean, String)
        // These don't have op_* methods, so handle them directly
        Object builtinResult = tryBuiltinOperator(methodName, receiver, methodArgs);
        if (builtinResult != SENTINEL) {
            return builtinResult;
        }

        // Find method by name and arity (Ruby doesn't have overloading by type)
        Method found = findMethod(clazz, methodName, methodArgs.length);

        // If not found, try Ruby name aliases (op_aref → get, empty_q → isEmpty_, etc.)
        if (found == null) {
            String[] aliases = RUBY_NAME_ALIASES.get(methodName);
            if (aliases != null) {
                for (String alias : aliases) {
                    found = findMethod(clazz, alias, methodArgs.length);
                    if (found != null) break;
                }
            }
        }

        // If still not found, try snake_case → camelCase conversion (Ruby → Java convention)
        if (found == null && methodName.contains("_")) {
            String camelName = snakeToCamel(methodName);
            found = findMethod(clazz, camelName, methodArgs.length);
        }

        if (found != null) {
            found.setAccessible(true);
            Object[] adapted = adaptArgs(found, methodArgs);
            Object result = found.invoke(receiver, adapted);
            return boxResult(result, found.getReturnType());
        }

        // Handle array indexing: Object[].op_aref(index)
        if (receiver.getClass().isArray() && methodName.equals("op_aref") && methodArgs.length == 1) {
            int idx = ((Number) methodArgs[0]).intValue();
            Object[] arr = (Object[]) receiver;
            if (idx < 0) idx = arr.length + idx;
            return arr[idx];
        }

        throw new NoSuchMethodError(
            clazz.getName() + "." + methodName + " (arity " + methodArgs.length + ")");
    }

    // Sentinel object to indicate "no built-in handler found"
    private static final Object SENTINEL = new Object();

    /**
     * Handle built-in operators on Long, Double, Boolean, String.
     * Returns SENTINEL if no built-in handler applies.
     */
    private static Object tryBuiltinOperator(String methodName, Object receiver, Object[] args) {
        // Long (Integer) arithmetic operators
        if (receiver instanceof Long) {
            long lv = (Long) receiver;
            if (args.length == 1 && args[0] instanceof Number) {
                long rv = ((Number) args[0]).longValue();
                switch (methodName) {
                    case "op_plus": return Long.valueOf(lv + rv);
                    case "op_minus": return Long.valueOf(lv - rv);
                    case "op_mul": return Long.valueOf(lv * rv);
                    case "op_div": return Long.valueOf(lv / rv);
                    case "op_mod": return Long.valueOf(lv % rv);
                    case "op_and": return Long.valueOf(lv & rv);
                    case "op_or": return Long.valueOf(lv | rv);
                    case "op_xor": return Long.valueOf(lv ^ rv);
                    case "op_lshift": return Long.valueOf(lv << rv);
                    case "op_rshift": return Long.valueOf(lv >> rv);
                    case "op_eq": return Boolean.valueOf(lv == rv);
                    case "op_neq": return Boolean.valueOf(lv != rv);
                    case "op_lt": return Boolean.valueOf(lv < rv);
                    case "op_gt": return Boolean.valueOf(lv > rv);
                    case "op_le": return Boolean.valueOf(lv <= rv);
                    case "op_ge": return Boolean.valueOf(lv >= rv);
                    case "op_spaceship": case "op_cmp": return Long.valueOf(Long.compare(lv, rv));
                }
            }
            if (args.length == 0) {
                switch (methodName) {
                    case "to_s": return Long.toString(lv);
                    case "to_f": return Double.valueOf((double) lv);
                    case "abs": return Long.valueOf(Math.abs(lv));
                    case "even_q": return Boolean.valueOf(lv % 2 == 0);
                    case "odd_q": return Boolean.valueOf(lv % 2 != 0);
                    case "zero_q": return Boolean.valueOf(lv == 0);
                    case "positive_q": return Boolean.valueOf(lv > 0);
                    case "negative_q": return Boolean.valueOf(lv < 0);
                }
            }
        }

        // Double (Float) arithmetic operators
        if (receiver instanceof Double) {
            double dv = (Double) receiver;
            if (args.length == 1 && args[0] instanceof Number) {
                double rv = ((Number) args[0]).doubleValue();
                switch (methodName) {
                    case "op_plus": return Double.valueOf(dv + rv);
                    case "op_minus": return Double.valueOf(dv - rv);
                    case "op_mul": return Double.valueOf(dv * rv);
                    case "op_div": return Double.valueOf(dv / rv);
                    case "op_eq": return Boolean.valueOf(dv == rv);
                    case "op_neq": return Boolean.valueOf(dv != rv);
                    case "op_lt": return Boolean.valueOf(dv < rv);
                    case "op_gt": return Boolean.valueOf(dv > rv);
                    case "op_le": return Boolean.valueOf(dv <= rv);
                    case "op_ge": return Boolean.valueOf(dv >= rv);
                    case "op_spaceship": case "op_cmp": return Long.valueOf(Double.compare(dv, rv));
                }
            }
            if (args.length == 0) {
                switch (methodName) {
                    case "to_s": return Double.toString(dv);
                    case "to_i": return Long.valueOf((long) dv);
                    case "abs": return Double.valueOf(Math.abs(dv));
                    case "zero_q": return Boolean.valueOf(dv == 0.0);
                    case "positive_q": return Boolean.valueOf(dv > 0.0);
                    case "negative_q": return Boolean.valueOf(dv < 0.0);
                }
            }
        }

        // Boolean operators
        if (receiver instanceof Boolean) {
            boolean bv = (Boolean) receiver;
            if (args.length == 0) {
                switch (methodName) {
                    case "to_s": return Boolean.toString(bv);
                    case "op_not": return Boolean.valueOf(!bv);
                }
            }
            if (args.length == 1) {
                switch (methodName) {
                    case "op_eq": return Boolean.valueOf(bv == Boolean.TRUE.equals(args[0]));
                    case "op_neq": return Boolean.valueOf(bv != Boolean.TRUE.equals(args[0]));
                }
            }
        }

        // String methods
        if (receiver instanceof String) {
            String sv = (String) receiver;

            // String comparison and concatenation operators
            if (args.length == 1 && args[0] instanceof String) {
                String rv = (String) args[0];
                switch (methodName) {
                    case "op_eq": return Boolean.valueOf(sv.equals(rv));
                    case "op_neq": return Boolean.valueOf(!sv.equals(rv));
                    case "op_spaceship": case "op_cmp": return Long.valueOf(sv.compareTo(rv));
                    case "op_plus": return sv + rv;
                    case "split": {
                        // Return KArray instead of String[]
                        String[] parts = sv.split(java.util.regex.Pattern.quote(rv), -1);
                        KArray arr = new KArray();
                        for (String part : parts) arr.push(part);
                        return arr;
                    }
                    case "include_q": return Boolean.valueOf(sv.contains(rv));
                    case "start_with_q": return Boolean.valueOf(sv.startsWith(rv));
                    case "end_with_q": return Boolean.valueOf(sv.endsWith(rv));
                }
            }

            // String#[](start, length) → substring
            if (methodName.equals("op_aref")) {
                if (args.length == 2 && args[0] instanceof Number && args[1] instanceof Number) {
                    int start = ((Number) args[0]).intValue();
                    int len = ((Number) args[1]).intValue();
                    if (start < 0) start = sv.length() + start;
                    if (start < 0 || start >= sv.length()) return "";
                    int end = Math.min(start + len, sv.length());
                    return sv.substring(start, end);
                }
                if (args.length == 1 && args[0] instanceof Number) {
                    int idx = ((Number) args[0]).intValue();
                    if (idx < 0) idx = sv.length() + idx;
                    if (idx < 0 || idx >= sv.length()) return null;
                    return String.valueOf(sv.charAt(idx));
                }
            }

            // No-arg String methods
            if (args.length == 0) {
                switch (methodName) {
                    case "length": return Long.valueOf(sv.length());
                    case "size": return Long.valueOf(sv.length());
                    case "strip": return sv.strip();
                    case "upcase": return sv.toUpperCase();
                    case "downcase": return sv.toLowerCase();
                    case "reverse": return new StringBuilder(sv).reverse().toString();
                    case "empty_q": return Boolean.valueOf(sv.isEmpty());
                    case "to_s": return sv;
                    case "to_i": {
                        try { return Long.parseLong(sv.strip()); }
                        catch (NumberFormatException e) { return Long.valueOf(0); }
                    }
                    case "to_f": {
                        try { return Double.parseDouble(sv.strip()); }
                        catch (NumberFormatException e) { return Double.valueOf(0.0); }
                    }
                }
            }

            // String + non-String (convert to string first)
            if (args.length == 1 && methodName.equals("op_plus")) {
                return sv + String.valueOf(args[0]);
            }
        }

        return SENTINEL;
    }

    /**
     * Convert snake_case to camelCase.
     * "clip_rect" → "clipRect", "get_width" → "getWidth"
     */
    private static String snakeToCamel(String snake) {
        StringBuilder sb = new StringBuilder();
        boolean capitalizeNext = false;
        for (int i = 0; i < snake.length(); i++) {
            char c = snake.charAt(i);
            if (c == '_') {
                capitalizeNext = true;
            } else {
                if (capitalizeNext) {
                    sb.append(Character.toUpperCase(c));
                    capitalizeNext = false;
                } else {
                    sb.append(c);
                }
            }
        }
        return sb.toString();
    }

    /**
     * Find a method by name and arity on the given class.
     * Returns null if not found.
     */
    private static Method findMethod(Class<?> clazz, String name, int arity) {
        for (Method m : clazz.getMethods()) {
            if (m.getName().equals(name) && m.getParameterCount() == arity) {
                return m;
            }
        }
        return null;
    }

    /**
     * Convert Object args to match method parameter types.
     * Handles Long↔int/long, Double↔double conversions needed because
     * Konpeito uses long for Integer and double for Float, but Java
     * methods may use int parameters.
     */
    private static Object[] adaptArgs(Method method, Object[] args) {
        Class<?>[] paramTypes = method.getParameterTypes();
        Object[] adapted = new Object[args.length];
        for (int i = 0; i < args.length; i++) {
            if (i < paramTypes.length && args[i] != null) {
                adapted[i] = convertArg(args[i], paramTypes[i]);
            } else {
                adapted[i] = args[i];
            }
        }
        return adapted;
    }

    private static Object convertArg(Object arg, Class<?> target) {
        if (target == long.class) {
            if (arg instanceof Long) return arg;
            if (arg instanceof Number) return ((Number) arg).longValue();
        }
        if (target == int.class && arg instanceof Number) {
            return ((Number) arg).intValue();
        }
        if (target == double.class) {
            if (arg instanceof Double) return arg;
            if (arg instanceof Number) return ((Number) arg).doubleValue();
        }
        if (target == float.class && arg instanceof Number) {
            return ((Number) arg).floatValue();
        }
        if (target == boolean.class && arg instanceof Boolean) {
            return arg;
        }
        return arg;
    }

    /**
     * Box primitive return values.
     * Converts Java int returns to long (Konpeito convention: Integer = long).
     * Wraps array returns in KArray for Ruby compatibility.
     */
    private static Object boxResult(Object result, Class<?> returnType) {
        if (returnType == void.class) return null;
        if (returnType == int.class && result instanceof Integer) {
            return Long.valueOf(((Integer) result).longValue());
        }
        // Wrap array results in KArray (e.g. String.split returns String[])
        if (result != null && result.getClass().isArray()) {
            KArray arr = new KArray();
            if (result instanceof Object[]) {
                for (Object item : (Object[]) result) {
                    arr.push(item);
                }
            }
            return arr;
        }
        return result;
    }
}
