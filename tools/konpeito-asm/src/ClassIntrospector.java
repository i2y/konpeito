package com.konpeito.asm;

import org.objectweb.asm.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.jar.*;

/**
 * ClassIntrospector: Reads .class files from classpath using ASM ClassReader
 * and outputs method signatures as JSON.
 *
 * Usage: java -jar konpeito-asm.jar --introspect
 *
 * Reads JSON request from stdin:
 *   { "classpath": "path1:path2:...", "classes": ["com/example/Foo", ...] }
 *
 * Writes JSON response to stdout with method descriptors, constructors,
 * inner classes, and SAM interface detection.
 */
public class ClassIntrospector {

    public static void run() throws Exception {
        // Read JSON request from stdin
        String json;
        try (var reader = new BufferedReader(new InputStreamReader(System.in))) {
            var sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append('\n');
            }
            json = sb.toString();
        }

        var parser = new KonpeitoAssembler.JsonParser(json);
        var request = parser.parseObject();

        String classpath = (String) request.get("classpath");
        @SuppressWarnings("unchecked")
        List<Object> classNames = (List<Object>) request.get("classes");

        if (classpath == null || classNames == null) {
            System.err.println("Error: request must have 'classpath' and 'classes' keys");
            System.exit(1);
        }

        var introspector = new ClassIntrospector();
        var result = introspector.introspect(classpath, classNames);

