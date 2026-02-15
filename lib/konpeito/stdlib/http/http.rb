# KonpeitoHTTP - Fast HTTP client using libcurl
#
# This module provides HTTP client functionality using the libcurl C library.
# It is implemented as a C extension for maximum performance.
#
# Usage:
#   require 'konpeito/stdlib/http'
#
#   # Simple GET request
#   body = KonpeitoHTTP.get("https://example.com")
#
#   # Simple POST request
#   body = KonpeitoHTTP.post("https://api.example.com/data", '{"key": "value"}')
#
#   # GET with full response details
#   response = KonpeitoHTTP.get_response("https://example.com")
#   puts response[:status]   # => 200
#   puts response[:body]     # => "<!doctype html>..."
#   puts response[:headers]  # => {"Content-Type" => "text/html", ...}
#
#   # POST with Content-Type
#   response = KonpeitoHTTP.post_response(
#     "https://api.example.com/json",
#     '{"name": "Alice"}',
#     "application/json"
#   )
#
#   # Generic request with custom method and headers
#   response = KonpeitoHTTP.request(
#     "PUT",
#     "https://api.example.com/resource/123",
#     '{"updated": true}',
#     {"Authorization" => "Bearer token", "Content-Type" => "application/json"}
#   )

# Try to load the native extension
begin
  require_relative 'konpeito_http'
rescue LoadError => e
  # Fallback to net/http if native extension is not available
  require 'net/http'
  require 'uri'

  module KonpeitoHTTP
    class << self
      def get(url)
        uri = URI.parse(url)
        Net::HTTP.get(uri)
      end

      def post(url, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = body
        response = http.request(request)
        response.body
      end

      def get_response(url)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        response = http.get(uri.request_uri)
        headers = {}
        response.each_header { |k, v| headers[k] = v }
        {
          status: response.code.to_i,
          body: response.body,
          headers: headers
        }
      end

      def post_response(url, body, content_type = nil)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = body
        request['Content-Type'] = content_type if content_type
        response = http.request(request)
        headers = {}
        response.each_header { |k, v| headers[k] = v }
        {
          status: response.code.to_i,
          body: response.body,
          headers: headers
        }
      end

      def request(method, url, body = nil, headers = nil)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')

        request_class = case method.upcase
        when 'GET' then Net::HTTP::Get
        when 'POST' then Net::HTTP::Post
        when 'PUT' then Net::HTTP::Put
        when 'DELETE' then Net::HTTP::Delete
        when 'PATCH' then Net::HTTP::Patch
        when 'HEAD' then Net::HTTP::Head
        else
          raise ArgumentError, "Unknown HTTP method: #{method}"
        end

        request = request_class.new(uri.request_uri)
        request.body = body if body
        headers&.each { |k, v| request[k] = v }

        response = http.request(request)
        response_headers = {}
        response.each_header { |k, v| response_headers[k] = v }
        {
          status: response.code.to_i,
          body: response.body,
          headers: response_headers
        }
      end
    end
  end

  warn "KonpeitoHTTP: Native extension not available, using net/http fallback (#{e.message})"
end
