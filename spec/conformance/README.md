# Konpeito Conformance Tests

A Ruby compatibility test suite for Konpeito, inspired by ruby/spec. Compares output across three backends — Ruby (reference), Native (LLVM), and JVM — to detect behavioral differences.

## Design

Konpeito does not support metaprogramming (`eval`, `define_method`, `instance_eval`, etc.), so mspec's DSL cannot be used directly. Instead, we follow the **Opal model**: a minimal assertion framework with output comparison across backends.

- Test files themselves are valid Ruby code compilable by Konpeito
- Each test is called from within a `run_tests` function
- `PASS:` / `FAIL:` / `SUMMARY:` lines on stdout are compared across backends

## Directory Structure

```
spec/conformance/
├── README.md
├── runner.rb                  # Test orchestrator (runs on CRuby, not compiled)
├── lib/
│   ├── konpeito_spec.rb       # Assertion framework (compilable by Konpeito)
│   └── runner/
│       ├── discovery.rb       # Test file discovery
│       ├── executor.rb        # Per-backend execution
│       ├── comparator.rb      # Output comparison and parsing
│       ├── reporter.rb        # Terminal report formatting
│       └── tag_manager.rb     # Known-failure tag management
├── tags/
│   ├── native/                # Known failures for the Native backend
│   └── jvm/                   # Known failures for the JVM backend
└── language/
    ├── if_spec.rb             # if/unless/elsif
    ├── while_spec.rb          # while/until
    ├── case_spec.rb           # case/when
    ├── break_spec.rb          # break
    ├── next_spec.rb           # next
    ├── logical_operators_spec.rb  # && ||
    ├── method_spec.rb         # def, return, args, keyword args
    ├── variables_spec.rb      # local, $global, compound assignment
    └── block_spec.rb          # yield, block_given?, Array iteration
```

## Usage

### Run all specs on all backends

```bash
ruby spec/conformance/runner.rb
```

### Select a backend

```bash
ruby spec/conformance/runner.rb --native-only
ruby spec/conformance/runner.rb --jvm-only
```

### Filter by pattern (substring match on filename)

```bash
ruby spec/conformance/runner.rb if           # only if_spec.rb
ruby spec/conformance/runner.rb method       # only method_spec.rb
```

### Options

| Option | Description |
|--------|-------------|
| `--native-only` | Run only the Native backend |
| `--jvm-only` | Run only the JVM backend |
| `--verbose`, `-v` | Show compile/run commands and detailed output |
| `--no-color` | Disable colored output |

### Rake Tasks

```bash
bundle exec rake conformance          # all backends
bundle exec rake conformance:native   # Native only
bundle exec rake conformance:jvm      # JVM only
```

## Writing Test Files

```ruby
require_relative "../lib/konpeito_spec"

def test_example
  result = 1 + 2
  assert_equal(3, result, "1 + 2 equals 3")
end

def run_tests
  spec_reset
  test_example
  spec_summary
end

run_tests
```

### Available Assertions

| Method | Description |
|--------|-------------|
| `assert_equal(expected, actual, desc)` | Verifies `expected == actual` |
| `assert_true(value, desc)` | Verifies the value is truthy |
| `assert_false(value, desc)` | Verifies the value is falsy |
| `assert_nil(value, desc)` | Verifies the value is `nil` |
| `spec_reset` | Resets pass/fail counters |
| `spec_summary` | Prints the `SUMMARY:` line |

### Constraints

The assertion framework must be compilable by Konpeito, so only the following constructs are used:

- Global variables, function definitions, `puts`, string concatenation, `if/else`, `==`
- No classes, modules, or metaprogramming

## How It Works

Each spec file is executed in three ways:

| Backend | Execution |
|---------|-----------|
| Ruby | `ruby language/if_spec.rb` |
| Native | `konpeito build -o /tmp/if_spec.bundle language/if_spec.rb` then `ruby -r /tmp/if_spec.bundle -e "run_tests"` |
| JVM | `konpeito build --target jvm -o /tmp/if_spec.jar language/if_spec.rb` then `java -jar /tmp/if_spec.jar` |

Ruby output serves as the reference. Native and JVM outputs are compared line-by-line against it (`PASS:` / `FAIL:` lines).

## Reading the Output

```
break_spec:
  ruby: 6 passed, 0 failed
  native: 6 passed, 0 failed [MATCH]       <- identical to Ruby
  jvm: 6 passed, 0 failed [MATCH]

if_spec:
  ruby: 19 passed, 0 failed
  native: 18 passed, 1 failed [DIFF (1)]   <- 1 difference found

method_spec:
  ruby: 16 passed, 0 failed
  native: ERROR - native compilation failed <- compile error
```

- **MATCH**: Output is identical to Ruby
- **DIFF (N)**: N lines differ from Ruby output
- **ERROR**: Compilation or runtime error

## Known Failures (Tags)

Known failures are recorded in `tags/{native,jvm}/` as text files, one per spec.

### Current Status

#### Native Backend

| Spec | Status | Cause |
|------|--------|-------|
| break_spec | MATCH | |
| case_spec | MATCH | |
| next_spec | MATCH | |
| variables_spec | MATCH | |
| while_spec | MATCH | |
| if_spec | DIFF (1) | Treats `if 0` as falsy (Ruby treats 0 as truthy) |
| block_spec | ERROR | `LocalJumpError` — yield/block_given? block state issue |
| logical_operators_spec | ERROR | `TypeError` — mixed bool/Integer phi node in `&&`/`||` |
| method_spec | ERROR | LLVM IR error — keyword args + early return |

#### JVM Backend

| Spec | Status | Cause |
|------|--------|-------|
| break_spec | MATCH | |
| case_spec | MATCH | |
| next_spec | MATCH | |
| while_spec | MATCH | |
| if_spec | DIFF (1) | Treats `if 0` as falsy (same as Native) |
| block_spec | ERROR | ASM `NegativeArraySizeException` (stack frame type mismatch) |
| logical_operators_spec | ERROR | ASM `NegativeArraySizeException` |
| variables_spec | ERROR | ASM `NegativeArraySizeException` |
| method_spec | ERROR | `VerifyError` — operand stack type mismatch |

## Adding New Specs

1. Create `language/<feature>_spec.rb`
2. Add `require_relative "../lib/konpeito_spec"` at the top
3. Define test functions and call them from `run_tests`
4. Verify with `ruby language/<feature>_spec.rb`
5. Compare backends with `ruby spec/conformance/runner.rb <feature>`
6. If failures are found, create tag files in `tags/{native,jvm}/`
