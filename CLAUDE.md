# FastCov Development Guide

## What is this project?

FastCov is a Ruby gem with a native C extension that tracks which source files are executed during test runs. It's built for test impact analysis — figuring out which tests need to re-run when code changes. It hooks directly into the Ruby VM's event system rather than using Ruby's built-in `Coverage` module, which makes it significantly faster.

## Quick reference

```sh
bundle exec rake compile   # compile the C extension (required before tests)
bundle exec rake spec      # compile + run tests (--fail-fast)
bin/rspec                  # run tests via binstub
bin/benchmark              # run performance benchmarks
bin/benchmark --baseline   # save benchmark results as baseline for comparison
ITERATIONS=5000 bin/benchmark  # override iteration count
```

**Testing locally:** Always test in both Ruby 4.0 and Ruby 3.4.

**Before starting new changes:** Ask the user if they want to save a baseline benchmark first (`bin/benchmark --baseline`). This allows comparing performance before and after the changes.

## Project structure

```
ext/fast_cov/
  fast_cov.c          # Core C extension (~440 lines). All the performance-critical code.
  fast_cov_utils.c    # Shared C utilities: path filtering, string helpers.
  fast_cov.h          # Header shared between the two C files.
  extconf.rb          # Build config (mkmf). Generates Makefile for compilation.

lib/
  fast_cov.rb         # Entry point. Loads C extension, autoloads Ruby modules.

lib/fast_cov/
  version.rb          # VERSION constant.
  coverage_map.rb     # CoverageMap — the primary API. Orchestrates C extension + trackers.
  connected_dependencies.rb # Learned file-to-file edges, expanded at stop time.
  utils.rb            # Ruby path helpers: path_within?, relativize_paths, resolve_caller.
  compiler.rb         # Compiles the extension on demand (used by dev.rb).
  dev.rb              # Auto-compile entrypoint for `path:` Gemfile references.
  static_map.rb       # StaticMap — build-time dependency graph via Prism.
  test_map.rb         # TestMap — mapping serialization + k-way merge aggregation.
  trackers/
    abstract_tracker.rb    # Base class for the Ruby trackers.
    file_tracker.rb        # Tracks File.read/File.open and YAML load_file calls.
    factory_bot_tracker.rb # Tracks FactoryBot factory definition files.
    const_get_tracker.rb   # Tracks constants resolved via Module#const_get.
    fixture_kit_tracker.rb # Tracks fixture_kit fixture definition files.
  benchmark/
    runner.rb          # Benchmark harness: measurement, baseline comparison, reporting.
    scenarios.rb       # The benchmark scenario definitions.

spec/
  lib/fast_cov/coverage/   # Integration tests organized by feature.
  fixtures/                 # Calculator, app models, vendor — test fixture code.
  support/                  # Shared contexts, file helpers.

bin/
  benchmark    # Run benchmarks, compare against baseline.
  console      # IRB with FastCov loaded.
  rspec        # RSpec binstub.
```

## How the C extension works

The C extension defines a single Ruby class, `FastCov::Coverage`. Everything performance-sensitive lives in C. `CoverageMap` wraps it on the Ruby side and merges in the tracker results.

### Line coverage

The core feature. Hooks `RUBY_EVENT_LINE` which fires every time the Ruby VM executes a new line. The callback (`on_line_event`) records the source file path. It uses a pointer-caching optimization: `rb_sourcefile()` returns a `const char*` whose address doesn't change for the same file, so we compare pointers (a single integer comparison) instead of strings to skip files we've already seen.

The cache has two levels, because execution alternates between files constantly (a method in one file calling into another) and a single-slot cache misses on every transition:

1. `last_filename_ptr` — one slot, hits while execution stays in one file.
2. The seen-set (`seen_ptrs`/`seen_paths`) — an open-addressed set of every file pointer seen this session. Starts at 256 entries and doubles at 3/4 load. A hit here returns without calling into the VM at all.

