# FastCov

A high-performance native C extension for tracking which Ruby source files are executed during test runs. Built for test impact analysis -- run only the tests affected by your code changes.

FastCov hooks directly into the Ruby VM's event system, avoiding the overhead of Ruby's built-in `Coverage` module. The result is file-level coverage tracking with minimal performance impact.

## Requirements

- Ruby >= 3.4.0 (MRI only)
- macOS or Linux

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

## Quick start

```ruby
require "fast_cov"

FastCov.configure do |config|
  config.root = File.expand_path("app")
  config.use FastCov::CoverageTracker
  config.use FastCov::FileTracker
end

result = FastCov.start do
  # ... run a test ...
end

# => { "/path/to/app/models/user.rb" => true, "/path/to/app/config.yml" => true, ... }
```

`stop` returns a hash where each key is the absolute path of a file that was touched during the coverage window.

## Configuration

Call `FastCov.configure` before using `start`/`stop`. The block yields a `Configuration` object:

```ruby
FastCov.configure do |config|
  config.root = Rails.root.to_s
  config.ignored_path = Rails.root.join("vendor").to_s
  config.threads = true

  config.use FastCov::CoverageTracker
  config.use FastCov::FileTracker
end
```

### Config options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String | `Dir.pwd` | Absolute path to the project root. Only files under this path are tracked. |
| `ignored_path` | String | `nil` | Path prefix to exclude (e.g., vendor/bundle). |
| `threads` | Boolean | `true` | `true` tracks all threads. `false` tracks only the thread that called `start`. |

### Registering trackers

Trackers are registered with `config.use`. Each tracker receives the config object and any options you pass:

```ruby
config.use FastCov::CoverageTracker
config.use FastCov::CoverageTracker, constant_references: false
config.use FastCov::FileTracker, ignored_path: "/custom/ignore"
```

## Singleton API

```ruby
FastCov.configure { |c| ... }  # Configure and install trackers
FastCov.start                  # Start all trackers. Returns FastCov.
FastCov.stop                   # Stop all trackers. Returns merged results hash.
FastCov.start { ... }          # Block form: start, yield, stop. Returns results.
FastCov.configured?            # true after configure, false after reset.
FastCov.reset                  # Clear configuration and trackers.
```

### RSpec integration

```ruby
# spec/support/fast_cov.rb
FastCov.configure do |config|
  config.root = Rails.root.to_s
  config.use FastCov::CoverageTracker
  config.use FastCov::FileTracker
end

RSpec.configure do |config|
  config.around(:each) do |example|
    result = FastCov.start { example.run }
    # result is a hash of impacted file paths
  end
end
```

## Trackers

### CoverageTracker

Wraps the native C extension. Handles line event tracking, allocation tracing, and constant reference resolution.

```ruby
config.use FastCov::CoverageTracker
```

#### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String | `config.root` | Override the root path for this tracker. |
| `ignored_path` | String | `config.ignored_path` | Override the ignored path for this tracker. |
| `threads` | Boolean | `config.threads` | Override the threading mode for this tracker. |
| `allocations` | Boolean | `true` | Track object allocations and resolve class hierarchies to source files. |
| `constant_references` | Boolean | `true` | Scan bytecode for constant references and resolve them to defining files. |

#### What it tracks

**Line events** -- hooks `RUBY_EVENT_LINE` to record which files execute. Uses pointer caching (`rb_sourcefile()` returns stable pointers) to skip redundant file checks with a single integer comparison.

**Allocation tracing** (`allocations: true`) -- hooks `RUBY_INTERNAL_EVENT_NEWOBJ` to capture `T_OBJECT` and `T_STRUCT` allocations. At stop time, walks each instantiated class's ancestor chain and resolves every ancestor to its source file. This catches empty models, structs, and Data objects that line events alone would miss.

**Constant reference resolution** (`constant_references: true`) -- at stop time, compiles tracked files to bytecode via `RubyVM::InstructionSequence.compile_file`, scans for `opt_getconstant_path` instructions, and resolves each constant to its defining file via `Object.const_source_location`. Resolution is transitive (up to 10 rounds) and cached with MD5 digests for invalidation.

#### Disabling expensive features

For maximum speed when you only need line-level file tracking:

```ruby
config.use FastCov::CoverageTracker, allocations: false, constant_references: false
```

This disables the NEWOBJ hook (no per-allocation overhead) and skips bytecode scanning at stop time.

### FileTracker

Tracks files read from disk during coverage -- JSON, YAML, ERB templates, or any file accessed via `File.read` or `File.open`.

```ruby
config.use FastCov::FileTracker
```

#### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String | `config.root` | Override the root path for this tracker. |
| `ignored_path` | String | `config.ignored_path` | Override the ignored path for this tracker. |

#### How it works

Prepends a module on `File.singleton_class` to intercept `File.read` and `File.open` (read-mode only). When a file within the root is read during coverage, its path is recorded. Write operations (`"w"`, `"a"`, etc.) are ignored.

This catches `YAML.load_file`, `JSON.parse(File.read(...))`, `CSV.read`, ERB template loading, and any other pattern that goes through `File.read` or `File.open`.

### Writing custom trackers

Any object that responds to `start` and `stop` can be a tracker. `install` is called once during `configure` (optional). `stop` must return a hash of `{ path => true }`.

```ruby
class MyTracker
  def initialize(config, **options)
    # config is the FastCov::Configuration object
    # options are whatever was passed to config.use
  end

  def install
    # optional: one-time setup (called during configure)
  end

  def start
    # called on FastCov.start
  end

  def stop
    # called on FastCov.stop, must return { "/path/to/file" => true, ... }
    {}
  end
end

FastCov.configure do |config|
  config.use MyTracker, some_option: "value"
end
```

Trackers start in registration order and stop in reverse order.

## Cache

FastCov caches constant reference resolution results in memory so files only need bytecode compilation once per process. The cache is process-level, content-addressed (MD5 digests), and populated automatically during `stop`.

```ruby
FastCov::Cache.data      # the raw cache hash
FastCov::Cache.clear     # empty the cache
FastCov::Cache.data = {} # replace cache contents
```

## Local development with path: gems

When developing FastCov alongside a consuming project, use the compile entrypoint to auto-compile the C extension:

```ruby
# Gemfile
gem "fast_cov", path: "../fast_cov", require: "fast_cov/compile"
```

This compiles on first use and detects source changes for recompilation.

## Development

```sh
git clone <repo>
cd fast_cov
bundle install
bundle exec rake compile  # compile the C extension
bundle exec rake spec     # run tests (compiles first)
```

### Benchmarking

```sh
bin/benchmark --baseline   # save current performance as baseline
# ... make changes ...
bin/benchmark              # compare against baseline
```

Override iteration count: `ITERATIONS=5000 bin/benchmark`

## License

MIT
