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
