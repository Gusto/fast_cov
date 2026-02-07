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

## Project structure

```
ext/fast_cov/
  fast_cov.c          # Core C extension (~610 lines). All the performance-critical code.
  fast_cov_utils.c    # Shared C utilities: path filtering, string helpers, const resolution.
  fast_cov.h          # Header shared between the two C files.
  extconf.rb          # Build config (mkmf). Generates Makefile for compilation.

lib/fast_cov/
  fast_cov.rb         # Entry point. Loads C extension + Ruby modules.
  version.rb          # VERSION constant.
  configuration.rb    # FastCov.configure block API. Currently a stub for future options.
  cache.rb            # FastCov::Cache module. C defines .data, .data=, .clear.
  benchmark/
    runner.rb          # Benchmark harness: measurement, baseline comparison, reporting.
    scenarios.rb       # The 7 benchmark scenario definitions.

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

The C extension defines `FastCov::Coverage` (a Ruby class) and `FastCov::Cache` (a Ruby module). Everything performance-sensitive lives in C.

### Three coverage mechanisms

**1. Line coverage** — The core feature. Hooks `RUBY_EVENT_LINE` which fires every time the Ruby VM executes a new line. The callback (`on_line_event`) records the source file path. It uses a pointer-caching optimization: `rb_sourcefile()` returns a `const char*` whose address doesn't change for the same file, so we compare pointers (a single integer comparison) instead of strings to skip files we've already seen.

**2. Allocation tracing** — Optional. Hooks `RUBY_INTERNAL_EVENT_NEWOBJ` which fires on every object allocation. We only care about `T_OBJECT` and `T_STRUCT` types (regular classes and structs). During `stop`, we iterate every class that was instantiated, walk its full ancestor chain (`rb_mod_ancestors`), and resolve each ancestor to its source file via `Object.const_source_location`. This catches classes that have no executable methods (empty models, structs, Data objects).

**3. Constant reference resolution** — Runs at `stop` time. For each file already in the coverage results, we compile its bytecode (`RubyVM::InstructionSequence.compile_file`), walk the instruction array looking for `opt_getconstant_path` instructions (Ruby's bytecode for constant access like `Foo::BAR`), and resolve each referenced constant to its defining file. This is transitive — if file A references a constant in file B, and file B references a constant in file C, all three end up in the results. Runs up to 10 rounds until no new files are discovered.

### In-memory cache

Constant resolution is the expensive part (compiling iseqs). Results are cached in a process-level Ruby Hash (`fast_cov_cache_hash`), keyed by file path with MD5 content digests for invalidation. The cache is shared across all `FastCov::Coverage` instances. `FastCov::Cache.clear` resets it. The cache lives only in memory (no disk persistence currently).

### GC integration

The C struct uses Ruby's TypedData API with proper `mark`, `free`, and `compact` callbacks. `rb_gc_mark_movable` is used for all VALUE fields so the GC can relocate them during compaction. The `klasses_table` (an `st_table`) stores raw VALUE pointers as keys, which are marked as non-movable during GC via `rb_gc_mark`.

## Benchmark scenarios

The 7 benchmarks in `lib/fast_cov/benchmark/scenarios.rb` measure distinct aspects of the system. When adding new features or optimizing, run `bin/benchmark` before and after to check for regressions.

| Scenario | What it measures |
|---|---|
| Line coverage (small) | Overhead of start/stop + tracking a few files via line events |
| Line coverage (many files) | Same but exercising all fixture files (calculator, models, structs, dynamic dispatch) |
| Allocation tracing | Overhead of NEWOBJ hooks + ancestor chain resolution at stop time |
| Constant resolution (cold cache) | Full iseq compile + scan cost when cache is empty |
| Constant resolution (warm cache) | Cache hit path — just MD5 digest comparison, no compilation |
| Rapid start/stop (100x) | Hook install/remove overhead across many cycles |
| Multi-threaded coverage | Thread creation + global hook overhead |

The runner takes 7 samples per scenario and reports the **median** to filter outliers. GC is run between samples. Default is 1000 iterations per sample.

## Testing conventions

- Tests are integration-level, organized by feature under `spec/lib/fast_cov/coverage/`.
- Shared context `"coverage instance"` (in `spec/support/shared_contexts.rb`) provides a standard `subject` with configurable `root`, `ignored_path`, `threading_mode`, and `use_allocation_tracing`.
- `fixtures_path(*segments)` helper builds absolute paths to `spec/fixtures/`.
- `FastCov::Cache.clear` runs before every test for isolation.
- Always use `--fail-fast` when running specs.

## Key design decisions

- **C over Ruby for the hot path.** Line event callbacks fire on every line of Ruby execution. Even small overhead per call multiplies across millions of events. The C extension avoids Ruby method dispatch, object allocation, and GC pressure in the callback.
- **Pointer caching for filename dedup.** `rb_sourcefile()` returns the same pointer for the same file. Comparing a pointer (one CPU instruction) is much faster than comparing strings.
- **Post-processing at stop time.** Constant resolution and allocation tracing processing happen in `stop`, not during execution. This keeps the hot path (line events) as lean as possible.
- **Process-level cache.** The iseq compilation cache is static/global, shared across all Coverage instances. In a test suite, the same source files are analyzed repeatedly — the cache means each file is compiled once.
- **No disk cache (for now).** The in-memory cache is sufficient for single test suite runs. Disk persistence was built and removed — it can be added back when needed.
- **Ruby 3.4+ only.** No version-conditional code. `GC.compact`, `Data.define`, `each_child` on iseq are all available unconditionally.
