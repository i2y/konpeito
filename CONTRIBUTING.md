# Contributing to Konpeito

Thank you for your interest in contributing to Konpeito! This document provides guidelines and instructions for contributing.

## Development Setup

### Prerequisites

- Ruby 4.0.1+
- LLVM 20
- Java 21+ (for JVM backend only)
- Bundler

### Installing LLVM 20

**macOS:**
```bash
brew install llvm@20
ln -sf /opt/homebrew/opt/llvm@20/lib/libLLVM-20.dylib /opt/homebrew/lib/
```

**Ubuntu / Debian:**
```bash
sudo apt install llvm-20 clang-20
```

**Fedora:**
```bash
sudo dnf install llvm20 clang20
```

**Windows (MSYS2 / MinGW):**
```bash
winget install LLVM.LLVM
```

### Setup

```bash
# Clone the repository
git clone https://github.com/i2y/konpeito.git
cd konpeito

# Install Ruby 4.0.1
rbenv install 4.0.1
rbenv local 4.0.1

# Install dependencies
bundle install

# Run tests
bundle exec rake test
```

### Running Specific Tests

```bash
# All tests
bundle exec rake test

# JVM backend only
bundle exec ruby -Ilib:test test/jvm/jvm_backend_test.rb

# Specific test file
bundle exec ruby -Ilib:test test/codegen/rescue_else_test.rb
```

## How to Contribute

### Reporting Bugs

1. Check existing [issues](https://github.com/i2y/konpeito/issues) to avoid duplicates
2. Use the bug report template
3. Include: Ruby version, LLVM version, OS, minimal reproduction code

### Suggesting Features

1. Open an issue using the feature request template
2. Describe the use case and expected behavior
3. If proposing a syntax extension, show example Ruby code and expected compiled output

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`bundle exec rake test`)
6. Submit a pull request using the PR template

### Code Style

- Follow existing code patterns in the codebase
- No trailing whitespace
- Use 2-space indentation (Ruby standard)
- Add tests for all new features and bug fixes

## Architecture Overview

See [docs/architecture.md](docs/architecture.md) for a detailed architecture guide.

Key directories:

| Directory | Purpose |
|-----------|---------|
| `lib/konpeito/parser/` | Prism parser adapter |
| `lib/konpeito/type_checker/` | HM type inference + RBS |
| `lib/konpeito/hir/` | High-level IR |
| `lib/konpeito/codegen/` | LLVM and JVM code generation |
| `lib/konpeito/stdlib/` | Native standard library (C extensions) |
| `tools/konpeito-asm/` | JVM ASM tool (JSON IR to .class) |
| `test/` | Test suite |

## Compiler Design Principles

1. **No ambiguous behavior**: If a type cannot be determined, fall back to dynamic dispatch with a warning — never guess heuristically. Adding RBS promotes the fallback to static dispatch
2. **HM inference is primary, RBS is auxiliary**: Code should compile correctly without RBS files
3. **No heuristic guessing**: Never search all classes to guess which one has a matching method name
4. **Follow Kotlin's design for JVM**: Kotlin is the reference for JVM type inference and code generation

## License

By contributing to Konpeito, you agree that your contributions will be licensed under the [BSD Zero Clause License (0BSD)](LICENSE).
