package konpeito.runtime;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

/**
 * KHTTP - HTTP client for Konpeito JVM backend.
 * Maps to KonpeitoHTTP Ruby module.
 * Uses java.net.http.HttpClient (Java 11+).
 */
public class KHTTP {
    private static final HttpClient CLIENT = HttpClient.newBuilder()
            .followRedirects(HttpClient.Redirect.NORMAL)
            .connectTimeout(Duration.ofSeconds(30))
            .build();

    /** KonpeitoHTTP.get(url) -> String (body) */
    public static String get(String url) {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(30))
                    .GET()
                    .build();
            HttpResponse<String> response = CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
            return response.body();
        } catch (Exception e) {
            throw new RuntimeException("HTTP GET failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoHTTP.post(url, body) -> String (body) */
    public static String post(String url, String body) {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(30))
                    .POST(HttpRequest.BodyPublishers.ofString(body != null ? body : ""))
                    .header("Content-Type", "application/json")
                    .build();
            HttpResponse<String> response = CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
            return response.body();
        } catch (Exception e) {
            throw new RuntimeException("HTTP POST failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoHTTP.get_response(url) -> KHash {status, body, headers} */
    @SuppressWarnings("unchecked")
    public static KHash<String, Object> getResponse(String url) {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(30))
                    .GET()
                    .build();
            HttpResponse<String> response = CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
            return buildResponseHash(response);
        } catch (Exception e) {
            throw new RuntimeException("HTTP GET failed: " + e.getMessage(), e);
        }
    }

    /** KonpeitoHTTP.request(method, url, body, headers) -> KHash */
    @SuppressWarnings("unchecked")
    public static KHash<String, Object> request(String method, String url, String body, KHash<String, String> headers) {
        try {
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(30));

            // Set method and body
            if (body != null && !body.isEmpty()) {
                builder.method(method.toUpperCase(), HttpRequest.BodyPublishers.ofString(body));
            } else {
                builder.method(method.toUpperCase(), HttpRequest.BodyPublishers.noBody());
            }

            // Set custom headers
            if (headers != null) {
                for (Map.Entry<String, String> entry : headers.entrySet()) {
                    builder.header(entry.getKey(), entry.getValue());
                }
            }

            HttpResponse<String> response = CLIENT.send(builder.build(), HttpResponse.BodyHandlers.ofString());
            return buildResponseHash(response);
        } catch (Exception e) {
            throw new RuntimeException("HTTP request failed: " + e.getMessage(), e);
        }
    }

    @SuppressWarnings("unchecked")
    private static KHash<String, Object> buildResponseHash(HttpResponse<String> response) {
        KHash<String, Object> result = new KHash<>();
        result.put("status", (long) response.statusCode());
        result.put("body", response.body());

        // Build headers hash
        KHash<String, Object> headersHash = new KHash<>();
        response.headers().map().forEach((key, values) -> {
            if (!values.isEmpty()) {
                headersHash.put(key, values.get(0));
            }
        });
        result.put("headers", headersHash);
        return result;
    }
}
