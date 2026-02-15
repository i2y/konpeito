# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "tmpdir"
require "fileutils"

class ConfigTest < Minitest::Test
  def test_default_config_when_no_file
    Dir.mktmpdir do |dir|
      config = Konpeito::Commands::Config.new(dir)

      assert_nil config.config_path
      refute config.exists?
      assert_equal "cruby_ext", config.dig("build", "format")
      assert_equal [], config.rbs_paths
      assert_equal "test/**/*_test.rb", config.test_pattern
    end
  end

  def test_loads_config_file
    Dir.mktmpdir do |dir|
      # Create config file
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        name = "my_project"
        version = "1.0.0"

        [build]
        output = "my_project.bundle"
        format = "cruby_ext"
        debug = true

        [test]
        pattern = "spec/**/*_spec.rb"
      TOML

      config = Konpeito::Commands::Config.new(dir)

      assert config.exists?
      assert_equal "my_project", config.project_name
      assert_equal "my_project.bundle", config.build_output
      assert_equal :cruby_ext, config.build_format
      assert config.debug?
      assert_equal "spec/**/*_spec.rb", config.test_pattern
    end
  end

  def test_parses_arrays
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [build]
        rbs_paths = ["sig", "types"]
        require_paths = ["src", "lib"]

        [watch]
        extensions = ["rb", "rbs", "erb"]
      TOML

      config = Konpeito::Commands::Config.new(dir)

      assert_equal ["sig", "types"], config.rbs_paths
      assert_equal ["src", "lib"], config.require_paths
      assert_equal ["rb", "rbs", "erb"], config.watch_extensions
    end
  end

  def test_parses_booleans
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [build]
        debug = true
        profile = false
        incremental = true
      TOML

      config = Konpeito::Commands::Config.new(dir)

      assert config.debug?
      refute config.profile?
      assert config.incremental?
    end
  end

  def test_finds_config_in_parent_directory
    Dir.mktmpdir do |dir|
      # Create config in parent
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        name = "parent_project"
      TOML

      # Create subdirectory
      subdir = File.join(dir, "src", "lib")
      FileUtils.mkdir_p(subdir)

      config = Konpeito::Commands::Config.new(subdir)

      assert config.exists?
      assert_equal "parent_project", config.project_name
    end
  end

  def test_project_name_defaults_to_directory_name
    Dir.mktmpdir("my_awesome_project") do |dir|
      config = Konpeito::Commands::Config.new(dir)

      assert_equal File.basename(dir), config.project_name
    end
  end

  def test_dig_method
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [build]
        output = "test.bundle"
      TOML

      config = Konpeito::Commands::Config.new(dir)

      assert_equal "test.bundle", config.dig("build", "output")
      assert_nil config.dig("nonexistent", "key")
    end
  end

  def test_bracket_accessor
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        name = "test"

        [build]
        debug = true
      TOML

      config = Konpeito::Commands::Config.new(dir)

      assert_equal "test", config["name"]
      assert_equal true, config["build"]["debug"]
    end
  end

  def test_skips_comments
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        # This is a comment
        name = "test"
        # Another comment
        version = "1.0.0"

        [build]
        # Comment in section
        debug = true
      TOML

      config = Konpeito::Commands::Config.new(dir)

      assert_equal "test", config["name"]
      assert_equal "1.0.0", config["version"]
      assert config.debug?
    end
  end

  def test_empty_array
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [build]
        rbs_paths = []
      TOML

      config = Konpeito::Commands::Config.new(dir)

      assert_equal [], config.rbs_paths
    end
  end
end
