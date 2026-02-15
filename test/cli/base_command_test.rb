# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"

class BaseCommandTest < Minitest::Test
  class TestCommand < Konpeito::Commands::BaseCommand
    attr_accessor :ran

    def self.command_name
      "test"
    end

    def self.description
      "Test command"
    end

    def run
      parse_options!
      @ran = true
    end

    def default_options
      super.merge(custom_option: false)
    end

    def setup_option_parser(opts)
      opts.on("--custom", "Custom option") do
        options[:custom_option] = true
      end
      super
    end
  end

  def test_command_name
    assert_equal "test", TestCommand.command_name
  end

  def test_description
    assert_equal "Test command", TestCommand.description
  end

  def test_default_options
    cmd = TestCommand.new([])
    assert_equal false, cmd.options[:verbose]
    assert_equal false, cmd.options[:custom_option]
  end

  def test_parses_verbose_option
    cmd = TestCommand.new(["--verbose"])
    cmd.run

    assert cmd.options[:verbose]
  end

  def test_parses_no_color_option
    cmd = TestCommand.new(["--no-color"])
    cmd.run

    refute cmd.options[:color]
  end

  def test_parses_custom_option
    cmd = TestCommand.new(["--custom"])
    cmd.run

    assert cmd.options[:custom_option]
  end

  def test_default_output_name_darwin
    skip unless RUBY_PLATFORM.include?("darwin")

    cmd = TestCommand.new([])
    assert_equal "foo.bundle", cmd.send(:default_output_name, "foo.rb")
  end

  def test_default_output_name_with_format
    cmd = TestCommand.new([])
    assert_equal "foo", cmd.send(:default_output_name, "foo.rb", format: :standalone)
  end

  def test_base_command_raises_on_abstract_methods
    assert_raises(NotImplementedError) do
      Konpeito::Commands::BaseCommand.command_name
    end

    assert_raises(NotImplementedError) do
      Konpeito::Commands::BaseCommand.description
    end

    cmd = Konpeito::Commands::BaseCommand.new([])
    assert_raises(NotImplementedError) do
      cmd.run
    end
  end
end
