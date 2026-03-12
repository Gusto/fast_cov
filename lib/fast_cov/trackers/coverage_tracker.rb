# frozen_string_literal: true

module FastCov
  # Wraps the FastCov::Coverage C extension as a tracker plugin.
  # Handles line coverage and allocation tracing.
  #
  # Register via: config.use FastCov::CoverageTracker
  # Options: root, ignored_path, threads, allocations
  class CoverageTracker
    def initialize(config, **options)
      @coverage = Coverage.new(
        root: options.fetch(:root, config.root),
        ignored_path: options.fetch(:ignored_path, config.ignored_path),
        threads: options.fetch(:threads, config.threads),
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
