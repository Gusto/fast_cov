# frozen_string_literal: true

require "fast_cov"

require_relative "support/file_helpers"
require_relative "support/shared_contexts"

require_relative "fixtures/app/model/my_model"
require_relative "fixtures/app/model/my_struct"
require_relative "fixtures/app/model/dynamic_model"
require_relative "fixtures/calculator/calculator"
require_relative "fixtures/calculator/operations/constant_reader"
require_relative "fixtures/calculator/operations/config_reader"
require_relative "fixtures/calculator/nested/nested_constant_reader"

RSpec.configure do |config|
  config.include FileHelpers

  config.before(:each) do
    FastCov::Cache.clear
    FastCov::FileTracker.reset
    FastCov.reset
  end
end
