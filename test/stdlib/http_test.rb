# frozen_string_literal: true

require 'minitest/autorun'
require 'json'

# Build the extension first
http_dir = File.expand_path('../../lib/konpeito/stdlib/http', __dir__)
Dir.chdir(http_dir) do
  system('ruby extconf.rb > /dev/null 2>&1') || raise("extconf.rb failed")
  system('make clean > /dev/null 2>&1')
  system('make > /dev/null 2>&1') || raise("make failed")
end

require_relative '../../lib/konpeito/stdlib/http/http'

class KonpeitoHTTPTest < Minitest::Test
  # Use httpbin.org for testing HTTP functionality
  # These tests require network access

  def test_get_simple
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    body = KonpeitoHTTP.get("https://httpbin.org/get")
    data = JSON.parse(body)
    assert_equal "https://httpbin.org/get", data['url']
  end

  def test_post_simple
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    body = KonpeitoHTTP.post("https://httpbin.org/post", 'test body')
    data = JSON.parse(body)
    # httpbin puts form data in 'form' field when no Content-Type is specified
    # and raw data in 'data' field when Content-Type is text/plain or similar
    # Our simple post doesn't set Content-Type, so check that request was received
    assert_equal 'https://httpbin.org/post', data['url']
  end

  def test_get_response
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    response = KonpeitoHTTP.get_response("https://httpbin.org/get")

    assert_kind_of Hash, response
    assert_equal 200, response[:status]
    assert_kind_of String, response[:body]
    assert_kind_of Hash, response[:headers]

    data = JSON.parse(response[:body])
    assert_equal "https://httpbin.org/get", data['url']
  end

  def test_post_response_with_json
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    response = KonpeitoHTTP.post_response(
      "https://httpbin.org/post",
      '{"key": "value"}',
      'application/json'
    )

    assert_equal 200, response[:status]
    data = JSON.parse(response[:body])
    assert_equal '{"key": "value"}', data['data']
    assert_equal 'application/json', data['headers']['Content-Type']
  end

  def test_request_put
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    response = KonpeitoHTTP.request(
      'PUT',
      "https://httpbin.org/put",
      '{"update": true}',
      {'Content-Type' => 'application/json'}
    )

    assert_equal 200, response[:status]
    data = JSON.parse(response[:body])
    assert_equal '{"update": true}', data['data']
  end

  def test_request_delete
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    response = KonpeitoHTTP.request(
      'DELETE',
      "https://httpbin.org/delete",
      nil,
      nil
    )

    assert_equal 200, response[:status]
  end

  def test_request_with_custom_headers
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    response = KonpeitoHTTP.request(
      'GET',
      "https://httpbin.org/headers",
      nil,
      {'X-Test-Header' => 'test-value', 'Authorization' => 'Bearer token123'}
    )

    assert_equal 200, response[:status]
    data = JSON.parse(response[:body])
    assert_equal 'test-value', data['headers']['X-Test-Header']
    assert_equal 'Bearer token123', data['headers']['Authorization']
  end

  def test_status_codes
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    response = KonpeitoHTTP.get_response("https://httpbin.org/status/404")
    assert_equal 404, response[:status]

    response = KonpeitoHTTP.get_response("https://httpbin.org/status/201")
    assert_equal 201, response[:status]
  end

  def test_error_on_invalid_url
    assert_raises(RuntimeError) do
      KonpeitoHTTP.get('http://invalid.local.domain.that.does.not.exist.test/')
    end
  end

  def test_follow_redirect
    skip "Network tests disabled" if ENV['SKIP_NETWORK_TESTS']
    response = KonpeitoHTTP.get_response("https://httpbin.org/redirect/1")
    assert_equal 200, response[:status] # Should follow redirect
  end

  # Offline tests (no network required)
  def test_module_exists
    assert_kind_of Module, KonpeitoHTTP
  end

  def test_methods_defined
    assert_respond_to KonpeitoHTTP, :get
    assert_respond_to KonpeitoHTTP, :post
    assert_respond_to KonpeitoHTTP, :get_response
    assert_respond_to KonpeitoHTTP, :post_response
    assert_respond_to KonpeitoHTTP, :request
  end
end
