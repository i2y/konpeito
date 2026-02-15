# extconf.rb for konpeito_compression
require 'mkmf'

# Check for zlib
unless have_library('z') && have_header('zlib.h')
  abort <<~MSG
    zlib is required for KonpeitoCompression.

    Installation:
      macOS:   Usually pre-installed. If not: brew install zlib
      Ubuntu:  sudo apt-get install zlib1g-dev
      Fedora:  sudo dnf install zlib-devel
  MSG
end

# Optimization flags
$CFLAGS << ' -O3'

create_makefile('konpeito_compression')