        // Output JSON
        System.out.println(result);
    }

    /**
     * Introspect the given classes from the classpath.
     */
    public String introspect(String classpath, List<Object> classNames) throws Exception {
        // Build classpath entries
        List<Path> entries = new ArrayList<>();
        for (String entry : classpath.split(":")) {
            Path p = Path.of(entry.trim());
            if (Files.exists(p)) {
                entries.add(p);
            }
        }

        // Collect results
        Map<String, ClassInfo> results = new LinkedHashMap<>();

        for (Object nameObj : classNames) {
            String className = (String) nameObj;
            byte[] classBytes = findClassBytes(entries, className);
            if (classBytes != null) {
                ClassInfo info = analyzeClass(classBytes);
                results.put(className, info);

                // Also introspect inner classes referenced by this class
                for (String innerName : info.innerClassNames) {
                    if (!results.containsKey(innerName)) {
                        byte[] innerBytes = findClassBytes(entries, innerName);
                        if (innerBytes != null) {
                            ClassInfo innerInfo = analyzeClass(innerBytes);
                            // Store inner class info within the parent
                            info.innerClasses.put(innerName, innerInfo);
                        }
                    }
                }
            }
        }

        return toJson(results);
    }

    /**
     * Find .class bytes from classpath entries (JAR files or directories).
     */
    private byte[] findClassBytes(List<Path> entries, String className) throws Exception {
        String classFilePath = className + ".class";

        for (Path entry : entries) {
            if (Files.isDirectory(entry)) {
                // Directory: look for className.class
                Path classFile = entry.resolve(classFilePath);
                if (Files.exists(classFile)) {
                    return Files.readAllBytes(classFile);
                }
            } else if (entry.toString().endsWith(".jar")) {
                // JAR file: look inside
                try (JarFile jar = new JarFile(entry.toFile())) {
                    JarEntry jarEntry = jar.getJarEntry(classFilePath);
                    if (jarEntry != null) {
                        try (InputStream is = jar.getInputStream(jarEntry)) {
                            return is.readAllBytes();
                        }
                    }
                }
            }
        }
        return null;
    }

    /**
     * Analyze a single .class file using ASM ClassReader.
     */
    private ClassInfo analyzeClass(byte[] classBytes) {
        ClassInfo info = new ClassInfo();
        ClassReader reader = new ClassReader(classBytes);

        reader.accept(new ClassVisitor(Opcodes.ASM9) {
            @Override
            public void visit(int version, int access, String name, String signature,
                              String superName, String[] interfaces) {
                info.isInterface = (access & Opcodes.ACC_INTERFACE) != 0;
                if (interfaces != null) {
                    info.interfaces.addAll(Arrays.asList(interfaces));
                }
            }

            @Override
            public void visitInnerClass(String name, String outerName, String innerName, int access) {
                // Track inner classes that belong to the class being analyzed
                if (outerName != null) {
                    info.innerClassNames.add(name);
                }
            }

            @Override
            public FieldVisitor visitField(int access, String name, String descriptor,
                                            String signature, Object value) {
                // Only public, non-synthetic fields
                if ((access & Opcodes.ACC_PUBLIC) == 0) return null;
                if ((access & Opcodes.ACC_SYNTHETIC) != 0) return null;

                if ((access & Opcodes.ACC_STATIC) != 0) {
                    info.staticFields.put(name, descriptor);
                } else {
                    info.fields.put(name, descriptor);
                }
                return null;
            }

            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor,
                                              String signature, String[] exceptions) {
                // Only public methods
                if ((access & Opcodes.ACC_PUBLIC) == 0) return null;

                // Skip bridge/synthetic methods
                if ((access & Opcodes.ACC_BRIDGE) != 0) return null;
                if ((access & Opcodes.ACC_SYNTHETIC) != 0) return null;

                if (name.equals("<init>")) {
                    // Constructor
                    info.constructorDescriptor = descriptor;
                } else if (name.equals("<clinit>")) {
                    // Class initializer - skip
                } else if ((access & Opcodes.ACC_STATIC) != 0) {
                    // Static method
                    info.staticMethods.put(name, descriptor);
                } else if ((access & Opcodes.ACC_ABSTRACT) != 0) {
                    // Abstract method (for SAM interface detection)
                    info.abstractMethods.put(name, descriptor);
                    info.methods.put(name, descriptor);
                } else {
                    // Instance method
                    info.methods.put(name, descriptor);
                }

                return null;
            }
        }, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);

        return info;
    }

    /**
     * Convert results to JSON string.
     */
    private String toJson(Map<String, ClassInfo> results) {
        var sb = new StringBuilder();
        sb.append("{\"classes\":{");

        boolean firstClass = true;
        for (var entry : results.entrySet()) {
            if (!firstClass) sb.append(",");
            firstClass = false;

            sb.append("\"").append(escapeJson(entry.getKey())).append("\":");
            classInfoToJson(sb, entry.getValue());
        }

        sb.append("}}");
        return sb.toString();
    }

    private void classInfoToJson(StringBuilder sb, ClassInfo info) {
        sb.append("{");

        // methods
        sb.append("\"methods\":{");
        methodMapToJson(sb, info.methods);
        sb.append("},");

        // static_methods
        sb.append("\"static_methods\":{");
        methodMapToJson(sb, info.staticMethods);
        sb.append("},");

        // constructor
        if (info.constructorDescriptor != null) {
            sb.append("\"constructor\":{\"descriptor\":\"")
              .append(escapeJson(info.constructorDescriptor)).append("\"},");
        } else {
            sb.append("\"constructor\":null,");
        }

        // is_interface
        sb.append("\"is_interface\":").append(info.isInterface).append(",");

        // interfaces
        sb.append("\"interfaces\":[");
        boolean first = true;
        for (String iface : info.interfaces) {
            if (!first) sb.append(",");
            first = false;
            sb.append("\"").append(escapeJson(iface)).append("\"");
        }
        sb.append("],");

        // abstract_methods (for SAM detection)
        sb.append("\"abstract_methods\":{");
        methodMapToJson(sb, info.abstractMethods);
        sb.append("},");

        // fields
        sb.append("\"fields\":{");
        methodMapToJson(sb, info.fields);
        sb.append("},");

        // static_fields
        sb.append("\"static_fields\":{");
        methodMapToJson(sb, info.staticFields);
        sb.append("},");

        // inner_classes
        sb.append("\"inner_classes\":{");
        boolean firstInner = true;
        for (var innerEntry : info.innerClasses.entrySet()) {
            if (!firstInner) sb.append(",");
            firstInner = false;
            sb.append("\"").append(escapeJson(innerEntry.getKey())).append("\":");
            classInfoToJson(sb, innerEntry.getValue());
        }
        sb.append("}");

        sb.append("}");
    }

    private void methodMapToJson(StringBuilder sb, Map<String, String> methods) {
        boolean first = true;
        for (var entry : methods.entrySet()) {
            if (!first) sb.append(",");
            first = false;
            sb.append("\"").append(escapeJson(entry.getKey())).append("\":")
              .append("{\"descriptor\":\"").append(escapeJson(entry.getValue())).append("\"}");
        }
    }

    private String escapeJson(String s) {
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    /**
     * Internal class to hold introspection results for a single class.
     */
    static class ClassInfo {
        Map<String, String> methods = new LinkedHashMap<>();
        Map<String, String> staticMethods = new LinkedHashMap<>();
        Map<String, String> abstractMethods = new LinkedHashMap<>();
        Map<String, String> fields = new LinkedHashMap<>();
        Map<String, String> staticFields = new LinkedHashMap<>();
        String constructorDescriptor = null;
        boolean isInterface = false;
        List<String> interfaces = new ArrayList<>();
        List<String> innerClassNames = new ArrayList<>();
        Map<String, ClassInfo> innerClasses = new LinkedHashMap<>();
    }
}
