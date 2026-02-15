package konpeito.runtime;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * KJSON - Lightweight JSON parser and generator for Konpeito JVM backend.
 * No external dependencies. Maps to KonpeitoJSON Ruby module.
 *
 * Supported types:
 *   JSON object  -> HashMap<String, Object>
 *   JSON array   -> ArrayList<Object>
 *   JSON string  -> String
 *   JSON number  -> Long (integers) or Double (decimals)
 *   JSON boolean -> Boolean
 *   JSON null    -> null
 */
public class KJSON {

    // ========================================================================
    // Public API
    // ========================================================================

    /** KonpeitoJSON.parse(json_string) -> Object */
    public static Object parse(String json) {
        if (json == null || json.isEmpty()) {
            throw new RuntimeException("Empty JSON input");
        }
        Parser parser = new Parser(json);
        Object result = parser.parseValue();
        parser.skipWhitespace();
        if (parser.pos < parser.input.length()) {
            throw new RuntimeException("Unexpected trailing content at position " + parser.pos);
        }
        return result;
    }

    /** KonpeitoJSON.generate(obj) -> String */
    public static String generate(Object obj) {
        StringBuilder sb = new StringBuilder();
        writeValue(sb, obj, -1, 0);
        return sb.toString();
    }

    /** KonpeitoJSON.generate_pretty(obj, indent) -> String */
    public static String generatePretty(Object obj, long indent) {
        StringBuilder sb = new StringBuilder();
        writeValue(sb, obj, (int) indent, 0);
        sb.append('\n');
        return sb.toString();
    }

    // ========================================================================
    // JSON Parser
    // ========================================================================

    private static class Parser {
        final String input;
        int pos;

        Parser(String input) {
            this.input = input;
            this.pos = 0;
        }

        Object parseValue() {
            skipWhitespace();
            if (pos >= input.length()) {
                throw new RuntimeException("Unexpected end of JSON");
            }
            char c = input.charAt(pos);
            switch (c) {
                case '"': return parseString();
                case '{': return parseObject();
                case '[': return parseArray();
                case 't': return parseLiteral("true", Boolean.TRUE);
                case 'f': return parseLiteral("false", Boolean.FALSE);
                case 'n': return parseLiteral("null", null);
                default:
                    if (c == '-' || (c >= '0' && c <= '9')) {
                        return parseNumber();
                    }
                    throw new RuntimeException("Unexpected character '" + c + "' at position " + pos);
            }
        }

        String parseString() {
            expect('"');
            StringBuilder sb = new StringBuilder();
            while (pos < input.length()) {
                char c = input.charAt(pos++);
                if (c == '"') return sb.toString();
                if (c == '\\') {
                    if (pos >= input.length()) throw new RuntimeException("Unexpected end of string escape");
                    char esc = input.charAt(pos++);
                    switch (esc) {
                        case '"': sb.append('"'); break;
                        case '\\': sb.append('\\'); break;
                        case '/': sb.append('/'); break;
                        case 'b': sb.append('\b'); break;
                        case 'f': sb.append('\f'); break;
                        case 'n': sb.append('\n'); break;
                        case 'r': sb.append('\r'); break;
                        case 't': sb.append('\t'); break;
                        case 'u':
                            if (pos + 4 > input.length()) throw new RuntimeException("Invalid unicode escape");
                            String hex = input.substring(pos, pos + 4);
                            sb.append((char) Integer.parseInt(hex, 16));
                            pos += 4;
                            break;
                        default:
                            throw new RuntimeException("Invalid escape character: \\" + esc);
                    }
                } else {
                    sb.append(c);
                }
            }
            throw new RuntimeException("Unterminated string");
        }

        HashMap<String, Object> parseObject() {
            expect('{');
            HashMap<String, Object> map = new HashMap<>();
            skipWhitespace();
            if (pos < input.length() && input.charAt(pos) == '}') {
                pos++;
                return map;
            }
            while (true) {
                skipWhitespace();
                String key = parseString();
                skipWhitespace();
                expect(':');
                Object value = parseValue();
                map.put(key, value);
                skipWhitespace();
                if (pos >= input.length()) throw new RuntimeException("Unterminated object");
                char c = input.charAt(pos++);
                if (c == '}') return map;
                if (c != ',') throw new RuntimeException("Expected ',' or '}' in object at position " + (pos - 1));
            }
        }

