# frozen_string_literal: true

require "pathname"

RSpec.describe FastCov::Configuration do
  it "yields the configuration via configure block" do
    FastCov.configure do |config|
      expect(config).to be_a(FastCov::Configuration)
      config.use FastCov::CoverageTracker
    end
  end

  it "registers trackers via use" do
    expect(FastCov.configured?).to be false
    FastCov.configure do |c|
      c.root = Dir.pwd
      c.use FastCov::CoverageTracker
    end
    expect(FastCov.configured?).to be true
  end

  describe "#root=" do
    subject(:config) { described_class.new }

    it "accepts an absolute path String" do
      config.root = "/app"
      expect(config.root).to eq("/app")
    end

    it "converts Pathname to String" do
      config.root = Pathname.new("/app")
      expect(config.root).to eq("/app")
      expect(config.root).to be_a(String)
    end

    it "handles nil" do
      config.root = nil
      expect(config.root).to be_nil
    end

    it "raises on relative path" do
      expect { config.root = "app" }.to raise_error(
        FastCov::Configuration::ConfigurationError,
        /root must be an absolute path/
      )
    end
  end

  describe "#ignored_path=" do
    subject(:config) { described_class.new }

    before { config.root = "/app" }

    it "accepts an absolute path inside root" do
      config.ignored_path = "/app/vendor"
      expect(config.ignored_path).to eq("/app/vendor")
    end

    it "converts Pathname to String" do
      config.ignored_path = Pathname.new("/app/vendor")
      expect(config.ignored_path).to eq("/app/vendor")
      expect(config.ignored_path).to be_a(String)
    end

    it "handles nil" do
      config.ignored_path = nil
      expect(config.ignored_path).to be_nil
    end

    it "expands relative paths against root" do
      config.ignored_path = "vendor"
      expect(config.ignored_path).to eq("/app/vendor")
    end

    it "expands nested relative paths against root" do
      config.ignored_path = "vendor/bundle"
      expect(config.ignored_path).to eq("/app/vendor/bundle")
    end

    it "raises when absolute path is outside root" do
      expect { config.ignored_path = "/other/path" }.to raise_error(
        FastCov::Configuration::ConfigurationError,
        /ignored_path must be inside root/
      )
    end
  end
end
