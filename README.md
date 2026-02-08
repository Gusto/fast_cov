# FastCov

A high-performance native C extension for tracking which Ruby source files are executed during test runs. Built for test impact analysis -- run only the tests affected by your code changes.

FastCov hooks directly into the Ruby VM's event system, avoiding the overhead of Ruby's built-in `Coverage` module. The result is file-level coverage tracking with minimal performance impact.

## Features

- **Line event tracking** -- hooks into `RUBY_EVENT_LINE` to record which files execute, with pointer caching to skip redundant checks
- **Allocation tracing** -- tracks object instantiation via `RUBY_INTERNAL_EVENT_NEWOBJ` and resolves class hierarchies to their source files
- **Constant reference resolution** -- scans bytecode for constant references (`opt_getconstant_path` instructions) and traces them to their defining files, transitively
- **Path filtering** -- only tracks files under a configurable root, with an optional ignored path for excluding vendored dependencies
- **Threading modes** -- single-threaded (per-thread isolation) or multi-threaded (global, tracks all threads)
- **In-memory cache** -- caches constant resolution results with MD5-based invalidation, shared across all Coverage instances within a process

## Requirements

- Ruby >= 3.4.0 (MRI only)
- macOS or Linux (not supported on Windows)

## Installation

Add to your Gemfile:

```ruby
gem "fast_cov"
```

Then:

```sh
bundle install
```

The C extension compiles automatically during gem installation.

## Usage

### Basic usage

```ruby
require "fast_cov"

cov = FastCov::Coverage.new(
  root: File.expand_path("app"),
  threading_mode: :multi
)

cov.start

# ... run a test ...

result = cov.stop
# => { "/path/to/app/models/user.rb" => true, "/path/to/app/services/signup.rb" => true, ... }
```

`stop` returns a hash where each key is the absolute path of a source file that was executed (or referenced via constants) during the coverage window.

### Constructor options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String | *required* | Absolute path to the project root. Only files under this path are tracked. |
| `ignored_path` | String | `nil` | Path prefix to exclude (e.g., your bundle path if gems are installed in-project). |
| `threading_mode` | Symbol | `:multi` | `:multi` tracks all threads. `:single` tracks only the thread that called `start`. |
| `allocation_tracing` | Boolean | `false` | When `true`, tracks object allocations and resolves their class definitions to source files. Requires `:multi` threading mode. |

### Start/stop lifecycle

```ruby
cov.start    # Begin tracking. Returns self.
result = cov.stop   # Stop tracking, return results, reset internal state.
```

Coverage data is cleared on each `stop`, so you can reuse the same instance across tests:

```ruby
cov.start
run_test_a
files_a = cov.stop

cov.start
run_test_b
files_b = cov.stop
```

Calling `start` multiple times is safe (idempotent). Calling `stop` when already stopped returns an empty hash.

### Allocation tracing

Line events only fire when code in a file executes. Classes that have no methods called during a test (e.g., empty model classes, structs) won't be detected by line events alone. Allocation tracing fills this gap:

```ruby
cov = FastCov::Coverage.new(
  root: "/path/to/project",
  threading_mode: :multi,
  allocation_tracing: true
)

cov.start
User.new("alice", "alice@example.com")  # User is a Struct defined in app/models/user.rb
result = cov.stop
# result includes "app/models/user.rb" even though no method body executed
```

When an object is allocated, FastCov records its class, then at `stop` time resolves the class and its entire ancestor chain to their source files via `Object.const_source_location`.

### Constant reference resolution

If a file references a constant defined in another file (e.g., `Config::DEFAULTS`), FastCov detects this by scanning the bytecode of each tracked file for `opt_getconstant_path` instructions. The constant's defining file is then added to the coverage results.

This resolution is transitive -- if file A references a constant in file B, and file B references a constant in file C, all three files appear in the results (up to 10 resolution rounds).

```ruby
# config/defaults.rb
module Config
  DEFAULTS = { timeout: 30 }.freeze
end

# app/services/client.rb
class Client
  def timeout
    Config::DEFAULTS[:timeout]
  end
end
```

When `Client#timeout` executes during coverage, both `app/services/client.rb` and `config/defaults.rb` appear in the results.

### Threading modes

**Multi-threaded (default):** Tracks execution across all threads. Use this for most applications, especially Rails apps with background threads.

