# frozen_string_literal: true

require "pathname"
require "set"

module FastCov
  class CoverageMap
    class ConfigurationError < StandardError; end

    attr_accessor :threads
    attr_reader :ignored_paths
    attr_reader :root

    def initialize
      @root = Dir.pwd
      @threads = true
      @ignored_paths = []
      @trackers = []
      @native_coverage = nil
      @started = false
    end

    def root=(value)
      return @root = nil if value.nil?

      path = value.to_s
      unless absolute_path?(path)
        raise ConfigurationError, "root must be an absolute path, got: #{path.inspect}"
      end

      @root = path
    end

    def ignored_paths=(value)
      @ignored_paths =
        case value
        when nil
          []
        when Array
          value.dup
        else
          [value]
        end
    end

    def use(tracker_class, **options)
      raise "CoverageMap is already started" if @started
      raise ArgumentError, "#{tracker_class} is already registered" if @trackers.any? { |tracker| tracker.is_a?(tracker_class) }

      tracker = tracker_class.new(self, **options)
      tracker.install if tracker.respond_to?(:install)
      @trackers << tracker
      self
    end

    def start
      if @started
        raise "CoverageMap is already started" if block_given?
        return self
      end

      begin
        @native_coverage = Coverage.new(
          root: normalized_root,
          ignored_paths: normalized_ignored_paths,
          threads: @threads != false
        )
        @native_coverage.start
        @trackers.each(&:start)
        @started = true
      rescue StandardError
        cleanup_failed_start
        raise
      end

      if block_given?
        result = nil
        begin
          yield
        ensure
          result = stop
        end
        result
      else
        self
      end
    end

    def stop
      return Set.new unless @started

      result = Set.new(@native_coverage.stop.each_key)
      @trackers.reverse_each { |tracker| result.merge(tracker.stop) }
      Utils.relativize_paths(result, normalized_root)
    ensure
      @native_coverage = nil
      @started = false
    end

    def include_path?(path)
      return false unless path
      return false unless Utils.path_within?(path, normalized_root)
      return true if @ignored_paths.empty?

      normalized_ignored_paths.none? { |ignored_path| Utils.path_within?(path, ignored_path) }
    end

    private

    def normalized_root
      path = @root&.to_s
      raise ConfigurationError, "root is required" if path.nil? || path.empty?
      raise ConfigurationError, "root must be an absolute path, got: #{path.inspect}" unless absolute_path?(path)

      path
    end

    def normalized_ignored_paths
      root = normalized_root

      @ignored_paths.map do |value|
        path = value.to_s
        path = File.join(root, path) unless absolute_path?(path)

        unless Utils.path_within?(path, root)
          raise ConfigurationError,
            "ignored_paths must be inside root (#{root.inspect}), got: #{path.inspect}"
        end

        path
      end
    end

    def absolute_path?(path)
      Pathname.new(path).absolute?
    end

    def cleanup_failed_start
      @trackers.reverse_each do |tracker|
        begin
          tracker.stop
        rescue StandardError
          nil
        end
      end

      begin
        @native_coverage&.stop
      rescue StandardError
        nil
      end

      @native_coverage = nil
      @started = false
    end
  end
end
