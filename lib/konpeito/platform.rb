# frozen_string_literal: true

require "rbconfig"

module Konpeito
  module Platform
    def self.windows?
      !!(RbConfig::CONFIG["host_os"] =~ /mingw|mswin|cygwin/)
    end

    def self.macos?
      !!(RbConfig::CONFIG["host_os"] =~ /darwin/)
    end

    def self.linux?
      !!(RbConfig::CONFIG["host_os"] =~ /linux/)
    end

    # CRuby extension file extension
    def self.shared_lib_extension
      if macos? then ".bundle"
      elsif windows? then ".dll"
      else ".so"
      end
    end

    # JVM classpath separator
    def self.classpath_separator
      windows? ? ";" : ":"
    end

    # Platform-independent executable finder (replaces `which`)
    def self.find_executable(name)
      exts = windows? ? (ENV["PATHEXT"] || ".COM;.EXE;.BAT").split(";") : [""]
      ENV["PATH"].split(File::PATH_SEPARATOR).each do |dir|
        exts.each do |ext|
          path = File.join(dir, "#{name}#{ext}")
          return path if File.executable?(path) && !File.directory?(path)
        end
      end
      nil
    end

    # Find LLVM tool (clang, llc, opt) with version suffix fallback
    def self.find_llvm_tool(name)
      ["#{name}-20", "#{name}-19", "#{name}-18", name].each do |tool|
        path = find_executable(tool)
        return path if path
      end
      platform_llvm_paths(name).each { |p| return p if File.exist?(p) }
      nil
    end

    # Find LLVM shared library for FFI (debug_info.rb)
    def self.find_llvm_lib
      candidates = if macos?
        ["/opt/homebrew/opt/llvm@20/lib/libLLVM-20.dylib",
         "/usr/local/opt/llvm@20/lib/libLLVM-20.dylib"]
      elsif windows?
        ["C:/Program Files/LLVM/bin/LLVM-C.dll"]
      else
        ["/usr/lib/llvm-20/lib/libLLVM-20.so", "/usr/lib/llvm-20/lib/libLLVM.so",
         "/usr/lib64/llvm20/lib/libLLVM-20.so", "/usr/lib/libLLVM-20.so"]
      end
      candidates.find { |p| File.exist?(p) }
    end

    def self.default_java_home
      if macos? then "/opt/homebrew/opt/openjdk@21"
      elsif windows? then "C:/Program Files/Java/jdk-21"
      else "/usr/lib/jvm/java-21-openjdk"
      end
    end

    def self.java_install_hint
      if macos? then "brew install openjdk@21"
      elsif windows? then "winget install EclipseAdoptium.Temurin.21.JDK"
      else "sudo apt install openjdk-21-jdk (Ubuntu) / sudo dnf install java-21-openjdk-devel (Fedora)"
      end
    end

    def self.llvm_install_hint
      if macos? then "brew install llvm@20"
      elsif windows? then "winget install LLVM.LLVM"
      else "sudo apt install llvm-20 clang-20 (Ubuntu) / sudo dnf install llvm20 clang20 (Fedora)"
      end
    end

    def self.mruby_install_hint
      if macos? then "brew install mruby"
      elsif windows? then "Build from source: https://github.com/mruby/mruby"
      else "sudo apt install mruby libmruby-dev (Ubuntu) / Build from source"
      end
    end

    # Find mruby-config tool for cflags/ldflags
    def self.find_mruby_config
      ENV["MRUBY_CONFIG"] || find_executable("mruby-config")
    end

    # Get mruby compiler flags
    def self.mruby_cflags
      config = find_mruby_config
      if config
        `#{config} --cflags`.strip
      elsif ENV["MRUBY_DIR"]
        "-I#{ENV['MRUBY_DIR']}/include"
      else
        # Try common install locations
        candidates = if macos?
          ["/opt/homebrew/include", "/usr/local/include"]
        else
          ["/usr/include"]
        end
        inc_dir = candidates.find { |d| File.exist?(File.join(d, "mruby.h")) }
        inc_dir ? "-I#{inc_dir}" : "-I/usr/include"
      end
    end

    # Get mruby linker flags
    def self.mruby_ldflags
      config = find_mruby_config
      if config
        `#{config} --ldflags --libs`.strip
      elsif ENV["MRUBY_DIR"]
        "-L#{ENV['MRUBY_DIR']}/lib -lmruby -lm"
      else
        candidates = if macos?
          ["/opt/homebrew/lib", "/usr/local/lib"]
        else
          ["/usr/lib", "/usr/lib/x86_64-linux-gnu"]
        end
        lib_dir = candidates.find { |d| File.exist?(File.join(d, "libmruby.a")) || File.exist?(File.join(d, "libmruby.so")) }
        lib_dir ? "-L#{lib_dir} -lmruby -lm" : "-lmruby -lm"
      end
    end

    # Check if mruby is available
    def self.mruby_available?
      config = find_mruby_config
      return true if config

      cflags = mruby_cflags
      inc_dir = cflags.sub(/^-I/, "")
      File.exist?(File.join(inc_dir, "mruby.h"))
    end

    # Get mruby version string (e.g., "3.4.0" or "4.0.0-rc2")
    def self.mruby_version
      # Try mruby-config --version first (mruby 4.x supports this)
      config = find_mruby_config
      if config
        version = `#{config} --version 2>/dev/null`.strip
        # Only accept if it looks like a version string (not help text)
        return version if version.match?(/\A\d+\.\d+/)
      end

      # Fallback: parse mruby/version.h
      version_h = find_mruby_version_header
      if version_h
        content = File.read(version_h)
        major = content[/MRUBY_RELEASE_MAJOR\s+(\d+)/, 1]
        minor = content[/MRUBY_RELEASE_MINOR\s+(\d+)/, 1]
        patch = content[/MRUBY_RELEASE_TEENY\s+(\d+)/, 1]
        return "#{major}.#{minor}.#{patch}" if major
      end

      nil
    end

    # Find mruby/version.h from include paths
    def self.find_mruby_version_header
      cflags = mruby_cflags
      cflags.split.select { |f| f.start_with?("-I") }.each do |flag|
        inc_dir = flag.sub(/^-I/, "")
        path = File.join(inc_dir, "mruby", "version.h")
        return path if File.exist?(path)
      end
      nil
    end

    # Get mruby major version number (e.g., 3 or 4)
    def self.mruby_major_version
      version = mruby_version
      return nil unless version
      version.split(".").first.to_i
    end

    # Find zig compiler (used for cross-compilation)
    def self.find_zig
      find_executable("zig")
    end

    # Check if zig is available
    def self.zig_available?
      !!find_zig
    end

    # Convert a cross-compilation target to a zig target triple
    def self.zig_target(cross_target)
      case cross_target
      when /^x86_64.*linux/   then "x86_64-linux-gnu"
      when /^aarch64.*linux|^arm64.*linux/ then "aarch64-linux-gnu"
      when /^x86_64.*windows|^x86_64.*mingw/ then "x86_64-windows-gnu"
      when /^aarch64.*windows|^arm64.*windows/ then "aarch64-windows-gnu"
      when /^x86_64.*darwin|^x86_64.*macos/ then "x86_64-macos"
      when /^aarch64.*darwin|^arm64.*darwin/ then "aarch64-macos"
      else cross_target
      end
    end

    # Convert a cross-compilation target to an LLVM target triple
    def self.llvm_triple(cross_target)
      return cross_target if cross_target.count("-") >= 2

      case cross_target
      when /^x86_64.*linux/  then "x86_64-unknown-linux-gnu"
      when /^aarch64.*linux/ then "aarch64-unknown-linux-gnu"
      when /^arm64.*linux/   then "aarch64-unknown-linux-gnu"
      when /^x86_64.*windows|^x86_64.*mingw/ then "x86_64-w64-windows-gnu"
      when /^x86_64.*darwin/ then "x86_64-apple-macosx"
      when /^arm64.*darwin|^aarch64.*darwin/ then "arm64-apple-macosx"
      else cross_target
      end
    end

    # Get mruby cflags for cross-compilation (using a cross-compiled mruby directory)
    def self.cross_mruby_cflags(cross_mruby_dir)
      inc_dir = File.join(cross_mruby_dir, "include")
      if File.exist?(File.join(inc_dir, "mruby.h"))
        "-I#{inc_dir}"
      else
        raise "mruby.h not found in #{inc_dir}"
      end
    end

    # Get mruby ldflags for cross-compilation
    def self.cross_mruby_ldflags(cross_mruby_dir)
      lib_dir = File.join(cross_mruby_dir, "lib")
      if File.exist?(File.join(lib_dir, "libmruby.a"))
        "-L#{lib_dir} -lmruby -lm"
      else
        raise "libmruby.a not found in #{lib_dir}"
      end
    end

    def self.debugger_tune
      macos? ? "lldb" : "gdb"
    end

    private_class_method def self.platform_llvm_paths(name)
      if macos?
        ["/opt/homebrew/opt/llvm@20/bin/#{name}", "/usr/local/opt/llvm@20/bin/#{name}"]
      elsif windows?
        ["C:/Program Files/LLVM/bin/#{name}.exe"]
      else
        ["/usr/lib/llvm-20/bin/#{name}", "/usr/lib/llvm-19/bin/#{name}", "/usr/bin/#{name}"]
      end
    end
  end
end
