# Konpeito — Ruby AOT Native Compiler
# Task runner recipes (https://github.com/casey/just)

# Default recipe: show available recipes
default:
    @just --list

# --- Development ---

# Install dependencies
setup:
    bundle install

# Clean build artifacts and caches
clean:
    rm -rf .konpeito_cache/
    find . -name "*.bundle" -not -path "./vendor/*" -delete
    find . -name "*.so" -not -path "./vendor/*" -delete
    find . -name "*.jar" -not -path "./vendor/*" -delete
    find . -name "*.class" -not -path "./vendor/*" -delete
    find . -name "*.o" -not -path "./vendor/*" -delete
    find . -name "*.ll" -not -path "./vendor/*" -delete
    find . -name "*.bc" -not -path "./vendor/*" -delete

# Check environment (LLVM, Java, etc.)
doctor:
    bundle exec ruby -Ilib bin/konpeito doctor

# --- Testing ---

# Run all unit tests
test:
    bundle exec rake test

# Run a specific test file
test-file path:
    bundle exec ruby -Ilib:test {{path}}

# Run conformance tests (all backends)
conformance:
    bundle exec rake conformance

# Run conformance tests (native only)
conformance-native:
    bundle exec rake conformance:native

# Run conformance tests (JVM only)
conformance-jvm:
    bundle exec rake conformance:jvm

# --- Linting & Formatting ---

# Run RuboCop linter
lint:
    bundle exec rubocop

# Run RuboCop with auto-fix
lint-fix:
    bundle exec rubocop -A

# Format source files (via RuboCop)
fmt *args:
    bundle exec ruby -Ilib bin/konpeito fmt {{args}}

# Check formatting (via RuboCop)
fmt-check:
    bundle exec ruby -Ilib bin/konpeito fmt --check

# --- Build & Run ---

# Compile a Ruby file to CRuby extension
build *args:
    bundle exec ruby -Ilib bin/konpeito build {{args}}

# Compile and run a Ruby file
run *args:
    bundle exec ruby -Ilib bin/konpeito run {{args}}

# Type-check a Ruby file
check *args:
    bundle exec ruby -Ilib bin/konpeito check {{args}}

# --- Benchmarks ---

# Run a benchmark (e.g., just bench native_internal)
bench name:
    bundle exec ruby benchmark/{{name}}_bench.rb

# List available benchmarks
bench-list:
    @ls benchmark/*_bench.rb | sed 's|benchmark/||; s|_bench.rb||'

# --- Install ---

# Build and install gem locally
install:
    gem build konpeito.gemspec && gem install konpeito-*.gem && rm -f konpeito-*.gem

# --- Tools ---

# Start LSP server
lsp:
    bundle exec ruby -Ilib bin/konpeito lsp

# Generate shell completion
completion shell:
    bundle exec ruby -Ilib bin/konpeito completion {{shell}}
