# frozen_string_literal: true

# Fiber-based HTTP Server Example for Konpeito
#
# This example demonstrates how to build a simple HTTP server using:
# - Ruby's socket library (via require "socket")
# - Konpeito's Fiber support for cooperative multitasking
# - Optimized request parsing with Konpeito's native compilation
#
# Usage:
#   konpeito build -o http_server.bundle examples/http_server/server.rb
#   ruby -e "require './http_server'; run_server(8080)"
#   curl http://localhost:8080/

require "socket"

# Parse HTTP method from request line
# Optimized by Konpeito with unboxed loop iteration
def parse_method(line)
  i = 0
  len = line.length
  result_end = 0
  while i < len
    c = line[i]
    # Type narrowing: c != nil ensures c is String in then-branch
    if c != nil && c == " "
      result_end = i
      i = len  # Exit loop
    end
    i = i + 1
  end
  line[0, result_end]
end

# Parse path from request line
def parse_path(line)
  space_count = 0
  start = 0
  path_end = 0
  i = 0
  len = line.length

  while i < len
    c = line[i]
    # Type narrowing: c != nil ensures c is String in then-branch
    if c != nil && c == " "
      space_count = space_count + 1
      if space_count == 1
        start = i + 1
      end
      if space_count == 2
        path_end = i
      end
    end
    i = i + 1
  end

  line[start, path_end - start]
end

# Build HTTP 200 OK response
def build_ok_response(content_type, body)
  header = "HTTP/1.1 200 OK\r\n"
  header = header + "Content-Type: " + content_type + "\r\n"
  header = header + "Content-Length: " + body.length.to_s + "\r\n"
  header = header + "Connection: close\r\n"
  header = header + "\r\n"
  header + body
end

# Build HTTP 404 response
def build_404_response(body)
  header = "HTTP/1.1 404 Not Found\r\n"
  header = header + "Content-Type: text/html\r\n"
  header = header + "Content-Length: " + body.length.to_s + "\r\n"
  header = header + "Connection: close\r\n"
  header = header + "\r\n"
  header + body
end

# Handle root path
def handle_root
  body = "<html><body><h1>Hello from Konpeito HTTP Server!</h1></body></html>"
  build_ok_response("text/html", body)
end

# Handle API status
def handle_api_status
  body = '{"status":"ok","server":"konpeito"}'
  build_ok_response("application/json", body)
end

# Handle 404
def handle_not_found
  body = "<html><body><h1>404 Not Found</h1></body></html>"
  build_404_response(body)
end

# Read and discard HTTP headers
def read_headers(socket)
  count = 0
  max_headers = 100
  while count < max_headers
    line = socket.gets
    count = count + 1
    # Use && to combine nil check and value check
    if line != nil && line == "\r\n"
      count = max_headers  # Exit loop
    end
  end
  count
end

# Handle a single connection (simple version - always returns root)
def handle_connection_simple(socket)
  request_line = socket.gets
  method = parse_method(request_line)
  path = parse_path(request_line)
  read_headers(socket)
  response = handle_root
  socket.write(response)
  socket.close
end

# Main server function
def run_server(port)
  server = TCPServer.new("0.0.0.0", port)
  puts "Konpeito HTTP Server listening on port " + port.to_s

  connection_count = 0
  max_connections = 1000

  while connection_count < max_connections
    client = server.accept
    connection_count = connection_count + 1

    # Create Fiber for this connection
    fiber = Fiber.new do |sock|
      handle_connection_simple(sock)
      "done"
    end

    fiber.resume(client)
    puts "Connection #" + connection_count.to_s + " handled"
  end

  server.close
end

# Benchmark function
def bench_parse(iterations)
  request_line = "GET /api/status HTTP/1.1"

  i = 0
  while i < iterations
    method = parse_method(request_line)
    path = parse_path(request_line)
    i = i + 1
  end

  iterations
end
