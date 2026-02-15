# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"
require "konpeito/cli/build_command"
require "tmpdir"
require "fileutils"

class BuildCommandTest < Minitest::Test
  def test_command_name
    assert_equal "build", Konpeito::Commands::BuildCommand.command_name
  end

  def test_description
    assert_includes Konpeito::Commands::BuildCommand.description.downcase, "compile"
  end

  def test_fails_without_source_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::BuildCommand.new([])

        assert_raises(SystemExit) do
          capture_io { cmd.run }
        end
      end
    end
  end

  def test_fails_with_nonexistent_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::BuildCommand.new(["nonexistent.rb"])

        err = assert_raises(SystemExit) do
          capture_io { cmd.run }
        end

        assert_equal 1, err.status
      end
    end
  end

  def test_accepts_output_option
    cmd = Konpeito::Commands::BuildCommand.new(["-o", "custom.bundle", "test.rb"])
    cmd.send(:parse_options!)

    assert_equal "custom.bundle", cmd.options[:output]
  end

  def test_accepts_format_option
    cmd = Konpeito::Commands::BuildCommand.new(["-f", "standalone", "test.rb"])
    cmd.send(:parse_options!)

    assert_equal :standalone, cmd.options[:format]
  end

  def test_accepts_debug_option
    cmd = Konpeito::Commands::BuildCommand.new(["-g", "test.rb"])
    cmd.send(:parse_options!)

    assert cmd.options[:debug]
  end

  def test_accepts_profile_option
    cmd = Konpeito::Commands::BuildCommand.new(["-p", "test.rb"])
    cmd.send(:parse_options!)

    assert cmd.options[:profile]
  end

  def test_accepts_incremental_option
    cmd = Konpeito::Commands::BuildCommand.new(["--incremental", "test.rb"])
    cmd.send(:parse_options!)

    assert cmd.options[:incremental]
  end

  def test_accepts_clean_cache_option
    cmd = Konpeito::Commands::BuildCommand.new(["--clean-cache", "test.rb"])
    cmd.send(:parse_options!)

    assert cmd.options[:clean_cache]
  end

  def test_accepts_rbs_option
    cmd = Konpeito::Commands::BuildCommand.new(["--rbs", "types.rbs", "--rbs", "sig.rbs", "test.rb"])
    cmd.send(:parse_options!)

    assert_equal ["types.rbs", "sig.rbs"], cmd.options[:rbs_paths]
  end

  def test_accepts_require_path_option
    cmd = Konpeito::Commands::BuildCommand.new(["-I", "lib", "-I", "src", "test.rb"])
    cmd.send(:parse_options!)

    assert_equal ["lib", "src"], cmd.options[:require_paths]
  end

  def test_uses_config_defaults
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [build]
        output = "from_config.bundle"
        debug = true
        rbs_paths = ["sig"]
      TOML

      config = Konpeito::Commands::Config.new(dir)
      cmd = Konpeito::Commands::BuildCommand.new(["test.rb"], config: config)
      cmd.send(:parse_options!)

      assert_equal "from_config.bundle", cmd.options[:output]
      assert cmd.options[:debug]
      assert_equal ["sig"], cmd.options[:rbs_paths]
    end
  end

  def test_cli_options_override_config
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [build]
        output = "from_config.bundle"
        debug = false
      TOML

      config = Konpeito::Commands::Config.new(dir)
      cmd = Konpeito::Commands::BuildCommand.new(["-o", "cli.bundle", "-g", "test.rb"], config: config)
      cmd.send(:parse_options!)

      assert_equal "cli.bundle", cmd.options[:output]
      assert cmd.options[:debug]
    end
  end
end
