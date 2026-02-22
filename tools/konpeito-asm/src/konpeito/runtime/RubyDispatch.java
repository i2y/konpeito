package konpeito.runtime;

import java.lang.invoke.*;
import java.lang.reflect.Method;
import java.util.Map;

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
        if (args.length == 0) {
            throw new NullPointerException("Method '" + methodName + "' called with no arguments");
        }

        Object receiver = args[0];
        Object[] methodArgs = new Object[args.length - 1];
        System.arraycopy(args, 1, methodArgs, 0, methodArgs.length);

        // Handle nil (null) receiver — Ruby's NilClass methods and Kernel methods
        if (receiver == null) {
            Object nilResult = tryNilDispatch(methodName, methodArgs);
            if (nilResult != SENTINEL) {
                return nilResult;
            }
            // Kernel methods (top-level functions with null receiver)
            if (methodName.equals("Integer") && methodArgs.length >= 1) {
                Object arg = methodArgs[0];
                if (arg instanceof Long) return arg;
                if (arg instanceof Double) return Long.valueOf(((Double) arg).longValue());
                if (arg instanceof String) {
                    String s = ((String) arg).strip();
                    if (s.startsWith("0x") || s.startsWith("0X")) {
                        return Long.parseLong(s.substring(2), 16);
                    }
                    return Long.parseLong(s);
                }
                throw new IllegalArgumentException("invalid value for Integer(): \"" + arg + "\"");
            }
            if (methodName.equals("Float") && methodArgs.length >= 1) {
                Object arg = methodArgs[0];
                if (arg instanceof Double) return arg;
                if (arg instanceof Long) return Double.valueOf(((Long) arg).doubleValue());
                if (arg instanceof String) {
                    String s = ((String) arg).strip();
                    return Double.parseDouble(s);
                }
                throw new IllegalArgumentException("invalid value for Float(): \"" + arg + "\"");
            }
            // Kernel#sleep
            if (methodName.equals("sleep") && methodArgs.length >= 1) {
                double seconds;
                if (methodArgs[0] instanceof Long) {
                    seconds = ((Long) methodArgs[0]).doubleValue();
                } else if (methodArgs[0] instanceof Double) {
                    seconds = (Double) methodArgs[0];
                } else if (methodArgs[0] instanceof Number) {
                    seconds = ((Number) methodArgs[0]).doubleValue();
                } else {
                    seconds = 0;
                }
                try {
                    Thread.sleep((long) (seconds * 1000));
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                return Long.valueOf((long) seconds);
            }
            // Kernel#rand
            if (methodName.equals("rand")) {
                if (methodArgs.length == 0) {
                    return Math.random();
                } else if (methodArgs[0] instanceof Long) {
                    return Long.valueOf((long)(Math.random() * (Long) methodArgs[0]));
                }
                return Math.random();
            }
            throw new NullPointerException("Method '" + methodName + "' called on null receiver");
        }

        Class<?> clazz = receiver.getClass();

        // Handle Ruby exception methods on Java Throwable/Exception objects
        if (receiver instanceof KRubyException) {
            KRubyException kexc = (KRubyException) receiver;
            switch (methodName) {
                case "message":
                    String kmsg = kexc.getMessage();
                    return kmsg != null ? kmsg : "";
                case "to_s":
                    String kts = kexc.getMessage();
                    return kts != null ? kts : kexc.getRubyClassName();
                case "k_class":
                    return kexc.getRubyClassName();
                case "inspect":
                    String kim = kexc.getMessage();
                    return "#<" + kexc.getRubyClassName() + ": " + (kim != null ? kim : "") + ">";
                case "backtrace":
                    return null;
            }
        }
        if (receiver instanceof Throwable) {
            Throwable throwable = (Throwable) receiver;
            switch (methodName) {
                case "message":
                    String msg = throwable.getMessage();
                    return msg != null ? msg : "";
                case "to_s":
                    String ts = throwable.getMessage();
                    return ts != null ? ts : throwable.getClass().getSimpleName();
                case "k_class":
                    // Map Java exception class to Ruby exception name
                    String className = throwable.getClass().getSimpleName();
                    if (className.equals("RuntimeException")) return "RuntimeError";
                    if (className.equals("Exception")) return "StandardError";
                    return className;
                case "inspect":
                    String im = throwable.getMessage();
                    return "#<" + throwable.getClass().getSimpleName() + ": " + (im != null ? im : "") + ">";
                case "backtrace":
                    return null; // Ruby returns nil for backtrace in simple cases
            }
        }

        // Built-in operator handling for primitive boxed types (Long, Double, Boolean, String)
        // These don't have op_* methods, so handle them directly
        Object builtinResult = tryBuiltinOperator(methodName, receiver, methodArgs);
        if (builtinResult != SENTINEL) {
            return builtinResult;
        }

        // KArray#sort with block: sort { |a, b| ... }
        if (receiver instanceof KArray && methodName.equals("sort") && methodArgs.length == 1) {
            Object block = methodArgs[0];
            @SuppressWarnings("unchecked")
            KArray<Object> arr = (KArray<Object>) receiver;
            KArray<Object> result = new KArray<>(arr);
            // Find the call method once before sorting
            Method[] blockMethods = block.getClass().getMethods();
            Method blockCallMethod = null;
            for (Method m : blockMethods) {
                if (m.getName().equals("call") && m.getParameterCount() == 2) {
                    blockCallMethod = m;
                    break;
                }
            }
            if (blockCallMethod == null) {
                // Try getDeclaredMethods for interface methods
                for (Class<?> iface : block.getClass().getInterfaces()) {
                    for (Method m : iface.getMethods()) {
                        if (m.getName().equals("call") && m.getParameterCount() == 2) {
                            blockCallMethod = m;
                            break;
                        }
                    }
                    if (blockCallMethod != null) break;
                }
            }
            final Method sortBlockCall = blockCallMethod;
            result.sort((a, b) -> {
                try {
                    sortBlockCall.setAccessible(true);
                    Object cmpResult = sortBlockCall.invoke(block, a, b);
                    if (cmpResult instanceof Long) return ((Long) cmpResult).intValue();
                    if (cmpResult instanceof Integer) return (Integer) cmpResult;
                    return 0;
                } catch (Exception e) {
                    throw new RuntimeException("sort block invocation failed", e);
                }
            });
            return result;
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

        // Comparable methods: between?, clamp — delegate to <=> if available
        if (methodName.equals("between_q") && methodArgs.length == 2) {
            Method spaceship = findMethod(clazz, "op_cmp", 1);
            if (spaceship != null) {
                spaceship.setAccessible(true);
                long cmpLo = ((Number) spaceship.invoke(receiver, methodArgs[0])).longValue();
                long cmpHi = ((Number) spaceship.invoke(receiver, methodArgs[1])).longValue();
                return Boolean.valueOf(cmpLo >= 0 && cmpHi <= 0);
            }
        }

        if (methodName.equals("clamp") && methodArgs.length == 2) {
            Method spaceship = findMethod(clazz, "op_cmp", 1);
            if (spaceship != null) {
                spaceship.setAccessible(true);
                long cmpLo = ((Number) spaceship.invoke(receiver, methodArgs[0])).longValue();
                if (cmpLo < 0) return methodArgs[0]; // below min → return min
                long cmpHi = ((Number) spaceship.invoke(receiver, methodArgs[1])).longValue();
                if (cmpHi > 0) return methodArgs[1]; // above max → return max
                return receiver; // in range → return self
            }
        }

        throw new NoSuchMethodError(
            clazz.getName() + "." + methodName + " (arity " + methodArgs.length + ")");
    }

    // Sentinel object to indicate "no built-in handler found"
    private static final Object SENTINEL = new Object();

    /**
     * Handle methods called on nil (null receiver) — Ruby's NilClass.
     * Returns SENTINEL if no handler applies.
     */
    private static Object tryNilDispatch(String methodName, Object[] args) {
        switch (methodName) {
            case "op_eq":
                // nil == nil is true; nil == anything_else is false
                return Boolean.valueOf(args.length == 1 && args[0] == null);
            case "op_neq":
                // nil != nil is false; nil != anything_else is true
                return Boolean.valueOf(args.length != 1 || args[0] != null);
            case "to_s":
                return "";
            case "to_i":
                return Long.valueOf(0);
            case "to_f":
                return Double.valueOf(0.0);
            case "to_a":
                return new KArray<>();
            case "inspect":
                return "nil";
            case "nil_q":
                return Boolean.TRUE;
            case "k_class":
                return "NilClass";
            case "frozen_q":
                return Boolean.TRUE;
            case "freeze":
                return null;
            case "is_a_q": case "kind_of_q": case "instance_of_q":
                if (args.length == 1) {
                    String cn = classNameOf(args[0]);
                    if ("NilClass".equals(cn) || "Object".equals(cn) || "BasicObject".equals(cn))
                        return Boolean.TRUE;
                    return Boolean.FALSE;
                }
                return Boolean.FALSE;
            case "respond_to_q":
                if (args.length == 1) {
                    String mn = args[0] instanceof String ? (String) args[0] : String.valueOf(args[0]);
                    switch (mn) {
                        case "nil?": case "to_s": case "inspect": case "to_a": case "to_i": case "to_f":
                        case "==": case "!=": case "class": case "frozen?": case "is_a?": case "kind_of?":
                            return Boolean.TRUE;
                    }
                    return Boolean.FALSE;
                }
                return Boolean.FALSE;
        }
        return SENTINEL;
    }

    /**
     * Handle built-in operators on Long, Double, Boolean, String.
     * Returns SENTINEL if no built-in handler applies.
     */
    private static Object tryBuiltinOperator(String methodName, Object receiver, Object[] args) {
        // Long (Integer) arithmetic operators
        if (receiver instanceof Long) {
            long lv = (Long) receiver;
            // Null-safe equality: Long == null => false
            if (args.length == 1 && args[0] == null) {
                switch (methodName) {
                    case "op_eq": return Boolean.FALSE;
                    case "op_neq": return Boolean.TRUE;
                }
            }
            // is_a? / kind_of? / instance_of? — check class identity
            if ((methodName.equals("is_a_q") || methodName.equals("kind_of_q") || methodName.equals("instance_of_q"))
                && args.length == 1) {
                String className = classNameOf(args[0]);
                if (className != null) {
                    switch (className) {
                        case "Integer": case "Numeric": case "Comparable": case "Object": case "BasicObject":
                            return Boolean.TRUE;
                        default:
                            return Boolean.FALSE;
                    }
                }
            }
            if (args.length == 1 && args[0] instanceof Number) {
                long rv = ((Number) args[0]).longValue();
                switch (methodName) {
                    case "op_plus": return Long.valueOf(lv + rv);
                    case "op_minus": return Long.valueOf(lv - rv);
                    case "op_mul": return Long.valueOf(lv * rv);
                    case "op_div": return Long.valueOf(lv / rv);
                    case "op_mod": return Long.valueOf(lv % rv);
                    case "op_pow": return Long.valueOf((long) Math.pow(lv, rv));
                    case "divmod": {
                        KArray<Object> result = new KArray<>();
                        result.push(Long.valueOf(Math.floorDiv(lv, rv)));
                        result.push(Long.valueOf(Math.floorMod(lv, rv)));
                        return result;
                    }
                    case "gcd": return Long.valueOf(gcd(Math.abs(lv), Math.abs(rv)));
                    case "lcm": {
                        long g = gcd(Math.abs(lv), Math.abs(rv));
                        return Long.valueOf(g == 0 ? 0 : Math.abs(lv / g * rv));
                    }
                    case "op_and": return Long.valueOf(lv & rv);
                    case "op_or": return Long.valueOf(lv | rv);
                    case "op_xor": return Long.valueOf(lv ^ rv);
                    case "op_lshift": return Long.valueOf(lv << rv);
                    case "op_rshift": return Long.valueOf(lv >> rv);
                    case "op_aref": return Long.valueOf((lv >> rv) & 1);
                    case "op_eq": return Boolean.valueOf(lv == rv);
                    case "op_neq": return Boolean.valueOf(lv != rv);
                    case "op_lt": return Boolean.valueOf(lv < rv);
                    case "op_gt": return Boolean.valueOf(lv > rv);
                    case "op_le": return Boolean.valueOf(lv <= rv);
                    case "op_ge": return Boolean.valueOf(lv >= rv);
                    case "op_spaceship": case "op_cmp": return Long.valueOf(Long.compare(lv, rv));
                }
            }
            // Integer ** Float => Float
            if (args.length == 1 && args[0] instanceof Double && methodName.equals("op_pow")) {
                return Double.valueOf(Math.pow(lv, (Double) args[0]));
            }
            if (args.length == 0) {
                switch (methodName) {
                    case "to_s": return Long.toString(lv);
                    case "to_f": return Double.valueOf((double) lv);
                    case "to_i": return receiver;
                    case "to_int": return receiver;
                    case "abs": return Long.valueOf(Math.abs(lv));
                    case "even_q": return Boolean.valueOf(lv % 2 == 0);
                    case "odd_q": return Boolean.valueOf(lv % 2 != 0);
                    case "zero_q": return Boolean.valueOf(lv == 0);
                    case "positive_q": return Boolean.valueOf(lv > 0);
                    case "negative_q": return Boolean.valueOf(lv < 0);
                    case "inspect": return Long.toString(lv);
                    case "k_class": return "Integer";
                    case "nil_q": return Boolean.FALSE;
                    case "chr": return String.valueOf((char) lv);
                    case "frozen_q": return Boolean.TRUE;
                    case "freeze": return receiver;
                    case "respond_to_q": return Boolean.TRUE; // all common methods exist
                    case "integer_q": return Boolean.TRUE;
                    case "op_uminus": return Long.valueOf(-lv);
                    case "op_uplus": return receiver;
                    case "digits": {
                        // Integer#digits — returns array of digits in reverse order (base 10)
                        KArray<Object> result = new KArray<>();
                        long val = Math.abs(lv);
                        if (val == 0) { result.add(0L); return result; }
                        while (val > 0) {
                            result.add(Long.valueOf(val % 10));
                            val /= 10;
                        }
                        return result;
                    }
                }
            }
        }

        // Double (Float) arithmetic operators
        if (receiver instanceof Double) {
            double dv = (Double) receiver;
            // Null-safe equality: Double == null => false
            if (args.length == 1 && args[0] == null) {
                switch (methodName) {
                    case "op_eq": return Boolean.FALSE;
                    case "op_neq": return Boolean.TRUE;
                }
            }
            // is_a? / kind_of? / instance_of?
            if ((methodName.equals("is_a_q") || methodName.equals("kind_of_q") || methodName.equals("instance_of_q"))
                && args.length == 1) {
                String className = classNameOf(args[0]);
                if (className != null) {
                    switch (className) {
                        case "Float": case "Numeric": case "Comparable": case "Object": case "BasicObject":
                            return Boolean.TRUE;
                        default:
                            return Boolean.FALSE;
                    }
                }
            }
            if (args.length == 1 && args[0] instanceof Number) {
                double rv = ((Number) args[0]).doubleValue();
                switch (methodName) {
                    case "op_plus": return Double.valueOf(dv + rv);
                    case "op_minus": return Double.valueOf(dv - rv);
                    case "op_mul": return Double.valueOf(dv * rv);
                    case "op_div": return Double.valueOf(dv / rv);
                    case "op_pow": return Double.valueOf(Math.pow(dv, rv));
                    case "op_mod": return Double.valueOf(dv % rv);
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
                    case "to_int": return Long.valueOf((long) dv);
                    case "to_f": return receiver;
                    case "abs": return Double.valueOf(Math.abs(dv));
                    case "zero_q": return Boolean.valueOf(dv == 0.0);
                    case "positive_q": return Boolean.valueOf(dv > 0.0);
                    case "negative_q": return Boolean.valueOf(dv < 0.0);
                    case "ceil": return Long.valueOf((long) Math.ceil(dv));
                    case "floor": return Long.valueOf((long) Math.floor(dv));
                    case "round": {
                        // Ruby uses round-half-away-from-zero
                        if (dv >= 0) {
                            return Long.valueOf((long) Math.floor(dv + 0.5));
                        } else {
                            return Long.valueOf((long) Math.ceil(dv - 0.5));
                        }
                    }
                    case "infinite_q":
                        if (dv == Double.POSITIVE_INFINITY) return Long.valueOf(1);
                        if (dv == Double.NEGATIVE_INFINITY) return Long.valueOf(-1);
                        return null;
                    case "nan_q": return Boolean.valueOf(Double.isNaN(dv));
                    case "inspect": return Double.toString(dv);
                    case "k_class": return "Float";
                    case "nil_q": return Boolean.FALSE;
                    case "frozen_q": return Boolean.TRUE;
                    case "freeze": return receiver;
                    case "finite_q": return Boolean.valueOf(!Double.isInfinite(dv) && !Double.isNaN(dv));
                    case "integer_q": return Boolean.valueOf(dv == Math.floor(dv) && !Double.isInfinite(dv) && !Double.isNaN(dv));
                    case "op_uminus": return Double.valueOf(-dv);
                    case "op_uplus": return receiver;
                }
            }
        }

        // Boolean operators
        if (receiver instanceof Boolean) {
            boolean bv = (Boolean) receiver;
            if (args.length == 0) {
                switch (methodName) {
                    case "to_s": return Boolean.toString(bv);
                    case "inspect": return Boolean.toString(bv);
                    case "op_not": return Boolean.valueOf(!bv);
                    case "nil_q": return Boolean.FALSE;
                    case "k_class": return bv ? "TrueClass" : "FalseClass";
                    case "frozen_q": return Boolean.TRUE;
                    case "freeze": return receiver;
                }
            }
            if (args.length == 1) {
                switch (methodName) {
                    case "op_eq":
                        // false == nil => false; true == nil => false
                        if (args[0] == null) return Boolean.FALSE;
                        return Boolean.valueOf(bv == Boolean.TRUE.equals(args[0]));
                    case "op_neq":
                        // false != nil => true; true != nil => true
                        if (args[0] == null) return Boolean.TRUE;
                        return Boolean.valueOf(bv != Boolean.TRUE.equals(args[0]));
                    case "is_a_q": case "kind_of_q": case "instance_of_q": {
                        String className = classNameOf(args[0]);
                        if (className != null) {
                            if (className.equals("TrueClass") && bv) return Boolean.TRUE;
                            if (className.equals("FalseClass") && !bv) return Boolean.TRUE;
                            if (className.equals("Object") || className.equals("BasicObject")) return Boolean.TRUE;
                            return Boolean.FALSE;
                        }
                    }
                }
            }
        }

        // String methods
        if (receiver instanceof String) {
            String sv = (String) receiver;

            // Null-safe equality: String == null => false
            if (args.length == 1 && args[0] == null) {
                switch (methodName) {
                    case "op_eq": return Boolean.FALSE;
                    case "op_neq": return Boolean.TRUE;
                }
            }

            // is_a? / kind_of? / instance_of?
            if ((methodName.equals("is_a_q") || methodName.equals("kind_of_q") || methodName.equals("instance_of_q"))
                && args.length == 1) {
                String className = classNameOf(args[0]);
                if (className != null) {
                    // Range-as-string: is_a?(Range) should return true
                    if (isRangeString(sv)) {
                        if ("Range".equals(className) || "Object".equals(className) || "BasicObject".equals(className) || "Enumerable".equals(className))
                            return Boolean.TRUE;
                        return Boolean.FALSE;
                    }
                    switch (className) {
                        case "String": case "Comparable": case "Object": case "BasicObject":
                            return Boolean.TRUE;
                        default:
                            return Boolean.FALSE;
                    }
                }
            }

            // Range operations on Range-as-String — handle BEFORE string-specific methods
            // to ensure size/length etc. return range-specific results
            if (isRangeString(sv)) {
                if (methodName.equals("include_q") && args.length == 1) {
                    return rangeInclude(sv, args[0]);
                }
                if (methodName.equals("size") && args.length == 0) {
                    return rangeSize(sv);
                }
                if (methodName.equals("length") && args.length == 0) {
                    return rangeSize(sv);
                }
                if (methodName.equals("min") && args.length == 0) {
                    return rangeMin(sv);
                }
                if (methodName.equals("max") && args.length == 0) {
                    return rangeMax(sv);
                }
                if (methodName.equals("first") && args.length == 0) {
                    return rangeMin(sv);
                }
                if (methodName.equals("last") && args.length == 0) {
                    return rangeMax(sv);
                }
                if (methodName.equals("k_class") && args.length == 0) {
                    return "Range";
                }
                if (methodName.equals("to_s") && args.length == 0) {
                    return sv; // Range#to_s returns "start..end"
                }
                if (methodName.equals("inspect") && args.length == 0) {
                    return sv;
                }
                if (methodName.equals("each") && args.length == 0) {
                    return rangeToArray(sv);
                }
            }

            // String comparison and concatenation operators
            if (args.length == 1 && args[0] instanceof String) {
                String rv = (String) args[0];
                switch (methodName) {
                    case "op_eq": return Boolean.valueOf(sv.equals(rv));
                    case "op_neq": return Boolean.valueOf(!sv.equals(rv));
                    case "op_spaceship": case "op_cmp": return Long.valueOf(sv.compareTo(rv));
                    case "op_plus": return sv + rv;
                    case "op_mul": {
                        // String * n handled below with Number arg
                        break;
                    }
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
                    case "count": return Long.valueOf(stringCount(sv, rv));
                    case "delete": return stringDelete(sv, rv);
                    case "squeeze": return stringSqueeze(sv, rv);
                    case "chomp": {
                        // String#chomp(separator)
                        if (sv.endsWith(rv)) {
                            return sv.substring(0, sv.length() - rv.length());
                        }
                        return sv;
                    }
                    case "index": {
                        int idx = sv.indexOf(rv);
                        return idx >= 0 ? Long.valueOf(idx) : null;
                    }
                    case "rindex": {
                        int idx = sv.lastIndexOf(rv);
                        return idx >= 0 ? Long.valueOf(idx) : null;
                    }
                    case "encode": return sv; // Simplified: return self for encoding
                }
            }

            // String#split(separator, limit) — split with limit
            if (methodName.equals("split") && args.length == 2 && args[0] instanceof String && args[1] instanceof Number) {
                String pattern = (String) args[0];
                int limit = ((Number) args[1]).intValue();
                String[] parts = sv.split(java.util.regex.Pattern.quote(pattern), limit);
                KArray<Object> splitArr = new KArray<>();
                for (String part : parts) splitArr.push(part);
                return splitArr;
            }

            // String#tr(from, to) — 2 string args
            if (methodName.equals("tr") && args.length == 2 && args[0] instanceof String && args[1] instanceof String) {
                return stringTr(sv, (String) args[0], (String) args[1]);
            }

            // String#index(substr, offset) — string + number
            if (methodName.equals("index") && args.length == 2 && args[0] instanceof String && args[1] instanceof Number) {
                int offset = ((Number) args[1]).intValue();
                if (offset < 0) offset = sv.length() + offset;
                if (offset < 0 || offset > sv.length()) return null;
                int idx = sv.indexOf((String) args[0], offset);
                return idx >= 0 ? Long.valueOf(idx) : null;
            }

            // String#rindex(substr, offset) — string + number
            if (methodName.equals("rindex") && args.length == 2 && args[0] instanceof String && args[1] instanceof Number) {
                int offset = ((Number) args[1]).intValue();
                if (offset < 0) offset = sv.length() + offset;
                if (offset < 0) return null;
                // rindex with offset: search backward from offset
                int idx = sv.lastIndexOf((String) args[0], offset);
                return idx >= 0 ? Long.valueOf(idx) : null;
            }

            // String#insert(index, string)
            if (methodName.equals("insert") && args.length == 2 && args[0] instanceof Number && args[1] instanceof String) {
                int idx = ((Number) args[0]).intValue();
                String ins = (String) args[1];
                if (idx < 0) idx = sv.length() + 1 + idx;
                if (idx < 0) idx = 0;
                if (idx > sv.length()) idx = sv.length();
                return sv.substring(0, idx) + ins + sv.substring(idx);
            }

            // String#center, #ljust, #rjust with width and optional pad string
            if ((methodName.equals("center") || methodName.equals("ljust") || methodName.equals("rjust"))) {
                if (args.length >= 1 && args[0] instanceof Number) {
                    int width = ((Number) args[0]).intValue();
                    String pad = (args.length >= 2 && args[1] instanceof String) ? (String) args[1] : " ";
                    if (width <= sv.length()) return sv;
                    int totalPad = width - sv.length();
                    switch (methodName) {
                        case "ljust": return sv + buildPadString(pad, totalPad);
                        case "rjust": return buildPadString(pad, totalPad) + sv;
                        case "center": {
                            int leftPad = totalPad / 2;
                            int rightPad = totalPad - leftPad;
                            return buildPadString(pad, leftPad) + sv + buildPadString(pad, rightPad);
                        }
                    }
                }
            }

            // String#*(n) — repetition
            if (methodName.equals("op_mul") && args.length == 1 && args[0] instanceof Number) {
                int n = ((Number) args[0]).intValue();
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < n; i++) sb.append(sv);
                return sb.toString();
            }

            // String#scan(string_pattern) — already handled above for 1 string arg
            // String#scan(regexp) via regex
            if (methodName.equals("scan") && args.length == 1) {
                if (args[0] instanceof String) {
                    String pattern = (String) args[0];
                    KArray result = new KArray();
                    int idx = 0;
                    while ((idx = sv.indexOf(pattern, idx)) >= 0) {
                        result.push(pattern);
                        idx += pattern.length();
                    }
                    return result;
                }
                if (args[0] instanceof java.util.regex.Pattern) {
                    java.util.regex.Pattern p = (java.util.regex.Pattern) args[0];
                    java.util.regex.Matcher m = p.matcher(sv);
                    KArray result = new KArray();
                    while (m.find()) {
                        result.push(m.group());
                    }
                    return result;
                }
            }

            // String#match(regexp), String#match?(regexp) — accept Pattern or String (regexp as string)
            if ((methodName.equals("match") || methodName.equals("match_q")) && args.length == 1
                && (args[0] instanceof java.util.regex.Pattern || args[0] instanceof String)) {
                java.util.regex.Pattern p;
                if (args[0] instanceof java.util.regex.Pattern) {
                    p = (java.util.regex.Pattern) args[0];
                } else {
                    p = java.util.regex.Pattern.compile((String) args[0]);
                }
                java.util.regex.Matcher m = p.matcher(sv);
                if (methodName.equals("match_q")) {
                    return Boolean.valueOf(m.find());
                }
                // match — return KMatchData (index 0 = full match, 1+ = groups)
                if (m.find()) {
                    KArray<String> groups = new KArray<>();
                    groups.push(m.group(0));
                    for (int i = 1; i <= m.groupCount(); i++) {
                        groups.push(m.group(i));
                    }
                    return new KMatchData(groups, sv);
                }
                return null;
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
                    case "lstrip": return sv.stripLeading();
                    case "rstrip": return sv.stripTrailing();
                    case "upcase": return sv.toUpperCase();
                    case "downcase": return sv.toLowerCase();
                    case "capitalize": {
                        if (sv.isEmpty()) return "";
                        return Character.toUpperCase(sv.charAt(0)) + sv.substring(1).toLowerCase();
                    }
                    case "swapcase": {
                        StringBuilder sb = new StringBuilder(sv.length());
                        for (int i = 0; i < sv.length(); i++) {
                            char c = sv.charAt(i);
                            if (Character.isUpperCase(c)) sb.append(Character.toLowerCase(c));
                            else if (Character.isLowerCase(c)) sb.append(Character.toUpperCase(c));
                            else sb.append(c);
                        }
                        return sb.toString();
                    }
                    case "reverse": return new StringBuilder(sv).reverse().toString();
                    case "empty_q": return Boolean.valueOf(sv.isEmpty());
                    case "to_s": return sv;
                    case "to_str": return sv;
                    // Symbol methods: id2name, name return self (symbols are strings in JVM backend)
                    case "id2name": return sv;
                    case "name": return sv;
                    case "inspect": {
                        // For Symbol (string starting with :) we'd return ":name", but
                        // in JVM backend symbols are just strings, so return quoted form
                        return "\"" + sv + "\"";
                    }
                    case "to_i": {
                        // Ruby: "123abc".to_i => 123, "abc".to_i => 0
                        String stripped = sv.strip();
                        if (stripped.isEmpty()) return Long.valueOf(0);
                        StringBuilder numStr = new StringBuilder();
                        int startIdx = 0;
                        if (stripped.charAt(0) == '-' || stripped.charAt(0) == '+') {
                            numStr.append(stripped.charAt(0));
                            startIdx = 1;
                        }
                        for (int i = startIdx; i < stripped.length(); i++) {
                            char c = stripped.charAt(i);
                            if (c >= '0' && c <= '9') numStr.append(c);
                            else break;
                        }
                        if (numStr.length() == 0 || (numStr.length() == 1 && (numStr.charAt(0) == '-' || numStr.charAt(0) == '+'))) {
                            return Long.valueOf(0);
                        }
                        try { return Long.parseLong(numStr.toString()); }
                        catch (NumberFormatException e) { return Long.valueOf(0); }
                    }
                    case "to_f": {
                        String stripped = sv.strip();
                        if (stripped.isEmpty()) return Double.valueOf(0.0);
                        StringBuilder numStr = new StringBuilder();
                        int startIdx = 0;
                        if (stripped.charAt(0) == '-' || stripped.charAt(0) == '+') {
                            numStr.append(stripped.charAt(0));
                            startIdx = 1;
                        }
                        boolean hasDot = false;
                        for (int i = startIdx; i < stripped.length(); i++) {
                            char c = stripped.charAt(i);
                            if (c >= '0' && c <= '9') numStr.append(c);
                            else if (c == '.' && !hasDot) { numStr.append(c); hasDot = true; }
                            else if ((c == 'e' || c == 'E') && numStr.length() > 0) {
                                numStr.append(c);
                                if (i + 1 < stripped.length() && (stripped.charAt(i+1) == '-' || stripped.charAt(i+1) == '+')) {
                                    numStr.append(stripped.charAt(++i));
                                }
                            }
                            else break;
                        }
                        if (numStr.length() == 0 || (numStr.length() == 1 && (numStr.charAt(0) == '-' || numStr.charAt(0) == '+'))) {
                            return Double.valueOf(0.0);
                        }
                        try { return Double.parseDouble(numStr.toString()); }
                        catch (NumberFormatException e) { return Double.valueOf(0.0); }
                    }
                    case "to_sym": return sv;
                    case "intern": return sv;
                    case "chomp": {
                        // No-arg chomp: remove trailing \r\n, \n, or \r
                        if (sv.endsWith("\r\n")) return sv.substring(0, sv.length() - 2);
                        if (sv.endsWith("\n")) return sv.substring(0, sv.length() - 1);
                        if (sv.endsWith("\r")) return sv.substring(0, sv.length() - 1);
                        return sv;
                    }
                    case "chop": {
                        if (sv.isEmpty()) return "";
                        if (sv.endsWith("\r\n")) return sv.substring(0, sv.length() - 2);
                        return sv.substring(0, sv.length() - 1);
                    }
                    case "hex": return Long.valueOf(stringHex(sv));
                    case "oct": return Long.valueOf(stringOct(sv));
                    case "squeeze": return stringSqueeze(sv, null);
                    case "chars": {
                        KArray result = new KArray();
                        for (int i = 0; i < sv.length(); i++) {
                            result.push(String.valueOf(sv.charAt(i)));
                        }
                        return result;
                    }
                    case "bytes": {
                        KArray result = new KArray();
                        byte[] bytes = sv.getBytes(java.nio.charset.StandardCharsets.UTF_8);
                        for (byte b : bytes) {
                            result.push(Long.valueOf(b & 0xFF));
                        }
                        return result;
                    }
                    case "lines": {
                        KArray result = new KArray();
                        String[] lines = sv.split("\n", -1);
                        for (int i = 0; i < lines.length; i++) {
                            if (i < lines.length - 1) {
                                result.push(lines[i] + "\n");
                            } else if (!lines[i].isEmpty()) {
                                result.push(lines[i]);
                            }
                        }
                        return result;
                    }
                    case "freeze": return sv; // Strings are immutable in Java
                    case "dup": return sv;
                    case "clone": return sv;
                    case "k_class": return "String";
                    case "nil_q": return Boolean.FALSE;
                    case "frozen_q": return Boolean.FALSE; // Strings are not frozen by default in Ruby
                    case "to_a": {
                        // Range#to_a — ranges are stored as strings "start..end" or "start...end"
                        return rangeToArray(sv);
                    }
                }
            }

            // String#=~(regexp) — match operator
            if (methodName.equals("op_match") && args.length == 1) {
                java.util.regex.Pattern p;
                if (args[0] instanceof java.util.regex.Pattern) {
                    p = (java.util.regex.Pattern) args[0];
                } else if (args[0] instanceof String) {
                    p = java.util.regex.Pattern.compile((String) args[0]);
                } else {
                    return null;
                }
                java.util.regex.Matcher m = p.matcher(sv);
                if (m.find()) return Long.valueOf(m.start());
                return null;
            }

            // String + non-String (convert to string first)
            if (args.length == 1 && methodName.equals("op_plus")) {
                return sv + String.valueOf(args[0]);
            }

            // String#encode(encoding) — simplified, just return self
            if (methodName.equals("encode") && args.length == 1) {
                return sv;
            }

            // String#gsub(pattern, replacement), String#sub(pattern, replacement)
            if ((methodName.equals("gsub") || methodName.equals("sub")) && args.length == 2
                && args[1] instanceof String) {
                String replacement = (String) args[1];
                if (args[0] instanceof java.util.regex.Pattern) {
                    java.util.regex.Pattern p = (java.util.regex.Pattern) args[0];
                    java.util.regex.Matcher matcher = p.matcher(sv);
                    // Use Matcher.quoteReplacement to escape special chars in replacement
                    String safeReplacement = java.util.regex.Matcher.quoteReplacement(replacement);
                    if (methodName.equals("gsub")) {
                        return matcher.replaceAll(safeReplacement);
                    } else {
                        return matcher.replaceFirst(safeReplacement);
                    }
                } else if (args[0] instanceof String) {
                    if (methodName.equals("gsub")) {
                        return sv.replace((String) args[0], replacement);
                    } else {
                        int idx = sv.indexOf((String) args[0]);
                        if (idx < 0) return sv;
                        return sv.substring(0, idx) + replacement + sv.substring(idx + ((String) args[0]).length());
                    }
                }
            }

            // String#replace(other)
            if (methodName.equals("replace") && args.length == 1 && args[0] instanceof String) {
                return args[0]; // Return the replacement string
            }

            // String#each_line(sep, &block) — call block for each line
            if (methodName.equals("each_line") && args.length >= 1) {
                Object block = args[args.length - 1];
                String separator = "\n";
                if (args.length >= 2 && args[0] instanceof String) {
                    separator = (String) args[0];
                }
                // Split using separator, keeping the separator in each part
                java.util.List<String> lines = new java.util.ArrayList<>();
                int idx = 0;
                while (true) {
                    int found = sv.indexOf(separator, idx);
                    if (found >= 0) {
                        lines.add(sv.substring(idx, found + separator.length()));
                        idx = found + separator.length();
                    } else {
                        if (idx < sv.length()) {
                            lines.add(sv.substring(idx));
                        }
                        break;
                    }
                }
                // Call block for each line via reflection
                if (block != null) {
                    try {
                        Method callMethod = findCallMethod(block.getClass());
                        if (callMethod != null) {
                            callMethod.setAccessible(true);
                            for (String line : lines) {
                                callMethod.invoke(block, (Object) line);
                            }
                        }
                    } catch (Exception e) {
                        // If block invocation fails, just return the string
                    }
                }
                return sv;
            }
        }

        // java.util.regex.Pattern (Regexp) methods
        if (receiver instanceof java.util.regex.Pattern) {
            java.util.regex.Pattern pat = (java.util.regex.Pattern) receiver;
            if (args.length == 0) {
                switch (methodName) {
                    case "source": return pat.pattern();
                    case "to_s": return pat.pattern();
                    case "inspect": return "/" + pat.pattern() + "/";
                    case "k_class": return "Regexp";
                    case "nil_q": return Boolean.FALSE;
                }
            }
            if (args.length == 1 && args[0] instanceof String) {
                String str = (String) args[0];
                switch (methodName) {
                    case "match": {
                        java.util.regex.Matcher m = pat.matcher(str);
                        if (m.find()) {
                            KArray<String> groups = new KArray<>();
                            groups.push(m.group(0));
                            for (int gi = 1; gi <= m.groupCount(); gi++) {
                                groups.push(m.group(gi));
                            }
                            return new KMatchData(groups, str);
                        }
                        return null;
                    }
                    case "match_q": return Boolean.valueOf(pat.matcher(str).find());
                    case "op_match": {
                        java.util.regex.Matcher m2 = pat.matcher(str);
                        if (m2.find()) return Long.valueOf(m2.start());
                        return null;
                    }
                    case "op_eq": return Boolean.valueOf(pat.pattern().equals(str));
                }
            }
            // is_a? for Regexp
            if ((methodName.equals("is_a_q") || methodName.equals("kind_of_q")) && args.length == 1) {
                String className = classNameOf(args[0]);
                if ("Regexp".equals(className) || "Object".equals(className) || "BasicObject".equals(className)) {
                    return Boolean.TRUE;
                }
                return Boolean.FALSE;
            }
        }

        // KMatchData methods
        if (receiver instanceof KMatchData) {
            KMatchData md = (KMatchData) receiver;
            switch (methodName) {
                case "op_aref":
                    if (args.length == 1 && args[0] instanceof Long) {
                        return md.get(((Long) args[0]).intValue());
                    }
                    break;
                case "to_s": return md.toString();
                case "string": return md.string();
                case "captures": return md.captures();
                case "length": case "size": return md.length();
                case "k_class": return md.k_class();
                case "nil_q": return Boolean.FALSE;
                case "frozen_q": return Boolean.TRUE;
                case "inspect": return md.toString();
                case "is_a_q": case "kind_of_q": case "instance_of_q":
                    if (args.length == 1) {
                        String cn = classNameOf(args[0]);
                        if ("MatchData".equals(cn) || "Object".equals(cn) || "BasicObject".equals(cn))
                            return Boolean.TRUE;
                        return Boolean.FALSE;
                    }
                    break;
            }
        }

        // KArray methods via dispatch (for methods not on the KArray class itself)
        if (receiver instanceof KArray) {
            KArray<?> arr = (KArray<?>) receiver;
            switch (methodName) {
                case "op_plus": {
                    // Array + Array -> new Array (concatenation)
                    if (args.length == 1 && args[0] instanceof KArray) {
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>((KArray<Object>) arr);
                        result.addAll((KArray<?>) args[0]);
                        return result;
                    }
                    break;
                }
                case "op_minus": {
                    // Array - Array -> new Array (difference)
                    if (args.length == 1 && args[0] instanceof KArray) {
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        KArray<?> other = (KArray<?>) args[0];
                        for (Object elem : arr) {
                            if (!other.contains(elem)) result.push(elem);
                        }
                        return result;
                    }
                    break;
                }
                case "op_and": {
                    // Array & Array -> intersection
                    if (args.length == 1 && args[0] instanceof KArray) {
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        KArray<?> other = (KArray<?>) args[0];
                        java.util.Set<Object> seen = new java.util.LinkedHashSet<>();
                        for (Object elem : arr) {
                            if (other.contains(elem) && seen.add(elem)) result.push(elem);
                        }
                        return result;
                    }
                    break;
                }
                case "op_or": {
                    // Array | Array -> union
                    if (args.length == 1 && args[0] instanceof KArray) {
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        java.util.Set<Object> seen = new java.util.LinkedHashSet<>();
                        for (Object elem : arr) { if (seen.add(elem)) result.push(elem); }
                        for (Object elem : (KArray<?>) args[0]) { if (seen.add(elem)) result.push(elem); }
                        return result;
                    }
                    break;
                }
                case "op_mul": {
                    // Array * String -> join
                    if (args.length == 1 && args[0] instanceof String) {
                        return arr.join((String) args[0]);
                    }
                    // Array * Integer -> repeat
                    if (args.length == 1 && args[0] instanceof Number) {
                        int n = ((Number) args[0]).intValue();
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        for (int i = 0; i < n; i++) result.addAll(arr);
                        return result;
                    }
                    break;
                }
                case "op_eq": {
                    if (args.length == 1) return Boolean.valueOf(arr.equals(args[0]));
                    break;
                }
                case "op_neq": {
                    if (args.length == 1) return Boolean.valueOf(!arr.equals(args[0]));
                    break;
                }
                case "take": {
                    if (args.length == 1 && args[0] instanceof Number) {
                        int n = ((Number) args[0]).intValue();
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        for (int i = 0; i < Math.min(n, arr.size()); i++) result.push(arr.get(i));
                        return result;
                    }
                    break;
                }
                case "drop": {
                    if (args.length == 1 && args[0] instanceof Number) {
                        int n = ((Number) args[0]).intValue();
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        for (int i = n; i < arr.size(); i++) result.push(arr.get(i));
                        return result;
                    }
                    break;
                }
                case "rotate": {
                    if (args.length <= 1) {
                        int n = (args.length == 1 && args[0] instanceof Number) ? ((Number) args[0]).intValue() : 1;
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        int sz = arr.size();
                        if (sz == 0) return result;
                        n = ((n % sz) + sz) % sz;
                        for (int i = n; i < sz; i++) result.push(arr.get(i));
                        for (int i = 0; i < n; i++) result.push(arr.get(i));
                        return result;
                    }
                    break;
                }
                case "zip": {
                    if (args.length == 1 && args[0] instanceof KArray) {
                        KArray<?> other = (KArray<?>) args[0];
                        @SuppressWarnings("unchecked") KArray<Object> result = new KArray<>();
                        for (int i = 0; i < arr.size(); i++) {
                            KArray<Object> pair = new KArray<>();
                            pair.push(arr.get(i));
                            pair.push(i < other.size() ? other.get(i) : null);
                            result.push(pair);
                        }
                        return result;
                    }
                    break;
                }
                case "k_class": return "Array";
                case "nil_q": return Boolean.FALSE;
                case "is_a_q": case "kind_of_q": case "instance_of_q": {
                    if (args.length == 1) {
                        String className = classNameOf(args[0]);
                        if ("Array".equals(className) || "Enumerable".equals(className) || "Object".equals(className) || "BasicObject".equals(className))
                            return Boolean.TRUE;
                        return Boolean.FALSE;
                    }
                    break;
                }
                case "inspect": case "to_s": {
                    if (args.length == 0) return arr.toString();
                    break;
                }
                case "flatten": {
                    if (args.length == 0) return arr.flatten();
                    break;
                }
                case "sample": {
                    if (args.length == 0 && arr.size() > 0) {
                        return arr.get(new java.util.Random().nextInt(arr.size()));
                    }
                    break;
                }
                case "select": case "filter": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>();
                        for (Object elem : arr) {
                            Object blockResult = invokeBlock(args[0], elem);
                            if (isTruthy(blockResult)) result.push(elem);
                        }
                        return result;
                    }
                    break;
                }
                case "reject": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>();
                        for (Object elem : arr) {
                            Object blockResult = invokeBlock(args[0], elem);
                            if (!isTruthy(blockResult)) result.push(elem);
                        }
                        return result;
                    }
                    break;
                }
                case "map": case "collect": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>();
                        for (Object elem : arr) {
                            result.push(invokeBlock(args[0], elem));
                        }
                        return result;
                    }
                    break;
                }
                case "each": {
                    if (args.length == 1) {
                        for (Object elem : arr) {
                            invokeBlock(args[0], elem);
                        }
                        return arr;
                    }
                    break;
                }
                case "each_with_index": {
                    if (args.length == 1) {
                        for (int i = 0; i < arr.size(); i++) {
                            invokeBlock(args[0], arr.get(i), Long.valueOf(i));
                        }
                        return arr;
                    }
                    break;
                }
                case "any_q": {
                    if (args.length == 1) {
                        for (Object elem : arr) {
                            if (isTruthy(invokeBlock(args[0], elem))) return Boolean.TRUE;
                        }
                        return Boolean.FALSE;
                    }
                    if (args.length == 0) return Boolean.valueOf(!arr.isEmpty());
                    break;
                }
                case "all_q": {
                    if (args.length == 1) {
                        for (Object elem : arr) {
                            if (!isTruthy(invokeBlock(args[0], elem))) return Boolean.FALSE;
                        }
                        return Boolean.TRUE;
                    }
                    break;
                }
                case "none_q": {
                    if (args.length == 1) {
                        for (Object elem : arr) {
                            if (isTruthy(invokeBlock(args[0], elem))) return Boolean.FALSE;
                        }
                        return Boolean.TRUE;
                    }
                    if (args.length == 0) return Boolean.valueOf(arr.isEmpty());
                    break;
                }
                case "find": case "detect": {
                    if (args.length == 1) {
                        for (Object elem : arr) {
                            if (isTruthy(invokeBlock(args[0], elem))) return elem;
                        }
                        return null;
                    }
                    break;
                }
                case "reduce": case "inject": {
                    if (args.length == 1) {
                        // reduce with block only (no initial value)
                        if (arr.isEmpty()) return null;
                        Object acc = arr.get(0);
                        for (int i = 1; i < arr.size(); i++) {
                            acc = invokeBlock(args[0], acc, arr.get(i));
                        }
                        return acc;
                    }
                    if (args.length == 2) {
                        // reduce with initial value + block
                        Object acc = args[0];
                        for (Object elem : arr) {
                            acc = invokeBlock(args[1], acc, elem);
                        }
                        return acc;
                    }
                    break;
                }
                case "flat_map": case "collect_concat": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>();
                        for (Object elem : arr) {
                            Object blockResult = invokeBlock(args[0], elem);
                            if (blockResult instanceof KArray) {
                                result.addAll((KArray<?>) blockResult);
                            } else {
                                result.push(blockResult);
                            }
                        }
                        return result;
                    }
                    break;
                }
                case "sort_by": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>(arr);
                        result.sort((a, b) -> {
                            Object ka = invokeBlock(args[0], a);
                            Object kb = invokeBlock(args[0], b);
                            if (ka instanceof Comparable && kb instanceof Comparable) {
                                @SuppressWarnings("unchecked")
                                Comparable<Object> ca = (Comparable<Object>) ka;
                                return ca.compareTo(kb);
                            }
                            return 0;
                        });
                        return result;
                    }
                    break;
                }
                case "min_by": {
                    if (args.length == 1) {
                        Object best = null;
                        Object bestKey = null;
                        for (Object elem : arr) {
                            Object key = invokeBlock(args[0], elem);
                            if (bestKey == null || (key instanceof Comparable && bestKey instanceof Comparable &&
                                ((Comparable) key).compareTo(bestKey) < 0)) {
                                best = elem;
                                bestKey = key;
                            }
                        }
                        return best;
                    }
                    break;
                }
                case "max_by": {
                    if (args.length == 1) {
                        Object best = null;
                        Object bestKey = null;
                        for (Object elem : arr) {
                            Object key = invokeBlock(args[0], elem);
                            if (bestKey == null || (key instanceof Comparable && bestKey instanceof Comparable &&
                                ((Comparable) key).compareTo(bestKey) > 0)) {
                                best = elem;
                                bestKey = key;
                            }
                        }
                        return best;
                    }
                    break;
                }
                case "group_by": {
                    if (args.length == 1) {
                        KHash<Object, Object> result = new KHash<>();
                        for (Object elem : arr) {
                            Object key = invokeBlock(args[0], elem);
                            result.groupByAdd(key, elem);
                        }
                        return result;
                    }
                    break;
                }
                case "each_with_object": {
                    if (args.length == 2) {
                        // args[0] = memo object, args[1] = block
                        Object memo = args[0];
                        Object block = args[1];
                        for (Object elem : arr) {
                            invokeBlock(block, elem, memo);
                        }
                        return memo;
                    }
                    break;
                }
                case "take_while": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>();
                        for (Object elem : arr) {
                            if (!isTruthy(invokeBlock(args[0], elem))) break;
                            result.push(elem);
                        }
                        return result;
                    }
                    break;
                }
                case "drop_while": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>();
                        boolean dropping = true;
                        for (Object elem : arr) {
                            if (dropping && isTruthy(invokeBlock(args[0], elem))) continue;
                            dropping = false;
                            result.push(elem);
                        }
                        return result;
                    }
                    break;
                }
                case "partition": {
                    if (args.length == 1) {
                        KArray<Object> trueArr = new KArray<>();
                        KArray<Object> falseArr = new KArray<>();
                        for (Object elem : arr) {
                            if (isTruthy(invokeBlock(args[0], elem))) {
                                trueArr.push(elem);
                            } else {
                                falseArr.push(elem);
                            }
                        }
                        KArray<Object> result = new KArray<>();
                        result.push(trueArr);
                        result.push(falseArr);
                        return result;
                    }
                    break;
                }
                case "tally": {
                    if (args.length == 0) {
                        KHash<Object, Object> result = new KHash<>();
                        for (Object elem : arr) {
                            Object count = result.get(elem);
                            if (count instanceof Long) {
                                result.put(elem, (Long) count + 1L);
                            } else {
                                result.put(elem, 1L);
                            }
                        }
                        return result;
                    }
                    break;
                }
                case "sum": {
                    if (args.length == 0) return arr.sumLong();
                    break;
                }
                case "count": {
                    if (args.length == 1) {
                        long count = 0;
                        for (Object elem : arr) {
                            if (isTruthy(invokeBlock(args[0], elem))) count++;
                        }
                        return Long.valueOf(count);
                    }
                    return Long.valueOf(arr.size());
                }
                case "frozen_q": return Boolean.valueOf(arr.isFrozen());
                case "freeze": { arr.freeze(); return arr; }
            }
        }

        // KHash methods via dispatch
        if (receiver instanceof KHash) {
            KHash<?, ?> hash = (KHash<?, ?>) receiver;
            switch (methodName) {
                case "include_q": case "key_q": case "member_q": {
                    if (args.length == 1) return Boolean.valueOf(hash.containsKey(args[0]));
                    break;
                }
                case "store": {
                    @SuppressWarnings("unchecked")
                    KHash<Object, Object> mutableHash = (KHash<Object, Object>) hash;
                    if (args.length == 2) { mutableHash.put(args[0], args[1]); return args[1]; }
                    break;
                }
                case "delete": {
                    @SuppressWarnings("unchecked")
                    KHash<Object, Object> mutableHash2 = (KHash<Object, Object>) hash;
                    if (args.length == 1) { return mutableHash2.remove(args[0]); }
                    break;
                }
                case "value_q": {
                    if (args.length == 1) return Boolean.valueOf(hash.containsValue(args[0]));
                    break;
                }
                case "op_eq": {
                    if (args.length == 1) return Boolean.valueOf(hash.equals(args[0]));
                    break;
                }
                case "k_class": return "Hash";
                case "nil_q": return Boolean.FALSE;
                case "is_a_q": case "kind_of_q": case "instance_of_q": {
                    if (args.length == 1) {
                        String className = classNameOf(args[0]);
                        if ("Hash".equals(className) || "Enumerable".equals(className) || "Object".equals(className) || "BasicObject".equals(className))
                            return Boolean.TRUE;
                        return Boolean.FALSE;
                    }
                    break;
                }
                case "fetch": {
                    if (args.length == 1) {
                        Object val = hash.get(args[0]);
                        if (val != null) return val;
                        throw new RuntimeException("KeyError: key not found: " + args[0]);
                    }
                    break;
                }
                case "any_q": {
                    if (args.length == 0) return Boolean.valueOf(!hash.isEmpty());
                    // any? with block
                    if (args.length == 1) {
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object result = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (isTruthy(result)) return Boolean.TRUE;
                        }
                        return Boolean.FALSE;
                    }
                    break;
                }
                case "all_q": {
                    if (args.length == 0) return Boolean.valueOf(!hash.isEmpty());
                    if (args.length == 1) {
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object result = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (!isTruthy(result)) return Boolean.FALSE;
                        }
                        return Boolean.TRUE;
                    }
                    break;
                }
                case "none_q": {
                    if (args.length == 0) return Boolean.valueOf(hash.isEmpty());
                    if (args.length == 1) {
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object result = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (isTruthy(result)) return Boolean.FALSE;
                        }
                        return Boolean.TRUE;
                    }
                    break;
                }
                case "select": case "filter": {
                    if (args.length == 1) {
                        @SuppressWarnings("unchecked")
                        KHash<Object, Object> result = new KHash<>();
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object blockResult = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (isTruthy(blockResult)) {
                                result.put(entry.getKey(), entry.getValue());
                            }
                        }
                        return result;
                    }
                    break;
                }
                case "reject": {
                    if (args.length == 1) {
                        @SuppressWarnings("unchecked")
                        KHash<Object, Object> result = new KHash<>();
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object blockResult = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (!isTruthy(blockResult)) {
                                result.put(entry.getKey(), entry.getValue());
                            }
                        }
                        return result;
                    }
                    break;
                }
                case "map": case "collect": {
                    if (args.length == 1) {
                        KArray<Object> result = new KArray<>();
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object blockResult = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            result.push(blockResult);
                        }
                        return result;
                    }
                    break;
                }
                case "each": {
                    if (args.length == 1) {
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            invokeBlock(args[0], entry.getKey(), entry.getValue());
                        }
                        return hash;
                    }
                    break;
                }
                case "each_pair": {
                    if (args.length == 1) {
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            invokeBlock(args[0], entry.getKey(), entry.getValue());
                        }
                        return hash;
                    }
                    break;
                }
                case "each_key": {
                    if (args.length == 1) {
                        for (Object key : hash.keySet()) {
                            invokeBlock(args[0], key);
                        }
                        return hash;
                    }
                    break;
                }
                case "each_value": {
                    if (args.length == 1) {
                        for (Object value : hash.values()) {
                            invokeBlock(args[0], value);
                        }
                        return hash;
                    }
                    break;
                }
                case "count": {
                    if (args.length == 1) {
                        long count = 0;
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object blockResult = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (isTruthy(blockResult)) count++;
                        }
                        return Long.valueOf(count);
                    }
                    return Long.valueOf(hash.size());
                }
                case "frozen_q": return Boolean.FALSE;
                case "freeze": return hash;
                case "to_a": {
                    KArray<Object> result = new KArray<>();
                    for (Map.Entry<?, ?> entry : hash.entrySet()) {
                        KArray<Object> pair = new KArray<>();
                        pair.push(entry.getKey());
                        pair.push(entry.getValue());
                        result.push(pair);
                    }
                    return result;
                }
                case "inspect": case "to_s": {
                    if (args.length == 0) return hash.toString();
                    break;
                }
                case "flatten": {
                    KArray<Object> result = new KArray<>();
                    for (Map.Entry<?, ?> entry : hash.entrySet()) {
                        result.push(entry.getKey());
                        result.push(entry.getValue());
                    }
                    return result;
                }
                case "min_by": {
                    if (args.length == 1) {
                        Object bestEntry = null;
                        Object bestKey = null;
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object key = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (bestKey == null || (key instanceof Comparable && bestKey instanceof Comparable &&
                                ((Comparable) key).compareTo(bestKey) < 0)) {
                                KArray<Object> pair = new KArray<>();
                                pair.push(entry.getKey());
                                pair.push(entry.getValue());
                                bestEntry = pair;
                                bestKey = key;
                            }
                        }
                        return bestEntry;
                    }
                    break;
                }
                case "max_by": {
                    if (args.length == 1) {
                        Object bestEntry = null;
                        Object bestKey = null;
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            Object key = invokeBlock(args[0], entry.getKey(), entry.getValue());
                            if (bestKey == null || (key instanceof Comparable && bestKey instanceof Comparable &&
                                ((Comparable) key).compareTo(bestKey) > 0)) {
                                KArray<Object> pair = new KArray<>();
                                pair.push(entry.getKey());
                                pair.push(entry.getValue());
                                bestEntry = pair;
                                bestKey = key;
                            }
                        }
                        return bestEntry;
                    }
                    break;
                }
                case "sort_by": {
                    if (args.length == 1) {
                        KArray<Object> entries = new KArray<>();
                        for (Map.Entry<?, ?> entry : hash.entrySet()) {
                            KArray<Object> pair = new KArray<>();
                            pair.push(entry.getKey());
                            pair.push(entry.getValue());
                            entries.push(pair);
                        }
                        entries.sort((a, b) -> {
                            // Pass pair as single arg (Ruby Hash#sort_by yields [k,v] pair)
                            Object ka = invokeBlock(args[0], a);
                            Object kb = invokeBlock(args[0], b);
                            if (ka instanceof Comparable && kb instanceof Comparable) {
                                return ((Comparable) ka).compareTo(kb);
                            }
                            return 0;
                        });
                        return entries;
                    }
                    break;
                }
                case "merge": {
                    if (args.length == 1 && args[0] instanceof KHash) {
                        @SuppressWarnings("unchecked")
                        KHash<Object, Object> result = new KHash<>(hash);
                        result.putAll((KHash<?, ?>) args[0]);
                        return result;
                    }
                    break;
                }
            }
        }

        // General is_a_q / k_class / nil_q for user-defined classes
        if (methodName.equals("nil_q") && args.length == 0) {
            return Boolean.FALSE; // Any non-null object is not nil
        }
        if (methodName.equals("k_class") && args.length == 0) {
            return rubyClassName(receiver);
        }
        if ((methodName.equals("is_a_q") || methodName.equals("kind_of_q") || methodName.equals("instance_of_q"))
            && args.length == 1) {
            String className = classNameOf(args[0]);
            String receiverClassName = rubyClassName(receiver);
            if (className != null) {
                if (className.equals(receiverClassName) || className.equals("Object") || className.equals("BasicObject")) {
                    return Boolean.TRUE;
                }
                // Check if the receiver's class is a subclass (via Java inheritance)
                try {
                    Class<?> targetClass = Class.forName(receiver.getClass().getPackage().getName() + "." + className);
                    return Boolean.valueOf(targetClass.isAssignableFrom(receiver.getClass()));
                } catch (ClassNotFoundException e) {
                    // Not found, fall through
                }
                return Boolean.FALSE;
            }
        }
        // General frozen_q / freeze for all objects
        if (methodName.equals("frozen_q") && args.length == 0) {
            return Boolean.FALSE;
        }
        if (methodName.equals("freeze") && args.length == 0) {
            return receiver;
        }
        // General equal? (identity comparison) — Object#equal?
        if (methodName.equals("equal_q") && args.length == 1) {
            return Boolean.valueOf(receiver == args[0]);
        }
        // General eql? — value equality
        if (methodName.equals("eql_q") && args.length == 1) {
            if (receiver == null) return Boolean.valueOf(args[0] == null);
            return Boolean.valueOf(receiver.equals(args[0]));
        }
        // General hash (Object#hash)
        if (methodName.equals("hash") && args.length == 0) {
            return Long.valueOf(System.identityHashCode(receiver));
        }
        // General object_id
        if (methodName.equals("object_id") && args.length == 0) {
            return Long.valueOf(System.identityHashCode(receiver));
        }
        // General respond_to?
        if (methodName.equals("respond_to_q") && args.length == 1) {
            String checkName = String.valueOf(args[0]);
            // Try multiple arities (0, 1, 2) since Ruby methods have various arities
            for (int arity = 0; arity <= 2; arity++) {
                Method found2 = findMethod(receiver.getClass(), checkName, arity);
                if (found2 != null) return Boolean.TRUE;
                String[] aliases2 = RUBY_NAME_ALIASES.get(checkName);
                if (aliases2 != null) {
                    for (String alias : aliases2) {
                        found2 = findMethod(receiver.getClass(), alias, arity);
                        if (found2 != null) return Boolean.TRUE;
                    }
                }
            }
            // Check well-known built-in methods handled in tryBuiltinOperator
            if (receiver instanceof KArray) {
                switch (checkName) {
                    case "push": case "pop": case "shift": case "unshift": case "first":
                    case "last": case "length": case "size": case "empty_q": case "include_q":
                    case "sort": case "reverse": case "flatten": case "compact": case "uniq":
                    case "each": case "map": case "select": case "reject": case "reduce":
                    case "find": case "any_q": case "all_q": case "none_q": case "join":
                    case "min": case "max": case "count": case "delete": case "index":
                    case "freeze": case "frozen_q":
                        return Boolean.TRUE;
                }
            }
            return Boolean.FALSE;
        }

        return SENTINEL;
    }

    /**
     * Extract a Ruby class name from a constant reference.
     * In the JVM backend, class constants may be represented as String class names.
     */
    private static String classNameOf(Object ref) {
        if (ref instanceof String) return (String) ref;
        if (ref instanceof Class) return ((Class<?>) ref).getSimpleName();
        return null;
    }

    /**
     * Get the Ruby class name for an object.
     */
    private static String rubyClassName(Object obj) {
        if (obj == null) return "NilClass";
        if (obj instanceof Long) return "Integer";
        if (obj instanceof Double) return "Float";
        if (obj instanceof Boolean) return ((Boolean) obj) ? "TrueClass" : "FalseClass";
        if (obj instanceof String) return "String";
        if (obj instanceof KArray) return "Array";
        if (obj instanceof KHash) return "Hash";
        if (obj instanceof java.util.regex.Pattern) return "Regexp";
        if (obj instanceof KFiber) return "Fiber";
        if (obj instanceof KThread) return "Thread";
        if (obj instanceof java.util.concurrent.locks.ReentrantLock) return "Mutex";
        // User-defined class: use simple name
        String name = obj.getClass().getSimpleName();
        return name;
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

    // ========================================================================
    // Block helper methods
    // ========================================================================

    /**
     * Find the "call" method on a KBlock functional interface.
     * KBlock interfaces have a single abstract method named "call".
     */
    private static Method findCallMethod(Class<?> clazz) {
        // First try direct "call" method with Object return
        for (Method m : clazz.getMethods()) {
            if (m.getName().equals("call") && m.getParameterCount() == 1) {
                return m;
            }
        }
        // Try with different arities
        for (Method m : clazz.getMethods()) {
            if (m.getName().equals("call")) {
                return m;
            }
        }
        return null;
    }

    // ========================================================================
    // String helper methods
    // ========================================================================

    /**
     * Build a pad string of exactly the given length by repeating padStr cyclically.
     */
    private static String buildPadString(String padStr, int length) {
        if (length <= 0 || padStr.isEmpty()) return "";
        StringBuilder sb = new StringBuilder(length);
        int idx = 0;
        while (sb.length() < length) {
            sb.append(padStr.charAt(idx % padStr.length()));
            idx++;
        }
        return sb.toString();
    }

    /**
     * Ruby String#count — count characters in the given character set.
     * Supports negated sets (^) for counting characters NOT in the set.
     */
    private static long stringCount(String str, String charSet) {
        boolean negate = charSet.startsWith("^");
        String chars = negate ? charSet.substring(1) : charSet;
        long count = 0;
        for (int i = 0; i < str.length(); i++) {
            boolean inSet = chars.indexOf(str.charAt(i)) >= 0;
            if (negate ? !inSet : inSet) count++;
        }
        return count;
    }

    /**
     * Ruby String#delete — remove characters in the given character set.
     */
    private static String stringDelete(String str, String charSet) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < str.length(); i++) {
            if (charSet.indexOf(str.charAt(i)) < 0) {
                sb.append(str.charAt(i));
            }
        }
        return sb.toString();
    }

    /**
     * Ruby String#squeeze — remove runs of the same character.
     * If charSet is null, squeeze all characters. Otherwise, only squeeze chars in the set.
     */
    private static String stringSqueeze(String str, String charSet) {
        if (str.isEmpty()) return str;
        StringBuilder sb = new StringBuilder();
        char prev = 0;
        for (int i = 0; i < str.length(); i++) {
            char c = str.charAt(i);
            if (i > 0 && c == prev) {
                // Check if this char should be squeezed
                if (charSet == null || charSet.indexOf(c) >= 0) {
                    continue; // Skip duplicate
                }
            }
            sb.append(c);
            prev = c;
        }
        return sb.toString();
    }

    /**
     * Ruby String#tr — translate characters.
     * Supports ranges (a-z), deletion (empty to_str).
     */
    private static String stringTr(String str, String from, String to) {
        String expandedFrom = expandTrRange(from);
        String expandedTo = expandTrRange(to);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < str.length(); i++) {
            char c = str.charAt(i);
            int idx = expandedFrom.indexOf(c);
            if (idx >= 0) {
                if (expandedTo.isEmpty()) {
                    // Delete mode: skip the character
                    continue;
                }
                // Map to the corresponding character (or last char if to is shorter)
                int toIdx = Math.min(idx, expandedTo.length() - 1);
                sb.append(expandedTo.charAt(toIdx));
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    /**
     * Expand tr range notation: "a-z" → "abcdefghijklmnopqrstuvwxyz"
     */
    private static String expandTrRange(String s) {
        StringBuilder sb = new StringBuilder();
        int i = 0;
        while (i < s.length()) {
            if (i + 2 < s.length() && s.charAt(i + 1) == '-') {
                char start = s.charAt(i);
                char end = s.charAt(i + 2);
                for (char c = start; c <= end; c++) {
                    sb.append(c);
                }
                i += 3;
            } else {
                sb.append(s.charAt(i));
                i++;
            }
        }
        return sb.toString();
    }

    /**
     * Ruby String#hex — interpret leading characters as hexadecimal.
     */
    private static long stringHex(String str) {
        String s = str.strip();
        if (s.startsWith("0x") || s.startsWith("0X")) s = s.substring(2);
        if (s.isEmpty()) return 0;
        StringBuilder numStr = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = Character.toLowerCase(s.charAt(i));
            if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
                numStr.append(c);
            } else {
                break;
            }
        }
        if (numStr.length() == 0) return 0;
        try { return Long.parseLong(numStr.toString(), 16); }
        catch (NumberFormatException e) { return 0; }
    }

    /**
     * Ruby String#oct — interpret leading characters as octal.
     */
    private static long stringOct(String str) {
        String s = str.strip();
        if (s.startsWith("0o") || s.startsWith("0O")) s = s.substring(2);
        else if (s.startsWith("0") && s.length() > 1) s = s.substring(1);
        if (s.isEmpty()) return 0;
        StringBuilder numStr = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= '0' && c <= '7') {
                numStr.append(c);
            } else {
                break;
            }
        }
        if (numStr.length() == 0) return 0;
        try { return Long.parseLong(numStr.toString(), 8); }
        catch (NumberFormatException e) { return 0; }
    }

    /**
     * Parse a Range-formatted string ("start..end" or "start...end") and produce a KArray.
     * Ranges are stored as strings in the JVM backend.
     */
    @SuppressWarnings("unchecked")
    private static KArray<Object> rangeToArray(String rangeStr) {
        boolean exclusive = false;
        int separatorIdx;
        if (rangeStr.contains("...")) {
            exclusive = true;
            separatorIdx = rangeStr.indexOf("...");
        } else if (rangeStr.contains("..")) {
            separatorIdx = rangeStr.indexOf("..");
        } else {
            // Not a range string, return array with the string itself
            KArray<Object> result = new KArray<>();
            result.push(rangeStr);
            return result;
        }

        String leftStr = rangeStr.substring(0, separatorIdx);
        String rightStr = rangeStr.substring(separatorIdx + (exclusive ? 3 : 2));

        KArray<Object> result = new KArray<>();
        try {
            long start = Long.parseLong(leftStr.strip());
            long end = Long.parseLong(rightStr.strip());
            if (exclusive) {
                for (long i = start; i < end; i++) {
                    result.push(Long.valueOf(i));
                }
            } else {
                for (long i = start; i <= end; i++) {
                    result.push(Long.valueOf(i));
                }
            }
        } catch (NumberFormatException e) {
            // If not numeric, try single character range
            if (leftStr.strip().length() == 1 && rightStr.strip().length() == 1) {
                char start = leftStr.strip().charAt(0);
                char end = rightStr.strip().charAt(0);
                if (exclusive) {
                    for (char c = start; c < end; c++) {
                        result.push(String.valueOf(c));
                    }
                } else {
                    for (char c = start; c <= end; c++) {
                        result.push(String.valueOf(c));
                    }
                }
            } else {
                result.push(rangeStr);
            }
        }
        return result;
    }

    // ========================================================================
    // Block invocation helpers
    // ========================================================================

    /**
     * Invoke a block (KBlock functional interface) with the given arguments.
     * Uses reflection to find and call the `call` method.
     */
    private static Object invokeBlock(Object block, Object... blockArgs) {
        if (block == null) return null;
        try {
            // Collect all `call` methods (both from getMethods and getDeclaredMethods)
            java.util.List<Method> callMethods = new java.util.ArrayList<>();
            for (Method m : block.getClass().getMethods()) {
                if (m.getName().equals("call")) callMethods.add(m);
            }
            for (Method m : block.getClass().getDeclaredMethods()) {
                if (m.getName().equals("call")) {
                    boolean duplicate = false;
                    for (Method existing : callMethods) {
                        if (java.util.Arrays.equals(existing.getParameterTypes(), m.getParameterTypes())) {
                            duplicate = true;
                            break;
                        }
                    }
                    if (!duplicate) callMethods.add(m);
                }
            }

            // First pass: exact arity match
            for (Method m : callMethods) {
                if (m.getParameterCount() == blockArgs.length) {
                    m.setAccessible(true);
                    return m.invoke(block, blockArgs);
                }
            }

            // Second pass: adapted arity (fewer params than args, or more params with null padding)
            for (Method m : callMethods) {
                if (!m.isBridge()) {
                    m.setAccessible(true);
                    int paramCount = m.getParameterCount();
                    Object[] adapted = new Object[paramCount];
                    for (int i = 0; i < paramCount; i++) {
                        adapted[i] = i < blockArgs.length ? blockArgs[i] : null;
                    }
                    return m.invoke(block, adapted);
                }
            }

            // Third pass: use any call method (even bridge) as last resort
            for (Method m : callMethods) {
                m.setAccessible(true);
                int paramCount = m.getParameterCount();
                Object[] adapted = new Object[paramCount];
                for (int i = 0; i < paramCount; i++) {
                    adapted[i] = i < blockArgs.length ? blockArgs[i] : null;
                }
                return m.invoke(block, adapted);
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to invoke block: " + e.getMessage(), e);
        }
        throw new RuntimeException("Block has no callable 'call' method for " + blockArgs.length + " args");
    }

    /**
     * Ruby truthiness check: everything is truthy except null (nil) and false.
     */
    public static boolean isTruthy(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        return true;
    }

    /**
     * GCD helper for Integer#gcd.
     */
    private static long gcd(long a, long b) {
        while (b != 0) { long t = b; b = a % b; a = t; }
        return a;
    }

    // ========================================================================
    // Range helper methods (Range stored as string "start..end" or "start...end")
    // ========================================================================

    /**
     * Check if a string represents a Range.
     */
    private static boolean isRangeString(String s) {
        return s.contains(".."); // covers both ".." and "..."
    }

    /**
     * Parse range bounds from a range string.
     * Returns [startStr, endStr, exclusive].
     */
    private static Object[] parseRangeString(String rangeStr) {
        boolean exclusive = false;
        int separatorIdx;
        if (rangeStr.contains("...")) {
            exclusive = true;
            separatorIdx = rangeStr.indexOf("...");
        } else {
            separatorIdx = rangeStr.indexOf("..");
        }
        String leftStr = rangeStr.substring(0, separatorIdx).strip();
        String rightStr = rangeStr.substring(separatorIdx + (exclusive ? 3 : 2)).strip();
        return new Object[]{leftStr, rightStr, exclusive};
    }

    /**
     * Range#include?(value) — check if value is within the range.
     */
    private static Boolean rangeInclude(String rangeStr, Object value) {
        Object[] parts = parseRangeString(rangeStr);
        String leftStr = (String) parts[0];
        String rightStr = (String) parts[1];
        boolean exclusive = (Boolean) parts[2];

        try {
            long start = Long.parseLong(leftStr);
            long end = Long.parseLong(rightStr);
            long val;
            if (value instanceof Number) {
                val = ((Number) value).longValue();
            } else {
                return Boolean.FALSE;
            }
            if (exclusive) {
                return Boolean.valueOf(val >= start && val < end);
            } else {
                return Boolean.valueOf(val >= start && val <= end);
            }
        } catch (NumberFormatException e) {
            // String range comparison
            String valStr = String.valueOf(value);
            int cmpStart = valStr.compareTo(leftStr);
            int cmpEnd = valStr.compareTo(rightStr);
            if (exclusive) {
                return Boolean.valueOf(cmpStart >= 0 && cmpEnd < 0);
            } else {
                return Boolean.valueOf(cmpStart >= 0 && cmpEnd <= 0);
            }
        }
    }

    /**
     * Range#size — returns the number of elements.
     */
    private static Long rangeSize(String rangeStr) {
        Object[] parts = parseRangeString(rangeStr);
        try {
            long start = Long.parseLong(((String) parts[0]));
            long end = Long.parseLong(((String) parts[1]));
            boolean exclusive = (Boolean) parts[2];
            long size = exclusive ? (end - start) : (end - start + 1);
            return Long.valueOf(Math.max(0, size));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /**
     * Range#min / Range#first — returns the start of the range.
     */
    private static Object rangeMin(String rangeStr) {
        Object[] parts = parseRangeString(rangeStr);
        try {
            return Long.parseLong(((String) parts[0]));
        } catch (NumberFormatException e) {
            return parts[0];
        }
    }

    /**
     * Range#max / Range#last — returns the end of the range.
     */
    private static Object rangeMax(String rangeStr) {
        Object[] parts = parseRangeString(rangeStr);
        boolean exclusive = (Boolean) parts[2];
        try {
            long end = Long.parseLong(((String) parts[1]));
            return Long.valueOf(exclusive ? end - 1 : end);
        } catch (NumberFormatException e) {
            return parts[1];
        }
    }

    /**
     * Null-safe unboxing: Object → long. Returns 0L if null.
     */
    public static long unboxLong(Object o) {
        if (o == null) return 0L;
        return ((Number) o).longValue();
    }

    /**
     * Null-safe unboxing: Object → double. Returns 0.0 if null.
     */
    public static double unboxDouble(Object o) {
        if (o == null) return 0.0;
        return ((Number) o).doubleValue();
    }

    /**
     * Null-safe unboxing: Object → boolean. Returns false if null.
     */
    public static boolean unboxBoolean(Object o) {
        if (o == null) return false;
        return ((Boolean) o).booleanValue();
    }
}
