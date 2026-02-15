# frozen_string_literal: true

module Konpeito
  module Commands
    # Doctor command - check development environment
    class DoctorCommand < BaseCommand
      def self.command_name
        "doctor"
      end

      def self.description
        "Check development environment and dependencies"
      end

      def run
        parse_options!

        $stderr.puts "Konpeito v#{Konpeito::VERSION} environment check:"
        $stderr.puts ""

        checks = []
        checks.concat(core_checks)
        checks.concat(native_checks) if check_native?
        checks.concat(jvm_checks) if check_jvm?
        checks.concat(ui_checks) if check_ui?
        checks.concat(optional_checks)

        # Display results
        max_name_len = checks.map { |c| c[:name].length }.max || 10
        checks.each do |check|
          display_check(check, max_name_len)
        end

        $stderr.puts ""

        issues = checks.select { |c| c[:status] == :missing }
        warnings = checks.select { |c| c[:status] == :warning }

        if issues.empty? && warnings.empty?
          emit("All checks", "passed.")
        else
          emit_warn("Warnings", "#{warnings.size} warning(s)") unless warnings.empty?
          emit_error("Issues", "#{issues.size} issue(s) found.") unless issues.empty?
          exit 1 unless issues.empty?
        end
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          target: nil  # nil = check both
        }
      end

      def setup_option_parser(opts)
        opts.on("--target TARGET", %i[native jvm ui], "Check only native, jvm, or ui dependencies") do |target|
          options[:target] = target
        end

        super
      end

      def banner
        "Usage: konpeito doctor [options]"
      end

      private

      def check_native?
        options[:target].nil? || options[:target] == :native
      end

      def check_jvm?
        options[:target].nil? || options[:target] == :jvm
      end

      def check_ui?
        options[:target] == :ui
      end

      def core_checks
        checks = []

        # Ruby version
        checks << {
          name: "Ruby",
          detail: RUBY_VERSION,
          status: ruby_version_ok? ? :ok : :missing,
          hint: "Ruby 4.0+ required. Install with: rbenv install 4.0.1"
        }

        # Prism
        checks << check_require("Prism", "prism", hint: "Prism is bundled with Ruby 4.0+")

        # RBS
        checks << check_require("RBS", "rbs", hint: "Install with: gem install rbs")

        checks
      end

      def native_checks
        checks = []

        # ruby-llvm (optional — only needed for native target)
        checks << check_require("ruby-llvm", "llvm/core",
          required: false,
          hint: "Optional for JVM-only. Required for --target native. Install: gem install ruby-llvm")

        # clang
        clang_path = Platform.find_llvm_tool("clang")
        checks << {
          name: "clang",
          detail: clang_path || "not found",
          status: clang_path ? :ok : :missing,
          hint: "Install: #{Platform.llvm_install_hint}"
        }

        # opt
        opt_path = Platform.find_llvm_tool("opt")
        checks << {
          name: "opt",
          detail: opt_path || "not found",
          status: opt_path ? :ok : :missing,
          hint: "Install: #{Platform.llvm_install_hint}"
        }

        # libLLVM (for debug info)
        llvm_lib = Platform.find_llvm_lib
        checks << {
          name: "libLLVM",
          detail: llvm_lib || "not found",
          status: llvm_lib ? :ok : :warning,
          hint: "Needed for -g (debug info). #{Platform.llvm_install_hint}"
        }

        checks
      end

      def jvm_checks
        checks = []

        # Java
        java_path = find_java_path
        java_version = java_path ? detect_java_version(java_path) : nil
        java_ok = java_version && java_version >= 21
        checks << {
          name: "Java",
          detail: java_path ? "#{java_version || '?'} (#{java_path})" : "not found",
          status: java_ok ? :ok : (java_path ? :warning : :missing),
          hint: "Java 21+ required. Install: #{Platform.java_install_hint}"
        }

        # ASM tool - check both gem install path and local path
        asm_jar_gem = File.expand_path("../../../tools/konpeito-asm/konpeito-asm.jar", __dir__)
        asm_jar_local = File.join("tools", "konpeito-asm", "konpeito-asm.jar")
        asm_jar = if File.exist?(asm_jar_gem)
                    asm_jar_gem
                  elsif File.exist?(asm_jar_local)
                    asm_jar_local
                  end
        asm_exists = !asm_jar.nil?
        checks << {
          name: "ASM tool",
          detail: asm_exists ? asm_jar : "not found (built automatically on first JVM compile)",
          status: asm_exists ? :ok : :warning,
          hint: asm_exists ? nil : "Run: konpeito build --target jvm hello.rb"
        }

        checks
      end

      def optional_checks
        checks = []

        # listen gem (for watch)
        checks << check_require("listen", "listen",
          required: false,
          hint: "Optional, for 'konpeito watch'. Install: gem install listen")

        # Config file
        config_exists = File.exist?("konpeito.toml")
        checks << {
          name: "Config",
          detail: config_exists ? "konpeito.toml" : "not found",
          status: config_exists ? :ok : :warning,
          hint: "Create with: konpeito init"
        }

        checks
      end

      def ui_checks
        checks = []

        # SDL3
        sdl3_found = false
        sdl3_detail = "not found"
        sdl3_hint = "See docs for installation"
        case RUBY_PLATFORM
        when /darwin/
          sdl3_prefix = `brew --prefix sdl3 2>/dev/null`.chomp rescue ""
          if !sdl3_prefix.empty? && File.directory?(sdl3_prefix)
            sdl3_found = true
            sdl3_detail = sdl3_prefix
          end
          sdl3_hint = "Install: brew install sdl3"
        when /linux/
          sdl3_pkg = `pkg-config --modversion sdl3 2>/dev/null`.chomp rescue ""
          if !sdl3_pkg.empty?
            sdl3_found = true
            sdl3_detail = "#{sdl3_pkg} (pkg-config)"
          end
          sdl3_hint = "Install: apt install libsdl3-dev"
        when /mingw|mswin/
          sdl3_dir = ENV["SDL3_DIR"]
          if sdl3_dir && File.directory?(sdl3_dir)
            sdl3_found = true
            sdl3_detail = sdl3_dir
          else
            sdl3_pkg = `pkg-config --modversion sdl3 2>NUL`.chomp rescue ""
            if !sdl3_pkg.empty?
              sdl3_found = true
              sdl3_detail = "#{sdl3_pkg} (pkg-config)"
            end
          end
          sdl3_hint = "Install: pacman -S mingw-w64-ucrt-x86_64-SDL3"
        end
        checks << {
          name: "SDL3",
          detail: sdl3_detail,
          status: sdl3_found ? :ok : :missing,
          hint: sdl3_hint
        }

        # Skia
        skia_dir = ENV["SKIA_DIR"] || File.expand_path("~/skia-prebuilt")
        skia_found = false
        if File.directory?(File.join(skia_dir, "out"))
          # Search for libskia.a (Unix) or skia.lib (Windows)
          Dir.glob(File.join(skia_dir, "out", "*", "{libskia.a,skia.lib}")).each do |path|
            skia_found = true
            break
          end
        end
        skia_found ||= File.exist?(File.join(skia_dir, "lib", "libskia.a"))
        skia_found ||= File.exist?(File.join(skia_dir, "lib", "skia.lib"))
        skia_detail = skia_found ? skia_dir : "not found"
        checks << {
          name: "Skia",
          detail: skia_detail,
          status: skia_found ? :ok : :missing,
          hint: "Set SKIA_DIR env var or place at ~/skia-prebuilt. See docs for build instructions."
        }

        # konpeito_ui extension
        ui_ext_found = false
        ui_ext_detail = "not found"
        begin
          require "konpeito/stdlib/ui/konpeito_ui"
          ui_ext_found = true
          ui_ext_detail = "loaded"
        rescue LoadError
          ui_makefile = File.join(__dir__, "..", "stdlib", "ui", "Makefile")
          if File.exist?(ui_makefile)
            ui_ext_detail = "not compiled (run: cd lib/konpeito/stdlib/ui && make)"
          end
        end
        checks << {
          name: "konpeito_ui",
          detail: ui_ext_detail,
          status: ui_ext_found ? :ok : :missing,
          hint: "Build: cd lib/konpeito/stdlib/ui && ruby extconf.rb && make"
        }

        checks
      end

      def display_check(check, max_name_len)
        name = check[:name].ljust(max_name_len)
        detail = check[:detail] || ""

        case check[:status]
        when :ok
          status_str = options[:color] ? "\e[32mok\e[0m" : "ok"
        when :warning
          status_str = options[:color] ? "\e[33mWARNING\e[0m" : "WARNING"
        when :missing
          status_str = options[:color] ? "\e[31mMISSING\e[0m" : "MISSING"
        end

        # Truncate detail to fit in terminal
        detail_max = 50
        detail = detail[0, detail_max] + "..." if detail.length > detail_max + 3

        $stderr.puts "  %-*s  %-55s %s" % [max_name_len, name, detail, status_str]

        # Show hint for non-ok status
        if check[:status] != :ok && check[:hint]
          $stderr.puts "  %-*s  %s" % [max_name_len, "", check[:hint]]
        end
      end

      def check_require(name, lib, required: true, hint: nil)
        begin
          require lib
          { name: name, detail: "available", status: :ok, hint: hint }
        rescue LoadError
          { name: name, detail: "not found", status: required ? :missing : :warning, hint: hint }
        end
      end

      def ruby_version_ok?
        parts = RUBY_VERSION.split(".").map(&:to_i)
        parts[0] > 4 || (parts[0] == 4 && parts[1] >= 0)
      end

      def find_java_path
        # Check JAVA_HOME first
        java_home = ENV["JAVA_HOME"] || Platform.default_java_home
        java_path = File.join(java_home, "bin", "java")
        return java_path if File.exist?(java_path)

        # Fall back to PATH
        Platform.find_executable("java")
      end

      def detect_java_version(java_path)
        output = `"#{java_path}" -version 2>&1`
        if output =~ /version "(\d+)/
          Regexp.last_match(1).to_i
        end
      rescue
        nil
      end
    end
  end
end
