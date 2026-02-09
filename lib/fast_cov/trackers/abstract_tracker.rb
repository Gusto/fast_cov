# frozen_string_literal: true

module FastCov
  # Base class for trackers that record file paths during coverage.
  #
  # Provides common functionality:
  # - Path filtering (root, ignored_path)
  # - Thread-aware recording (threads option)
  # - File collection and lifecycle management
  #
  # Descendants override hooks: on_start, on_stop, on_record
  # Or implement start, stop, record directly without inheriting.
  #
  # Threading behavior:
  # - threads: true  -> record from ALL threads (global tracking)
  # - threads: false -> only record from the thread that called start
  class AbstractTracker
    def initialize(config, **options)
      @root = options.fetch(:root, config.root)
      @ignored_path = options.fetch(:ignored_path, config.ignored_path)
      @threads = options.fetch(:threads, config.threads)
      @files = nil
      @started_thread = nil
    end

    # Public API - called by FastCov framework

    def start
      @files = {}
      @started_thread = Thread.current unless @threads
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
      return if !@threads && Thread.current != @started_thread
      return unless abs_path.start_with?(@root)
      return if @ignored_path && abs_path.start_with?(@ignored_path)
      @files[abs_path] = true if on_record(abs_path)
    end

    # Hooks for descendants - override as needed

    def install; end
    def on_start; end
    def on_stop; end

    def on_record(abs_path)
      true
    end

    class << self
      attr_accessor :active

      def record(abs_path)
        @active&.record(abs_path)
      end

      def reset
        @active = nil
      end
    end
  end
end