        ArrayList<Object> parseArray() {
            expect('[');
            ArrayList<Object> list = new ArrayList<>();
            skipWhitespace();
            if (pos < input.length() && input.charAt(pos) == ']') {
                pos++;
                return list;
            }
            while (true) {
                list.add(parseValue());
                skipWhitespace();
                if (pos >= input.length()) throw new RuntimeException("Unterminated array");
                char c = input.charAt(pos++);
                if (c == ']') return list;
                if (c != ',') throw new RuntimeException("Expected ',' or ']' in array at position " + (pos - 1));
            }
        }

        Object parseNumber() {
            int start = pos;
            if (pos < input.length() && input.charAt(pos) == '-') pos++;
            if (pos >= input.length()) throw new RuntimeException("Invalid number");

            // Integer part
            if (input.charAt(pos) == '0') {
                pos++;
            } else if (input.charAt(pos) >= '1' && input.charAt(pos) <= '9') {
                while (pos < input.length() && input.charAt(pos) >= '0' && input.charAt(pos) <= '9') pos++;
            } else {
                throw new RuntimeException("Invalid number at position " + pos);
            }

            boolean isFloat = false;
            // Fractional part
            if (pos < input.length() && input.charAt(pos) == '.') {
                isFloat = true;
                pos++;
                if (pos >= input.length() || input.charAt(pos) < '0' || input.charAt(pos) > '9') {
                    throw new RuntimeException("Invalid number: no digits after decimal point");
                }
                while (pos < input.length() && input.charAt(pos) >= '0' && input.charAt(pos) <= '9') pos++;
            }

            // Exponent part
            if (pos < input.length() && (input.charAt(pos) == 'e' || input.charAt(pos) == 'E')) {
                isFloat = true;
                pos++;
                if (pos < input.length() && (input.charAt(pos) == '+' || input.charAt(pos) == '-')) pos++;
                if (pos >= input.length() || input.charAt(pos) < '0' || input.charAt(pos) > '9') {
                    throw new RuntimeException("Invalid number: no digits in exponent");
                }
                while (pos < input.length() && input.charAt(pos) >= '0' && input.charAt(pos) <= '9') pos++;
            }

            String numStr = input.substring(start, pos);
            if (isFloat) {
                return Double.parseDouble(numStr);
            } else {
                try {
                    return Long.parseLong(numStr);
                } catch (NumberFormatException e) {
                    return Double.parseDouble(numStr); // Fallback for very large integers
                }
            }
        }

        Object parseLiteral(String expected, Object value) {
            if (!input.startsWith(expected, pos)) {
                throw new RuntimeException("Expected '" + expected + "' at position " + pos);
            }
            pos += expected.length();
            return value;
        }

        void expect(char c) {
            if (pos >= input.length() || input.charAt(pos) != c) {
                throw new RuntimeException("Expected '" + c + "' at position " + pos);
            }
            pos++;
        }