```ruby
cov = FastCov::Coverage.new(root: root, threading_mode: :multi)
cov.start

Thread.new { run_background_work }.join  # tracked

result = cov.stop  # includes files from the background thread
```

**Single-threaded:** Each thread gets isolated coverage. Useful for test frameworks that run tests in parallel threads.

```ruby
cov = FastCov::Coverage.new(
  root: root,
  threading_mode: :single,
  allocation_tracing: false  # required: allocation tracing not supported in single mode
)

cov.start
# only tracks the current thread
result = cov.stop
```

## Configuration

```ruby
FastCov.configure do |config|
  # Configuration options will be added here as features grow.
end
```

Reset to defaults:

```ruby
FastCov.configuration.reset
```

## Cache

FastCov caches the results of constant reference resolution (bytecode scanning) in memory so that files only need to be compiled and analyzed once per process. The cache is:

- **Process-level** -- shared across all `FastCov::Coverage` instances
- **Content-addressed** -- entries are invalidated when the file's MD5 digest changes
- **Automatic** -- populated transparently during `stop`, no setup needed

```ruby
FastCov::Cache.data      # the raw cache hash
FastCov::Cache.clear     # empties the in-memory cache
FastCov::Cache.data = {} # replace cache contents (advanced use)
```

## Development

```sh
git clone <repo>
cd fast_cov
bundle install
bundle exec rake compile  # compile the C extension
bundle exec rake spec     # run tests (compiles first)
```

### Benchmarking

FastCov includes a benchmarking suite for catching performance regressions. The workflow is: save a baseline before your change, develop, then compare against the baseline when you're done.

```sh
# 1. Before making changes, save the current performance as baseline
bin/benchmark --baseline

# 2. Make your changes...

# 3. Compare against the baseline
bin/benchmark
```

The output shows the average time per iteration, iterations per second, and the % change vs the baseline for each scenario:

```
FastCov Benchmark Suite
Ruby 4.0.0, arm64-darwin24
1000 iterations x 7 samples (median)
========================================================================

                                           avg (ms)          ips    vs baseline
-------------------------------------------------------------------------------
  Line coverage (small)                       0.216       4631.4         -2.7%
  Line coverage (many files)                  0.316       3163.9         -3.9%
  Allocation tracing                          0.208       4813.4         -7.1%
  Constant resolution (cold cache)            1.051        951.2         -1.8%
  Constant resolution (warm cache)            0.353       2833.0         -3.3%
  Rapid start/stop (100x)                    20.303         49.3         -1.3%
  Multi-threaded coverage                     0.236       4241.8         -3.9%
```

Negative percentages mean faster. Each scenario runs 1000 iterations across 7 samples and reports the median to filter outliers. Override iteration count with `ITERATIONS=5000 bin/benchmark`.

You can re-save the baseline at any time with `bin/benchmark --baseline`.

### Project structure

```
fast_cov/
├── ext/fast_cov/
│   ├── fast_cov.c           # Core C extension (~610 lines)
│   ├── fast_cov_utils.c     # Path filtering, string utils, constant resolution
│   ├── fast_cov.h           # Shared declarations
│   └── extconf.rb           # Build configuration
├── lib/
│   ├── fast_cov.rb           # Entry point
│   └── fast_cov/
│       ├── version.rb        # Version constant
│       ├── configuration.rb  # FastCov.configure
│       ├── cache.rb          # In-memory cache
│       └── benchmark/
│           ├── runner.rb     # Measurement harness + baseline comparison
│           └── scenarios.rb  # Benchmark scenario definitions
├── spec/
│   ├── lib/fast_cov/         # Tests organized by feature
│   │   ├── coverage/
│   │   │   ├── initialization_spec.rb
│   │   │   ├── path_filtering_spec.rb
│   │   │   ├── line_coverage_spec.rb
│   │   │   ├── threading_spec.rb
│   │   │   ├── allocation_tracing_spec.rb
│   │   │   ├── caching_spec.rb
│   │   │   └── robustness_spec.rb
│   │   ├── cache_spec.rb
│   │   └── configuration_spec.rb
│   └── fixtures/             # Calculator and app model fixtures
├── bin/
│   ├── benchmark             # Performance benchmarks with baseline comparison
│   ├── console               # IRB with FastCov loaded
│   └── rspec                 # RSpec binstub
├── Gemfile
├── Rakefile
└── fast_cov.gemspec
```

## License

MIT
