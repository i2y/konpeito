# extconf.rb for konpeito_http
require 'mkmf'

# Check for libcurl
unless have_library('curl') && have_header('curl/curl.h')
  abort <<~MSG
    libcurl is required for KonpeitoHTTP.

    Installation:
      macOS:   brew install curl
      Ubuntu:  sudo apt-get install libcurl4-openssl-dev
      Fedora:  sudo dnf install libcurl-devel
  MSG
end

# Optimization flags
$CFLAGS << ' -O3'

create_makefile('konpeito_http')
