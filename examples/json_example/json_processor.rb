# JSON processing example using stdlib require
require "json"

def parse_user(json_str)
  JSON.parse(json_str)
end

def create_user_json(name, age)
  user = { "name" => name, "age" => age }
  JSON.generate(user)
end

def get_name(json_str)
  data = JSON.parse(json_str)
  data["name"]
end

def get_age(json_str)
  data = JSON.parse(json_str)
  data["age"]
end