Only pointers we hold the path string for get cached, and those strings are pinned in `fast_cov_mark`. That pin is load-bearing: it keeps each pointer alive and at a fixed address for the session. Without it, a freed string's address could be reused by another file, which would read as a cache hit and silently drop that file from the results.

### GC integration

The C struct uses Ruby's TypedData API with proper `mark` and `free` callbacks. `rb_gc_mark` (non-movable, pins objects) is used for all VALUE fields — on Ruby 3.4+, `rb_gc_mark_movable` with compaction causes crashes, so we pin objects instead.

**Important for C code:** anything holding a raw `const char*` from a Ruby string must keep that string reachable and pinned, or re-read the pointer immediately before use with no intervening Ruby calls. `xmalloc`/`xcalloc` can trigger GC, so never leave the struct in a state `fast_cov_mark` cannot safely walk across an allocation.

### Utils module

`FastCov::Utils` is plain Ruby (it used to be C):

- `path_within?(path, directory)` — Returns true if `path` is within `directory`. Correctly handles trailing slashes and sibling directories with longer names (e.g., `/a/b/c` does NOT match `/a/b/cd`).
- `relativize_paths(set, root)` — Mutates the Set in place, converting absolute paths to paths relative to `root`. Called by `CoverageMap#stop`.
- `resolve_caller(locations, root)` — First caller frame inside `root`, for attributing indirect reads.

## Benchmark scenarios

The benchmarks in `lib/fast_cov/benchmark/scenarios.rb` measure distinct aspects of the system. When adding new features or optimizing, run `bin/benchmark` before and after to check for regressions.

| Scenario | What it measures |
|---|---|
| Line coverage (small) | Overhead of start/stop + tracking a few files via line events |
| Line coverage (many files) | Same but exercising all fixture files (calculator, models, structs, dynamic dispatch) |
| Line coverage (single-threaded) | Per-thread hook mode (`threads: false`) vs global hook |
| Line coverage (with ignored_path) | Overhead of ignored_path filtering in the hot path |
| Line coverage (cross-file transitions) | Per-line-event cost when execution bounces between files (exercises the seen-set) |
| Rapid start/stop (100x) | Hook install/remove overhead across many cycles |
| Multi-threaded coverage | Thread creation + global hook overhead |

The runner takes 5 samples per scenario and reports the **median** to filter outliers. GC is run between samples. Default is 1000 iterations per sample.

## Testing conventions

- Tests are integration-level, organized by feature under `spec/lib/fast_cov/coverage/`.
- Shared context `"coverage instance"` (in `spec/support/shared_contexts.rb`) provides a standard `subject` with configurable `root` and `ignored_paths`.
- `fixtures_path(*segments)` helper builds absolute paths to `spec/fixtures/`.
- The trackers are reset before every test (`spec/spec_helper.rb`) for isolation.
- Always use `--fail-fast` when running specs.

## Key design decisions

- **C over Ruby for the hot path.** Line event callbacks fire on every line of Ruby execution. Even small overhead per call multiplies across millions of events. The C extension avoids Ruby method dispatch, object allocation, and GC pressure in the callback.
- **Pointer caching for filename dedup.** `rb_sourcefile()` returns the same pointer for the same file. Comparing a pointer (one CPU instruction) is much faster than comparing strings.
- **Trackers check `active` before doing work.** The monkey patches stay installed for the life of the process, so anything expensive (`const_source_location`, `File.expand_path`) must sit behind the active check rather than being computed and discarded.
- **The native Coverage instance is reused across start/stop cycles.** It rebuilds its caches on construction, and callers run one cycle per test.
- **ABI-version-tagged extension.** The compiled file is tagged with `RbConfig::CONFIG["ruby_version"]`, matching how RubyGems keys installed extensions. Tagging by `RUBY_VERSION` broke on patch upgrades.
- **Gemspec allows Ruby >= 3.2**, but CI covers 3.4 and 4.0 — those are the versions to test against.

## Releasing

- **Always ask before releasing a new version.** Do not bump version or create releases without explicit user approval.
- **Release names should be `vX.Y.Z`** — no extra words or descriptions in the release title.
