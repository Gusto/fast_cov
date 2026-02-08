# frozen_string_literal: true

module FastCov
  class Configuration
    attr_accessor :root, :ignored_path, :threads

    def initialize
      @root = Dir.pwd
      @ignored_path = nil
      @threads = true
      @trackers = []
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
