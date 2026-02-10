# frozen_string_literal: true

module FastCov
  class Configuration
    attr_accessor :threads
    attr_reader :root, :ignored_path

    def initialize
      @root = Dir.pwd
      @ignored_path = nil
      @threads = true
      @trackers = []
    end

    def root=(value)
      @root = value&.to_s
    end

    def ignored_path=(value)
      @ignored_path = value&.to_s
    end

    def use(tracker_class, **options)
      @trackers << {klass: tracker_class, options: options}
    end

    def trackers
      @trackers
    end

    def reset
      initialize
      self
    end
  end
end
