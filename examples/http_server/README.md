# Fiber-based HTTP Server Example

This example demonstrates how to build a simple HTTP server using Konpeito with:
- Ruby's socket library for network I/O
- Fiber support for cooperative multitasking
- Native compilation for optimized request parsing

## Build

```bash
cd examples/http_server
konpeito build -o http_server.bundle server.rb
```

## Run

```bash
ruby -r ./http_server -e "run_server(8080)"
```

## Test

```bash
curl http://localhost:8080/
curl http://localhost:8080/api/status
curl http://localhost:8080/api/echo
```

## Endpoints

| Path | Response |
|------|----------|
| `/` | HTML welcome page |
| `/api/status` | JSON status response |
| `/api/echo` | JSON echo of request method and path |
| Other | 404 Not Found |

## Architecture

The server uses a simple architecture:
1. Main loop accepts TCP connections
2. Each connection is handled in a Fiber
3. Request parsing (method, path extraction) is optimized by Konpeito
4. Response building uses string concatenation

### Performance Notes

- Socket I/O goes through Ruby's socket library (not optimized)
- String parsing loops are compiled to native code with unboxed iteration
- For production use, consider adding proper error handling and connection pooling

## Benchmarking

The `bench_parse` function can be used to measure parsing performance:

```ruby
require './http_server'
iterations = 1_000_000

start = Time.now
bench_parse(iterations)
elapsed = Time.now - start

puts "#{iterations / elapsed} requests/sec"
```
