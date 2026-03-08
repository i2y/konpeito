# Third-Party Notices

Konpeito includes and/or links against the following third-party software.

## Vendored Code

### yyjson

- **License**: MIT
- **Copyright**: Copyright (c) 2020 YaoYuan <ibireme@gmail.com>
- **Source**: https://github.com/ibireme/yyjson
- **Location**: `vendor/yyjson/`
- **Usage**: JSON parsing and generation in the `KonpeitoJSON` stdlib

## Linked Libraries (mruby backend)

The mruby backend (`konpeito build --target mruby`) statically links `libmruby.a` into the generated executable. The following libraries may also be linked depending on the stdlibs used.

### mruby

- **License**: MIT
- **Copyright**: Copyright (c) mruby developers
- **Source**: https://github.com/mruby/mruby
- **Usage**: Runtime for standalone executables

### raylib (optional)

- **License**: zlib/libpng
- **Copyright**: Copyright (c) 2013-2024 Ramon Santamaria (@raysan5)
- **Source**: https://github.com/raysan5/raylib
- **Usage**: Graphics/input stdlib (`module Raylib`)
- **Linked when**: Code references `module Raylib`

### libcurl (optional)

- **License**: MIT/X-inspired (curl license)
- **Copyright**: Copyright (c) Daniel Stenberg
- **Source**: https://curl.se/
- **Usage**: HTTP client stdlib (`KonpeitoHTTP`)
- **Linked when**: Code uses `KonpeitoHTTP` module

### OpenSSL (optional)

- **License**: Apache-2.0
- **Copyright**: Copyright (c) The OpenSSL Project
- **Source**: https://www.openssl.org/
- **Usage**: Cryptography stdlib (`KonpeitoCrypto`)
- **Linked when**: Code uses `KonpeitoCrypto` module

### zlib (optional)

- **License**: zlib
- **Copyright**: Copyright (c) 1995-2024 Jean-loup Gailly and Mark Adler
- **Source**: https://zlib.net/
- **Usage**: Compression stdlib (`KonpeitoCompression`)
- **Linked when**: Code uses `KonpeitoCompression` module
