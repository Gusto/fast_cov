# frozen_string_literal: true

require "fast_cov/fast_cov.#{RUBY_VERSION}"

module FastCov
  autoload :VERSION, File.expand_path("fast_cov/version", __dir__)
  autoload :Configuration, File.expand_path("fast_cov/configuration", __dir__)
  autoload :Singleton, File.expand_path("fast_cov/singleton", __dir__)
  autoload :AbstractTracker, File.expand_path("fast_cov/trackers/abstract_tracker", __dir__)
  autoload :CoverageTracker, File.expand_path("fast_cov/trackers/coverage_tracker", __dir__)
  autoload :FileTracker, File.expand_path("fast_cov/trackers/file_tracker", __dir__)
  autoload :FactoryBotTracker, File.expand_path("fast_cov/trackers/factory_bot_tracker", __dir__)
  autoload :ConstGetTracker, File.expand_path("fast_cov/trackers/const_get_tracker", __dir__)

  extend Singleton
end