        void skipWhitespace() {
            while (pos < input.length()) {
                char c = input.charAt(pos);
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    pos++;
                } else {
                    break;
                }
            }
        }
    }

    // ========================================================================
    // JSON Generator
    // ========================================================================

    @SuppressWarnings("unchecked")
    private static void writeValue(StringBuilder sb, Object value, int indent, int depth) {
        if (value == null) {
            sb.append("null");
        } else if (value instanceof String) {
            writeString(sb, (String) value);
        } else if (value instanceof Long) {
            sb.append(((Long) value).longValue());
        } else if (value instanceof Integer) {
            sb.append(((Integer) value).intValue());
        } else if (value instanceof Double) {
            double d = (Double) value;
            if (d == Math.floor(d) && !Double.isInfinite(d) && Math.abs(d) < 1e15) {
                sb.append(String.format("%.1f", d));
            } else {
                sb.append(Double.toString(d));
            }
        } else if (value instanceof Float) {
            sb.append(Float.toString((Float) value));
        } else if (value instanceof Boolean) {
            sb.append(((Boolean) value).booleanValue() ? "true" : "false");
        } else if (value instanceof Map) {
            writeObject(sb, (Map<String, Object>) value, indent, depth);
        } else if (value instanceof List) {
            writeArray(sb, (List<Object>) value, indent, depth);
        } else if (value instanceof KArray) {
            writeKArray(sb, (KArray) value, indent, depth);
        } else if (value instanceof KHash) {
            writeKHash(sb, (KHash) value, indent, depth);
        } else {
            writeString(sb, value.toString());
        }
    }

    private static void writeString(StringBuilder sb, String s) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\b': sb.append("\\b"); break;
                case '\f': sb.append("\\f"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
    }

    private static void writeObject(StringBuilder sb, Map<String, Object> map, int indent, int depth) {
        if (map.isEmpty()) {
            sb.append("{}");
            return;
        }
        boolean pretty = indent > 0;
        sb.append('{');
        boolean first = true;
        for (Map.Entry<String, Object> entry : map.entrySet()) {
            if (!first) sb.append(',');
            first = false;
            if (pretty) {
                sb.append('\n');
                writeIndent(sb, indent, depth + 1);
            }
            writeString(sb, entry.getKey());
            sb.append(pretty ? ": " : ":");
            writeValue(sb, entry.getValue(), indent, depth + 1);
        }
        if (pretty) {
            sb.append('\n');
            writeIndent(sb, indent, depth);
        }
        sb.append('}');
    }

    private static void writeArray(StringBuilder sb, List<Object> list, int indent, int depth) {
        if (list.isEmpty()) {
            sb.append("[]");
            return;
        }
        boolean pretty = indent > 0;
        sb.append('[');
        for (int i = 0; i < list.size(); i++) {
            if (i > 0) sb.append(',');
            if (pretty) {
                sb.append('\n');
                writeIndent(sb, indent, depth + 1);
            }
            writeValue(sb, list.get(i), indent, depth + 1);
        }
        if (pretty) {
            sb.append('\n');
            writeIndent(sb, indent, depth);
        }
        sb.append(']');
    }

    private static void writeKArray(StringBuilder sb, KArray arr, int indent, int depth) {
        int size = (int) arr.length();
        if (size == 0) {
            sb.append("[]");
            return;
        }
        boolean pretty = indent > 0;
        sb.append('[');
        for (int i = 0; i < size; i++) {
            if (i > 0) sb.append(',');
            if (pretty) {
                sb.append('\n');
                writeIndent(sb, indent, depth + 1);
            }
            writeValue(sb, arr.get(i), indent, depth + 1);
        }
        if (pretty) {
            sb.append('\n');
            writeIndent(sb, indent, depth);
        }
        sb.append(']');
    }

    @SuppressWarnings("unchecked")
    private static void writeKHash(StringBuilder sb, KHash hash, int indent, int depth) {
        KArray keys = hash.rubyKeys();
        int size = (int) keys.length();
        if (size == 0) {
            sb.append("{}");
            return;
        }
        boolean pretty = indent > 0;
        sb.append('{');
        for (int i = 0; i < size; i++) {
            if (i > 0) sb.append(',');
            if (pretty) {
                sb.append('\n');
                writeIndent(sb, indent, depth + 1);
            }
            Object key = keys.get(i);
            writeString(sb, key != null ? key.toString() : "null");
            sb.append(pretty ? ": " : ":");
            writeValue(sb, hash.get(key), indent, depth + 1);
        }
        if (pretty) {
            sb.append('\n');
            writeIndent(sb, indent, depth);
        }
        sb.append('}');
    }

    private static void writeIndent(StringBuilder sb, int indent, int depth) {
        int spaces = indent * depth;
        for (int i = 0; i < spaces; i++) {
            sb.append(' ');
        }
    }
}
