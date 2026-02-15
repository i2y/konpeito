# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"
require "konpeito/cli/watch_command"
require "tmpdir"

class WatchCommandTest < Minitest::Test
  def test_command_name
    assert_equal "watch", Konpeito::Commands::WatchCommand.command_name
  end

  def test_description
    assert_includes Konpeito::Commands::WatchCommand.description.downcase, "watch"
  end

  def test_default_options
    cmd = Konpeito::Commands::WatchCommand.new([])
    cmd.send(:parse_options!)

    assert_equal ["src", "sig"], cmd.options[:paths]
    assert_equal ["rb", "rbs"], cmd.options[:extensions]
    assert cmd.options[:clear]
  end

  def test_accepts_output_option
    cmd = Konpeito::Commands::WatchCommand.new(["-o", "output.bundle"])
    cmd.send(:parse_options!)

    assert_equal "output.bundle", cmd.options[:output]
  end

  def test_accepts_watch_path_option
    cmd = Konpeito::Commands::WatchCommand.new(["-w", "lib", "-w", "app"])
    cmd.send(:parse_options!)

    assert_includes cmd.options[:paths], "lib"
    assert_includes cmd.options[:paths], "app"
  end

  def test_accepts_no_clear_option
    cmd = Konpeito::Commands::WatchCommand.new(["--no-clear"])
    cmd.send(:parse_options!)

    refute cmd.options[:clear]
  end

  def test_uses_config_watch_paths
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [watch]
        paths = ["lib", "app"]
        extensions = ["rb", "erb"]
      TOML

      config = Konpeito::Commands::Config.new(dir)
      cmd = Konpeito::Commands::WatchCommand.new([], config: config)
      cmd.send(:parse_options!)

      assert_equal ["lib", "app"], cmd.options[:paths]
      assert_equal ["rb", "erb"], cmd.options[:extensions]
    end
  end

  def test_accepts_source_file_argument
    cmd = Konpeito::Commands::WatchCommand.new(["src/main.rb"])
    cmd.send(:parse_options!)

    assert_equal ["src/main.rb"], cmd.args
  end
end
