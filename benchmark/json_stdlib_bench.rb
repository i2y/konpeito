# frozen_string_literal: true

require "benchmark/ips"
require "json"

# Build the extension if needed
json_dir = File.expand_path("../lib/konpeito/stdlib/json", __dir__)
unless File.exist?(File.join(json_dir, "konpeito_json.bundle")) ||
       File.exist?(File.join(json_dir, "konpeito_json.so"))
  Dir.chdir(json_dir) do
    system("ruby extconf.rb && make")
  end
end

$LOAD_PATH.unshift(json_dir)
require "konpeito_json"

puts "KonpeitoJSON vs Ruby JSON Benchmark"
puts "=" * 50

# Test data
small_json = '{"name": "Alice", "age": 30, "active": true}'
medium_json = {
  "users" => (1..100).map { |i| {"id" => i, "name" => "User#{i}", "email" => "user#{i}@example.com"} },
  "metadata" => {"total" => 100, "page" => 1}
}.then { |obj| JSON.generate(obj) }
large_json = {
  "data" => (1..1000).map { |i|
    {
      "id" => i,
      "name" => "Item #{i}",
      "description" => "This is a description for item #{i}. " * 10,
      "tags" => ["tag1", "tag2", "tag3"],
      "nested" => {"a" => 1, "b" => 2, "c" => {"d" => 3}}
    }
  }
}.then { |obj| JSON.generate(obj) }

puts "\nJSON sizes:"
puts "  Small:  #{small_json.bytesize} bytes"
puts "  Medium: #{medium_json.bytesize} bytes"
puts "  Large:  #{large_json.bytesize} bytes"

# Objects for generate benchmark
small_obj = JSON.parse(small_json)
medium_obj = JSON.parse(medium_json)
large_obj = JSON.parse(large_json)

puts "\n=== PARSE Benchmark ==="

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby JSON.parse (small)") { JSON.parse(small_json) }
  x.report("KonpeitoJSON.parse (small)") { KonpeitoJSON.parse(small_json) }

  x.compare!
end

puts "\n"

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby JSON.parse (medium)") { JSON.parse(medium_json) }
  x.report("KonpeitoJSON.parse (medium)") { KonpeitoJSON.parse(medium_json) }

  x.compare!
end

puts "\n"

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby JSON.parse (large)") { JSON.parse(large_json) }
  x.report("KonpeitoJSON.parse (large)") { KonpeitoJSON.parse(large_json) }

  x.compare!
end

puts "\n=== GENERATE Benchmark ==="

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby JSON.generate (small)") { JSON.generate(small_obj) }
  x.report("KonpeitoJSON.generate (small)") { KonpeitoJSON.generate(small_obj) }

  x.compare!
end

puts "\n"

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby JSON.generate (medium)") { JSON.generate(medium_obj) }
  x.report("KonpeitoJSON.generate (medium)") { KonpeitoJSON.generate(medium_obj) }

  x.compare!
end

puts "\n"

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  x.report("Ruby JSON.generate (large)") { JSON.generate(large_obj) }
  x.report("KonpeitoJSON.generate (large)") { KonpeitoJSON.generate(large_obj) }

  x.compare!
end
