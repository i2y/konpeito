#!/usr/bin/env ruby
# frozen_string_literal: true

# Build script for konpeito_ui native extension (SDL3 + Skia)
#
# Prerequisites:
#   macOS:
#     brew install sdl3
#     Download Skia prebuilt (Aseprite m124):
#       https://github.com/aseprite/skia/releases
#     Set SKIA_DIR=~/skia-prebuilt (or wherever you extracted it)
#
#   Linux:
#     sudo apt install libsdl3-dev libgl-dev libfontconfig-dev libfreetype-dev
#     Download/build Skia, set SKIA_DIR
#
#   Windows (MSYS2):
#     pacman -S mingw-w64-ucrt-x86_64-SDL3
#     Download/build Skia, set SKIA_DIR
#
# Build:
#     cd lib/konpeito/stdlib/ui && ruby extconf.rb && make

require "mkmf"

# C++17 required for Skia
# Aseprite Skia build uses -frtti (extra_cflags_cc = ["-frtti"])
$CXXFLAGS = ($CXXFLAGS || "") + " -std=c++17"
$CFLAGS = ($CFLAGS || "") + " -std=c11"

# Source file
$srcs = ["konpeito_ui_native.cpp"]

skia_dir = ENV["SKIA_DIR"] || File.expand_path("~/skia-prebuilt")

case RUBY_PLATFORM
when /darwin/
  # macOS: SDL3 via Homebrew, Skia from SKIA_DIR
  sdl_prefix = `brew --prefix sdl3 2>/dev/null`.chomp
  if sdl_prefix.empty?
    sdl_prefix = `pkg-config --variable=prefix sdl3 2>/dev/null`.chomp
  end

  unless sdl_prefix.empty?
    $CFLAGS << " -I#{sdl_prefix}/include"
    $CXXFLAGS << " -I#{sdl_prefix}/include"
    $LDFLAGS << " -L#{sdl_prefix}/lib -lSDL3"
  else
    abort "SDL3 not found. Install with: brew install sdl3"
  end

  # Skia
  if File.directory?(skia_dir)
    # Include paths: top-level for "include/core/..." style includes
    $INCFLAGS = "-I#{skia_dir} #{$INCFLAGS}"
    $CXXFLAGS << " -I#{skia_dir}"

    # Detect lib directory (Release-arm64, Release-x64, or Release)
    skia_lib_dir = nil
    ["Release-arm64", "Release-x64", "Release"].each do |d|
      candidate = File.join(skia_dir, "out", d)
      if File.exist?(File.join(candidate, "libskia.a"))
        skia_lib_dir = candidate
        break
      end
    end

    unless skia_lib_dir
      abort "libskia.a not found in #{skia_dir}/out/. Check your Skia build."
    end

    # Link Skia and its bundled dependencies
    $LDFLAGS << " -L#{skia_lib_dir}"
    # Order matters for static linking: dependents first, then dependencies
    $LDFLAGS << " -lskia"
    # Skia sub-libraries that are built separately in Aseprite's build
    %w[harfbuzz freetype2 png zlib expat skcms webp].each do |lib|
      lib_path = File.join(skia_lib_dir, "lib#{lib}.a")
      if File.exist?(lib_path)
        $LDFLAGS << " -l#{lib}"
      end
    end
  else
    abort "Skia not found at #{skia_dir}. Set SKIA_DIR environment variable."
  end

  # macOS frameworks for Metal + Cocoa + CoreText
  $LDFLAGS << " -framework Metal -framework MetalKit -framework QuartzCore"
  $LDFLAGS << " -framework Cocoa -framework IOKit -framework CoreFoundation"
  $LDFLAGS << " -framework CoreGraphics -framework CoreText -framework CoreServices"
  $LDFLAGS << " -framework Foundation -framework AppKit"

  # Skia GPU backend defines (required for Metal/Ganesh headers)
  $CXXFLAGS << " -DSK_GANESH -DSK_METAL"

  # Objective-C++ support for Metal code
  $CXXFLAGS << " -ObjC++"

  # Suppress Skia deprecation warnings
  $CXXFLAGS << " -Wno-deprecated-declarations"

