# frozen_string_literal: true

require "minitest/autorun"

# Build the extension if needed
json_dir = File.expand_path("../../lib/konpeito/stdlib/json", __dir__)
unless File.exist?(File.join(json_dir, "konpeito_json.bundle")) ||
       File.exist?(File.join(json_dir, "konpeito_json.so"))
  Dir.chdir(json_dir) do
    system("ruby extconf.rb && make")
  end
end

$LOAD_PATH.unshift(json_dir)
require "konpeito_json"

class KonpeitoJSONTest < Minitest::Test
  # === Parse Tests ===

  def test_parse_simple_object
    json = '{"name": "Alice", "age": 30}'
    result = KonpeitoJSON.parse(json)
    assert_equal "Alice", result["name"]
    assert_equal 30, result["age"]
  end

  def test_parse_array
    json = '[1, 2, 3, "four"]'
    result = KonpeitoJSON.parse(json)
    assert_equal [1, 2, 3, "four"], result
  end

  def test_parse_nested
    json = '{"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}'
    result = KonpeitoJSON.parse(json)
    assert_equal 2, result["users"].length
    assert_equal "Alice", result["users"][0]["name"]
    assert_equal 2, result["users"][1]["id"]
  end

  def test_parse_unicode
    json = '{"text": "日本語", "emoji": "😀"}'
    result = KonpeitoJSON.parse(json)
    assert_equal "日本語", result["text"]
    assert_equal "😀", result["emoji"]
  end

  def test_parse_numbers
    json = '{"int": 42, "negative": -100, "float": 3.14, "exp": 1.5e10}'
    result = KonpeitoJSON.parse(json)
    assert_equal 42, result["int"]
    assert_equal(-100, result["negative"])
    assert_in_delta 3.14, result["float"], 0.001
    assert_in_delta 1.5e10, result["exp"], 1e6
  end

  def test_parse_booleans_and_null
    json = '{"active": true, "deleted": false, "data": null}'
    result = KonpeitoJSON.parse(json)
    assert_equal true, result["active"]
    assert_equal false, result["deleted"]
    assert_nil result["data"]
  end

  def test_parse_empty_structures
    assert_equal({}, KonpeitoJSON.parse("{}"))
    assert_equal([], KonpeitoJSON.parse("[]"))
  end

  def test_parse_deeply_nested
    json = '{"a": {"b": {"c": {"d": {"e": 5}}}}}'
    result = KonpeitoJSON.parse(json)
    assert_equal 5, result["a"]["b"]["c"]["d"]["e"]
  end

  def test_parse_invalid_json_raises
    assert_raises(ArgumentError) { KonpeitoJSON.parse("not json") }
    assert_raises(ArgumentError) { KonpeitoJSON.parse("{invalid}") }
    assert_raises(ArgumentError) { KonpeitoJSON.parse("[1, 2,]") } # trailing comma without flag
  end

  def test_parse_type_error
    assert_raises(TypeError) { KonpeitoJSON.parse(123) }
    assert_raises(TypeError) { KonpeitoJSON.parse(nil) }
  end

  # === Generate Tests ===

  def test_generate_object
    obj = {"name" => "Bob", "active" => true}
    json = KonpeitoJSON.generate(obj)
    # Parse it back to verify
    parsed = KonpeitoJSON.parse(json)
    assert_equal "Bob", parsed["name"]
    assert_equal true, parsed["active"]
  end

  def test_generate_array
    arr = [1, 2, 3, "four", nil]
    json = KonpeitoJSON.generate(arr)
    parsed = KonpeitoJSON.parse(json)
    assert_equal [1, 2, 3, "four", nil], parsed
  end

  def test_generate_nested
    obj = {
      "users" => [
        {"id" => 1, "tags" => ["admin", "active"]},
        {"id" => 2, "tags" => []}
      ]
    }
    json = KonpeitoJSON.generate(obj)
    parsed = KonpeitoJSON.parse(json)
    assert_equal 2, parsed["users"].length
    assert_equal ["admin", "active"], parsed["users"][0]["tags"]
  end

  def test_generate_symbol_keys
    obj = {name: "Alice", age: 30}
    json = KonpeitoJSON.generate(obj)
    parsed = KonpeitoJSON.parse(json)
    assert_equal "Alice", parsed["name"]
    assert_equal 30, parsed["age"]
  end

  def test_generate_unicode
    obj = {"text" => "日本語", "emoji" => "🎉"}
    json = KonpeitoJSON.generate(obj)
    parsed = KonpeitoJSON.parse(json)
    assert_equal "日本語", parsed["text"]
    assert_equal "🎉", parsed["emoji"]
  end

  def test_generate_numbers
    obj = {"int" => 42, "float" => 3.14159, "negative" => -100}
    json = KonpeitoJSON.generate(obj)
    parsed = KonpeitoJSON.parse(json)
    assert_equal 42, parsed["int"]
    assert_in_delta 3.14159, parsed["float"], 0.00001
    assert_equal(-100, parsed["negative"])
  end

  def test_generate_pretty
    obj = {"a" => 1, "b" => [2, 3]}
    json = KonpeitoJSON.generate_pretty(obj, 2)
    assert_includes json, "\n"
    assert_includes json, "    " # yyjson uses 4-space indent
    parsed = KonpeitoJSON.parse(json)
    assert_equal obj, parsed
  end

  # === Round-trip Tests ===

  def test_roundtrip_complex
    original = {
      "string" => "hello world",
      "integer" => 42,
      "float" => 3.14159,
      "boolean_true" => true,
      "boolean_false" => false,
      "null_value" => nil,
      "array" => [1, "two", 3.0, true, nil],
      "nested" => {
        "deep" => {
          "value" => 123
        }
      }
    }
    json = KonpeitoJSON.generate(original)
    parsed = KonpeitoJSON.parse(json)
    assert_equal original, parsed
  end

  # === Constants Tests ===

  def test_constants_defined
    assert_kind_of Integer, KonpeitoJSON::ALLOW_COMMENTS
    assert_kind_of Integer, KonpeitoJSON::ALLOW_TRAILING_COMMAS
    assert_kind_of Integer, KonpeitoJSON::ALLOW_INF_NAN
  end
end
