# frozen_string_literal: true

require_relative "fast_cov/version"
require_relative "fast_cov/fast_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
require_relative "fast_cov/configuration"
require_relative "fast_cov/trackers/coverage_tracker"
require_relative "fast_cov/trackers/file_tracker"

module FastCov
  class << self
    def configured?
      !@trackers.nil? && !@trackers.empty?
    end

    def configure
      @configuration = Configuration.new
      yield(@configuration)
      install_trackers
      self
    end

    def start(&block)
      raise "FastCov.configure must be called before start" unless configured?
      @trackers.each(&:start)
      if block
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
      raise "FastCov.configure must be called before stop" unless configured?
      result = {}
      @trackers.reverse_each { |t| result.merge!(t.stop) }
      result
    end

    def reset
      @trackers = nil
      @configuration = nil
    end

    private

    def install_trackers
      @trackers = @configuration.trackers.map do |entry|
        tracker = entry[:klass].new(@configuration, **entry[:options])
        tracker.install if tracker.respond_to?(:install)
        tracker
      end
    end
  end
end
