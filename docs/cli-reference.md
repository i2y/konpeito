# CLI Reference

## Overview

```
konpeito <command> [options] [arguments]
```

### Global options

| Option | Description |
|---|---|
| `-h, --help` | Show help |
| `-V, --version` | Show version and environment info |

### Commands

| Command | Description |
|---|---|
| `build` | Compile Ruby source to native code or JVM bytecode |
| `run` | Build and run in one step |
| `check` | Type check only (no code generation) |
| `init` | Initialize a new project |
| `test` | Run tests |
| `fmt` | Format Ruby source files |
| `watch` | Watch for file changes and recompile |
| `lsp` | Start Language Server Protocol server |
| `deps` | Download JAR dependencies from Maven Central |
| `doctor` | Check development environment |

### Legacy mode

For backward compatibility, Konpeito also accepts the old invocation style:

```bash
konpeito source.rb           # same as: konpeito build source.rb
konpeito -c source.rb        # same as: konpeito check source.rb
konpeito --lsp               # same as: konpeito lsp
```

---

## `konpeito build`

Compile Ruby source to a CRuby extension or JVM JAR.

```
konpeito build [options] <source.rb> [additional_files...]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `-o, --output` | FILE | Output file name | Auto-generated from source |
| `-f, --format` | FORMAT | Output format (`cruby_ext`, `standalone`) | `cruby_ext` |
| `--target` | TARGET | Target platform (`native`, `jvm`) | `native` |
| `-g, --debug` | — | Generate DWARF debug info for lldb/gdb | off |
| `-p, --profile` | — | Enable profiling instrumentation | off |
| `--stats` | — | Show optimization statistics after compilation | off |
| `-v, --verbose` | — | Verbose output (show inferred types, timings) | off |
| `-q, --quiet` | — | Suppress non-error output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |
| `-I, --require-path` | PATH | Add require search path (repeatable) | from config |
| `--rbs` | FILE | RBS type definition file (repeatable) | from config |
| `--inline` | — | Use inline RBS annotations from Ruby source | off |
| `--incremental` | — | Enable incremental compilation | off |
| `--clean-cache` | — | Clear compilation cache before building | off |
| `--run` | — | Run the compiled program after building | off |
| `--emit-ir` | — | Emit intermediate representation for debugging | off |
| `--classpath` | PATH | JVM classpath (colon-separated JARs/directories) | from config |
| `--lib` | — | Build as library JAR (no Main-Class manifest, JVM only) | off |

### Examples

```bash
# CRuby extension (default)
konpeito build src/main.rb
konpeito build -o output.bundle src/main.rb

# JVM JAR
konpeito build --target jvm -o app.jar src/main.rb
konpeito build --target jvm --run src/main.rb

# With inline RBS annotations
konpeito build --target jvm --inline --run src/main.rb

# With separate RBS files
konpeito build --rbs sig/types.rbs src/main.rb

# Debug and profile
konpeito build -g src/main.rb                 # debug info
konpeito build -p src/main.rb                 # profiling

# JVM with classpath
konpeito build --target jvm --classpath "lib/dep.jar:lib/other.jar" src/main.rb

# Library JAR (no main entry point)
konpeito build --target jvm --lib -o mylib.jar src/lib.rb
```

### Notes

- JARs in `lib/` are automatically added to the classpath for JVM builds.
- `--emit-ir` outputs the HIR (High-level Intermediate Representation) for debugging the compiler.
- `--stats` shows counts of inlined calls, monomorphized functions, and loop optimizations.

---

## `konpeito run`

Build and execute a program in one step.

```
konpeito run [options] [source.rb]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `--target` | TARGET | Target platform (`native`, `jvm`) | from config |
| `--classpath` | PATH | JVM classpath (colon-separated) | from config |
| `--rbs` | FILE | RBS type definition file (repeatable) | from config |
| `-I, --require-path` | PATH | Add require search path (repeatable) | from config |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Examples

```bash
konpeito run src/main.rb
konpeito run --target jvm src/main.rb
```

### Notes

