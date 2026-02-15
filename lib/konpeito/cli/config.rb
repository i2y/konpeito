# frozen_string_literal: true

module Konpeito
  module Commands
    # Configuration file loader for konpeito.toml
    class Config
      CONFIG_FILE_NAME = "konpeito.toml"

      DEFAULT_CONFIG = {
        "name" => nil,
        "version" => "0.1.0",
        "build" => {
          "output" => nil,
          "format" => "cruby_ext",
          "target" => "native",
          "rbs_paths" => [],
          "require_paths" => [],
          "debug" => false,
          "profile" => false,
          "incremental" => false
        },
        "jvm" => {
          "classpath" => "",
          "java_home" => "",
          "library" => false,
          "main_class" => ""
        },
        "deps" => {
          "jars" => []
        },
        "test" => {
          "pattern" => "test/**/*_test.rb"
        },
        "fmt" => {
          "indent" => 2
        },
        "watch" => {
          "paths" => ["src", "sig"],
          "extensions" => ["rb", "rbs"]
        }
      }.freeze

      attr_reader :config, :config_path

      def initialize(base_dir = Dir.pwd)
        @base_dir = base_dir
        @config_path = find_config_file
        @config = load_config
      end

      def [](key)
        @config[key]
      end

      def dig(*keys)
        @config.dig(*keys)
      end

      def project_name
        @config["name"] || File.basename(@base_dir)
      end

      def build_output
        @config.dig("build", "output")
      end

      def build_format
        @config.dig("build", "format")&.to_sym || :cruby_ext
      end

      def rbs_paths
        @config.dig("build", "rbs_paths") || []
      end

      def require_paths
        @config.dig("build", "require_paths") || []
      end

      def debug?
        @config.dig("build", "debug") || false
      end

      def profile?
        @config.dig("build", "profile") || false
      end

      def incremental?
        @config.dig("build", "incremental") || false
      end

      def target
        (@config.dig("build", "target") || "native").to_sym
      end

      def jvm_classpath
        @config.dig("jvm", "classpath") || ""
      end

      def jvm_java_home
        @config.dig("jvm", "java_home") || ""
      end

      def jvm_library?
        @config.dig("jvm", "library") || false
      end

      def jvm_main_class
        @config.dig("jvm", "main_class") || ""
      end

      def deps_jars
        @config.dig("deps", "jars") || []
      end

      def test_pattern
        @config.dig("test", "pattern") || "test/**/*_test.rb"
      end

      def fmt_indent
        @config.dig("fmt", "indent") || 2
      end

      def watch_paths
        @config.dig("watch", "paths") || ["src", "sig"]
      end

      def watch_extensions
        @config.dig("watch", "extensions") || ["rb", "rbs"]
      end

      def exists?
        !@config_path.nil?
      end

      private

      def find_config_file
        dir = @base_dir
        loop do
          config_file = File.join(dir, CONFIG_FILE_NAME)
          return config_file if File.exist?(config_file)

          parent = File.dirname(dir)
          break if parent == dir

          dir = parent
        end
        nil
      end

      def load_config
        return deep_dup(DEFAULT_CONFIG) unless @config_path

        content = File.read(@config_path)
        parsed = parse_toml(content)
        deep_merge(deep_dup(DEFAULT_CONFIG), parsed)
      end

      # Simple TOML parser (supports basic key-value pairs and sections)
      def parse_toml(content)
        result = {}
        current_section = result

        content.each_line do |line|
          line = line.strip

          # Skip empty lines and comments
          next if line.empty? || line.start_with?("#")

          # Section header [section]
          if line.match?(/^\[(.+)\]$/)
            section_name = line[1..-2]
            result[section_name] ||= {}
            current_section = result[section_name]
          # Key = value
          elsif line.include?("=")
            key, value = line.split("=", 2).map(&:strip)
            current_section[key] = parse_value(value)
          end
        end

        result
      end

      def parse_value(value)
        case value
        when /^"(.*)"$/, /^'(.*)'$/
          # String
          Regexp.last_match(1)
        when /^\[(.*)?\]$/
          # Array
          content = Regexp.last_match(1)
          return [] if content.nil? || content.strip.empty?

          content.split(",").map { |v| parse_value(v.strip) }
        when "true"
          true
        when "false"
          false
        when /^\d+$/
          value.to_i
        when /^\d+\.\d+$/
          value.to_f
        else
          value
        end
      end

      def deep_dup(obj)
        case obj
        when Hash
          obj.transform_values { |v| deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        else
          obj.dup rescue obj
        end
      end

      def deep_merge(base, override)
        base.merge(override) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end
    end
  end
end
