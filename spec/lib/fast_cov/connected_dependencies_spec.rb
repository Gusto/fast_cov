# frozen_string_literal: true

RSpec.describe FastCov::ConnectedDependencies do
  describe ".connect" do
    before do
      FastCov.configure do |config|
        config.root = "/app"
        config.use FastCov::CoverageTracker
      end
    end

    it "stores connections in the cache" do
      described_class.connect(
        owner: "/app/services/config_reader.rb",
        dependency: "/app/config/settings.yml"
      )

      expect(FastCov::Cache.data[:connections]).to eq(
        "/app/services/config_reader.rb" => {
          "/app/config/settings.yml" => true
        }
      )
    end

    it "ignores owners outside the configured root" do
      described_class.connect(
        owner: "/other/config_reader.rb",
        dependency: "/app/config/settings.yml"
      )

      expect(FastCov::Cache.data[:connections]).to be_nil
    end

    it "ignores self-connections" do
      described_class.connect(
        owner: "/app/config/settings.yml",
        dependency: "/app/config/settings.yml"
      )

      expect(FastCov::Cache.data[:connections]).to be_nil
    end

    it "ignores owners inside the configured ignored_path" do
      FastCov.configure do |config|
        config.root = "/app"
        config.ignored_path = "/app/vendor"
        config.use FastCov::CoverageTracker
      end

      described_class.connect(
        owner: "/app/vendor/config_reader.rb",
        dependency: "/app/config/settings.yml"
      )

      expect(FastCov::Cache.data[:connections]).to be_nil
    end
  end

  describe ".expand" do
    before do
      FastCov::Cache.data[:connections] = {
        "/app/a.rb" => { "/app/b.rb" => true },
        "/app/b.rb" => { "/app/config/settings.yml" => true }
      }
    end

    it "expands connections transitively" do
      expanded = described_class.expand(Set.new(["/app/a.rb"]))

      expect(expanded).to eq(Set.new(["/app/b.rb", "/app/config/settings.yml"]))
    end

    it "returns an empty set when there are no connections" do
      FastCov::Cache.clear

      expect(described_class.expand(Set.new(["/app/a.rb"]))).to eq(Set.new)
    end
  end
end