- If no source file is given, Konpeito looks for `src/main.rb`, `main.rb`, or `app.rb` in that order.
- For native targets, the compiled extension is loaded into a temporary Ruby process and cleaned up after execution.
- For JVM targets, this delegates to `build --run`.

---

## `konpeito check`

Type check Ruby source without generating code.

```
konpeito check [options] <source.rb>
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `--rbs` | FILE | RBS type definition file (repeatable) | from config |
| `-I, --require-path` | PATH | Add require search path (repeatable) | from config |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Examples

```bash
konpeito check src/main.rb
konpeito check --rbs sig/types.rbs src/main.rb
```

---

## `konpeito init`

Initialize a new Konpeito project.

```
konpeito init [options] [project_name]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `--target` | TARGET | Target platform (`native`, `jvm`) | `native` |
| `--no-git` | — | Do not create `.gitignore` | creates `.gitignore` |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Examples

```bash
konpeito init my_app                    # native project
konpeito init --target jvm my_app       # JVM project
konpeito init                           # initialize current directory
```

### Generated structure

**Native project:**

```
my_app/
  konpeito.toml
  src/main.rb
  sig/main.rbs
  test/main_test.rb
  .gitignore
```

**JVM project:**

```
my_app/
  konpeito.toml
  src/main.rb
  test/main_test.rb
  lib/                  # place JARs here
  .gitignore
```

---

## `konpeito test`

Run project tests.

```
konpeito test [options] [test_files...]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `-p, --pattern` | PATTERN | Test file glob pattern | `test/**/*_test.rb` |
| `-n, --name` | PATTERN | Run tests matching name pattern | all |
| `--compile` | — | Compile source files before running tests | off |
| `--target` | TARGET | Target platform (`native`, `jvm`) | from config |
| `--classpath` | PATH | JVM classpath (colon-separated) | from config |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Examples

```bash
konpeito test                              # run all tests
konpeito test test/math_test.rb            # run specific file
konpeito test -n test_addition             # run matching tests
konpeito test --target jvm                 # run JVM tests
```

### Notes

- **Native tests** use Minitest and run in a Ruby subprocess.
- **JVM tests** compile each test file to a JAR and run it with `java`. The test output is parsed for `PASS:` and `FAIL:` markers.

---

## `konpeito fmt`

Format Ruby source files using the built-in Prism-based formatter.

```
konpeito fmt [options] [files...]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `--check` | — | Check formatting without modifying files | off |
| `--diff` | — | Show what would change (unified diff) | off |
| `-q, --quiet` | — | Suppress non-error output | off |
| `--exclude` | PATTERN | Exclude files matching pattern (repeatable) | none |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Examples

```bash
konpeito fmt                               # format all Ruby files
konpeito fmt src/main.rb                   # format specific file
konpeito fmt --check                       # check only (CI-friendly)
konpeito fmt --diff                        # show diff without modifying
konpeito fmt --exclude "vendor/**"         # exclude patterns
```

### Notes

- Automatically excludes `vendor/`, `.bundle/`, `.konpeito_cache/`, and `tools/` directories.
- `--diff` implies `--check` (no files are modified).
- Exits with code 1 if any files need formatting when using `--check`.

---

## `konpeito watch`

Watch for file changes and recompile automatically.

```
konpeito watch [options] [source.rb]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `-o, --output` | FILE | Output file name | from config |
| `-w, --watch` | PATH | Additional paths to watch (repeatable) | from config |
| `--no-clear` | — | Do not clear screen before each rebuild | clears screen |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Examples

```bash
konpeito watch src/main.rb
konpeito watch -w lib src/main.rb          # watch additional paths
```

### Notes

- Requires the `listen` gem: `gem install listen`
- Default watch paths: `src/`, `sig/`
- Default extensions: `.rb`, `.rbs`
- Press Ctrl+C to stop.

---

## `konpeito lsp`

Start a Language Server Protocol server for IDE integration.

```
konpeito lsp [options]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Supported capabilities

