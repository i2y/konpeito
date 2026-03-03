# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"
require "konpeito/cli/fmt_command"

class FmtCommandTest < Minitest::Test
  def test_command_name
    assert_equal "fmt", Konpeito::Commands::FmtCommand.command_name
  end

  def test_description_mentions_rubocop
    desc = Konpeito::Commands::FmtCommand.description
    assert_includes desc.downcase, "format"
    assert_includes desc, "RuboCop"
  end

  def test_build_rubocop_args_default
    cmd = Konpeito::Commands::FmtCommand.new([])
    cmd.send(:parse_options!)

    args = cmd.build_rubocop_args
    assert_includes args, "-A"
  end

  def test_build_rubocop_args_check_mode
    cmd = Konpeito::Commands::FmtCommand.new(["--check"])
    cmd.send(:parse_options!)

    args = cmd.build_rubocop_args
    refute_includes args, "-A"
  end

  def test_accepts_check_option
    cmd = Konpeito::Commands::FmtCommand.new(["--check"])
    cmd.send(:parse_options!)

    assert cmd.options[:check]
  end

  def test_accepts_diff_option
    cmd = Konpeito::Commands::FmtCommand.new(["--diff"])
    cmd.send(:parse_options!)

    # --diff is an alias for --check
    assert cmd.options[:check]
  end

  def test_accepts_quiet_option
    cmd = Konpeito::Commands::FmtCommand.new(["--quiet"])
    cmd.send(:parse_options!)

    assert cmd.options[:quiet]
    args = cmd.build_rubocop_args
    assert_includes args, "--format"
    assert_includes args, "quiet"
  end

  def test_accepts_exclude_option
    cmd = Konpeito::Commands::FmtCommand.new(["--exclude", "test/**/*.rb"])
    cmd.send(:parse_options!)

    assert_includes cmd.options[:exclude], "test/**/*.rb"
    args = cmd.build_rubocop_args
    assert_includes args, "--exclude"
    assert_includes args, "test/**/*.rb"
  end

  def test_accepts_files_as_arguments
    cmd = Konpeito::Commands::FmtCommand.new(["file1.rb", "file2.rb"])
    cmd.send(:parse_options!)

    assert_equal ["file1.rb", "file2.rb"], cmd.args
    args = cmd.build_rubocop_args
    assert_includes args, "file1.rb"
    assert_includes args, "file2.rb"
  end

  def test_no_color_option
    cmd = Konpeito::Commands::FmtCommand.new(["--no-color"])
    cmd.send(:parse_options!)

    refute cmd.options[:color]
    args = cmd.build_rubocop_args
    assert_includes args, "--no-color"
  end
end
