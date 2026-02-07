# frozen_string_literal: true

require_relative "fast_cov/version"
require_relative "fast_cov/fast_cov"
require_relative "fast_cov/configuration"
require_relative "fast_cov/cache"

module FastCov
end

FastCov::Cache.setup_autosave
