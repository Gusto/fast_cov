# frozen_string_literal: true

module FastCov
  # Wraps the FastCov::Coverage C extension as a tracker plugin.
  # Handles line coverage, allocation tracing, and constant resolution.
  #
  # Register via: config.use FastCov::CoverageTracker
  # Options: root, ignored_path, threads, constant_references, allocations
  class CoverageTracker
    def initialize(config, **options)
      @coverage = Coverage.new(
        root: options.fetch(:root, config.root),
        ignored_path: options.fetch(:ignored_path, config.ignored_path),
        threads: options.fetch(:threads, config.threads),
        constant_references: options.fetch(:constant_references, true),
        allocations: options.fetch(:allocations, true)
      )
    end

    def start
      @coverage.start
    end

    def stop
      Set.new(@coverage.stop.each_key)
    end
  end
end
