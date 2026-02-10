# frozen_string_literal: true

module FastCov
  module Singleton
    def configured?
      !@trackers.nil? && !@trackers.empty?
    end

    def configure
      @configuration = Configuration.new
      yield(@configuration)
      @trackers = @configuration.install_trackers
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
      result = Set.new
      @trackers.each { |t| result.merge(t.stop) }
      Utils.relativize_paths(result, @configuration.root)
    end

    def reset
      @trackers = nil
      @configuration = nil
    end
  end
end
