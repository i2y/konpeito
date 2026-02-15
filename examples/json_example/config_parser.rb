# Config parser using JSON stdlib
require "json"

def load_config(json_str)
  JSON.parse(json_str)
end

def get_config_value(config, key)
  config[key]
end

def config_to_json(config)
  JSON.generate(config)
end

def merge_configs(base_json, override_json)
  base = JSON.parse(base_json)
  override = JSON.parse(override_json)
  base.merge(override)
end
