package com.konpeito.asm;

import org.objectweb.asm.*;
import java.io.*;
import java.lang.invoke.*;
import java.nio.file.*;
import java.util.*;

/**
 * KonpeitoAssembler: Reads JSON IR from stdin, generates .class files using ASM.
 *
 * Usage: java -cp konpeito-asm.jar com.konpeito.asm.KonpeitoAssembler <output_dir>
 *
 * JSON IR is read from stdin. Each class definition produces a .class file in output_dir.
 */
public class KonpeitoAssembler {

    public static void main(String[] args) throws Exception {
        if (args.length >= 1 && args[0].equals("--introspect")) {
            ClassIntrospector.run();
            return;
        }

        if (args.length < 1) {
            System.err.println("Usage: KonpeitoAssembler <output_dir>");
            System.err.println("       KonpeitoAssembler --introspect");
            System.exit(1);
        }

        String outputDir = args[0];
        Files.createDirectories(Path.of(outputDir));

        // Read JSON from stdin
        String json;
        try (var reader = new BufferedReader(new InputStreamReader(System.in))) {
            var sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append('\n');
            }
            json = sb.toString();
        }

        // Parse and generate
        var assembler = new KonpeitoAssembler();
        assembler.processJson(json, outputDir);
    }

    // Class hierarchy map: className -> superClassName (for COMPUTE_FRAMES resolution)
    private final Map<String, String> classHierarchy = new HashMap<>();
    // Interface set: classNames that are interfaces
    private final Set<String> interfaceSet = new HashSet<>();

    public void processJson(String json, String outputDir) throws Exception {
        var parser = new JsonParser(json);
        var root = parser.parseObject();

        @SuppressWarnings("unchecked")
        var classes = (List<Map<String, Object>>) root.get("classes");
        if (classes == null) {
            System.err.println("Error: no 'classes' key in JSON IR");
            System.exit(1);
        }

        // Build class hierarchy map before generating any classes
        for (var classDef : classes) {
            String name = (String) classDef.get("name");
            String superName = (String) classDef.getOrDefault("superName", "java/lang/Object");
            classHierarchy.put(name, superName);
            var access = (List<?>) classDef.get("access");
            if (access != null && access.contains("interface")) {
                interfaceSet.add(name);
            }
        }

        for (var classDef : classes) {
            generateClass(classDef, outputDir);
        }
    }

    private void generateClass(Map<String, Object> classDef, String outputDir) throws Exception {
        String className = (String) classDef.get("name");
        String superName = (String) classDef.getOrDefault("superName", "java/lang/Object");
        int accessFlags = parseAccessFlags((List<?>) classDef.get("access"));

        @SuppressWarnings("unchecked")
        var interfaces = (List<String>) classDef.getOrDefault("interfaces", List.of());

        // Use custom ClassWriter that knows about our generated class hierarchy
        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS) {
            @Override
            protected String getCommonSuperClass(String type1, String type2) {
                // If both are in our hierarchy, walk up to find common ancestor
                if (classHierarchy.containsKey(type1) || classHierarchy.containsKey(type2)) {
                    // Collect all ancestors of type1
                    Set<String> ancestors1 = new HashSet<>();
                    String t = type1;
                    while (t != null && !t.equals("java/lang/Object")) {
                        ancestors1.add(t);
                        t = classHierarchy.getOrDefault(t, "java/lang/Object");
                        if (ancestors1.contains(t)) break; // prevent infinite loop
                    }
                    ancestors1.add("java/lang/Object");

                    // Walk up type2's chain until we find a common ancestor
                    t = type2;
                    while (t != null) {
                        if (ancestors1.contains(t)) return t;
                        if (t.equals("java/lang/Object")) break;
                        t = classHierarchy.getOrDefault(t, "java/lang/Object");
                    }
                    return "java/lang/Object";
                }
                // Fall back to default for standard library classes
                try {
                    return super.getCommonSuperClass(type1, type2);
                } catch (Exception e) {
                    return "java/lang/Object";
                }
            }
        };
        cw.visit(Opcodes.V21, accessFlags, className, null, superName,
                interfaces.isEmpty() ? null : interfaces.toArray(new String[0]));

        // Generate record components (for Java Records)
        @SuppressWarnings("unchecked")
        var recordComponents = (List<Map<String, Object>>) classDef.getOrDefault("recordComponents", List.of());
        for (var comp : recordComponents) {
            String compName = (String) comp.get("name");
            String compDescriptor = (String) comp.get("descriptor");
            cw.visitRecordComponent(compName, compDescriptor, null).visitEnd();
        }

        // Generate fields
        @SuppressWarnings("unchecked")
        var fields = (List<Map<String, Object>>) classDef.getOrDefault("fields", List.of());
        for (var field : fields) {
            generateField(cw, field);
        }

        // Generate methods
        @SuppressWarnings("unchecked")
        var methods = (List<Map<String, Object>>) classDef.getOrDefault("methods", List.of());
        for (var method : methods) {
            try {
                generateMethod(cw, method);
            } catch (Exception e) {
                String mName = (String) method.get("name");
                String mDesc = (String) method.get("descriptor");
                System.err.println("ASM error in class=" + className + " method=" + mName + " descriptor=" + mDesc);
                throw e;
            }
        }

        cw.visitEnd();

        // Write .class file
        byte[] bytecode = cw.toByteArray();
        String filePath = outputDir + "/" + className + ".class";
        Path path = Path.of(filePath);
        Files.createDirectories(path.getParent());
        Files.write(path, bytecode);
    }

    private void generateField(ClassWriter cw, Map<String, Object> field) {
        String name = (String) field.get("name");
        String descriptor = (String) field.get("descriptor");
        int access = parseAccessFlags((List<?>) field.get("access"));
        Object value = field.get("value"); // for static final constants
        cw.visitField(access, name, descriptor, null, value);
    }

    private void generateMethod(ClassWriter cw, Map<String, Object> method) {
        String name = (String) method.get("name");
        String descriptor = (String) method.get("descriptor");
        int access = parseAccessFlags((List<?>) method.get("access"));

        MethodVisitor mv = cw.visitMethod(access, name, descriptor, null, null);

        // Abstract methods have no body
        if ((access & Opcodes.ACC_ABSTRACT) != 0) {
            mv.visitEnd();
            return;
        }

        mv.visitCode();

        // Label registry for jumps
        Map<String, Label> labels = new HashMap<>();

        // Process exception table BEFORE instructions (ASM requires this)
        @SuppressWarnings("unchecked")
        var exceptionTable = (List<Map<String, Object>>)
            method.getOrDefault("exceptionTable", List.of());
        for (var entry : exceptionTable) {
            mv.visitTryCatchBlock(
                getLabel(labels, (String) entry.get("start")),
                getLabel(labels, (String) entry.get("end")),
                getLabel(labels, (String) entry.get("handler")),
                (String) entry.get("type"));  // null for finally/catch-all
        }

        @SuppressWarnings("unchecked")
        var instructions = (List<Map<String, Object>>) method.getOrDefault("instructions", List.of());
        for (var inst : instructions) {
            emitInstruction(mv, inst, labels);
        }

        mv.visitMaxs(0, 0); // ASM COMPUTE_MAXS handles this
        mv.visitEnd();
    }

    private void emitInstruction(MethodVisitor mv, Map<String, Object> inst, Map<String, Label> labels) {
        String op = (String) inst.get("op");

        switch (op) {
            // --- Labels ---
            case "label" -> {
                String labelName = (String) inst.get("name");
                mv.visitLabel(getLabel(labels, labelName));
            }

            // --- Load/Store (long takes 2 slots) ---
            case "lload" -> mv.visitVarInsn(Opcodes.LLOAD, getInt(inst, "var"));
            case "lstore" -> mv.visitVarInsn(Opcodes.LSTORE, getInt(inst, "var"));
            case "dload" -> mv.visitVarInsn(Opcodes.DLOAD, getInt(inst, "var"));
            case "dstore" -> mv.visitVarInsn(Opcodes.DSTORE, getInt(inst, "var"));
            case "iload" -> mv.visitVarInsn(Opcodes.ILOAD, getInt(inst, "var"));
            case "istore" -> mv.visitVarInsn(Opcodes.ISTORE, getInt(inst, "var"));
            case "aload" -> mv.visitVarInsn(Opcodes.ALOAD, getInt(inst, "var"));
            case "astore" -> mv.visitVarInsn(Opcodes.ASTORE, getInt(inst, "var"));

            // --- Constants ---
            case "ldc" -> {
                Object value = inst.get("value");
                if (value instanceof String s) {
                    mv.visitLdcInsn(s);
                } else if (value instanceof Number n) {
                    // For int/float constants
                    if (n instanceof Double || (n instanceof Number && n.toString().contains("."))) {
                        mv.visitLdcInsn(n.doubleValue());
                    } else {
                        mv.visitLdcInsn(n.intValue());
                    }
                }
            }
            case "ldc2_w" -> {
                Object value = inst.get("value");
                String type = (String) inst.getOrDefault("type", "long");
                if ("double".equals(type)) {
                    mv.visitLdcInsn(((Number) value).doubleValue());
                } else {
                    mv.visitLdcInsn(((Number) value).longValue());
                }
            }
            case "iconst" -> {
                int val = getInt(inst, "value");
                switch (val) {
                    case -1 -> mv.visitInsn(Opcodes.ICONST_M1);
                    case 0 -> mv.visitInsn(Opcodes.ICONST_0);
                    case 1 -> mv.visitInsn(Opcodes.ICONST_1);
                    case 2 -> mv.visitInsn(Opcodes.ICONST_2);
                    case 3 -> mv.visitInsn(Opcodes.ICONST_3);
                    case 4 -> mv.visitInsn(Opcodes.ICONST_4);
                    case 5 -> mv.visitInsn(Opcodes.ICONST_5);
                    default -> mv.visitIntInsn(Opcodes.BIPUSH, val);
                }
            }
            case "lconst_0" -> mv.visitInsn(Opcodes.LCONST_0);
            case "lconst_1" -> mv.visitInsn(Opcodes.LCONST_1);
            case "dconst_0" -> mv.visitInsn(Opcodes.DCONST_0);
            case "dconst_1" -> mv.visitInsn(Opcodes.DCONST_1);
            case "aconst_null" -> mv.visitInsn(Opcodes.ACONST_NULL);

            // --- Arithmetic (int) ---
            case "iadd" -> mv.visitInsn(Opcodes.IADD);
            case "isub" -> mv.visitInsn(Opcodes.ISUB);

            // --- Arithmetic (long) ---
            case "ladd" -> mv.visitInsn(Opcodes.LADD);
            case "lsub" -> mv.visitInsn(Opcodes.LSUB);
            case "lmul" -> mv.visitInsn(Opcodes.LMUL);
            case "ldiv" -> mv.visitInsn(Opcodes.LDIV);
            case "lrem" -> mv.visitInsn(Opcodes.LREM);
            case "lneg" -> mv.visitInsn(Opcodes.LNEG);
            case "land" -> mv.visitInsn(Opcodes.LAND);
            case "lor" -> mv.visitInsn(Opcodes.LOR);
            case "lxor" -> mv.visitInsn(Opcodes.LXOR);
            case "lshl" -> mv.visitInsn(Opcodes.LSHL);
            case "lshr" -> mv.visitInsn(Opcodes.LSHR);
            case "lushr" -> mv.visitInsn(Opcodes.LUSHR);

            // --- Arithmetic (double) ---
            case "dadd" -> mv.visitInsn(Opcodes.DADD);
            case "dsub" -> mv.visitInsn(Opcodes.DSUB);
            case "dmul" -> mv.visitInsn(Opcodes.DMUL);
            case "ddiv" -> mv.visitInsn(Opcodes.DDIV);
            case "drem" -> mv.visitInsn(Opcodes.DREM);
            case "dneg" -> mv.visitInsn(Opcodes.DNEG);

            // --- Type conversions ---
            case "l2d" -> mv.visitInsn(Opcodes.L2D);
            case "d2l" -> mv.visitInsn(Opcodes.D2L);
            case "i2l" -> mv.visitInsn(Opcodes.I2L);
            case "l2i" -> mv.visitInsn(Opcodes.L2I);
            case "i2d" -> mv.visitInsn(Opcodes.I2D);
            case "d2i" -> mv.visitInsn(Opcodes.D2I);

            // --- Comparisons ---
            case "lcmp" -> mv.visitInsn(Opcodes.LCMP);
            case "dcmpl" -> mv.visitInsn(Opcodes.DCMPL);
            case "dcmpg" -> mv.visitInsn(Opcodes.DCMPG);

            // --- Branch instructions ---
            case "ifeq" -> mv.visitJumpInsn(Opcodes.IFEQ, getLabel(labels, (String) inst.get("target")));
            case "ifne" -> mv.visitJumpInsn(Opcodes.IFNE, getLabel(labels, (String) inst.get("target")));
            case "iflt" -> mv.visitJumpInsn(Opcodes.IFLT, getLabel(labels, (String) inst.get("target")));
            case "ifge" -> mv.visitJumpInsn(Opcodes.IFGE, getLabel(labels, (String) inst.get("target")));
            case "ifgt" -> mv.visitJumpInsn(Opcodes.IFGT, getLabel(labels, (String) inst.get("target")));
            case "ifle" -> mv.visitJumpInsn(Opcodes.IFLE, getLabel(labels, (String) inst.get("target")));
            case "if_icmpeq" -> mv.visitJumpInsn(Opcodes.IF_ICMPEQ, getLabel(labels, (String) inst.get("target")));
            case "if_icmpne" -> mv.visitJumpInsn(Opcodes.IF_ICMPNE, getLabel(labels, (String) inst.get("target")));
            case "if_icmplt" -> mv.visitJumpInsn(Opcodes.IF_ICMPLT, getLabel(labels, (String) inst.get("target")));
            case "if_icmpge" -> mv.visitJumpInsn(Opcodes.IF_ICMPGE, getLabel(labels, (String) inst.get("target")));
            case "if_icmpgt" -> mv.visitJumpInsn(Opcodes.IF_ICMPGT, getLabel(labels, (String) inst.get("target")));
            case "if_icmple" -> mv.visitJumpInsn(Opcodes.IF_ICMPLE, getLabel(labels, (String) inst.get("target")));
            case "ifnull" -> mv.visitJumpInsn(Opcodes.IFNULL, getLabel(labels, (String) inst.get("target")));
            case "ifnonnull" -> mv.visitJumpInsn(Opcodes.IFNONNULL, getLabel(labels, (String) inst.get("target")));
            case "goto" -> mv.visitJumpInsn(Opcodes.GOTO, getLabel(labels, (String) inst.get("target")));

            // --- Return ---
            case "lreturn" -> mv.visitInsn(Opcodes.LRETURN);
            case "dreturn" -> mv.visitInsn(Opcodes.DRETURN);
            case "ireturn" -> mv.visitInsn(Opcodes.IRETURN);
            case "areturn" -> mv.visitInsn(Opcodes.ARETURN);
            case "return" -> mv.visitInsn(Opcodes.RETURN);

            // --- Method calls ---
            case "invokestatic" -> {
                    boolean isIface = inst.containsKey("isInterface") && (boolean) inst.get("isInterface");
                    mv.visitMethodInsn(Opcodes.INVOKESTATIC,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"), isIface);
                }
            case "invokevirtual" -> mv.visitMethodInsn(Opcodes.INVOKEVIRTUAL,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"), false);
            case "invokespecial" -> mv.visitMethodInsn(Opcodes.INVOKESPECIAL,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"), false);
            case "invokeinterface" -> mv.visitMethodInsn(Opcodes.INVOKEINTERFACE,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"), true);

            // --- invokedynamic (for blocks/lambdas via LambdaMetafactory) ---
            case "invokedynamic" -> {
                String indyName = (String) inst.get("name");
                String indyDescriptor = (String) inst.get("descriptor");

                // Bootstrap method handle
                Handle bootstrapHandle = new Handle(
                        Opcodes.H_INVOKESTATIC,
                        (String) inst.get("bootstrapOwner"),
                        (String) inst.get("bootstrapName"),
                        (String) inst.get("bootstrapDescriptor"),
                        false);

                // Bootstrap arguments
                @SuppressWarnings("unchecked")
                var bsmArgs = (List<Map<String, Object>>) inst.getOrDefault("bootstrapArgs", List.of());
                Object[] args = new Object[bsmArgs.size()];
                for (int i = 0; i < bsmArgs.size(); i++) {
                    Map<String, Object> arg = bsmArgs.get(i);
                    String argType = (String) arg.get("type");
                    switch (argType) {
                        case "methodType" -> args[i] = Type.getMethodType((String) arg.get("descriptor"));
                        case "handle" -> {
                            int tag = parseHandleTag((String) arg.get("tag"));
                            boolean isInterface = arg.containsKey("itf") && Boolean.TRUE.equals(arg.get("itf"));
                            args[i] = new Handle(tag,
                                    (String) arg.get("owner"),
                                    (String) arg.get("name"),
                                    (String) arg.get("descriptor"),
                                    isInterface);
                        }
                        default -> throw new RuntimeException("Unknown bootstrap arg type: " + argType);
                    }
                }

                mv.visitInvokeDynamicInsn(indyName, indyDescriptor, bootstrapHandle, args);
            }

            // --- Field access ---
            case "getfield" -> mv.visitFieldInsn(Opcodes.GETFIELD,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"));
            case "putfield" -> mv.visitFieldInsn(Opcodes.PUTFIELD,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"));
            case "getstatic" -> mv.visitFieldInsn(Opcodes.GETSTATIC,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"));
            case "putstatic" -> mv.visitFieldInsn(Opcodes.PUTSTATIC,
                    (String) inst.get("owner"), (String) inst.get("name"),
                    (String) inst.get("descriptor"));

            // --- Object creation ---
            case "new" -> mv.visitTypeInsn(Opcodes.NEW, (String) inst.get("type"));
            case "dup" -> mv.visitInsn(Opcodes.DUP);
            case "dup2" -> mv.visitInsn(Opcodes.DUP2);
            case "dup_x1" -> mv.visitInsn(Opcodes.DUP_X1);
            case "dup_x2" -> mv.visitInsn(Opcodes.DUP_X2);
            case "dup2_x1" -> mv.visitInsn(Opcodes.DUP2_X1);
            case "dup2_x2" -> mv.visitInsn(Opcodes.DUP2_X2);
            case "pop" -> mv.visitInsn(Opcodes.POP);
            case "pop2" -> mv.visitInsn(Opcodes.POP2);
            case "swap" -> mv.visitInsn(Opcodes.SWAP);

            // --- Type checks ---
            case "instanceof" -> mv.visitTypeInsn(Opcodes.INSTANCEOF, (String) inst.get("type"));
            case "checkcast" -> mv.visitTypeInsn(Opcodes.CHECKCAST, (String) inst.get("type"));

            // --- Array operations ---
            case "newarray" -> {
                String atype = (String) inst.get("type");
                int typeCode = switch (atype) {
                    case "long" -> Opcodes.T_LONG;
                    case "double" -> Opcodes.T_DOUBLE;
                    case "int" -> Opcodes.T_INT;
                    case "byte" -> Opcodes.T_BYTE;
                    case "boolean" -> Opcodes.T_BOOLEAN;
                    default -> Opcodes.T_LONG;
                };
                mv.visitIntInsn(Opcodes.NEWARRAY, typeCode);
            }
            case "anewarray" -> mv.visitTypeInsn(Opcodes.ANEWARRAY, (String) inst.get("type"));
            case "arraylength" -> mv.visitInsn(Opcodes.ARRAYLENGTH);
            case "laload" -> mv.visitInsn(Opcodes.LALOAD);
            case "lastore" -> mv.visitInsn(Opcodes.LASTORE);
            case "daload" -> mv.visitInsn(Opcodes.DALOAD);
            case "dastore" -> mv.visitInsn(Opcodes.DASTORE);
            case "aaload" -> mv.visitInsn(Opcodes.AALOAD);
            case "aastore" -> mv.visitInsn(Opcodes.AASTORE);

            // --- Exception handling ---
            case "athrow" -> mv.visitInsn(Opcodes.ATHROW);

            // --- Line number (for debugging) ---
            case "linenumber" -> {
                int line = getInt(inst, "line");
                String labelName = (String) inst.get("label");
                if (labelName != null) {
                    mv.visitLineNumber(line, getLabel(labels, labelName));
                }
            }

            default -> System.err.println("Warning: unknown instruction: " + op);
        }
    }

    // --- Helpers ---

    private Label getLabel(Map<String, Label> labels, String name) {
        return labels.computeIfAbsent(name, k -> new Label());
    }

    private int getInt(Map<String, Object> inst, String key) {
        Object val = inst.get(key);
        if (val instanceof Number n) return n.intValue();
        throw new RuntimeException("Expected int for key '" + key + "', got: " + val);
    }

    private int parseHandleTag(String tag) {
        return switch (tag) {
            case "H_GETFIELD" -> Opcodes.H_GETFIELD;
            case "H_GETSTATIC" -> Opcodes.H_GETSTATIC;
            case "H_PUTFIELD" -> Opcodes.H_PUTFIELD;
            case "H_PUTSTATIC" -> Opcodes.H_PUTSTATIC;
            case "H_INVOKEVIRTUAL" -> Opcodes.H_INVOKEVIRTUAL;
            case "H_INVOKESTATIC" -> Opcodes.H_INVOKESTATIC;
            case "H_INVOKESPECIAL" -> Opcodes.H_INVOKESPECIAL;
            case "H_NEWINVOKESPECIAL" -> Opcodes.H_NEWINVOKESPECIAL;
            case "H_INVOKEINTERFACE" -> Opcodes.H_INVOKEINTERFACE;
            default -> throw new RuntimeException("Unknown handle tag: " + tag);
        };
    }

    private int parseAccessFlags(List<?> flags) {
        if (flags == null) return 0;
        int result = 0;
        for (Object flag : flags) {
            result |= switch ((String) flag) {
                case "public" -> Opcodes.ACC_PUBLIC;
                case "private" -> Opcodes.ACC_PRIVATE;
                case "protected" -> Opcodes.ACC_PROTECTED;
                case "static" -> Opcodes.ACC_STATIC;
                case "final" -> Opcodes.ACC_FINAL;
                case "abstract" -> Opcodes.ACC_ABSTRACT;
                case "interface" -> Opcodes.ACC_INTERFACE;
                case "super" -> Opcodes.ACC_SUPER;
                case "synthetic" -> Opcodes.ACC_SYNTHETIC;
                case "record" -> Opcodes.ACC_RECORD;
                default -> 0;
            };
        }
        return result;
    }

    // ========================================================================
    // Minimal JSON Parser (no external dependencies)
    // ========================================================================
    static class JsonParser {
        private final String input;
        private int pos;

        JsonParser(String input) {
            this.input = input;
            this.pos = 0;
        }

        Map<String, Object> parseObject() {
            skipWhitespace();
            expect('{');
            var map = new LinkedHashMap<String, Object>();
            skipWhitespace();
            if (peek() != '}') {
                do {
                    skipWhitespace();
                    String key = parseString();
                    skipWhitespace();
                    expect(':');
                    skipWhitespace();
                    Object value = parseValue();
                    map.put(key, value);
                    skipWhitespace();
                } while (tryConsume(','));
            }
            expect('}');
            return map;
        }

        List<Object> parseArray() {
            expect('[');
            var list = new ArrayList<>();
            skipWhitespace();
            if (peek() != ']') {
                do {
                    skipWhitespace();
                    list.add(parseValue());
                    skipWhitespace();
                } while (tryConsume(','));
            }
            expect(']');
            return list;
        }

        Object parseValue() {
            skipWhitespace();
            char c = peek();
            return switch (c) {
                case '"' -> parseString();
                case '{' -> parseObject();
                case '[' -> parseArray();
                case 't' -> { consume("true"); yield Boolean.TRUE; }
                case 'f' -> { consume("false"); yield Boolean.FALSE; }
                case 'n' -> { consume("null"); yield null; }
                default -> parseNumber();
            };
        }

        String parseString() {
            expect('"');
            var sb = new StringBuilder();
            while (pos < input.length()) {
                char c = input.charAt(pos++);
                if (c == '"') return sb.toString();
                if (c == '\\') {
                    char esc = input.charAt(pos++);
                    switch (esc) {
                        case '"' -> sb.append('"');
                        case '\\' -> sb.append('\\');
                        case '/' -> sb.append('/');
                        case 'n' -> sb.append('\n');
                        case 'r' -> sb.append('\r');
                        case 't' -> sb.append('\t');
                        case 'u' -> {
                            String hex = input.substring(pos, pos + 4);
                            sb.append((char) Integer.parseInt(hex, 16));
                            pos += 4;
                        }
                        default -> sb.append(esc);
                    }
                } else {
                    sb.append(c);
                }
            }
            throw new RuntimeException("Unterminated string");
        }

        Number parseNumber() {
            int start = pos;
            if (peek() == '-') pos++;
            while (pos < input.length() && Character.isDigit(input.charAt(pos))) pos++;
            boolean isFloat = false;
            if (pos < input.length() && input.charAt(pos) == '.') {
                isFloat = true;
                pos++;
                while (pos < input.length() && Character.isDigit(input.charAt(pos))) pos++;
            }
            if (pos < input.length() && (input.charAt(pos) == 'e' || input.charAt(pos) == 'E')) {
                isFloat = true;
                pos++;
                if (pos < input.length() && (input.charAt(pos) == '+' || input.charAt(pos) == '-')) pos++;
                while (pos < input.length() && Character.isDigit(input.charAt(pos))) pos++;
            }
            String num = input.substring(start, pos);
            if (isFloat) return Double.parseDouble(num);
            long val = Long.parseLong(num);
            if (val >= Integer.MIN_VALUE && val <= Integer.MAX_VALUE) return (int) val;
            return val;
        }

        char peek() {
            if (pos >= input.length()) throw new RuntimeException("Unexpected end of input");
            return input.charAt(pos);
        }

        void expect(char c) {
            skipWhitespace();
            if (pos >= input.length() || input.charAt(pos) != c) {
                throw new RuntimeException("Expected '" + c + "' at pos " + pos +
                        ", got: " + (pos < input.length() ? "'" + input.charAt(pos) + "'" : "EOF"));
            }
            pos++;
        }

        boolean tryConsume(char c) {
            skipWhitespace();
            if (pos < input.length() && input.charAt(pos) == c) {
                pos++;
                return true;
            }
            return false;
        }

        void consume(String s) {
            for (char c : s.toCharArray()) {
                if (pos >= input.length() || input.charAt(pos) != c) {
                    throw new RuntimeException("Expected '" + s + "' at pos " + pos);
                }
                pos++;
            }
        }

        void skipWhitespace() {
            while (pos < input.length() && Character.isWhitespace(input.charAt(pos))) pos++;
        }
    }
}
