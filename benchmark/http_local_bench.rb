# frozen_string_literal: true

require 'benchmark/ips'
require 'net/http'
require 'uri'

# Build HTTP extension
http_dir = File.expand_path('../lib/konpeito/stdlib/http', __dir__)
Dir.chdir(http_dir) do
  system('ruby extconf.rb > /dev/null 2>&1')
  system('make > /dev/null 2>&1')
end

require_relative '../lib/konpeito/stdlib/http/http'

PORT = 18082
URL = "http://127.0.0.1:#{PORT}/test"

puts "=" * 60
puts "HTTP Benchmark: KonpeitoHTTP (libcurl) vs Net::HTTP"
puts "Local server at #{URL} (no network latency)"
puts "=" * 60
puts
puts "NOTE: Start server first with:"
puts "  ruby benchmark/http_local_server.rb #{PORT}"
puts

# Verify server is running
begin
  KonpeitoHTTP.get(URL)
  puts "Server OK"
rescue => e
  puts "ERROR: Server not running - #{e.message}"
  exit 1
end
puts

puts "--- GET Request ---"
Benchmark.ips do |x|
  x.report("Net::HTTP.get") { Net::HTTP.get(URI.parse(URL)) }
  x.report("KonpeitoHTTP.get (libcurl)") { KonpeitoHTTP.get(URL) }
  x.compare!
end
puts

puts "--- GET with Response Parsing ---"
Benchmark.ips do |x|
  x.report("Net::HTTP (full)") do
    uri = URI.parse(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    response = http.get(uri.request_uri)
    { status: response.code.to_i, body: response.body }
  end
  x.report("KonpeitoHTTP.get_response") { KonpeitoHTTP.get_response(URL) }
  x.compare!
end
puts

puts "=" * 60
puts "Summary: libcurl provides efficient C-level HTTP handling"
puts "=" * 60
