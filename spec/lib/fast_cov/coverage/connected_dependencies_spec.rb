# frozen_string_literal: true

RSpec.describe "FastCov connected dependencies" do
  describe "memoized file reads" do
    let(:coverage_map) do
      FastCov::CoverageMap.new.tap do |coverage|
        coverage.root = fixtures_path("calculator")
        coverage.use(FastCov::FileTracker)
      end
    end

    before do
      ConfigReader.reset!
    end

    it "reuses learned file dependencies across runs" do
      first_result = coverage_map.start do
        ConfigReader.memoized_config
      end

      second_result = coverage_map.start do
        ConfigReader.memoized_config
      end

      expect(first_result).to include("config.yml", "operations/config_reader.rb")
      expect(second_result).to include("config.yml", "operations/config_reader.rb")
    end
  end

  describe "memoized const_get lookups" do
    let(:coverage_map) do
      FastCov::CoverageMap.new.tap do |coverage|
        coverage.root = fixtures_path("const_get")
        coverage.use(FastCov::ConstGetTracker)
      end
    end

    before do
      require_relative "../../../fixtures/const_get/service"
      require_relative "../../../fixtures/const_get/resolver"
    end

    it "reuses learned const dependencies across runs" do
      resolver = ConstGetFixtures::Resolver.new

      first_result = coverage_map.start do
        resolver.resolve(:Service)
      end

      second_result = coverage_map.start do
        resolver.resolve(:Service)
      end

      expect(first_result).to include("resolver.rb", "service.rb")
      expect(second_result).to include("resolver.rb", "service.rb")
    end
  end
end
