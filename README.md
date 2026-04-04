# FastCov

A high-performance native C extension for tracking which Ruby source files are executed during test runs. Built for test impact analysis.

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

## Quick start

```ruby
require "fast_cov"

coverage = FastCov::CoverageMap.new
coverage.root = File.expand_path("app")
coverage.use(FastCov::FileTracker)

result = coverage.start do
  # ... run a test ...
end

# => #<Set: {"models/user.rb", "config/settings.yml"}>
```

`CoverageMap#stop` returns a `Set` of paths relative to `root`.

## CoverageMap

`FastCov::CoverageMap` is the primary API.

```ruby
coverage = FastCov::CoverageMap.new
coverage.root = Rails.root.to_s
coverage.threads = true
coverage.ignored_paths = Rails.root.join("vendor")

coverage.use(FastCov::FileTracker)
coverage.use(FastCov::FactoryBotTracker)
```

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String | `Dir.pwd` | Absolute project root. Returned paths are relativized to this root. |
| `threads` | Boolean | `true` | `true` tracks all threads. `false` tracks only the thread that called `start`. |
| `ignored_paths` | String, Pathname, or Array | `[]` | Paths under `root` to exclude from tracking. Single values are wrapped into an array, and relative entries are resolved against `root` when coverage starts. |

### Lifecycle

```ruby
coverage.start        # starts tracking and returns the CoverageMap
coverage.stop         # stops tracking and returns a Set
coverage.start { ... } # block form: start, yield, stop
```

Native line coverage is always enabled. Extra trackers registered with `use` are additive.

## Trackers

### FileTracker

Tracks files read from disk during coverage, including JSON, YAML, ERB templates, and any file accessed via `File.read` or read-mode `File.open`.

```ruby
coverage.use(FastCov::FileTracker)
```

### FactoryBotTracker

Tracks FactoryBot factory definition files when factories are used. This is useful because factory files are often loaded before coverage starts.

```ruby
coverage.use(FastCov::FactoryBotTracker)
```

### ConstGetTracker

Tracks constants looked up dynamically via `Module#const_get`.

```ruby
coverage.use(FastCov::ConstGetTracker)
```

This catches patterns such as:

- `Object.const_get("Foo::Bar")`
- Rails `"UserMailer".constantize`
- metaprogramming that resolves constants from strings

It does not catch direct constant references such as `Foo::Bar` in source code.

## Low-level native coverage

`FastCov::Coverage` is still available as a low-level primitive:

```ruby
cov = FastCov::Coverage.new(
  root: "/repo/app",
  ignored_paths: ["/repo/app/vendor"],
  threads: true
)
```

This API is mainly useful for internal use and low-level tests. `CoverageMap` is the intended public orchestration API.

## StaticMap

`FastCov::StaticMap` is a build-time API for static dependency mapping. It parses Ruby files with Prism, resolves literal constant references, and builds a direct dependency graph. Transitive closures are computed lazily on demand.

```ruby
static_map = FastCov::StaticMap.new(root: Rails.root)
static_map.build(files: ["spec/**/*_spec.rb"])

# Direct dependencies for a single file
static_map.dependencies("/app/spec/models/user_spec.rb")
# => ["/app/app/models/user.rb"]

# Transitive closure (computed and cached on first call)
static_map.transitive_dependencies("/app/spec/models/user_spec.rb")
# => ["/app/app/models/account.rb", "/app/app/models/user.rb"]

# Raw direct graph
static_map.direct_graph
# => { "/app/spec/models/user_spec.rb" => ["/app/app/models/user.rb"], ... }
```

The instance caches constant resolution results, so reusing the same instance across multiple `build` calls is efficient.

#### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String or Pathname | required | Absolute project root. Only resolved files under this path are included. |
| `ignored_paths` | String or Array<String> | `[]` | Files or directories to exclude from the graph and recursive traversal. |
| `files` (on `build`) | String or Array<String> | required | Glob or file list to traverse. Relative paths are expanded against `root`. |

#### How it works

- `build` traverses reachable files and stores a direct dependency graph
- `dependencies` returns direct dependencies for a file
- `transitive_dependencies` computes and caches the transitive closure lazily
- Constant resolution results are cached and reused across `build` calls
- Resolves each reference from most-specific lexical candidate to least-specific
- Uses `const_defined?` and `const_source_location` to resolve literal constant references to source files

This is intended for a booted application process. It requires constants to be eager-loaded. It will not see dynamic constant lookups that are not expressed as literal constants in the source.

## Writing custom trackers

There are two approaches: a minimal custom tracker, or inheriting from `AbstractTracker`.

### Option 1: From scratch

Any object that responds to `start` and `stop` can be used.

```ruby
class MyTracker
  def initialize(coverage_map, **options)
    @coverage_map = coverage_map
    @options = options
    @files = Set.new
  end

  def install
  end

  def start
    @files = Set.new
  end

  def stop
    @files
  end
end
```

### Option 2: Inherit from AbstractTracker

`AbstractTracker` provides:

- path filtering through the owning `CoverageMap`
- thread-aware recording
- lifecycle management
- class-level `record` dispatch for patched hooks

```ruby
class MyTracker < FastCov::AbstractTracker
  def install
    SomeClass.singleton_class.prepend(MyPatch)
  end

  module MyPatch
    def some_method(...)
      MyTracker.record { some_file_path }
      super
    end
  end
end
```

#### Hooks

| Method | When called |
|---|---|
| `install` | Once when the tracker is registered with `CoverageMap#use` |
| `on_start` | At the beginning of `start` |
| `on_stop` | At the beginning of `stop` |
| `on_record(path)` | Before a path is added to the result set |

## Local development with path: gems

When developing FastCov alongside a consuming project, use the compile entrypoint to auto-compile the C extension:

```ruby
gem "fast_cov", path: "../fast_cov", require: "fast_cov/dev"
```

## Development

```sh
git clone <repo>
cd fast_cov
bundle install
bundle exec rake compile
bundle exec rspec --fail-fast
```
