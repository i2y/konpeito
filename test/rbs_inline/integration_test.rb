# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tempfile"

class RBSInlineIntegrationTest < Minitest::Test
  def setup
    @output_dir = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(@output_dir)
  end

  def teardown
    FileUtils.rm_rf(@output_dir)
  end

  def test_compile_with_inline_rbs_simple
    # Create a Ruby source with inline RBS annotations
    source_file = create_temp_file("inline_demo.rb", <<~RUBY)
      # rbs_inline: enabled

      #: (Integer, Integer) -> Integer
      def add_numbers(a, b)
        a + b
      end
    RUBY

    output_file = File.join(@output_dir, "inline_demo.bundle")

    # Compile with --inline option
    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      verbose: false,
      inline_rbs: true
    )

    # Should compile without raising
    compiler.compile

    assert File.exist?(output_file), "Bundle should be created"

    # Verify the bundle exports the function
    nm_output = `nm #{output_file} 2>/dev/null`.strip
    assert_includes nm_output, "Init_inline_demo"
  end

  def test_compile_without_inline_rbs_magic_comment
    # Ruby source without the magic comment
    source_file = create_temp_file("no_magic.rb", <<~RUBY)
      # This file doesn't have the rbs_inline: enabled comment
      def add(a, b)
        a + b
      end
    RUBY

    output_file = File.join(@output_dir, "no_magic.bundle")

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      verbose: false,
      inline_rbs: true  # Even with this option, should work without magic comment
    )

    compiler.compile

    assert File.exist?(output_file), "Bundle should be created"
  end

  private

  def create_temp_file(name, content)
    path = File.join(@output_dir, name)
    File.write(path, content)
    path
  end
end
