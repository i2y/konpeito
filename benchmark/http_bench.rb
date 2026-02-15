# frozen_string_literal: true

require 'benchmark'
require 'net/http'
require 'uri'

# Build HTTP extension
http_dir = File.expand_path('../lib/konpeito/stdlib/http', __dir__)
Dir.chdir(http_dir) do
  system('ruby extconf.rb > /dev/null 2>&1')
  system('make clean > /dev/null 2>&1')
  system('make > /dev/null 2>&1')
end

require_relative '../lib/konpeito/stdlib/http/http'

puts "=" * 60
puts "KonpeitoHTTP (libcurl) vs Net::HTTP Benchmark"
puts "=" * 60
puts

# Use httpbin.org for testing
TEST_URL = "https://httpbin.org/get"
POST_URL = "https://httpbin.org/post"
ITERATIONS = 10

puts "Testing against httpbin.org (#{ITERATIONS} iterations each)"
puts "Note: Network latency dominates, so differences may be small"
puts

# Net::HTTP helpers
def net_http_get(url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10
  response = http.get(uri.request_uri)
  response.body
end

def net_http_post(url, body)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10
  response = http.post(uri.request_uri, body)
  response.body
end

puts "--- GET Request ---"
puts

net_http_times = []
konpeito_times = []

ITERATIONS.times do |i|
  # Net::HTTP
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  net_http_get(TEST_URL)
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  net_http_times << (t2 - t1) * 1000

  # KonpeitoHTTP
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  KonpeitoHTTP.get(TEST_URL)
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  konpeito_times << (t2 - t1) * 1000

  print "."
end
puts

net_avg = net_http_times.sum / net_http_times.size
konpeito_avg = konpeito_times.sum / konpeito_times.size
net_min = net_http_times.min
konpeito_min = konpeito_times.min

puts
puts "GET Results (ms):"
puts "  Net::HTTP:    avg=#{net_avg.round(1)}ms, min=#{net_min.round(1)}ms"
puts "  KonpeitoHTTP: avg=#{konpeito_avg.round(1)}ms, min=#{konpeito_min.round(1)}ms"

if konpeito_avg < net_avg
  speedup = net_avg / konpeito_avg
  puts "  => KonpeitoHTTP is #{speedup.round(2)}x faster (avg)"
else
  slowdown = konpeito_avg / net_avg
  puts "  => KonpeitoHTTP is #{slowdown.round(2)}x slower (avg)"
end
puts

puts "--- POST Request ---"
puts

post_body = '{"name": "benchmark", "value": 12345}'

net_http_times = []
konpeito_times = []

ITERATIONS.times do |i|
  # Net::HTTP
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  net_http_post(POST_URL, post_body)
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  net_http_times << (t2 - t1) * 1000

  # KonpeitoHTTP
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  KonpeitoHTTP.post(POST_URL, post_body)
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  konpeito_times << (t2 - t1) * 1000

  print "."
end
puts

net_avg = net_http_times.sum / net_http_times.size
konpeito_avg = konpeito_times.sum / konpeito_times.size
net_min = net_http_times.min
konpeito_min = konpeito_times.min

puts
puts "POST Results (ms):"
puts "  Net::HTTP:    avg=#{net_avg.round(1)}ms, min=#{net_min.round(1)}ms"
puts "  KonpeitoHTTP: avg=#{konpeito_avg.round(1)}ms, min=#{konpeito_min.round(1)}ms"

if konpeito_avg < net_avg
  speedup = net_avg / konpeito_avg
  puts "  => KonpeitoHTTP is #{speedup.round(2)}x faster (avg)"
else
  slowdown = konpeito_avg / net_avg
  puts "  => KonpeitoHTTP is #{slowdown.round(2)}x slower (avg)"
end
puts

puts "=" * 60
puts "Note: HTTP benchmarks are dominated by network latency."
puts "The real benefit of libcurl is better connection handling,"
puts "keep-alive support, and lower CPU overhead per request."
puts "=" * 60
