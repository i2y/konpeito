# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"
require "konpeito/cli/test_command"
require "tmpdir"

class TestCommandTest < Minitest::Test
  def test_command_name
    assert_equal "test", Konpeito::Commands::TestCommand.command_name
  end

  def test_description
    assert_includes Konpeito::Commands::TestCommand.description.downcase, "test"
  end

  def test_default_pattern
    cmd = Konpeito::Commands::TestCommand.new([])
    cmd.send(:parse_options!)

    assert_equal "test/**/*_test.rb", cmd.options[:pattern]
  end

  def test_accepts_pattern_option
    cmd = Konpeito::Commands::TestCommand.new(["-p", "spec/**/*_spec.rb"])
    cmd.send(:parse_options!)

    assert_equal "spec/**/*_spec.rb", cmd.options[:pattern]
  end

  def test_accepts_name_option
    cmd = Konpeito::Commands::TestCommand.new(["-n", "test_hello"])
    cmd.send(:parse_options!)

    assert_equal "test_hello", cmd.options[:name_pattern]
  end

  def test_accepts_compile_option
    cmd = Konpeito::Commands::TestCommand.new(["--compile"])
    cmd.send(:parse_options!)

    assert cmd.options[:compile_first]
  end

  def test_uses_config_pattern
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "konpeito.toml"), <<~TOML)
        [test]
        pattern = "spec/**/*_spec.rb"
      TOML

      config = Konpeito::Commands::Config.new(dir)
      cmd = Konpeito::Commands::TestCommand.new([], config: config)
      cmd.send(:parse_options!)

      assert_equal "spec/**/*_spec.rb", cmd.options[:pattern]
    end
  end

  def test_accepts_test_files_as_arguments
    cmd = Konpeito::Commands::TestCommand.new(["test/foo_test.rb", "test/bar_test.rb"])
    cmd.send(:parse_options!)

    assert_equal ["test/foo_test.rb", "test/bar_test.rb"], cmd.args
  end

  def test_find_test_files_with_pattern
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("test")
        File.write("test/foo_test.rb", "")
        File.write("test/bar_test.rb", "")
        File.write("test/helper.rb", "")

        cmd = Konpeito::Commands::TestCommand.new([])
        cmd.send(:parse_options!)
        files = cmd.send(:find_test_files)

        assert_includes files, "test/foo_test.rb"
        assert_includes files, "test/bar_test.rb"
        refute_includes files, "test/helper.rb"
      end
    end
  end
end
