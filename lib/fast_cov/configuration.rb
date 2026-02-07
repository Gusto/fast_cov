# frozen_string_literal: true

module FastCov
  class Configuration
    def initialize
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
