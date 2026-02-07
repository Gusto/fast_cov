# frozen_string_literal: true

module FastCov
  class Configuration
    attr_accessor :cache_path

    def initialize
      @cache_path = "tmp/cache/fast_cov"
    end

    def reset
      initialize
      self
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
