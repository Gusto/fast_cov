# frozen_string_literal: true

require "fast_cov/fast_cov.#{RUBY_VERSION}"

module FastCov
  autoload :VERSION,           "fast_cov/version"
  autoload :Configuration,      "fast_cov/configuration"
  autoload :Singleton,         "fast_cov/singleton"
  autoload :AbstractTracker,   "fast_cov/trackers/abstract_tracker"
  autoload :CoverageTracker,   "fast_cov/trackers/coverage_tracker"
  autoload :FileTracker,       "fast_cov/trackers/file_tracker"
  autoload :FactoryBotTracker, "fast_cov/trackers/factory_bot_tracker"
  autoload :ConstGetTracker,   "fast_cov/trackers/const_get_tracker"

  extend Singleton
end
