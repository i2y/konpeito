# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"
require "minitest/autorun"

# Platform-appropriate shared library extension (.bundle on macOS, .so on Linux)
SHARED_EXT = ".#{RbConfig::CONFIG['DLEXT']}"

# Check if native extension compilation works in this environment.
# On CI without proper CRuby dev headers or LLVM tools, codegen tests
# should be skipped rather than failing with LoadError.
NATIVE_COMPILE_AVAILABLE = begin
  require "tempfile"
  require "fileutils"
  dir = Dir.mktmpdir("konpeito_compile_check_")
  source = File.join(dir, "check.rb")
  output = File.join(dir, "check#{SHARED_EXT}")
  File.write(source, "def __konpeito_compile_check__; 42; end\n")
  compiler = Konpeito::Compiler.new(source_file: source, output_file: output, verbose: false)
  compiler.compile
  require output
  __konpeito_compile_check__ == 42
rescue LoadError, StandardError
  false
ensure
  FileUtils.rm_rf(dir) if dir && Dir.exist?(dir)
end

# Skip codegen tests gracefully when native compilation is unavailable
# (e.g. missing LLVM tools or CRuby dev headers on CI).
module CodegenSkipPlugin
  def before_setup
    super
    if self.class.instance_method(name).source_location&.first&.include?("test/codegen/")
      skip "Native compilation not available" unless NATIVE_COMPILE_AVAILABLE
    end
  end
end
Minitest::Test.prepend(CodegenSkipPlugin)
