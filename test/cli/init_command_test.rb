# frozen_string_literal: true

require_relative "../test_helper"
require "konpeito/cli/config"
require "konpeito/cli/base_command"
require "konpeito/cli/init_command"
require "tmpdir"
require "fileutils"

class InitCommandTest < Minitest::Test
  def test_command_name
    assert_equal "init", Konpeito::Commands::InitCommand.command_name
  end

  def test_description
    assert_includes Konpeito::Commands::InitCommand.description.downcase, "initialize"
  end

  def test_creates_project_structure_in_new_directory
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new(["my_project"])

        # Capture output
        output = capture_io { cmd.run }.first

        assert_includes output, "my_project"
        assert_includes output, "initialized successfully"

        # Check directory structure
        project_dir = File.join(dir, "my_project")
        assert Dir.exist?(project_dir)
        assert Dir.exist?(File.join(project_dir, "src"))
        assert Dir.exist?(File.join(project_dir, "sig"))
        assert Dir.exist?(File.join(project_dir, "test"))

        # Check files
        assert File.exist?(File.join(project_dir, "konpeito.toml"))
        assert File.exist?(File.join(project_dir, "src", "main.rb"))
        assert File.exist?(File.join(project_dir, "sig", "main.rbs"))
        assert File.exist?(File.join(project_dir, "test", "main_test.rb"))
        assert File.exist?(File.join(project_dir, ".gitignore"))
      end
    end
  end

  def test_creates_project_in_current_directory
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new([])

        capture_io { cmd.run }

        # Check files in current directory
        assert File.exist?(File.join(dir, "konpeito.toml"))
        assert File.exist?(File.join(dir, "src", "main.rb"))
      end
    end
  end

  def test_config_file_content
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new(["test_project"])
        capture_io { cmd.run }

        config_path = File.join(dir, "test_project", "konpeito.toml")
        content = File.read(config_path)

        assert_includes content, 'name = "test_project"'
        assert_includes content, 'format = "cruby_ext"'
        assert_includes content, "[build]"
        assert_includes content, "[test]"
      end
    end
  end

  def test_main_rb_content
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new(["my_app"])
        capture_io { cmd.run }

        main_rb = File.join(dir, "my_app", "src", "main.rb")
        content = File.read(main_rb)

        assert_includes content, "module MyApp"
        assert_includes content, "def self.hello"
      end
    end
  end

  def test_main_rbs_content
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new(["my_app"])
        capture_io { cmd.run }

        main_rbs = File.join(dir, "my_app", "sig", "main.rbs")
        content = File.read(main_rbs)

        assert_includes content, "module MyApp"
        assert_includes content, "def self.hello: (String name) -> String"
      end
    end
  end

  def test_gitignore_content
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new(["my_project"])
        capture_io { cmd.run }

        gitignore = File.join(dir, "my_project", ".gitignore")
        content = File.read(gitignore)

        assert_includes content, "*.bundle"
        assert_includes content, "*.so"
        assert_includes content, ".konpeito_cache/"
        assert_includes content, "*_profile.json"
      end
    end
  end

  def test_no_git_option
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new(["--no-git", "my_project"])
        capture_io { cmd.run }

        gitignore = File.join(dir, "my_project", ".gitignore")
        refute File.exist?(gitignore)
      end
    end
  end

  def test_fails_if_directory_exists_and_not_empty
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir("existing_project")
        File.write(File.join("existing_project", "file.txt"), "content")

        cmd = Konpeito::Commands::InitCommand.new(["existing_project"])

        assert_raises(SystemExit) do
          capture_io { cmd.run }
        end
      end
    end
  end

  def test_allows_empty_existing_directory
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir("empty_project")

        cmd = Konpeito::Commands::InitCommand.new(["empty_project"])
        capture_io { cmd.run }

        assert File.exist?(File.join(dir, "empty_project", "src", "main.rb"))
      end
    end
  end

  def test_camelizes_project_name
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cmd = Konpeito::Commands::InitCommand.new(["my-awesome_project"])
        capture_io { cmd.run }

        main_rb = File.join(dir, "my-awesome_project", "src", "main.rb")
        content = File.read(main_rb)

        # Should convert to camelcase
        assert_includes content, "module MyAwesomeProject"
      end
    end
  end
end
