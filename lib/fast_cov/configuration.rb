# frozen_string_literal: true

require "pathname"

module FastCov
  class Configuration
    class ConfigurationError < StandardError; end

    attr_accessor :threads
    attr_reader :root, :ignored_path

    def initialize
      @root = Dir.pwd
      @ignored_path = nil
      @threads = true
      @tracker_definitions = []
    end

    def root=(value)
      return @root = nil if value.nil?

      path = value.to_s
      unless absolute_path?(path)
        raise ConfigurationError, "root must be an absolute path, got: #{path.inspect}"
      end
      @root = path
    end

    def ignored_path=(value)
      return @ignored_path = nil if value.nil?

      path = value.to_s

      # Expand relative paths against root
      unless absolute_path?(path)
        path = File.join(@root, path)
      end

      # Validate ignored_path is inside root
      unless path.start_with?(@root)
        raise ConfigurationError,
          "ignored_path must be inside root (#{@root.inspect}), got: #{path.inspect}"
      end

      @ignored_path = path
    end

    def use(tracker_class, **options)
      @tracker_definitions << {klass: tracker_class, options: options}
    end

    def install_trackers
      @tracker_definitions.map do |entry|
        tracker = entry[:klass].new(self, **entry[:options])
        tracker.install if tracker.respond_to?(:install)
        tracker
      end
    end

    def reset
      initialize
      self
    end

    private

    def absolute_path?(path)
      Pathname.new(path).absolute?
    end
  end
end
