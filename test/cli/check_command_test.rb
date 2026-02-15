# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"
require "konpeito/cli/check_command"
require "tmpdir"

class CheckCommandTest < Minitest::Test
  def test_command_name
    assert_equal "check", Konpeito::Commands::CheckCommand.command_name
  end

  def test_description
    assert_includes Konpeito::Commands::CheckCommand.description.downcase, "type check"
  end

  def test_fails_without_source_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::CheckCommand.new([])

        assert_raises(SystemExit) do
          capture_io { cmd.run }
        end
      end
    end
  end

  def test_fails_with_nonexistent_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::CheckCommand.new(["nonexistent.rb"])

        err = assert_raises(SystemExit) do
          capture_io { cmd.run }
        end

        assert_equal 1, err.status
      end
    end
  end

  def test_accepts_rbs_option
    cmd = Konpeito::Commands::CheckCommand.new(["--rbs", "types.rbs", "test.rb"])
    cmd.send(:parse_options!)

    assert_equal ["types.rbs"], cmd.options[:rbs_paths]
  end

  def test_accepts_require_path_option
    cmd = Konpeito::Commands::CheckCommand.new(["-I", "lib", "test.rb"])
    cmd.send(:parse_options!)

    assert_equal ["lib"], cmd.options[:require_paths]
  end
end
