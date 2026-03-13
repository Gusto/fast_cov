# frozen_string_literal: true

module FastCov
  # Base class for trackers that record file paths during coverage.
  #
  # Provides common functionality:
  # - Path filtering (root, ignored_path)
  # - Thread-aware recording (global threads config)
  # - File collection and lifecycle management
  #
  # Descendants override hooks: on_start, on_stop, on_record
  # Or implement start, stop, record directly without inheriting.
  #
  # Threading behavior:
  # - threads: true  -> record from ALL threads (global tracking)
  # - threads: false -> only record from the thread that called start
  class AbstractTracker
    include ConfigurationHelper

    def initialize(**_options)
      @files = nil
      @started_thread = nil
    end

    # Public API - called by FastCov framework

    def start
      @files = Set.new
      @started_thread = Thread.current unless threads?
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

    def record(abs_path, owner: nil)
      return if !threads? && Thread.current != @started_thread
      path = normalize_path(abs_path)
      return unless trackable_path?(path)
      return unless on_record(path)

      @files.add(path)
      ConnectedDependencies.connect(owner: owner, dependency: path) if owner
    end

    def trackable_path?(path)
      include_path?(normalize_path(path))
    end

    # Hooks for descendants - override as needed

    def install; end
    def on_start; end
    def on_stop; end

    def on_record(abs_path)
      true
    end

    private

    def include_path?(abs_path)
      return false unless abs_path
      return false unless Utils.path_within?(abs_path, configuration.root)
      return false if configuration.ignored_path && Utils.path_within?(abs_path, configuration.ignored_path)

      true
    end

    def threads?
      configuration.threads
    end

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
      def record(abs_path = nil, owner: nil)
        return unless active

        path = abs_path || (yield if block_given?)
        active.record(path, owner: owner) if path
      end

      def reset
        @active = nil
      end
    end
  end
end
