# KonpeitoJSON - Fast JSON parsing using yyjson
#
# This module provides fast JSON parsing and generation using the yyjson C library.
# It is implemented as a C extension for maximum performance.
#
# Usage:
#   require 'konpeito/stdlib/json'
#
#   # Parse JSON
#   obj = KonpeitoJSON.parse('{"name": "Alice", "age": 30}')
#   # => {"name" => "Alice", "age" => 30}
#
#   # Generate JSON
#   json = KonpeitoJSON.generate({name: "Bob", active: true})
#   # => '{"name":"Bob","active":true}'
#
#   # Pretty print
#   json = KonpeitoJSON.generate_pretty({a: 1, b: 2}, 2)

# Try to load the native extension
begin
  require_relative 'konpeito_json'
rescue LoadError
  # Fallback to Ruby's JSON if native extension is not available
  require 'json'

  module KonpeitoJSON
    ALLOW_COMMENTS = 1 << 3
    ALLOW_TRAILING_COMMAS = 1 << 2
    ALLOW_INF_NAN = 1 << 4

    def self.parse(json_string)
      JSON.parse(json_string)
    end

    def self.generate(obj)
      JSON.generate(obj)
    end

    def self.generate_pretty(obj, indent = 2)
      JSON.pretty_generate(obj)
    end
  end
end
