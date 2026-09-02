# frozen_string_literal: true

require "rbconfig"

# Tagged with the ABI version ("3.4.0"), not RUBY_VERSION ("3.4.9"). RubyGems
# keys installed extensions by ABI too, so it will not rebuild the gem when
# only the patch level changes -- tagging by patch level meant a Ruby upgrade
# inside the same ABI left this require looking for a file that was never
# built. Distinct ABIs still get distinct files, which is what matters for
# keeping multiple Ruby versions side by side in development.
require "fast_cov/fast_cov.#{RbConfig::CONFIG["ruby_version"]}"

module FastCov
  autoload :Utils, File.expand_path("fast_cov/utils", __dir__)
  autoload :VERSION, File.expand_path("fast_cov/version", __dir__)
  autoload :ConnectedDependencies, File.expand_path("fast_cov/connected_dependencies", __dir__)
  autoload :CoverageMap, File.expand_path("fast_cov/coverage_map", __dir__)
  autoload :AbstractTracker, File.expand_path("fast_cov/trackers/abstract_tracker", __dir__)
  autoload :FileTracker, File.expand_path("fast_cov/trackers/file_tracker", __dir__)
  autoload :FactoryBotTracker, File.expand_path("fast_cov/trackers/factory_bot_tracker", __dir__)
  autoload :ConstGetTracker, File.expand_path("fast_cov/trackers/const_get_tracker", __dir__)
  autoload :FixtureKitTracker, File.expand_path("fast_cov/trackers/fixture_kit_tracker", __dir__)
  autoload :StaticMap, File.expand_path("fast_cov/static_map", __dir__)
  autoload :TestMap, File.expand_path("fast_cov/test_map", __dir__)
end
