# frozen_string_literal: true

module FastCov
  # Base class for trackers that record file paths during coverage.
  #
  # Provides common functionality:
  # - Path filtering (root, ignored_paths)
  # - Thread-aware recording (CoverageMap#threads)
  # - File collection and lifecycle management
  #
  # Descendants override hooks: on_start, on_stop, on_record
  # Or implement start, stop, record directly without inheriting.
  #
  # Threading behavior:
  # - threads: true  -> record from ALL threads (global tracking)
  # - threads: false -> only record from the thread that called start
  class AbstractTracker
    def initialize(coverage_map, **_options)
      @coverage_map = coverage_map
      @files = nil
      @started_thread = nil
    end

    # Public API - called by FastCov framework

    def start
      @files = Set.new
      @started_thread = Thread.current unless @coverage_map.threads
      self.class.active = self
      on_start
    end

    def stop
      self.class.active = nil
      @started_thread = nil
      on_stop
      result = @files
      @files = nil
      result
    end

    def record(abs_path)
      return if !@coverage_map.threads && Thread.current != @started_thread

      path = normalize_path(abs_path)
      return unless @coverage_map.include_path?(path)

      @files.add(path) if on_record(path)
    end

    # Hooks for descendants - override as needed

    def install; end
    def on_start; end
    def on_stop; end

    def on_record(path)
      true
    end

    private

    def normalize_path(path)
      return if path.nil?

      File.expand_path(path.to_s)
    end

    class << self
      attr_accessor :active

      # Record a file path. Accepts a path directly or a block that returns the path.
      # If block given, it's only executed when tracker is active (avoids expensive work).
      # Nil values are ignored.
      #
      #   record("/path/to/file.rb")           # direct path
      #   record { expensive_lookup }          # lazy evaluation
      #   record("/path") { fallback }         # path takes precedence
      #
      def record(abs_path = nil)
        return unless active

        path = abs_path || (yield if block_given?)
        active.record(path) if path
      end

      def reset
        @active = nil
      end
    end
  end
end
