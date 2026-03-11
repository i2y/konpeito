# frozen_string_literal: true

# Konpeito stdlib: KonpeitoShell — Shell execution, env vars, file I/O (Ruby stubs)

module KonpeitoShell
  # Shell Execution
  def self.exec(cmd) end
  def self.exec_status() end
  def self.system(cmd) end

  # Environment Variables
  def self.getenv(name) end
  def self.setenv(name, value) end

  # File I/O
  def self.read_file(path) end
  def self.write_file(path, content) end
  def self.append_file(path, content) end
  def self.file_exists(path) end
end
