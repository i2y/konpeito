# extconf.rb for konpeito_crypto
require 'mkmf'

# Check for OpenSSL
# macOS: Uses LibreSSL or OpenSSL from Homebrew
# Linux: Uses system OpenSSL

# Try to find OpenSSL (Homebrew on macOS)
openssl_dir = nil
['/opt/homebrew/opt/openssl@3', '/opt/homebrew/opt/openssl', '/usr/local/opt/openssl'].each do |dir|
  if File.directory?(dir)
    openssl_dir = dir
    break
  end
end

if openssl_dir
  $INCFLAGS << " -I#{openssl_dir}/include"
  $LDFLAGS << " -L#{openssl_dir}/lib"
end

# Check for required libraries and headers
unless have_library('crypto') && have_header('openssl/sha.h')
  abort <<~MSG
    OpenSSL (libcrypto) is required for KonpeitoCrypto.

    Installation:
      macOS:   brew install openssl
      Ubuntu:  sudo apt-get install libssl-dev
      Fedora:  sudo dnf install openssl-devel

    If OpenSSL is installed but not found, try:
      macOS:   export PKG_CONFIG_PATH="/opt/homebrew/opt/openssl@3/lib/pkgconfig"
  MSG
end

# Optimization flags
$CFLAGS << ' -O3'

create_makefile('konpeito_crypto')
