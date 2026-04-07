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

    def root
      @coverage_map.root
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

    def record(abs_path, to: nil)
      return if !@coverage_map.threads && Thread.current != @started_thread

      path = normalize_path(abs_path)
      return unless @coverage_map.include_path?(path)

      @coverage_map.connect(from: to, to: path) if to
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

      def record(path, to: nil)
        return unless active
        return unless path

        to ||= Utils.resolve_caller(caller_locations(1, 20), active.root)
        active.record(path, to: to)
      end

      def reset
        @active = nil
      end
    end
  end
end
