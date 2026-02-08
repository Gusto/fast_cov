# frozen_string_literal: true

module FastCov
  class Configuration
    attr_accessor :root, :ignored_path, :threading_mode, :allocation_tracing

    def initialize
      @root = Dir.pwd
      @ignored_path = nil
      @threading_mode = :multi
      @allocation_tracing = true
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
