# frozen_string_literal: true

require_relative "lib/konpeito/version"

Gem::Specification.new do |spec|
  spec.name = "konpeito"
  spec.version = Konpeito::VERSION
  spec.authors = ["Yasushi Itoh"]
  spec.email = ["i2y@users.noreply.github.com"]

  spec.summary = "A gradually typed Ruby compiler with dual LLVM/JVM backends"
  spec.description = "Konpeito is a gradually typed ahead-of-time compiler for Ruby with " \
                     "Hindley-Milner type inference and dual LLVM/JVM backends. Compile Ruby " \
                     "to CRuby C extensions (.so) or standalone JARs with seamless Java interop. " \
                     "Includes Castella UI, a reactive GUI framework powered by Skia, " \
                     "based on a port of Castella for Python (github.com/i2y/castella)."
  spec.homepage = "https://github.com/i2y/konpeito"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .github appveyor Gemfile
                          benchmark/ docs/ examples/ tmp/ CLAUDE.md])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["konpeito"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism"
  spec.add_dependency "rbs"
  spec.add_dependency "language_server-protocol", "~> 3.17"

  # ruby-llvm is optional — only needed for native/CRuby extension compilation (--target native).
  # JVM backend (--target jvm), type checking, LSP, and formatting work without it.
  # Install manually: gem install ruby-llvm
end
