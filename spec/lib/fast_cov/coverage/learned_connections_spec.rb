# frozen_string_literal: true

require_relative "../../../fixtures/const_get/service"
require_relative "../../../fixtures/const_get/resolver"

RSpec.describe "FastCov learned connections" do
  describe "FileTracker" do
    let(:root) { fixtures_path("calculator") }

    before do
      FastCov.configure do |config|
        config.root = root
        config.use FastCov::CoverageTracker
        config.use FastCov::FileTracker
      end

      ConfigReader.reset
    end

    it "reuses learned file dependencies when the read is memoized" do
      first_result = FastCov.start do
        ConfigReader.read_memoized_config
      end

      second_result = FastCov.start do
        ConfigReader.read_memoized_config
      end

      expect(first_result).to include("operations/config_reader.rb", "config.yml")
      expect(second_result).to include("operations/config_reader.rb", "config.yml")
    end
  end

  describe "ConstGetTracker" do
    let(:root) { fixtures_path("const_get") }

    before do
      FastCov.configure do |config|
        config.root = root
        config.use FastCov::CoverageTracker
        config.use FastCov::ConstGetTracker
      end

      ConstGetFixtures::Resolver.reset
    end

    it "reuses learned constant dependencies when const_get is memoized" do
      first_result = FastCov.start do
        ConstGetFixtures::Resolver.service_class
      end

      second_result = FastCov.start do
        ConstGetFixtures::Resolver.service_class
      end

      expect(first_result).to include("resolver.rb", "service.rb")
      expect(second_result).to include("resolver.rb", "service.rb")
    end
  end

  describe "stop-time expansion" do
    let(:tracker_class) do
      Class.new do
        def initialize(_config); end

        def start; end

        def stop
          Set.new(["/app/a.rb"])
        end
      end
    end

    before do
      FastCov::Cache.data[:connections] = {
        "/app/a.rb" => { "/app/b.rb" => true },
        "/app/b.rb" => { "/app/config/settings.yml" => true }
      }

      FastCov.configure do |config|
        config.root = "/app"
        config.use tracker_class
      end
    end

    it "expands learned connections transitively" do
      result = FastCov.start {}

      expect(result).to include("a.rb", "b.rb", "config/settings.yml")
    end
  end
end
