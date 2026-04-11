# FastCov

A high-performance native C extension for tracking which Ruby source files are executed during test runs. Built for test impact analysis.

FastCov hooks directly into the Ruby VM's event system, avoiding the overhead of Ruby's built-in `Coverage` module. The result is file-level coverage tracking with minimal performance impact.

## Requirements

- Ruby >= 3.2.0 (MRI only)
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

result = coverage.build do
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
coverage.use(FastCov::ConstGetTracker)
coverage.use(FastCov::FixtureKitTracker)
```

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String | `Dir.pwd` | Absolute project root. Returned paths are relativized to this root. |
| `threads` | Boolean | `true` | `true` tracks all threads. `false` tracks only the thread that called `start`. |
| `ignored_paths` | String, Pathname, or Array | `[]` | Paths under `root` to exclude from tracking. Single values are wrapped into an array, and relative entries are resolved against `root` when coverage starts. |

### Lifecycle

```ruby
coverage.start         # starts tracking, returns self
result = coverage.stop # stops tracking, returns a Set

# Block form: start, yield, stop
result = coverage.build do
  # ...
end
```

Native line coverage is always enabled. Extra trackers registered with `use` are additive.

## Trackers

### FileTracker

Tracks files read from disk during coverage, including YAML, JSON, ERB templates, and any file accessed via `File.read`, read-mode `File.open`, `YAML.load_file`, `YAML.safe_load_file`, or `YAML.unsafe_load_file`.

The YAML methods are patched directly to handle Bootsnap's compile cache, which bypasses `File.open` for YAML files.

When a file is read indirectly (e.g., `YAML.load_file` calling through Psych), the tracker walks the caller stack to find the first in-root frame and creates a connected dependency.

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

### FixtureKitTracker

Tracks [fixture_kit](https://github.com/Gusto/fixture_kit) fixture definition files when fixtures are used. Requires fixture_kit >= 0.14.0.

Fixture definitions run once during cache generation (`before(:context)`), then every test replays cached SQL without executing Ruby. This tracker uses fixture_kit's callback hooks to:

1. Track files touched during fixture generation and create connected dependencies
2. Record fixture definition files (including parent chain) when tests mount fixtures

```ruby
coverage.use(FastCov::FixtureKitTracker)
```

## StaticMap

`FastCov::StaticMap` is a build-time API for static dependency mapping. It parses Ruby files with Prism, resolves literal constant references, and builds a dependency graph. Transitive closures are computed lazily on demand.

```ruby
static_map = FastCov::StaticMap.new(root: Rails.root)
static_map.build("spec/**/*_spec.rb")

# Direct dependencies for a single file
static_map.direct_dependencies("spec/models/user_spec.rb")
# => ["app/models/user.rb"]

# Transitive dependencies (computed and cached on first call)
static_map.dependencies("spec/models/user_spec.rb")
# => ["app/models/user.rb", "app/models/account.rb"]
```

The instance caches constant resolution results, so reusing the same instance across multiple `build` calls is efficient.

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `root` | String or Pathname | required | Absolute project root. Only resolved files under this path are included. |
| `ignored_paths` | String or Array | `[]` | Files or directories to exclude from the graph and recursive traversal. |
| `concurrency` | Integer | `Etc.nprocessors` | Number of threads for parallel file parsing. |

### How it works

- `build(*patterns)` traverses reachable files and stores a direct dependency graph
- `direct_dependencies(file)` returns direct dependencies for a file
- `dependencies(file)` computes and caches the transitive closure lazily
- Constant resolution results are cached and reused across `build` calls
- Resolves each reference from most-specific lexical candidate to least-specific
- Uses `const_defined?` and `const_source_location` to resolve literal constant references to source files

This is intended for a booted application process. It requires constants to be eager-loaded. It will not see dynamic constant lookups that are not expressed as literal constants in the source.

## TestMap

`FastCov::TestMap` handles test mapping serialization and aggregation. It accumulates mappings from test runs, writes gzipped fragment files, and merges fragments from multiple CI nodes.

### Accumulating mappings

```ruby
test_map = FastCov::TestMap.new

# Record which files each test depends on
test_map.add("spec/models/" => coverage_map.stop)

# Query: which tests cover this file?
test_map.dependencies("app/models/user.rb")
# => ["spec/models/"]

# Write gzipped fragment for later aggregation
test_map.dump("tmp/test_mapping.node_0.gz")
```

### Aggregating fragments

Merge fragments from multiple CI nodes via k-way merge:

```ruby
aggregator = FastCov::TestMap.aggregate(Dir["tmp/test_mapping.*.gz"])

# Hook into progress events
aggregator.on(:sort) { |fragments, batches| puts "#{fragments} fragments -> #{batches} batches" }
aggregator.on(:sorted) { |elapsed| puts "Sorted in #{elapsed.round(2)}s" }
aggregator.on(:merge) { |processed, total| print "#{processed}/#{total}\r" }
aggregator.on(:merged) { |files, elapsed| puts "Merged #{files} files in #{elapsed.round(2)}s" }

# Iterate in batches — yields Hash of { file => [deps] }
aggregator.each(10_000) do |batch|
  database.bulk_write(batch)
end
```

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `readers:` | Integer | `min(100, ulimit/2)` | Max concurrent readers for k-way merge. Auto-detected from OS file descriptor limit. |

### Fragment format

Tab-delimited, gzipped. One line per source file, first column is the file, remaining columns are dependencies:

```
source_file\tdep1\tdep2\tdep3
```

Aggregation owns sorting — fragments are unsorted, intermediates are sorted during the merge process using pure Ruby (no shell commands).

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
- caller stack traversal via `Utils.resolve_caller` for indirect calls

```ruby
class MyTracker < FastCov::AbstractTracker
  def install
    SomeClass.singleton_class.prepend(MyPatch)
  end

  module MyPatch
    def some_method(...)
      # record(path) auto-resolves the caller via stack traversal
      MyTracker.record(some_file_path)
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