| Feature | Description |
|---|---|
| Diagnostics | Real-time type errors and warnings |
| Hover | Show inferred types on hover |
| Completion | Method and variable completion based on types |
| Go to Definition | Jump to method and variable definitions |
| Find References | Find all usages of a symbol |
| Rename | Rename variables and methods across files |

### IDE setup

The LSP server communicates over stdin/stdout. Configure your editor to run `konpeito lsp` as the language server for Ruby files. The exact setup depends on your editor.

---

## `konpeito deps`

Download JAR dependencies from Maven Central.

```
konpeito deps [options]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `-d, --dir` | DIR | Output directory | `lib` |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Configuration

Add dependencies to `konpeito.toml`:

```toml
[deps]
jars = [
  "com.google.code.gson:gson:2.10.1",
  "org.apache.commons:commons-lang3:3.14.0"
]
```

The format is `group:artifact:version` (Maven coordinates).

### Examples

```bash
konpeito deps                              # download to lib/
konpeito deps -d vendor/jars               # download to custom directory
```

### Notes

- Skips already-downloaded JARs.
- Downloads from Maven Central (`repo1.maven.org`).
- Follows HTTP redirects automatically.

---

## `konpeito doctor`

Check that your development environment is correctly set up.

```
konpeito doctor [options]
```

### Options

| Option | Argument | Description | Default |
|---|---|---|---|
| `--target` | TARGET | Check only `native`, `jvm`, or `ui` dependencies | check all |
| `-v, --verbose` | — | Verbose output | off |
| `--no-color` | — | Disable colored output | auto-detect TTY |

### Checks performed

**Core (always checked):**
- Ruby version (4.0+)
- Prism parser
- RBS

**Native backend (`--target native`):**
- ruby-llvm gem
- clang compiler
- opt (LLVM optimizer)
- libLLVM shared library

**JVM backend (`--target jvm`):**
- Java (21+)
- ASM tool (`tools/konpeito-asm/konpeito-asm.jar`)

**UI (`--target ui`):**
- SDL3
- Skia
- konpeito_ui extension

**Optional:**
- `listen` gem (for `watch` command)
- `konpeito.toml` configuration file

### Examples

```bash
konpeito doctor                            # check everything
konpeito doctor --target jvm               # check JVM dependencies only
konpeito doctor --target native            # check native dependencies only
```

### Output format

Each dependency is shown with a status indicator:

```
  Ruby .............. ✓ 4.0.1 (/path/to/ruby)
  Java .............. ✓ 21.0.10 (/path/to/java)
  listen gem ........ ⚠ not installed (optional)
  libLLVM ........... ✗ not found
```

---

## Configuration File (`konpeito.toml`)

Konpeito looks for `konpeito.toml` in the current directory and its parents. All settings are optional — defaults are used when not specified.

```toml
# Project name (defaults to directory name)
name = "my_app"

[build]
output = "app.jar"                    # output file name
format = "cruby_ext"                  # cruby_ext or standalone
target = "jvm"                        # native or jvm
rbs_paths = ["sig/types.rbs"]         # RBS type definition files
require_paths = ["lib"]               # require search paths
debug = false                         # DWARF debug info
profile = false                       # profiling instrumentation
incremental = false                   # incremental compilation

[jvm]
classpath = "lib/dep.jar"             # JVM classpath
java_home = ""                        # JAVA_HOME override
library = false                       # build as library JAR (no Main-Class)
main_class = ""                       # custom Main-Class name

[deps]
jars = [                              # Maven dependencies
  "com.google.code.gson:gson:2.10.1"
]

[test]
pattern = "test/**/*_test.rb"         # test file glob pattern

[fmt]
indent = 2                            # indentation width

[watch]
paths = ["src", "sig"]                # directories to watch
extensions = ["rb", "rbs"]            # file extensions to watch
```

---

## Environment Variables

| Variable | Description |
|---|---|
| `JAVA_HOME` | Java installation directory (overrides auto-detection) |
| `SKIA_DIR` | Skia library directory (for UI backend) |
| `SDL3_DIR` | SDL3 library directory (for UI backend) |
