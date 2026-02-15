# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"
require "konpeito/cli/fmt_command"
require "tmpdir"

class FmtCommandTest < Minitest::Test
  def test_command_name
    assert_equal "fmt", Konpeito::Commands::FmtCommand.command_name
  end

  def test_description
    assert_includes Konpeito::Commands::FmtCommand.description.downcase, "format"
  end

  def test_uses_builtin_formatter
    cmd = Konpeito::Commands::FmtCommand.new([])
    cmd.send(:parse_options!)

    # FmtCommand uses built-in Prism-based formatter (no --tool option)
    assert_nil cmd.options[:tool]
  end

  def test_accepts_check_option
    cmd = Konpeito::Commands::FmtCommand.new(["--check"])
    cmd.send(:parse_options!)

    assert cmd.options[:check]
  end

  def test_accepts_diff_option
    cmd = Konpeito::Commands::FmtCommand.new(["--diff"])
    cmd.send(:parse_options!)

    assert cmd.options[:diff]
    assert cmd.options[:check]  # diff implies check
  end

  def test_accepts_quiet_option
    cmd = Konpeito::Commands::FmtCommand.new(["--quiet"])
    cmd.send(:parse_options!)

    assert cmd.options[:quiet]
  end

  def test_accepts_exclude_option
    cmd = Konpeito::Commands::FmtCommand.new(["--exclude", "test/**/*.rb"])
    cmd.send(:parse_options!)

    assert_includes cmd.options[:exclude], "test/**/*.rb"
  end

  def test_accepts_files_as_arguments
    cmd = Konpeito::Commands::FmtCommand.new(["file1.rb", "file2.rb"])
    cmd.send(:parse_options!)

    assert_equal ["file1.rb", "file2.rb"], cmd.args
  end

  def test_find_ruby_files_excludes_vendor
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Create files
        File.write("main.rb", "")
        FileUtils.mkdir_p("vendor/bundle")
        File.write("vendor/bundle/gem.rb", "")
        FileUtils.mkdir_p(".bundle")
        File.write(".bundle/config.rb", "")

        cmd = Konpeito::Commands::FmtCommand.new([])
        files = cmd.send(:find_ruby_files)

        assert_includes files, "main.rb"
        refute_includes files, "vendor/bundle/gem.rb"
        refute_includes files, ".bundle/config.rb"
      end
    end
  end
end
