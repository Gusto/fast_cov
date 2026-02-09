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

# => { "models/user.rb" => true, "config.yml" => true, ... }
```

`stop` returns a hash where each key is the path (relative to `root`) of a file that was touched during the coverage window.

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
| `constant_references` | Boolean | `true` | Parse source with Prism for constant references and resolve them to defining files. |

#### What it tracks

**Line events** -- hooks `RUBY_EVENT_LINE` to record which files execute. Uses pointer caching (`rb_sourcefile()` returns stable pointers) to skip redundant file checks with a single integer comparison.

**Allocation tracing** (`allocations: true`) -- hooks `RUBY_INTERNAL_EVENT_NEWOBJ` to capture `T_OBJECT` and `T_STRUCT` allocations. At stop time, walks each instantiated class's ancestor chain and resolves every ancestor to its source file. This catches empty models, structs, and Data objects that line events alone would miss.

**Constant reference resolution** (`constant_references: true`) -- at stop time, parses tracked files with Prism and walks the AST for `ConstantPathNode` and `ConstantReadNode` to extract constant references, then resolves each constant to its defining file via `Object.const_source_location`. Resolution is transitive (up to 10 rounds) and cached with MD5 digests for invalidation.

#### Disabling expensive features

For maximum speed when you only need line-level file tracking:

```ruby
config.use FastCov::CoverageTracker, allocations: false, constant_references: false
```

This disables the NEWOBJ hook (no per-allocation overhead) and skips AST parsing at stop time.

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
| `threads` | Boolean | `config.threads` | Override the threading mode for this tracker. |

#### How it works

Prepends a module on `File.singleton_class` to intercept `File.read` and `File.open` (read-mode only). When a file within the root is read during coverage, its path is recorded. Write operations (`"w"`, `"a"`, etc.) are ignored.

This catches `YAML.load_file`, `JSON.parse(File.read(...))`, `CSV.read`, ERB template loading, and any other pattern that goes through `File.read` or `File.open`.

### FactoryBotTracker

Tracks FactoryBot factory definition files when factories are used during tests. Factory files are typically loaded at boot time before coverage starts, so this tracker intercepts `FactoryBot.factories.find` to record the source file where each factory was defined.

```ruby
config.use FastCov::FactoryBotTracker
```

**Requires:** The `factory_bot` gem must be installed. Raises `LoadError` if FactoryBot is not defined.

#### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String | `config.root` | Override the root path for this tracker. |
| `ignored_path` | String | `config.ignored_path` | Override the ignored path for this tracker. |
| `threads` | Boolean | `config.threads` | Override the threading mode for this tracker. |

#### How it works

Prepends a module on `FactoryBot.factories.singleton_class` to intercept the `find` method (called by `create`, `build`, etc.). When a factory is used, the tracker walks its declaration blocks and extracts `source_location` from each proc to find the factory definition file.

## Writing custom trackers

There are two approaches to writing custom trackers: from scratch (minimal interface) or inheriting from `AbstractTracker` (batteries included).

### Option 1: From scratch

Any object that responds to `start` and `stop` can be a tracker. This is the minimal interface:

```ruby
class MyTracker
  def initialize(config, **options)
    @config = config
    @options = options
    @files = {}
  end

  def install
    # Optional: one-time setup (called during configure)
    # Good place to patch classes, set up hooks, etc.
  end

  def start
    @files = {}
    # Begin tracking
  end

  def stop
    # Stop tracking and return results
    # Paths should be absolute; FastCov will relativize them to config.root
    @files
  end
end
```

### Option 2: Inherit from AbstractTracker

`AbstractTracker` provides common functionality out of the box:

- **Path filtering** — Only records files within `root`, excludes `ignored_path`
- **Thread-aware recording** — Respects the `threads` option
- **Lifecycle management** — Handles `@files` hash and `active` class attribute

```ruby
class MyTracker < FastCov::AbstractTracker
  def install
    # Patch the class/module you want to track
    SomeClass.singleton_class.prepend(MyPatch)
  end

  module MyPatch
    def some_method(...)
      # Record the file when this method is called
      # Uses inherited class method - no need to check .active
      MyTracker.record(some_file_path)
      super
    end
  end
end
```

#### AbstractTracker hooks

Override these methods as needed:

| Method | When called | Purpose |
|---|---|---|
| `install` | Once during `configure` | Set up patches, hooks, instrumentation |
| `on_start` | At the beginning of `start` | Initialize tracker-specific state |
| `on_stop` | At the beginning of `stop` | Clean up tracker-specific state |
| `on_record(path)` | When `record(path)` is called | Return `true` to record, `false` to skip |

The base `record(path)` method handles path filtering and thread checks before calling `on_record`.

#### Full example: tracking ActiveRecord queries

```ruby
class QueryTracker < FastCov::AbstractTracker
  def install
    return unless defined?(ActiveSupport::Notifications)

    ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      # Extract the caller location from the backtrace
      caller_locations(1, 20).each do |loc|
        path = loc.absolute_path
        next unless path

        # Uses inherited class method - safely no-ops if tracker isn't active
        QueryTracker.record(path)
        break
      end
    end
  end
end
```

### Tracker lifecycle

1. `initialize(config, **options)` — Called when registered via `config.use`
2. `install` — Called once after all trackers are registered
3. `start` — Called on `FastCov.start` (in registration order)
4. `stop` — Called on `FastCov.stop` (in reverse order), must return `{ path => true }`

Results from all trackers are merged, with later trackers overwriting earlier ones for duplicate keys.

## Cache

FastCov caches constant reference resolution results in memory so files only need parsing once per process. The cache is process-level, content-addressed (MD5 digests), and populated automatically during `stop`.

```ruby
FastCov::Cache.data      # the raw cache hash
FastCov::Cache.clear     # empty the cache
FastCov::Cache.data = {} # replace cache contents
```

## Local development with path: gems

When developing FastCov alongside a consuming project, use the compile entrypoint to auto-compile the C extension:

```ruby
# Gemfile
gem "fast_cov", path: "../fast_cov", require: "fast_cov/dev"
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