when /linux/
  # Linux: SDL3 via pkg-config, Skia from SKIA_DIR
  sdl_cflags = `pkg-config --cflags sdl3 2>/dev/null`.chomp
  sdl_libs = `pkg-config --libs sdl3 2>/dev/null`.chomp

  if sdl_cflags.empty? && sdl_libs.empty?
    abort "SDL3 not found. Install with: sudo apt install libsdl3-dev"
  end

  $CFLAGS << " " << sdl_cflags
  $CXXFLAGS << " " << sdl_cflags
  $LDFLAGS << " " << sdl_libs

  # Skia
  if File.directory?(skia_dir)
    $INCFLAGS = "-I#{skia_dir} #{$INCFLAGS}"
    $CXXFLAGS << " -I#{skia_dir}"

    skia_lib_dir = nil
    ["Release-x64", "Release"].each do |d|
      candidate = File.join(skia_dir, "out", d)
      if File.exist?(File.join(candidate, "libskia.a"))
        skia_lib_dir = candidate
        break
      end
    end
    unless skia_lib_dir
      abort "libskia.a not found in #{skia_dir}/out/"
    end

    $LDFLAGS << " -L#{skia_lib_dir} -lskia"
    %w[harfbuzz freetype2 png zlib expat skcms webp].each do |lib|
      lib_path = File.join(skia_lib_dir, "lib#{lib}.a")
      $LDFLAGS << " -l#{lib}" if File.exist?(lib_path)
    end
  else
    abort "Skia not found at #{skia_dir}. Set SKIA_DIR environment variable."
  end

  # Linux: OpenGL GPU backend + fontconfig
  $LDFLAGS << " -lGL -lfontconfig -lfreetype"

  # Skia GPU backend defines (required for OpenGL/Ganesh headers)
  $CXXFLAGS << " -DSK_GANESH -DSK_GL"
  $CXXFLAGS << " -Wno-deprecated-declarations"

when /mingw|mswin/
  # Windows: SDL3 via MSYS2 or SDL3_DIR, Skia from SKIA_DIR
  #
  # MSYS2 setup:
  #   pacman -S mingw-w64-ucrt-x86_64-SDL3
  #
  # Or set SDL3_DIR to the SDL3 development folder.

  sdl3_dir = ENV["SDL3_DIR"]
  if sdl3_dir && File.directory?(sdl3_dir)
    $CFLAGS << " -I#{sdl3_dir}/include"
    $CXXFLAGS << " -I#{sdl3_dir}/include"
    $LDFLAGS << " -L#{sdl3_dir}/lib -lSDL3"
  else
    # Try pkg-config (MSYS2 provides it)
    sdl_cflags = `pkg-config --cflags sdl3 2>NUL`.chomp rescue ""
    sdl_libs = `pkg-config --libs sdl3 2>NUL`.chomp rescue ""
    if !sdl_cflags.empty? || !sdl_libs.empty?
      $CFLAGS << " " << sdl_cflags unless sdl_cflags.empty?
      $CXXFLAGS << " " << sdl_cflags unless sdl_cflags.empty?
      $LDFLAGS << " " << sdl_libs unless sdl_libs.empty?
    else
      abort "SDL3 not found. Install with: pacman -S mingw-w64-ucrt-x86_64-SDL3\n" \
            "Or set SDL3_DIR environment variable."
    end
  end

  # Skia
  if File.directory?(skia_dir)
    $INCFLAGS = "-I#{skia_dir} #{$INCFLAGS}"
    $CXXFLAGS << " -I#{skia_dir}"

    skia_lib_dir = nil
    ["Release-x64", "Release"].each do |d|
      candidate = File.join(skia_dir, "out", d)
      skia_lib = File.join(candidate, "skia.lib")
      skia_lib_a = File.join(candidate, "libskia.a")
      if File.exist?(skia_lib) || File.exist?(skia_lib_a)
        skia_lib_dir = candidate
        break
      end
    end
    unless skia_lib_dir
      abort "skia.lib/libskia.a not found in #{skia_dir}/out/"
    end

    $LDFLAGS << " -L#{skia_lib_dir} -lskia"
    %w[harfbuzz freetype2 png zlib expat skcms webp].each do |lib|
      lib_path_a = File.join(skia_lib_dir, "lib#{lib}.a")
      lib_path_lib = File.join(skia_lib_dir, "#{lib}.lib")
      $LDFLAGS << " -l#{lib}" if File.exist?(lib_path_a) || File.exist?(lib_path_lib)
    end
  else
    abort "Skia not found at #{skia_dir}. Set SKIA_DIR environment variable."
  end

  # Windows: OpenGL + system libraries
  $LDFLAGS << " -lopengl32 -lgdi32 -luser32"

  # Skia GPU backend defines (required for OpenGL/Ganesh headers)
  $CXXFLAGS << " -DSK_GANESH -DSK_GL"
  $CXXFLAGS << " -Wno-deprecated-declarations"

else
  abort "Unsupported platform: #{RUBY_PLATFORM}. macOS, Linux, and Windows (MSYS2) are supported."
end

# Create Makefile
create_makefile("konpeito_ui")
