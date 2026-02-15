# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli"
require "tmpdir"

class CLIRouterTest < Minitest::Test
  def test_help_with_no_args
    cli = Konpeito::CLI.new([])

    output, = capture_io do
      assert_raises(SystemExit) { cli.run }
    end

    assert_includes output, "Konpeito"
    assert_includes output, "Commands:"
    assert_includes output, "build"
    assert_includes output, "check"
  end

  def test_help_option
    cli = Konpeito::CLI.new(["--help"])

    output, = capture_io do
      assert_raises(SystemExit) { cli.run }
    end

    assert_includes output, "Commands:"
  end

  def test_version_option
    cli = Konpeito::CLI.new(["--version"])

    output, = capture_io do
      assert_raises(SystemExit) { cli.run }
    end

    assert_includes output, "konpeito"
    assert_includes output, Konpeito::VERSION
  end

  def test_version_short_option
    cli = Konpeito::CLI.new(["-V"])

    output, = capture_io do
      assert_raises(SystemExit) { cli.run }
    end

    assert_includes output, Konpeito::VERSION
  end

  def test_unknown_command
    cli = Konpeito::CLI.new(["unknown_command"])

    _, err = capture_io do
      assert_raises(SystemExit) { cli.run }
    end

    assert_includes err, "Unknown command"
  end

  def test_commands_map
    commands = Konpeito::CLI::COMMANDS

    assert_includes commands.keys, "build"
    assert_includes commands.keys, "check"
    assert_includes commands.keys, "lsp"
    assert_includes commands.keys, "init"
    assert_includes commands.keys, "fmt"
    assert_includes commands.keys, "test"
    assert_includes commands.keys, "watch"
  end

  def test_legacy_mode_with_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("test.rb", "def hello; end")

        cli = Konpeito::CLI.new(["test.rb"])

        # Should delegate to build command
        # We just check it doesn't fail with "unknown command"
        # The actual compilation may fail, but that's expected
        _, err = capture_io do
          # It will try to compile and may fail, but shouldn't say "unknown command"
          begin
            cli.run
          rescue SystemExit
            # Expected
          end
        end

        refute_includes err, "Unknown command"
      end
    end
  end

  def test_legacy_mode_with_options
    cli = Konpeito::CLI.new(["-v", "nonexistent.rb"])

    # Should delegate to build command (with verbose flag)
    _, err = capture_io do
      begin
        cli.run
      rescue SystemExit
        # Expected - file doesn't exist
      end
    end

    # Should fail because file doesn't exist, not because of unknown command
    assert_includes err, "not found"
    refute_includes err, "Unknown command"
  end

  def test_explicit_build_command
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("test.rb", "def hello; end")

        cli = Konpeito::CLI.new(["build", "test.rb"])

        # Just verify it routes correctly (actual compile may fail)
        capture_io do
          begin
            cli.run
          rescue SystemExit
            # Expected
          end
        end
      end
    end
  end

  def test_help_shows_all_commands
    cli = Konpeito::CLI.new(["--help"])

    output, = capture_io do
      assert_raises(SystemExit) { cli.run }
    end

    # Should show all commands with descriptions
    Konpeito::CLI::COMMANDS.each do |name, klass|
      assert_includes output, name
    end
  end

  def test_help_shows_legacy_mode_info
    cli = Konpeito::CLI.new(["--help"])

    output, = capture_io do
      assert_raises(SystemExit) { cli.run }
    end

    assert_includes output, "Legacy mode"
    assert_includes output, "backwards compatible"
  end
end
